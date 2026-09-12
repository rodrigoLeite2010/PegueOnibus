extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://assets/characters/passengers/passenger_01.glb")
	if packed == null:
		print("FALHA AO CARREGAR GLB")
		quit()
		return
	var inst: Node = packed.instantiate()
	print("=== ARVORE DE NOS ===")
	_dump(inst, 0)
	print("=== RESUMO ===")
	var total_tris := 0
	var total_verts := 0
	var mesh_count := 0
	var materials := {}
	_collect(inst, materials)
	quit()

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var surf_count: int = mi.mesh.get_surface_count()
			var tris := 0
			var verts := 0
			for s in range(surf_count):
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
					var vcount: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					verts += vcount
				if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
					var icount: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
					tris += int(icount / 3.0)
				elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
					tris += int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
			extra = " [surfaces=%d verts=%d tris=%d]" % [surf_count, verts, tris]
	if node is Skeleton3D:
		extra = " [bones=%d]" % (node as Skeleton3D).get_bone_count()
	if node is AnimationPlayer:
		var ap := node as AnimationPlayer
		extra = " [anims=%s]" % str(ap.get_animation_list())
	print(indent, node.name, " (", node.get_class(), ")", extra)
	for child in node.get_children():
		_dump(child, depth + 1)

func _collect(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.mesh.surface_get_material(s)
				if mat == null:
					mat = mi.get_surface_override_material(s)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					var key: String = mat.resource_path if mat.resource_path != "" else str(mat.get_instance_id())
					if not materials.has(key):
						materials[key] = true
						var tex: Texture2D = bm.albedo_texture
						var tex_info := "sem albedo_texture"
						if tex != null:
							tex_info = "albedo %dx%d" % [tex.get_width(), tex.get_height()]
						print("MATERIAL ", key, " -> ", tex_info)
	for child in node.get_children():
		_collect(child, materials)
