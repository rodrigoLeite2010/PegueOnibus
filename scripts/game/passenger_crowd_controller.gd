class_name PassengerCrowdController
extends Node

# ETAPA 7 (refatoracao segura, SEM mudanca visual/gameplay): extraido de
# GameController. Reune os bonecos 3D da fila de passageiros esperando perto
# das vagas -- spawn visual, posicionamento em grade/zigue-zague, avanco/
# reorganizacao da fila, o stagger exclusivo da fase 950, reacao de cor e a
# lista de instancias PassengerController correspondentes (_queue_dolls). O
# CODIGO e exatamente o mesmo de antes, so mudou de arquivo e (nos poucos
# metodos que viram API publica) perdeu o prefixo "_queue"/"_advance"/
# "_sync"/"_react"/"_rebuild".
#
# NAO reune a decisao de QUANDO reservar um boneco para embarque a partir de
# um evento do GameEngine ("PassengerBoarded") -- isso e leitura direta dos
# eventos do motor, que continua 100% em GameController._reserve_boarding_
# dolls(). Este controller so oferece a MECANICA (pop_front_doll/
# advance_dolls); quem decide QUANDO chamar cada uma continua sendo
# GameController, a partir dos eventos do GameEngine -- o mesmo desenho ja
# usado para PolishEffectsController/BoardingAreaController nesta mesma etapa.
#
# Instanciado em runtime por GameController._ready() (nao existe como no na
# cena .tscn, igual a PolishEffectsController). setup() e chamado de novo a
# cada _load_level_number(), ja que polish_mode/board_cols mudam por fase.
var _passengers_root: Node3D
var _boarding_area: Node3D
var _polish_mode: bool = false
var _board_cols: int = 0
var _cell_size: float = 1.0

var _queue_dolls: Array[PassengerController] = []
var _queue_reveal_count: int = 0

# Os passageiros aparecem no proprio mundo 3D, perto das vagas, em vez de uma
# fila resumida no HUD. 40 cobre exatamente a maior capacidade oficial
# (onibus), entao um onibus de 40 lugares pode mostrar 40 pessoas reais
# aguardando e entrando uma a uma.
const MAX_VISIBLE_QUEUE_DOLLS := 40
const CROWD_COLUMNS := 8
const CROWD_COLUMN_SPACING := 0.52
const CROWD_ROW_SPACING := 0.58
# Quando um passageiro passa a ser visivel pela primeira vez (fila com mais
# gente do que MAX_VISIBLE_QUEUE_DOLLS de uma vez), ele nao aparece pronto na
# posicao final: nasce um pouco mais a direita da propria fileira e anda ate
# o lugar (ver _spawn_doll_walking_in), reforcando a leitura de "entrando
# pela direita, andando ate a fila".
const CROWD_ENTRY_OFFSET_X := 1.35
# ETAPA 2B, item D (mantido/ajustado): fileiras em zigue-zague em vez da
# "matriz perfeita" relatada. ETAPA 2C aumenta as colunas de 7 para 8 (menos
# fileiras pra caber os mesmos 40 bonecos, ver GameController.
# POLISH_BOARDING_AREA_DEPTH) especificamente pra tirar o grupo de baixo do
# titulo "FASE 950".
const POLISH_CROWD_COLUMNS := 8
const POLISH_CROWD_COLUMN_SPACING := 0.58
const POLISH_CROWD_ROW_SPACING := 0.62
const POLISH_CROWD_ROW_STAGGER := 0.29
# ETAPA 4B: atraso entre o step_to() de um boneco da fila e o do proximo
# quando a fila reorganiza pra fechar um buraco (advance_dolls_polished) --
# pedido explicito: "primeiro desloca / 0.02s / segundo / 0.02s / terceiro".
const POLISH_QUEUE_ADVANCE_STAGGER := 0.02


func setup(passengers_root: Node3D, boarding_area: Node3D, polish_mode: bool, board_cols: int, cell_size: float) -> void:
	_passengers_root = passengers_root
	_boarding_area = boarding_area
	_polish_mode = polish_mode
	_board_cols = board_cols
	_cell_size = cell_size


# --- Passageiros 3D esperando perto das vagas ---
# Em vez de resumir a fila no topo da HUD, mostramos pessoas reais no mundo.
# A ordem visual continua sendo a mesma ordem logica de state.passenger_queue.
# Ate 40 ficam visiveis de uma vez, exatamente a capacidade maxima oficial.

func queue_slot_position(slot_index: int) -> Vector3:
	var queue_marker: Marker3D = _boarding_area.get_node_or_null("PassengerQueueStart") as Marker3D
	var base_local: Vector3
	if queue_marker != null:
		base_local = _passengers_root.to_local(queue_marker.global_position)
	else:
		base_local = Vector3(float(_board_cols) * _cell_size * 0.5, 0.20, -1.28)

	# Grade compacta centralizada: 10 pessoas por linha, ate 4 linhas para um
	# onibus de 40 lugares. A primeira linha fica mais perto dos carros.
	# ETAPA 2B, item D: so a fase 950 usa fileiras em zigue-zague (linhas
	# alternadas deslocadas por meio espacamento) em vez da grade perfeita
	# ("planilha") relatada, com colunas/espacamento levemente maiores -- toda
	# fase normal cai exatamente nas mesmas CROWD_COLUMNS/CROWD_COLUMN_SPACING/
	# CROWD_ROW_SPACING de sempre, com stagger_offset sempre 0.0.
	var columns_per_row: int = POLISH_CROWD_COLUMNS if _polish_mode else CROWD_COLUMNS
	var column_spacing: float = POLISH_CROWD_COLUMN_SPACING if _polish_mode else CROWD_COLUMN_SPACING
	var row_spacing: float = POLISH_CROWD_ROW_SPACING if _polish_mode else CROWD_ROW_SPACING

	var column: int = slot_index % columns_per_row
	var row: int = slot_index / columns_per_row
	var row_count: int = mini(columns_per_row, MAX_VISIBLE_QUEUE_DOLLS - row * columns_per_row)
	var row_width: float = float(maxi(row_count - 1, 0)) * column_spacing
	var stagger_offset: float = 0.0
	if _polish_mode and row % 2 == 1:
		stagger_offset = POLISH_CROWD_ROW_STAGGER * column_spacing
	var x_offset: float = float(column) * column_spacing - row_width * 0.5 + stagger_offset
	var z_offset: float = -float(row) * row_spacing
	return base_local + Vector3(x_offset, 0.0, z_offset)


func rebuild_dolls(passenger_queue: Array) -> void:
	for doll: PassengerController in _queue_dolls:
		if is_instance_valid(doll):
			doll.free()
	_queue_dolls.clear()
	_queue_reveal_count = mini(passenger_queue.size(), MAX_VISIBLE_QUEUE_DOLLS)
	for index: int in range(_queue_reveal_count):
		_queue_dolls.append(_spawn_doll(index, passenger_queue[index]))


func _spawn_doll(spawn_index: int, color_id: String) -> PassengerController:
	var doll := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	_passengers_root.add_child(doll)
	doll.setup(color_id, _polish_mode)
	doll.position = queue_slot_position(_queue_dolls.size())
	return doll


# Mesma coisa que _spawn_doll, mas para quando um boneco passa a ser visivel
# DEPOIS que a fase ja comecou (ver sync_to_state): em vez de aparecer pronto
# na posicao final, nasce mais a direita (fora da propria fileira) e anda ate
# o lugar com a mesma animacao de passo usada na fila avancando -- e a
# entrada "vindo andando da direita" pedida.
func _spawn_doll_walking_in(slot_index: int, color_id: String) -> PassengerController:
	var doll := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	_passengers_root.add_child(doll)
	doll.setup(color_id, _polish_mode)
	var target: Vector3 = queue_slot_position(slot_index)
	doll.position = target + Vector3(CROWD_ENTRY_OFFSET_X, 0.0, 0.0)
	doll.step_to(target)
	return doll


func pop_front_doll(color_id: String) -> PassengerController:
	if not _queue_dolls.is_empty():
		return _queue_dolls.pop_front()
	var fallback := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	_passengers_root.add_child(fallback)
	fallback.setup(color_id, _polish_mode)
	fallback.position = queue_slot_position(0)
	return fallback


func advance_dolls() -> void:
	# Cada passageiro restante avanca para a proxima posicao livre da grade.
	for index: int in range(_queue_dolls.size()):
		var doll: PassengerController = _queue_dolls[index]
		if is_instance_valid(doll):
			doll.step_to(queue_slot_position(index))


# ETAPA 4B ("REORGANIZACAO DA FILA"): variante da funcao acima, exclusiva da
# fase 950 -- em vez de mandar TODOS os step_to() no mesmo instante (o que
# lia como um bloco inteiro reagindo junto), cada boneco restante recebe um
# pequeno atraso (POLISH_QUEUE_ADVANCE_STAGGER) em relacao ao anterior antes
# do seu proprio step_to() disparar -- step_to() ja anima cada um em 0.26s
# (dentro dos "0.20-0.28s" pedidos), entao o resultado e um efeito de onda
# sem sobreposicao. NAO precisa terminar de percorrer os 40 bonecos de uma
# vez: e fire-and-forget (chamada sem "await" pelo GameController), entao o
# resto do jogo nunca fica bloqueado esperando a fila terminar de
# reorganizar visualmente.
func advance_dolls_polished() -> void:
	var count: int = _queue_dolls.size()
	for index: int in range(count):
		var doll: PassengerController = _queue_dolls[index] if index < _queue_dolls.size() else null
		if is_instance_valid(doll):
			doll.step_to(queue_slot_position(index))
		if index < count - 1:
			await get_tree().create_timer(POLISH_QUEUE_ADVANCE_STAGGER).timeout


# Ressincroniza a fila visual com a fila LOGICA atual. Roda depois de cada
# leva de embarque. NAO destroi mais todos os bonecos toda vez (isso fazia a
# fila inteira "piscar"/teleportar de novo a cada carro que terminava,
# inclusive durante toques concorrentes que ainda estavam com bonecos no meio
# do caminho): so ajusta a DIFERENCA. Quem ja esta na tela e continua
# correspondendo a fila logica (a ordem e sempre preservada por
# GameController._reserve_boarding_dolls/advance_dolls, que ja tiram e
# reordenam os bonecos certos no instante do toque) fica exatamente onde
# esta; so entra gente nova quando a fila logica tem mais passageiros do que
# os bonecos atuais mostram (fases com mais de MAX_VISIBLE_QUEUE_DOLLS
# passageiros no total) -- e so esses bonecos novos "andam" ate o lugar
# vindo de fora da fileira, pela direita (ver _spawn_doll_walking_in).
func sync_to_state(passenger_queue: Array) -> void:
	var target_count: int = mini(passenger_queue.size(), MAX_VISIBLE_QUEUE_DOLLS)
	while _queue_dolls.size() > target_count:
		var extra: PassengerController = _queue_dolls.pop_back()
		if is_instance_valid(extra):
			extra.free()
	while _queue_dolls.size() < target_count:
		var slot_index: int = _queue_dolls.size()
		_queue_dolls.append(_spawn_doll_walking_in(slot_index, passenger_queue[slot_index]))
	_queue_reveal_count = _queue_dolls.size()


# Item 3 do pedido: reage (micro pop) nos primeiros bonecos visiveis da fila
# cuja cor bate com a do veiculo que acabou de estacionar -- so cosmetico,
# nunca mexe em _queue_dolls nem em quem vai realmente embarcar (isso
# continua 100% decidido por GameController._reserve_boarding_dolls/eventos
# do GameEngine). Limitado a poucos bonecos de proposito (o pedido permite
# nao aplicar aos 40 de uma vez, por performance).
func react_for_color(color_id: String) -> void:
	var reacted := 0
	for doll: PassengerController in _queue_dolls:
		if reacted >= 10:
			break
		if is_instance_valid(doll) and doll.color_id == color_id:
			doll.polish_color_react()
			reacted += 1


# Chamado por GameController._clear_all_visuals(): os nos ja foram
# destruidos ali (free() em todos os filhos de passengers_root); aqui so
# limpamos a lista de referencias, pra nao ficar apontando para nos mortos.
func reset() -> void:
	_queue_dolls.clear()
