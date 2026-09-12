extends SceneTree

func _init() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: int = doc.append_from_file("res://assets/characters/passengers/passenger_01.glb", state)
	if err != OK:
		print("FALHA append_from_file err=", err)
		quit()
		return
	var root: Node = doc.generate_scene(state)
	print("root=", root, " class=", root.get_class())

	# Empacota exatamente como o importador de cena faria.
	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	print("pack_err=", pack_err)
	if pack_err != OK:
		print("FALHA ao empacotar")
		quit()
		return

	var dest_path := "res://.godot/imported/passenger_01.glb-00cf597de0b8a43e3db5e3700bca9009.scn"
	var save_err: int = ResourceSaver.save(packed, dest_path)
	print("save_err=", save_err, " dest=", dest_path)
	quit()
