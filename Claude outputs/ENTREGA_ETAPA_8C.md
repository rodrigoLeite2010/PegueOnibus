# ENTREGA — Etapa 8C: Board Visual Compacto para Fases SMALL

## 0. Contexto

A Etapa 8B foi validada em vídeo real: fases 1–3 melhoraram, rotas continuam
funcionando, fase 950 permaneceu boa. Mas o problema relatado persistiu nas
fases SMALL (1 e 2, principalmente): o tabuleiro ainda parece grande demais
para a quantidade de veículos, os carros continuam concentrados no centro de
uma área muito vazia, e os 4 docks ativos parecem grandes demais.

**Diagnóstico do porquê a 8B não resolveu isso**: a 8B só cortava o que a
CÂMERA enquadra (`bottom_z`/`required_by_width` em `_setup_camera()`), mas
nunca tocava na MALHA do tabuleiro (`BoardController` continuava desenhando
`rows×cols` cheios) nem nas posições de veículos/rotas. Dentro do
enquadramento mais apertado da 8B, o espectador ainda via o mesmo retângulo
de asfalto cinza inteiro, só que com menos dele cortado fora de tela.

A Etapa 8C ataca isso diretamente: comprime visualmente a MALHA do
tabuleiro, as posições dos veículos, as rotas de saída e o cenário ao redor
— sem tocar em `GameEngine`, `state`, JSON de fase, ou qualquer coordenada
lógica. `GameEngine` continua pensando no tabuleiro 7×7 (ou 8×7) original;
só o que é DESENHADO muda.

**Confirmação explícita do pedido (seção 27)**: em nenhum momento a
implementação exigiu alterar `GameEngine`, `GameState`, `VehicleState`,
`LevelDefinition`, JSON de fase, pathfinding, bloqueios, regras de saída,
capacidades ou passageiros. Toda a mudança ficou nos 4 scripts de
apresentação abaixo.

---

## 1. Arquivos alterados

| Arquivo | O que mudou |
|---|---|
| `scripts/game/board_controller.gd` | Nova API de transformação visual (`visual_x`/`visual_z`/`get_visual_size`/`get_visual_scale`/`get_board_center`) + as 7 funções de desenho (piso, sombra, marcações, meio-fio, cantos, grade de debug, saídas) passam a usar a janela visual compacta quando ativa. |
| `scripts/game/boarding_area_controller.gd` | Novo `dock_depth_scale`: reduz a profundidade das vagas (`POLISH_SLOT_DEPTH`) e o tamanho do "+" (`SlotPlus`) em fases SMALL/MEDIUM, sem tocar na largura da vaga ativa. |
| `scripts/game/environment_controller.gd` | `_board_size()`/`_board_center()` (as 2 únicas funções que toda a decoração já consultava) passam a devolver o board visual compacto quando ativo — grama, calçada, acessos, árvores, bancos e postes acompanham automaticamente. |
| `scripts/game/game_controller.gd` | Orquestração: resolve `use_compact_board`/`visual_compact_scale` uma vez por fase, propaga para `board.setup()`/`environment.setup()`/`boarding_area.setup()`, reposiciona veículos em `_spawn_vehicles()`, e ajusta `_setup_camera()`/`_build_route_to_waiting_slot()` para usar a mesma transformação. |

Nenhum outro arquivo foi tocado. `VehicleController.gd`, `PolishEffectsController.gd`, `PassengerCrowdController.gd`, `GameEngine`, `GameState`, `VehicleState`, `LevelDefinition` e todo JSON de fase permanecem **byte-a-byte idênticos**.

---

## 2. Regra de ativação

```gdscript
use_compact_board = is_polished and content_density == ContentDensity.SMALL
```

Só ativa para fases POLISHED com `ContentDensity.SMALL` (hoje: 1, 2, 3 — ver
Etapa 8B). `MEDIUM` e `LARGE` (fase 950) usam `use_compact_board = false`,
que faz toda função nova (`visual_x`, `visual_z`, `get_visual_scale`,
`_board_size`/`_board_center` do ambiente) devolver exatamente o valor de
sempre — **identidade matemática**, não um caminho de código separado que
possa divergir. CLASSIC nunca chega perto desse código (`is_polished`
sempre false).

---

## 3. API criada — transformação visual (`BoardController`)

Única fonte de verdade, consumida por `GameController` (nunca duplicada em
outro script — ticket seção 16):

```gdscript
func visual_x(x: float) -> float          # ancorado no centro fixo do board
func visual_z(z: float) -> float          # ancorado em Z=0 (borda do patio)
func get_visual_size() -> Vector2         # largura/profundidade do board visual
func get_visual_scale() -> float          # fator de compressao (1.0 fora de SMALL)
func get_board_center() -> Vector3        # centro do board visual (X sempre fixo)
```

- **Eixo X**: `visual_x(x) = center_x + (x - center_x) * scale`, ancorado no
  centro fixo do board (`cols*cell_size*0.5`) — o MESMO ponto onde
  `BoardingAreaController` já centraliza vagas/passageiros. Como o conteúdo
  real das fases 1/2/3 já está centralizado nesse ponto (verificado nos
  JSONs), comprimir em torno dele não desalinha nada — docks continuam
  exatamente onde estavam.
- **Eixo Z**: `visual_z(z) = (z - crop_offset_z) * scale`, ancorado em Z=0
  (a borda do tabuleiro adjacente ao pátio de embarque, que nunca é
  cortada). `crop_offset_z` remove o vão vazio ENTRE o pátio e a primeira
  linha ocupada (com margem de 1 célula); o fator `scale` então comprime o
  que sobrou. Uma única fórmula afim resolve as duas coisas pedidas (cortar
  bounds vazios + comprimir espaçamento) ao mesmo tempo.
- `scale` vem de `_resolve_visual_compact_scale()` em `GameController`,
  baseado na ocupação real (`área do conteúdo / área do board`), entre
  `COMPACT_SCALE_MIN=0.86` e `COMPACT_SCALE_MAX=0.96` — fase mais vazia
  comprime mais, fase com mais conteúdo comprime menos, sem precisar de uma
  categoria "SMALL_TINY" (explicitamente não pedida na seção 20).

---

## 4. Números por fase (calculados, não medidos visualmente)

**Importante, igual à Etapa 8B**: não tenho como rodar o Godot neste
ambiente — os números abaixo vêm da fórmula exata do código, reproduzida em
Python. Peço confirmação visual no vídeo/teste real antes de considerar
isto fechado.

| Fase | Densidade | Ocupação | `compact_scale` | Bounds lógicos (linhas/cols) |
|---|---|---|---|---|
| 1 | SMALL | 24.5% | **0.898** | linhas [1,5] / colunas [2,5] |
| 2 | SMALL | 24.5% | **0.898** | linhas [1,5] / colunas [2,5] |
| 3 | SMALL | 32.1% | **0.929** | linhas [1,7] / colunas [2,5] |
| 950 | LARGE | — | 1.0 (sem compressão) | — |

### Tamanho do board VISUAL (largura × profundidade, em unidades de mundo)

| Fase | Antes (8B, board lógico cheio) | Depois (8C, board visual compacto) | Redução de área |
|---|---|---|---|
| 1 | 7.00 × 7.00 | **6.29 × 5.39** | −30.9% |
| 2 | 7.00 × 7.00 | **6.29 × 5.39** | −30.9% |
| 3 | 7.00 × 8.00 | **6.50 × 7.43** | −13.8% |
| 950 | 9.00 × 13.00 | 9.00 × 13.00 (inalterado) | 0% |

Fase 3 comprime bem menos que 1/2 porque seu conteúdo já ocupa quase a
profundidade inteira do próprio tabuleiro (linhas [1,7] de 8) — exatamente
o comportamento pedido na seção 20, sem precisar de uma categoria nova.

### `camera.size` (comparado com o valor pós-8B)

| Fase | `camera.size` 8B | `camera.size` 8C | Mudança |
|---|---|---|---|
| 1 | 14.213 | **14.213** | **0.0%** |
| 2 | 14.213 | **14.213** | **0.0%** |
| 3 | 14.213 | **14.213** | **0.0%** |
| 950 | 20.800 | 20.800 | 0.0% |

**Achado importante, honesto**: o `camera.size` não muda em relação à 8B
porque a LARGURA (bloco de 6 vagas + AccessLane, já comprimido pela 8B) já
era — e continua sendo — o fator dominante da fórmula (`required_by_width`
vence `required_by_depth`), então cortar mais a profundidade do board (8C)
não move a agulha da câmera. Isto é esperado e é exatamente o motivo de a
8C não ser "mais zoom" — ela reduz o TABULEIRO e os DOCKS dentro do MESMO
enquadramento de sempre, em vez de aumentar o zoom (que você pediu
explicitamente para não fazer). O resultado prático: dentro da mesma
janela de câmera, o piso de asfalto agora ocupa ~31% menos área (fases
1/2), os docks ficam 20% mais rasos, e os veículos se aproximam ~10% uns
dos outros — sobra mais grama/calçada visível e menos "vazio" de asfalto
ao redor dos carros, que é o problema relatado.

### Docks (profundidade das vagas, `POLISH_SLOT_DEPTH`)

| Fase | Densidade | `dock_depth_scale` | Profundidade antes | Profundidade depois |
|---|---|---|---|---|
| 1, 2, 3 | SMALL | 0.80 | 2.40 | **1.92** (−20%) |
| 950 | LARGE | 1.0 | 2.40 | 2.40 (inalterado) |

A largura da vaga ativa (`POLISH_SLOT_WIDTH`) **não mudou** — já não tinha
folga sobrando (ver Etapa 6B/8B). Quem ficou menor foi a profundidade (que
tinha bastante sobra, já que o small_car só precisa de ~1 célula real) e o
tamanho do "+" (`SlotPlus`, `font_size` proporcional a `dock_depth_scale`).

---

## 5. Como as rotas de saída foram adaptadas

`_build_route_to_waiting_slot()` usa a MESMA transformação do board:

- `vehicle_node.position` (ponto de partida da rota) já chega transformado,
  porque `_spawn_vehicles()` aplica `board.visual_x()`/`board.visual_z()`
  logo depois de `setup_from_state()` — a posição LÓGICA (row/col em
  `VehicleState`) nunca muda, só a posição 3D deste nó específico.
- `framed_rows_depth` (limite de saída pra baixo, direção DOWN) passa por
  `board.visual_z()` depois do corte já existente da 8B — idêntico fora de
  SMALL.
- `left_x`/`right_x` (limites de saída LEFT/RIGHT) **não precisaram
  mudar**: já vêm da largura do bloco de vagas
  (`get_polish_lane_half_width()`), que não depende da compressão do board,
  e o ponto central que usam (`cols_width*0.5`) já é o mesmo ancora fixo
  que `visual_x()` usa — matematicamente idêntico nos dois casos.
- `lane_z` (entrada da vaga) também não muda — vem da geometria do próprio
  dock, que tem seu próprio `dock_depth_scale`, independente do board.

Testei mentalmente as 4 direções (UP/DOWN/LEFT/RIGHT, usadas nas fases
1–3): nenhuma delas depende de uma coordenada de board que ficou sem
transformação — ver seção 7 (limitação) sobre o que isso NÃO cobre.

---

## 6. Como o ambiente (`EnvironmentController`) foi adaptado

`_board_size()` e `_board_center()` — as duas únicas funções que TODA a
decoração (`_add_grass`, `_add_plaza`, `_add_plaza_edge`,
`_add_side_connector`, `_add_trees`, `_add_benches`, `_add_lamps`,
`_add_side_planter`, `_add_lot_parking_lines`) já consultava — passam a
devolver `board.get_visual_size()`/`board.get_board_center()` quando
`use_compact_board`. Nenhuma outra função precisou mudar: grama, calçada,
árvores, bancos e postes encolhem/recentralizam automaticamente ao redor
do board compacto. Fora de SMALL, devolvem exatamente `Vector2(cols *
cell_size, rows * cell_size)` / o centro de sempre — zero mudança.

---

## 7. Limitação encontrada — leia antes de testar (prioridade #1)

Ao verificar matematicamente a segurança da compressão (não consigo
renderizar no Godot), encontrei um ponto real que precisa da sua
confirmação visual antes de aprovar esta etapa:

Em pelo menos um par de veículos por fase (ex.: `red_car`/`blue_car` na
fase 1, o mesmo par geométrico em `purple_car`/`orange_car` na fase 2, e
`red_car`/`green_car` na fase 3), os veículos ficam em células
logicamente ADJACENTES (0 células de folga entre eles — comum em puzzles
de "carro travando carro"). Como o multiplicador de escala já existente
(`_polish_test_vehicle_scale_multiplier` = 1.30 para small_car, combinado
com `BOARD_VEHICLE_SCALE` = 0.86) já faz o modelo 3D "vazar" um pouco além
do footprint lógico, esses pares específicos JÁ tinham uma pequena
sobreposição de caixa delimitadora antes da Etapa 8C (calculado, não
confirmado visualmente — o modelo 3D real pode ter folga que uma caixa
retangular simples não captura).

A compressão da 8C aproxima ainda mais esses dois veículos específicos:
calculei um crescimento de ~60–86% na área de sobreposição estimada
desses pares (de uma estimativa pequena para outra um pouco maior, ambas
frações de célula). **Se ao testar você notar qualquer encavalamento de
malha exatamente nesses dois carros**, a correção é trivial e não exige
mexer em nenhuma fórmula: só subir `COMPACT_SCALE_MIN`/`COMPACT_SCALE_MAX`
em `game_controller.gd` (hoje 0.86/0.96) um pouco mais perto de 1.0 — são
2 constantes nomeadas, única fonte de verdade, nada mais precisa mudar.
Escolhi deliberadamente uma faixa mais conservadora que o 0.82–1.0 sugerido
no pedido exatamente por causa deste risco.

Isto **não é uma regressão da Etapa 8C** — a situação de base (veículos
adjacentes com o multiplicador 1.30) já existe hoje, em produção, nas
fases 1/2/3. A 8C só torna a mesma situação um pouco mais apertada. Sinalizo
com prioridade máxima porque é exatamente o tipo de coisa que "prioridade:
zero sobreposição > compactação máxima" (sua seção 9) pede pra verificar
antes de aprovar.

---

## 8. Confirmação — nada de GameEngine/lógica foi tocado

- `GameEngine`, `GameState`, `VehicleState`, `LevelDefinition`: intocados.
- Nenhum JSON de fase foi lido de forma diferente ou alterado.
- `row`/`col` lógicos, footprint lógico, pathfinding, bloqueios, regras de
  saída, capacidades e passageiros: nenhuma linha tocada.
- `rows`/`cols` continuam sendo os valores REAIS do board (`state.board_rows`/
  `state.board_cols`) em todo lugar — só o que é DESENHADO/POSICIONADO
  visualmente usa a janela compacta.
- Fases 4+ não foram migradas (`POLISHED_LEVEL_IDS` continua `[1, 2, 3,
  950]`, intocado).
- Não precisei parar por nenhuma exigência de alterar GameEngine/estado —
  a transformação inteira ficou 100% nos 4 scripts de apresentação.

---

## 9. Checklist manual para você testar no Godot

**Fase 1** (alvo principal):
- [ ] Todos os 4 veículos visíveis, sem sair da tela.
- [ ] **Verificar especificamente `red_car` e `blue_car`** (ver seção 7) —
      sem encavalamento visível de malha.
- [ ] Toque em cada veículo aciona corretamente (colisor segue a nova
      posição visual).
- [ ] Saída de cada veículo (LEFT/UP/DOWN, conforme o JSON) sem cortar
      diagonalmente o tabuleiro nem sumir da câmera.
- [ ] 4 docks visíveis e proporcionalmente menores que antes.
- [ ] Embarque/vitória completam normalmente.
- [ ] Tabuleiro visualmente menor/mais "feito sob medida" que no vídeo da
      8B, sem esticar o zoom.

**Fase 2**: mesmo checklist (mesma geometria de veículos que a fase 1 —
verificar `purple_car`/`orange_car`).

**Fase 3**: mesmo checklist, além de:
- [ ] Confirmar que NÃO comprimiu tão agressivamente quanto 1/2 (conteúdo
      maior, compressão mais suave por design).
- [ ] Verificar `red_car`/`green_car` (ver seção 7).
- [ ] Testar a direção RIGHT (`orange_car`, única fase com as 4 direções
      diferentes entre 1/2/3).

**Fase 950** (regressão visual):
- [ ] Board, espaçamento, câmera, docks, passageiros e rotas devem
      permanecer **perceptivelmente idênticos** ao vídeo já aprovado.

---

## 10. O que NÃO foi feito (por escopo, igual à Etapa 8B)

Fases 4+ não migradas, nenhum carro/passageiro novo, HUD/sons/economia/
dificuldade intocados, nenhum JSON alterado, nenhuma capacidade mudada.
Paro por aqui, aguardando sua validação em vídeo real — especialmente da
seção 7 acima antes de considerar isto fechado.
