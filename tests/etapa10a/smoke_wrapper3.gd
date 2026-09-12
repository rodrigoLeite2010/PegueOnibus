extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://scenes/passengers/Passenger3D.tscn")
	var inst = scene.instantiate()
	# Propositalmente SEM add_child/await aqui -- e exatamente a sequencia que
	# PassengerController._build_glb_visual() usa (instantiate -> add_child no
	# _body_root -> uso imediato no mesmo frame).
	print("visual_root=", inst.get_visual_root())
	print("skeleton=", inst.get_skeleton())
	print("animation_player=", inst.get_animation_player())
	print("has_animations=", inst.has_animations())
	inst.play_idle(3.0)
	print("after play_idle: current_animation=", inst.get_animation_player().current_animation, " pos=", inst.get_animation_player().current_animation_position)
	inst.play_walk()
	print("after play_walk: current_animation=", inst.get_animation_player().current_animation)
	inst.play_run()
	print("after play_run: current_animation=", inst.get_animation_player().current_animation)
	print("loop_mode idle=", inst.get_animation_player().get_animation("preset_biped_idle").loop_mode)
	quit()
