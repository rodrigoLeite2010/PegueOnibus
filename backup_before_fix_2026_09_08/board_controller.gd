class_name BoardController
extends Node3D

@export var rows: int = 9
@export var cols: int = 7
@export var cell_size: float = 1.0

func _ready() -> void:
	rebuild()

func setup(p_rows: int, p_cols: int, p_cell_size: float) -> void:
	rows = p_rows
	cols = p_cols
	cell_size = p_cell_size
	rebuild()

func rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	_add_floor_shadow()
	_add_floor()
	_add_grid_lines()
	_add_exit_gates()

func get_board_center() -> Vector3:
	return Vector3(cols * cell_size * 0.5, 0.0, rows * cell_size * 0.5)

func _add_floor_shadow() -> void:
	var shadow := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cols * cell_size + 0.72, 0.05, rows * cell_size + 0.72)
	shadow.mesh = mesh
	shadow.position = Vector3(cols * cell_size * 0.5, -0.15, rows * cell_size * 0.5 + 0.12)
	shadow.material_override = _make_material(Color("#9faec5"), 0.95)
	add_child(shadow)

func _add_floor() -> void:
	var floor_mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cols * cell_size + 0.38, 0.1, rows * cell_size + 0.38)
	floor_mesh_instance.mesh = mesh
	floor_mesh_instance.position = Vector3(cols * cell_size * 0.5, -0.06, rows * cell_size * 0.5)
	floor_mesh_instance.material_override = _make_material(Color("#d9e3f4"), 0.72)
	add_child(floor_mesh_instance)

func _add_grid_lines() -> void:
	for row: int in range(rows + 1):
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(cols * cell_size, 0.028, 0.026)
		line.mesh = mesh
		line.position = Vector3(cols * cell_size * 0.5, 0.025, row * cell_size)
		line.material_override = _make_material(Color("#ffffff"), 0.82)
		add_child(line)
	for col: int in range(cols + 1):
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.026, 0.028, rows * cell_size)
		line.mesh = mesh
		line.position = Vector3(col * cell_size, 0.027, rows * cell_size * 0.5)
		line.material_override = _make_material(Color("#ffffff"), 0.82)
		add_child(line)

func _add_exit_gates() -> void:
	var gate_material := _make_material(Color("#eef7ff"), 0.5)
	var gate_specs: Array[Dictionary] = [
		{"pos": Vector3(cols * cell_size * 0.5, 0.08, -0.18), "size": Vector3(1.8, 0.09, 0.16)},
		{"pos": Vector3(cols * cell_size * 0.5, 0.08, rows * cell_size + 0.18), "size": Vector3(1.8, 0.09, 0.16)},
		{"pos": Vector3(-0.18, 0.08, rows * cell_size * 0.5), "size": Vector3(0.16, 0.09, 1.8)},
		{"pos": Vector3(cols * cell_size + 0.18, 0.08, rows * cell_size * 0.5), "size": Vector3(0.16, 0.09, 1.8)},
	]
	for spec: Dictionary in gate_specs:
		var gate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = spec["size"]
		gate.mesh = mesh
		gate.position = spec["pos"]
		gate.material_override = gate_material
		add_child(gate)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
