extends SceneTree

func _init() -> void:
	var files := [
		"res://scripts/game/passenger_3d.gd",
		"res://scripts/game/passenger_controller.gd",
		"res://scripts/game/passenger_crowd_controller.gd",
	]
	var ok := true
	for path: String in files:
		var script: GDScript = load(path)
		if script == null:
			print("FALHA AO CARREGAR ", path)
			ok = false
			continue
		var inst_err := script.reload()
		print(path, " reload()=", inst_err)
		if inst_err != OK:
			ok = false
	print("RESULT ok=", ok)
	quit()
