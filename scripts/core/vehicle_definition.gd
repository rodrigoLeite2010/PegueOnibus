class_name VehicleDefinition
extends RefCounted

var id: String
var type_id: String
var color_id: String
var capacity: int
var row: int
var col: int
var orientation: String
var exit_direction: String
var footprint_rows: int
var footprint_cols: int

func _init(
	p_id: String = "",
	p_type_id: String = "car",
	p_color_id: String = "red",
	p_capacity: int = 2,
	p_row: int = 0,
	p_col: int = 0,
	p_orientation: String = "vertical",
	p_exit_direction: String = "up",
	p_footprint_rows: int = 0,
	p_footprint_cols: int = 0
) -> void:
	id = p_id
	type_id = p_type_id
	color_id = p_color_id
	capacity = p_capacity
	row = p_row
	col = p_col
	orientation = p_orientation
	exit_direction = p_exit_direction
	footprint_rows = p_footprint_rows
	footprint_cols = p_footprint_cols
	_apply_default_footprint_if_needed()

func duplicate_definition() -> VehicleDefinition:
	return VehicleDefinition.new(id, type_id, color_id, capacity, row, col, orientation, exit_direction, footprint_rows, footprint_cols)

func _apply_default_footprint_if_needed() -> void:
	if footprint_rows > 0 and footprint_cols > 0:
		return
	var length: int = 2
	if type_id == "mini_bus" or type_id == "bus":
		length = 3
	if orientation == "horizontal":
		footprint_rows = 1
		footprint_cols = length
	else:
		footprint_rows = length
		footprint_cols = 1
