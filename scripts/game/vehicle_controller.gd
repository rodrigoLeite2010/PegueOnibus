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
const BOARD_VEHICLE_SCALE := 0.86

# --- ETAPA 3 (Polish Test, fase 950 exclusivamente): "personalidade" por
# tipo no game feel de movimento -- nunca usado fora dos metodos
# "_polished" abaixo, entao nenhuma fase normal e afetada. Chaves cobrem os
# 3 tipos oficiais mais os aliases ja usados em VehicleVisualLibrary/
# VehicleDefinition ("car"=small_car, "van"=medium_car, "mini_bus"=bus).
const POLISH_TYPE_SPEED_MULTIPLIER := {
	"small_car": 1.00, "car": 1.00,
	"medium_car": 0.90, "van": 0.90,
	"bus": 0.80, "mini_bus": 0.80,
}
# Quanto mais alto, mais rapido o veiculo GIRA para encarar a nova direcao
# (peso do lerp aplicado a cada amostra da curva -- ver
# _apply_curve_progress_polished). Onibus com peso baixo = "curva pesada",
# small_car com peso alto = vira quase instantaneo (mas nunca 100% instantaneo
# de fato, ver item 4 do pedido: "evitar mudanca instantanea de rotacao").
const POLISH_TYPE_YAW_SMOOTHING := {
	"small_car": 0.34, "car": 0.34,
	"medium_car": 0.24, "van": 0.24,
	"bus": 0.16, "mini_bus": 0.16,
}
# Inclinacao (roll) maxima em graus durante a curva -- dentro dos "2-4 graus"
# pedidos, com o onibus inclinando um pouco menos (veiculo mais pesado/rigido).
const POLISH_TYPE_MAX_LEAN_DEGREES := {
	"small_car": 4.0, "car": 4.0,
	"medium_car": 3.0, "van": 3.0,
	"bus": 2.0, "mini_bus": 2.0,
}

# --- ETAPA 3B (ainda so fase 950): correcao de chegada/estacionamento. ---
# Escala final "estacionada" (item 6 do pedido), como fracao da escala que o
# veiculo JA tinha (a escala de tabuleiro da Etapa 2B, BOARD_VEHICLE_SCALE *
# multiplicador por tipo) -- nunca um valor absoluto novo, entao nunca muda
# a escala enquanto o veiculo ainda esta rodando pelo tabuleiro. Valores no
# meio das faixas pedidas (small 0.90-0.95 / medium 0.85-0.92 / bus 0.75-0.85).
const POLISH_TYPE_PARKED_SCALE_MULTIPLIER := {
	"small_car": 0.925, "car": 0.925,
	"medium_car": 0.885, "van": 0.885,
	"bus": 0.80, "mini_bus": 0.80,
}

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

# ETAPA 3 (item 10 do pedido): protecao contra taps repetidos SO durante o
# fluxo polished (feedback -> dirigindo -> estacionando). GameController
# consulta is_polish_busy() antes de reprocessar um toque na fase 950 (ver
# _process_vehicle_tap); fora da fase 950 esta flag nunca e tocada, entao
# nenhuma fase normal muda de comportamento.
var _polish_busy: bool = false
var _polish_feedback_tween: Tween
var _polish_roll_degrees: float = 0.0
var _polish_blocked_origin: Vector3 = Vector3.ZERO
# ETAPA 3B: guarda a escala "de tabuleiro" (antes do trecho final de
# aproximacao) para restaurar se precisar; ver _drive_final_approach_polished.
var _polish_original_scale: Vector3 = Vector3.ONE

# ETAPA 6B (item 3, "matar tweens residuais"): guarda o Tween que esta
# escrevendo rotation_degrees deste veiculo (drive_route_polished's
# move_tween OU _drive_final_approach_polished's tween) -- so pra poder
# encerra-lo de forma defensiva em snap_polish_parked_orientation(), caso
# ele por algum motivo ainda esteja "vivo" quando o snap final roda.
var _polish_route_tween: Tween

# ETAPA 6B (item 4): diferenca maxima aceitavel entre o yaw logico do
# veiculo estacionado e o yaw do slot antes de push_error.
const POLISH_YAW_MATCH_TOLERANCE_DEGREES := 1.0

# ETAPA 6 (investigacao do veiculo "atravessado"): GameController preenche
# isto com o indice da vaga (0..3) assim que decide pra onde este veiculo
# vai, ANTES de chamar drive_route_polished -- so serve pra identificar a
# vaga nos logs de diagnostico abaixo (_log_polish_rotation). Nao influencia
# nenhuma logica de posicionamento/rotacao real.
var polish_slot_index: int = -1

# ETAPA 6: liga o log de diagnostico de rotacao (3 pontos pedidos: antes da
# aproximacao final, assim que estaciona, e antes de sair). So imprime no
# console/log do Godot -- nenhum efeito visual ou de gameplay. Deixar
# ligado por padrao ate confirmarmos que o veiculo "atravessado" da
# gravacao da Etapa 5 nao se repete mais.
const POLISH_DEBUG_LOG_ROTATION := true

func _log_polish_rotation(stage: String) -> void:
	if not POLISH_DEBUG_LOG_ROTATION:
		return
	var turn_target: Node3D = _model_node if is_instance_valid(_model_node) else _visual_pivot
	var yaw: float = wrapf(turn_target.rotation_degrees.y, -180.0, 180.0) if turn_target != null else 0.0
	var roll: float = _visual_pivot.rotation_degrees.z if is_instance_valid(_visual_pivot) else 0.0
	print("[PolishRotation] vehicle_id=%s type_id=%s slot=%d stage=%s yaw=%.1f roll=%.1f pos=%s" % [
		vehicle_id, type_id, polish_slot_index, stage, yaw, roll, position
	])

func _ready() -> void:
	if get_child_count() == 0:
		rebuild()

# ETAPA 6, item 3 (PolishTest, fase 950 exclusivamente): quando true,
# rebuild() reforca a sombra de contato (maior/mais nitida no centro) e
# acrescenta um highlight superior sutil, pra o veiculo "saltar" do
# cenario. Nenhuma fase normal passa este argumento, entao o visual dela
# nunca muda.
var is_polish_visual: bool = false

func setup_from_state(vehicle: VehicleState, cell_size: float, p_is_polish_visual: bool = false) -> void:
	is_polish_visual = p_is_polish_visual
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
	scale = Vector3.ONE * BOARD_VEHICLE_SCALE
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
	if is_polish_visual:
		_add_polish_highlight(width, depth)
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
	var factor: float = BOARD_VEHICLE_SCALE
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

# ETAPA 3, item 10: GameController consulta isto (so na fase 950, ver
# _process_vehicle_tap) antes de reprocessar um toque -- enquanto true,
# nenhum novo toque neste veiculo comeca outro feedback/rota/estacionamento.
func is_polish_busy() -> bool:
	return _polish_busy

# ETAPA 3, item 1: squash/pop assimetrico (XZ estica um pouco, Y encolhe um
# pouco -- diferente do "escala uniforme" de animate_valid_tap acima) usando
# a escala ATUAL de _visual_pivot como base, nunca Vector3.ONE fixo caso ela
# ja nao seja ONE por algum outro efeito em andamento (por isso o kill() +
# reset explicito antes de comecar: sempre parte de um estado limpo
# conhecido, Vector3.ONE, que E a base de repouso real de _visual_pivot --
# o multiplicador de escala por tipo da Etapa 2B fica no NO PAI, nunca em
# _visual_pivot). Duracao total ~0.15s (dentro de 0.12-0.18s pedido).
func animate_valid_tap_polished() -> void:
	if _visual_pivot == null:
		return
	if _polish_feedback_tween != null and _polish_feedback_tween.is_valid():
		_polish_feedback_tween.kill()
	_visual_pivot.scale = Vector3.ONE
	var squash_scale := Vector3(1.055, 0.955, 1.055)
	_polish_feedback_tween = create_tween()
	_polish_feedback_tween.set_trans(Tween.TRANS_SINE)
	_polish_feedback_tween.set_ease(Tween.EASE_OUT)
	_polish_feedback_tween.tween_property(_visual_pivot, "scale", squash_scale, 0.07)
	_polish_feedback_tween.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.08)

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

# ETAPA 3, item 2: feedback de "bloqueado" para a PolishTest -- mesma ideia
# de shake lateral curto (posicao original -> desloca -> outro lado ->
# volta), com guarda explicita contra taps repetidos empilhando tweens (item
# 10): se ja existe um shake em andamento neste veiculo, mata e comeca de
# novo a partir da posicao original (nunca acumula deslocamento). Marca
# _polish_busy durante a duracao inteira do shake; GameController ja evita
# chamar isto de novo enquanto _polish_busy for true (ver is_polish_busy()),
# entao o kill() aqui e so uma segunda camada de seguranca.
func animate_blocked_polished() -> void:
	if _polish_feedback_tween != null and _polish_feedback_tween.is_valid():
		_polish_feedback_tween.kill()
		position = _polish_blocked_origin
	_polish_busy = true
	_polish_blocked_origin = position
	var start_position := _polish_blocked_origin
	var shake_axis := Vector3(0.12, 0.0, 0.0)
	if exit_direction == ExitDirection.Value.LEFT or exit_direction == ExitDirection.Value.RIGHT:
		shake_axis = Vector3(0.0, 0.0, 0.12)
	_polish_feedback_tween = create_tween()
	_polish_feedback_tween.set_trans(Tween.TRANS_SINE)
	_polish_feedback_tween.tween_property(self, "position", start_position - shake_axis, 0.05)
	_polish_feedback_tween.tween_property(self, "position", start_position + shake_axis, 0.07)
	_polish_feedback_tween.tween_property(self, "position", start_position - shake_axis * 0.6, 0.055)
	_polish_feedback_tween.tween_property(self, "position", start_position, 0.06)
	_polish_feedback_tween.tween_callback(func() -> void: _polish_busy = false)
	_flash_blocked_indicator()

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


# --- ETAPA 3 (Polish Test): variante "polida" de drive_route(), usada
# SOMENTE quando GameController detecta state.level_id == POLISH_TEST_LEVEL_ID
# (ver GameController._process_vehicle_tap). Reaproveita _build_route_curve()
# (geometria pura, identica para os dois casos) mas substitui o unico tween de
# progresso por 3 segmentos encadeados no MESMO Tween -- cada um com seu
# proprio trans/ease -- pra dar sensacao real de "acelera -> cruzeiro ->
# freia", em vez do easing unico e constante do drive_route() normal. A
# velocidade relativa por tipo (POLISH_TYPE_SPEED_MULTIPLIER) so afeta a
# duracao total aqui, nunca a logica de chegada (o destino continua sendo
# exatamente points[-1], igual ao drive_route() original). Marca _polish_busy
# no inicio e so libera depois do bounce de chegada, pra bloquear toques
# repetidos durante toda a animacao (ver is_polish_busy() e o guard em
# GameController._process_vehicle_tap).
func drive_route_polished(points: Array[Vector3], slot_yaw_degrees: float = 0.0) -> void:
	if points.is_empty():
		return
	_polish_busy = true

	# "Preparacao": mesmo hop de partida do drive_route() normal -- reforca a
	# sensacao de veiculo saindo de marcha antes de acelerar de verdade.
	if _visual_pivot != null:
		var lift := create_tween()
		lift.set_trans(Tween.TRANS_SINE)
		lift.set_ease(Tween.EASE_OUT)
		lift.tween_property(_visual_pivot, "position:y", 0.055, 0.06)
		lift.tween_property(_visual_pivot, "position:y", 0.0, 0.09)
	_spawn_ground_puff(Color(0.62, 0.56, 0.46, 0.4), 5)

	# ETAPA 3B: o ULTIMO ponto de "points" continua sendo exatamente o centro
	# da vaga (o Marker3D Slot0..Slot3), e o PENULTIMO ponto (ja calculado por
	# GameController._build_route_to_waiting_slot, alinhado na mesma X/coluna
	# do slot e posicionado bem na entrada da vaga na fase 950 -- ver o
	# "lane_z" polish-only la) funciona como o "ApproachPoint" pedido no item
	# 2. Em vez de deixar a chegada final dentro da MESMA curva arredondada do
	# resto da rota (o que deixava a orientacao final refem da tangente
	# amostrada e o carro por vezes atravessado), tratamos so o ultimo trecho
	# ApproachPoint->SlotCenter como um movimento reto e explicito em
	# _drive_final_approach_polished(), nunca amostrado da Curve3D. A curva
	# "normal" cobre so ate o ApproachPoint.
	var slot_center: Vector3 = points[points.size() - 1]
	var curve_points: Array[Vector3] = points.duplicate()
	curve_points.remove_at(curve_points.size() - 1)

	var waypoints: Array[Vector3] = [position]
	waypoints.append_array(curve_points)
	var curve: Curve3D = _build_route_curve(waypoints)
	var total_length: float = curve.get_baked_length()

	if total_length <= 0.001:
		if not curve_points.is_empty():
			position = curve_points[curve_points.size() - 1]
	else:
		var speed_mult: float = POLISH_TYPE_SPEED_MULTIPLIER.get(type_id, 1.0)
		var duration: float = clampf(total_length * 0.11, 0.32, 1.6) / maxf(speed_mult, 0.01)

		# Fases em distancia ao longo da curva (nao em tempo): ~20% pra
		# acelerar, ~20% pra desacelerar no final (dentro dos "15-25%" pedidos),
		# o resto e cruzeiro. Se a rota for curta demais pro cruzeiro caber,
		# os dois segmentos crescem pra cobrir a rota inteira sem deixar
		# nenhum trecho de fora.
		var accel_distance: float = total_length * 0.20
		var decel_distance: float = total_length * 0.20
		var cruise_distance: float = total_length - accel_distance - decel_distance
		if cruise_distance < 0.0:
			accel_distance = total_length * 0.5
			decel_distance = total_length * 0.5
			cruise_distance = 0.0

		var segments: Array[Dictionary] = []
		if accel_distance > 0.001:
			segments.append({"from": 0.0, "to": accel_distance, "trans": Tween.TRANS_SINE, "ease": Tween.EASE_IN, "weight": 0.28})
		if cruise_distance > 0.001:
			segments.append({"from": accel_distance, "to": accel_distance + cruise_distance, "trans": Tween.TRANS_LINEAR, "ease": Tween.EASE_IN_OUT, "weight": 0.44})
		if decel_distance > 0.001:
			segments.append({"from": accel_distance + cruise_distance, "to": total_length, "trans": Tween.TRANS_SINE, "ease": Tween.EASE_OUT, "weight": 0.28})

		var weight_sum: float = 0.0
		for segment: Dictionary in segments:
			weight_sum += float(segment["weight"])

		var move_tween := create_tween()
		_polish_route_tween = move_tween
		for segment: Dictionary in segments:
			move_tween.set_trans(segment["trans"] as Tween.TransitionType)
			move_tween.set_ease(segment["ease"] as Tween.EaseType)
			var segment_weight: float = float(segment["weight"])
			var segment_duration: float = duration * (segment_weight / weight_sum)
			move_tween.tween_method(_apply_curve_progress_polished.bind(curve, total_length), float(segment["from"]), float(segment["to"]), segment_duration)
		await move_tween.finished

	# Snap no ApproachPoint (remove qualquer residuo de amostragem da curva)
	# antes do trecho final reto e explicito. Se por algum motivo a rota nao
	# tinha nenhum ponto intermediario, o trecho final abaixo simplesmente
	# parte de onde o veiculo ja estava.
	if not curve_points.is_empty():
		position = curve_points[curve_points.size() - 1]

	await _drive_final_approach_polished(slot_center, slot_yaw_degrees)

	# Alinhamento exato final (o chamador TAMBEM faz snap de posicao E de
	# orientacao a partir do proprio Marker3D logo depois disso -- ver
	# GameController._process_vehicle_tap / snap_polish_parked_orientation).
	position = slot_center
	if _visual_pivot != null:
		_visual_pivot.rotation_degrees.z = 0.0
	_polish_roll_degrees = 0.0

	await _arrival_bounce_polished()
	_polish_busy = false

# ETAPA 3B (itens 1, 2, 3, 4 e 6 do pedido): trecho final reto do
# ApproachPoint ate o centro exato da vaga. Diferente de
# _apply_curve_progress_polished(), a orientacao final AQUI nunca depende de
# amostragem de Curve3D -- e calculada uma unica vez, direto do vetor
# ApproachPoint->SlotCenter (sempre praticamente puro -Z na fase 950, ja que
# o ApproachPoint recebido de GameController tem a MESMA X do slot_center).
# Tambem e onde a escala
# "estacionada" (item 6) e aplicada, com transicao suave, e SO durante este
# trecho -- o veiculo nunca muda de escala enquanto ainda esta a caminho.
func _drive_final_approach_polished(slot_center: Vector3, slot_yaw_degrees: float) -> void:
	_log_polish_rotation("antes_da_aproximacao")
	var start_position: Vector3 = position
	_polish_original_scale = scale
	var parked_scale_multiplier: float = POLISH_TYPE_PARKED_SCALE_MULTIPLIER.get(type_id, 0.9)
	var parked_scale: Vector3 = _polish_original_scale * parked_scale_multiplier

	var turn_target: Node3D = _model_node if is_instance_valid(_model_node) else _visual_pivot
	var target_yaw_degrees: float = 0.0
	if turn_target != null:
		var calibration: float = 0.0
		if turn_target == _model_node and visual_resource != null:
			calibration = MODEL_FACING_CALIBRATION_DEGREES + visual_resource.model_rotation_degrees.y
		# ETAPA 6B (item 1): a orientacao final NUNCA mais vem de
		# ApproachPoint->SlotCenter (nem de qualquer outra "direcao
		# anterior do veiculo") -- slot_yaw_degrees chega pronto do
		# chamador, lido direto do Marker3D Slot0..Slot3 (a MESMA fonte
		# usada depois em snap_polish_parked_orientation). So a calibracao
		# de modelo (diferenca legitima de autoria do GLB, ex.: onibus)
		# entra por cima; os 4 slots tem o mesmo slot_yaw_degrees, entao
		# todo veiculo do mesmo tipo termina no mesmo angulo, sempre.
		target_yaw_degrees = slot_yaw_degrees + calibration

	# Freio final (item 3): mais devagar que o resto da rota, proporcional a
	# distancia real do ApproachPoint (recebido de GameController) ate o
	# centro da vaga -- nunca robotico/fixo demais nem instantaneo.
	var final_duration: float = clampf(start_position.distance_to(slot_center) * 0.42, 0.30, 0.55)

	var tween := create_tween()
	_polish_route_tween = tween
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", slot_center, final_duration)
	tween.tween_property(self, "scale", parked_scale, final_duration)
	if turn_target != null:
		tween.tween_property(turn_target, "rotation_degrees:y", target_yaw_degrees, final_duration * 0.85)
	if _visual_pivot != null:
		tween.tween_property(_visual_pivot, "rotation_degrees:z", 0.0, final_duration * 0.6)
	await tween.finished

	# Trava explicita no fim -- o tween acima ja devia terminar exatamente
	# nesses valores, isso so cobre arredondamento de ponto flutuante. A
	# palavra REALMENTE final sobre posicao/orientacao e
	# snap_polish_parked_orientation(), chamada pelo GameController logo
	# depois do snap de posicao no Marker3D global.
	position = slot_center
	scale = parked_scale
	if turn_target != null:
		turn_target.rotation_degrees.y = wrapf(target_yaw_degrees, -180.0, 180.0)
	if _visual_pivot != null:
		_visual_pivot.rotation_degrees.z = 0.0
	_log_polish_rotation("estacionado")

# ETAPA 6B (itens 1, 3 e 4 -- PolishTest/fase 950 exclusivamente): ULTIMA
# palavra sobre a orientacao do veiculo estacionado, chamada pelo
# GameController logo depois de vehicle_node.global_position =
# final_marker.global_position (mesmo ponto, mesma logica -- so que pra
# rotacao). slot_yaw_degrees chega pronto (GameController le
# final_marker.global_rotation_degrees.y), entao esta funcao NUNCA calcula
# heading a partir de posicao/tangente/exit_direction. Idempotente: pode
# ser chamada mais de uma vez sem efeito colateral.
func snap_polish_parked_orientation(slot_yaw_degrees: float) -> void:
	# Item 3: encerra qualquer tween que ainda possa estar escrevendo
	# rotation_degrees deste veiculo (drive_route_polished/
	# _drive_final_approach_polished ja devem ter terminado a esta altura,
	# mas nunca assumimos isso).
	if _polish_route_tween != null and _polish_route_tween.is_valid():
		_polish_route_tween.kill()
	if _polish_feedback_tween != null and _polish_feedback_tween.is_valid():
		_polish_feedback_tween.kill()

	var turn_target: Node3D = _model_node if is_instance_valid(_model_node) else _visual_pivot
	var calibration: float = 0.0
	if turn_target == _model_node and visual_resource != null:
		calibration = MODEL_FACING_CALIBRATION_DEGREES + visual_resource.model_rotation_degrees.y

	if turn_target != null:
		turn_target.rotation_degrees.y = wrapf(slot_yaw_degrees + calibration, -180.0, 180.0)
	# Zera lean/roll/pitch residual (item 2: "VISUAL: roll = 0, pitch
	# residual = 0" -- nenhum efeito de _visual_pivot pode sobreviver ao
	# estacionamento).
	if _visual_pivot != null:
		_visual_pivot.rotation_degrees.z = 0.0
		_visual_pivot.rotation_degrees.x = 0.0
	_polish_roll_degrees = 0.0

	_log_polish_rotation("estacionado_slot_snap")

	# Item 4: assert/log temporario -- compara o yaw LOGICO do veiculo (sem
	# a calibracao de modelo, que e uma diferenca legitima de autoria do
	# GLB, ex.: onibus = +90 graus) contra o yaw do proprio slot. Qualquer
	# divergencia > 1 grau so pode significar que outra coisa escreveu
	# rotation_degrees.y depois deste snap -- nunca deveria acontecer.
	if turn_target != null:
		var logical_yaw: float = wrapf(turn_target.rotation_degrees.y - calibration, -180.0, 180.0)
		var diff: float = absf(wrapf(logical_yaw - slot_yaw_degrees, -180.0, 180.0))
		if diff > POLISH_YAW_MATCH_TOLERANCE_DEGREES:
			push_error("[PolishRotation] DIVERGENCIA vehicle_id=%s type_id=%s slot=%d vehicle_yaw=%.2f slot_yaw=%.2f diff=%.2f" % [
				vehicle_id, type_id, polish_slot_index, logical_yaw, slot_yaw_degrees, diff
			])

# Igual a _apply_curve_progress(), mas com duas diferencas pedidas na Etapa 3:
# (1) o giro (yaw) deixa de ser um snap instantaneo e passa a ser suavizado
# via lerp_angle, com peso por tipo (POLISH_TYPE_YAW_SMOOTHING) -- onibus gira
# mais devagar/pesado, small_car gira quase instantaneo mas nunca 100% snap;
# (2) a inclinacao (roll) usa um limite maximo por tipo
# (POLISH_TYPE_MAX_LEAN_DEGREES, dentro dos "2-4 graus" pedidos) e e sempre
# suavizada com lerp (inclusive ao voltar a zero no fim da curva), em vez da
# logica antiga que so suavizava o retorno a zero e fazia snap durante a
# curva. Guarda o angulo suavizado em _polish_roll_degrees entre chamadas.
func _apply_curve_progress_polished(distance: float, curve: Curve3D, total_length: float) -> void:
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
		var target_yaw_degrees: float = heading + calibration
		var yaw_weight: float = POLISH_TYPE_YAW_SMOOTHING.get(type_id, 0.3)
		var current_yaw_rad: float = deg_to_rad(turn_target.rotation_degrees.y)
		var target_yaw_rad: float = deg_to_rad(target_yaw_degrees)
		var smoothed_yaw_rad: float = lerp_angle(current_yaw_rad, target_yaw_rad, yaw_weight)
		turn_target.rotation_degrees.y = rad_to_deg(smoothed_yaw_rad)

	if _visual_pivot != null:
		var max_lean_degrees: float = POLISH_TYPE_MAX_LEAN_DEGREES.get(type_id, 3.0)
		var target_roll_degrees: float = 0.0
		if have_forward and have_backward:
			var turn_rate: float = wrapf(heading_forward - heading_backward, -180.0, 180.0)
			target_roll_degrees = clampf(turn_rate * 0.55, -max_lean_degrees, max_lean_degrees)
		_polish_roll_degrees = lerpf(_polish_roll_degrees, target_roll_degrees, 0.3)
		_visual_pivot.rotation_degrees.z = _polish_roll_degrees

# Chegada polida: bounce combinado (posicao Y sobe/desce + escala) em vez do
# "settle" so-de-escala do drive_route() normal -- pedido explicito da Etapa
# 3 (item 7). Duracao total 0.10+0.08+0.07 = 0.25s, dentro dos "0.18-0.25s"
# pedidos. Chamada apenas por drive_route_polished(), nunca pelo drive_route()
# normal.
func _arrival_bounce_polished() -> void:
	if _visual_pivot == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual_pivot, "position:y", 0.065, 0.10)
	tween.parallel().tween_property(_visual_pivot, "scale", Vector3(1.03, 1.03, 1.03), 0.10)
	tween.tween_property(_visual_pivot, "position:y", 0.0, 0.08)
	tween.parallel().tween_property(_visual_pivot, "scale", Vector3(0.98, 0.98, 0.98), 0.08)
	tween.tween_property(_visual_pivot, "scale", Vector3.ONE, 0.07)
	_spawn_ground_puff(Color(1.0, 1.0, 1.0, 0.5), 4, 0.05)
	await tween.finished

func animate_boarding_bounce() -> void:
	if _visual_pivot == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual_pivot, "position:y", 0.08, 0.07)
	tween.tween_property(_visual_pivot, "position:y", 0.0, 0.09)

# ETAPA 4B (Polish Test, fase 950 exclusivamente -- "SINCRONIZACAO DO
# VEICULO"): micro reacao de "veiculo lotado", tocada uma unica vez quando o
# ultimo passageiro da leva termina de embarcar, ANTES do veiculo comecar a
# sair (ver GameController._play_boarding_events_polished, ramo SlotFreed).
# So escala self.scale (a MESMA escala "estacionada" aplicada em
# _drive_final_approach_polished via POLISH_TYPE_PARKED_SCALE_MULTIPLIER) um
# pouco pra cima e de volta -- nunca _visual_pivot, que e reservado para
# feedback de toque/chegada. Usar a escala ATUAL como base (nunca um valor
# fixo) evita qualquer salto: o veiculo sai exatamente da escala em que
# estava estacionado.
func animate_vehicle_full_polished() -> void:
	var base_scale: Vector3 = scale
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", base_scale * 1.03, 0.07)
	tween.tween_property(self, "scale", base_scale, 0.08)
	await tween.finished

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


# ETAPA 4B (Polish Test, fase 950 exclusivamente): variante polida de
# drive_away_from_pickup(), usada SOMENTE quando um veiculo termina o
# embarque na fase 950 (ver GameController._play_boarding_events_polished).
# Causa do veiculo "atravessado"/diagonal ao sair (ETAPA 4B, problema 2):
# a versao generica acima gira o veiculo quase instantaneamente (tween de
# rotacao de so 0.16s, direcao fixa ~90 graus em relacao ao estacionamento)
# enquanto a translacao (0.48s, EASE_IN -- comeca devagar) mal tinha
# comecado: na pratica o carro ficava quase parado girando bruscamente e so
# depois arrancava, lendo como um snap diagonal. Aqui a saida reaproveita a
# MESMA curva suave + giro gradual (lerp por tipo, POLISH_TYPE_YAW_SMOOTHING)
# + inclinacao limitada por curvatura (POLISH_TYPE_MAX_LEAN_DEGREES) ja
# usadas em drive_route_polished/_apply_curve_progress_polished: o giro
# sempre parte do angulo REAL em que o veiculo esta (turn_target.rotation_
# degrees.y, lido ao vivo a cada amostra), nunca de um valor fixo, entao
# nunca ha salto instantaneo de rotacao.
func drive_away_from_pickup_polished(board_width: float) -> void:
	_log_polish_rotation("antes_da_saida")
	_spawn_ground_puff(Color(0.62, 0.56, 0.46, 0.4), 4)

	# Zera explicitamente qualquer lean/roll residual antes de comecar a
	# saida (pedido explicito da Etapa 4B). Defensivo: a chegada polida ja
	# devia ter deixado isto em 0 (ver drive_route_polished), mas nunca
	# assumimos isso -- a saida sempre parte de um estado visual limpo.
	if _visual_pivot != null:
		_visual_pivot.rotation_degrees.z = 0.0
	_polish_roll_degrees = 0.0

	# Ponto de partida SEMPRE a posicao/rotacao real estacionada (nunca um
	# valor presumido) -- o mesmo alvo de saida generico de antes, so que
	# percorrido por uma curva suave em vez de um tween reto + giro em separado.
	var start_position: Vector3 = position
	var target: Vector3 = start_position + Vector3(maxf(board_width * 0.65, 4.5), 0.18, -0.35)
	var curve: Curve3D = _build_route_curve([start_position, target])
	var total_length: float = curve.get_baked_length()

	if total_length <= 0.001:
		position = target
	else:
		var speed_mult: float = POLISH_TYPE_SPEED_MULTIPLIER.get(type_id, 1.0)
		var duration: float = clampf(total_length * 0.11, 0.32, 1.6) / maxf(speed_mult, 0.01)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_method(_apply_curve_progress_polished.bind(curve, total_length), 0.0, total_length, duration)
		if _visual_pivot != null:
			tween.parallel().tween_property(_visual_pivot, "scale", Vector3(0.88, 0.88, 0.88), duration)
		await tween.finished

	# Trava explicita no fim, mesmo criterio de drive_route_polished/
	# _drive_final_approach_polished: cobre qualquer arredondamento de ponto
	# flutuante e garante que nenhum lean residual sobrevive ao proximo uso
	# deste VehicleController (ele e removido logo em seguida via queue_free,
	# mas o estado limpo evita qualquer duvida futura).
	position = target
	if _visual_pivot != null:
		_visual_pivot.rotation_degrees.z = 0.0
	_polish_roll_degrees = 0.0


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
	# ETAPA 6: nenhum valor de ExitDirection bateu -- isso e exatamente a
	# classe de bug que deixaria um veiculo virado numa direcao arbitraria
	# (ex.: "atravessado") em vez da direcao real da vaga/saida, ja que TODA
	# orientacao do modelo (spawn, drive_route, drive_route_polished,
	# drive_away_from_pickup) parte deste vetor. Antes isso caia no fallback
	# RIGHT em silencio; agora fica registrado.
	push_warning("[PolishRotation] vehicle_id=%s type_id=%s: exit_direction invalido (%s) -- usando fallback RIGHT" % [vehicle_id, type_id, exit_direction])
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
	# ETAPA 6, item 3: sombra de contato um pouco maior e mais escura na
	# PolishTest -- reforca a leitura "o veiculo esta ACIMA do chao", sem
	# mexer em nenhuma cor logica. Fases normais mantem exatamente os
	# valores antigos.
	var shadow_scale_mult: float = 1.12 if is_polish_visual else 1.0
	var shadow_alpha: float = 0.26 if is_polish_visual else 0.18
	shadow.scale = Vector3(maxf(width * 0.82, 0.72) * shadow_scale_mult, 1.0, maxf(depth * 0.64, 0.62) * shadow_scale_mult)
	shadow.position = Vector3(0.0, -0.235, 0.07)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.14, 0.19, 0.28, shadow_alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	shadow.material_override = material
	add_child(shadow)

# ETAPA 6, item 3 (PolishTest exclusivamente): highlight bem sutil no topo
# do veiculo -- um disco quase transparente logo acima do teto, simulando
# uma luz pegando a carroceria sem precisar de um material PBR completo
# nem de luzes extras (custo zero de performance: e so mais um
# MeshInstance3D estatico, sem tween nem atualizacao por frame).
func _add_polish_highlight(width: float, depth: float) -> void:
	var highlight := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 0.5
	highlight.mesh = mesh
	highlight.scale = Vector3(maxf(width * 0.5, 0.32), 0.16, maxf(depth * 0.34, 0.24))
	highlight.position = Vector3(0.0, 0.62, -0.05)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.16)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight.material_override = material
	add_child(highlight)

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
