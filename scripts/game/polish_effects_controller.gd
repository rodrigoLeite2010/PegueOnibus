class_name PolishEffectsController
extends Node

# ETAPA 7 (refatoracao segura, SEM mudanca visual/gameplay): extraido de
# GameController. Reune os efeitos puramente visuais (particulas
# procedurais, popups, feedback de vaga liberada) que antes eram metodos
# privados de GameController -- o CODIGO e exatamente o mesmo, so mudou de
# arquivo e perdeu o prefixo "_spawn"/"_play" (agora e a API publica deste
# controller). Nenhuma logica de jogo mora aqui: quem decide QUANDO chamar
# cada efeito continua sendo GameController, a partir dos eventos do
# GameEngine.
#
# Instanciado em runtime por GameController._ready() (nao existe como no
# na cena .tscn) -- ver GameController._create_polish_effects(). Isso evita
# qualquer edicao da cena e mantem o comportamento 100% identico ao de
# antes da extracao.
#
# Dependencias injetadas via setup(), nunca @onready: este no nao pertence
# a arvore de GameController.tscn, entao nao teria como resolver caminhos
# como $VFX sozinho.
var _vfx_root: Node3D
var _board: BoardController

# ETAPA 5, item 1 (ver comentario original em GameController): limite de
# frequencia do som de embarque durante a cascata da PolishTest -- movido
# pra ca junto com play_board_sfx_throttled(), unico lugar que usa.
var _last_polish_board_sfx_ms: int = -1000000
const POLISH_BOARD_SFX_MIN_INTERVAL_MS := 45


func setup(vfx_root: Node3D, board: BoardController) -> void:
	_vfx_root = vfx_root
	_board = board


# ETAPA 5, item 3 (PolishTest exclusivamente): particula discreta na base do
# veiculo ao confirmar um toque valido -- poucos elementos (6), sobe pouco e
# some rapido (~0.22s), reforca o toque sem competir com o proprio "pop" do
# carro (animate_valid_tap_polished, que e so escala).
func tap_spark(spawn_position: Vector3) -> void:
	for i: int in range(6):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.035
		mesh.height = 0.035
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.05, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = material
		_vfx_root.add_child(piece)
		var angle: float = (TAU / 6.0) * float(i)
		var direction := Vector3(cos(angle), 0.5, sin(angle))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.30, 0.22)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.22)
		tween.tween_callback(piece.queue_free)

# Usado tanto pelas fases normais (_play_boarding_events) quanto pela
# PolishTest (_play_boarding_events_polished/_run_cascaded_boarding) -- ja
# era assim antes da extracao, comportamento identico.
func boarding_spark(spawn_position: Vector3, color_id: String) -> void:
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
		_vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.6, 1.2), randf_range(-1.0, 1.0))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.55, 0.28)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.28)
		tween.tween_callback(piece.queue_free)

# ETAPA 5, item 1: ver comentario de _last_polish_board_sfx_ms acima -- limita
# a FREQUENCIA do som de embarque durante a cascata (nunca o efeito visual),
# pra um onibus de 40 lugares nao soar como 40 sons colados. So usado no
# caminho da fase 950.
func play_board_sfx_throttled() -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_polish_board_sfx_ms < POLISH_BOARD_SFX_MIN_INTERVAL_MS:
		return
	_last_polish_board_sfx_ms = now_ms
	AudioManager.play_sfx("passenger_board")

# ETAPA 5, item 7 (PolishTest exclusivamente): feedback rapido (~0.3s) no
# instante em que uma vaga fica livre -- o "+" aparece com pop (em vez de
# so trocar "visible" instantaneo), o piso da vaga pulsa (clareia e volta) e
# uma pequena particula verde sobe e some. Ensina visualmente "uma vaga
# acabou de abrir". Reaproveita os nos "SlotPlus"/"Pad" ja criados em
# BoardingAreaController (ver Etapa 7, item 4); nao cria nenhum no novo na
# vaga.
func slot_freed_feedback_polished(marker: Marker3D) -> void:
	var plus_label: Label3D = marker.get_node_or_null("SlotPlus") as Label3D
	if plus_label != null:
		plus_label.scale = Vector3.ZERO
		var pop_tween := create_tween()
		pop_tween.set_trans(Tween.TRANS_BACK)
		pop_tween.set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(plus_label, "scale", Vector3.ONE * 1.2, 0.14)
		pop_tween.tween_property(plus_label, "scale", Vector3.ONE, 0.10)
	var pad: MeshInstance3D = marker.get_node_or_null("Pad") as MeshInstance3D
	if pad != null:
		var pad_material: StandardMaterial3D = pad.material_override as StandardMaterial3D
		if pad_material != null:
			var base_color: Color = pad_material.albedo_color
			var pulse_tween := create_tween()
			pulse_tween.tween_property(pad_material, "albedo_color", Color("#3f8f5c"), 0.10)
			pulse_tween.tween_property(pad_material, "albedo_color", base_color, 0.18)
	_slot_freed_spark(marker.global_position)

func _slot_freed_spark(spawn_position: Vector3) -> void:
	for i: int in range(6):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.04
		mesh.height = 0.04
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.05, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#63ef91")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = material
		_vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-0.6, 0.6), randf_range(0.8, 1.3), randf_range(-0.6, 0.6))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.4, 0.3)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.3)
		tween.tween_callback(piece.queue_free)

# ETAPA 5, itens 8-9 (PolishTest exclusivamente): "+10" que aparece com pop,
# sobe levemente e desaparece (~0.75s), perto do veiculo/vaga que acabou de
# completar. Nunca toca em Wallet -- ver GameController._polish_local_coin_balance.
func coin_popup(spawn_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = "+10"
	label.font_size = 48
	label.outline_size = 12
	label.modulate = Color("#ffd233")
	label.outline_modulate = Color(0.35, 0.22, 0.0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = spawn_position + Vector3(0.0, 0.9, 0.0)
	_vfx_root.add_child(label)
	label.scale = Vector3.ZERO
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE, 0.12)
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector3(0.0, 0.55, 0.0), 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.40)
	tween.chain().tween_callback(label.queue_free)

# Usado por qualquer fase (normal ou PolishTest) ao vencer -- ja era assim
# antes da extracao.
func win_particles() -> void:
	AudioManager.vibrate(90)
	var center: Vector3 = _board.get_board_center()
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
		_vfx_root.add_child(piece)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + Vector3(randf_range(-2.4, 2.4), randf_range(1.4, 2.6), randf_range(-2.4, 2.4)), 0.45)
		tween.tween_property(piece, "position:y", 0.1, 0.5)
		tween.tween_callback(piece.queue_free)

func vehicle_complete_burst(spawn_position: Vector3, color_id: String) -> void:
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
		_vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.7, 1.4), randf_range(-1.0, 1.0))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.75, 0.34)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.34)
		tween.tween_callback(piece.queue_free)
