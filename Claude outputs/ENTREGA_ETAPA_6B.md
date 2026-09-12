# ENTREGA — Etapa 6B: Correção definitiva da orientação + docks de embarque

Escopo respeitado integralmente: só `scripts/game/vehicle_controller.gd` e `scripts/game/game_controller.gd` foram tocados, só dentro dos trechos exclusivos da PolishTest (`is_polish_test` / fase 950). Nenhuma refatoração estrutural foi feita (nenhum nó mudou de lugar na hierarquia, nenhuma função existente foi removida) — a mudança é um "hard override" determinístico aplicado no mesmo ponto onde o snap de posição já existia.

## 1) Causa técnica do yaw incorreto

Reli com cuidado todo o pipeline de rotação (`drive_route_polished` → `_drive_final_approach_polished`) e confirmei matematicamente que a fórmula antiga de heading (`atan2` sobre `slot_center - start_position`) já era, por construção, determinística: `_build_route_to_waiting_slot` sempre alinha o `ApproachPoint` na mesma coluna X do slot antes do trecho final, então o ângulo calculado dava 180° pra qualquer um dos 4 slots. Ou seja, não existia mais um bug isolado e reproduzível nessa fórmula em si — o risco real era estrutural: a orientação final continuava sendo uma **conta derivada de posição/tangente**, sujeita a qualquer variação futura de rota, tween interrompido, ou reentrada de código, sem nenhuma fonte única e auditável. Não tenho como reproduzir ao vivo o exato instante do vídeo em que o veículo azul ficou transversal (não consigo rodar o Godot neste ambiente — ver nota na seção 4), então em vez de caçar um "culpado" histórico impossível de confirmar sem repro, implementei exatamente o que o ticket pede: eliminar a categoria inteira de bug, tornando a orientação uma leitura direta de uma fonte fixa.

## 2) Fonte única do yaw estacionado

**O `rotation_degrees.y` do próprio Marker3D do slot.** Cada um dos 4 slots ativos (`Slot0`..`Slot3`) agora recebe explicitamente `marker.rotation_degrees.y = POLISH_PARKED_YAW_DEGREES` (constante única, `180.0`) na criação, em `_setup_boarding_area_polish()`. Como os 4 slots compartilham a mesma constante, todos os veículos estacionados terminam paralelos entre si — exatamente como pedido.

O fluxo agora é:
- `GameController._process_vehicle_tap()` busca o `Marker3D` do slot **antes** de iniciar a animação (`final_marker = _boarding_slot_marker(slot_index)`) e lê `slot_yaw_degrees = final_marker.global_rotation_degrees.y`.
- Esse valor é passado para `vehicle_node.drive_route_polished(route, slot_yaw_degrees)`, que repassa para `_drive_final_approach_polished(slot_center, slot_yaw_degrees)`.
- Dentro de `_drive_final_approach_polished`, o antigo cálculo `entry_direction = slot_center - start_position` / `atan2(...)` foi **removido por completo**. O yaw final agora é `target_yaw_degrees = slot_yaw_degrees + calibration` (a `calibration` é só o ajuste legítimo de autoria do modelo GLB por tipo de veículo, ex. ônibus = +90°, nunca uma direção calculada).
- Depois que `drive_route_polished` retorna, `GameController` já faz o snap de posição (`vehicle_node.global_position = final_marker.global_position`) e **imediatamente em seguida** chama `vehicle_node.snap_polish_parked_orientation(slot_yaw_degrees)` — a palavra final e explícita sobre a rotação, lida da mesma fonte.

Nenhuma fonte proibida pelo ticket (última tangente da Curve3D, direção anterior do veículo, `exit_direction`, rotação residual) é usada em nenhum ponto desse caminho.

## 3) ROOT vs VISUAL e neutralização de tweens residuais

Sem alterar a hierarquia de nós (nada de refatoração), a separação lógica pedida foi implementada por comportamento:

- **ROOT lógico** (`_model_node`, ou `_visual_pivot` como fallback quando não há modelo — é o nó que carrega `rotation_degrees.y`): recebe o yaw final determinístico do slot, sempre.
- **VISUAL** (`_visual_pivot`): `snap_polish_parked_orientation()` zera explicitamente `rotation_degrees.z` (roll) **e** `rotation_degrees.x` (pitch residual) — item 2 do ticket ("VISUAL: roll = 0, pitch residual = 0"). `_polish_roll_degrees` também é zerado.
- **Ordem de execução** (item 3, respeitada à risca): SNAP POSIÇÃO (`GameController`) → SNAP YAW + ZERO LEAN (`snap_polish_parked_orientation`) → só then o bounce (`_arrival_bounce_polished`, que só mexe em `position:y` e `scale` do `_visual_pivot` — nunca em rotação, então não pode reintroduzir lean depois do snap).
- **Tweens matados antes do snap final**: `snap_polish_parked_orientation()` guarda uma referência (`_polish_route_tween`) para qualquer tween de movimento/aproximação em andamento (`drive_route_polished`'s `move_tween` e `_drive_final_approach_polished`'s `tween`) e chama `.kill()` nele se ainda estiver vivo, além de matar também `_polish_feedback_tween` (usado pelos feedbacks de toque válido/bloqueado, que mexem em `position`/`scale`). Isso cobre defensivamente qualquer tween que ainda pudesse escrever uma transformação por cima do snap final, mesmo que na prática eles já devessem ter terminado.
- **Assert temporário (item 4)**: logo após o snap, `snap_polish_parked_orientation()` compara o yaw lógico do veículo (yaw atual menos a calibração do modelo) contra `slot_yaw_degrees`; se a diferença passar de `POLISH_YAW_MATCH_TOLERANCE_DEGREES = 1.0`, dispara `push_error("[PolishRotation] DIVERGENCIA vehicle_id=... type_id=... slot=... vehicle_yaw=... slot_yaw=... diff=...")`. É só um log/assert (não corrige nada), exatamente como pedido, e só roda na PolishTest.

## 4) Resultado do teste de 8 veículos (item 10) — preciso da sua ajuda aqui

Preciso ser honesto sobre um limite real deste ambiente: o dispositivo que uso para editar os arquivos do seu projeto (via a ponte de arquivos) é uma VM Linux isolada, sem o executável do Godot instalado — não tenho como abrir, rodar ou testar visualmente o jogo a partir daqui, em nenhuma hipótese. Então **não posso afirmar que rodei o teste de estacionar 8 veículos** — seria desonesto simular esse resultado.

O que fiz para compensar isso o máximo possível sem rodar o jogo:
- Tracei manualmente o novo caminho de código (posição do slot → yaw do slot → `drive_route_polished` → `_drive_final_approach_polished` → `snap_polish_parked_orientation`) confirmando que, para qualquer `type_id` (`small_car`, `medium_car`, `bus`) e qualquer um dos 4 slots, o yaw final é sempre `slot_yaw_degrees + calibration_do_tipo`, nunca dependente de posição/rota — ou seja, a divergência entre veículos do mesmo tipo é matematicamente zero por construção, e o `push_error` de diagnóstico já fica pronto para pegar qualquer regressão futura.
- Rodei a suíte de verificação estática de sempre nos dois arquivos alterados (balanceamento de `()`/`[]`/`{}` ignorando strings/comentários, indentação só-com-tabs, nomes de função duplicados) — os dois passaram limpos.

**Pedido**: por favor rode você mesmo a fase 950 e estacione pelo menos 8 veículos (reaproveitando vagas), incluindo ao menos um `small_car`, um `medium_car` e um `bus`, e me diga: (a) se algum `push_error("[PolishRotation] DIVERGENCIA ...")` apareceu no console, e (b) se visualmente algum veículo ainda ficou transversal. Se aparecer qualquer divergência, o log já vem com `vehicle_id`, `type_id`, `slot_index`, `vehicle_yaw` e `slot_yaw` — cole esse log aqui que eu já sigo direto pra causa.

## 5) Dimensões finais das vagas

| Constante | Etapa 3B (antes) | Etapa 6B (agora) |
|---|---|---|
| `POLISH_SLOT_WIDTH` (4 vagas ativas) | 1.60 | **1.45** (-9%) |
| `POLISH_SLOT_DEPTH` | 2.40 | 2.40 (sem mudança) |
| `POLISH_LOCKED_SLOT_WIDTH` (2 vagas bloqueadas) | 1.00 | **0.75** (-25%, também ajuda o item 8 — vagas bloqueadas mais discretas) |

## 6) Distância entre vagas

`POLISH_SLOT_GAP`: **0.12 → 0.28** (mais que dobrou). Com os novos tamanhos, a fileira inteira das 6 vagas mede `4×1.45 + 2×0.75 + 5×0.28 = 8.70`, contra os `9.00` exatos de antes — cabe com folga dentro da largura do tabuleiro (9.00), sem overflow.

A causa raiz do "parece uma tira única" não era só o gap pequeno: havia uma caixa "Platform" compartilhada (cor bege quase idêntica à borda das vagas) por baixo/ao redor de toda a fileira, unificando visualmente as 4 vagas. Essa caixa foi **removida** — cada vaga agora só mostra o próprio Frame (borda off-white) + Pad (azul-acinzentado escuro) + sombra própria, sem nenhum piso comum por baixo. A "AccessLane" (pista curta ligando ao tabuleiro) não foi tocada, pois não fazia parte do problema.

Também: ícone de carrinho 🚗 removido das vagas ativas (o próprio modelo 3D já comunica isso); texto das vagas bloqueadas trocado de "ANUNCIO" para "EM BREVE"; gap entre passageiros e vagas reduzido de 0.20 para 0.12 (leitura mais compacta PASSAGEIROS → DOCKS → ESTACIONAMENTO).

## 7) Posição final do contador

Não alterada nesta etapa — continua em `Vector3(0.0, 1.55, 0.0)` relativo ao Marker3D do slot (ajuste feito na Etapa 3B, permanece válido porque a escala do veículo estacionado não mudou). Como o ícone de carrinho acima dele foi removido, o número passa a ficar sozinho, sem duplicar leitura com o modelo 3D do veículo logo abaixo.

## 8) Arquivos alterados

- `scripts/game/vehicle_controller.gd` — nova função `snap_polish_parked_orientation()`; `drive_route_polished()` e `_drive_final_approach_polished()` passam a receber `slot_yaw_degrees` como parâmetro e não calculam mais heading a partir de posição/tangente; novo campo `_polish_route_tween` e constante `POLISH_YAW_MATCH_TOLERANCE_DEGREES`.
- `scripts/game/game_controller.gd` — `_setup_boarding_area_polish()` agora define `rotation_degrees.y` em cada slot ativo; `_process_vehicle_tap()` busca o marker antes da animação e chama `snap_polish_parked_orientation()` logo após o snap de posição; consts de layout dos docks (`POLISH_SLOT_WIDTH`, `POLISH_LOCKED_SLOT_WIDTH`, `POLISH_SLOT_GAP`, `POLISH_GAP_PASSENGERS_TO_SLOTS`) ajustadas; caixa "Platform" compartilhada removida; ícone de carrinho removido; texto "ANUNCIO" → "EM BREVE"; nova constante `POLISH_PARKED_YAW_DEGREES`.

Além disso, removi um arquivo `nul` que eu mesmo tinha criado por engano no seu diretório do projeto (efeito colateral de um comando de shell mal formado numa etapa anterior desta sessão) — não tem relação com o jogo, já está limpo.

## Como parei

Como pedido: **parei depois da Etapa 6B**. Não iniciei a Etapa 7 nem toquei em GameEngine, level_950, lógica/animação de passageiros, capacidades, câmera, economia, sons, partículas, tabuleiro, cenário ou HUD geral.

Fico no aguardo do resultado do seu teste de 8 veículos (item 10) antes de qualquer próximo passo.
