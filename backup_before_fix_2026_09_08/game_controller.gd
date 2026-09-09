class_name GameController
extends Node3D

const CELL_SIZE := 1.0

@onready var board: BoardController = $Board
@onready var vehicles_root: Node3D = $Vehicles
@onready var passengers_root: Node3D = $Passengers
@onready var vfx_root: Node3D = $VFX
@onready var camera: Camera3D = $Camera3D
@onready var hud: HUDController = $HUD

var state: GameState
var level: LevelDefinition
var vehicle_nodes: Dictionary = {}
var is_animating := false

func _ready() -> void:
	hud.restart_requested.connect(restart_level)
	_load_level()

func restart_level() -> void:
	if is_animating:
		return
	state = GameEngine.create_state(level)
	_spawn_vehicles()
	hud.update_state(state, "Fase reiniciada.")

func _load_level() -> void:
	level = LevelDefinition.new(
		1,
		3,
		10,
		7,
		["red", "red", "blue", "blue", "green", "green", "yellow", "yellow", "purple", "purple"],
		[
			VehicleDefinition.new("orange_van", "van", "orange", 4, 2, 0, "horizontal", "left", 1, 1),
			VehicleDefinition.new("blue_van", "van", "blue", 4, 3, 3, "horizontal", "right", 1, 1),
			VehicleDefinition.new("green_bus", "bus", "green", 6, 1, 5, "horizontal", "right", 1, 1),
			VehicleDefinition.new("red_car", "car", "red", 2, 6, 1, "horizontal", "left", 1, 1),
			VehicleDefinition.new("yellow_car", "car", "yellow", 2, 5, 4, "horizontal", "right", 1, 1),
			VehicleDefinition.new("purple_car", "car", "purple", 2, 7, 5, "horizontal", "right", 1, 1),
			VehicleDefinition.new("pink_car", "car", "pink", 2, 0, 3, "horizontal", "up", 1, 1),
		]
	)
	state = GameEngine.create_state(level)
	board.setup(state.board_rows, state.board_cols, CELL_SIZE)
	_spawn_vehicles()
	_setup_camera()
	hud.update_state(state, "Toque em um veiculo livre.")
	print("Pega Passageiro - Etapas 4 e 5 carregadas.")

func _spawn_vehicles() -> void:
	for child: Node in vehicles_root.get_children():
		child.queue_free()
	vehicle_nodes.clear()
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		var vehicle_node := preload("res://scenes/game/Vehicle.tscn").instantiate() as VehicleController
		vehicle_node.setup_from_state(vehicle, CELL_SIZE)
		vehicle_node.pressed.connect(_on_vehicle_pressed)
		vehicles_root.add_child(vehicle_node)
		vehicle_nodes[vehicle_id] = vehicle_node

func _on_vehicle_pressed(vehicle_id: String) -> void:
	if is_animating or state.status != GameState.PLAYING:
		return
	var vehicle_node: VehicleController = vehicle_nodes.get(vehicle_id) as VehicleController
	if vehicle_node == null:
		return

	vehicle_node.animate_valid_tap()
	Input.vibrate_handheld(18)
	var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, vehicle_id)
	var events: Array = result["events"]
	var blocked := _has_event(events, "VehicleBlocked")
	var no_slot := _has_event(events, "NoWaitingSlotAvailable")

	if blocked:
		vehicle_node.animate_blocked()
		Input.vibrate_handheld(55)
		hud.update_state(state, "Caminho bloqueado.")
		return
	if no_slot:
		hud.update_state(state, "Sem vaga livre.")
		return

	state = result["state"]
	is_animating = true
	vehicle_node.animate_exit()
	_spawn_boarding_passengers(events, vehicle_node.get_boarding_point())
	hud.update_state(state, _message_from_events(events))
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(vehicle_node):
		vehicle_node.queue_free()
	vehicle_nodes.erase(vehicle_id)
	if _has_event(events, "Win"):
		_spawn_win_particles()
	is_animating = false
	hud.update_state(state, _message_from_events(events))

func _message_from_events(events: Array) -> String:
	if _has_event(events, "Win"):
		return "Todos embarcaram!"
	if _has_event(events, "GameOver"):
		return "Os slots travaram."
	if _has_event(events, "PassengerBoarded"):
		return "Passageiros embarcando."
	if _has_event(events, "VehicleParked"):
		return "Veiculo no slot."
	return "Escolha o proximo veiculo."

func _has_event(events: Array, event_type: String) -> bool:
	for event: GameEvent in events:
		if event.type == event_type:
			return true
	return false

func _spawn_boarding_passengers(events: Array, target: Vector3) -> void:
	var count := 0
	for event: GameEvent in events:
		if event.type != "PassengerBoarded":
			continue
		var passenger := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
		passenger.setup(event.payload.get("color_id", "red"))
		passenger.position = _passenger_spawn_position(count)
		passengers_root.add_child(passenger)
		passenger.walk_to(target, float(count) * 0.07)
		count += 1

func _passenger_spawn_position(index: int) -> Vector3:
	var board_center := board.get_board_center()
	var lane_x := board_center.x - 1.7 + float(index % 5) * 0.34
	return Vector3(lane_x, 0.18, -0.78 - float(index) / 5.0 * 0.18)

func _spawn_win_particles() -> void:
	Input.vibrate_handheld(90)
	var center := board.get_board_center()
	for i: int in range(28):
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.09, 0.035, 0.15)
		piece.mesh = mesh
		piece.position = center + Vector3(randf_range(-1.2, 1.2), 1.1, randf_range(-0.8, 0.8))
		piece.rotation_degrees = Vector3(randf_range(0.0, 180.0), randf_range(0.0, 180.0), randf_range(0.0, 180.0))
		var material := StandardMaterial3D.new()
		material.albedo_color = [Color("#ff4b4b"), Color("#35de45"), Color("#ffd236"), Color("#2f91ff"), Color("#ff43c8")][i % 5]
		piece.material_override = material
		vfx_root.add_child(piece)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + Vector3(randf_range(-2.4, 2.4), randf_range(1.4, 2.6), randf_range(-2.4, 2.4)), 0.45)
		tween.tween_property(piece, "position:y", 0.1, 0.5)
		tween.tween_callback(piece.queue_free)

func _setup_camera() -> void:
	var center := board.get_board_center()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.6
	camera.position = center + Vector3(0.0, 13.0, 7.8)
	camera.rotation_degrees = Vector3(-62.0, 0.0, 0.0)
	camera.current = true
