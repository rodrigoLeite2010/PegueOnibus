# ENTREGA — Etapa 8B: Composição Adaptativa para Fases Pequenas

## 0. Contexto

A Etapa 8 foi validada em vídeo real: a fase 1 funciona com `PresentationProfile.POLISHED`
e chega até a vitória. O teste revelou um problema de **composição**, não de lógica: a
fase 950 é densa e fica bem enquadrada; fases com poucos veículos (1, 2, 3) ficam com uma
área vazia enorme ao redor de dois ou três carrinhos perdidos no meio do tabuleiro.

Esta etapa resolve isso com uma **densidade de conteúdo** (`ContentDensity`) que adapta
câmera, largura das vagas de embarque e pontos de parada das rotas de saída ao volume real
de veículos da fase — sem tocar em `GameEngine`, `state`, JSON de fase, capacidades ou
dificuldade, e sem migrar fases 4+.

**Importante sobre escopo**: durante a investigação ficou claro que só cortar a câmera não
bastava — as rotas de saída dos veículos (que hoje sempre viajam até a borda física do
tabuleiro inteiro, em qualquer uma das 4 direções) fariam o carro sair visualmente da tela
no meio da animação assim que a câmera fosse apertada. Perguntei antes de mexer nisso, e
você aprovou explicitamente estender o escopo da 8B para também cortar essas rotas — é a
mesma categoria de ajuste visual que o fix da curva exagerada da Etapa 8 (nunca toca
`GameEngine`/pathfinding, só o waypoint visual).

---

## 1. Regra de classificação de densidade

`GameController.ContentDensity` (`SMALL | MEDIUM | LARGE`), resolvida **uma vez por fase
carregada**, a partir do número de veículos (`state.vehicles.size()`):

```gdscript
const DENSITY_SMALL_MAX_VEHICLES := 6
const DENSITY_MEDIUM_MAX_VEHICLES := 14

func _resolve_content_density(vehicle_count: int) -> ContentDensity:
	if vehicle_count <= DENSITY_SMALL_MAX_VEHICLES:
		return ContentDensity.SMALL
	elif vehicle_count <= DENSITY_MEDIUM_MAX_VEHICLES:
		return ContentDensity.MEDIUM
	return ContentDensity.LARGE
```

Usei os mesmos limiares sugeridos no pedido (≤6 SMALL, 7–14 MEDIUM, 15+ LARGE) porque os
dados das 4 fases POLISHED reais não indicaram necessidade de ajustá-los. Só tem efeito
dentro de `is_polished == true`; toda fase CLASSIC ignora `content_density` por completo.

**Classificação real (verificada, não presumida)**, direto do JSON de cada fase:

| Fase | Veículos | Classificação |
|---|---|---|
| 1 | 4 | **SMALL** |
| 2 | 4 | **SMALL** |
| 3 | 5 | **SMALL** |
| 950 | 26 | **LARGE** |

As três fases piloto caíram todas em SMALL — não assumi isso, é o resultado real da regra
aplicada aos dados de cada `level_XXX.json`. Nenhuma fase real hoje cai em MEDIUM; o
caminho existe e está implementado (constantes + `dock_width_scale`), pronto para quando
fases 4+ forem migradas no futuro, mas não pôde ser validado contra um nível real ainda.

---

## 2. Bounds visuais do conteúdo (`_content_bounds`)

Calculado uma única vez por fase carregada (`_compute_content_bounds()`), é o retângulo
(em linhas/colunas de grade, não unidades de mundo soltas) que envolve todos os veículos
`ON_BOARD`, usando o **footprint inteiro** de cada um (não só a célula de origem):

```gdscript
func _compute_content_bounds() -> Rect2:
	var min_row := 999999.0
	var max_row := -999999.0
	var min_col := 999999.0
	var max_col := -999999.0
	var found := false
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		found = true
		min_row = minf(min_row, float(vehicle.row))
		max_row = maxf(max_row, float(vehicle.row + vehicle.footprint_rows))
		min_col = minf(min_col, float(vehicle.col))
		max_col = maxf(max_col, float(vehicle.col + vehicle.footprint_cols))
	if not found:
		return Rect2(0.0, 0.0, float(state.board_cols), float(state.board_rows))
	return Rect2(min_col, min_row, max_col - min_col, max_row - min_row)
```

Veículos nunca nascem no meio de uma fase, então isso é calculado uma vez e cacheado; é
só leitura, nunca altera `GameEngine`/`state`/`board_rows`/`board_cols` lógicos.

Bounds reais medidos nos 4 JSONs:

| Fase | Tabuleiro (linhas×cols) | Conteúdo ocupado (linhas / colunas) |
|---|---|---|
| 1 | 7×7 | linhas [1,5] / colunas [2,5] |
| 2 | 7×7 | linhas [1,5] / colunas [2,5] |
| 3 | 8×7 | linhas [1,7] / colunas [2,5] |
| 950 | 13×9 | linhas [0,13] / colunas [0,9] (~ tabuleiro inteiro) |

Fica claro por que a 950 nunca precisou de composição adaptativa: seu conteúdo já ocupa
quase o tabuleiro inteiro. E por que 1/2/3 tinham tanto espaço vazio: o conteúdo ocupa só
uma faixa central de 4 (ou 6) linhas dentro de um tabuleiro de 7-8.

---

## 3. Câmera adaptativa

`_setup_camera()` agora corta dois dos quatro insumos da fórmula original — **só** quando
`is_polished && content_density != LARGE`, e sempre via `minf()` contra o valor de sempre
(nunca pode aumentar o enquadramento em relação ao comportamento anterior):

- **Profundidade (`bottom_z`)**: em vez de sempre ir até `board_rows * CELL_SIZE +
  BOARD_EDGE_MARGIN` (a borda do tabuleiro lógico inteiro), corta para a última linha
  realmente ocupada pelos veículos + a MESMA folga de sempre (`BOARD_EDGE_MARGIN`).
- **Largura (`required_by_width`)**: em vez de sempre derivar do `board_cols` (que pode
  ser estreito), usa o maior entre a largura do próprio conteúdo e a largura do bloco de
  vagas de embarque (que, como o próprio pedido notou na seção 10, é o elemento mais largo
  da composição em fases pequenas — ver seção 5 abaixo).

Não toquei no mecanismo `POLISH_BOARD_FILL_FRACTION`/`POLISH_WIDTH_FILL_FRACTION`
(constantes deixadas em 1.0 desde a Etapa 2B): eu tinha derivado antes de codificar que
reduzi-lo abaixo de 1.0 **aumenta** o enquadramento (é um divisor), exatamente o erro que
a Etapa 2B cometeu e reverteu. O corte real vem de encolher os próprios `bottom_z`/largura
que entram na fórmula, não desse "gancho".

### Números (calculados pela fórmula exata de `_setup_camera`, viewport 720×1280)

**Importante**: não tenho como rodar o Godot neste ambiente, então estes são valores
**calculados** a partir da fórmula real do código (reproduzida e conferida em Python),
não medidos visualmente. Peço que você confirme visualmente com o vídeo/teste real.

| Fase | Densidade | `camera.size` ANTES | `camera.size` DEPOIS | Redução | Carros aparentam |
|---|---|---|---|---|---|
| 1 | SMALL | 17.244 | **14.213** | 17.6% | **+21.3%** maiores |
| 2 | SMALL | 17.244 | **14.213** | 17.6% | **+21.3%** maiores |
| 3 | SMALL | 17.244 | **14.213** | 17.6% | **+21.3%** maiores |
| 950 | LARGE | 20.800 | **20.800** | **0.0%** | sem mudança |

950 sai com redução de **exatamente 0%** — os dois ramos novos (`is_polished and
content_density != ContentDensity.LARGE`) nunca rodam para ela, então o valor é
byte-a-byte o mesmo de antes da Etapa 8B. Usei 950 como teste de regressão, como pedido.

### Sobre a meta de 25–40% / 75–85% do ticket

Cheguei a +21.3% nas fases 1/2/3, um pouco abaixo do piso de 25% pedido — quero ser
transparente sobre por quê, em vez de forçar números. Na proporção de tela do jogo
(720×1280, retrato), a fórmula divide a largura pelo aspect ratio (0.5625), o que amplifica
bastante o peso da largura sobre o da profundidade. E quem manda na largura, mesmo depois
do corte, não é o conteúdo (carros ocupam só 3 colunas) — é o **bloco de vagas de
embarque** (4 ativas + 2 bloqueadas), que é fisicamente largo e só pode ser compactado até
um certo ponto sem ficar ilegível (ver seção 5). Isso faz a largura continuar sendo o fator
que decide o tamanho final da câmera nessas 3 fases, e o piso físico dela limita o quanto
dá pra apertar sem arriscar as vagas.

Optei por uma compactação de vagas moderada (mantendo a legibilidade da vaga bloqueada e
do espaçamento, coerente com o próprio pedido da seção 10: "podem ficar visualmente **um
pouco** mais compactos") em vez de espremer ao limite físico só para bater o número — o
que exigiria vagas bloqueadas bem mais finas, um risco visual que prefiro não assumir sem
poder validar num teste real. +21.3% é uma melhora real e substancial (quase 1/4 maior),
só um pouco aquém do teto aspiracional de 40%. Se depois de ver o vídeo real você quiser
mais agressividade, dá pra reduzir ainda mais `DOCK_WIDTH_SCALE_SMALL` (hoje 0.55) — é um
único número centralizado.

### Ocupação aproximada da faixa útil

- **Largura**: o bloco de vagas (já compactado) ocupa ~100% da largura visível nas fases
  1/2/3 — ela é, por construção, o próprio limite da largura da câmera agora.
- **Profundidade**: a área de embarque+tabuleiro ocupado ocupa ~75% (fase 1/2) a ~88%
  (fase 3) da faixa vertical útil — dentro/próximo da faixa de 75-85% pedida.

---

## 4. Docks (vagas de embarque) em fase pequena

`BoardingAreaController.setup()`/`_setup_polish()` ganharam um parâmetro
`dock_width_scale` (default `1.0`, sem mudança de comportamento se omitido):

```gdscript
const DOCK_WIDTH_SCALE_SMALL := 0.55
const DOCK_WIDTH_SCALE_MEDIUM := 0.80
const DOCK_WIDTH_SCALE_LARGE := 1.0
```

Aplicado **só** em `POLISH_SLOT_GAP` (espaçamento entre vagas) e
`POLISH_LOCKED_SLOT_WIDTH` (largura das 2 vagas bloqueadas/"EM BREVE") — nunca em
`POLISH_SLOT_WIDTH` (a vaga ativa, onde o carro de verdade estaciona). Essa vaga ativa
tem só ~4.6% de folga sobre o footprint real do `small_car` (documentado desde a Etapa
6B); reduzi-la teria risco real de o carro voltar a "transbordar" visualmente da vaga, e
o pedido explicitamente disse "não reduzir o número de vagas ativas" (mantive as 4 + 2,
só a largura visual das 2 bloqueadas e o espaçamento). `waiting_slots` (a lógica) não foi
tocado em nenhum momento.

Largura total do bloco de vagas (4×1.45 ativas + 2× bloqueada + 5 gaps):

| Densidade | `dock_width_scale` | Largura bloqueada | Gap | Largura total do bloco |
|---|---|---|---|---|
| LARGE (950) | 1.0 | 0.75 | 0.28 | **8.70** (idêntico a hoje) |
| MEDIUM | 0.80 | 0.60 | 0.224 | 8.12 |
| SMALL (1/2/3) | 0.55 | 0.4125 | 0.154 | 7.395 |

A tabela confirma 950 byte-a-byte igual (`8.70`, o mesmo valor documentado desde a
Etapa 6B/8).

---

## 5. Rotas de saída dos veículos (escopo aprovado por você)

`_build_route_to_waiting_slot()` usa a mesma fonte de dados da câmera
(`_content_bounds` e `BoardingAreaController.get_polish_lane_half_width()`, um getter
novo que expõe a largura real do bloco de vagas já escalada) para encurtar, **só** em
POLISHED + `content_density != LARGE`:

- O ponto de parada da saída **DOWN** (hoje vai até `board_rows + margem`) → agora vai até
  `última linha ocupada + a mesma margem de sempre`.
- Os pontos de saída **LEFT**/**RIGHT** (hoje vão até a borda esquerda/direita do
  tabuleiro inteiro) → agora ficam alinhados com a borda do próprio bloco de vagas (menos
  uma folga de segurança de 0.30, a mesma ordem de grandeza da folga que já existe hoje
  entre a margem de saída genérica e a margem de câmera).

Verifiquei nos 3 JSONs que as 4 direções (up/down/left/right) são todas usadas entre os
4-5 veículos de cada fase — por isso esse corte era necessário: sem ele, um carro saindo
por baixo ou pelos lados sairia da tela assim que a câmera apertasse. Todo o cálculo usa
`minf()`/`maxf()` contra os valores de sempre, então LARGE/CLASSIC ficam idênticos.

---

## 6. Passageiros — nenhuma mudança de código necessária

Revisei `PassengerCrowdController.queue_slot_position()` e confirmei que ela **já**
centraliza cada fileira de passageiros independentemente, baseada na contagem real de
bonecos daquela fileira (`row_width = (row_count - 1) * column_spacing`, deslocamento
`x_offset = column * column_spacing - row_width * 0.5`). Para a fase 1 (8 passageiros,
`POLISH_CROWD_COLUMNS = 8`) isso já produz exatamente uma fileira completa de 8,
perfeitamente centralizada sobre o centro das vagas/tabuleiro. Não fiz nenhuma alteração
aqui — o pedido da seção 11 já estava satisfeito.

---

## 7. Cenário (árvores, bancos, postes, jardineiras)

Revisei `environment_controller.gd` por completo. Toda a decoração (grama, praça, árvores,
bancos, postes, jardineiras, conectores de via) é posicionada em relação ao **tabuleiro
lógico inteiro** (`_board_size()`/`_board_center()`), não ao conteúdo — isso não muda
nesta etapa (não tocamos nesse arquivo).

Com a câmera mais apertada em fases SMALL, calculei que a nova borda inferior visível
(`bottom_z` ≈ 5.85 pra fase 1) fica bem **antes** da posição de árvores/bancos/postes
(que ficam na borda da praça, ~7.4 a 8.5 nas mesmas unidades) — ou seja, esses objetos
ficam **totalmente fora** do novo quadro, não "cortados feios" no meio (não há
sobreposição parcial na borda). Isso está dentro do que a seção 12 do pedido já
antecipava e autorizava ("pode simplificar detalhes periféricos em SMALL") — optei por
não alterar `environment_controller.gd` para não expandir o escopo além do necessário;
o efeito prático é que fases SMALL mostram menos cenário periférico (sem cortes feios),
o que é esperado e aceitável pelo próprio pedido.

---

## 8. Botão Dica / espaço inferior (seção 13)

Não mexi no HUD nesta etapa, como pedido. O espaço reservado ao HUD inferior
(`HUD_BOTTOM_UNSAFE_FRACTION`) não muda; o que muda é que agora o `camera.size` menor
faz o conteúdo (tabuleiro + vagas) preencher mais dessa mesma faixa útil, então a
sensação de "vão vazio até o botão Dica" deve diminuir proporcionalmente à redução de
`camera.size` (~17.6% em 1/2/3), mesmo sem redesenhar nada do HUD.

---

## 9. Arquivos alterados

- `scripts/game/boarding_area_controller.gd` — parâmetro `dock_width_scale` em
  `setup()`/`_setup_polish()`; constante `POLISH_ACCESS_LANE_PAD` (era 0.60 inline);
  getter novo `get_polish_lane_half_width()`.
- `scripts/game/game_controller.gd` — enum `ContentDensity` + constantes de limiar;
  `_resolve_content_density()`, `_dock_width_scale_for_density()`,
  `_compute_content_bounds()`; `_setup_camera()` cortando `bottom_z`/
  `required_by_width`; `_build_route_to_waiting_slot()` cortando pontos de saída
  DOWN/LEFT/RIGHT.

Nenhum outro arquivo foi tocado. Não alterei nenhum `level_XXX.json`, `GameEngine`,
capacidades, `waiting_slots`, dificuldade, nem migrei fases 4+.

---

## 10. Checklist de teste manual (não consigo rodar o Godot aqui)

- [ ] **Fase 1**: carros aparentam maiores/menos perdidos no vazio; 4 vagas + 2
      bloqueadas e passageiros continuam totalmente visíveis; nenhum veículo sai da tela
      ao animar saída (testar especificamente o carro que sai para BAIXO e os que saem
      para os LADOS); vitória final abre normalmente e o painel não é afetado pelo novo
      zoom.
- [ ] **Fase 2**: mesma checagem da fase 1 (mesma densidade/bounds).
- [ ] **Fase 3**: mesma checagem; fase 3 tem 1 veículo a mais e ocupa 1 linha a mais
      (bounds [1,7] de um tabuleiro de 8 linhas) — confirmar que o enquadramento ainda
      parece adequado (a redução de profundidade é um pouco menor que nas fases 1/2).
- [ ] **Fase 950**: comparar lado a lado com o vídeo já aprovado da Etapa 8 — o
      enquadramento deve estar **imperceptivelmente idêntico** (os cálculos mostram
      0% de mudança no `camera.size`).
- [ ] Qualquer fase CLASSIC (4+): nenhuma mudança visual/comportamental — os ramos novos
      nunca rodam fora de `is_polished`.

---

## 11. O que NÃO foi feito (por escopo do ticket)

- Nenhum `level_XXX.json` foi alterado.
- Nenhum veículo foi movido logicamente; `GameEngine`/`state` não foram tocados.
- Capacidades, dificuldade e `waiting_slots` (contagem lógica) continuam exatamente
  como estavam.
- Fases 4+ não foram migradas para POLISHED.
- Nenhum asset novo foi criado.
- HUD não foi redesenhado.

---

Paro por aqui, aguardando validação em vídeo real antes de qualquer próxima etapa.
