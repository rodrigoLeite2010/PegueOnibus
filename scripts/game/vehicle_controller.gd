class_name VehicleController
extends Node3D

signal pressed(vehicle_id: String)

@export var vehicle_id: String = ""
@export var type_id: String = "car"
@export var color_id: String = "red"
@export var footprint_rows: int = 2
@export var footprint_cols: int = 1
@export var orientation: String = "vertical"
@export var exit_direction: String = "up"

const COLOR_MAP := {
	"red": Color("#ff4b4b"),
	"blue": Color("#2f91ff"),
	"green": Color("#35de45"),
	"yellow": Color("#ffd633"),
	"purple": Color("#9349ff"),
	"pink": Color("#ff43c8"),
	"orange": Color("#ff7b20"),
}

const USE_PROCEDURAL_PLACEHOLDER := true

var visual_resource: VehicleVisualResource
var _visual_pivot: Node3D
var _input_area: Area3D
var _model_boarding_point: Node3D
var _model_selection_point: Node3D
var _model_node: Node3D
var _model_base_rotation_y: float = 0.0

func _ready() -> void:
	if get_child_count() == 0:
		rebuild()

func setup_from_state(vehicle: VehicleState, cell_size: float) -> void:
	vehicle_id = vehicle.id
	type_id = vehicle.type_id
	color_id = vehicle.color_id
	footprint_rows = vehicle.footprint_rows
	footprint_cols = vehicle.footprint_cols
	orientation = vehicle.orientation
	exit_direction = vehicle.exit_direction
	position = Vector3(
		(vehicle.col + vehicle.footprint_cols * 0.5) * cell_size,
		0.31,
		(vehicle.row + vehicle.footprint_rows * 0.5) * cell_size
	)
	rebuild()

func rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()

	_model_boarding_point = null
	_model_selection_point = null
	_model_node = null
	_model_base_rotation_y = 0.0
	visual_resource = VehicleVisualLibrary.get_for_vehicle(type_id, color_id)
	var width: float = maxf(0.78, float(footprint_cols) * 0.88)
	var depth: float = maxf(0.78, float(footprint_rows) * 0.88)

	_add_shadow(width, depth)
	_visual_pivot = Node3D.new()
	_visual_pivot.name = "Visual"
	add_child(_visual_pivot)

	# O sprite 2D em Sprite3D usa billboard (sempre de frente pra camera), entao
	# ele nunca gira/inclina com o movimento e acaba lendo como um recorte de
	# papel deslizando na tela em vez de um veiculo 3D de verdade. Enquanto nao
	# houver arte definitiva por tipo (carro/van/onibus), preferimos o veiculo
	# processual 3D abaixo: ele gira, recebe sombra real e ja varia de forma por
	# tipo. Para voltar a usar os PNGs recortados quando houver arte por tipo,
	# troque USE_PROCEDURAL_PLACEHOLDER para false.
	if visual_resource != null and visual_resource.model_scene != null:
		_add_model_visual()
	elif USE_PROCEDURAL_PLACEHOLDER:
		_add_procedural_vehicle(width, depth)
	elif visual_resource != null and visual_resource.sprite_texture != null:
		_add_sprite_visual(width, depth)
	else:
		_add_procedural_vehicle(width, depth)

	_add_arrow_marker(width, depth)
	_add_input_area(width, depth)

func get_boarding_point() -> Vector3:
	# Modelos 3D profissionais podem declarar o ponto exato da porta com um
	# Marker3D chamado BoardingPoint. Como ele faz parte do modelo visual, sua
	# posicao acompanha escala e rotacao automaticamente.
	if is_instance_valid(_model_boarding_point):
		return _model_boarding_point.global_position
	if visual_resource != null:
		return global_position + _rotated_local_offset(visual_resource.door_offset)
	return global_position + _rotated_local_offset(Vector3(0.0, 0.0, -0.35))

func get_selection_point() -> Vector3:
	if is_instance_valid(_model_selection_point):
		return _model_selection_point.global_position
	return global_position + Vector3(0.0, 0.7, 0.0)

func animate_valid_tap() -> void:
	if _visual_pivot == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual_pivot, "scale", Vector3(1.07, 1.07, 1.07), 0.075)
	tween.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.095)

func animate_blocked() -> void:
	var start_position := position
	var shake_axis := Vector3(0.12, 0.0, 0.0)
	if exit_direction == "left" or exit_direction == "right":
		shake_axis = Vector3(0.0, 0.0, 0.12)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", start_position - shake_axis, 0.045)
	tween.tween_property(self, "position", start_position + shake_axis, 0.06)
	tween.tween_property(self, "position", start_position - shake_axis * 0.65, 0.05)
	tween.tween_property(self, "position", start_position, 0.055)

func animate_no_slot() -> void:
	if _visual_pivot == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(_visual_pivot, "scale", Vector3(0.92, 0.92, 0.92), 0.08)
	tween.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.12)

# Usado pelo botao "Dica" (etapa 9): pulso 3x pra destacar o veiculo
# sugerido, sem precisar de nenhum asset/shader novo.
func animate_hint() -> void:
	if _visual_pivot == null:
		return
	var tween := create_tween()
	tween.set_loops(3)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_visual_pivot, "scale", Vector3(1.14, 1.14, 1.14), 0.16)
	tween.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.16)

func drive_route(points: Array[Vector3]) -> void:
	if points.is_empty():
		return
	for target: Vector3 in points:
		var delta: Vector3 = target - position
		var distance: float = delta.length()
		var duration: float = clampf(distance * 0.095, 0.16, 0.46)

		# O GLB agora vira de verdade para o sentido do deslocamento. Isso evita
		# o efeito de carro deslizando de lado quando contorna o tabuleiro.
		if is_instance_valid(_model_node) and Vector2(delta.x, delta.z).length() > 0.01:
			var desired_y: float = _model_base_rotation_y + rad_to_deg(atan2(delta.x, delta.z))
			var turn := create_tween()
			turn.set_trans(Tween.TRANS_SINE)
			turn.set_ease(Tween.EASE_IN_OUT)
			turn.tween_property(_model_node, "rotation_degrees:y", desired_y, 0.10)
			await turn.finished

		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "position", target, duration)
		if _visual_pivot != null:
			# Pequena inclinacao de carroceria durante o deslocamento, sem mudar
			# a orientacao logica/collider do veiculo.
			var roll: float = -1.8 if delta.x >= 0.0 else 1.8
			tween.parallel().tween_property(_visual_pivot, "rotation_degrees:z", roll, minf(duration, 0.14))
		await tween.finished

	if _visual_pivot != null:
		var settle := create_tween()
		settle.set_trans(Tween.TRANS_BACK)
		settle.set_ease(Tween.EASE_OUT)
		settle.tween_property(_visual_pivot, "scale", Vector3(1.06, 1.06, 1.06), 0.07)
		settle.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.12)
		settle.parallel().tween_property(_visual_pivot, "rotation_degrees:z", 0.0, 0.12)
		await settle.finished

func animate_boarding_bounce() -> void:
	if _visual_pivot == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual_pivot, "position:y", 0.08, 0.07)
	tween.tween_property(_visual_pivot, "position:y", 0.0, 0.09)

func drive_away_from_pickup(board_width: float) -> void:
	var target := position + Vector3(maxf(board_width * 0.65, 4.5), 0.18, -0.35)
	var delta: Vector3 = target - position
	if is_instance_valid(_model_node):
		var desired_y: float = _model_base_rotation_y + rad_to_deg(atan2(delta.x, delta.z))
		var turn := create_tween()
		turn.set_trans(Tween.TRANS_SINE)
		turn.set_ease(Tween.EASE_IN_OUT)
		turn.tween_property(_model_node, "rotation_degrees:y", desired_y, 0.10)
		await turn.finished
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "position", target, 0.48)
	if _visual_pivot != null:
		tween.parallel().tween_property(_visual_pivot, "scale", Vector3(0.88, 0.88, 0.88), 0.48)
	await tween.finished


func _add_input_area(width: float, depth: float) -> void:
	_input_area = Area3D.new()
	_input_area.name = "TouchArea"
	_input_area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var height := 0.9
	if visual_resource != null:
		height = visual_resource.collider_height
	box.size = Vector3(width, height, depth)
	shape.shape = box
	shape.position = Vector3(0.0, 0.18, 0.0)
	_input_area.add_child(shape)
	_input_area.input_event.connect(_on_input_event)
	add_child(_input_area)

func _add_model_visual() -> void:
	var model := visual_resource.model_scene.instantiate() as Node3D
	if model == null:
		return
	model.name = "VehicleModel"
	model.position = visual_resource.model_offset
	model.scale = Vector3.ONE * visual_resource.model_scale
	model.rotation_degrees = visual_resource.model_rotation_degrees

	# Convencao do primeiro GLB: comprimento no eixo Z. Quando o footprint
	# logico e horizontal, giramos somente a apresentacao; a regra continua
	# usando row/col/footprint sem depender da arte.
	if orientation == "horizontal":
		model.rotation_degrees.y += 90.0

	_visual_pivot.add_child(model)
	_model_node = model
	_model_base_rotation_y = model.rotation_degrees.y
	_model_boarding_point = model.find_child("BoardingPoint", true, false) as Node3D
	_model_selection_point = model.find_child("SelectionPoint", true, false) as Node3D

func _rotated_local_offset(offset: Vector3) -> Vector3:
	if orientation == "horizontal":
		return offset.rotated(Vector3.UP, deg_to_rad(90.0))
	return offset

func _add_sprite_visual(width: float, depth: float) -> void:
	var sprite := Sprite3D.new()
	sprite.name = "VehicleSprite"
	sprite.texture = visual_resource.sprite_texture
	sprite.pixel_size = 0.00325
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.08
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = false
	sprite.position = Vector3(0.0, visual_resource.sprite_vertical_offset, 0.0)

	var texture_size: Vector2 = sprite.texture.get_size()
	var current_long := maxf(texture_size.x, texture_size.y) * sprite.pixel_size
	var logical_long := maxf(width, depth)
	# Mantem carros grandes o suficiente para leitura, mas respeita o footprint.
	var target_long := clampf(logical_long * 0.92, 1.18, 2.6)
	if current_long > 0.0:
		var factor := target_long / current_long
		factor *= clampf(visual_resource.sprite_scale, 0.85, 1.12)
		sprite.scale = Vector3.ONE * factor
	_visual_pivot.add_child(sprite)

func _add_procedural_vehicle(width: float, depth: float) -> void:
	var color: Color = COLOR_MAP.get(color_id, Color.WHITE)
	var is_big: bool = type_id == "van" or type_id == "mini_bus" or type_id == "bus"
	var is_horizontal: bool = width >= depth
	var long_axis: float = maxf(width, depth)
	var body_height: float = 0.40 if is_big else 0.34

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(width * 0.76, body_height, depth * 0.78)
	body.mesh = body_mesh
	body.position = Vector3(0.0, body_height * 0.5 - 0.03, 0.0)
	body.material_override = _make_material(color, 0.42)
	_visual_pivot.add_child(body)

	if is_big:
		# Van/micro-onibus/onibus: teto reto de ponta a ponta e janelas em fileira,
		# para ler como um veiculo maior e diferente do carro mesmo sem arte nova.
		var roof_height: float = 0.30 if type_id == "bus" else 0.24
		var roof := MeshInstance3D.new()
		var roof_mesh := BoxMesh.new()
		roof_mesh.size = Vector3(width * 0.70, roof_height, depth * 0.72)
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, body_height + roof_height * 0.5 - 0.03, 0.0)
		roof.material_override = _make_material(color.lightened(0.08), 0.4)
		_visual_pivot.add_child(roof)

		var roof_stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		if is_horizontal:
			stripe_mesh.size = Vector3(width * 0.72, 0.03, 0.10)
		else:
			stripe_mesh.size = Vector3(0.10, 0.03, depth * 0.72)
		roof_stripe.mesh = stripe_mesh
		roof_stripe.position = Vector3(0.0, body_height + roof_height + 0.015, 0.0)
		roof_stripe.material_override = _make_material(Color("#ffffff"), 0.5)
		_visual_pivot.add_child(roof_stripe)

		var window_count: int = clampi(int(long_axis / 0.82), 2, 5)
		var window_span: float = long_axis * 0.82
		var window_gap: float = window_span / float(window_count)
		var start_offset: float = -window_span * 0.5
		for i: int in range(window_count):
			var offset: float = start_offset + window_gap * (float(i) + 0.5)
			var window := MeshInstance3D.new()
			var window_mesh := BoxMesh.new()
			var window_node_pos: Vector3
			if is_horizontal:
				window_mesh.size = Vector3(window_gap * 0.62, 0.16, 0.04)
				window_node_pos = Vector3(offset, body_height + 0.06, depth * 0.37)
			else:
				window_mesh.size = Vector3(0.04, 0.16, window_gap * 0.62)
				window_node_pos = Vector3(width * 0.37, body_height + 0.06, offset)
			window.mesh = window_mesh
			window.position = window_node_pos
			window.material_override = _make_material(Color("#293a58"), 0.16)
			_visual_pivot.add_child(window)
	else:
		# Carro pequeno: cabine elevada + para-brisa, visual original.
		var cabin := MeshInstance3D.new()
		var cabin_mesh := BoxMesh.new()
		cabin_mesh.size = Vector3(width * 0.58, 0.30, depth * 0.46)
		cabin.mesh = cabin_mesh
		cabin.position = Vector3(0.0, 0.42, -depth * 0.04)
		cabin.material_override = _make_material(color.lightened(0.12), 0.38)
		_visual_pivot.add_child(cabin)

		var glass := MeshInstance3D.new()
		var glass_mesh := BoxMesh.new()
		glass_mesh.size = Vector3(width * 0.48, 0.10, depth * 0.28)
		glass.mesh = glass_mesh
		glass.position = Vector3(0.0, 0.57, -depth * 0.07)
		glass.material_override = _make_material(Color("#293a58"), 0.18)
		_visual_pivot.add_child(glass)

	_add_wheels(width, depth, is_horizontal, long_axis)

func _add_wheels(width: float, depth: float, is_horizontal: bool, long_axis: float) -> void:
	# Rodas simples melhoram muito a leitura de "veiculo de brinquedo" sem
	# depender de nenhuma imagem nova. Onibus/vans mais compridos ganham uma
	# roda extra por lado.
	var wheel_count_per_side: int = clampi(int(long_axis / 0.85) + 1, 2, 3)
	var wheel_radius: float = 0.135
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = wheel_radius
	wheel_mesh.bottom_radius = wheel_radius
	wheel_mesh.height = 0.09
	wheel_mesh.radial_segments = 14
	var wheel_material := _make_material(Color("#20242c"), 0.75)

	var long_span: float = long_axis * 0.62
	var short_half: float = (depth if is_horizontal else width) * 0.42

	for side: float in [-1.0, 1.0]:
		for i: int in range(wheel_count_per_side):
			var t: float = 0.5 if wheel_count_per_side == 1 else float(i) / float(wheel_count_per_side - 1)
			var along: float = lerpf(-long_span * 0.5, long_span * 0.5, t)
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.material_override = wheel_material
			wheel.position = Vector3(0.0, -0.06, 0.0)
			if is_horizontal:
				wheel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				wheel.position = Vector3(along, -0.06, side * short_half)
			else:
				wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
				wheel.position = Vector3(side * short_half, -0.06, along)
			_visual_pivot.add_child(wheel)

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(vehicle_id)
		return
	var touch_event := event as InputEventScreenTouch
	if touch_event != null and touch_event.pressed:
		pressed.emit(vehicle_id)

func _exit_vector() -> Vector3:
	match exit_direction:
		"up": return Vector3(0.0, 0.0, -1.0)
		"down": return Vector3(0.0, 0.0, 1.0)
		"left": return Vector3(-1.0, 0.0, 0.0)
		"right": return Vector3(1.0, 0.0, 0.0)
	return Vector3(1.0, 0.0, 0.0)

func _add_shadow(width: float, depth: float) -> void:
	var shadow := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.018
	mesh.radial_segments = 28
	shadow.mesh = mesh
	shadow.scale = Vector3(maxf(width * 0.82, 0.72), 1.0, maxf(depth * 0.64, 0.62))
	shadow.position = Vector3(0.0, -0.235, 0.07)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.14, 0.19, 0.28, 0.18)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	shadow.material_override = material
	add_child(shadow)

func _add_arrow_marker(width: float, depth: float) -> void:
	var arrow_label := Label3D.new()
	arrow_label.name = "DirectionArrow"
	arrow_label.text = _marker_text()
	arrow_label.font_size = 92
	arrow_label.modulate = Color.WHITE
	arrow_label.outline_size = 14
	arrow_label.outline_modulate = Color(0.12, 0.16, 0.25, 0.72)
	arrow_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow_label.position = Vector3(0.0, 1.03, 0.0)
	arrow_label.scale = Vector3(0.0105, 0.0105, 0.0105) * clampf(maxf(width, depth), 1.0, 2.2)
	add_child(arrow_label)

func _arrow_text() -> String:
	match exit_direction:
		"up": return "↑"
		"down": return "↓"
		"left": return "←"
		"right": return "→"
	return "→"

# Combina a seta de saida com o simbolo de acessibilidade a daltonismo
# (etapa 10), quando ligado. Fixado no momento em que o veiculo aparece no
# tabuleiro (rebuild()); ligar/desligar o toggle nao redesenha veiculos que
# ja estao no tabuleiro, so os que aparecerem dai em diante.
func _marker_text() -> String:
	if not AccessibilitySettings.color_symbols_enabled:
		return _arrow_text()
	var symbol: String = AccessibilitySettings.symbol_for(color_id)
	if symbol == "":
		return _arrow_text()
	return "%s %s" % [_arrow_text(), symbol]

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material
