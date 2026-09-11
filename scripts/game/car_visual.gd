extends Node3D

@export var body_path: NodePath

@onready var body: MeshInstance3D = get_node(body_path) as MeshInstance3D

	
func set_vehicle_color(new_color: Color) -> void:
	if body == null:
		push_error("Car body not found")
		return

	var source_material := body.get_active_material(0)

	if source_material == null:
		push_error("Car body material not found")
		return

	var material := source_material.duplicate() as StandardMaterial3D

	if material == null:
		push_error("Car body material is not StandardMaterial3D")
		return

	material.albedo_color = new_color
	body.set_surface_override_material(0, material)
