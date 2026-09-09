class_name GameEvent
extends RefCounted

var type: String
var payload: Dictionary

func _init(p_type: String = "", p_payload: Dictionary = {}) -> void:
	type = p_type
	payload = p_payload.duplicate(true)

