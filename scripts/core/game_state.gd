class_name GameState
extends RefCounted

const PLAYING := "playing"
const WON := "won"
const LOST := "lost"

var level_id: int
var board_rows: int
var board_cols: int
var passenger_queue: Array[String]
var vehicles: Dictionary
var waiting_slots: Array[WaitingSlotState]
var status: String
var moves: int

func _init(level: LevelDefinition = null) -> void:
	vehicles = {}
	waiting_slots = []
	passenger_queue = []
	status = PLAYING
	moves = 0
	if level != null:
		load_level(level)

func load_level(level: LevelDefinition) -> void:
	level_id = level.id
	board_rows = level.board_rows
	board_cols = level.board_cols
	passenger_queue = level.passengers.duplicate()
	vehicles.clear()
	for definition: VehicleDefinition in level.vehicles:
		var vehicle := VehicleState.new(definition)
		vehicles[vehicle.id] = vehicle
	waiting_slots.clear()
	for index: int in range(level.waiting_slots):
		waiting_slots.append(WaitingSlotState.new(index))
	status = PLAYING
	moves = 0

func duplicate_state() -> GameState:
	var copy := GameState.new()
	copy.level_id = level_id
	copy.board_rows = board_rows
	copy.board_cols = board_cols
	copy.passenger_queue = passenger_queue.duplicate()
	copy.vehicles = {}
	for vehicle_id: String in vehicles.keys():
		copy.vehicles[vehicle_id] = vehicles[vehicle_id].duplicate_state()
	copy.waiting_slots = []
	for slot: WaitingSlotState in waiting_slots:
		copy.waiting_slots.append(slot.duplicate_state())
	copy.status = status
	copy.moves = moves
	return copy

func get_front_passenger_color() -> String:
	if passenger_queue.is_empty():
		return ""
	return passenger_queue[0]

func get_first_empty_slot() -> WaitingSlotState:
	for slot: WaitingSlotState in waiting_slots:
		if slot.is_empty():
			return slot
	return null

func are_all_slots_full() -> bool:
	return get_first_empty_slot() == null
