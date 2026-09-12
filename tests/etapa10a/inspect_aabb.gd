extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://assets/characters/passengers/passenger_01.glb")
	var inst: Node3D = packed.instantiate()
	var mi: MeshInstance3D = null
	for child in inst.get_children():
		if child is MeshInstance3D:
			mi = child
	if mi == null:
		print("sem MeshInstance3D direto, procurando recursivo")
		quit()
		return
	var aabb: AABB = mi.mesh.get_aabb()
	print("AABB position=", aabb.position, " size=", aabb.size)
	print("altura(Y)=", aabb.size.y, " largura(X)=", aabb.size.x, " profundidade(Z)=", aabb.size.z)
	print("mesh.get_aabb() usa espaco local do MeshInstance3D (transform=", mi.transform, ")")
	quit()
