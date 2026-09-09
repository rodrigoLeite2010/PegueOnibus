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

func _ready() -> void:
	_build()

func setup(p_color_id: String) -> void:
	color_id = p_color_id
	_build()

func walk_to_and_board(target: Vector3) -> void:
	# Movimento curto com dois "passos" para parecer caminhada, com as pernas
	# alternando para frente/tras, seguido de entrada no veiculo. A regra ja
	# foi validada pelo GameEngine.
	var start: Vector3 = position
	var middle: Vector3 = start.lerp(target, 0.52) + Vector3(0.0, 0.07, 0.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", middle, 0.16)
	if _body_root != null:
		tween.parallel().tween_property(_body_root, "rotation_degrees:z", -9.0, 0.08)
	tween.tween_property(self, "position", target + Vector3(0.0, 0.24, 0.0), 0.16)
	if _body_root != null:
		tween.parallel().tween_property(_body_root, "rotation_degrees:z", 9.0, 0.08)
	_animate_leg_swing()
	await tween.finished
	_reset_legs()

	var board_tween := create_tween()
	board_tween.set_trans(Tween.TRANS_BACK)
	board_tween.set_ease(Tween.EASE_IN)
	board_tween.parallel().tween_property(self, "position", target + Vector3(0.0, 0.18, 0.0), 0.12)
	board_tween.parallel().tween_property(self, "scale", Vector3(0.10, 0.10, 0.10), 0.12)
	await board_tween.finished
	queue_free()

func _build() -> void:
	for child: Node in get_children():
		child.queue_free()

	_body_root = Node3D.new()
	_body_root.name = "BodyRoot"
	add_child(_body_root)

	var color: Color = COLOR_MAP.get(color_id, Color.WHITE)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.09
	body_mesh.height = 0.32
	body_mesh.radial_segments = 12
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.18, 0.0)
	body.material_override = _material(color)
	_body_root.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.115
	head_mesh.height = 0.23
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.42, 0.0)
	head.material_override = _material(color.lightened(0.18))
	_body_root.add_child(head)

	# Cada perna tem um pivo no quadril: girar o pivo em X faz a perna balancar
	# para frente/tras de verdade durante a caminhada, em vez de so deslizar.
	_leg_pivots.clear()
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "LegPivot"
		hip.position = Vector3(side * 0.045, 0.14, 0.0)
		_body_root.add_child(hip)
		_leg_pivots.append(hip)

		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.045, 0.14, 0.05)
		leg.mesh = leg_mesh
		leg.position = Vector3(0.0, -0.07, 0.0)
		leg.material_override = _material(color.darkened(0.05))
		hip.add_child(leg)

		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.07, 0.05, 0.11)
		foot.mesh = foot_mesh
		foot.position = Vector3(0.0, -0.145, 0.025)
		foot.material_override = _material(color.darkened(0.12))
		hip.add_child(foot)

func _animate_leg_swing() -> void:
	if _leg_pivots.size() < 2:
		return
	var swing_angle := 24.0
	var step_time := 0.08
	var left: Node3D = _leg_pivots[0]
	var right: Node3D = _leg_pivots[1]
	var leg_tween := create_tween()
	leg_tween.set_trans(Tween.TRANS_SINE)
	leg_tween.set_ease(Tween.EASE_IN_OUT)
	leg_tween.set_loops(2)
	leg_tween.tween_property(left, "rotation_degrees:x", swing_angle, step_time)
	leg_tween.parallel().tween_property(right, "rotation_degrees:x", -swing_angle, step_time)
	leg_tween.tween_property(left, "rotation_degrees:x", -swing_angle, step_time)
	leg_tween.parallel().tween_property(right, "rotation_degrees:x", swing_angle, step_time)

func _reset_legs() -> void:
	for pivot: Node3D in _leg_pivots:
		pivot.rotation_degrees = Vector3.ZERO

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.58
	return material
