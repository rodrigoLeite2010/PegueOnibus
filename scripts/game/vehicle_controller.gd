class_name VehicleController
extends Node3D

signal pressed(vehicle_id: String)

@export var vehicle_id: String = ""
@export var type_id: String = "car"
@export var color_id: String = "red"
@export var footprint_rows: int = 2
@export var footprint_cols: int = 1
@export var orientation: String = "vertical"
@export var exit_direction: ExitDirection.Value = ExitDirection.Value.UP

# Mapa central de cores dos veiculos (Etapa: cor automatica do carro 3D).
# Usado tanto pelo veiculo procedural (_add_procedural_vehicle) quanto para
# colorir o corpo de modelos GLB reais via VehicleController.set_vehicle_color
# (chamado em _add_model_visual quando o modelo expõe esse metodo). As 10
# cores nomeadas abaixo sao o conjunto oficial pedido nesta etapa; "blue" e
# "pink" ficam mantidos como aliases de compatibilidade porque o
# LevelGenerator.COLORS e os resources/vehicle_types/*.tres atuais ainda
# geram exatamente esses dois ids -- sem isso, todo veiculo azul/rosa
# existente cairia no fallback cinza em vez de manter sua cor.
const COLOR_MAP := {
	"red": Color("#e53935"),
	"yellow": Color("#fdd835"),
	"dark_blue": Color("#1565c0"),
	"light_blue": Color("#4fc3f7"),
	"green": Color("#43a047"),
	"purple": Color("#8e24aa"),
	"brown": Color("#6d4c41"),
	"orange": Color("#fb8c00"),
	"black": Color("#212121"),
	"gray": Color("#9e9e9e"),
	# Aliases de compatibilidade (ver comentario acima).
	"blue": Color("#1565c0"),
	"pink": Color("#ff4fa3"),
}

# Fallback seguro para color_id desconhecido ou ausente: nunca deixamos o
# corpo do veiculo sem cor nem geramos erro por causa disso.
const DEFAULT_VEHICLE_COLOR := Color("#9e9e9e")

# Calibracao do "para onde o GLB olha" quando rotation_degrees.y = 0 (etapa
# "todos os veiculos usam o GLB real"). O jogo decide a direcao logica via
# exit_direction; este numero so ajusta a leitura visual do modelo pra
# concordar com a seta. Se, no teste visual, o carro sair de costas (ex.:
# a seta aponta pra cima mas o carro olha pra baixo), ajuste SOMENTE este
# valor (ex.: para 180.0) -- nao espalhe esse ajuste em outro lugar do
# codigo.
const MODEL_FACING_CALIBRATION_DEGREES := 0.0

# A partir desta etapa o placeholder procedural (BoxMesh/CapsuleMesh/etc,
# ver _add_procedural_vehicle) e apenas um fallback de emergencia: so entra
# em jogo se VehicleVisualLibrary nao encontrar nenhum resource/model_scene
# para o type_id (ex.: van/bus, que ainda nao tem GLB dedicado -- fora do
# escopo desta etapa). Para o tipo "car", VehicleVisualLibrary agora sempre
# resolve um model_scene valido (o mesmo GLB reaproveitado p/ todas as
# cores), entao esse placeholder nunca deveria aparecer na execucao normal
# da fase para veiculos do tipo "car".
const USE_PROCEDURAL_PLACEHOLDER := true

var visual_resource: VehicleVisualResource
var _visual_pivot: Node3D
var _input_area: Area3D
var _model_boarding_point: Node3D
var _model_selection_point: Node3D
var _model_node: Node3D
var _model_base_rotation_y: float = 0.0

# Passo 9 (animacoes secundarias): anel de brilho discreto sob o veiculo,
# ligado/desligado por set_selectable() conforme o veiculo pode ou nao sair
# agora. Fica fora de _visual_pivot (igual _add_shadow) para nunca girar/
# inclinar junto com o modelo durante drive_route().
var _selectable_glow: MeshInstance3D
var _selectable_glow_material: StandardMaterial3D
var _selectable_tween: Tween
var _is_selectable: bool = false

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
	if _selectable_tween != null and _selectable_tween.is_valid():
		_selectable_tween.kill()
	_selectable_tween = null
	_selectable_glow = null
	_selectable_glow_material = null
	_is_selectable = false
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
	_add_selectable_glow(width, depth)
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


# Quando o veiculo chega a uma vaga de embarque ele vira uma miniatura 3D
# dentro do quadrado, como na referencia visual. Isso impede principalmente
# onibus/veiculos medios de invadirem a vaga vizinha.
func set_waiting_slot_mode(enabled: bool) -> void:
	var factor: float = 1.0
	if enabled:
		if type_id == "bus":
			factor = 0.48
		elif type_id == "medium_car" or type_id == "van":
			factor = 0.60
		else:
			factor = 0.72
	scale = Vector3.ONE * factor

func get_boarding_point() -> Vector3:
	# Modelos 3D profissionais podem declarar o ponto exato da porta com um
	# Marker3D chamado BoardingPoint. Como ele faz parte do modelo visual, sua
	# posicao acompanha escala e rotacao automaticamente.
	if is_instance_valid(_model_boarding_point):
		return _model_boarding_point.global_position
	var fallback_offset: Vector3 = Vector3(0.0, 0.0, -0.35)
	if visual_resource != null:
		fallback_offset = visual_resource.door_offset
	# Quando o veiculo procedural gira durante a rota, a porta visual gira junto
	# com o Visual. O fallback precisa usar esse espaco, nao apenas a orientacao
	# logica original do footprint.
	if is_instance_valid(_visual_pivot):
		return _visual_pivot.to_global(_rotated_local_offset(fallback_offset))
	return global_position + _rotated_local_offset(fallback_offset)

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
	if exit_direction == ExitDirection.Value.LEFT or exit_direction == ExitDirection.Value.RIGHT:
		shake_axis = Vector3(0.0, 0.0, 0.12)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", start_position - shake_axis, 0.045)
	tween.tween_property(self, "position", start_position + shake_axis, 0.06)
	tween.tween_property(self, "position", start_position - shake_axis * 0.65, 0.05)
	tween.tween_property(self, "position", start_position, 0.055)
	_flash_blocked_indicator()

# Flash leve (vermelho) por cima do veiculo quando o toque e invalido --
# reforca o feedback de "bloqueado" junto com o shake, sem tocar nos
# materiais do corpo (nao ha risco de deixar uma cor errada perdurar se o
# veiculo for tocado de novo logo em seguida).
func _flash_blocked_indicator() -> void:
	var width: float = maxf(0.9, float(footprint_cols) * 0.9)
	var depth: float = maxf(0.9, float(footprint_rows) * 0.9)
	var flash := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.5, depth)
	flash.mesh = mesh
	flash.position = Vector3(0.0, 0.28, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.15, 0.15, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = material
	add_child(flash)
	var flash_tween := create_tween()
	flash_tween.tween_property(material, "albedo_color:a", 0.42, 0.05)
	flash_tween.tween_property(material, "albedo_color:a", 0.0, 0.16)
	flash_tween.tween_callback(flash.queue_free)


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

	# Pequeno "hop" de partida (eleva levemente antes de acelerar): reforca a
	# sensacao de veiculo saindo de marcha em vez de deslizar do zero.
	if _visual_pivot != null:
		var lift := create_tween()
		lift.set_trans(Tween.TRANS_SINE)
		lift.set_ease(Tween.EASE_OUT)
		lift.tween_property(_visual_pivot, "position:y", 0.055, 0.06)
		lift.tween_property(_visual_pivot, "position:y", 0.0, 0.09)
	_spawn_ground_puff(Color(0.62, 0.56, 0.46, 0.4), 5)

	# A rota inteira (posicao atual -> ... -> vaga final) agora e UMA curva
	# continua (Curve3D), nao mais um tween por trecho. Antes, cada canto da
	# rota fazia o tween do trecho anterior terminar (freando ate zero) pra so
	# depois comecar o proximo -- lia como um robo parando/virando/reacelerando
	# em cada esquina em vez de fazer uma curva. Com Curve3D + handles
	# arredondando os pontos internos, o veiculo faz um unico movimento, com
	# uma unica aceleracao no inicio e desaceleracao no final (via easing na
	# progressao ao longo da curva), giro continuo (nao mais em saltos por
	# trecho) e inclinacao (roll) proporcional a curvatura real do caminho.
	var waypoints: Array[Vector3] = [position]
	waypoints.append_array(points)
	var curve: Curve3D = _build_route_curve(waypoints)
	var total_length: float = curve.get_baked_length()

	if total_length <= 0.001:
		position = points[-1]
	else:
		var duration: float = clampf(total_length * 0.11, 0.32, 1.6)
		var move_tween := create_tween()
		move_tween.set_trans(Tween.TRANS_QUAD)
		move_tween.set_ease(Tween.EASE_IN_OUT)
		move_tween.tween_method(_apply_curve_progress.bind(curve, total_length), 0.0, total_length, duration)
		await move_tween.finished

	# Alinhamento perfeito: garante o ponto final exato independente de
	# qualquer tolerancia de amostragem da curva (o chamador tambem faz um
	# snap no Marker3D global depois disso, esse aqui e so o local).
	position = points[-1]
	if _visual_pivot != null:
		_visual_pivot.rotation_degrees.z = 0.0

	if _visual_pivot != null:
		var settle := create_tween()
		settle.set_trans(Tween.TRANS_BACK)
		settle.set_ease(Tween.EASE_OUT)
		settle.tween_property(_visual_pivot, "scale", Vector3(1.06, 1.06, 1.06), 0.07)
		settle.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.12)
		_spawn_ground_puff(Color(1.0, 1.0, 1.0, 0.5), 4, 0.10)
		await settle.finished

# Constroi uma Curve3D suave passando por todos os waypoints. Pontos
# internos ganham handles tangentes (media normalizada das direcoes dos
# dois trechos vizinhos, limitados a uma fracao do trecho mais curto pra
# nao estourar a curva em trechos pequenos) pra arredondar os cantos; o
# primeiro e o ultimo ponto ficam sem handle, entao a curva sai/chega
# alinhada com a reta original desses trechos (sem desviar da vaga final).
func _build_route_curve(waypoints: Array[Vector3]) -> Curve3D:
	var curve := Curve3D.new()
	var count: int = waypoints.size()
	for i: int in range(count):
		var point: Vector3 = waypoints[i]
		var in_handle := Vector3.ZERO
		var out_handle := Vector3.ZERO
		if i > 0 and i < count - 1:
			var prev: Vector3 = waypoints[i - 1]
			var next: Vector3 = waypoints[i + 1]
			var to_prev: Vector3 = point - prev
			var to_next: Vector3 = next - point
			var prev_len: float = to_prev.length()
			var next_len: float = to_next.length()
			if prev_len > 0.001 and next_len > 0.001:
				var tangent_dir: Vector3 = to_prev.normalized() + to_next.normalized()
				if tangent_dir.length() > 0.001:
					tangent_dir = tangent_dir.normalized()
					var handle_len: float = minf(prev_len, next_len) * 0.35
					in_handle = -tangent_dir * handle_len
					out_handle = tangent_dir * handle_len
		curve.add_point(point, in_handle, out_handle)
	return curve

# Chamada a cada passo do tween_method com a distancia ja percorrida ao
# longo da curva. Faz o veiculo (a) seguir a posicao amostrada; (b) girar
# de forma continua pra encarar a tangente do caminho, respeitando a mesma
# calibracao de "frente" usada no repouso (MODEL_FACING_CALIBRATION_DEGREES
# + visual_resource.model_rotation_degrees.y quando ha modelo GLB), em vez
# do calculo antigo por trecho; (c) inclinar levemente (roll) proporcional
# a curvatura real do trajeto naquele ponto.
func _apply_curve_progress(distance: float, curve: Curve3D, total_length: float) -> void:
	if not is_instance_valid(self):
		return
	var pos_now: Vector3 = curve.sample_baked(distance, true)
	position = pos_now

	var step: float = clampf(total_length * 0.02, 0.04, 0.22)
	var pos_behind: Vector3 = curve.sample_baked(clampf(distance - step, 0.0, total_length), true)
	var pos_ahead: Vector3 = curve.sample_baked(clampf(distance + step, 0.0, total_length), true)

	var tangent_forward: Vector3 = pos_ahead - pos_now
	var tangent_backward: Vector3 = pos_now - pos_behind

	var have_forward: bool = Vector2(tangent_forward.x, tangent_forward.z).length() > 0.01
	var have_backward: bool = Vector2(tangent_backward.x, tangent_backward.z).length() > 0.01
	if not have_forward and not have_backward:
		return

	var heading_forward: float = rad_to_deg(atan2(tangent_forward.x, tangent_forward.z)) if have_forward else 0.0
	var heading_backward: float = rad_to_deg(atan2(tangent_backward.x, tangent_backward.z)) if have_backward else 0.0
	var heading: float = heading_forward if have_forward else heading_backward

	var turn_target: Node3D = _model_node if is_instance_valid(_model_node) else _visual_pivot
	if turn_target != null:
		var calibration: float = 0.0
		if turn_target == _model_node and visual_resource != null:
			calibration = MODEL_FACING_CALIBRATION_DEGREES + visual_resource.model_rotation_degrees.y
		turn_target.rotation_degrees.y = heading + calibration

	if _visual_pivot != null:
		if have_forward and have_backward:
			var turn_rate: float = wrapf(heading_forward - heading_backward, -180.0, 180.0)
			_visual_pivot.rotation_degrees.z = clampf(turn_rate * 0.55, -6.0, 6.0)
		else:
			_visual_pivot.rotation_degrees.z = lerpf(_visual_pivot.rotation_degrees.z, 0.0, 0.25)


func animate_boarding_bounce() -> void:
	if _visual_pivot == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual_pivot, "position:y", 0.08, 0.07)
	tween.tween_property(_visual_pivot, "position:y", 0.0, 0.09)

func drive_away_from_pickup(board_width: float) -> void:
	_spawn_ground_puff(Color(0.62, 0.56, 0.46, 0.4), 4)
	var target := position + Vector3(maxf(board_width * 0.65, 4.5), 0.18, -0.35)
	var delta: Vector3 = target - position
	if Vector2(delta.x, delta.z).length() > 0.01:
		var desired_y: float = rad_to_deg(atan2(delta.x, delta.z))
		var turn_target: Node3D = _model_node if is_instance_valid(_model_node) else _visual_pivot
		# Mesma calibracao de "frente" usada no repouso e em drive_route(),
		# em vez do antigo "_model_base_rotation_y + desired_y" (que somava
		# um angulo absoluto em cima de outro angulo absoluto, dobrando a
		# calibracao de modelos com model_rotation_degrees != 0, como o
		# onibus).
		var calibration: float = 0.0
		if turn_target == _model_node and visual_resource != null:
			calibration = MODEL_FACING_CALIBRATION_DEGREES + visual_resource.model_rotation_degrees.y
		if turn_target != null:
			var turn := create_tween()
			turn.set_trans(Tween.TRANS_SINE)
			turn.set_ease(Tween.EASE_IN_OUT)
			turn.tween_property(turn_target, "rotation_degrees:y", desired_y + calibration, 0.16)
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

	# A frente visual do modelo agora segue exit_direction diretamente (4
	# direcoes distintas), em vez do hack anterior que so diferenciava
	# vertical/horizontal (up/down ficavam iguais entre si, e left/right
	# tambem). Mesma convencao de atan2 usada em drive_route()/animate, pra
	# ficar coerente com o giro que acontece durante a saida do veiculo.
	var exit_dir: Vector3 = _exit_vector()
	var facing_yaw: float = rad_to_deg(atan2(exit_dir.x, exit_dir.z)) + MODEL_FACING_CALIBRATION_DEGREES
	model.rotation_degrees = visual_resource.model_rotation_degrees + Vector3(0.0, facing_yaw, 0.0)

	_visual_pivot.add_child(model)
	_model_node = model
	_model_base_rotation_y = model.rotation_degrees.y
	_model_boarding_point = model.find_child("BoardingPoint", true, false) as Node3D
	_model_selection_point = model.find_child("SelectionPoint", true, false) as Node3D
	_apply_vehicle_color(model)

# Aplica a cor da fase (color_id) na carroceria do modelo 3D instanciado.
# Qual mesh e "a carroceria" e conhecimento exclusivo da cena do veiculo
# (ex.: CarSmall.tscn + car_visual.gd via @export var body_path); aqui so
# resolvemos color_id -> Color e chamamos o metodo publico, sem depender de
# nomes de mesh do Sketchfab/GLB. Modelos que ainda nao implementam
# set_vehicle_color (ex.: veiculos sem essa cena de suporte) simplesmente
# mantem a cor original do GLB.
func _apply_vehicle_color(model: Node3D) -> void:
	if not model.has_method("set_vehicle_color"):
		return
	var color: Color = COLOR_MAP.get(color_id, DEFAULT_VEHICLE_COLOR)
	model.call("set_vehicle_color", color)

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
	var color: Color = COLOR_MAP.get(color_id, DEFAULT_VEHICLE_COLOR)
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
		ExitDirection.Value.UP: return Vector3(0.0, 0.0, -1.0)
		ExitDirection.Value.DOWN: return Vector3(0.0, 0.0, 1.0)
		ExitDirection.Value.LEFT: return Vector3(-1.0, 0.0, 0.0)
		ExitDirection.Value.RIGHT: return Vector3(1.0, 0.0, 0.0)
	return Vector3(1.0, 0.0, 0.0)

func _spawn_ground_puff(color: Color, count: int, delay: float = 0.0) -> void:
	for i: int in range(count):
		var puff := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.08
		mesh.height = 0.08
		puff.mesh = mesh
		puff.position = Vector3(randf_range(-0.22, 0.22), -0.18, randf_range(-0.28, 0.28))
		puff.scale = Vector3.ZERO
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.material_override = material
		add_child(puff)

		var tween := create_tween()
		tween.tween_interval(delay + float(i) * 0.018)
		tween.parallel().tween_property(puff, "scale", Vector3.ONE * randf_range(0.65, 1.05), 0.10)
		tween.parallel().tween_property(puff, "position", puff.position + Vector3(randf_range(-0.18, 0.18), 0.08, randf_range(-0.18, 0.18)), 0.18)
		tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.18)
		tween.tween_callback(puff.queue_free)

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

# Anel fino acima da sombra (mesmo eixo, level ligeiramente mais alto pra
# nunca dar z-fighting), comecando totalmente apagado. set_selectable() e
# quem liga/desliga o pulso -- construir aqui so garante que o no e o
# material ja existem antes do primeiro _refresh_selectable_highlights().
func _add_selectable_glow(width: float, depth: float) -> void:
	var glow := MeshInstance3D.new()
	glow.name = "SelectableGlow"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.016
	mesh.radial_segments = 28
	glow.mesh = mesh
	glow.scale = Vector3(maxf(width * 0.98, 0.86), 1.0, maxf(depth * 0.80, 0.76))
	glow.position = Vector3(0.0, -0.205, 0.07)
	var glow_color := Color("#ffd233")
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(glow_color, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = glow_color
	material.emission_energy_multiplier = 0.0
	glow.material_override = material
	add_child(glow)
	_selectable_glow = glow
	_selectable_glow_material = material

# Chamada pelo GameController (_refresh_selectable_highlights) toda vez que
# o estado muda: liga um pulso lento e discreto de "isto pode ser tocado
# agora" ou apaga o brilho. Mais fraco de proposito que animate_hint() (que
# continua sendo o destaque forte e temporario da Dica), pra nao competir
# visualmente com o resto da cena.
func set_selectable(is_selectable: bool) -> void:
	if is_selectable == _is_selectable:
		return
	_is_selectable = is_selectable
	if _selectable_tween != null and _selectable_tween.is_valid():
		_selectable_tween.kill()
	_selectable_tween = null
	if _selectable_glow_material == null:
		return
	if not is_selectable:
		var fade := create_tween()
		fade.tween_property(_selectable_glow_material, "albedo_color:a", 0.0, 0.18)
		fade.parallel().tween_property(_selectable_glow_material, "emission_energy_multiplier", 0.0, 0.18)
		return
	var pulse := create_tween()
	_selectable_tween = pulse
	pulse.set_loops()
	pulse.set_trans(Tween.TRANS_SINE)
	pulse.set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_selectable_glow_material, "albedo_color:a", 0.34, 0.62)
	pulse.parallel().tween_property(_selectable_glow_material, "emission_energy_multiplier", 0.55, 0.62)
	pulse.tween_property(_selectable_glow_material, "albedo_color:a", 0.10, 0.62)
	pulse.parallel().tween_property(_selectable_glow_material, "emission_energy_multiplier", 0.15, 0.62)

func _add_arrow_marker(width: float, depth: float) -> void:
	var arrow_label := Label3D.new()
	arrow_label.name = "ArrowIndicator"
	arrow_label.text = _marker_text()
	arrow_label.font_size = 220
	arrow_label.modulate = Color.WHITE
	arrow_label.outline_size = 26
	arrow_label.outline_modulate = Color(0.12, 0.16, 0.25, 0.85)
	arrow_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow_label.no_depth_test = true
	arrow_label.position = Vector3(0.0, 1.05, 0.0)
	# BUG real encontrado (Etapa 1): isto usava "scale" em cima do pixel_size
	# padrao (0.01), resultando numa altura final de ~0.017 unidades -- uma
	# fracao de pixel na tela, ou seja, a seta existia mas era invisivel na
	# pratica. pixel_size e a forma correta de dimensionar um Label3D; com
	# font_size=220 isso da uma seta de ~0.3-0.7 unidade (proporcional ao carro),
	# clara o suficiente pra ler de longe, e no_depth_test evita que o teto do
	# modelo 3D (carro "red", com GLB real) tampe a seta em certos angulos.
	arrow_label.pixel_size = 0.00145 * clampf(maxf(width, depth), 1.0, 2.2)
	add_child(arrow_label)

func _arrow_text() -> String:
	match exit_direction:
		ExitDirection.Value.UP: return "↑"
		ExitDirection.Value.DOWN: return "↓"
		ExitDirection.Value.LEFT: return "←"
		ExitDirection.Value.RIGHT: return "→"
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
