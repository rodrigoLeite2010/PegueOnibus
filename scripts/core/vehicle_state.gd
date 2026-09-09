class_name VehicleState
extends RefCounted

const ON_BOARD := "on_board"
const WAITING := "waiting"
const COMPLETE := "complete"

var id: String
var type_id: String
var color_id: String
var capacity: int
var occupied_seats: int
var row: int
var col: int
var orientation: String
var exit_direction: String
var footprint_rows: int
var footprint_cols: int
var status: String

func _init(definition: VehicleDefinition = null) -> void:
	if definition == null:
		return
	id = definition.id
	type_id = definition.type_id
	color_id = definition.color_id
	capacity = definition.capacity
	occupied_seats = 0
	row = definition.row
	col = definition.col
	orientation = definition.orientation
	exit_direction = definition.exit_direction
	footprint_rows = definition.footprint_rows
	footprint_cols = definition.footprint_cols
	status = ON_BOARD

func duplicate_state() -> VehicleState:
	var copy := VehicleState.new()
	copy.id = id
	copy.type_id = type_id
	copy.color_id = color_id
	copy.capacity = capacity
	copy.occupied_seats = occupied_seats
	copy.row = row
	copy.col = col
	copy.orientation = orientation
	copy.exit_direction = exit_direction
	copy.footprint_rows = footprint_rows
	copy.footprint_cols = footprint_cols
	copy.status = status
	return copy
