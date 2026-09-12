extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://scenes/passengers/Passenger3D.tscn")
	if packed == null:
		print("FALHA: nao carregou Passenger3D.tscn")
		quit()
		return
	var inst: Node3D = packed.instantiate() as Node3D
	if inst == null:
		print("FALHA: instancia nula")
		quit()
		return
	print("OK instanciado: ", inst.name, " script=", inst.get_script())
	root.add_child(inst)
	await process_frame
	print("visual_root: ", inst.call("get_visual_root"))
	print("skeleton: ", inst.call("get_skeleton"))
	print("animation_player: ", inst.call("get_animation_player"))
	quit()
