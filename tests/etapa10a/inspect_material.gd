extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://assets/characters/passengers/passenger_01.glb")
	var inst: Node = packed.instantiate()
	for child in inst.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mat: Material = mi.mesh.surface_get_material(0)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				print("albedo_texture: ", bm.albedo_texture)
				print("normal_enabled: ", bm.normal_enabled, " normal_texture: ", bm.normal_texture)
				print("metallic: ", bm.metallic, " roughness: ", bm.roughness, " metallic_texture: ", bm.metallic_texture, " roughness_texture: ", bm.roughness_texture)
				print("cast_shadow (MeshInstance3D): ", mi.cast_shadow)
	quit()
