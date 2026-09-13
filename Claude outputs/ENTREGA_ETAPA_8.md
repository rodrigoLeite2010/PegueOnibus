# ENTREGA — Etapa 8: PresentationProfile e migração da apresentação polida para as fases 1-3

Escopo respeitado integralmente: nenhuma alteração em level JSON, capacidades, GameEngine/pathfinding lógico, dificuldade, criação de fases, economia real (Wallet) ou arte. Migrado só **apresentação** (câmera, docks, fila 3D, ambiente/paleta, efeitos, HUD) — o conteúdo de cada fase (veículos, capacidades, vagas, dificuldade, board, regras) continua vindo do próprio `level_00X.json`, intocado. Feito em 2 commits incrementais sobre o checkpoint da Etapa 7 (`3a74f1c`).

| Commit | Conteúdo |
|---|---|
| `bf88756` | Etapa 8 (1/2): `PresentationProfile` substitui checagens diretas de `level_id==950` (`game_controller.gd` + `hud_controller.gd`) |
| `bda00d2` | Etapa 8 (2/2): renomeia `is_polish_visual` → `is_polished` em `VehicleController` |

## 1) Sistema de perfil de apresentação criado

Em `game_controller.gd`:

```gdscript
enum PresentationProfile { CLASSIC, POLISHED }
const POLISH_TEST_LEVEL_ID := 950
const POLISHED_LEVEL_IDS: Array[int] = [1, 2, 3, POLISH_TEST_LEVEL_ID]

var presentation_profile: PresentationProfile = PresentationProfile.CLASSIC
var is_polished: bool = false

func _resolve_presentation_profile(level_id: int) -> PresentationProfile:
	return PresentationProfile.POLISHED if POLISHED_LEVEL_IDS.has(level_id) else PresentationProfile.CLASSIC
```

`presentation_profile`/`is_polished` são recalculados **uma vez** por fase, logo no início de `_load_level_number()` (`presentation_profile = _resolve_presentation_profile(state.level_id)`), e usados como membro do `GameController` em todo o resto do arquivo — nenhuma outra função volta a comparar `state.level_id` contra 950 para decidir aparência (a única exceção deliberada é a recompensa de teste "+10", ver seção 5).

Optei por não criar um `Resource`/arquivo separado para isto: um enum + uma constante + uma função pura resolvem o pedido ("evitar arquitetura excessiva") sem introduzir mais uma classe/arquivo só para guardar dois valores.

## 2) Fase 950 (PolishTest)

Continua POLISHED (está na lista `POLISHED_LEVEL_IDS`) e nenhuma constante visual (câmera, paleta, tamanhos de vaga, efeitos, HUD) mudou de valor. A única diferença de comportamento é estrutural (a decisão passa por `is_polished` em vez de uma comparação inline), o que é indistinguível visualmente do vídeo já aprovado na Etapa 7 — exceto pelo fix do bug da curva (seção 6), que também se aplica a ela.

## 3) Fases reais migradas: 1, 2 e 3

`POLISHED_LEVEL_IDS := [1, 2, 3, POLISH_TEST_LEVEL_ID]`. Só essas 3 fases reais entram em POLISHED nesta etapa, exatamente como pedido — nenhuma outra fase foi tocada. Fases 4+ e as geradas proceduralmente (`LevelGenerator`) continuam CLASSIC, sem passar por `POLISHED_LEVEL_IDS.has(...)` com sucesso.

## 4) Conteúdo das fases 1-3: intocado

Não editei nenhum `level_001.json`/`level_002.json`/`level_003.json`. Confirmei via grep que os `"id"` continuam 1/2/3 e todos os campos de veículos/capacidades/vagas/dificuldade permanecem como estavam. O que muda para essas 3 fases é só a chamada de `board.setup(...)`, `environment.setup(...)`, `boarding_area.setup(...)`, `_passenger_crowd.setup(...)`, câmera e HUD com `is_polished = true` — todas essas funções já recebiam esse boolean como parâmetro (arquitetura da Etapa 7), então não houve mudança de assinatura, só do valor passado.

## 5) Controllers não conhecem mais "950"

Confirmei (antes mesmo de mexer) que `BoardingAreaController`, `PassengerCrowdController`, `BoardController` e `EnvironmentController` já recebiam um boolean puro via `setup(...)` — nenhum deles compara `level_id`/950 internamente. Esse requisito já estava arquiteturalmente satisfeito desde a Etapa 7; nesta etapa só passei a alimentá-los com `is_polished` (derivado do perfil) em vez de uma variável local `is_polish_test_level` recalculada ad-hoc.

`PolishEffectsController` nunca recebeu esse parâmetro (todos os seus métodos já são inerentemente "efeito polido", chamados condicionalmente pelo próprio `GameController`) — nada a mudar aí.

## 6) Bug da curva exagerada ao sair da vaga (seção 9 do ticket) — corrigido

**Causa**: em `_build_route_to_waiting_slot()`, a direção de saída `UP` usa `lane_z` como profundidade do primeiro ponto da rota. Em fases POLISHED, `lane_z` é comprimido para `-boarding_area.get_slot_gap_to_board()` (≈ -0,15, resultado do trabalho de compactação de docks da Etapa 6B) — bem mais perto do tabuleiro que o `-0,78` genérico usado nas demais direções (`margin = 0,72`). Isso criava um primeiro segmento de saída muito curto, concentrando uma curva grande (a suavização Catmull-Rom-like de `_build_route_curve`) numa fatia mínima do comprimento/tempo total da animação (`drive_route_polished`/`_apply_curve_progress_polished` escalam a duração pelo comprimento total da curva) — lido visualmente como um giro brusco/diagonal assim que o veículo deixa o tabuleiro.

**Fix aplicado**, só na direção `UP`, depois do `match` que já define o `stage` de saída e antes de `route.append(stage)`:

```gdscript
if vehicle_node.exit_direction == ExitDirection.Value.UP:
	stage.z = minf(stage.z, vehicle_node.position.z - margin)
	lane_z = stage.z
route.append(stage)
```

Garante uma folga mínima de saída igual ao `margin` já usado pelas outras 3 direções, antes da curva começar. É puramente geometria do waypoint visual — **não toquei em `GameEngine`, pathfinding lógico, `exit_direction`/`entry_direction` reais ou em qualquer decisão de bloqueio**. O `minf()` faz este fix ser matematicamente neutro em fases CLASSIC (onde `lane_z` genérico já é `-0,78`, mais negativo que `-margin = -0,72`) e nas demais direções (DOWN/LEFT/RIGHT), cujos pontos de saída já são ancorados em constantes fixas (`margin`/`rows_depth`/`cols_width`), nunca em `lane_z`.

**Não consigo confirmar visualmente esse fix** pelo mesmo motivo já relatado nas etapas anteriores — ver seção 9.

## 7) HUD polido em fases 1-3, badge DEV isolada na 950

`hud_controller.gd`: `update_state()` ganhou um novo parâmetro `polished: bool = false`. A decisão de aplicar o estilo "polido" (esconder o contador "X mov.", trocar o painel de mensagem por toasts) agora usa esse parâmetro em vez de `state.level_id == POLISH_TEST_LEVEL_ID` internamente — então fases 1-3 também ganham o HUD polido, como pedido.

A badge "DEV" (`show_polish_test_coin_counter`/`_build_polish_coin_badge`, com a tag `"DEV"` explícita) **não foi tocada** e continua exclusivamente chamada pelo `GameController` só quando `state.level_id == POLISH_TEST_LEVEL_ID` (comparação literal, ver seção 8) — nunca aparece nas fases 1-3. `POLISH_TEST_LEVEL_ID` continua duplicado como constante local no `HUDController` (já era assim antes; não é acessível via `GameController.POLISH_TEST_LEVEL_ID` sem acoplar os dois scripts, e o ticket não pediu para mudar esse padrão).

Em fases 1-3 o saldo mostrado é sempre o balanço real (`Wallet.total_coins`, badge normal `_coin_badge`/`_coin_label`) — nenhuma moeda falsa foi criada.

## 8) Recompensa de teste "+10" isolada à fase 950

Verifiquei o sistema real de economia antes de mexer: `scripts/core/wallet.gd` (autoload `Wallet`) já é usado sem condição nenhuma em `_process_vehicle_tap()` no evento `Win` (`Wallet.award_win_bonus()`, 20 moedas reais persistidas em `user://wallet.cfg`) — **não alterei este arquivo nem essa chamada**.

Em `_play_boarding_events_polished()`, o bloco de recompensa de teste ficava:

```gdscript
_polish_effects.vehicle_complete_burst(...)
_polish_local_coin_balance += 10
_polish_effects.coin_popup(...)
hud.show_polish_test_coin_counter(_polish_local_coin_balance)
```

Passou a:

```gdscript
_polish_effects.vehicle_complete_burst(...)   # efeito visual puro, continua incondicional
if state.level_id == POLISH_TEST_LEVEL_ID:    # check LITERAL, nao is_polished
	_polish_local_coin_balance += 10
	_polish_effects.coin_popup(...)
	hud.show_polish_test_coin_counter(_polish_local_coin_balance)
```

Ou seja: o efeito de partícula de "veículo completo" continua rodando em qualquer fase POLISHED (é um efeito visual real, sem número associado), mas o saldo falso, o popup "+10" e a badge DEV ficam presos à fase 950 especificamente — nunca aparecem em fases 1, 2 ou 3, mesmo com `presentation_profile == POLISHED`.

## 9) Testar fases 1, 2, 3 e 950 — preciso da sua ajuda aqui

Mesmo limite de sempre: o ambiente que uso para editar os arquivos do seu projeto (ponte de arquivos até uma VM Linux isolada) não tem o executável do Godot. Não consigo abrir, rodar ou ver visualmente nenhuma das 4 fases a partir daqui — só a verificação estática de código (balanceamento de `()`/`[]`/`{}`, indentação só-com-tabs, nomes de função duplicados, grep de referências órfãs), que rodei nos 3 arquivos alterados e todos passaram limpos.

### Checklist manual — fases 1, 2 e 3 (novo, POLISHED)

1. Abrir a fase 1: confirmar que o board aparece enquadrado corretamente (nem cortado, nem sobrando espaço demais), do mesmo jeito que a fase 950.
2. Carros não devem parecer gigantes nem minúsculos (a escala por tipo de veículo da PolishTest se aplica agora aqui — `_polish_test_vehicle_scale_multiplier`).
3. Docks (vagas de embarque) visíveis e legíveis, com o HUD polido (sem contador "X mov.", mensagens como toast).
4. Passageiros visíveis na fila 3D, com o layout em zigue-zague da PolishTest.
5. Embarcar passageiros normalmente (a cascata de embarque da fase 950 agora roda aqui também).
6. Vencer a fase: confirmar vitória, sem popup "+10" nem badge "DEV" aparecendo em nenhum momento — só o saldo real de moedas (`Wallet`) deve mudar, com a animação normal de recompensa.
7. Repetir os passos 1-6 na fase 2 e na fase 3.
8. Prestar atenção especial a um veículo saindo do board pela parte de cima (rumo aos passageiros) — não deve mais fazer aquela curva/giro exagerado na base; se ainda acontecer, me avise em qual fase/veículo para eu investigar mais.

### Checklist manual — fase 950 (regressão)

9. Repetir a checklist da Etapa 7 (embarque, vagas, contadores, moedas de teste "+10"/badge DEV, vitória) — tudo deve continuar idêntico ao vídeo já aprovado, incluindo a badge DEV (que so aparece aqui).
10. Confirmar que o "+10"/badge DEV continua aparecendo normalmente na 950 (não deve ter sumido — só deixou de vazar para as fases 1-3).

### Checklist manual — fases 4+ (regressão CLASSIC)

11. Abrir qualquer fase 4 em diante e confirmar que nada mudou visualmente (câmera, cores, docks, fila de passageiros no formato antigo) — devem continuar 100% CLASSIC.

Se qualquer um desses pontos se comportar diferente do esperado, me diga exatamente o quê (fase, veículo, e se possível algum erro do painel de saída do Godot) que eu sigo direto pra causa.

## 10) Remoção de hardcode 950 — busca e classificação final

Busquei `950`, `POLISH_TEST_LEVEL_ID` e `is_polish_test` em todo o repositório depois de todas as mudanças. Restam **80 ocorrências**, das quais **75 são comentários/documentação** (histórico das etapas anteriores, several ainda mencionando "fase 950" em texto — atualizei os mais enganosos, como o cabeçalho do `game_controller.gd` e comentários em `vehicle_controller.gd`/`hud_controller.gd` que descreviam um comportamento que deixou de ser exclusivo da 950). As **5 ocorrências de código** restantes:

| Local | Classificação |
|---|---|
| `game_controller.gd`: `const POLISH_TEST_LEVEL_ID := 950` | (a) necessária — é a própria âncora numérica que identifica a fase de teste dentro de `POLISHED_LEVEL_IDS` |
| `game_controller.gd`: `const POLISHED_LEVEL_IDS := [1, 2, 3, POLISH_TEST_LEVEL_ID]` | é o próprio mecanismo do `presentation_profile` — a única lista que decide POLISHED vs CLASSIC |
| `game_controller.gd`: `if state.level_id == POLISH_TEST_LEVEL_ID:` (dentro de `_play_boarding_events_polished`) | (c) DEV-only — isola a recompensa de teste "+10"/badge DEV à fase 950, por design (seção 8) |
| `hud_controller.gd`: `const POLISH_TEST_LEVEL_ID := 950` | (a) necessária — usada só para gatear a badge DEV (`show_polish_test_coin_counter`) |
| `polish_test_launcher.gd`: `const POLISH_TEST_LEVEL_NUMBER := 950` | (a) necessária — é o próprio bootstrap dedicado da cena `PolishTest.tscn`, o único ponto de entrada da fase 950 |

Nenhuma dessas 5 é uma dependência visual "escondida" — todas são pontos explícitos e documentados onde a fase 950 precisa mesmo ser identificada por número (o launcher dela, a âncora da lista de perfis, e o isolamento deliberado do dinheiro de teste).

Não renomeei `is_polish_test`/`p_is_polish_test` em `board_controller.gd` e `environment_controller.gd` (continuam com esses nomes internos, só recebendo o boolean já correto de `is_polished`) — são só nomes de parâmetro locais, sem nenhuma comparação com 950, então o requisito funcional da seção 5 já estava satisfeito; renomear é cosmético e de baixo valor frente ao risco de mexer em mais 2 arquivos sem necessidade.

## 11) VehicleController: renomeação parcial (seção 6 do ticket)

Segui a permissão explícita do ticket ("não precisa renomear tudo se causar risco"). Levantei mais de 20 símbolos com prefixo `polish_`/`POLISH_` em `vehicle_controller.gd` (1319 linhas) e confirmei que **nenhum deles compara o número 950** — todos já são boolean-driven pelo chamador. Rename executado: só `is_polish_visual`/`p_is_polish_visual` → `is_polished`/`p_is_polished` (4 ocorrências, todas internas a este arquivo, `setup_from_state()` chamado só posicionalmente por `GameController`). Os demais (`drive_route_polished`, `POLISH_TYPE_SPEED_MULTIPLIER`, `snap_polish_parked_orientation`, `_polish_busy`, etc.) foram deliberadamente deixados como estão — nenhuma decisão visual **nova** depende do número 950 neles, e renomear os ~20 restantes seria trabalho cosmético com risco desproporcional num arquivo desse tamanho.

## 12) Arquivos alterados (resumo)

| Arquivo | Mudança |
|---|---|
| `scripts/game/game_controller.gd` | `PresentationProfile`/`POLISHED_LEVEL_IDS`/`_resolve_presentation_profile`; `is_polished` substitui todas as comparações locais com `POLISH_TEST_LEVEL_ID` (exceto o fence DEV do +10); fix do bug da curva em `_build_route_to_waiting_slot`; `hud.update_state(...)` passa `is_polished` |
| `scripts/ui/hud_controller.gd` | `update_state()` ganha parâmetro `polished`; badge DEV continua literal-950 |
| `scripts/game/vehicle_controller.gd` | `is_polish_visual`/`p_is_polish_visual` → `is_polished`/`p_is_polished` |

Nenhum outro arquivo foi tocado (level JSON, GameEngine, cenas .tscn, arte, economia real — todos intocados).

---

Com isso a Etapa 8 está entregue. Como pedido: **paro aqui**, aguardando sua validação nas fases 1, 2, 3 e 950 antes de qualquer próxima etapa.
