extends SceneTree

func _init() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: int = doc.append_from_file("res://assets/characters/passengers/passenger_01.glb", state)
	print("append_from_file err=", err)
	if err != OK:
		quit()
		return
	print("state animations names? checking json directly")
	var json: Dictionary = state.json
	var anims: Array = json.get("animations", [])
	print("json animations count=", anims.size())
	for a in anims:
		print("  name=", a.get("name"), " channels=", (a.get("channels", []) as Array).size())
	var root: Node = doc.generate_scene(state)
	print("=== GENERATED SCENE TREE ===")
	_dump(root, 0)
	quit()

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is AnimationPlayer:
		var ap := node as AnimationPlayer
		extra = " list=%s libs=%s" % [str(ap.get_animation_list()), str(ap.get_animation_library_list())]
	print(indent, node.name, " (", node.get_class(), ")", extra)
	for child in node.get_children():
		_dump(child, depth + 1)
