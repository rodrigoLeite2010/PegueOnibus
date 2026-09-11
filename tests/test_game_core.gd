extends SceneTree

func _init() -> void:
	_test_create_state_from_level()
	_test_boarding_preserves_reappearing_color()
	_test_no_slot_available()
	_test_vehicle_cells_use_footprint()
	_test_exit_up_blocked_and_clear()
	_test_exit_down_blocked()
	_test_exit_left_blocked()
	_test_exit_right_blocked()
	_test_full_slots_without_front_color_is_game_over()
	print("Etapa 1 e 2 core tests passed.")
	quit()

func _make_level() -> LevelDefinition:
	return LevelDefinition.new(
		1,
		2,
		9,
		7,
		["red", "red", "blue", "blue", "red", "red"],
		[
			VehicleDefinition.new("red_van", "van", "red", 4, 4, 0, "vertical", "up"),
			VehicleDefinition.new("blue_car", "car", "blue", 2, 4, 2, "vertical", "up"),
		]
	)

func _test_create_state_from_level() -> void:
	var state: GameState = GameEngine.create_state(_make_level())
	assert(state.level_id == 1)
	assert(state.passenger_queue.size() == 6)
	assert(state.waiting_slots.size() == 2)
	assert(state.vehicles.has("red_van"))
	assert(state.status == GameState.PLAYING)

func _test_boarding_preserves_reappearing_color() -> void:
	var state: GameState = GameEngine.create_state(_make_level())
	var first_result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, "red_van")
	state = first_result["state"]
	assert(state.vehicles["red_van"].occupied_seats == 2)
	assert(state.vehicles["red_van"].status == VehicleState.WAITING)
	assert(state.waiting_slots[0].vehicle_id == "red_van")

	var second_result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, "blue_car")
	state = second_result["state"]
	assert(state.vehicles["blue_car"].status == VehicleState.COMPLETE)
	assert(state.vehicles["red_van"].status == VehicleState.COMPLETE)
	assert(state.passenger_queue.is_empty())
	assert(state.status == GameState.WON)

func _test_no_slot_available() -> void:
	var level := LevelDefinition.new(
		2,
		1,
		9,
		7,
		["red", "red", "green", "green"],
		[
			VehicleDefinition.new("blue_car", "car", "blue", 2, 4, 0, "vertical", "up"),
			VehicleDefinition.new("green_car", "car", "green", 2, 4, 2, "vertical", "up"),
		]
	)
	var state: GameState = GameEngine.create_state(level)
	# Ocupa a unica vaga manualmente (sem passar pelo fluxo normal do motor):
	# com so 1 vaga, deixar o motor de fato estacionar o blue_car dispararia
	# a checagem de Game Over (nenhuma vaga livre + cor da frente nao
	# atendida) -- comportamento correto, ja coberto por
	# _test_full_slots_without_front_color_is_game_over. Aqui queremos isolar
	# so o evento "NoWaitingSlotAvailable" ao tentar mandar um segundo
	# veiculo com a unica vaga ja ocupada; nao assumimos que ele seja o unico
	# evento, porque o motor pode (corretamente) tambem concluir Game Over
	# na mesma tentativa.
	state.waiting_slots[0].vehicle_id = "blue_car"
	state.vehicles["blue_car"].status = VehicleState.WAITING
	var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, "green_car")
	var events: Array = result["events"]
	var result_state: GameState = result["state"]
	var has_no_slot_event := false
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == "NoWaitingSlotAvailable":
			has_no_slot_event = true
	assert(has_no_slot_event)
	assert(result_state.moves == 0)

func _test_vehicle_cells_use_footprint() -> void:
	var level := LevelDefinition.new(
		3,
		1,
		5,
		5,
		["red"],
		[VehicleDefinition.new("bus", "bus", "red", 8, 1, 2, "horizontal", "right")]
	)
	var state: GameState = GameEngine.create_state(level)
	var cells: Array[Vector2i] = GameEngine.get_vehicle_cells(state.vehicles["bus"])
	assert(cells.has(Vector2i(2, 1)))
	assert(cells.has(Vector2i(3, 1)))
	assert(cells.has(Vector2i(4, 1)))
	assert(cells.size() == 3)

func _test_exit_up_blocked_and_clear() -> void:
	var level := LevelDefinition.new(
		4,
		2,
		6,
		6,
		["red", "red"],
		[
			VehicleDefinition.new("target", "car", "red", 2, 3, 2, "vertical", "up"),
			VehicleDefinition.new("blocker", "car", "blue", 2, 1, 2, "horizontal", "left"),
		]
	)
	var state: GameState = GameEngine.create_state(level)
	var blocked: Dictionary = GameEngine.can_vehicle_exit(state, "target")
	assert(blocked["can_exit"] == false)
	assert(blocked["blockers"].has("blocker"))
	state.vehicles["blocker"].status = VehicleState.WAITING
	var clear: Dictionary = GameEngine.can_vehicle_exit(state, "target")
	assert(clear["can_exit"] == true)

func _test_exit_down_blocked() -> void:
	var level := LevelDefinition.new(
		5,
		2,
		6,
		6,
		["red"],
		[
			VehicleDefinition.new("target", "car", "red", 2, 1, 2, "vertical", "down"),
			VehicleDefinition.new("blocker", "car", "blue", 2, 4, 2, "horizontal", "left"),
		]
	)
	var state: GameState = GameEngine.create_state(level)
	var result: Dictionary = GameEngine.can_vehicle_exit(state, "target")
	assert(result["can_exit"] == false)
	assert(result["blockers"].has("blocker"))

func _test_exit_left_blocked() -> void:
	var level := LevelDefinition.new(
		6,
		2,
		6,
		6,
		["red"],
		[
			VehicleDefinition.new("target", "car", "red", 2, 2, 3, "horizontal", "left"),
			VehicleDefinition.new("blocker", "car", "blue", 2, 2, 1, "vertical", "up"),
		]
	)
	var state: GameState = GameEngine.create_state(level)
	var result: Dictionary = GameEngine.can_vehicle_exit(state, "target")
	assert(result["can_exit"] == false)
	assert(result["blockers"].has("blocker"))

func _test_exit_right_blocked() -> void:
	var level := LevelDefinition.new(
		7,
		2,
		6,
		6,
		["red"],
		[
			VehicleDefinition.new("target", "car", "red", 2, 2, 1, "horizontal", "right"),
			VehicleDefinition.new("blocker", "car", "blue", 2, 2, 4, "vertical", "up"),
		]
	)
	var state: GameState = GameEngine.create_state(level)
	var result: Dictionary = GameEngine.can_vehicle_exit(state, "target")
	assert(result["can_exit"] == false)
	assert(result["blockers"].has("blocker"))

# Regressao: slots cheios + cor da frente ausente na espera deve encerrar a fase.
# Um carro livre no tabuleiro nao resolve, pois nao existe slot para recebe-lo.
func _test_full_slots_without_front_color_is_game_over() -> void:
	var level := LevelDefinition.new(
		8,
		1,
		6,
		6,
		["red", "red", "blue", "blue"],
		[
			VehicleDefinition.new("green_car", "car", "green", 2, 0, 0, "horizontal", "left"),
			VehicleDefinition.new("red_car", "car", "red", 2, 4, 3, "horizontal", "right"),
		]
	)
	var state := GameEngine.create_state(level)
	var first := GameEngine.try_send_vehicle_to_waiting_slot(state, "green_car")
	var next_state: GameState = first["state"]
	assert(next_state.status == GameState.LOST)
