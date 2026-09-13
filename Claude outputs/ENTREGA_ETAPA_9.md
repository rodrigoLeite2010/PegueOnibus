# ENTREGA — ETAPA 9: Migração segura do modo POLISHED para todas as fases

**Branch:** `profissional_v1`
**Commits desta etapa:**
- `b4394f5` — POLISHED vira padrão de apresentação para toda fase real (remove `POLISHED_LEVEL_IDS`, adiciona `FORCE_CLASSIC_DEBUG`)
- `c02033e` — corrige dois comentários obsoletos sobre o escopo do modo polido (documentação apenas, zero mudança de código)

Esta etapa é migração e validação, como pedido — **nenhum redesign visual, nenhuma mudança de gameplay**. Godot não está disponível neste ambiente, então toda a validação abaixo é estática: leitura de código + um simulador Python que reimplementa fielmente as regras do `GameEngine.gd` real (não um segundo validador divergente — é o mesmo conjunto de regras portado, já que não havia simulador Python de etapas anteriores para reaproveitar). A validação visual em Godot continua sendo sua, na lista no final deste documento.

---

## 1. O que mudou de fato (único ponto de código funcional)

Antes desta etapa, `GameController` decidia `PresentationProfile` por uma lista fixa (`POLISHED_LEVEL_IDS := [1, 2, 3, 950]`). Qualquer fase nova exigiria editar essa lista manualmente. A mudança:

```gdscript
enum PresentationProfile { CLASSIC, POLISHED }
const POLISH_TEST_LEVEL_ID := 950   # só para o gate do "+10"/contador DEV
const FORCE_CLASSIC_DEBUG := false  # trava de regressão, sem UI, nunca exposta ao jogador

func _resolve_presentation_profile(_level_id: int) -> PresentationProfile:
    if FORCE_CLASSIC_DEBUG:
        return PresentationProfile.CLASSIC
    return PresentationProfile.POLISHED
```

`level_id` não é mais usado para decidir apresentação (só é recebido para manter a assinatura estável). `ContentDensity`, o board compacto, câmera adaptativa, docks, ambiente e HUD polido continuam vindo exclusivamente do conteúdo real da fase (`state.vehicles.size()`, `content_bounds`) — exatamente como pedido nas seções 3, 4 e 5 do ticket. Nenhum outro arquivo de lógica de apresentação precisou mudar: todo o restante da máquina (BoardController, EnvironmentController, BoardingAreaController, PassengerCrowdController, HUDController) já lia `is_polished`/`content_density`, nunca `level_id`, desde a Etapa 8/8C.

`CLASSIC` continua existindo e funcionando (não foi apagado) — vira modo de fallback/debug, acionável só via `FORCE_CLASSIC_DEBUG := true` no código, sem UI para o jogador, como pedido na seção 27.

---

## 2. Inventário completo das fases existentes em `levels/`

| Fase | Origem | Board | Veículos | Passageiros | waiting_slots (JSON) | exit_directions usados | Bounds reais ocupados | Occupancy* |
|---|---|---|---|---|---|---|---|---|
| 001 | JSON | 7×7 | 4 (`car`) | 8 | 4 | up, down, left, right | linhas [1,5) colunas [2,5) | 24,5% |
| 002 | JSON | 7×7 | 4 (`car`) | 8 | 4 | up, down, left, right | linhas [1,5) colunas [2,5) | 24,5% |
| 003 | JSON | 8×7 | 5 (`car`) | 10 | 4 | up, down, left, right×2 | linhas [1,7) colunas [2,5) | 32,1% |
| 004 | JSON | 8×7 | 6 (`car`) | 12 | 4 | up, down×2, left, right×2 | linhas [1,7) colunas [1,5) | 42,9% |
| 005 | JSON | 8×7 | 6 (`car`) | 12 | 4 | up, down×2, left, right×2 | linhas [1,7) colunas [1,5) | 42,9% |
| 900 | JSON (órfã/QA antiga) | 10×9 | 7 (3 small_car, 3 medium_car, 1 bus) | 160 | 4 | up×3, left, right×3 | linhas [0,10) colunas [0,8) | 88,9% |
| 950 | JSON (QA/stress oficial) | 13×9 | 26 (14 small_car, 8 medium_car, 4 bus) | 576 | 4 | up×17, down×9 | linhas [0,13) colunas [0,9) | 100% |

*Occupancy = área do bounding box do conteúdo real ÷ área total do tabuleiro (aproximação geométrica pedida na seção 9, não é a ocupação célula-a-célula exata).

**Achado importante:** `waiting_slots` no JSON é **sempre 4** nas 7 fases — mas isso é irrelevante na prática, porque `LevelDefinition._init()` e `LevelDefinition.from_dictionary()` **ignoram completamente o valor do JSON e sempre fixam 4** (confirmado por leitura de código, já reportado informalmente na investigação da Etapa 8C). Ou seja: mesmo que uma fase JSON pedisse outro número de vagas, o jogo sempre usaria 4. Como todas as 7 fases já pedem 4, não há inconsistência a reportar aqui hoje (seção 15) — mas o campo é vestigial e pode enganar quem editar fases manualmente no futuro.

**Não presumi contagem de fases**: o inventário acima é exatamente o que existe hoje em `levels/*.json` (7 arquivos, IDs 001–005, 900, 950). Nenhuma fase adicional foi encontrada.

### 2.1 Achado novo: `level_900.json` é um arquivo órfão, não uma fase real pretendida

`polish_test_launcher.gd` documenta que `level_900.json` foi a origem histórica da fase de stress (comentário: "900→950, 7 veículos, 160 passageiros"), depois expandida para os 26 veículos/576 passageiros atuais e movida para `level_950.json`. O arquivo antigo `level_900.json` nunca foi removido nem excluído da descoberta de fases.

`GameController._discover_levels()` escaneia `levels/` por qualquer `level_*.json` com id numérico e não exclui nada — então `available_levels` hoje é `[1, 2, 3, 4, 5, 900, 950]`. Isso não afeta a progressão normal no curto prazo (fase 6+ já cai no gerador procedural, que não usa `available_levels` para si mesmo), mas **se um jogador algum dia alcançar a fase 900 via progressão normal** (jogando centenas de fases proceduralmente geradas), o jogo carregaria esse JSON órfão — uma fase com dificuldade de início de jogo (7 veículos, board 10×9) — em vez de gerar proceduralmente uma fase de dificuldade máxima nesse ponto (o gerador, em `difficulty_params(900)`, produziria 18 veículos, board 12×10, os tetos máximos da curva). Isso é uma inconsistência estrutural pré-existente, não introduzida por esta etapa, mas só ficou visível agora ao mapear tudo que `PresentationProfile` passaria a tratar como "fase real".

**Não fiz nada com esse arquivo** — nem removi, nem excluí da descoberta, nem renomeei — porque isso seria uma mudança de conteúdo/progressão fora do escopo de migração visual pedido. Fica para sua decisão: (a) apagar `level_900.json` (parece ser puro lixo de desenvolvimento), (b) renomear para algo fora do padrão `level_*.json` para não ser descoberto, ou (c) excluir explicitamente o id 900 em `_discover_levels()`. Qualquer uma dessas é trivial, mas prefiro não decidir por você.

---

## 3. Classificação SMALL / MEDIUM / LARGE e câmera calculada

Usando os limiares já existentes (`DENSITY_SMALL_MAX_VEHICLES=6`, `DENSITY_MEDIUM_MAX_VEHICLES=14`, baseados em `state.vehicles.size()` — não criei nenhuma regra nova nem por número de fase):

| Fase | Veículos | ContentDensity | Board compacto (Etapa 8C) ativo? | compact_scale calculado | camera.size calculado |
|---|---|---|---|---|---|
| 001 | 4 | SMALL | Sim | 0,898 | 14,213 |
| 002 | 4 | SMALL | Sim | 0,898 | 14,213 |
| 003 | 5 | SMALL | Sim | 0,929 | 14,213 |
| 004 | 6 | SMALL | Sim | 0,960 | 14,213 |
| 005 | 6 | SMALL | Sim | 0,960 | 14,213 |
| 900 | 7 | MEDIUM | Não (só SMALL usa board compacto, Etapa 8C) | — (1,0) | 15,502 |
| 950 | 26 | LARGE | Não | — (1,0) | 20,800 |

Todos os `camera.size` foram recalculados fielmente a partir das fórmulas já existentes (pitch da câmera, HUD safe-zones, largura da pista de docks por densidade, crop/compactação da Etapa 8C) — nenhum valor de câmera por-fase foi criado; a câmera continua 100% derivada de densidade + bounds de conteúdo, nunca de `level_id` (seção 20). Nenhum `camera.size` calculado corta conteúdo (todos ficam acima do mínimo necessário pelas próprias fórmulas de segurança do HUD).

**Achado relevante para a seção 21 (curva de progressão) e seção 31 (checklist manual):** as 5 fases reais (1–5) são **todas SMALL** (4 a 6 veículos) — nenhuma fase real hoje chega a MEDIUM ou LARGE. A única fase MEDIUM é a órfã 900 (não deveria ser considerada "real"), e a única LARGE é a 950 (QA). Isso significa que, na prática, **não existe hoje nenhuma fase real MEDIUM ou LARGE** — o salto de densidade só aparece a partir da geração procedural (fase 6 em diante) ou na fase 950 de QA. Isso não é um bug desta etapa nem peço para corrigir agora (ticket pede só observar e relatar, seção 21) — mas explica por que o checklist manual abaixo não tem como incluir "uma fase real LARGE": ela não existe.

---

## 4. Zero overlap, integridade de passageiros e waiting_slots

Rodei uma verificação geométrica exaustiva (par-a-par de células ocupadas) para as 7 fases:

**Overlaps de veículos: 0 em todas as 7 fases.** Nenhum par de veículos ocupa a mesma célula lógica em nenhuma fase, incluindo 900 e 950 (com bus de 3 células).

**Inconsistência de passageiros (bruto do JSON vs. exigido pela capacidade dos veículos daquela cor): 0 em todas as 7 fases.** Toda fase tem exatamente a quantidade de passageiros por cor que a soma das capacidades dos veículos daquela cor demanda — não há excesso nem falta em nenhuma fase, então `LevelDefinition._normalized_passengers()` não precisa completar/cortar nada nelas hoje. Não havia nada para reportar aqui (seção 14).

**waiting_slots:** já coberto na seção 2 — todas as 7 fases já pedem 4 no JSON, e o motor sempre usa 4 de qualquer forma. Nenhuma inconsistência a reportar (seção 15).

---

## 5. Solvabilidade (seção 23/24)

Não havia simulador Python de etapas anteriores para reaproveitar (as validações anteriores foram sempre cálculo geométrico direto ou o próprio `LevelGenerator._validate_solvable()` do Godot). Portei fielmente as regras de `GameEngine.gd` (`can_vehicle_exit`, `get_exit_path_cells`, `process_pending_boarding`, condição de vitória) para Python e rodei uma busca em largura (BFS) geral sobre todos os estados alcançáveis — mais abrangente que o `_validate_solvable()` do próprio `LevelGenerator`, que só testa a ordem canônica de geração (válida por construção para fases procedurais, mas não para fases desenhadas à mão).

| Fase | Solvável (BFS geral) | Estados explorados | Ordem "canônica" do JSON resolve sozinha? |
|---|---|---|---|
| 001 | **Sim** | 16 | Não (precisa de outra ordem — ver nota abaixo) |
| 002 | **Sim** | 16 | Não |
| 003 | **Sim** | 33 | Não |
| 004 | **Sim** | 110 | Não |
| 005 | **Sim** | 110 | Não |
| 900 | **Sim** | 501 | Sim |
| 950 | **Inconclusivo** (ver abaixo) | >600.000 (busca abortada) | Não |

**Nota importante sobre "ordem canônica":** testei também mandar os veículos exatamente na ordem em que aparecem no JSON (o mesmo método que `LevelGenerator._validate_solvable()` usa) e as fases 1–5 **falham** nessa ordem específica (ficam bloqueadas). Isso **não é um bug** — essa garantia de "a ordem de geração sempre resolve" é uma propriedade de construção exclusiva do gerador procedural (ele posiciona veículos de trás para frente exatamente para garantir isso, conforme o comentário no topo de `level_generator.gd`). Fases desenhadas à mão (1–5) não têm essa garantia por construção — e não precisam ter: a busca geral confirma que existe pelo menos uma ordem de embarque que resolve cada uma delas (16 a 110 estados visitados até encontrar a vitória), que é exatamente o quebra-cabeça que o jogador precisa descobrir jogando. Fase 900 por acaso também resolve na ordem literal do JSON.

**Fase 950:** com 26 veículos, o espaço de estados é grande demais para uma busca exaustiva neste ambiente — tentei até ~600 mil estados (limitado pela memória disponível na VM, não por tempo) sem terminar a busca nem encontrar contradição. Não afirmo "impossível" nem "confirmado solúvel por busca" — o resultado é honestamente inconclusivo por limitação computacional deste ambiente, não por um problema encontrado na fase. Dado que a fase 950 já foi jogada até o fim no vídeo real aprovado nas Etapas 8/8B/8C (conforme contexto do próprio ticket), considero essa validação empírica o teste de solvabilidade que realmente importa para ela — recomendo não gastar mais esforço tentando prová-la por busca exaustiva aqui.

**Nenhuma fase foi encontrada impossível.** Não haveria necessidade de alterar conteúdo para "consertar" nada (seção 24) — não se aplica.

---

## 6. Bus, vans e a fase da seção 11

**Achado direto:** nenhuma das 5 fases reais (1–5) contém `medium_car`, `van` ou `bus` — todas usam exclusivamente `type: "car"`. Os únicos veículos maiores do jogo hoje estão em `level_900.json` (órfã) e `level_950.json` (QA). Ou seja, **não existe hoje nenhuma fase real com bus** para validar visualmente "em pelo menos uma fase real" como pedido na seção 11 — o pedido pressupunha que isso existisse, e não existe ainda no conteúdo atual.

O que dá para confirmar estaticamente sobre bus (fases 900/950): footprint de 3 células (`_apply_default_footprint_if_needed`), capacidade 40 (não alterei — é a capacidade configurada no JSON e em `VehicleCapacityTable.default_for("bus")`), zero overlap com outros veículos nas duas fases que o contêm. Curva de saída, lean, chegada, dock e `BoardingPoint` do ônibus (`Bus.tscn`, `BoardingPoint` em `(-195, 11, -193)`, compatível com a escala nativa do GLB do ônibus) só podem ser confirmados visualmente em Godot — incluídos no checklist manual abaixo, usando a fase 950 (única fonte de verdade visual já aprovada em vídeo) já que não há alternativa real.

---

## 7. `CarMedium.tscn` — BoardingPoint na origem (achado já conhecido, não corrigido)

Confirmado por leitura direta do `.tscn`: `CarMedium.tscn` tem um nó `BoardingPoint` (Marker3D) **sem nenhuma propriedade `transform`**, ou seja, na origem/centro geométrico do modelo — diferente de `CarSmall.tscn` (`BoardingPoint` deslocado para `(0.035, 0.009, -0.07)`) e `Bus.tscn` (deslocado para `(-195, 11, -193)`, compatível com a escala nativa do seu GLB). Isso faria passageiros embarcarem visualmente no centro do medium_car em vez de perto de uma porta/lateral.

**Não corrigi isso nesta etapa**, como pedido (só reportar, a menos que esteja claramente causando embarque atravessando o veículo — e isso eu não posso confirmar sem ver em Godot). Vale notar: esse defeito já está presente e ativo no vídeo real já aprovado da fase 950 (que usa 8 medium_car), então, na prática, ou (a) já foi visto e considerado aceitável, ou (b) passou despercebido. Fica sua decisão se quer que eu corrija — se sim, preciso que você me diga um offset aproximado observado em Godot (não tenho como calibrar isso sem visualizar o modelo), e eu faço um commit isolado só com essa mudança, documentando o valor exato usado.

---

## 8. `LevelGenerator` — bug histórico do clamp por paleta de cores

Auditei `scripts/core/level_generator.gd` linha a linha. **O bug não existe mais** (ou já foi corrigido antes desta etapa): `vehicle_count` é calculado por `clampi(7 + int((n - 6) / 2.4), 6, 18)` — um teto fixo de 18, sem nenhuma relação com `COLORS.size()` (que tem 7 cores). Quando `vehicle_count > COLORS.size()`, as cores são reaproveitadas por módulo (`colors[index % colors.size()]`), não usadas como limite superior. Não precisei alterar nada aqui — só confirmo, como pedido na seção 22.

Também confirmei que fases proceduradas usam `type_id = "small_car"` como base (não o literal `"car"` que as fases 1–5 usam) — ver seção 9 abaixo, é um achado relevante para consistência visual.

`LevelGenerator._validate_solvable()` já existe e já garante (por construção + teste real via `GameEngine`) que toda fase procedural gerada é jogável antes de ser aceita — reaproveitei essa mesma lógica (portada para Python) no lugar de criar um segundo validador divergente, como pedido.

---

## 9. Achado novo (fora do escopo dos itens numerados, mas relevante): `"car"` vs `"small_car"` na escala visual polida

Ao investigar `_polish_test_vehicle_scale_multiplier(type_id)` em `game_controller.gd` (usada para aumentar a escala visual de veículos no modo polido), confirmei que ela casa por **string literal**:

```gdscript
match type_id:
    "small_car": return 1.30
    "medium_car", "van": return 1.35
    "bus", "mini_bus": return 1.25
    _: return 1.0
```

As fases reais 1–5 usam `type: "car"` no JSON — que **não** casa com `"small_car"` nesse `match` (só em `VehicleVisualLibrary`, onde `"car"` é um alias documentado para o mesmo modelo/escala de `"small_car"`, mas isso é só a escolha do GLB, não o multiplicador de polish). Já fases procedurais (nível 6+) e a fase 900 usam o literal `"small_car"`. **Resultado prático:** veículos das fases 1–5 renderizam sem o boost de +30% do modo polido, enquanto veículos do mesmo tipo visual em fases procedurais (e 900) renderizam 30% maiores. Isso é uma pequena inconsistência de escala entre fases reais antigas e fases procedurais/QA — não é overlap nem bug de gameplay, é só uma diferença de "peso visual" entre fases que hoje passam a usar o mesmo `PresentationProfile.POLISHED`.

Não corrigi isso (mudaria a aparência de veículos já aprovada nas fases 1–3 em vídeo real, e a ticket pede para não alterar arte/visual além da migração). Reporto para você decidir se quer padronizar em uma etapa futura — a correção seria trivial (adicionar `"car"` ao `match`), mas alteraria a escala visual das fases 1–5 já validadas, então não fiz por conta própria.

---

## 10. `PassengerCrowdController` nas três densidades

Confirmado por leitura de código (`passenger_crowd_controller.gd`): o comportamento já é dirigido por `_polish_mode` (bool) + tamanho real da fila de passageiros (`passenger_queue.size()`), nunca por `level_id` ou por um número de fase. `MAX_VISIBLE_QUEUE_DOLLS := 40` já limita bonecos visíveis simultâneos ao máximo oficial (capacidade do ônibus), com grade em zigue-zague (`POLISH_CROWD_COLUMNS/SPACING`) só no modo polido. Como isso é dirigido puramente por tamanho de fila e não por densidade explícita, o comportamento pedido (SMALL: poucos passageiros centralizados; MEDIUM: grupo intermediário; LARGE: várias fileiras sem invadir o HUD) já emerge automaticamente a partir das fases 1–5 (8–12 passageiros na fila visível) até a 950 (fila de 576, sempre limitada a 40 visíveis por vez, distribuída em até 5 fileiras de 8). Não precisei alterar nada aqui — nenhuma quantidade lógica de passageiros muda, só a exibição visual, que já era assim antes desta etapa.

---

## 11. Docks, HUD polido, economia (+10) — nada alterado

Confirmei por leitura que `_dock_width_scale_for_density`/`_dock_depth_scale_for_density` (Etapas 8B/8C) já são dirigidas por `ContentDensity`, não por `level_id` — então já se aplicam automaticamente a toda fase real agora que `is_polished` é universal. Não toquei em `BoardingAreaController`, `HUDController.update_state()` nem em nenhuma constante de dock/HUD.

`POLISH_TEST_LEVEL_ID := 950` continua existindo e é usado **apenas** para o contador de moedas DEV (`show_polish_test_coin_counter`) e o saldo local `_polish_local_coin_balance` (+10 por veículo, nunca passa por `Wallet`). Confirmei por grep que a única comparação restante com `level_id` no código é exatamente esse gate (`game_controller.gd:1088`, `if state.level_id == POLISH_TEST_LEVEL_ID:`) — nenhuma outra decisão de apresentação, HUD ou visual depende de `level_id` hoje. Fases reais continuam mostrando o saldo real da `Wallet`, sem nenhuma moeda fictícia. Nenhuma mudança de economia foi feita.

---

## 12. Ambiente (grama, calçada, rua, árvores, bancos, luz, sombra)

`EnvironmentController` já lê `is_polish_test` (nome legado — ver classificação abaixo) só para trocar padding/paleta entre CLASSIC e POLISHED, e já usa `use_compact_board`/`visual_center`/`visual_size` vindos do mesmo `BoardController` que todo o resto consome (mesma API da Etapa 8C). Não adicionei nenhum asset novo nem redesenhei nada — só confirmei, por leitura, que o caminho de código já é genérico por presentation_profile/content_density, não por fase.

---

## 13. Classificação da varredura `polish_test`/`POLISH_TEST_LEVEL_ID`/`level_id == 950` (seção 28)

| Local | Classificação | Ação |
|---|---|---|
| `game_controller.gd`: `POLISH_TEST_LEVEL_ID := 950` e seu uso em `state.level_id == POLISH_TEST_LEVEL_ID` (gate do "+10"/contador DEV) | **A — genuinamente exclusivo de QA/950** | Mantido, comentário já correto |
| `hud_controller.gd`: `POLISH_TEST_LEVEL_ID := 950`, `show_polish_test_coin_counter` | **A** | Mantido |
| `polish_test_launcher.gd` (arquivo inteiro) | **A** | Mantido |
| `board_controller.gd` / `environment_controller.gd`: parâmetro `is_polish_test` (na verdade liga/desliga paleta e paddings **POLISHED vs CLASSIC**, para qualquer fase) | **B — nome genérico, devia ser algo como `is_polished`** | Reportado, não renomeado (evitar refactor grande nesta etapa, como pedido) |
| `game_controller.gd`: `_polish_test_vehicle_scale_multiplier()` (aplica a **qualquer** veículo em modo polido, não só na 950) | **B** | Reportado, não renomeado |
| `passenger_controller.gd`: comentário sobre `walk_to_and_board_polished` dizendo que só rodava na fase 950 | **C — comentário obsoleto** | **Corrigido nesta etapa** (commit `c02033e`) |
| `hud_controller.gd`: comentário dizendo que o HUD polido "liga nas fases 1-3, não só na 950" | **C** | **Corrigido nesta etapa** (commit `c02033e`) |

Não fiz nenhuma renomeação de símbolo (variável/função/parâmetro) — só corrigi texto de comentário nos dois casos C, que são zero-risco. Os itens B ficam classificados e documentados para uma etapa futura dedicada a nomenclatura, se você quiser.

---

## 14. O que **não** foi tocado (confirmações negativas pedidas)

- **Arte:** nenhum modelo, material, textura, som, partícula, menu, mapa ou tela de vitória foi alterado.
- **Gameplay:** `GameEngine.gd` não foi tocado. Capacidade, economia, regras de bloqueio, contagem de vagas, fila, ordem de passageiros e condição de vitória continuam idênticas.
- **JSON de fases:** nenhum arquivo em `levels/` foi alterado (nem posições, capacidades, veículos, passageiros, waiting_slots ou dificuldade).
- **Fase 950:** `level_950.json` não foi tocado — 26 veículos, 576 passageiros, composição, `content_density` LARGE e comportamento de docks/câmera LARGE permanecem exatamente como antes (LARGE nunca usa o board compacto da Etapa 8C, e a fórmula de câmera para LARGE não muda nesta etapa).
- **`+10`/DEV:** continuam exclusivos da fase 950, gated por `state.level_id == POLISH_TEST_LEVEL_ID`, nunca por `presentation_profile`.

---

## 15. Resumo objetivo (checklist do ticket, seção 33)

1. **Arquivos alterados:** `scripts/game/game_controller.gd` (mudança funcional), `scripts/game/passenger_controller.gd` e `scripts/ui/hud_controller.gd` (comentário apenas).
2. **Fases existentes encontradas:** 7 — `001, 002, 003, 004, 005, 900, 950` (900 é órfã/QA antiga, ver seção 2.1).
3. **Quais passaram a POLISHED:** todas as 7 (antes só 1, 2, 3 e 950 estavam na lista manual; agora **toda** fase é POLISHED por padrão, incluindo 4, 5 e a órfã 900).
4. **Quais não passaram e por quê:** nenhuma — não há critério de exclusão hoje (CLASSIC só existe via `FORCE_CLASSIC_DEBUG`, desligado por padrão).
5. **Classificação SMALL/MEDIUM/LARGE:** 001–005 = SMALL; 900 = MEDIUM; 950 = LARGE (ver tabela seção 3).
6. **Inconsistências de passageiros encontradas:** nenhuma (seção 4).
7. **Inconsistências de waiting_slots encontradas:** nenhuma no JSON (todas já pedem 4); o campo é vestigial (ignorado pelo motor, sempre 4).
8. **Resultado de solvabilidade:** 001, 002, 003, 004, 005, 900 confirmadas solúveis por busca geral; 950 inconclusiva por limite computacional deste ambiente (ver seção 5), validada na prática pelo vídeo real já aprovado.
9. **Estado do `LevelGenerator`:** bug histórico do clamp por paleta de cores **não existe** (já corrigido antes desta etapa); `_validate_solvable()` já garante toda fase procedural jogável.
10. **Ocorrências restantes específicas da 950:** listadas e classificadas na seção 13 (Categoria A) — todas legítimas, nenhuma removida.
11. **Confirmação `+10`/DEV exclusivos da 950:** confirmado, única comparação restante com `level_id` no código inteiro.
12. **Commits/checkpoints:** `b4394f5` (mudança funcional) e `c02033e` (comentários).
13. **Checklist manual de teste no Godot:** seção 16 abaixo.

---

## 16. Checklist manual para você testar no Godot

Como pedido, aqui está a lista objetiva — sem eu poder confirmar visualmente nada disso neste ambiente:

**Fase 1 (SMALL, inicial, 4 veículos "car")**
- Confirmar que o board aparece compacto (Etapa 8C) e não "estourado" como antes da 8C.
- Confirmar que os 4 veículos saem nas 4 direções (up/down/left/right) sem cruzar malha nem virar dentro de outro veículo.
- Confirmar HUD polido, saldo real da Wallet (sem "+10"/contador DEV).

**Fase 5 (SMALL, mais tardia entre as reais, 6 veículos "car")**
- Mesma checagem de bounds/compactação/direções da fase 1, agora com occupancy mais alta (42,9% calculado) — é o caso mais "apertado" entre as fases SMALL reais, prioridade para checar zero overlap visual.

**Fase 6 (primeira procedural, deve cair em MEDIUM — 7 veículos)**
- Confirmar que gera normalmente (procedural, sem JSON) e que o board **não** fica compacto (Etapa 8C é só para SMALL) — comparar visualmente com uma fase SMALL para confirmar que a transição de densidade é perceptível.
- Como não existe fase real MEDIUM hoje (ver seção 3), esta é a única forma de validar visualmente o comportamento MEDIUM fora da fase 950.

**Fase 950 (LARGE, QA/stress oficial)**
- Confirmar que continua visualmente idêntica ao vídeo já aprovado (board, câmera, docks LARGE, ambiente, 26 veículos, HUD com contador DEV visível).
- Atenção especial ao bus: escala, curva de saída, lean, chegada ao dock, `BoardingPoint`, embarque de passageiros, e saída após completar — é a única fonte visual real de bus disponível hoje (seção 6).
- Confirmar que `CarMedium` (8 unidades nesta fase) mostra o problema de `BoardingPoint` na origem relatado na seção 7 — se **não** for perceptível/incomodo no vídeo, isso é argumento a favor de não mexer nele.

**Uma fase procedural mais avançada (ex.: fase 15–20, para ver van/bus procedurais)**
- `van_chance` começa a subir a partir do nível 8, `bus_chance` a partir do nível 14 — testar uma fase nessa faixa para ver medium_car/bus procedurais lado a lado com small_car, e confirmar que a diferença de escala reportada na seção 9 (veículos procedurais com +30%/+35% de escala vs. fases 1-5 sem boost) não causa overlap nem aparência estranha.

**Fase real LARGE:** não existe (ver seção 3) — não há o que testar aqui até que uma fase real chegue a 15+ veículos ou você decida criar uma.

---

## 17. Onde parei

Como pedido explicitamente no ticket, **parei aqui**. Não iniciei a Etapa 10, não adicionei passageiros/carros/assets/HUD novos, não criei fases novas. Aguardando sua validação manual em Godot antes de continuar.

Dois achados ficaram como decisão sua, não como bloqueio: o arquivo órfão `level_900.json` (seção 2.1) e a diferença de escala `"car"` vs `"small_car"` no modo polido (seção 9). Nenhum dos dois foi alterado.
