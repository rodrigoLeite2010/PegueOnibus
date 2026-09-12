extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://assets/characters/passengers/passenger_01.glb")
	var inst: Node = packed.instantiate()
	var ap: AnimationPlayer = _find(inst)
	for anim_name in ap.get_animation_list():
		var anim: Animation = ap.get_animation(anim_name)
		print(anim_name, " length=", anim.length, " loop_mode=", anim.loop_mode, " tracks=", anim.get_track_count())
	quit()

func _find(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := _find(c)
		if f != null:
			return f
	return null
