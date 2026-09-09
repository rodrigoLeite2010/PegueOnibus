class_name LevelDefinition
extends RefCounted

var id: int
var waiting_slots: int
var board_rows: int
var board_cols: int
var passengers: Array[String]
var vehicles: Array[VehicleDefinition]

func _init(
	p_id: int = 1,
	p_waiting_slots: int = 3,
	p_board_rows: int = 9,
	p_board_cols: int = 7,
	p_passengers: Array[String] = [],
	p_vehicles: Array[VehicleDefinition] = []
) -> void:
	id = p_id
	waiting_slots = p_waiting_slots
	board_rows = p_board_rows
	board_cols = p_board_cols
	passengers = p_passengers.duplicate()
	vehicles = []
	for vehicle: VehicleDefinition in p_vehicles:
		vehicles.append(vehicle.duplicate_definition())

static func from_dictionary(data: Dictionary) -> LevelDefinition:
	var parsed_passengers: Array[String] = []
	for color_id: String in data.get("passengers", []):
		parsed_passengers.append(color_id)

	var parsed_vehicles: Array[VehicleDefinition] = []
	for item: Dictionary in data.get("vehicles", []):
		parsed_vehicles.append(VehicleDefinition.new(
			item.get("id", ""),
			item.get("type", "car"),
			item.get("color", "red"),
			item.get("capacity", 2),
			item.get("row", 0),
			item.get("col", 0),
			item.get("orientation", "vertical"),
			item.get("exit_direction", "up"),
			item.get("footprint_rows", 0),
			item.get("footprint_cols", 0)
		))

	var board: Dictionary = data.get("board", {})
	return LevelDefinition.new(
		data.get("id", 1),
		data.get("waiting_slots", 3),
		board.get("rows", 9),
		board.get("cols", 7),
		parsed_passengers,
		parsed_vehicles
	)

func duplicate_definition() -> LevelDefinition:
	return LevelDefinition.new(id, waiting_slots, board_rows, board_cols, passengers, vehicles)
