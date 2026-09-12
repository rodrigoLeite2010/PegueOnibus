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
	p_waiting_slots: int = 4,
	p_board_rows: int = 9,
	p_board_cols: int = 7,
	p_passengers: Array[String] = [],
	p_vehicles: Array[VehicleDefinition] = []
) -> void:
	id = p_id
	waiting_slots = 4
	board_rows = p_board_rows
	board_cols = p_board_cols
	vehicles = []
	for vehicle: VehicleDefinition in p_vehicles:
		vehicles.append(vehicle.duplicate_definition())
	passengers = _normalized_passengers(p_passengers, vehicles)

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
		4,
		board.get("rows", 9),
		board.get("cols", 7),
		parsed_passengers,
		parsed_vehicles
	)

# Garante que a fila tenha EXATAMENTE a soma das capacidades dos veiculos,
# por cor. Preserva a ordem original enquanto houver demanda daquela cor,
# remove passageiros excedentes e completa faltantes no fim. Assim uma fase
# nunca pode terminar com pessoas sobrando por erro de JSON/geracao.
static func _normalized_passengers(source: Array[String], vehicle_defs: Array[VehicleDefinition]) -> Array[String]:
	var required: Dictionary = {}
	for vehicle: VehicleDefinition in vehicle_defs:
		required[vehicle.color_id] = int(required.get(vehicle.color_id, 0)) + vehicle.capacity

	var used: Dictionary = {}
	var result: Array[String] = []
	for color_id: String in source:
		var need: int = int(required.get(color_id, 0))
		var have: int = int(used.get(color_id, 0))
		if have < need:
			result.append(color_id)
			used[color_id] = have + 1

	# Se o arquivo tinha passageiros a menos, completa por cor.
	for vehicle: VehicleDefinition in vehicle_defs:
		var color_id: String = vehicle.color_id
		var need: int = int(required.get(color_id, 0))
		var have: int = int(used.get(color_id, 0))
		while have < need:
			result.append(color_id)
			have += 1
		used[color_id] = have

	return result

func duplicate_definition() -> LevelDefinition:
	return LevelDefinition.new(id, waiting_slots, board_rows, board_cols, passengers, vehicles)
