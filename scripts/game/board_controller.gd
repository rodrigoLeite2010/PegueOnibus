class_name BoardController
extends Node3D

## Tabuleiro / patio de estacionamento: gera a base do jogo como uma pista
## de asfalto estilizada com meio-fio, vagas marcadas e saidas em destaque,
## em vez do retangulo branco original. Continua 100% procedural (sem
## depender de texturas ou assets externos) para nao pesar no mobile.

@export var rows: int = 8
@export var cols: int = 7
@export var cell_size: float = 1.0
@export var show_debug_grid := false

const COLOR_ASPHALT := Color("#667a99")
const COLOR_ASPHALT_SHADOW := Color("#344258")
const COLOR_CURB := Color("#eef1f6")
const COLOR_ACCENT := Color("#ffd233")
const COLOR_PARKING_LINE := Color(1.0, 1.0, 1.0, 0.16)

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
	_add_parking_markings()
	_add_border()
	if show_debug_grid:
		_add_grid_lines()
	_add_exit_gates()

func get_board_center() -> Vector3:
	return Vector3(cols * cell_size * 0.5, 0.0, rows * cell_size * 0.5)

func _add_floor_shadow() -> void:
	var shadow := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cols * cell_size + 0.72, 0.05, rows * cell_size + 0.72)
	shadow.mesh = mesh
	shadow.position = Vector3(cols * cell_size * 0.5, -0.17, rows * cell_size * 0.5 + 0.12)
	shadow.material_override = _make_material(COLOR_ASPHALT_SHADOW, 1.0)
	add_child(shadow)

func _add_floor() -> void:
	var floor_mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cols * cell_size + 0.34, 0.11, rows * cell_size + 0.34)
	floor_mesh_instance.mesh = mesh
	floor_mesh_instance.position = Vector3(cols * cell_size * 0.5, -0.07, rows * cell_size * 0.5)
	floor_mesh_instance.material_override = _make_material(COLOR_ASPHALT, 0.88)
	add_child(floor_mesh_instance)

# Linhas discretas de vaga (uma por divisa de coluna), para o tabuleiro ler
# como um estacionamento e nao como uma grade de planilha. Ficam sempre
# visiveis (diferente de _add_grid_lines, que e so uma ferramenta de debug).
func _add_parking_markings() -> void:
	var line_material := _make_material(COLOR_PARKING_LINE, 1.0)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for col: int in range(1, cols):
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.03, 0.02, rows * cell_size * 0.86)
		line.mesh = mesh
		line.position = Vector3(col * cell_size, 0.008, rows * cell_size * 0.5)
		line.material_override = line_material
		add_child(line)
	# Linhas na outra direcao (uma por divisa de linha), pra fechar o
	# desenho em uma grade completa de vagas -- antes so existiam as
	# divisoes de coluna, o que lia como "faixas" e nao "vagas delimitadas".
	# Mesmo material/opacidade das linhas de coluna, ainda mais discreta que
	# o grid de debug (show_debug_grid), que continua reservado para depuracao.
	for row: int in range(1, rows):
		var row_line := MeshInstance3D.new()
		var row_mesh := BoxMesh.new()
		row_mesh.size = Vector3(cols * cell_size * 0.86, 0.02, 0.03)
		row_line.mesh = row_mesh
		row_line.position = Vector3(cols * cell_size * 0.5, 0.008, row * cell_size)
		row_line.material_override = line_material
		add_child(row_line)

func _add_border() -> void:
	var border_material := _make_material(COLOR_CURB, 0.85)
	var width := cols * cell_size
	var depth := rows * cell_size
	var specs: Array[Dictionary] = [
		{"pos": Vector3(width * 0.5, 0.02, -0.13), "size": Vector3(width + 0.32, 0.05, 0.11)},
		{"pos": Vector3(width * 0.5, 0.02, depth + 0.13), "size": Vector3(width + 0.32, 0.05, 0.11)},
		{"pos": Vector3(-0.13, 0.02, depth * 0.5), "size": Vector3(0.11, 0.05, depth + 0.32)},
		{"pos": Vector3(width + 0.13, 0.02, depth * 0.5), "size": Vector3(0.11, 0.05, depth + 0.32)},
	]
	for spec: Dictionary in specs:
		var edge := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = spec["size"]
		edge.mesh = mesh
		edge.position = spec["pos"]
		edge.material_override = border_material
		add_child(edge)

func _add_grid_lines() -> void:
	var line_material := _make_material(Color(1, 1, 1, 0.38), 1.0)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for row: int in range(rows + 1):
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(cols * cell_size, 0.018, 0.018)
		line.mesh = mesh
		line.position = Vector3(cols * cell_size * 0.5, 0.005, row * cell_size)
		line.material_override = line_material
		add_child(line)
	for col: int in range(cols + 1):
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.018, 0.018, rows * cell_size)
		line.mesh = mesh
		line.position = Vector3(col * cell_size, 0.006, rows * cell_size * 0.5)
		line.material_override = line_material
		add_child(line)

func _add_exit_gates() -> void:
	var gate_material := _make_material(COLOR_ACCENT, 0.55)
	var width := cols * cell_size
	var depth := rows * cell_size
	var gate_specs: Array[Dictionary] = [
		{"pos": Vector3(width * 0.5, 0.045, -0.23), "size": Vector3(1.5, 0.035, 0.11)},
		{"pos": Vector3(width * 0.5, 0.045, depth + 0.23), "size": Vector3(1.5, 0.035, 0.11)},
		{"pos": Vector3(-0.23, 0.045, depth * 0.5), "size": Vector3(0.11, 0.035, 1.5)},
		{"pos": Vector3(width + 0.23, 0.045, depth * 0.5), "size": Vector3(0.11, 0.035, 1.5)},
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
