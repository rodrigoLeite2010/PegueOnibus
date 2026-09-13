# ENTREGA — Etapa 7: Refatoração segura da PolishTest

Escopo respeitado integralmente: refatoração estrutural pura, sem nenhuma melhoria/feature nova. Nenhuma constante de gameplay mudou de valor, nenhum node mudou de posição na hierarquia visual, nenhum comportamento de `GameEngine`/`GameState`/`level_950.json` foi tocado. `VehicleController` e `PassengerController` não tiveram nenhuma responsabilidade movida (só alguns comentários de documentação corrigidos — seção 8). Feita em 3 passos incrementais, cada um validado estaticamente e commitado isoladamente antes do próximo, exatamente como o ticket pediu.

## 1) Checkpoint / backup

Commit de checkpoint antes de qualquer mudança: `4a87dc1` ("Checkpoint pre-Etapa 7: PolishTest completa ate Etapa 6B"). A partir dele, cada extração virou seu próprio commit:

| Commit | Conteúdo |
|---|---|
| `c0a02d7` | Etapa 7 (1/3): extrai `PolishEffectsController` |
| `be19c48` | Etapa 7 (2/3): extrai `BoardingAreaController` (+ edita `Game.tscn`) |
| `740d0b7` | Etapa 7 (3/3): extrai `PassengerCrowdController` |
| `3a74f1c` | Atualiza comentários em `environment_controller.gd`/`passenger_controller.gd` que citavam métodos movidos |

Se algo aqui precisar ser desfeito, dá pra voltar a qualquer um desses pontos sem perder o histórico.

## 2) Análise inicial de responsabilidades

`game_controller.gd` antes da etapa (checkpoint `4a87dc1`): **2128 linhas**, concentrando efeitos visuais puros (partículas, popups), toda a criação/aparência das vagas físicas de embarque, e toda a mecânica visual da fila de passageiros — além da própria orquestração de jogo (input → GameEngine → eventos → animações). Essas três responsabilidades visuais foram extraídas, uma por vez, para três novos controllers.

## 3) Arquivos criados

| Arquivo | Linhas | Papel |
|---|---|---|
| `scripts/game/polish_effects_controller.gd` | 210 | Efeitos visuais puros (partículas procedurais, popups, feedback de vaga liberada) |
| `scripts/game/boarding_area_controller.gd` | 732 | Criação e aparência dos docks de embarque (4 ativos + 2 bloqueados), Marker3D dos slots, labels |
| `scripts/game/passenger_crowd_controller.gd` | 221 | Bonecos 3D da fila de passageiros: spawn, grade/zigue-zague, avanço, reserva visual, reação de cor |

## 4) Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `scripts/game/game_controller.gd` | Remoção das funções/consts/vars movidas; chamadas reescritas para a API pública dos 3 novos controllers |
| `scenes/game/Game.tscn` | Novo `ext_resource` para `boarding_area_controller.gd`; script anexado ao nó `BoardingArea` já existente (`script = ExtResource("5_boarding_area")`); `load_steps` 6→7 |
| `scripts/game/environment_controller.gd` | Só comentário: referência a `GameController._setup_boarding_area()` (função que não existe mais) corrigida para citar `BoardingAreaController` |
| `scripts/game/passenger_controller.gd` | Só comentário: referências a `GameController._react_queue_dolls_for_color`/`_advance_queue_dolls_polished` corrigidas para citar `PassengerCrowdController` |

## 5) `game_controller.gd`: linhas antes/depois (métrica pedida)

| Momento | Linhas | Variação |
|---|---|---|
| Antes da Etapa 7 (checkpoint `4a87dc1`) | **2128** | — |
| Depois do passo 1 (`PolishEffectsController`) | 1960 | −168 |
| Depois do passo 2 (`BoardingAreaController`) | 1267 | −693 |
| Depois do passo 3 (`PassengerCrowdController`) | **1110** | −157 |

**Redução total: 2128 → 1110 linhas (−1018 linhas, −47,8%).** Não persegui um número artificial — o resultado é consequência direta de mover as três responsabilidades pedidas (efeitos, docks, fila visual) e manter tudo mais (orquestração de input/eventos, câmera, rotas de veículo, deadlock) exatamente onde estava.

Total de código GDScript nos 4 arquivos hoje: 1110 + 210 + 732 + 221 = 2273 linhas (o pequeno aumento frente às 2128 originais é esperado: cada novo arquivo tem seu próprio cabeçalho de documentação explicando escopo/decisões, o que antes era um único bloco de comentário compartilhado).

## 6) API pública de cada controller

**`PolishEffectsController`** (`extends Node`, instanciado em runtime por `GameController._ready()`):
`setup(vfx_root, board)`, `tap_spark(pos)`, `boarding_spark(pos, color_id)`, `play_board_sfx_throttled()`, `slot_freed_feedback_polished(marker)`, `coin_popup(pos)`, `win_particles()`, `vehicle_complete_burst(pos, color_id)`.

**`BoardingAreaController`** (`extends Node3D`, script anexado diretamente ao nó `$BoardingArea` da cena):
`setup(waiting_slots_count, board_cols, cell_size, polish_mode)`, `get_slot_marker(slot_index)`, `get_slot_gap_to_board()`, `set_slot_label_text(marker, text)`, `set_slot_label_text_pop(marker, text)`, `set_slot_label_text_pop_bump(marker, text)`.

**`PassengerCrowdController`** (`extends Node`, instanciado em runtime por `GameController._ready()`):
`setup(passengers_root, boarding_area, polish_mode, board_cols, cell_size)`, `queue_slot_position(slot_index)`, `rebuild_dolls(passenger_queue)`, `pop_front_doll(color_id)`, `advance_dolls()`, `advance_dolls_polished()`, `sync_to_state(passenger_queue)`, `react_for_color(color_id)`, `reset()`.

## 7) Dependências entre os controllers

Não há dependência entre os três controllers novos — cada um só depende de nós/dados que `GameController` já possui e repassa via `setup()` (padrão de injeção de dependência simples, sem service locator nem event bus):

- `PolishEffectsController` depende de `vfx_root` (onde as partículas nascem) e `board` (só para `win_particles()` centralizar no tabuleiro).
- `BoardingAreaController` não depende de nenhum outro controller — é autossuficiente a partir do que `setup()` recebe.
- `PassengerCrowdController` depende de `passengers_root` (onde os bonecos nascem) e de `boarding_area` (só para ler a posição do nó `PassengerQueueStart`, via `get_node_or_null` — funciona porque `BoardingAreaController extends Node3D`, então continua sendo um `Node3D` normal para quem só quer sua posição/hierarquia).

`GameController` continua sendo o único que fala com `GameEngine`/`GameState` e o único que decide **quando** chamar cada controller a partir dos eventos do motor — os três controllers novos só representam visualmente o que já foi decidido, nunca leem eventos do `GameEngine` por conta própria.

## 8) O que foi deliberadamente NÃO movido, e por quê

- **`GameController._reserve_boarding_dolls(events)`** continua em `GameController` porque é ela quem lê o array de eventos do `GameEngine` (`"PassengerBoarded"`) e decide, sincronamente, quais bonecos reservar — isso é leitura/decisão sobre eventos do motor, não mecânica visual. Ela hoje chama `_passenger_crowd.pop_front_doll(color_id)` e `_passenger_crowd.advance_dolls()` em vez de métodos próprios.
- **`GameController._boarding_slot_position(slot_index)`** e **`GameController._event_slot_index(events, vehicle_id)`** continuam em `GameController`: a primeira faz a ponte de coordenadas entre `vehicles_root` e `boarding_area` (usada só no fallback de spawn de veículo), a segunda só lê o array de eventos — nenhuma das duas é "aparência de dock".
- **`GameController._build_route_to_waiting_slot(...)`** continua em `GameController` (planejamento de rota do veículo é responsabilidade do próprio `GameController`/`VehicleController`); só a constante `POLISH_SLOT_GAP_TO_BOARD` que ela usava foi movida — agora ela chama `boarding_area.get_slot_gap_to_board()`.
- **`PolishEffectsController.slot_freed_feedback_polished(marker)`** — o ticket cita "feedback de vaga liberada" tanto na seção do `BoardingAreaController` quanto na do `PolishEffectsController`. Decidi manter essa função 100% em `PolishEffectsController` (já extraída na Etapa 7, passo 1) porque o corpo inteiro dela é tween/partícula (pop do "+", pulso de cor no piso, partícula verde) — nenhuma criação/estrutura de dock. `BoardingAreaController` só expõe os nós (`get_slot_marker`) que esse efeito reaproveita.
- **`VehicleController` e `PassengerController`**: nenhuma responsabilidade movida, por instrução explícita do ticket — só 2 comentários de documentação corrigidos (citavam nomes de função que migraram de arquivo).

## 9) Testes estáticos rodados após cada um dos 3 passos

Em cada arquivo tocado ou criado: balanceamento de `()`/`[]`/`{}` (ignorando strings e comentários), varredura de indentação (só tabs, nunca espaço), nomes de função duplicados dentro do mesmo arquivo, e grep de todo o repositório atrás de qualquer referência sobrevivente aos nomes antigos das funções/consts/vars removidas — inclusive em arquivos que eu não tinha tocado (`environment_controller.gd`, `passenger_controller.gd`), onde encontrei e corrigi comentários de documentação desatualizados. Todos os arquivos passaram limpos.

## 10) Sobre testar no Godot — preciso da sua ajuda aqui

Preciso repetir o mesmo limite já relatado na Etapa 6B: o ambiente que uso para editar os arquivos do seu projeto (ponte de arquivos até uma VM Linux isolada) não tem o executável do Godot instalado. Não consigo abrir, rodar ou testar visualmente o jogo a partir daqui — só a verificação estática de código acima. Como esta etapa é uma refatoração pura (nenhuma linha de lógica de jogo mudou de comportamento, só de arquivo), o risco é essencialmente "quebrei alguma referência/assinatura sem perceber" — e é exatamente isso que a checklist abaixo cobre.

### Checklist manual (por favor, rode você mesmo)

1. Abrir o projeto no Godot e checar se `Game.tscn`/`game_controller.gd` carregam sem nenhum erro no painel de saída (script inválido, referência quebrada, etc.).
2. Abrir a PolishTest (fase 950).
3. Mover um veículo livre até uma vaga (toque válido).
4. Tocar em um veículo bloqueado (deve continuar balançando/tremendo, sem mover).
5. Confirmar que o veículo estaciona na vaga certa, com a mesma orientação de sempre (paralela, igual às outras).
6. Embarcar passageiros: confirmar que os bonecos da fila saem, o contador da vaga desce, e o veículo anima o embarque normalmente.
7. Confirmar que o contador da vaga (`SlotLabel`) aparece/atualiza igual a antes.
8. Deixar um veículo sair depois de completar (todos os passageiros embarcados).
9. Confirmar que a vaga libera visualmente (o "+" volta a aparecer, com o mesmo efeito de partícula/pulso).
10. Confirmar o popup "+10" e o toast/mensagem de progresso.
11. Completar a fase e conferir a tela de vitória (partículas, zoom de câmera).

Se qualquer um desses pontos se comportar diferente do vídeo já aprovado na Etapa 6B, me avise com o quê exatamente mudou (e, se possível, algum erro do painel de saída do Godot) que eu sigo direto pra causa.

---

Com isso a Etapa 7 está entregue. Não implementei nada da Etapa 8 — paro aqui, aguardando sua validação no Godot.
