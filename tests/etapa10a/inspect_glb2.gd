extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://assets/characters/passengers/passenger_01.glb")
	if packed == null:
		print("FALHA AO CARREGAR GLB")
		quit()
		return
	var inst: Node = packed.instantiate()
	print("=== ARVORE DE NOS (detalhe AnimationPlayer) ===")
	_dump(inst, 0)
	quit()

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	print(indent, node.name, " (", node.get_class(), ")")
	if node is AnimationPlayer:
		var ap := node as AnimationPlayer
		print(indent, "  get_animation_list() = ", ap.get_animation_list())
		print(indent, "  get_animation_library_list() = ", ap.get_animation_library_list())
		for lib_name in ap.get_animation_library_list():
			var lib: AnimationLibrary = ap.get_animation_library(lib_name)
			if lib != null:
				print(indent, "  lib '", lib_name, "' anims = ", lib.get_animation_list())
				for anim_name in lib.get_animation_list():
					var anim: Animation = lib.get_animation(anim_name)
					print(indent, "    anim '", anim_name, "' length=", anim.length, " tracks=", anim.get_track_count())
	for child in node.get_children():
		_dump(child, depth + 1)
