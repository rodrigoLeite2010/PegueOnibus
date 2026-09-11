class_name PassengerController
extends Node3D

@export var color_id: String = "red"

const COLOR_MAP := {
	"red": Color("#ff4b4b"),
	"blue": Color("#2f91ff"),
	"green": Color("#35de45"),
	"yellow": Color("#ffd236"),
	"purple": Color("#9349ff"),
	"pink": Color("#ff43c8"),
	"orange": Color("#ff7b20"),
}

var _body_root: Node3D
var _leg_pivots: Array[Node3D] = []
var _arm_pivots: Array[Node3D] = []
var _idle_tween: Tween
var _walk_tween: Tween

func _ready() -> void:
	_build()

func setup(p_color_id: String) -> void:
	color_id = p_color_id
	_build()

# Velocidade dobrada em relacao ao original (0.57s -> 0.285s do total ate
# sumir dentro do carro). Uma rodada seguinte tentou dobrar de novo (~0.15s)
# mas ficou rapido demais e foi revertida a pedido -- fica neste ponto. O
# ciclo de passada acompanha a mesma proporcao (ver _start_walk_cycle).
func walk_to_and_board(target: Vector3) -> void:
	# Apresentacao apenas: a regra/assentos ja foram confirmados pelo GameEngine.
	# O boneco agora percorre uma rota curta em 3 trechos, vira para a direcao
	# do movimento, balanca bracos/pernas e faz um "hop" final para dentro.
	var start: Vector3 = position
	var approach: Vector3 = target + Vector3(0.0, 0.0, 0.34)
	var middle: Vector3 = start.lerp(approach, 0.58)
	middle.y += 0.025

	_face_towards(middle)
	_start_walk_cycle(0.0425)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", middle, 0.045)
	tween.tween_property(self, "position", approach, 0.035)
	await tween.finished

	_face_towards(target)
	var hop := create_tween()
	hop.set_trans(Tween.TRANS_QUAD)
	hop.set_ease(Tween.EASE_OUT)
	hop.parallel().tween_property(self, "position", target + Vector3(0.0, 0.19, 0.0), 0.025)
	hop.parallel().tween_property(self, "scale", Vector3(0.78, 0.78, 0.78), 0.025)
	await hop.finished

	var enter := create_tween()
	enter.set_trans(Tween.TRANS_BACK)
	enter.set_ease(Tween.EASE_IN)
	enter.parallel().tween_property(self, "position", target + Vector3(0.0, 0.10, -0.05), 0.025)
	enter.parallel().tween_property(self, "scale", Vector3(0.06, 0.06, 0.06), 0.025)
	await enter.finished
	_stop_walk_cycle()
	_kill_idle()
	queue_free()

func _face_towards(target: Vector3) -> void:
	var delta: Vector3 = target - position
	if Vector2(delta.x, delta.z).length() < 0.001:
		return
	rotation.y = atan2(delta.x, delta.z)

func _build() -> void:
	_kill_idle()
	_stop_walk_cycle()
	# free() (nao queue_free()) e importante aqui: setup() chama _build() logo
	# depois que _ready() ja rodou um _build() com a cor padrao, e com
	# queue_free() os dois corpos ficavam sobrepostos por um frame antes da
	# remocao diferida acontecer.
	for child: Node in get_children():
		child.free()

	_body_root = Node3D.new()
	_body_root.name = "BodyRoot"
	add_child(_body_root)

	var shirt_color: Color = COLOR_MAP.get(color_id, Color.WHITE)
	var skin := Color("#f2b58a")
	var dark := shirt_color.darkened(0.14)
	var shoe := Color("#263238")

	# Torso toy-like, com silhueta mais humana do que a capsula anterior.
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.18, 0.24, 0.12)
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 0.27, 0.0)
	torso.material_override = _material(shirt_color, 0.46)
	_body_root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.105
	head_mesh.height = 0.21
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.48, 0.0)
	head.material_override = _material(skin, 0.58)
	_body_root.add_child(head)

	# Cabelo simples: hemisferio visual escuro deslocado para tras/cima.
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.108
	hair_mesh.height = 0.105
	hair.mesh = hair_mesh
	hair.position = Vector3(0.0, 0.525, -0.018)
	hair.scale = Vector3(1.0, 0.55, 1.0)
	hair.material_override = _material(Color("#3c2a24"), 0.7)
	_body_root.add_child(hair)

	# Olhos minimos para o personagem ler como pessoa mesmo pequeno na tela.
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.012
		eye_mesh.height = 0.024
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.034, 0.492, 0.092)
		eye.material_override = _material(Color("#20252b"), 0.8)
		_body_root.add_child(eye)

	_leg_pivots.clear()
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "LegPivot"
		hip.position = Vector3(side * 0.045, 0.16, 0.0)
		_body_root.add_child(hip)
		_leg_pivots.append(hip)

		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.052, 0.16, 0.055)
		leg.mesh = leg_mesh
		leg.position = Vector3(0.0, -0.08, 0.0)
		leg.material_override = _material(dark, 0.55)
		hip.add_child(leg)

		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.072, 0.05, 0.115)
		foot.mesh = foot_mesh
		foot.position = Vector3(0.0, -0.17, 0.028)
		foot.material_override = _material(shoe, 0.7)
		hip.add_child(foot)

	_arm_pivots.clear()
	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.name = "ArmPivot"
		shoulder.position = Vector3(side * 0.125, 0.34, 0.0)
		_body_root.add_child(shoulder)
		_arm_pivots.append(shoulder)

		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.045, 0.16, 0.05)
		arm.mesh = arm_mesh
		arm.position = Vector3(0.0, -0.075, 0.0)
		arm.material_override = _material(shirt_color.lightened(0.04), 0.5)
		shoulder.add_child(arm)

		var hand := MeshInstance3D.new()
		var hand_mesh := SphereMesh.new()
		hand_mesh.radius = 0.032
		hand_mesh.height = 0.064
		hand.mesh = hand_mesh
		hand.position = Vector3(0.0, -0.17, 0.0)
		hand.material_override = _material(skin, 0.6)
		shoulder.add_child(hand)

	# Leve bounce idle para nao parecer uma peca totalmente estatica.
	var idle := create_tween()
	_idle_tween = idle
	idle.set_loops()
	idle.set_trans(Tween.TRANS_SINE)
	idle.set_ease(Tween.EASE_IN_OUT)
	idle.tween_property(_body_root, "position:y", 0.018, 0.34)
	idle.tween_property(_body_root, "position:y", 0.0, 0.34)

# step_duration e o tempo de CADA quarto de passada. walk_to_and_board() usa
# um valor menor (passada mais rapida, ver acima); step_to() (fila 3D
# avancando um lugar) continua no ritmo original, sem pressa.
func _start_walk_cycle(step_duration: float = 0.085) -> void:
	if _leg_pivots.size() < 2 or _arm_pivots.size() < 2:
		return
	_stop_walk_cycle()
	var cycle := create_tween()
	_walk_tween = cycle
	cycle.set_loops()
	cycle.set_trans(Tween.TRANS_SINE)
	cycle.set_ease(Tween.EASE_IN_OUT)
	cycle.tween_property(_leg_pivots[0], "rotation_degrees:x", 28.0, step_duration)
	cycle.parallel().tween_property(_leg_pivots[1], "rotation_degrees:x", -28.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[0], "rotation_degrees:x", -22.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[1], "rotation_degrees:x", 22.0, step_duration)
	cycle.tween_property(_leg_pivots[0], "rotation_degrees:x", -28.0, step_duration)
	cycle.parallel().tween_property(_leg_pivots[1], "rotation_degrees:x", 28.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[0], "rotation_degrees:x", 22.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[1], "rotation_degrees:x", -22.0, step_duration)

func _stop_walk_cycle() -> void:
	if _walk_tween != null and _walk_tween.is_valid():
		_walk_tween.kill()
	_walk_tween = null
	for pivot: Node3D in _leg_pivots:
		pivot.rotation_degrees = Vector3.ZERO
	for pivot: Node3D in _arm_pivots:
		pivot.rotation_degrees = Vector3.ZERO

func _kill_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null

# Passo curto da fila avancando (FASE C): reaproveita o ciclo de caminhada
# por um instante, sem repetir toda a coreografia de embarque completo.
func step_to(target: Vector3) -> void:
	if position.distance_to(target) < 0.01:
		return
	_face_towards(target)
	_start_walk_cycle()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", target, 0.26)
	await tween.finished
	_stop_walk_cycle()

# Usado quando um novo boneco aparece no fim da fila 3D visivel.
func pop_in() -> void:
	scale = Vector3.ZERO
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE, 0.22)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
