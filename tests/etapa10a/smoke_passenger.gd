extends SceneTree
func _init() -> void:
	var doll: Node3D = preload("res://scenes/game/Passenger.tscn").instantiate() as Node3D
	root.add_child(doll)
	doll.call("setup", "red", false, false)
	print("PROCEDURAL OK, children=", doll.get_child_count())
	doll.call("setup", "blue", true, true)
	await process_frame
	print("GLB OK, children=", doll.get_child_count())
	quit()
