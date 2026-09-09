class_name VehicleController
extends Node3D

signal pressed(vehicle_id: String)

@export var vehicle_id: String = ""
@export var color_id: String = "red"
@export var footprint_rows: int = 2
@export var footprint_cols: int = 1
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

var visual_resource: VehicleVisualResource

func _ready() -> void:
	rebuild()

func setup_from_state(vehicle: VehicleState, cell_size: float) -> void:
	vehicle_id = vehicle.id
	color_id = vehicle.color_id
	footprint_rows = vehicle.footprint_rows
	footprint_cols = vehicle.footprint_cols
	exit_direction = vehicle.exit_direction
	position = Vector3(
		(vehicle.col + vehicle.footprint_cols * 0.5) * cell_size,
		0.34,
		(vehicle.row + vehicle.footprint_rows * 0.5) * cell_size
	)
	rebuild()

func rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()

	visual_resource = VehicleVisualLibrary.get_for_color(color_id)
	var color: Color = COLOR_MAP.get(color_id, Color.WHITE)
	var width: float = maxf(0.78, float(footprint_cols) * 0.86)
	var depth: float = maxf(0.78, float(footprint_rows) * 0.86)
	var long_axis_is_z: bool = depth >= width

	_add_shadow(width, depth)
	if _has_configured_visual():
		_add_configured_visual(width, depth, color, long_axis_is_z)
	else:
		_add_body(color, width, depth, long_axis_is_z)
		_add_windows(width, depth, long_axis_is_z)
	_add_arrow_marker(width, depth)
	if not _has_configured_visual():
		_add_wheels(width, depth, long_axis_is_z)
	_add_input_area(width, depth)

func get_boarding_point() -> Vector3:
	if visual_resource != null:
		return global_position + visual_resource.door_offset
	return global_position + Vector3(0.0, 0.0, -0.35)

func animate_valid_tap() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3(1.08, 1.08, 1.08), 0.08)
	tween.tween_property(self, "scale", Vector3.ONE, 0.1)

func animate_blocked() -> void:
	var start_position := position
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", start_position + Vector3(-0.12, 0.0, 0.0), 0.045)
	tween.tween_property(self, "position", start_position + Vector3(0.12, 0.0, 0.0), 0.06)
	tween.tween_property(self, "position", start_position + Vector3(-0.08, 0.0, 0.0), 0.05)
	tween.tween_property(self, "position", start_position, 0.055)

func animate_exit() -> void:
	var direction := _exit_vector()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "position", position + direction * 7.0 + Vector3(0.0, 0.35, 0.0), 0.46)
	tween.parallel().tween_property(self, "scale", Vector3(0.82, 0.82, 0.82), 0.46)
	tween.tween_callback(func() -> void: visible = false)

func _add_input_area(width: float, depth: float) -> void:
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var height := 0.9
	if visual_resource != null:
		height = visual_resource.collider_height
	box.size = Vector3(width, height, depth)
	shape.shape = box
	shape.position = Vector3(0.0, 0.18, 0.0)
	area.add_child(shape)
	area.input_event.connect(_on_input_event)
	add_child(area)

func _has_configured_visual() -> bool:
	if visual_resource == null:
		return false
	return visual_resource.sprite_texture != null or visual_resource.model_scene != null

func _add_configured_visual(width: float, depth: float, color: Color, long_axis_is_z: bool) -> void:
	if visual_resource.model_scene != null:
		_add_model_visual(width, depth)
		return
	if visual_resource.sprite_texture != null:
		_add_sprite_visual(width, depth)
		return
	_add_body(color, width, depth, long_axis_is_z)
	_add_windows(width, depth, long_axis_is_z)

func _add_model_visual(_width: float, _depth: float) -> void:
	var model := visual_resource.model_scene.instantiate() as Node3D
	if model == null:
		return
	model.position = Vector3(0.0, visual_resource.sprite_vertical_offset, 0.0)
	model.scale = Vector3.ONE * visual_resource.sprite_scale
	add_child(model)

func _add_sprite_visual(width: float, depth: float) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = visual_resource.sprite_texture
	sprite.pixel_size = 0.0038
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = Vector3(0.0, visual_resource.sprite_vertical_offset, 0.0)
	var texture_size: Vector2 = sprite.texture.get_size()
	var target_width := width * 0.86
	var target_height := depth * 0.86
	var current_width := texture_size.x * sprite.pixel_size
	var current_height := texture_size.y * sprite.pixel_size
	if current_width > 0.0 and current_height > 0.0:
		var factor: float = minf(target_width / current_width, target_height / current_height)
		factor *= visual_resource.sprite_scale
		sprite.scale = Vector3(factor, factor, factor)
	add_child(sprite)

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
		"up":
			return Vector3(0.0, 0.0, -1.0)
		"down":
			return Vector3(0.0, 0.0, 1.0)
		"left":
			return Vector3(-1.0, 0.0, 0.0)
		"right":
			return Vector3(1.0, 0.0, 0.0)
	return Vector3(1.0, 0.0, 0.0)

func _add_shadow(width: float, depth: float) -> void:
	var shadow := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.025
	mesh.radial_segments = 32
	shadow.mesh = mesh
	shadow.scale = Vector3(width * 0.95, 1.0, depth * 0.7)
	shadow.position = Vector3(0.0, -0.24, 0.06)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.26, 0.34, 0.26)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	shadow.material_override = material
	add_child(shadow)

func _add_body(color: Color, width: float, depth: float, long_axis_is_z: bool) -> void:
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = minf(width, depth) * 0.42
	mesh.height = maxf(width, depth)
	mesh.radial_segments = 24
	mesh.rings = 8
	body.mesh = mesh
	body.rotation_degrees = Vector3(90.0, 0.0, 0.0) if long_axis_is_z else Vector3(0.0, 0.0, 90.0)
	body.position = Vector3(0.0, 0.0, 0.0)
	body.material_override = _make_material(color, 0.48)
	add_child(body)

	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(width * 0.74, 0.22, depth * 0.56)
	deck.mesh = deck_mesh
	deck.position = Vector3(0.0, 0.24, 0.0)
	deck.material_override = _make_material(color.lightened(0.16), 0.5)
	add_child(deck)

func _add_windows(width: float, depth: float, long_axis_is_z: bool) -> void:
	var window_count: int = 3 if maxf(width, depth) > 1.7 else 2
	for index: int in range(window_count):
		var window := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.2, 0.035, 0.28) if long_axis_is_z else Vector3(0.28, 0.035, 0.2)
		window.mesh = mesh
		var spread: float = (float(index) - float(window_count - 1) * 0.5) * 0.34
		window.position = Vector3(spread, 0.38, -depth * 0.12) if long_axis_is_z else Vector3(-width * 0.12, 0.38, spread)
		window.material_override = _make_material(Color("#dff6ff"), 0.22)
		add_child(window)

func _add_arrow_marker(width: float, depth: float) -> void:
	if _has_configured_visual():
		_add_sprite_arrow(width, depth)
		return
	var arrow := MeshInstance3D.new()
	var arrow_mesh := BoxMesh.new()
	if exit_direction == "left" or exit_direction == "right":
		arrow_mesh.size = Vector3(width * 0.48, 0.04, 0.11)
	else:
		arrow_mesh.size = Vector3(0.11, 0.04, depth * 0.48)
	arrow.mesh = arrow_mesh
	arrow.position = Vector3(0.0, 0.52, 0.0)
	arrow.material_override = _make_material(Color("#ffffff"), 0.3)
	add_child(arrow)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.24, 0.045, 0.24)
	head.mesh = head_mesh
	match exit_direction:
		"up": head.position = Vector3(0.0, 0.54, -depth * 0.24)
		"down": head.position = Vector3(0.0, 0.54, depth * 0.24)
		"left": head.position = Vector3(-width * 0.24, 0.54, 0.0)
		"right": head.position = Vector3(width * 0.24, 0.54, 0.0)
		_: head.position = Vector3.ZERO
	head.material_override = _make_material(Color("#ffffff"), 0.25)
	add_child(head)

func _add_sprite_arrow(width: float, depth: float) -> void:
	var arrow_label := Label3D.new()
	arrow_label.text = _arrow_text()
	arrow_label.font_size = 72
	arrow_label.modulate = Color.WHITE
	arrow_label.outline_size = 10
	arrow_label.outline_modulate = Color(0.18, 0.22, 0.3, 0.7)
	arrow_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow_label.position = Vector3(0.0, 0.92, 0.0)
	arrow_label.scale = Vector3(0.012, 0.012, 0.012) * maxf(width, depth)
	add_child(arrow_label)

func _arrow_text() -> String:
	match exit_direction:
		"up":
			return "↑"
		"down":
			return "↓"
		"left":
			return "←"
		"right":
			return "→"
	return "→"

func _add_wheels(width: float, depth: float, long_axis_is_z: bool) -> void:
	var offsets: Array[Vector3] = [
		Vector3(-width * 0.39, -0.08, -depth * 0.34),
		Vector3(width * 0.39, -0.08, -depth * 0.34),
		Vector3(-width * 0.39, -0.08, depth * 0.34),
		Vector3(width * 0.39, -0.08, depth * 0.34),
	]
	for offset: Vector3 in offsets:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.09
		wheel_mesh.bottom_radius = 0.09
		wheel_mesh.height = 0.12
		wheel_mesh.radial_segments = 14
		wheel.mesh = wheel_mesh
		wheel.position = offset
		wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0) if long_axis_is_z else Vector3(90.0, 0.0, 0.0)
		wheel.material_override = _make_material(Color("#2d3340"), 0.8)
		add_child(wheel)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material
