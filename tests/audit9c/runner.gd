extends SceneTree

# Etapa 9C - ferramenta de auditoria/QA. So LE o LevelGenerator/GameEngine
# reais (nenhuma regra alterada); nao faz parte do jogo em runtime.

const PRODUCTIVE_WINDOW := 60

func _init() -> void:
	var args := _parse_args()
	var mode: String = args.get("mode", "sample")
	var runs: int = int(args.get("runs", "150"))
	var out: String = args.get("out", "res://tests/audit9c/out.json")
	if mode == "level":
		var level_number: int = int(args.get("level", "948"))
		var result := _measure_level(level_number, runs)
		_write(out, result)
	else:
		var levels_str: String = args.get("levels", "6,10,20,50,100,250,500,948")
		var results := []
		for part in levels_str.split(","):
			var level_number := int(part.strip_edges())
			results.append(_measure_level(level_number, runs))
		_write(out, results)
	quit()

func _write(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("WROTE ", path)

func _parse_args() -> Dictionary:
	var result := {}
	for arg: String in OS.get_cmdline_user_args():
		var a := arg
		while a.begins_with("-"):
			a = a.substr(1)
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			result[parts[0]] = parts[1]
		else:
			result[a] = true
	return result

# ---------------------------------------------------------------------------
# Metricas de veiculos livres (Etapa 9C, item 2 e item 10)
# ---------------------------------------------------------------------------

func _free_vehicle_ids(state: GameState) -> Array:
	# "quantos veiculos ainda no board podem legalmente sair agora" -- so a
	# capacidade FISICA de sair (can_vehicle_exit), independente de vaga.
	var ids := []
	for vid: String in state.vehicles.keys():
		var v: VehicleState = state.vehicles[vid]
		if v.status == VehicleState.ON_BOARD and GameEngine.can_vehicle_exit(state, vid)["can_exit"]:
			ids.append(vid)
	ids.sort()
	return ids

func _productive_free_vehicle_ids(state: GameState, free_ids: Array, window: int) -> Array:
	var relevant_colors := {}
	var upto: int = mini(window, state.passenger_queue.size())
	for i in range(upto):
		relevant_colors[state.passenger_queue[i]] = true
	var productive := []
	for vid: String in free_ids:
		var v: VehicleState = state.vehicles[vid]
		if relevant_colors.has(v.color_id):
			productive.append(vid)
	return productive

# Caminha a ordem direta de partida (a mesma que _validate_solvable usa como
# prova de solvabilidade) e registra as metricas de liberdade a cada passo.
# Barato: e o mesmo numero de chamadas que a validacao ja faz.
func _canonical_trace(level: LevelDefinition) -> Dictionary:
	var state: GameState = GameEngine.create_state(level)
	var free_counts := []
	var productive_counts := []
	var won := true
	for vehicle: VehicleDefinition in level.vehicles:
		var free_ids := _free_vehicle_ids(state)
		var productive_ids := _productive_free_vehicle_ids(state, free_ids, PRODUCTIVE_WINDOW)
		free_counts.append(free_ids.size())
		productive_counts.append(productive_ids.size())
		var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, vehicle.id)
		var events: Array = result["events"]
		for item: Variant in events:
			var event: GameEvent = item as GameEvent
			if event != null and (event.type == "VehicleBlocked" or event.type == "NoWaitingSlotAvailable"):
				won = false
		state = result["state"]
	won = won and state.status == GameState.WON
	return {
		"won": won,
		"free_counts": free_counts,
		"productive_counts": productive_counts,
		"initial_free": free_counts[0] if not free_counts.is_empty() else 0,
		"initial_productive": productive_counts[0] if not productive_counts.is_empty() else 0,
		"avg_free": _avg(free_counts),
		"peak_free": _max_of(free_counts),
		"min_free": _min_of(free_counts),
		"avg_productive": _avg(productive_counts),
	}

func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0
	for x in arr:
		s += int(x)
	return float(s) / arr.size()

func _max_of(arr: Array) -> int:
	var m := 0
	for x in arr:
		m = maxi(m, int(x))
	return m

func _min_of(arr: Array) -> int:
	if arr.is_empty():
		return 0
	var m: int = int(arr[0])
	for x in arr:
		m = mini(m, int(x))
	return m

# ---------------------------------------------------------------------------
# Overlap / sanidade fisica (item 20)
# ---------------------------------------------------------------------------

func _check_overlap_and_bounds(level: LevelDefinition) -> Dictionary:
	var occupied := {}
	var overlaps := []
	var out_of_bounds := []
	for v: VehicleDefinition in level.vehicles:
		for row_offset in range(v.footprint_rows):
			for col_offset in range(v.footprint_cols):
				var cell := Vector2i(v.col + col_offset, v.row + row_offset)
				if cell.x < 0 or cell.x >= level.board_cols or cell.y < 0 or cell.y >= level.board_rows:
					out_of_bounds.append(v.id)
				if occupied.has(cell):
					overlaps.append([occupied[cell], v.id])
				occupied[cell] = v.id
	return {"overlaps": overlaps, "out_of_bounds": out_of_bounds}

# ---------------------------------------------------------------------------
# Simulacoes estocasticas (reaproveitado da Etapa 9B)
# ---------------------------------------------------------------------------

func _movable_candidates(state: GameState) -> Array:
	var candidates := []
	if state.are_all_slots_full():
		return candidates
	for vid: String in state.vehicles.keys():
		var v: VehicleState = state.vehicles[vid]
		if v.status == VehicleState.ON_BOARD:
			var res: Dictionary = GameEngine.can_vehicle_exit(state, vid)
			if res["can_exit"]:
				candidates.append(vid)
	candidates.sort()
	return candidates

func _mixed_choice(matching: Array, candidates: Array, rng: RandomNumberGenerator, p_useful: float) -> String:
	if rng.randf() < p_useful and not matching.is_empty():
		return matching[rng.randi_range(0, matching.size() - 1)]
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _simulate(level: LevelDefinition, strategy: String, rng: RandomNumberGenerator) -> bool:
	var state: GameState = GameEngine.create_state(level)
	while state.status == GameState.PLAYING:
		var candidates := _movable_candidates(state)
		if candidates.is_empty():
			break
		var front := state.get_front_passenger_color()
		var matching := []
		for vid: String in candidates:
			if state.vehicles[vid].color_id == front:
				matching.append(vid)
		var chosen: String
		match strategy:
			"mix80":
				chosen = _mixed_choice(matching, candidates, rng, 0.8)
			"mix70":
				chosen = _mixed_choice(matching, candidates, rng, 0.7)
			"random":
				chosen = candidates[rng.randi_range(0, candidates.size() - 1)]
			_:
				chosen = candidates[rng.randi_range(0, candidates.size() - 1)]
		var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, chosen)
		state = result["state"]
	return state.status == GameState.WON

func _win_rate(level: LevelDefinition, strategy: String, runs: int, seed_key: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + "_" + strategy)
	var wins := 0
	for i in range(runs):
		if _simulate(level, strategy, rng):
			wins += 1
	return float(wins) / runs

# ---------------------------------------------------------------------------
# Medicao completa de uma fase
# ---------------------------------------------------------------------------

func _longest_run(queue: Array) -> int:
	if queue.is_empty():
		return 0
	var best := 1
	var cur := 1
	for i in range(1, queue.size()):
		if queue[i] == queue[i - 1]:
			cur += 1
			best = maxi(best, cur)
		else:
			cur = 1
	return best

func _measure_level(level_number: int, runs: int) -> Dictionary:
	var level: LevelDefinition = LevelGenerator.generate(level_number)
	var trace := _canonical_trace(level)
	var overlap := _check_overlap_and_bounds(level)
	var mix80 := _win_rate(level, "mix80", runs, str(level_number))
	var mix70 := _win_rate(level, "mix70", runs, str(level_number))
	var rnd := _win_rate(level, "random", runs, str(level_number))
	return {
		"level_number": level_number,
		"n_vehicles": level.vehicles.size(),
		"board_rows": level.board_rows,
		"board_cols": level.board_cols,
		"total_passengers": level.passengers.size(),
		"longest_color_run": _longest_run(level.passengers),
		"solvable": trace["won"],
		"initial_free": trace["initial_free"],
		"avg_free": trace["avg_free"],
		"peak_free": trace["peak_free"],
		"min_free": trace["min_free"],
		"initial_productive": trace["initial_productive"],
		"avg_productive": trace["avg_productive"],
		"free_counts": trace["free_counts"],
		"overlaps": overlap["overlaps"],
		"out_of_bounds": overlap["out_of_bounds"],
		"win_rate_80_20": mix80,
		"win_rate_70_30": mix70,
		"win_rate_random": rnd,
	}
