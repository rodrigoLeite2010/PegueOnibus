class_name GameController
extends Node3D

const CELL_SIZE := 1.0
const LEVEL_DIR := "res://levels"
const LEVEL_PATTERN := "level_%03d.json"
const HINT_COST := 15
# Os passageiros agora aparecem no proprio mundo 3D, perto das vagas, em vez
# de uma fila resumida no HUD. 40 cobre exatamente a maior capacidade oficial
# (onibus), entao um onibus de 40 lugares pode mostrar 40 pessoas reais
# aguardando e entrando uma a uma.
const MAX_VISIBLE_QUEUE_DOLLS := 40
const CROWD_COLUMNS := 10
const CROWD_COLUMN_SPACING := 0.34
const CROWD_ROW_SPACING := 0.34

# --- Enquadramento da camera ---
# A HUD (CanvasLayer, 2D) fica sempre por cima da cena 3D, ocupando uma faixa
# fixa de tela (em pixels, no espaco de design 720x1280 do projeto) tanto no
# topo (TopPanel + QueuePanel) quanto embaixo (BottomPanel). O enquadramento da
# camera 3D precisa deixar o tabuleiro inteiro fora dessas faixas; antes disso
# nao acontecia (a camera usava um deslocamento fixo, calibrado so pra um
# tamanho de tabuleiro, e ignorava a atenuacao trigonometrica causada pela
# inclinacao da camera), o que deixava veiculos proximos da borda norte do
# tabuleiro escondidos atras da HUD em fases com outra proporcao de linhas.
const CAMERA_PITCH_DEGREES := -63.0
const CAMERA_HEIGHT := 14.5
const BOARD_EDGE_MARGIN := 0.85
# Profundidade real ocupada pela area de embarque (plataforma, pista, letreiros
# e o ponto onde os passageiros nascem -- ver _setup_boarding_area) ANTES da
# linha 0 do tabuleiro. Precisa entrar na conta do enquadramento da camera
# como a propria area do tabuleiro; tratar como se fosse so a folga generica
# de borda (BOARD_EDGE_MARGIN) escondia parte da area de embarque atras da
# faixa de HUD de cima -- exatamente o bug relatado ("carro sumindo atras do
# topo"). O maior letreiro ("PASSAGEIROS") fica em z=-1.62; 1.85 da folga.
const BOARDING_AREA_DEPTH := 3.05
const HUD_TOP_UNSAFE_FRACTION := 118.0 / 1280.0
const HUD_BOTTOM_UNSAFE_FRACTION := 160.0 / 1280.0
# Colchao extra (fracao de tela) alem da borda exata da HUD, pra nunca deixar
# a area de embarque ou a ultima linha do tabuleiro coladas exatamente na
# borda (o que arrisca cortar 1-2px dependendo do arredondamento).
const CAMERA_FRAME_SAFETY_FRACTION := 0.02

@onready var board: BoardController = $Board
@onready var environment: EnvironmentController = $GameEnvironment
@onready var vehicles_root: Node3D = $Vehicles
@onready var passengers_root: Node3D = $Passengers
@onready var vfx_root: Node3D = $VFX
@onready var boarding_area: Node3D = $BoardingArea
@onready var camera: Camera3D = $Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var hud: HUDController = $HUD

var state: GameState
var level: LevelDefinition
var vehicle_nodes: Dictionary = {}
# vehicle_id -> Marker3D da vaga de embarque onde ele estacionou (ver
# _process_vehicle_tap). Usado so pra atualizar o contador regressivo
# (Label3D "SlotLabel") em cima do proprio carro conforme os eventos de
# PassengerBoarded/SlotFreed sao reproduzidos -- nunca decide nada do jogo,
# so espelha o que ja aconteceu em GameEngine.
var _vehicle_slot_markers: Dictionary = {}
# is_animating reflete "ha PELO MENOS uma jogada em andamento agora" -- usado
# so por restart/dica/continuar, que continuam bloqueados enquanto qualquer
# veiculo estiver se movendo. Nao serializa mais toques: varios veiculos
# podem estar andando/estacionando/embarcando ao mesmo tempo (pedido
# explicito do usuario: "a ideia e ir outro concomitante"), entao o controle
# e um CONTADOR (_active_tap_count), nao um bool travado por uma unica
# corrotina -- ver _begin_tap_animation/_end_tap_animation.
var is_animating: bool = false
var _active_tap_count: int = 0
var current_level_number: int = 1
var available_levels: Array[int] = []
var _blocked_tap_count: int = 0
var last_stars_earned: int = -1
var _queue_dolls: Array[PassengerController] = []
var _queue_reveal_count: int = 0
var _camera_base_size: float = 14.0
var _camera_base_position: Vector3 = Vector3.ZERO
var _camera_shake_tween: Tween

func _ready() -> void:
	hud.restart_requested.connect(restart_level)
	hud.continue_requested.connect(_on_continue_requested)
	hud.hint_requested.connect(_on_hint_requested)

# Chamado pelo AppRouter logo depois de instanciar a cena do jogo (etapa 9:
# Home/Mapa decidem qual fase abrir, o jogo nao carrega mais sozinho no
# _ready). Mantem o antigo comportamento de _ready para quem chamar direto.
func start_level(level_number: int) -> void:
	available_levels = _discover_levels()
	current_level_number = level_number
	_load_level_number(current_level_number)

func restart_level() -> void:
	if is_animating:
		return
	_load_level_number(current_level_number)

# O botao do modal de vitoria agora volta pro Mapa de fases (decisao da
# etapa 9) em vez de carregar a proxima fase no lugar.
func _on_continue_requested() -> void:
	if is_animating:
		return
	AppRouter.go_map()

func _discover_levels() -> Array[int]:
	var result: Array[int] = []
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		return [1]
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("level_") and file_name.ends_with(".json"):
			var number_text: String = file_name.trim_prefix("level_").trim_suffix(".json")
			if number_text.is_valid_int():
				result.append(number_text.to_int())
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	if result.is_empty():
		result.append(1)
	return result

func _level_path(level_number: int) -> String:
	return "%s/%s" % [LEVEL_DIR, LEVEL_PATTERN % level_number]

func _load_level_number(level_number: int) -> void:
	_clear_all_visuals()
	_reset_scene_saturation()
	_blocked_tap_count = 0
	_active_tap_count = 0
	is_animating = false
	_vehicle_slot_markers.clear()
	last_stars_earned = -1
	if available_levels.has(level_number):
		var path: String = _level_path(level_number)
		level = _load_level_from_json(path)
		if level == null:
			push_error("Nao foi possivel carregar %s. Usando fase de emergencia." % path)
			level = _fallback_level()
			current_level_number = level.id
	else:
		# Pacote de fases prontas esgotado: gera a proxima fase proceduralmente,
		# sempre jogavel (validada internamente) e um pouco mais dificil que a
		# anterior.
		level = LevelGenerator.generate(level_number)
	state = GameEngine.create_state(level)
	board.setup(state.board_rows, state.board_cols, CELL_SIZE)
	environment.setup(state.board_rows, state.board_cols, CELL_SIZE)
	_setup_boarding_area()
	_rebuild_queue_dolls()
	_spawn_vehicles()
	_refresh_selectable_highlights()
	_setup_camera()
	hud.update_state(state, "Toque em um veiculo livre.", _level_position_text(), -1)
	print("Pega Passageiro - fase %s carregada." % state.level_id)

func _level_position_text() -> String:
	var index: int = available_levels.find(current_level_number)
	if index < 0:
		# Fase gerada proceduralmente: nao ha um total fixo, o jogo continua
		# sempre com uma fase nova.
		return "Fase %d" % current_level_number
	return "%d/%d" % [index + 1, available_levels.size()]

func _load_level_from_json(path: String) -> LevelDefinition:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var raw: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON de fase invalido: %s" % path)
		return null
	return LevelDefinition.from_dictionary(parsed as Dictionary)

func _fallback_level() -> LevelDefinition:
	return LevelDefinition.new(
		1,
		5,
		8,
		7,
		["red", "red", "blue", "blue", "green", "green", "yellow", "yellow"],
		[
			VehicleDefinition.new("red_car", "car", "red", 2, 5, 2, "horizontal", "left"),
			VehicleDefinition.new("blue_car", "car", "blue", 2, 2, 3, "vertical", "up"),
			VehicleDefinition.new("green_car", "car", "green", 2, 4, 4, "vertical", "down"),
			VehicleDefinition.new("yellow_car", "car", "yellow", 2, 1, 2, "horizontal", "right"),
		]
	)

func _spawn_vehicles() -> void:
	for child: Node in vehicles_root.get_children():
		child.free()
	vehicle_nodes.clear()
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		var vehicle_node := preload("res://scenes/game/Vehicle.tscn").instantiate() as VehicleController
		vehicles_root.add_child(vehicle_node)
		vehicle_node.setup_from_state(vehicle, CELL_SIZE)
		vehicle_node.pressed.connect(_on_vehicle_pressed)
		vehicle_nodes[vehicle_id] = vehicle_node

# Passo 9 (animacoes secundarias): brilho suave nos veiculos que podem sair
# agora. Reaproveita GameEngine.can_vehicle_exit -- a MESMA funcao pura que
# ja decide bloqueio no toque -- entao o indicador nunca diverge da regra
# real. So leitura de estado; nao muda nada em GameEngine nem em state.
func _refresh_selectable_highlights() -> void:
	for vehicle_id: String in vehicle_nodes.keys():
		var vehicle_node: VehicleController = vehicle_nodes[vehicle_id] as VehicleController
		if vehicle_node == null:
			continue
		var vehicle: VehicleState = state.vehicles.get(vehicle_id) as VehicleState
		if vehicle == null or vehicle.status != VehicleState.ON_BOARD:
			vehicle_node.set_selectable(false)
			continue
		vehicle_node.set_selectable(GameEngine.can_vehicle_exit(state, vehicle_id)["can_exit"])

# Ponto de entrada de TODO toque em veiculo. NAO serializa mais: se um
# veiculo valido e tocado enquanto outro ja esta andando/estacionando/
# embarcando, os dois processam em PARALELO (pedido explicito: "a ideia e
# ir outro concomitante"). _process_vehicle_tap e uma corrotina; chama-la
# sem serializar so funciona porque cada uma so mexe no que e dela ate o
# primeiro "await" (a mutacao do estado logico e sincrona, sempre antes de
# qualquer animacao), entao duas chamadas concorrentes nunca correm o risco
# de pegar a mesma vaga ou o mesmo passageiro -- ver comentarios dentro de
# _process_vehicle_tap e _reserve_boarding_dolls.
func _on_vehicle_pressed(vehicle_id: String) -> void:
	if state.status != GameState.PLAYING:
		return
	await _process_vehicle_tap(vehicle_id)

func _begin_tap_animation() -> void:
	_active_tap_count += 1
	is_animating = true

func _end_tap_animation() -> void:
	_active_tap_count = maxi(_active_tap_count - 1, 0)
	is_animating = _active_tap_count > 0

# Processa UM toque. Pode rodar ao mesmo tempo que outras chamadas desta
# mesma funcao (uma por veiculo tocado) -- ver nota em _on_vehicle_pressed.
func _process_vehicle_tap(vehicle_id: String) -> void:
	var vehicle_node: VehicleController = vehicle_nodes.get(vehicle_id) as VehicleController
	if vehicle_node == null:
		return
	# Rede de seguranca: com toques concorrentes, um segundo toque no MESMO
	# veiculo (antes da primeira animacao dele terminar) chega aqui depois
	# que o primeiro ja mudou o status dele pra WAITING/COMPLETE. Sem isto,
	# GameEngine devolveria "VehicleUnavailable" -- nem bloqueado nem
	# sem-vaga -- e o codigo cairia sem querer no caminho de sucesso.
	var vehicle_state: VehicleState = state.vehicles.get(vehicle_id) as VehicleState
	if vehicle_state == null or vehicle_state.status != VehicleState.ON_BOARD:
		return

	var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, vehicle_id)
	var events: Array = result["events"]
	var blocked: bool = _has_event(events, "VehicleBlocked")
	var no_slot: bool = _has_event(events, "NoWaitingSlotAvailable")

	if blocked:
		_blocked_tap_count += 1
		vehicle_node.animate_blocked()
		_camera_shake_blocked()
		AudioManager.play_sfx("blocked")
		AudioManager.vibrate(45)
		hud.update_state(state, "Esse veiculo esta bloqueado.", _level_position_text())
		return
	if no_slot:
		vehicle_node.animate_no_slot()
		AudioManager.vibrate(35)
		hud.update_state(state, "As vagas de espera estao ocupadas.", _level_position_text())
		return

	_begin_tap_animation()
	vehicle_node.animate_valid_tap()
	_camera_pulse_valid_tap()
	AudioManager.play_sfx("tap_valid")
	AudioManager.vibrate(18)

	# O estado logico (inclusive quais passageiros embarcam) e confirmado
	# AQUI, de forma sincrona -- antes do primeiro "await" desta funcao.
	# Isso e o que garante que dois veiculos tocados em sequencia rapida
	# nunca disputam a mesma vaga de espera nem o mesmo passageiro da fila,
	# mesmo que suas animacoes depois rodem juntas.
	state = result["state"]
	var boarding_dolls: Array[PassengerController] = _reserve_boarding_dolls(events)
	var slot_index: int = _state_slot_index(vehicle_id)
	if slot_index < 0:
		slot_index = _event_slot_index(events, vehicle_id)
	var route: Array[Vector3] = _build_route_to_waiting_slot(vehicle_node, slot_index)
	hud.show_message("Veiculo a caminho dos passageiros...")
	AudioManager.play_sfx("car_driving")
	await vehicle_node.drive_route(route)
	# Snap final em coordenada GLOBAL. Mesmo que algum ponto intermediario use
	# coordenadas locais, o carro termina exatamente no Marker3D do slot.
	var final_marker: Marker3D = _boarding_slot_marker(slot_index)
	if final_marker != null:
		vehicle_node.global_position = final_marker.global_position
		_vehicle_slot_markers[vehicle_id] = final_marker
		# Numero regressivo aparece no instante em que o carro encosta na vaga
		# (ainda ninguem embarcou -- os PassengerBoarded desta leva so tocam
		# durante _play_boarding_events logo abaixo, e cada um atualiza este
		# mesmo numero com o valor real do evento).
		var parked_vehicle: VehicleState = state.vehicles.get(vehicle_id) as VehicleState
		if parked_vehicle != null:
			_set_slot_label_text(final_marker, str(maxi(parked_vehicle.capacity - parked_vehicle.occupied_seats, 0)))
			vehicle_node.set_waiting_slot_mode(true)
	AudioManager.play_sfx("car_parking")
	AudioManager.vibrate(22)

	# Agora reproduzimos PassengerBoarded/SlotFreed na ordem dos eventos do motor.
	await _play_boarding_events(events, boarding_dolls)

	if _has_event(events, "Win"):
		AudioManager.play_sfx("win")
		var coins_awarded: int = Wallet.award_win_bonus()
		hud.play_coin_reward(coins_awarded)
		_spawn_win_particles()
		_camera_zoom_out_for_win()
		last_stars_earned = _stars_for_run()
		ProgressService.report_level_result(current_level_number, last_stars_earned)
	elif _has_event(events, "GameOver"):
		AudioManager.play_sfx("game_over")
		AudioManager.vibrate(40)
		_apply_game_over_desaturation()

	_refresh_selectable_highlights()
	hud.update_state(state, _message_from_events(events), _level_position_text(), last_stars_earned)
	_end_tap_animation()

# Criterio de estrelas (etapa 9, decisao confirmada): baseado em quantas
# vezes o jogador tocou num veiculo bloqueado durante a fase.
func _stars_for_run() -> int:
	if _blocked_tap_count <= 0:
		return 3
	if _blocked_tap_count <= 2:
		return 2
	return 1

# Dica (etapa 9, decisao confirmada): gasta moedas de verdade pela primeira
# vez no jogo e destaca um veiculo com uma jogada valida.
func _on_hint_requested() -> void:
	if is_animating or state == null or state.status != GameState.PLAYING:
		return
	if not Wallet.spend_coins(HINT_COST):
		hud.show_message("Moedas insuficientes para a dica.")
		return
	var target_id: String = _find_hint_vehicle_id()
	if target_id == "":
		Wallet.add_coins(HINT_COST)
		hud.show_message("Nenhuma jogada disponivel agora.")
		return
	var vehicle_node: VehicleController = vehicle_nodes.get(target_id) as VehicleController
	if vehicle_node != null:
		vehicle_node.animate_hint()
	AudioManager.play_sfx("coin")
	hud.show_message("Toque no veiculo destacado.")

func _find_hint_vehicle_id() -> String:
	var front_color: String = state.get_front_passenger_color()
	var fallback_id: String = ""
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		if not GameEngine.can_vehicle_exit(state, vehicle_id)["can_exit"]:
			continue
		if vehicle.color_id == front_color:
			return vehicle_id
		if fallback_id == "":
			fallback_id = vehicle_id
	return fallback_id

func _state_slot_index(vehicle_id: String) -> int:
	# Fonte definitiva para o visual: o estado atual do motor. Isso evita que
	# qualquer evento intermediario/ordem de animacao mande dois carros ao mesmo slot.
	for slot: WaitingSlotState in state.waiting_slots:
		if slot.vehicle_id == vehicle_id:
			return slot.index
	return -1

func _boarding_slot_marker(slot_index: int) -> Marker3D:
	return boarding_area.get_node_or_null("Slot%d" % slot_index) as Marker3D

# Atualiza o Label3D "SlotLabel" (contador regressivo) de UMA vaga especifica.
# Texto vazio = vaga livre (sem numero flutuando a toa sobre o asfalto).
func _set_slot_label_text(marker: Marker3D, text: String) -> void:
	if marker == null:
		return
	var label: Label3D = marker.get_node_or_null("SlotLabel") as Label3D
	if label != null:
		label.text = text
	var plus_label: Label3D = marker.get_node_or_null("SlotPlus") as Label3D
	if plus_label != null:
		plus_label.visible = text == ""

func _event_slot_index(events: Array, vehicle_id: String) -> int:
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == "VehicleParked" and String(event.payload.get("vehicle_id", "")) == vehicle_id:
			return int(event.payload.get("slot_index", 0))
	return 0

func _setup_boarding_area() -> void:
	# Faixa de embarque fisica: os slots continuam sendo definidos pela regra,
	# mas agora existe uma plataforma/rua visivel no mesmo mundo 3D. Isso tira
	# a sensacao de "carros flutuando acima do tabuleiro" e prepara o caminho
	# para passageiros correndo ate as portas.
	for child: Node in boarding_area.get_children():
		child.free()

	var count: int = maxi(state.waiting_slots.size(), 1)
	var board_width: float = float(state.board_cols) * CELL_SIZE
	var spacing: float = minf(1.48, (board_width - 0.9) / float(count))
	var total_span: float = spacing * float(count - 1)
	var first_x: float = board_width * 0.5 - total_span * 0.5
	var slot_z: float = -0.48

	# Plataforma clara e pista de acesso escura, ambas apenas visuais.
	_add_boarding_box(
		"Platform",
		Vector3(board_width + 0.65, 0.06, 1.26),
		Vector3(board_width * 0.5, 0.01, -0.50),
		Color("#ded3ba")
	)
	_add_boarding_box(
		"AccessLane",
		Vector3(board_width + 0.65, 0.035, 0.38),
		Vector3(board_width * 0.5, 0.035, -0.94),
		Color("#5b6b86")
	)

	# Faixa tracejada dourada no centro da pista (mesma cor de destaque usada
	# nas saidas do tabuleiro), em vez de uma linha branca solida.
	var lane_segment_count := 5
	var lane_span := board_width * 0.78
	for lane_index: int in range(lane_segment_count):
		var lane_t: float = (float(lane_index) - float(lane_segment_count - 1) * 0.5) / float(lane_segment_count)
		_add_boarding_box(
			"LaneLine%d" % lane_index,
			Vector3(lane_span / float(lane_segment_count) * 0.55, 0.018, 0.045),
			Vector3(board_width * 0.5 + lane_span * lane_t, 0.06, -0.94),
			Color("#ffd233")
		)

	# Ponto onde os passageiros "nascem" visualmente antes de caminhar.
	var queue_start := Marker3D.new()
	queue_start.name = "PassengerQueueStart"
	queue_start.position = Vector3(board_width * 0.5, 0.20, -1.28)
	boarding_area.add_child(queue_start)

	# Letreiros (Label3D com billboard, sempre de frente pra camera): dao
	# nome as duas areas e reforcam a leitura de "estacao profissional" em
	# vez de uma faixa generica. Puramente decorativos, sem Control/HUD.
	# A fila principal agora esta no HUD. Mantemos apenas um titulo discreto na area 3D.
	_add_boarding_label("BoardingAreaLabel", "EMBARQUE", Vector3(board_width * 0.5, 0.88, -0.58), 24)

	for index: int in range(count):
		var marker := Marker3D.new()
		marker.name = "Slot%d" % index
		marker.position = Vector3(first_x + spacing * float(index), 0.31, slot_z)
		boarding_area.add_child(marker)

		# Moldura sob o piso claro (mesma tecnica de _add_floor/_add_floor_shadow
		# do BoardController: uma caixa mais larga e um pouco mais baixa, com
		# uma folga pequena entre as duas pra nao dar z-fighting). A largura
		# some com base em "spacing" pra nunca invadir a vaga vizinha mesmo em
		# fases com slots mais apertados.
		var frame_width: float = minf(1.34, spacing * 0.94)
		var frame := MeshInstance3D.new()
		frame.name = "Frame"
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3(frame_width, 0.02, 1.02)
		frame.mesh = frame_mesh
		frame.position = Vector3(0.0, -0.32, 0.0)
		var frame_material := StandardMaterial3D.new()
		frame_material.albedo_color = Color("#7d8aa0")
		frame_material.roughness = 0.85
		frame.material_override = frame_material
		marker.add_child(frame)

		# Base maior e mais legivel, com linha clara na frente e separadores.
		var pad := MeshInstance3D.new()
		pad.name = "Pad"
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(minf(1.16, frame_width - 0.08), 0.026, 0.92)
		pad.mesh = pad_mesh
		pad.position = Vector3(0.0, -0.285, 0.0)
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color("#41516b")
		pad_material.roughness = 0.9
		pad.material_override = pad_material
		marker.add_child(pad)

		var stop_line := MeshInstance3D.new()
		var stop_mesh := BoxMesh.new()
		stop_mesh.size = Vector3(0.88, 0.018, 0.035)
		stop_line.mesh = stop_mesh
		stop_line.position = Vector3(0.0, -0.258, -0.30)
		var stop_material := StandardMaterial3D.new()
		stop_material.albedo_color = Color("#87f7aa")
		stop_line.material_override = stop_material
		marker.add_child(stop_line)

		# Numero da vaga, alto o suficiente pra continuar visivel mesmo com um
		# onibus estacionado ali (collider_height do onibus e 1.1). Sempre de
		# frente pra camera -- e a resposta direta ao pedido de "vagas fisicas,
		# nao so quadrados de HUD": agora cada vaga tem identidade propria no
		# mundo 3D, alem do card que ja existia no HUD.
		# Comeca vazio (vaga livre = sem numero); vira o contador regressivo
		# real assim que um veiculo estaciona ali (ver _process_vehicle_tap /
		# _play_boarding_events / _set_slot_label_text). Fonte bem maior e
		# contorno grosso pra ler de longe -- e ESTE numero que representa a
		# quantidade de passageiros que faltam pro carro, direto em cima dele.
		var slot_label := Label3D.new()
		slot_label.name = "SlotLabel"
		slot_label.text = ""
		slot_label.font_size = 46
		slot_label.outline_size = 14
		slot_label.modulate = Color.WHITE
		slot_label.outline_modulate = Color(0.12, 0.15, 0.2, 0.9)
		slot_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot_label.no_depth_test = true
		slot_label.position = Vector3(0.0, 0.62, 0.46)
		marker.add_child(slot_label)

		# Sinal de vaga livre, inspirado no layout de referencia. Some quando um
		# veiculo estaciona e volta quando a vaga e liberada.
		var slot_plus := Label3D.new()
		slot_plus.name = "SlotPlus"
		slot_plus.text = "+"
		slot_plus.font_size = 44
		slot_plus.outline_size = 10
		slot_plus.modulate = Color("#63ef91")
		slot_plus.outline_modulate = Color(0.08, 0.16, 0.12, 0.85)
		slot_plus.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot_plus.no_depth_test = true
		slot_plus.position = Vector3(0.0, 0.42, 0.02)
		marker.add_child(slot_plus)

func _add_boarding_box(name_text: String, box_size: Vector3, box_position: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name_text
	var box := BoxMesh.new()
	box.size = box_size
	mesh_instance.mesh = box
	mesh_instance.position = box_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	mesh_instance.material_override = material
	boarding_area.add_child(mesh_instance)

# Letreiro simples da area de embarque (Label3D com billboard), reaproveitado
# tanto para o titulo "PASSAGEIROS" quanto para "ESTACAO DE EMBARQUE". Sem
# acento nas strings porque a fonte padrao do projeto ja e usada assim em
# outros textos gerados por script (ver HUDController).
func _add_boarding_label(name_text: String, label_text: String, label_position: Vector3, size: int) -> void:
	var label := Label3D.new()
	label.name = name_text
	label.text = label_text
	label.font_size = size
	label.outline_size = size - 16
	label.modulate = Color("#2b3550")
	label.outline_modulate = Color(1.0, 1.0, 1.0, 0.92)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = label_position
	boarding_area.add_child(label)

func _boarding_slot_position(slot_index: int) -> Vector3:
	var marker: Marker3D = _boarding_slot_marker(slot_index)
	if marker != null:
		# VehicleController.position e todos os pontos usados por drive_route()
		# estao no espaco LOCAL de Vehicles. O Marker3D pertence a BoardingArea,
		# portanto nunca misturamos marker.global_position diretamente com
		# vehicle.position. A conversao explicita elimina o deslocamento que fazia
		# o segundo carro terminar atras/sobre o primeiro.
		return vehicles_root.to_local(marker.global_position)
	# Fallback defensivo ja no mesmo espaco local de Vehicles.
	var fallback_world := boarding_area.to_global(Vector3(float(state.board_cols) * CELL_SIZE * 0.5, 0.31, -0.52))
	return vehicles_root.to_local(fallback_world)

func _build_route_to_waiting_slot(vehicle_node: VehicleController, slot_index: int) -> Array[Vector3]:
	var route: Array[Vector3] = []
	var rows_depth: float = float(state.board_rows) * CELL_SIZE
	var cols_width: float = float(state.board_cols) * CELL_SIZE
	var margin: float = 0.72
	var lane_z: float = -0.78
	var stage: Vector3 = vehicle_node.position

	# Primeiro o veiculo realmente sai do tabuleiro pela direcao autorizada
	# (a mesma ExitDirection.Value que o GameEngine ja validou -- nunca a
	# rotacao visual).
	match vehicle_node.exit_direction:
		ExitDirection.Value.UP:
			stage.z = lane_z
		ExitDirection.Value.DOWN:
			stage.z = rows_depth + margin
		ExitDirection.Value.LEFT:
			stage.x = -margin
		ExitDirection.Value.RIGHT:
			stage.x = cols_width + margin
	route.append(stage)

	# IMPORTANTE: slot_position ja esta convertido para o espaco local de
	# Vehicles, exatamente o mesmo espaco de vehicle_node.position.
	var slot_position: Vector3 = _boarding_slot_position(slot_index)

	# Depois entra numa faixa comum de embarque. O ultimo ponto e SEMPRE o
	# Marker3D do slot logico convertido para o espaco correto.
	if vehicle_node.exit_direction == ExitDirection.Value.DOWN:
		var side_x: float = -margin
		if vehicle_node.position.x >= cols_width * 0.5:
			side_x = cols_width + margin
		route.append(Vector3(side_x, 0.31, rows_depth + margin))
		route.append(Vector3(side_x, 0.31, lane_z))
	elif vehicle_node.exit_direction == ExitDirection.Value.LEFT:
		route.append(Vector3(-margin, 0.31, lane_z))
	elif vehicle_node.exit_direction == ExitDirection.Value.RIGHT:
		route.append(Vector3(cols_width + margin, 0.31, lane_z))

	route.append(Vector3(slot_position.x, 0.31, lane_z))
	route.append(slot_position)
	return route

# reserved_dolls: os bonecos que vao embarcar NESTA leva, na MESMA ordem dos
# eventos "PassengerBoarded" -- ja escolhidos por _reserve_boarding_dolls()
# no instante do toque (sincrono), nao aqui. Isso importa porque agora
# varios veiculos podem estar animando ao mesmo tempo (varios toques
# concorrentes): se o boneco so fosse escolhido AQUI (quando a animacao de
# CADA carro finalmente chega nesse ponto), um carro que demorasse mais pra
# chegar podia acabar roubando visualmente o boneco que logicamente ja
# tinha embarcado em outro carro que chegou primeiro.
func _play_boarding_events(events: Array, reserved_dolls: Array[PassengerController]) -> void:
	var doll_cursor := 0
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event == null:
			continue
		if event.type == "PassengerBoarded":
			var boarded_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var target_vehicle: VehicleController = vehicle_nodes.get(boarded_vehicle_id) as VehicleController
			var passenger: PassengerController = reserved_dolls[doll_cursor] if doll_cursor < reserved_dolls.size() else null
			doll_cursor += 1
			if target_vehicle == null or passenger == null or not is_instance_valid(passenger):
				continue
			var color_id: String = String(event.payload.get("color_id", "red"))
			await passenger.walk_to_and_board(target_vehicle.get_boarding_point())
			target_vehicle.animate_boarding_bounce()
			AudioManager.play_sfx("passenger_board")
			_spawn_boarding_spark(target_vehicle.get_boarding_point(), color_id)
			# Contador regressivo no proprio carro: sempre o numero real do
			# evento (capacity - occupied_seats), nunca reconsultado depois --
			# assim continua certo mesmo com varios veiculos animando juntos.
			var remaining: int = maxi(int(event.payload.get("capacity", 0)) - int(event.payload.get("occupied_seats", 0)), 0)
			var boarding_marker: Marker3D = _vehicle_slot_markers.get(boarded_vehicle_id) as Marker3D
			if boarding_marker != null:
				_set_slot_label_text(boarding_marker, str(remaining))
		elif event.type == "SlotFreed":
			var completed_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var completed_node: VehicleController = vehicle_nodes.get(completed_vehicle_id) as VehicleController
			var freed_marker: Marker3D = _vehicle_slot_markers.get(completed_vehicle_id) as Marker3D
			if freed_marker != null:
				_set_slot_label_text(freed_marker, "")
			_vehicle_slot_markers.erase(completed_vehicle_id)
			if completed_node != null:
				AudioManager.play_sfx("vehicle_complete")
				AudioManager.vibrate(30)
				_spawn_vehicle_complete_burst(completed_node.global_position, completed_node.color_id)
				completed_node.set_waiting_slot_mode(false)
				AudioManager.play_sfx("car_driving")
				await completed_node.drive_away_from_pickup(float(state.board_cols) * CELL_SIZE)
				completed_node.queue_free()
				vehicle_nodes.erase(completed_vehicle_id)

# Chamada SINCRONA, no instante do toque (antes de qualquer await em
# _process_vehicle_tap) -- reserva, na ordem certa, um boneco 3D real da
# fila para cada evento "PassengerBoarded" desta leva, e ja tira esses
# bonecos de _queue_dolls. Isso e o que garante a identidade certa mesmo com
# varios veiculos animando ao mesmo tempo: quem reserva primeiro (ordem real
# dos toques) fica com os bonecos da frente, nao quem termina de andar
# primeiro.
func _reserve_boarding_dolls(events: Array) -> Array[PassengerController]:
	var reserved: Array[PassengerController] = []
	var popped_any := false
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == "PassengerBoarded":
			var color_id: String = String(event.payload.get("color_id", "red"))
			reserved.append(_pop_front_queue_doll(color_id))
			popped_any = true
	if popped_any:
		_advance_queue_dolls()
	return reserved

# --- Passageiros 3D esperando perto das vagas ---
# Em vez de resumir a fila no topo da HUD, mostramos pessoas reais no mundo.
# A ordem visual continua sendo a mesma ordem logica de state.passenger_queue.
# Ate 40 ficam visiveis de uma vez, exatamente a capacidade maxima oficial.

func _queue_slot_position(slot_index: int) -> Vector3:
	var queue_marker: Marker3D = boarding_area.get_node_or_null("PassengerQueueStart") as Marker3D
	var base_local: Vector3
	if queue_marker != null:
		base_local = passengers_root.to_local(queue_marker.global_position)
	else:
		base_local = Vector3(float(state.board_cols) * CELL_SIZE * 0.5, 0.20, -1.28)

	# Grade compacta centralizada: 10 pessoas por linha, ate 4 linhas para um
	# onibus de 40 lugares. A primeira linha fica mais perto dos carros.
	var column: int = slot_index % CROWD_COLUMNS
	var row: int = slot_index / CROWD_COLUMNS
	var row_count: int = mini(CROWD_COLUMNS, MAX_VISIBLE_QUEUE_DOLLS - row * CROWD_COLUMNS)
	var row_width: float = float(maxi(row_count - 1, 0)) * CROWD_COLUMN_SPACING
	var x_offset: float = float(column) * CROWD_COLUMN_SPACING - row_width * 0.5
	var z_offset: float = -float(row) * CROWD_ROW_SPACING
	return base_local + Vector3(x_offset, 0.0, z_offset)

func _rebuild_queue_dolls() -> void:
	for doll: PassengerController in _queue_dolls:
		if is_instance_valid(doll):
			doll.free()
	_queue_dolls.clear()
	_queue_reveal_count = mini(level.passengers.size(), MAX_VISIBLE_QUEUE_DOLLS)
	for index: int in range(_queue_reveal_count):
		_queue_dolls.append(_spawn_queue_doll(index, level.passengers[index]))

func _spawn_queue_doll(spawn_index: int, color_id: String) -> PassengerController:
	var doll := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	passengers_root.add_child(doll)
	doll.setup(color_id)
	doll.position = _queue_slot_position(_queue_dolls.size())
	return doll

func _pop_front_queue_doll(color_id: String) -> PassengerController:
	if not _queue_dolls.is_empty():
		return _queue_dolls.pop_front()
	var fallback := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	passengers_root.add_child(fallback)
	fallback.setup(color_id)
	fallback.position = _queue_slot_position(0)
	return fallback

func _advance_queue_dolls() -> void:
	# Cada passageiro restante avanca para a proxima posicao livre da grade.
	for index: int in range(_queue_dolls.size()):
		var doll: PassengerController = _queue_dolls[index]
		if is_instance_valid(doll):
			doll.step_to(_queue_slot_position(index))

	# Reabastece a area visivel usando a fila logica completa da fase.
	while _queue_reveal_count < level.passengers.size() and _queue_dolls.size() < MAX_VISIBLE_QUEUE_DOLLS:
		var doll := _spawn_queue_doll(_queue_reveal_count, level.passengers[_queue_reveal_count])
		doll.pop_in()
		_queue_dolls.append(doll)
		_queue_reveal_count += 1

func _message_from_events(events: Array) -> String:
	if _has_event(events, "Win"):
		return "Fase concluida!"
	if _has_event(events, "GameOver"):
		return "Sem movimentos possiveis."
	if _has_event(events, "PassengerBoarded"):
		return "Passageiros embarcaram."
	if _has_event(events, "VehicleParked"):
		return "Veiculo aguardando sua cor."
	return "Escolha o proximo veiculo."

func _has_event(events: Array, event_type: String) -> bool:
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == event_type:
			return true
	return false

# VFX leve de embarque (etapa 10 - polimento): poucas particulas coloridas
# no ponto de embarque, sem asset novo (mesma tecnica procedural do
# confete de vitoria, so que menor e na cor do passageiro).
func _spawn_boarding_spark(spawn_position: Vector3, color_id: String) -> void:
	var color: Color = VehicleController.COLOR_MAP.get(color_id, Color.WHITE)
	for i: int in range(8):
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.045, 0.045, 0.045)
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.15, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		piece.material_override = material
		vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.6, 1.2), randf_range(-1.0, 1.0))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.55, 0.28)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.28)
		tween.tween_callback(piece.queue_free)

func _spawn_win_particles() -> void:
	AudioManager.vibrate(90)
	var center: Vector3 = board.get_board_center()
	for i: int in range(30):
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.09, 0.035, 0.15)
		piece.mesh = mesh
		piece.position = center + Vector3(randf_range(-1.4, 1.4), 1.1, randf_range(-0.9, 0.9))
		piece.rotation_degrees = Vector3(randf_range(0.0, 180.0), randf_range(0.0, 180.0), randf_range(0.0, 180.0))
		var material := StandardMaterial3D.new()
		material.albedo_color = [Color("#ff4b4b"), Color("#35de45"), Color("#ffd236"), Color("#2f91ff"), Color("#ff43c8"), Color("#ff7b20")][i % 6]
		piece.material_override = material
		vfx_root.add_child(piece)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + Vector3(randf_range(-2.4, 2.4), randf_range(1.4, 2.6), randf_range(-2.4, 2.4)), 0.45)
		tween.tween_property(piece, "position:y", 0.1, 0.5)
		tween.tween_callback(piece.queue_free)

func _spawn_vehicle_complete_burst(spawn_position: Vector3, color_id: String) -> void:
	var color: Color = VehicleController.COLOR_MAP.get(color_id, Color.WHITE)
	for i: int in range(14):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.05
		mesh.height = 0.05
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.2, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = material
		vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.7, 1.4), randf_range(-1.0, 1.0))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.75, 0.34)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.34)
		tween.tween_callback(piece.queue_free)

func _setup_camera() -> void:
	var center: Vector3 = board.get_board_center()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(CAMERA_PITCH_DEGREES, 0.0, 0.0)

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)

	# A camera olha de cima em angulo (CAMERA_PITCH_DEGREES). pitch_sin e a
	# taxa de conversao entre "size" (extensao vertical ortogonal) e
	# profundidade real no chao (Z); pitch_cos entra na relacao entre a altura
	# da camera e o quanto ela precisa se deslocar em Z pra um dado Z do mundo
	# cair numa fracao de tela especifica (ver _screen_fraction_for_z abaixo).
	var pitch_rad: float = deg_to_rad(CAMERA_PITCH_DEGREES)
	var pitch_sin: float = sin(pitch_rad)
	var pitch_cos: float = cos(pitch_rad)

	# Os dois "Z do mundo" que TEM que cair exatamente logo abaixo da faixa de
	# HUD de cima e logo acima da de baixo: nao e mais "as linhas do
	# tabuleiro", e sim "a area de embarque inteira" (que fica ANTES da linha
	# 0, ver BOARDING_AREA_DEPTH) ate "a ultima linha do tabuleiro + folga".
	# Tratar so as linhas do tabuleiro (sem contar a area de embarque) foi
	# exatamente o bug relatado: a plataforma/letreiros ficavam escondidos
	# atras do HUD de cima em fases com HUD maior.
	var top_z: float = -BOARDING_AREA_DEPTH
	var bottom_z: float = float(state.board_rows) * CELL_SIZE + BOARD_EDGE_MARGIN

	var top_fraction: float = HUD_TOP_UNSAFE_FRACTION + CAMERA_FRAME_SAFETY_FRACTION
	var bottom_fraction: float = 1.0 - HUD_BOTTOM_UNSAFE_FRACTION - CAMERA_FRAME_SAFETY_FRACTION

	var required_by_width: float = (float(state.board_cols) * CELL_SIZE + 2.7) / maxf(aspect, 0.35)
	# Tamanho minimo pra caber (area de embarque + tabuleiro + folga) exatamente
	# entre as duas fracoes de tela acima.
	var required_by_depth: float = absf(pitch_sin) * (bottom_z - top_z) / maxf(bottom_fraction - top_fraction, 0.01)
	camera.size = maxf(required_by_width, required_by_depth)

	# Ancora SEMPRE o topo da area de embarque (top_z) exatamente em
	# top_fraction, nunca centraliza pelo meio da tela: se "size" acabou maior
	# que o minimo (largura do tabuleiro mandou mais que profundidade), a
	# folga extra sobra embaixo -- nunca escondendo a area de embarque atras
	# do HUD de cima.
	camera.position = Vector3(center.x, center.y + CAMERA_HEIGHT, center.z)
	camera.position.z = top_z - (camera.size * (0.5 - top_fraction) + CAMERA_HEIGHT * pitch_cos) / pitch_sin
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.current = true
	_camera_base_size = camera.size
	_camera_base_position = camera.position

# --- Reacoes de camera (FASE D: game feel) ---
# Pequeno pulso de zoom-in ao confirmar um toque valido: reforca o feedback
# tatil sem mexer no enquadramento fixo usado pelo resto do jogo.
func _camera_pulse_valid_tap() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "size", _camera_base_size * 0.97, 0.06)
	tween.tween_property(camera, "size", _camera_base_size, 0.12)

# Pequeno "shake" horizontal ao tocar num veiculo bloqueado -- so a camera
# balanca; o tabuleiro e os veiculos continuam exatamente no lugar certo.
func _camera_shake_blocked() -> void:
	# O ramo de veiculo bloqueado nao usa is_animating (o jogador pode tocar
	# varias vezes seguidas rapido nele), entao um shake anterior ainda em
	# andamento e interrompido e a camera realinhada na base antes de comecar
	# o novo -- evita deriva acumulada de toques repetidos.
	if _camera_shake_tween != null and _camera_shake_tween.is_valid():
		_camera_shake_tween.kill()
	var base: Vector3 = _camera_base_position
	camera.position = base
	var tween := create_tween()
	_camera_shake_tween = tween
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "position", base + Vector3(0.18, 0.0, 0.0), 0.045)
	tween.tween_property(camera, "position", base + Vector3(-0.16, 0.0, 0.0), 0.045)
	tween.tween_property(camera, "position", base + Vector3(0.09, 0.0, 0.0), 0.045)
	tween.tween_property(camera, "position", base, 0.05)

# Pequeno zoom-out ao vencer a fase, pra "respirar" e mostrar o tabuleiro
# inteiro com o confete caindo antes do HUD de vitoria assumir a tela.
func _camera_zoom_out_for_win() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "size", _camera_base_size * 1.12, 0.5)

# --- Game Over (Fase F): reduz um pouco a saturacao da cena pra reforcar
# que a partida travou, sem escurecer a ponto de esconder o tabuleiro. A
# proxima fase (via restart) sempre reseta isso em _load_level_number().
func _apply_game_over_desaturation() -> void:
	var env: Environment = world_environment.environment
	if env == null:
		return
	env.adjustment_enabled = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(env, "adjustment_saturation", 0.42, 0.45)

func _reset_scene_saturation() -> void:
	var env: Environment = world_environment.environment
	if env == null:
		return
	env.adjustment_saturation = 1.0

func _clear_all_visuals() -> void:
	for root: Node3D in [vehicles_root, passengers_root, vfx_root]:
		for child: Node in root.get_children():
			child.free()
	vehicle_nodes.clear()
	_queue_dolls.clear()

