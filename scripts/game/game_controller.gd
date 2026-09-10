class_name GameController
extends Node3D

const CELL_SIZE := 1.0
const LEVEL_DIR := "res://levels"
const LEVEL_PATTERN := "level_%03d.json"
const HINT_COST := 15

# --- Enquadramento da camera ---
# A HUD (CanvasLayer, 2D) fica sempre por cima da cena 3D, ocupando uma faixa
# fixa de tela (em pixels, no espaco de design 720x1280 do projeto) tanto no
# topo (TopPanel + SlotStrip) quanto embaixo (BottomPanel). O enquadramento da
# camera 3D precisa deixar o tabuleiro inteiro fora dessas faixas; antes disso
# nao acontecia (a camera usava um deslocamento fixo, calibrado so pra um
# tamanho de tabuleiro, e ignorava a atenuacao trigonometrica causada pela
# inclinacao da camera), o que deixava veiculos proximos da borda norte do
# tabuleiro escondidos atras da HUD em fases com outra proporcao de linhas.
const CAMERA_PITCH_DEGREES := -63.0
const CAMERA_HEIGHT := 14.5
const BOARD_EDGE_MARGIN := 0.85
const HUD_TOP_UNSAFE_FRACTION := 328.0 / 1280.0
const HUD_BOTTOM_UNSAFE_FRACTION := 190.0 / 1280.0

@onready var board: BoardController = $Board
@onready var vehicles_root: Node3D = $Vehicles
@onready var passengers_root: Node3D = $Passengers
@onready var vfx_root: Node3D = $VFX
@onready var boarding_area: Node3D = $BoardingArea
@onready var camera: Camera3D = $Camera3D
@onready var hud: HUDController = $HUD

var state: GameState
var level: LevelDefinition
var vehicle_nodes: Dictionary = {}
var is_animating: bool = false
var current_level_number: int = 1
var available_levels: Array[int] = []
var _blocked_tap_count: int = 0
var last_stars_earned: int = -1

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
	_blocked_tap_count = 0
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
	_setup_boarding_area()
	_spawn_vehicles()
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
		4,
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

func _on_vehicle_pressed(vehicle_id: String) -> void:
	if is_animating or state.status != GameState.PLAYING:
		return
	var vehicle_node: VehicleController = vehicle_nodes.get(vehicle_id) as VehicleController
	if vehicle_node == null:
		return

	var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, vehicle_id)
	var events: Array = result["events"]
	var blocked: bool = _has_event(events, "VehicleBlocked")
	var no_slot: bool = _has_event(events, "NoWaitingSlotAvailable")

	if blocked:
		_blocked_tap_count += 1
		vehicle_node.animate_blocked()
		AudioManager.play_sfx("blocked")
		AudioManager.vibrate(45)
		hud.update_state(state, "Esse veiculo esta bloqueado.", _level_position_text())
		return
	if no_slot:
		vehicle_node.animate_no_slot()
		AudioManager.vibrate(35)
		hud.update_state(state, "As vagas de espera estao ocupadas.", _level_position_text())
		return

	is_animating = true
	vehicle_node.animate_valid_tap()
	AudioManager.play_sfx("tap_valid")
	AudioManager.vibrate(18)

	# O estado logico e confirmado primeiro, mas o HUD so recebe o novo estado
	# depois que a animacao representa a acao. Assim a fila nao "teleporta".
	state = result["state"]
	var slot_index: int = _state_slot_index(vehicle_id)
	if slot_index < 0:
		slot_index = _event_slot_index(events, vehicle_id)
	var route: Array[Vector3] = _build_route_to_waiting_slot(vehicle_node, slot_index)
	hud.show_message("Veiculo a caminho dos passageiros...")
	await vehicle_node.drive_route(route)
	# Snap final em coordenada GLOBAL. Mesmo que algum ponto intermediario use
	# coordenadas locais, o carro termina exatamente no Marker3D do slot.
	var final_marker: Marker3D = _boarding_slot_marker(slot_index)
	if final_marker != null:
		vehicle_node.global_position = final_marker.global_position
	print("[BOARDING] %s -> slot %d | world=%s" % [vehicle_id, slot_index, str(vehicle_node.global_position)])

	# Agora reproduzimos PassengerBoarded/SlotFreed na ordem dos eventos do motor.
	await _play_boarding_events(events)

	if _has_event(events, "Win"):
		AudioManager.play_sfx("win")
		var coins_awarded: int = Wallet.award_win_bonus()
		hud.play_coin_reward(coins_awarded)
		_spawn_win_particles()
		last_stars_earned = _stars_for_run()
		ProgressService.report_level_result(current_level_number, last_stars_earned)
	elif _has_event(events, "GameOver"):
		AudioManager.play_sfx("game_over")

	is_animating = false
	hud.update_state(state, _message_from_events(events), _level_position_text(), last_stars_earned)

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
	var slot_z: float = -0.52

	# Plataforma clara e pista de acesso escura, ambas apenas visuais.
	_add_boarding_box(
		"Platform",
		Vector3(board_width + 0.65, 0.06, 1.40),
		Vector3(board_width * 0.5, 0.01, -0.55),
		Color("#dce8f6")
	)
	_add_boarding_box(
		"AccessLane",
		Vector3(board_width + 0.65, 0.035, 0.44),
		Vector3(board_width * 0.5, 0.035, -1.02),
		Color("#718097")
	)

	# Linha branca da pista.
	_add_boarding_box(
		"LaneLine",
		Vector3(board_width * 0.78, 0.018, 0.045),
		Vector3(board_width * 0.5, 0.06, -1.02),
		Color(1.0, 1.0, 1.0, 0.92)
	)

	# Ponto onde os passageiros "nascem" visualmente antes de caminhar.
	var queue_start := Marker3D.new()
	queue_start.name = "PassengerQueueStart"
	queue_start.position = Vector3(board_width * 0.5, 0.20, -1.34)
	boarding_area.add_child(queue_start)

	for index: int in range(count):
		var marker := Marker3D.new()
		marker.name = "Slot%d" % index
		marker.position = Vector3(first_x + spacing * float(index), 0.31, slot_z)
		boarding_area.add_child(marker)

		# Base maior e mais legivel, com linha clara na frente e separadores.
		var pad := MeshInstance3D.new()
		pad.name = "Pad"
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(1.22, 0.026, 0.76)
		pad.mesh = pad_mesh
		pad.position = Vector3(0.0, -0.285, 0.0)
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color("#aebdd0")
		pad_material.roughness = 0.9
		pad.material_override = pad_material
		marker.add_child(pad)

		var stop_line := MeshInstance3D.new()
		var stop_mesh := BoxMesh.new()
		stop_mesh.size = Vector3(0.92, 0.018, 0.045)
		stop_line.mesh = stop_mesh
		stop_line.position = Vector3(0.0, -0.258, -0.30)
		var stop_material := StandardMaterial3D.new()
		stop_material.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
		stop_line.material_override = stop_material
		marker.add_child(stop_line)

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

	# Primeiro o veiculo realmente sai do tabuleiro pela direcao autorizada.
	match vehicle_node.exit_direction:
		"up":
			stage.z = lane_z
		"down":
			stage.z = rows_depth + margin
		"left":
			stage.x = -margin
		"right":
			stage.x = cols_width + margin
	route.append(stage)

	# IMPORTANTE: slot_position ja esta convertido para o espaco local de
	# Vehicles, exatamente o mesmo espaco de vehicle_node.position.
	var slot_position: Vector3 = _boarding_slot_position(slot_index)

	# Depois entra numa faixa comum de embarque. O ultimo ponto e SEMPRE o
	# Marker3D do slot logico convertido para o espaco correto.
	if vehicle_node.exit_direction == "down":
		var side_x: float = -margin
		if vehicle_node.position.x >= cols_width * 0.5:
			side_x = cols_width + margin
		route.append(Vector3(side_x, 0.31, rows_depth + margin))
		route.append(Vector3(side_x, 0.31, lane_z))
	elif vehicle_node.exit_direction == "left":
		route.append(Vector3(-margin, 0.31, lane_z))
	elif vehicle_node.exit_direction == "right":
		route.append(Vector3(cols_width + margin, 0.31, lane_z))

	route.append(Vector3(slot_position.x, 0.31, lane_z))
	route.append(slot_position)
	return route

func _play_boarding_events(events: Array) -> void:
	var passenger_index: int = 0
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event == null:
			continue
		if event.type == "PassengerBoarded":
			var boarded_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var target_vehicle: VehicleController = vehicle_nodes.get(boarded_vehicle_id) as VehicleController
			if target_vehicle == null:
				continue
			var passenger := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
			passengers_root.add_child(passenger)
			passenger.setup(String(event.payload.get("color_id", "red")))
			passenger.position = _passenger_spawn_position(passenger_index, target_vehicle.position)
			passenger_index += 1
			await passenger.walk_to_and_board(target_vehicle.get_boarding_point())
			target_vehicle.animate_boarding_bounce()
			AudioManager.play_sfx("passenger_board")
			_spawn_boarding_spark(target_vehicle.get_boarding_point(), String(event.payload.get("color_id", "red")))
		elif event.type == "SlotFreed":
			var completed_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var completed_node: VehicleController = vehicle_nodes.get(completed_vehicle_id) as VehicleController
			if completed_node != null:
				AudioManager.play_sfx("vehicle_complete")
				await completed_node.drive_away_from_pickup(float(state.board_cols) * CELL_SIZE)
				completed_node.queue_free()
				vehicle_nodes.erase(completed_vehicle_id)

func _passenger_spawn_position(index: int, target_vehicle_position: Vector3) -> Vector3:
	# Origem visual fixa na area de embarque. Cada passageiro surge um pouco
	# atras/lateral do anterior e percorre a pista ate o BoardingPoint.
	var queue_marker: Marker3D = boarding_area.get_node_or_null("PassengerQueueStart") as Marker3D
	var base_local := Vector3(target_vehicle_position.x - 1.15, 0.20, target_vehicle_position.z - 0.78)
	if queue_marker != null:
		base_local = passengers_root.to_local(queue_marker.global_position)
	var lane_offset := Vector3(float(index % 4) * 0.22 - 0.33, 0.0, float(index / 4) * 0.15)
	return base_local + lane_offset

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

func _setup_camera() -> void:
	var center: Vector3 = board.get_board_center()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(CAMERA_PITCH_DEGREES, 0.0, 0.0)

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)

	# A camera olha de cima em angulo (CAMERA_PITCH_DEGREES), entao um mesmo
	# "size" (extensao vertical do enquadramento ortogonal) cobre menos
	# profundidade real no chao do que cobriria uma camera olhando reto pra
	# baixo. pitch_up_z e a projecao do "topo da tela" no eixo Z do mundo; sua
	# magnitude e o fator que converte size em profundidade de tabuleiro
	# coberta. pitch_cot relaciona a altura da camera com o quanto ela precisa
	# se deslocar no eixo Z pra manter o alvo (onde o centro da tela aponta).
	var pitch_rad: float = deg_to_rad(CAMERA_PITCH_DEGREES)
	var pitch_up_z: float = sin(pitch_rad)
	var pitch_cot: float = cos(pitch_rad) / pitch_up_z

	var safe_fraction: float = 1.0 - HUD_TOP_UNSAFE_FRACTION - HUD_BOTTOM_UNSAFE_FRACTION
	# Margem maior porque os PNGs atuais sao renders 3/4 e ultrapassam o footprint logico.
	var required_by_width: float = (float(state.board_cols) * CELL_SIZE + 2.7) / maxf(aspect, 0.35)
	var required_by_depth: float = (float(state.board_rows) * CELL_SIZE + 2.0 * BOARD_EDGE_MARGIN) / (absf(pitch_up_z) * safe_fraction)
	camera.size = maxf(required_by_width, required_by_depth)

	# Centraliza o tabuleiro na area LIVRE da tela (entre os paineis da HUD no
	# topo e o painel inferior), nao no centro geometrico da tela inteira -
	# senao o topo do tabuleiro pode ficar escondido atras da HUD em fases com
	# outro numero de linhas.
	var center_ray_z: float = absf(pitch_up_z) * camera.size * (0.5 - HUD_TOP_UNSAFE_FRACTION) - BOARD_EDGE_MARGIN
	var board_center_z: float = float(state.board_rows) * CELL_SIZE * 0.5
	var z_offset: float = (center_ray_z - board_center_z) - CAMERA_HEIGHT * pitch_cot

	camera.position = center + Vector3(0.0, CAMERA_HEIGHT, z_offset)
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.current = true

func _clear_all_visuals() -> void:
	for root: Node3D in [vehicles_root, passengers_root, vfx_root]:
		for child: Node in root.get_children():
			child.free()
	vehicle_nodes.clear()
