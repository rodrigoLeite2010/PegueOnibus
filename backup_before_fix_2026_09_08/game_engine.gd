class_name GameEngine
extends RefCounted

static func create_state(level: LevelDefinition) -> GameState:
	return GameState.new(level)

static func try_send_vehicle_to_waiting_slot(state: GameState, vehicle_id: String) -> Dictionary:
	var next_state := state.duplicate_state()
	var events: Array[GameEvent] = []
	if next_state.status != GameState.PLAYING:
		return {"state": next_state, "events": events}
	if not next_state.vehicles.has(vehicle_id):
		events.append(GameEvent.new("InvalidVehicle", {"vehicle_id": vehicle_id}))
		return {"state": next_state, "events": events}

	var vehicle: VehicleState = next_state.vehicles[vehicle_id]
	if vehicle.status != VehicleState.ON_BOARD:
		events.append(GameEvent.new("VehicleUnavailable", {"vehicle_id": vehicle_id}))
		return {"state": next_state, "events": events}

	var exit_result: Dictionary = can_vehicle_exit(next_state, vehicle_id)
	if not exit_result["can_exit"]:
		events.append(GameEvent.new("VehicleBlocked", {
			"vehicle_id": vehicle_id,
			"blockers": exit_result["blockers"],
			"path": exit_result["path"]
		}))
		return {"state": next_state, "events": events}

	var slot := next_state.get_first_empty_slot()
	if slot == null:
		events.append(GameEvent.new("NoWaitingSlotAvailable", {"vehicle_id": vehicle_id}))
		update_terminal_status(next_state, events)
		return {"state": next_state, "events": events}

	vehicle.status = VehicleState.WAITING
	slot.vehicle_id = vehicle.id
	next_state.moves += 1
	events.append(GameEvent.new("VehicleExited", {"vehicle_id": vehicle.id, "exit_direction": vehicle.exit_direction}))
	events.append(GameEvent.new("VehicleParked", {"vehicle_id": vehicle.id, "slot_index": slot.index}))
	process_pending_boarding(next_state, events)
	update_terminal_status(next_state, events)
	return {"state": next_state, "events": events}

static func can_vehicle_exit(state: GameState, vehicle_id: String) -> Dictionary:
	if not state.vehicles.has(vehicle_id):
		return {"can_exit": false, "blockers": [], "path": []}
	var vehicle: VehicleState = state.vehicles[vehicle_id]
	if vehicle.status != VehicleState.ON_BOARD:
		return {"can_exit": false, "blockers": [], "path": []}

	var path: Array[Vector2i] = get_exit_path_cells(state, vehicle)
	var blockers: Array[String] = []
	for path_cell: Vector2i in path:
		var blocker_id: String = get_vehicle_at_cell(state, path_cell, vehicle.id)
		if blocker_id != "" and not blockers.has(blocker_id):
			blockers.append(blocker_id)
	return {"can_exit": blockers.is_empty(), "blockers": blockers, "path": path}

static func get_vehicle_cells(vehicle: VehicleState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row_offset: int in range(vehicle.footprint_rows):
		for col_offset: int in range(vehicle.footprint_cols):
			cells.append(Vector2i(vehicle.col + col_offset, vehicle.row + row_offset))
	return cells

static func get_exit_path_cells(state: GameState, vehicle: VehicleState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = get_vehicle_cells(vehicle)
	var path: Array[Vector2i] = []
	var min_x: int = cells[0].x
	var max_x: int = cells[0].x
	var min_y: int = cells[0].y
	var max_y: int = cells[0].y
	for cell: Vector2i in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)

	match vehicle.exit_direction:
		"up":
			for y: int in range(min_y - 1, -1, -1):
				for x: int in range(min_x, max_x + 1):
					path.append(Vector2i(x, y))
		"down":
			for y: int in range(max_y + 1, state.board_rows):
				for x: int in range(min_x, max_x + 1):
					path.append(Vector2i(x, y))
		"left":
			for x: int in range(min_x - 1, -1, -1):
				for y: int in range(min_y, max_y + 1):
					path.append(Vector2i(x, y))
		"right":
			for x: int in range(max_x + 1, state.board_cols):
				for y: int in range(min_y, max_y + 1):
					path.append(Vector2i(x, y))
	return path

static func get_vehicle_at_cell(state: GameState, cell: Vector2i, ignored_vehicle_id: String = "") -> String:
	for vehicle_id: String in state.vehicles.keys():
		if vehicle_id == ignored_vehicle_id:
			continue
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		if get_vehicle_cells(vehicle).has(cell):
			return vehicle_id
	return ""

static func process_pending_boarding(state: GameState, events: Array[GameEvent]) -> void:
	var changed := true
	while changed:
		changed = false
		var front_color := state.get_front_passenger_color()
		if front_color == "":
			return

		for slot: WaitingSlotState in state.waiting_slots:
			if slot.is_empty():
				continue
			var vehicle: VehicleState = state.vehicles[slot.vehicle_id]
			if vehicle.color_id != front_color:
				continue

			while not state.passenger_queue.is_empty() and state.passenger_queue[0] == vehicle.color_id and vehicle.occupied_seats < vehicle.capacity:
				state.passenger_queue.remove_at(0)
				vehicle.occupied_seats += 1
				changed = true
				events.append(GameEvent.new("PassengerBoarded", {
					"vehicle_id": vehicle.id,
					"color_id": vehicle.color_id,
					"occupied_seats": vehicle.occupied_seats,
					"capacity": vehicle.capacity,
				}))

			if vehicle.occupied_seats >= vehicle.capacity:
				vehicle.status = VehicleState.COMPLETE
				slot.vehicle_id = ""
				changed = true
				events.append(GameEvent.new("SlotFreed", {"vehicle_id": vehicle.id, "slot_index": slot.index}))
			break

static func update_terminal_status(state: GameState, events: Array[GameEvent]) -> void:
	process_pending_boarding(state, events)
	if state.passenger_queue.is_empty():
		state.status = GameState.WON
		events.append(GameEvent.new("Win"))
		return
	if not state.are_all_slots_full():
		return
	if has_waiting_vehicle_for_front_color(state):
		return
	if has_any_valid_board_move(state):
		return
	state.status = GameState.LOST
	events.append(GameEvent.new("GameOver"))

static func has_waiting_vehicle_for_front_color(state: GameState) -> bool:
	var front_color := state.get_front_passenger_color()
	if front_color == "":
		return true
	for slot: WaitingSlotState in state.waiting_slots:
		if slot.is_empty():
			continue
		var vehicle: VehicleState = state.vehicles[slot.vehicle_id]
		if vehicle.color_id == front_color:
			return true
	return false

static func has_any_valid_board_move(state: GameState) -> bool:
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status == VehicleState.ON_BOARD and can_vehicle_exit(state, vehicle_id)["can_exit"]:
			return true
	return false
