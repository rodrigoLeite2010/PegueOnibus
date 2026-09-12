class_name EnvironmentController
extends Node3D

## Cenario de apoio ao redor do tabuleiro: transforma o fundo em uma pequena
## praca/estacionamento urbano (calcada, grama, acessos, arvores, bancos,
## postes), preparado para receber props/modelos 3D no futuro sem exigir
## mudanca na logica do jogo. E puramente decorativo -- nao guarda nenhum
## estado de partida -- e se redimensiona a partir das dimensoes reais do
## tabuleiro recebidas em setup(), chamado pelo GameController junto com
## BoardController.setup().
##
## Etapa "cenario real": os filhos diretos de GameEnvironment agora sao
## grupos nomeados (Node3D vazios usados so como pastas), um por categoria
## visual, em vez de uma pilha unica de MeshInstance3D soltos. Isso deixa
## facil, no editor, esconder/mover/trocar uma categoria inteira (por
## exemplo desligar "Trees" num dispositivo mais fraco) sem tocar no resto.
##
## Nota sobre "BoardingArea": a area de embarque REAL (plataforma, pista de
## acesso e os slots individuais) e um no separado, $BoardingArea, irmao de
## $GameEnvironment em Game.tscn, reconstruido pelo GameController a cada
## fase porque depende de state.waiting_slots (dado de jogo, nao decoracao).
## Por isso NAO existe um grupo "BoardingArea" aqui dentro -- duplicaria
## aquele no funcional. O lado "up" (onde fica o embarque) ganha sua propria
## pista dedicada em BoardingAreaController (chamada via GameController.
## boarding_area.setup()); aqui so evitamos
## colocar decoracao nova em cima dele.

@export var rows: int = 8
@export var cols: int = 7
@export var cell_size: float = 1.0

const PLAZA_PADDING := 2.6
const GRASS_PADDING := 1.8
const CONNECTOR_WIDTH := 1.7
const CONNECTOR_LENGTH := 2.3

const COLOR_GRASS := Color("#8ecb86")
const COLOR_PLAZA := Color("#ded3ba")
const COLOR_PLAZA_EDGE := Color("#c7bb9d")
const COLOR_ASPHALT := Color("#5b6b86")
const COLOR_ACCENT := Color("#ffd233")
const COLOR_PLANTER_POT := Color("#c7bb9d")
const COLOR_PLANTER_TRUNK := Color("#8a6a4a")
const COLOR_PLANTER_LEAVES := Color("#4fae5c")
const COLOR_TREE_TRUNK := Color("#7a5a3d")
const COLOR_TREE_CANOPY := Color("#3f9a52")
const COLOR_BENCH_SEAT := Color("#a9713f")
const COLOR_BENCH_LEG := Color("#3c3f45")
const COLOR_LAMP_POLE := Color("#3c3f45")
const COLOR_LAMP_HEAD := Color("#fff2c2")
const COLOR_PARKING_LINE := Color(1.0, 1.0, 1.0, 0.5)

# Grupos (pastas Node3D) -- criados em rebuild(), guardados aqui so pra nao
# precisar procurar por nome toda hora ao adicionar filhos.
var _group_ground: Node3D
var _group_parking_lot: Node3D
var _group_curbs: Node3D
var _group_roads: Node3D
var _group_exit_roads: Node3D
var _group_parking_lines: Node3D
var _group_trees: Node3D
var _group_benches: Node3D
var _group_lamps: Node3D
var _group_decoration: Node3D

func _ready() -> void:
	rebuild()

# ETAPA 6 (PolishTest, fase 950 exclusivamente): quando true, rebuild() usa
# folgas bem menores ao redor do tabuleiro (menos "faixa vazia") e cores da
# PolishPalette na grama; nenhuma fase normal chama setup() com este
# argumento, entao o patio delas continua identico.
var is_polish_test: bool = false

func setup(p_rows: int, p_cols: int, p_cell_size: float, p_is_polish_test: bool = false) -> void:
	rows = p_rows
	cols = p_cols
	cell_size = p_cell_size
	is_polish_test = p_is_polish_test
	rebuild()

func rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()

	_group_ground = _add_group("Ground")
	_group_parking_lot = _add_group("ParkingLot")
	_group_curbs = _add_group("Curbs")
	_group_roads = _add_group("Roads")
	_group_exit_roads = _add_group("ExitRoads")
	_group_parking_lines = _add_group("ParkingLines")
	_group_trees = _add_group("Trees")
	_group_benches = _add_group("Benches")
	_group_lamps = _add_group("Lamps")
	_group_decoration = _add_group("Decoration")

	_add_grass()
	_add_plaza()
	_add_plaza_edge()
	_add_side_connector("down")
	_add_side_connector("left")
	_add_side_connector("right")
	# O lado "up" ja ganha uma rua/plataforma dedicada em
	# BoardingAreaController (chamada via GameController.boarding_area.setup());
	# nao duplicamos aqui.
	# ETAPA 6, item 6: as vagas extras pintadas no patio (fora do tabuleiro
	# jogavel) somavam "espaco visual inutil" e liam como planilha -- a
	# PolishTest fica so com grama/pista/poucos props, como pedido.
	if not is_polish_test:
		_add_lot_parking_lines()
	_add_trees()
	_add_benches()
	_add_lamps()
	_add_side_planter(-1)
	_add_side_planter(1)

func _add_group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	add_child(group)
	return group

func _board_size() -> Vector2:
	return Vector2(cols * cell_size, rows * cell_size)

func _board_center() -> Vector3:
	return Vector3(cols * cell_size * 0.5, 0.0, rows * cell_size * 0.5)

func _add_box(parent: Node3D, box_size: Vector3, box_position: Vector3, color: Color, roughness: float = 0.92) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh_instance.mesh = mesh
	mesh_instance.position = box_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

# ETAPA 6, item 6: folgas dedicadas da PolishTest -- bem menores que as
# normais (PLAZA_PADDING/GRASS_PADDING acima, usadas por toda fase normal
# sem excecao), pra reduzir a "faixa vazia" ao redor do tabuleiro sem
# remover grama/pista/arvores (que o pedido explicitamente quer manter).
const POLISH_PLAZA_PADDING := 1.35
const POLISH_GRASS_PADDING := 0.85

func _plaza_padding() -> float:
	return POLISH_PLAZA_PADDING if is_polish_test else PLAZA_PADDING

func _grass_padding() -> float:
	return POLISH_GRASS_PADDING if is_polish_test else GRASS_PADDING

# ETAPA 6, item 6: pista de acesso mais curta pra combinar com a folga
# menor da PolishTest -- sem isso a pista continuaria com o comprimento
# normal e acabaria pisando na grama, fora da pavimentacao menor.
const POLISH_CONNECTOR_LENGTH := 0.85

func _connector_length() -> float:
	return POLISH_CONNECTOR_LENGTH if is_polish_test else CONNECTOR_LENGTH

func _add_grass() -> void:
	var size: Vector2 = _board_size()
	var pad: float = _plaza_padding() + _grass_padding()
	var grass_color: Color = PolishPalette.GRASS if is_polish_test else COLOR_GRASS
	_add_box(
		_group_ground,
		Vector3(size.x + pad * 2.0, 0.05, size.y + pad * 2.0),
		_board_center() + Vector3(0.0, -0.30, 0.0),
		grass_color,
		1.0
	)

func _add_plaza() -> void:
	var size: Vector2 = _board_size()
	var pad: float = _plaza_padding()
	_add_box(
		_group_parking_lot,
		Vector3(size.x + pad * 2.0, 0.06, size.y + pad * 2.0),
		_board_center() + Vector3(0.0, -0.24, 0.0),
		COLOR_PLAZA,
		0.95
	)

func _add_plaza_edge() -> void:
	var size: Vector2 = _board_size()
	var pad: float = _plaza_padding()
	var width: float = size.x + pad * 2.0
	var depth: float = size.y + pad * 2.0
	var center: Vector3 = _board_center()
	var specs: Array[Dictionary] = [
		{"pos": center + Vector3(0.0, -0.205, -depth * 0.5 + 0.06), "size": Vector3(width, 0.03, 0.12)},
		{"pos": center + Vector3(0.0, -0.205, depth * 0.5 - 0.06), "size": Vector3(width, 0.03, 0.12)},
		{"pos": center + Vector3(-width * 0.5 + 0.06, -0.205, 0.0), "size": Vector3(0.12, 0.03, depth)},
		{"pos": center + Vector3(width * 0.5 - 0.06, -0.205, 0.0), "size": Vector3(0.12, 0.03, depth)},
	]
	for spec: Dictionary in specs:
		_add_box(_group_curbs, spec["size"], spec["pos"], COLOR_PLAZA_EDGE, 0.9)

func _add_side_connector(direction: String) -> void:
	var size: Vector2 = _board_size()
	var center: Vector3 = _board_center()
	var connector_length: float = _connector_length()
	var box_size: Vector3
	var box_position: Vector3
	match direction:
		"down":
			box_size = Vector3(CONNECTOR_WIDTH, 0.05, connector_length + 0.3)
			box_position = center + Vector3(0.0, -0.17, size.y * 0.5 + connector_length * 0.5)
		"left":
			box_size = Vector3(connector_length + 0.3, 0.05, CONNECTOR_WIDTH)
			box_position = center + Vector3(-size.x * 0.5 - connector_length * 0.5, -0.17, 0.0)
		"right":
			box_size = Vector3(connector_length + 0.3, 0.05, CONNECTOR_WIDTH)
			box_position = center + Vector3(size.x * 0.5 + connector_length * 0.5, -0.17, 0.0)
		_:
			return
	_add_box(_group_roads, box_size, box_position, COLOR_ASPHALT, 0.9)
	_add_connector_stripe(direction, box_position)

# As faixas tracejadas ficam no grupo "ExitRoads" (nao "Roads"): a laje de
# asfalto e so a via; a faixa e que marca visualmente "e por aqui que o
# veiculo sai", entao pertence conceitualmente a marcacao de saida.
func _add_connector_stripe(direction: String, connector_center: Vector3) -> void:
	var segment_count := 3
	for i: int in range(segment_count):
		var t: float = (float(i) - float(segment_count - 1) * 0.5) * 0.55
		var box_size: Vector3
		var box_position: Vector3
		if direction == "down":
			box_size = Vector3(0.05, 0.02, 0.28)
			box_position = connector_center + Vector3(0.0, 0.05, t)
		else:
			box_size = Vector3(0.28, 0.02, 0.05)
			box_position = connector_center + Vector3(t, 0.05, 0.0)
		_add_box(_group_exit_roads, box_size, box_position, COLOR_ACCENT, 0.6)

# Vagas "extras" pintadas no restante do patio (fora do tabuleiro
# jogavel), so pra reforcar a leitura de estacionamento maior do que a
# grade interativa -- puramente decorativo, sem nenhum efeito no jogo.
func _add_lot_parking_lines() -> void:
	var size: Vector2 = _board_size()
	var center: Vector3 = _board_center()
	var lane_depth: float = size.y * 0.5 + 0.55
	var stall_width: float = 0.75
	var stall_count: int = 3
	var span: float = stall_width * float(stall_count)
	var start_x: float = center.x - span * 0.5
	for i: int in range(stall_count + 1):
		var x: float = start_x + stall_width * float(i)
		_add_box(
			_group_parking_lines,
			Vector3(0.04, 0.01, 1.1),
			center + Vector3(x - center.x, -0.185, lane_depth),
			COLOR_PARKING_LINE,
			0.4
		)

# Duas arvores simples (tronco + copa) nos cantos do lado "down" (o lado
# oposto ao embarque, que fica no lado "up" -- ver nota no topo do arquivo),
# pra nao brigar visualmente com a plataforma/pista de embarque.
func _add_trees() -> void:
	var size: Vector2 = _board_size()
	var center: Vector3 = _board_center()
	var pad: float = _plaza_padding()
	var corner_x: float = size.x * 0.5 + pad * 0.6
	var corner_z: float = size.y * 0.5 + pad * 0.62
	_add_tree(center + Vector3(-corner_x, 0.0, corner_z))
	_add_tree(center + Vector3(corner_x, 0.0, corner_z))

func _add_tree(base_position: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.07
	trunk_mesh.bottom_radius = 0.09
	trunk_mesh.height = 0.55
	trunk.mesh = trunk_mesh
	trunk.position = base_position + Vector3(0.0, 0.155, 0.0)
	trunk.material_override = _material(COLOR_TREE_TRUNK, 0.95)
	_group_trees.add_child(trunk)

	# Duas esferas de copa levemente deslocadas, pra nao ficar uma bola
	# perfeita e generica.
	var canopy_a := MeshInstance3D.new()
	var canopy_a_mesh := SphereMesh.new()
	canopy_a_mesh.radius = 0.42
	canopy_a_mesh.height = 0.78
	canopy_a.mesh = canopy_a_mesh
	canopy_a.position = base_position + Vector3(0.0, 0.62, 0.0)
	canopy_a.material_override = _material(COLOR_TREE_CANOPY, 1.0)
	_group_trees.add_child(canopy_a)

	var canopy_b := MeshInstance3D.new()
	var canopy_b_mesh := SphereMesh.new()
	canopy_b_mesh.radius = 0.30
	canopy_b_mesh.height = 0.55
	canopy_b.mesh = canopy_b_mesh
	canopy_b.position = base_position + Vector3(0.16, 0.82, 0.10)
	canopy_b.material_override = _material(COLOR_TREE_CANOPY.lightened(0.06), 1.0)
	_group_trees.add_child(canopy_b)

# Bancos simples perto do lado "down", de frente pro patio.
func _add_benches() -> void:
	var size: Vector2 = _board_size()
	var center: Vector3 = _board_center()
	var z: float = size.y * 0.5 + _plaza_padding() * 0.32
	_add_bench(center + Vector3(-size.x * 0.22, 0.0, z))
	_add_bench(center + Vector3(size.x * 0.22, 0.0, z))

func _add_bench(base_position: Vector3) -> void:
	_add_box(_group_benches, Vector3(0.62, 0.05, 0.24), base_position + Vector3(0.0, 0.24, 0.0), COLOR_BENCH_SEAT, 0.85)
	_add_box(_group_benches, Vector3(0.62, 0.24, 0.04), base_position + Vector3(0.0, 0.38, -0.10), COLOR_BENCH_SEAT, 0.85)
	_add_box(_group_benches, Vector3(0.05, 0.24, 0.22), base_position + Vector3(-0.26, 0.12, 0.0), COLOR_BENCH_LEG, 0.7)
	_add_box(_group_benches, Vector3(0.05, 0.24, 0.22), base_position + Vector3(0.26, 0.12, 0.0), COLOR_BENCH_LEG, 0.7)

# Quatro postes de luz nos cantos do patio -- cabeca com emissao leve pra
# ler como "aceso" sem precisar de nenhum OmniLight3D de verdade (o projeto
# ja evita luzes dinamicas extras por performance mobile).
func _add_lamps() -> void:
	var size: Vector2 = _board_size()
	var center: Vector3 = _board_center()
	var pad: float = _plaza_padding()
	var corner_x: float = size.x * 0.5 + pad * 0.88
	var corner_z: float = size.y * 0.5 + pad * 0.88
	for sign_x: float in [-1.0, 1.0]:
		for sign_z: float in [-1.0, 1.0]:
			_add_lamp(center + Vector3(sign_x * corner_x, 0.0, sign_z * corner_z))

func _add_lamp(base_position: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.035
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 1.0
	pole.mesh = pole_mesh
	pole.position = base_position + Vector3(0.0, 0.5, 0.0)
	pole.material_override = _material(COLOR_LAMP_POLE, 0.6)
	_group_lamps.add_child(pole)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.08
	head_mesh.height = 0.16
	head.mesh = head_mesh
	head.position = base_position + Vector3(0.0, 1.02, 0.0)
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = COLOR_LAMP_HEAD
	head_material.emission_enabled = true
	head_material.emission = COLOR_LAMP_HEAD
	head_material.emission_energy_multiplier = 1.4
	head_material.roughness = 0.4
	head.material_override = head_material
	_group_lamps.add_child(head)

# Duas pequenas jardineiras nas laterais do estacionamento, na altura do
# meio do tabuleiro -- decoracao leve, sem depender de nenhum asset externo.
func _add_side_planter(side: int) -> void:
	var size: Vector2 = _board_size()
	var center: Vector3 = _board_center()
	var x: float = center.x + float(side) * (size.x * 0.5 + _plaza_padding() * 0.55)
	var base_position := Vector3(x, 0.0, center.z)
	_add_planter(base_position)

func _add_planter(base_position: Vector3) -> void:
	var pot := MeshInstance3D.new()
	var pot_mesh := CylinderMesh.new()
	pot_mesh.top_radius = 0.22
	pot_mesh.bottom_radius = 0.26
	pot_mesh.height = 0.22
	pot.mesh = pot_mesh
	pot.position = base_position + Vector3(0.0, -0.13, 0.0)
	pot.material_override = _material(COLOR_PLANTER_POT, 0.9)
	_group_decoration.add_child(pot)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.05
	trunk_mesh.bottom_radius = 0.06
	trunk_mesh.height = 0.28
	trunk.mesh = trunk_mesh
	trunk.position = base_position + Vector3(0.0, 0.12, 0.0)
	trunk.material_override = _material(COLOR_PLANTER_TRUNK, 0.95)
	_group_decoration.add_child(trunk)

	var canopy := MeshInstance3D.new()
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 0.30
	canopy_mesh.height = 0.55
	canopy.mesh = canopy_mesh
	canopy.position = base_position + Vector3(0.0, 0.44, 0.0)
	canopy.material_override = _material(COLOR_PLANTER_LEAVES, 1.0)
	_group_decoration.add_child(canopy)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
