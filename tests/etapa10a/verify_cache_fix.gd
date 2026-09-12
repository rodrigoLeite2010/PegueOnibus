extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://assets/characters/passengers/passenger_01.glb")
	print("packed=", packed)
	var inst: Node = packed.instantiate()
	_dump(inst, 0)
	quit()

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is AnimationPlayer:
		var ap := node as AnimationPlayer
		extra = " list=%s libs=%s" % [str(ap.get_animation_list()), str(ap.get_animation_library_list())]
	if node is Skeleton3D:
		extra = " bones=%d" % (node as Skeleton3D).get_bone_count()
	print(indent, node.name, " (", node.get_class(), ")", extra)
	for child in node.get_children():
		_dump(child, depth + 1)
