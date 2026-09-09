class_name WaitingSlotState
extends RefCounted

var index: int
var vehicle_id: String

func _init(p_index: int = 0, p_vehicle_id: String = "") -> void:
	index = p_index
	vehicle_id = p_vehicle_id

func is_empty() -> bool:
	return vehicle_id == ""

func duplicate_state() -> WaitingSlotState:
	return WaitingSlotState.new(index, vehicle_id)

