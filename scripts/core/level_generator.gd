class_name LevelGenerator
extends RefCounted

# Gerador procedural de fases, usado quando o pacote de fases prontas (JSON em
# res://levels) se esgota. Garante SEMPRE uma fase jogavel (nunca trava) por
# construcao: os veiculos sao posicionados em ordem REVERSA de partida, e cada
# veiculo, ao ser colocado, exige que seu proprio caminho ate a borda do
# tabuleiro esteja livre de tudo que ja foi posicionado antes dele (ou seja,
# dos veiculos que partem DEPOIS dele, na ordem direta). Isso garante
# matematicamente que, seguindo a ordem direta de partida (a mesma ordem usada
# para montar a fila de passageiros), cada veiculo encontra seu caminho livre
# quando chega sua vez: os unicos veiculos ainda no tabuleiro naquele momento
# sao justamente os que partem depois dele.
#
# A fila de passageiros e construida de forma canonica: exatamente `capacity`
# copias da cor de cada veiculo, na mesma ordem direta de partida. Isso garante
# uma solucao trivial sempre valida (mandar os veiculos nessa ordem), mas a
# dificuldade real do quebra-cabeca vem do tabuleiro: veiculos posicionados
# depois (que partem antes) podem ficar bem no caminho de saida de veiculos
# posicionados antes (que partem depois), criando cadeias de bloqueio que o
# jogador precisa descobrir jogando - sem nunca tornar a fase impossivel.
#
# Antes de aceitar uma fase gerada, `_validate_solvable` reproduz a solucao
# canonica inteira atraves do GameEngine de verdade (nao e so teoria: e testado
# fase por fase) e so aceita se ela realmente vencer sem nenhum bloqueio.

const COLORS: Array[String] = ["red", "blue", "green", "yellow", "purple", "pink", "orange"]
const DIRECTIONS: Array[String] = ["up", "down", "left", "right"]
const MAX_PLACEMENT_ATTEMPTS_PER_VEHICLE := 60
const MAX_LEVEL_ATTEMPTS := 25

static func generate(level_number: int, rng_seed: int = -1) -> LevelDefinition:
	var rng := RandomNumberGenerator.new()
	# Seed deterministica por numero de fase: a mesma fase "6" gera sempre o
	# mesmo layout, entao salvar/retomar o progresso funciona normalmente mesmo
	# sem um arquivo JSON por tras dela.
	rng.seed = level_number if rng_seed < 0 else rng_seed

	for _attempt: int in range(MAX_LEVEL_ATTEMPTS):
		var candidate: LevelDefinition = _try_generate(level_number, rng, 0)
		if candidate != null and _validate_solvable(candidate):
			return candidate

	# Rede de seguranca: tabuleiros muito apertados podem falhar a colocacao
	# aleatoria repetidas vezes. Tentamos de novo com folga extra de tabuleiro.
	for _attempt: int in range(MAX_LEVEL_ATTEMPTS):
		var relaxed: LevelDefinition = _try_generate(level_number, rng, 2)
		if relaxed != null and _validate_solvable(relaxed):
			return relaxed

	# Isso nao deve acontecer na pratica, mas garante que o jogo nunca fique
	# sem uma proxima fase valida.
	return _minimal_safe_level(level_number)

static func difficulty_params(level_number: int) -> Dictionary:
	var n: int = maxi(level_number, 1)
	var vehicle_count: int = clampi(7 + int((n - 6) / 2.4), 6, 18)
	var board_rows: int = clampi(9 + int((n - 6) / 6.0), 8, 12)
	var board_cols: int = clampi(8 + int((n - 6) / 8.0), 7, 10)
	var waiting_slots: int = 4
	var van_chance: float = 0.0
	if n >= 8:
		van_chance = clampf(float(n - 8) * 0.06, 0.0, 0.45)
	var bus_chance: float = 0.0
	if n >= 14:
		bus_chance = clampf(float(n - 14) * 0.05, 0.0, 0.30)
	return {
		"vehicle_count": vehicle_count,
		"board_rows": board_rows,
		"board_cols": board_cols,
		"waiting_slots": waiting_slots,
		"van_chance": van_chance,
		"bus_chance": bus_chance,
	}

static func _try_generate(level_number: int, rng: RandomNumberGenerator, board_padding: int) -> LevelDefinition:
	var params: Dictionary = difficulty_params(level_number)
	var vehicle_count: int = params["vehicle_count"]
	var board_rows: int = params["board_rows"] + board_padding
	var board_cols: int = params["board_cols"] + board_padding
	var waiting_slots: int = params["waiting_slots"]
	var van_chance: float = params["van_chance"]
	var bus_chance: float = params["bus_chance"]

	# Em fases densas ha mais veiculos do que cores. Em vez de limitar o
	# tabuleiro a 7 veiculos, repetimos uma paleta embaralhada. Isso deixa a
	# tela cheia como a referencia sem criar cores novas ou quebrar a regra.
	var colors: Array[String] = _shuffled(COLORS, rng)

	var specs: Array[Dictionary] = []
	for index: int in range(vehicle_count):
		var color_id: String = colors[index % colors.size()]
		var type_id: String = "small_car"
		var capacity: int = VehicleCapacityTable.default_for(type_id)
		var length: int = 2
		var roll: float = rng.randf()
		if roll < bus_chance:
			type_id = "bus"
			capacity = VehicleCapacityTable.default_for(type_id)
			length = 3
		elif roll < bus_chance + van_chance:
			type_id = "medium_car"
			capacity = VehicleCapacityTable.default_for(type_id)
			length = 3
		var direction: String = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
		specs.append({
			"id": "%s_%d" % [color_id, index],
			"color": color_id,
			"type_id": type_id,
			"capacity": capacity,
			"length": length,
			"exit_direction": direction,
		})

	var occupied: Dictionary = {}
	var placements: Dictionary = {}
	for reverse_index: int in range(specs.size() - 1, -1, -1):
		var spec: Dictionary = specs[reverse_index]
		var placement: Dictionary = _place_vehicle(occupied, board_rows, board_cols, spec, rng)
		if placement.is_empty():
			return null
		placements[spec["id"]] = placement

	var vehicles: Array[VehicleDefinition] = []
	var passengers: Array[String] = []
	for spec: Dictionary in specs:
		var placement: Dictionary = placements[spec["id"]]
		vehicles.append(VehicleDefinition.new(
			spec["id"],
			spec["type_id"],
			spec["color"],
			spec["capacity"],
			placement["row"],
			placement["col"],
			placement["orientation"],
			spec["exit_direction"],
			placement["footprint_rows"],
			placement["footprint_cols"]
		))
		for _seat: int in range(int(spec["capacity"])):
			passengers.append(spec["color"])

	return LevelDefinition.new(level_number, waiting_slots, board_rows, board_cols, passengers, vehicles)

static func _place_vehicle(occupied: Dictionary, board_rows: int, board_cols: int, spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var orientation: String = "horizontal" if spec["exit_direction"] in ["left", "right"] else "vertical"
	var length: int = spec["length"]
	var footprint_rows: int = 1 if orientation == "horizontal" else length
	var footprint_cols: int = length if orientation == "horizontal" else 1

	if orientation == "horizontal" and board_cols < length:
		return {}
	if orientation == "vertical" and board_rows < length:
		return {}

	var attempts := 0
	while attempts < MAX_PLACEMENT_ATTEMPTS_PER_VEHICLE:
		attempts += 1
		var row: int
		var col: int
		if orientation == "horizontal":
			row = rng.randi_range(0, board_rows - 1)
			col = rng.randi_range(0, board_cols - length)
		else:
			col = rng.randi_range(0, board_cols - 1)
			row = rng.randi_range(0, board_rows - length)

		var cells: Array[Vector2i] = []
		for offset: int in range(length):
			if orientation == "horizontal":
				cells.append(Vector2i(col + offset, row))
			else:
				cells.append(Vector2i(col, row + offset))

		var cells_free := true
		for cell: Vector2i in cells:
			if occupied.has(cell):
				cells_free = false
				break
		if not cells_free:
			continue

		var path: Array[Vector2i] = _exit_path_cells(cells, spec["exit_direction"], board_rows, board_cols)
		var path_clear := true
		for cell: Vector2i in path:
			if occupied.has(cell):
				path_clear = false
				break
		if not path_clear:
			continue

		for cell: Vector2i in cells:
			occupied[cell] = true
		return {
			"row": row,
			"col": col,
			"orientation": orientation,
			"footprint_rows": footprint_rows,
			"footprint_cols": footprint_cols,
		}

	return {}

static func _exit_path_cells(cells: Array[Vector2i], direction: String, board_rows: int, board_cols: int) -> Array[Vector2i]:
	var min_x: int = cells[0].x
	var max_x: int = cells[0].x
	var min_y: int = cells[0].y
	var max_y: int = cells[0].y
	for cell: Vector2i in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)

	var path: Array[Vector2i] = []
	match direction:
		"up":
			for y: int in range(min_y - 1, -1, -1):
				for x: int in range(min_x, max_x + 1):
					path.append(Vector2i(x, y))
		"down":
			for y: int in range(max_y + 1, board_rows):
				for x: int in range(min_x, max_x + 1):
					path.append(Vector2i(x, y))
		"left":
			for x: int in range(min_x - 1, -1, -1):
				for y: int in range(min_y, max_y + 1):
					path.append(Vector2i(x, y))
		"right":
			for x: int in range(max_x + 1, board_cols):
				for y: int in range(min_y, max_y + 1):
					path.append(Vector2i(x, y))
	return path

static func _shuffled(source: Array[String], rng: RandomNumberGenerator) -> Array[String]:
	var result: Array[String] = source.duplicate()
	for i: int in range(result.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: String = result[i]
		result[i] = result[j]
		result[j] = temp
	return result

# Reproduz a solucao canonica (enviar os veiculos na mesma ordem usada para
# montar a fila) atraves do GameEngine de verdade. So aceitamos a fase gerada
# se essa solucao vencer sem nenhum VehicleBlocked/NoWaitingSlotAvailable.
static func _validate_solvable(level: LevelDefinition) -> bool:
	var state: GameState = GameEngine.create_state(level)
	for vehicle: VehicleDefinition in level.vehicles:
		var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, vehicle.id)
		var events: Array = result["events"]
		for item: Variant in events:
			var event: GameEvent = item as GameEvent
			if event != null and (event.type == "VehicleBlocked" or event.type == "NoWaitingSlotAvailable"):
				return false
		state = result["state"]
	return state.status == GameState.WON

static func _minimal_safe_level(level_number: int) -> LevelDefinition:
	return LevelDefinition.new(
		level_number,
		3,
		6,
		6,
		["red", "red", "blue", "blue"],
		[
			VehicleDefinition.new("red_0", "car", "red", 2, 2, 2, "horizontal", "left"),
			VehicleDefinition.new("blue_0", "car", "blue", 2, 3, 2, "horizontal", "right"),
		]
	)
