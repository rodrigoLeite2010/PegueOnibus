class_name VehiclePreviewController
extends Node3D

const CELL_SIZE := 1.0

const PREVIEW_ITEMS := [
	{"id": "pink_preview", "color_id": "pink", "rows": 2, "cols": 2, "row": 0, "col": 0, "direction": "right"},
	{"id": "orange_preview", "color_id": "orange", "rows": 3, "cols": 2, "row": 0, "col": 3, "direction": "down"},
	{"id": "blue_preview", "color_id": "blue", "rows": 2, "cols": 2, "row": 0, "col": 6, "direction": "left"},
	{"id": "green_preview", "color_id": "green", "rows": 3, "cols": 2, "row": 3, "col": 0, "direction": "up"},
	{"id": "yellow_preview", "color_id": "yellow", "rows": 2, "cols": 2, "row": 3, "col": 3, "direction": "right"},
	{"id": "red_preview", "color_id": "red", "rows": 3, "cols": 2, "row": 3, "col": 6, "direction": "down"},
	{"id": "purple_preview", "color_id": "purple", "rows": 2, "cols": 2, "row": 6, "col": 3, "direction": "left"},
]

@onready var camera: Camera3D = $Camera3D
@onready var board: BoardController = $Board
@onready var vehicles_root: Node3D = $Vehicles

func _ready() -> void:
	board.setup(8, 9, CELL_SIZE)
	_spawn_preview_vehicles()
	_setup_camera()
	print("Pega Passageiro - Preview de assets da etapa 7 carregado.")

func _spawn_preview_vehicles() -> void:
	for child: Node in vehicles_root.get_children():
		child.queue_free()
	for item: Dictionary in PREVIEW_ITEMS:
		var vehicle := VehicleState.new(
			item["id"],
			item["color_id"],
			4,
			int(item["rows"]),
			int(item["cols"]),
			int(item["row"]),
			int(item["col"]),
			item["direction"]
		)
		var vehicle_node := preload("res://scenes/game/Vehicle.tscn").instantiate() as VehicleController
		vehicle_node.setup_from_state(vehicle, CELL_SIZE)
		vehicles_root.add_child(vehicle_node)

func _setup_camera() -> void:
	var center := board.get_board_center()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.8
	camera.position = center + Vector3(0.0, 12.5, 6.8)
	camera.rotation_degrees = Vector3(-61.0, 0.0, 0.0)
	camera.current = true
