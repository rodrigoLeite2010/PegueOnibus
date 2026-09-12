class_name GameController
extends Node3D

const CELL_SIZE := 1.0
const LEVEL_DIR := "res://levels"
const LEVEL_PATTERN := "level_%03d.json"
const HINT_COST := 15

# --- Enquadramento da camera ---
# A HUD (CanvasLayer, 2D) fica sempre por cima da cena 3D, ocupando uma faixa
# fixa de tela (em pixels, no espaco de design 720x1280 do projeto) tanto no
# topo (TopPanel + QueuePanel) quanto embaixo (BottomPanel). O enquadramento da
# camera 3D precisa deixar o tabuleiro inteiro fora dessas faixas; antes disso
# nao acontecia (a camera usava um deslocamento fixo, calibrado so pra um
# tamanho de tabuleiro, e ignorava a atenuacao trigonometrica causada pela
# inclinacao da camera), o que deixava veiculos proximos da borda norte do
# tabuleiro escondidos atras da HUD em fases com outra proporcao de linhas.
const CAMERA_PITCH_DEGREES := -63.0
const CAMERA_HEIGHT := 14.5
const BOARD_EDGE_MARGIN := 0.85
# Profundidade real ocupada pela area de embarque (plataforma, pista, letreiros
# e o ponto onde os passageiros nascem -- ver BoardingAreaController.setup()) ANTES da
# linha 0 do tabuleiro. Precisa entrar na conta do enquadramento da camera
# como a propria area do tabuleiro; tratar como se fosse so a folga generica
# de borda (BOARD_EDGE_MARGIN) escondia parte da area de embarque atras da
# faixa de HUD de cima -- exatamente o bug relatado ("carro sumindo atras do
# topo"). O maior letreiro ("PASSAGEIROS") fica em z=-1.62; 1.85 da folga.
const BOARDING_AREA_DEPTH := 3.05
const HUD_TOP_UNSAFE_FRACTION := 118.0 / 1280.0
const HUD_BOTTOM_UNSAFE_FRACTION := 160.0 / 1280.0
# Colchao extra (fracao de tela) alem da borda exata da HUD, pra nunca deixar
# a area de embarque ou a ultima linha do tabuleiro coladas exatamente na
# borda (o que arrisca cortar 1-2px dependendo do arredondamento).
const CAMERA_FRAME_SAFETY_FRACTION := 0.02

# --- ETAPA 8: perfil de apresentacao (presentation_profile) ---
# Substitui as comparacoes espalhadas "state.level_id == 950" por uma unica
# fonte: is_polished, derivado de presentation_profile, calculado UMA vez por
# fase carregada (ver _load_level_number -> _resolve_presentation_profile()).
# POLISHED_LEVEL_IDS e a UNICA lista que decide quais fases usam a
# apresentacao polida -- hoje: a PolishTest (950, sempre, usada como teste de
# stress) e as 3 fases reais piloto desta etapa (1, 2, 3). Todas as demais
# fases continuam CLASSIC, sem nenhuma mudanca de comportamento/aparencia.
# IMPORTANTE (ticket Etapa 8, secao 4): isto migra so APRESENTACAO (camera,
# docks, fila 3D, efeitos, HUD) -- NUNCA conteudo (veiculos, capacidades,
# vagas, dificuldade, board ou regras), que continuam vindo do proprio
# level_XXX.json de cada fase, sem nenhuma alteracao aqui.
enum PresentationProfile { CLASSIC, POLISHED }
const POLISH_TEST_LEVEL_ID := 950
const POLISHED_LEVEL_IDS: Array[int] = [1, 2, 3, POLISH_TEST_LEVEL_ID]
# ETAPA 2B: pitch ainda mais raso (-50 -> -44, dentro da faixa -42..-46
# pedida) para mostrar claramente a lateral dos veiculos, especialmente dos
# onibus -- o feedback da Etapa 2 foi "ainda parece muito de cima".
const POLISH_CAMERA_PITCH_DEGREES := -44.0
const POLISH_CAMERA_HEIGHT := 12.5
# ETAPA 2B: a Etapa 2 encolhia o conteudo pra ~70% da faixa util, centralizado
# -- isso foi identificado como a causa direta da "faixa vazia enorme entre o
# HUD e os passageiros" reportada. Agora o PolishTest usa a MESMA regra 100%
# top-anchored das fases normais (ver _setup_camera: content_top_fraction ==
# top_fraction, content_bottom_fraction == bottom_fraction sempre), preservando
# so a diferenca de pitch/altura acima. As constantes ficam aqui (valor 1.0)
# apenas para nao remover o "gancho" caso um respiro futuro seja necessario.
const POLISH_BOARD_FILL_FRACTION := 1.0
const POLISH_WIDTH_FILL_FRACTION := 1.0

# Profundidade total (Z) reservada pela area de embarque da PolishTest, do
# limite Z=0 do tabuleiro ate a fileira MAIS de tras de passageiros possivel
# (pior caso: PassengerCrowdController.MAX_VISIBLE_QUEUE_DOLLS=40 bonecos,
# PassengerCrowdController.POLISH_CROWD_COLUMNS=8 ->
# ceil(40/8)=5 fileiras). Calculado, nao chutado, pra nunca mais deixar
# nenhuma fileira de passageiro cair por tras do proprio limite reservado
# (era exatamente o bug: a Etapa 2B usava a mesma BOARDING_AREA_DEPTH das
# fases normais, 3.05, mas com 40 bonecos as ultimas fileiras iam ate
# Z=-4.38 -- 1.33 alem do limite -- ou seja, apareciam ATRAS/dentro da faixa
# do HUD superior). So entra na formula da camera quando is_polished;
# BOARDING_AREA_DEPTH continua exatamente igual para toda fase normal.
const POLISH_BOARDING_AREA_DEPTH := 5.5

@onready var board: BoardController = $Board
@onready var environment: EnvironmentController = $GameEnvironment
@onready var vehicles_root: Node3D = $Vehicles
@onready var passengers_root: Node3D = $Passengers
@onready var vfx_root: Node3D = $VFX
@onready var boarding_area: BoardingAreaController = $BoardingArea
@onready var camera: Camera3D = $Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var hud: HUDController = $HUD

# ETAPA 7 (refatoracao segura): instanciado em _ready(), nunca editado na
# cena .tscn -- ver PolishEffectsController e _ready() abaixo. Reune os
# efeitos visuais puros que antes eram metodos privados deste script
# (particulas procedurais, popups, feedback de vaga liberada); o
# comportamento e byte-a-byte o mesmo, so mudou de arquivo.
var _polish_effects: PolishEffectsController

# ETAPA 8: unica fonte de verdade sobre a apresentacao da fase atual --
# recalculado a cada _load_level_number(), nunca inferido de state.level_id
# em nenhum outro lugar do arquivo.
var presentation_profile: PresentationProfile = PresentationProfile.CLASSIC
var is_polished: bool = false

# ETAPA 7 (refatoracao segura): instanciado em _ready(), nunca editado na
# cena .tscn -- ver PassengerCrowdController. setup() e chamado de novo a
# cada _load_level_number() (ao contrario de _polish_effects, que so muda de
# fase quando is_polished/board_cols mudam). Reune os bonecos 3D da fila
# de passageiros que antes eram metodos privados deste script; o
# comportamento e byte-a-byte o mesmo, so mudou de arquivo.
var _passenger_crowd: PassengerCrowdController

# ETAPA 6 (PolishTest, fase 950 exclusivamente): snapshot do Environment/luz
# ORIGINAIS (fases normais), tirado uma unica vez em _ready() antes de
# qualquer fase carregar. _apply_polish_environment()/
# _restore_default_environment() usam isso pra nunca deixar residuo da
# PolishTest vazar pra uma fase normal carregada depois, na mesma sessao.
var _default_environment: Environment
var _default_light_transform: Transform3D
var _default_light_energy: float = 1.0
var _default_light_shadow_blur: float = 0.0
var _default_light_color: Color = Color.WHITE

var state: GameState
var level: LevelDefinition
var vehicle_nodes: Dictionary = {}
# vehicle_id -> Marker3D da vaga de embarque onde ele estacionou (ver
# _process_vehicle_tap). Usado so pra atualizar o contador regressivo
# (Label3D "SlotLabel") em cima do proprio carro conforme os eventos de
# PassengerBoarded/SlotFreed sao reproduzidos -- nunca decide nada do jogo,
# so espelha o que ja aconteceu em GameEngine.
var _vehicle_slot_markers: Dictionary = {}
# is_animating reflete "ha PELO MENOS uma jogada em andamento agora" -- usado
# so por restart/dica/continuar, que continuam bloqueados enquanto qualquer
# veiculo estiver se movendo. Nao serializa mais toques: varios veiculos
# podem estar andando/estacionando/embarcando ao mesmo tempo (pedido
# explicito do usuario: "a ideia e ir outro concomitante"), entao o controle
# e um CONTADOR (_active_tap_count), nao um bool travado por uma unica
# corrotina -- ver _begin_tap_animation/_end_tap_animation.
var is_animating: bool = false
var _active_tap_count: int = 0
var current_level_number: int = 1
var available_levels: Array[int] = []
var _blocked_tap_count: int = 0
var last_stars_earned: int = -1
# ETAPA 4 (Polish Test, fase 950 exclusivamente): vehicle_id -> quantos
# embarques em cascata (_run_cascaded_boarding) ainda estao rodando para
# aquele veiculo. Um veiculo so pode sair (drive_away_from_pickup) quando
# este numero chegar a 0 -- ver _play_boarding_events_polished, item 16 do
# pedido. Nunca usado/consultado fora da fase 950.
var _pending_polish_boardings: Dictionary = {}
var _camera_base_size: float = 14.0
var _camera_base_position: Vector3 = Vector3.ZERO
var _camera_shake_tween: Tween
# ETAPA 5 (Polish Test, fase 950 exclusivamente): saldo de moedas LOCAL e
# temporario desta sessao de teste (+10 por veiculo completado, itens 8-9 do
# pedido) -- NUNCA passa por Wallet.add_coins nem e persistido; reseta a
# cada _load_level_number(). Existe so para o feedback visual "+10" e o
# contador separado no HUD (ver PolishEffectsController.coin_popup e
# HUDController.show_polish_test_coin_counter). Fora da fase 950 nunca e
# incrementado nem lido.
var _polish_local_coin_balance: int = 0
func _resolve_presentation_profile(level_id: int) -> PresentationProfile:
	return PresentationProfile.POLISHED if POLISHED_LEVEL_IDS.has(level_id) else PresentationProfile.CLASSIC

func _ready() -> void:
	hud.restart_requested.connect(restart_level)
	hud.continue_requested.connect(_on_continue_requested)
	hud.hint_requested.connect(_on_hint_requested)
	# ETAPA 7: ver comentario do var _polish_effects acima.
	_polish_effects = PolishEffectsController.new()
	add_child(_polish_effects)
	_polish_effects.setup(vfx_root, board)
	_passenger_crowd = PassengerCrowdController.new()
	add_child(_passenger_crowd)
	# ETAPA 6: guarda o visual ORIGINAL antes de qualquer fase carregar (ver
	# comentario dos vars _default_* acima).
	if world_environment != null and world_environment.environment != null:
		_default_environment = world_environment.environment
	if directional_light != null:
		_default_light_transform = directional_light.transform
		_default_light_energy = directional_light.light_energy
		_default_light_shadow_blur = directional_light.shadow_blur
		_default_light_color = directional_light.light_color

# Chamado pelo AppRouter logo depois de instanciar a cena do jogo (etapa 9:
# Home/Mapa decidem qual fase abrir, o jogo nao carrega mais sozinho no
# _ready). Mantem o antigo comportamento de _ready para quem chamar direto.
func start_level(level_number: int) -> void:
	available_levels = _discover_levels()
	current_level_number = level_number
	_load_level_number(current_level_number)

func restart_level() -> void:
	if is_animating:
		return
	_load_level_number(current_level_number)

# O botao do modal de vitoria agora volta pro Mapa de fases (decisao da
# etapa 9) em vez de carregar a proxima fase no lugar.
func _on_continue_requested() -> void:
	if is_animating:
		return
	AppRouter.go_map()

func _discover_levels() -> Array[int]:
	var result: Array[int] = []
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		return [1]
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("level_") and file_name.ends_with(".json"):
			var number_text: String = file_name.trim_prefix("level_").trim_suffix(".json")
			if number_text.is_valid_int():
				result.append(number_text.to_int())
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	if result.is_empty():
		result.append(1)
	return result

func _level_path(level_number: int) -> String:
	return "%s/%s" % [LEVEL_DIR, LEVEL_PATTERN % level_number]

func _load_level_number(level_number: int) -> void:
	_clear_all_visuals()
	_reset_scene_saturation()
	_blocked_tap_count = 0
	_active_tap_count = 0
	is_animating = false
	_vehicle_slot_markers.clear()
	last_stars_earned = -1
	# ETAPA 5: saldo de teste da PolishTest sempre comeca zerado numa fase
	# nova/reiniciada -- nunca herda nada do saldo real (Wallet) nem de uma
	# sessao anterior de teste.
	_polish_local_coin_balance = 0
	if available_levels.has(level_number):
		var path: String = _level_path(level_number)
		level = _load_level_from_json(path)
		if level == null:
			push_error("Nao foi possivel carregar %s. Usando fase de emergencia." % path)
			level = _fallback_level()
			current_level_number = level.id
	else:
		# Pacote de fases prontas esgotado: gera a proxima fase proceduralmente,
		# sempre jogavel (validada internamente) e um pouco mais dificil que a
		# anterior.
		level = LevelGenerator.generate(level_number)
	state = GameEngine.create_state(level)
	presentation_profile = _resolve_presentation_profile(state.level_id)
	is_polished = presentation_profile == PresentationProfile.POLISHED
	if is_polished:
		_apply_polish_environment()
	else:
		_restore_default_environment()
	board.setup(state.board_rows, state.board_cols, CELL_SIZE, is_polished)
	environment.setup(state.board_rows, state.board_cols, CELL_SIZE, is_polished)
	boarding_area.setup(state.waiting_slots.size(), state.board_cols, CELL_SIZE, is_polished)
	_passenger_crowd.setup(passengers_root, boarding_area, is_polished, state.board_cols, CELL_SIZE)
	_passenger_crowd.rebuild_dolls(state.passenger_queue)
	_spawn_vehicles()
	_refresh_selectable_highlights()
	_setup_camera()
	hud.update_state(state, "Toque em um veiculo livre.", _level_position_text(), -1, is_polished)
	print("Pega Passageiro - fase %s carregada." % state.level_id)

func _level_position_text() -> String:
	var index: int = available_levels.find(current_level_number)
	if index < 0:
		# Fase gerada proceduralmente: nao ha um total fixo, o jogo continua
		# sempre com uma fase nova.
		return "Fase %d" % current_level_number
	return "%d/%d" % [index + 1, available_levels.size()]

# ETAPA 6, itens 4 e 5 (PolishTest, fase 950 exclusivamente): fundo pastel,
# ambient suave, tonemap agradavel e SSAO leve (item 4); luz vindo de
# cima/lateral com sombra suave e curta (item 5). SSAO fica isolado num
# Environment NOVO (nunca o SubResource compartilhado do Game.tscn), entao
# nenhuma fase normal e afetada nem antes nem depois de rodar a PolishTest.
func _apply_polish_environment() -> void:
	if world_environment != null:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = PolishPalette.BACKGROUND
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1.0, 0.99, 0.96)
		env.ambient_light_energy = 1.15
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 1.35
		# SSAO leve (item 4: "se compativel, usar SSAO leve, nao sacrificar
		# performance mobile") -- raio/intensidade contidos, nunca em fase
		# normal.
		env.ssao_enabled = true
		env.ssao_radius = 0.8
		env.ssao_intensity = 0.9
		env.ssao_power = 1.1
		world_environment.environment = env
	if directional_light != null:
		# Vinda de cima/lateral (item 5), sombra mais suave/curta que o
		# padrao das fases normais (shadow_blur maior, energia um pouco
		# menor pra nao estourar contraste).
		directional_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
		directional_light.light_energy = 1.05
		directional_light.shadow_blur = 3.0
		directional_light.light_color = Color(1.0, 0.98, 0.94)

# Restaura exatamente o Environment/luz das fases normais -- chamado sempre
# que a fase carregada NAO e a PolishTest, mesmo que a sessao tenha acabado
# de sair da fase 950 (o Game.tscn e reaproveitado entre fases, entao sem
# isso o visual polido vazaria pra fase normal seguinte).
func _restore_default_environment() -> void:
	if world_environment != null and _default_environment != null:
		world_environment.environment = _default_environment
	if directional_light != null:
		directional_light.transform = _default_light_transform
		directional_light.light_energy = _default_light_energy
		directional_light.shadow_blur = _default_light_shadow_blur
		directional_light.light_color = _default_light_color

func _load_level_from_json(path: String) -> LevelDefinition:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var raw: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON de fase invalido: %s" % path)
		return null
	return LevelDefinition.from_dictionary(parsed as Dictionary)

func _fallback_level() -> LevelDefinition:
	return LevelDefinition.new(
		1,
		5,
		8,
		7,
		["red", "red", "blue", "blue", "green", "green", "yellow", "yellow"],
		[
			VehicleDefinition.new("red_car", "car", "red", 2, 5, 2, "horizontal", "left"),
			VehicleDefinition.new("blue_car", "car", "blue", 2, 2, 3, "vertical", "up"),
			VehicleDefinition.new("green_car", "car", "green", 2, 4, 4, "vertical", "down"),
			VehicleDefinition.new("yellow_car", "car", "yellow", 2, 1, 2, "horizontal", "right"),
		]
	)

func _spawn_vehicles() -> void:
	for child: Node in vehicles_root.get_children():
		child.free()
	vehicle_nodes.clear()
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		var vehicle_node := preload("res://scenes/game/Vehicle.tscn").instantiate() as VehicleController
		vehicles_root.add_child(vehicle_node)
		vehicle_node.setup_from_state(vehicle, CELL_SIZE, is_polished)
		if is_polished:
			# ETAPA 2B: aumento bem maior que a Etapa 2 (que so dava +10% ao
			# medium_car). Valores escolhidos na ponta CONSERVADORA de cada
			# faixa pedida (small +30-40%, medium +35-45%, bus +25-35%) porque
			# BOARD_VEHICLE_SCALE ja usa 86% da propria celula de footprint;
			# com esse multiplicador em cima, a extrapolacao pra fora da
			# celula fica (0.86*multiplicador - 1) do comprimento do
			# footprint, repartida nas duas pontas -- ver o comentario no
			# level_950.json (ETAPA 2B) sobre a folga minima de 1 celula
			# vazia mantida entre veiculos no layout novo, calculada
			# exatamente para cobrir essa extrapolacao com margem. Nao mexe
			# em VehicleVisualLibrary nem em BOARD_VEHICLE_SCALE (globais).
			vehicle_node.scale *= _polish_test_vehicle_scale_multiplier(vehicle.type_id)
		vehicle_node.pressed.connect(_on_vehicle_pressed)
		vehicle_nodes[vehicle_id] = vehicle_node

func _polish_test_vehicle_scale_multiplier(type_id: String) -> float:
	match type_id:
		"small_car":
			return 1.30
		"medium_car", "van":
			return 1.35
		"bus", "mini_bus":
			return 1.25
		_:
			return 1.0

# Passo 9 (animacoes secundarias): brilho suave nos veiculos que podem sair
# agora. Reaproveita GameEngine.can_vehicle_exit -- a MESMA funcao pura que
# ja decide bloqueio no toque -- entao o indicador nunca diverge da regra
# real. So leitura de estado; nao muda nada em GameEngine nem em state.
func _refresh_selectable_highlights() -> void:
	for vehicle_id: String in vehicle_nodes.keys():
		var vehicle_node: VehicleController = vehicle_nodes[vehicle_id] as VehicleController
		if vehicle_node == null:
			continue
		var vehicle: VehicleState = state.vehicles.get(vehicle_id) as VehicleState
		if vehicle == null or vehicle.status != VehicleState.ON_BOARD:
			vehicle_node.set_selectable(false)
			continue
		vehicle_node.set_selectable(GameEngine.can_vehicle_exit(state, vehicle_id)["can_exit"])

# Ponto de entrada de TODO toque em veiculo. NAO serializa mais: se um
# veiculo valido e tocado enquanto outro ja esta andando/estacionando/
# embarcando, os dois processam em PARALELO (pedido explicito: "a ideia e
# ir outro concomitante"). _process_vehicle_tap e uma corrotina; chama-la
# sem serializar so funciona porque cada uma so mexe no que e dela ate o
# primeiro "await" (a mutacao do estado logico e sincrona, sempre antes de
# qualquer animacao), entao duas chamadas concorrentes nunca correm o risco
# de pegar a mesma vaga ou o mesmo passageiro -- ver comentarios dentro de
# _process_vehicle_tap e _reserve_boarding_dolls.
func _on_vehicle_pressed(vehicle_id: String) -> void:
	if state.status != GameState.PLAYING:
		return
	await _process_vehicle_tap(vehicle_id)

func _begin_tap_animation() -> void:
	_active_tap_count += 1
	is_animating = true

func _end_tap_animation() -> void:
	_active_tap_count = maxi(_active_tap_count - 1, 0)
	is_animating = _active_tap_count > 0

# Processa UM toque. Pode rodar ao mesmo tempo que outras chamadas desta
# mesma funcao (uma por veiculo tocado) -- ver nota em _on_vehicle_pressed.
func _process_vehicle_tap(vehicle_id: String) -> void:
	var vehicle_node: VehicleController = vehicle_nodes.get(vehicle_id) as VehicleController
	if vehicle_node == null:
		return
	# ETAPA 3/8: presentation_profile decide isto agora (nao mais uma
	# comparacao local com 950) -- qualquer fase POLISHED (950, 1, 2 ou 3)
	# ignora novos toques durante animacao "polida" em andamento -- ver
	# VehicleController.is_polish_busy().
	if is_polished and vehicle_node.is_polish_busy():
		return
	# Rede de seguranca: com toques concorrentes, um segundo toque no MESMO
	# veiculo (antes da primeira animacao dele terminar) chega aqui depois
	# que o primeiro ja mudou o status dele pra WAITING/COMPLETE. Sem isto,
	# GameEngine devolveria "VehicleUnavailable" -- nem bloqueado nem
	# sem-vaga -- e o codigo cairia sem querer no caminho de sucesso.
	var vehicle_state: VehicleState = state.vehicles.get(vehicle_id) as VehicleState
	if vehicle_state == null or vehicle_state.status != VehicleState.ON_BOARD:
		return

	var result: Dictionary = GameEngine.try_send_vehicle_to_waiting_slot(state, vehicle_id)
	var events: Array = result["events"]
	var blocked: bool = _has_event(events, "VehicleBlocked")
	var no_slot: bool = _has_event(events, "NoWaitingSlotAvailable")

	if blocked:
		_blocked_tap_count += 1
		if is_polished:
			vehicle_node.animate_blocked_polished()
		else:
			vehicle_node.animate_blocked()
		_camera_shake_blocked()
		AudioManager.play_sfx("blocked")
		AudioManager.vibrate(45)
		hud.update_state(state, "Esse veiculo esta bloqueado.", _level_position_text(), -1, is_polished)
		return
	if no_slot:
		vehicle_node.animate_no_slot()
		AudioManager.vibrate(35)
		hud.update_state(state, "As vagas de espera estao ocupadas.", _level_position_text(), -1, is_polished)
		return

	_begin_tap_animation()
	if is_polished:
		vehicle_node.animate_valid_tap_polished()
		# ETAPA 5/8: particula discreta na base do veiculo ao confirmar o
		# toque -- em qualquer fase com presentation_profile POLISHED.
		_polish_effects.tap_spark(vehicle_node.global_position)
	else:
		vehicle_node.animate_valid_tap()
	_camera_pulse_valid_tap()
	AudioManager.play_sfx("tap_valid")
	AudioManager.vibrate(18)

	# O estado logico (inclusive quais passageiros embarcam) e confirmado
	# AQUI, de forma sincrona -- antes do primeiro "await" desta funcao.
	# Isso e o que garante que dois veiculos tocados em sequencia rapida
	# nunca disputam a mesma vaga de espera nem o mesmo passageiro da fila,
	# mesmo que suas animacoes depois rodem juntas.
	state = result["state"]
	var boarding_dolls: Array[PassengerController] = _reserve_boarding_dolls(events)
	var slot_index: int = _state_slot_index(vehicle_id)
	if slot_index < 0:
		slot_index = _event_slot_index(events, vehicle_id)
	# ETAPA 6: so pra identificar a vaga nos logs de diagnostico de rotacao
	# do veiculo (ver VehicleController._log_polish_rotation) -- nao afeta
	# nenhuma logica de posicionamento real.
	vehicle_node.polish_slot_index = slot_index
	var route: Array[Vector3] = _build_route_to_waiting_slot(vehicle_node, slot_index)
	# ETAPA 6B (item 1): buscamos o Marker3D da vaga ANTES de iniciar a
	# animacao, pra entregar a orientacao final (slot.rotation_degrees.y,
	# ver BoardingAreaController.POLISH_PARKED_YAW_DEGREES) pro VehicleController desde o comeco da
	# aproximacao -- em vez de ele calcular um heading a partir de
	# posicao/tangente da curva (fonte antiga, agora proibida pelo ticket).
	var final_marker: Marker3D = boarding_area.get_slot_marker(slot_index)
	var slot_yaw_degrees: float = final_marker.global_rotation_degrees.y if final_marker != null else 0.0
	hud.show_message("Veiculo a caminho dos passageiros...")
	AudioManager.play_sfx("car_driving")
	if is_polished:
		await vehicle_node.drive_route_polished(route, slot_yaw_degrees)
	else:
		await vehicle_node.drive_route(route)
	# Snap final em coordenada GLOBAL. Mesmo que algum ponto intermediario use
	# coordenadas locais, o carro termina exatamente no Marker3D do slot.
	if final_marker != null:
		vehicle_node.global_position = final_marker.global_position
		_vehicle_slot_markers[vehicle_id] = final_marker
		# ETAPA 6B (itens 1, 3 e 4): ultima palavra sobre a orientacao --
		# fonte unica e explicita (slot_yaw_degrees), mata qualquer tween
		# residual que ainda escreva rotation_degrees, zera roll/pitch, e
		# faz o assert de divergencia (push_error se diff > 1 grau) -- so na
		# PolishTest.
		if is_polished:
			vehicle_node.snap_polish_parked_orientation(slot_yaw_degrees)
		# Numero regressivo aparece no instante em que o carro encosta na vaga
		# (ainda ninguem embarcou -- os PassengerBoarded desta leva so tocam
		# durante _play_boarding_events logo abaixo, e cada um atualiza este
		# mesmo numero com o valor real do evento).
		var parked_vehicle: VehicleState = state.vehicles.get(vehicle_id) as VehicleState
		if parked_vehicle != null:
			var initial_count_text: String = str(maxi(parked_vehicle.capacity - parked_vehicle.occupied_seats, 0))
			if is_polished:
				boarding_area.set_slot_label_text_pop(final_marker, initial_count_text)
				# ETAPA 3B: na fase 950 a escala "estacionada" (e a transicao ate
				# ela) ja foi aplicada dentro de drive_route_polished() (ver
				# VehicleController._drive_final_approach_polished) -- chamar
				# set_waiting_slot_mode(true) aqui por cima desfaria a transicao
				# suave com um snap pros fatores antigos (0.48/0.60/0.72).
				# ETAPA 4 (item 3): passageiros da cor certa reagem (micro pop)
				# antes do primeiro comecar a correr -- ver _play_boarding_events
				# logo abaixo, que so dispara a corrida em si.
				_passenger_crowd.react_for_color(vehicle_node.color_id)
			else:
				boarding_area.set_slot_label_text(final_marker, initial_count_text)
				vehicle_node.set_waiting_slot_mode(true)
	AudioManager.play_sfx("car_parking")
	AudioManager.vibrate(22)

	# Agora reproduzimos PassengerBoarded/SlotFreed na ordem dos eventos do motor.
	await _play_boarding_events(events, boarding_dolls)
	_passenger_crowd.sync_to_state(state.passenger_queue)

	if _has_event(events, "Win"):
		AudioManager.play_sfx("win")
		var coins_awarded: int = Wallet.award_win_bonus()
		hud.play_coin_reward(coins_awarded)
		_polish_effects.win_particles()
		_camera_zoom_out_for_win()
		last_stars_earned = _stars_for_run()
		ProgressService.report_level_result(current_level_number, last_stars_earned)
	elif _has_event(events, "GameOver"):
		AudioManager.play_sfx("game_over")
		AudioManager.vibrate(40)
		_apply_game_over_desaturation()
		# ETAPA 4B ("LOG TEMPORARIO", diagnostico do falso "Travou"): SOMENTE na
		# PolishTest, e SOMENTE no instante em que o motor decide GameOver.
		# Remover depois que a investigacao/QA desta etapa terminar -- nunca deve
		# poluir fases normais nem ficar permanente.
		if is_polished:
			_debug_dump_deadlock_state()

	_refresh_selectable_highlights()
	hud.update_state(state, _message_from_events(events), _level_position_text(), last_stars_earned, is_polished)
	_end_tap_animation()

# ETAPA 4B ("LOG TEMPORARIO"): dump de diagnostico chamado SOMENTE quando a
# PolishTest detecta GameOver -- imprime exatamente a lista pedida (veiculos
# restantes/completed, vagas, vehicle_id por vaga, capacidade restante,
# tamanho da fila, cores no comeco dela, _pending_polish_boardings e quais
# veiculos ainda estao animando) para investigar se um "Travou" e um
# deadlock logico real ou uma janela de sincronizacao entre motor/visual.
# TEMPORARIO: remover estas chamadas depois que a investigacao terminar.
func _debug_dump_deadlock_state() -> void:
	print("[PolishTest][DEADLOCK] ---- diagnostico de Travou (fase %d, move %d) ----" % [state.level_id, state.moves])
	var remaining_on_board: Array[String] = []
	var completed_vehicles: Array[String] = []
	for vid: String in state.vehicles.keys():
		var v: VehicleState = state.vehicles[vid]
		if v.status == VehicleState.ON_BOARD:
			remaining_on_board.append(vid)
		elif v.status == VehicleState.COMPLETE:
			completed_vehicles.append(vid)
	print("[PolishTest][DEADLOCK] veiculos ON_BOARD restantes (%d): %s" % [remaining_on_board.size(), remaining_on_board])
	print("[PolishTest][DEADLOCK] veiculos COMPLETE (%d): %s" % [completed_vehicles.size(), completed_vehicles])
	for slot: WaitingSlotState in state.waiting_slots:
		if slot.is_empty():
			print("[PolishTest][DEADLOCK] slot %d: vazio" % slot.index)
		else:
			var parked: VehicleState = state.vehicles[slot.vehicle_id]
			print("[PolishTest][DEADLOCK] slot %d: vehicle_id=%s color=%s ocupados=%d/%d (faltam %d)" % [
				slot.index, slot.vehicle_id, parked.color_id, parked.occupied_seats, parked.capacity,
				parked.capacity - parked.occupied_seats,
			])
	print("[PolishTest][DEADLOCK] fila: %d passageiros restantes" % state.passenger_queue.size())
	var front_preview: Array[String] = []
	for i: int in range(mini(10, state.passenger_queue.size())):
		front_preview.append(state.passenger_queue[i])
	print("[PolishTest][DEADLOCK] cores no comeco da fila: %s" % [front_preview])
	print("[PolishTest][DEADLOCK] _pending_polish_boardings: %s" % [_pending_polish_boardings])
	var animating: Array[String] = []
	for vid: String in vehicle_nodes.keys():
		var node: VehicleController = vehicle_nodes[vid] as VehicleController
		if node != null and is_instance_valid(node) and node.is_polish_busy():
			animating.append(vid)
	print("[PolishTest][DEADLOCK] veiculos atualmente animando (is_polish_busy): %s" % [animating])
	print("[PolishTest][DEADLOCK] ------------------------------------------")

# Criterio de estrelas (etapa 9, decisao confirmada): baseado em quantas
# vezes o jogador tocou num veiculo bloqueado durante a fase.
func _stars_for_run() -> int:
	if _blocked_tap_count <= 0:
		return 3
	if _blocked_tap_count <= 2:
		return 2
	return 1

# Dica (etapa 9, decisao confirmada): gasta moedas de verdade pela primeira
# vez no jogo e destaca um veiculo com uma jogada valida.
func _on_hint_requested() -> void:
	if is_animating or state == null or state.status != GameState.PLAYING:
		return
	if not Wallet.spend_coins(HINT_COST):
		hud.show_message("Moedas insuficientes para a dica.")
		return
	var target_id: String = _find_hint_vehicle_id()
	if target_id == "":
		Wallet.add_coins(HINT_COST)
		hud.show_message("Nenhuma jogada disponivel agora.")
		return
	var vehicle_node: VehicleController = vehicle_nodes.get(target_id) as VehicleController
	if vehicle_node != null:
		vehicle_node.animate_hint()
	AudioManager.play_sfx("coin")
	hud.show_message("Toque no veiculo destacado.")

func _find_hint_vehicle_id() -> String:
	var front_color: String = state.get_front_passenger_color()
	var fallback_id: String = ""
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		if not GameEngine.can_vehicle_exit(state, vehicle_id)["can_exit"]:
			continue
		if vehicle.color_id == front_color:
			return vehicle_id
		if fallback_id == "":
			fallback_id = vehicle_id
	return fallback_id

func _state_slot_index(vehicle_id: String) -> int:
	# Fonte definitiva para o visual: o estado atual do motor. Isso evita que
	# qualquer evento intermediario/ordem de animacao mande dois carros ao mesmo slot.
	for slot: WaitingSlotState in state.waiting_slots:
		if slot.vehicle_id == vehicle_id:
			return slot.index
	return -1

func _event_slot_index(events: Array, vehicle_id: String) -> int:
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == "VehicleParked" and String(event.payload.get("vehicle_id", "")) == vehicle_id:
			return int(event.payload.get("slot_index", 0))
	return 0

func _boarding_slot_position(slot_index: int) -> Vector3:
	var marker: Marker3D = boarding_area.get_slot_marker(slot_index)
	if marker != null:
		# VehicleController.position e todos os pontos usados por drive_route()
		# estao no espaco LOCAL de Vehicles. O Marker3D pertence a BoardingArea,
		# portanto nunca misturamos marker.global_position diretamente com
		# vehicle.position. A conversao explicita elimina o deslocamento que fazia
		# o segundo carro terminar atras/sobre o primeiro.
		return vehicles_root.to_local(marker.global_position)
	# Fallback defensivo ja no mesmo espaco local de Vehicles.
	var fallback_world := boarding_area.to_global(Vector3(float(state.board_cols) * CELL_SIZE * 0.5, 0.31, -0.52))
	return vehicles_root.to_local(fallback_world)

func _build_route_to_waiting_slot(vehicle_node: VehicleController, slot_index: int) -> Array[Vector3]:
	var route: Array[Vector3] = []
	var rows_depth: float = float(state.board_rows) * CELL_SIZE
	var cols_width: float = float(state.board_cols) * CELL_SIZE
	var margin: float = 0.72
	var lane_z: float = -0.78
	# ETAPA 3B: na fase 950 a faixa de embarque foi comprimida bem perto do
	# tabuleiro (ver BoardingAreaController.POLISH_SLOT_GAP_TO_BOARD/_setup_polish), e
	# o -0.78 generico acima ja fica DENTRO da vaga (que comeca em
	# -boarding_area.get_slot_gap_to_board() = -0.15) -- o veiculo cruzava lateralmente por
	# cima do piso da vaga antes de virar pra entrar, em vez de alinhar ANTES
	# dela. Aqui o alinhamento em X passa a acontecer exatamente na entrada da
	# vaga; o trecho final ate o centro (ApproachPoint->SlotCenter, ver
	# VehicleController.drive_route_polished/_drive_final_approach_polished)
	# cobre a profundidade real da vaga de forma reta e explicita.
	# ETAPA 8: agora vale pra qualquer fase POLISHED (nao mais so a 950).
	if is_polished:
		lane_z = -boarding_area.get_slot_gap_to_board()
	var stage: Vector3 = vehicle_node.position

	# Primeiro o veiculo realmente sai do tabuleiro pela direcao autorizada
	# (a mesma ExitDirection.Value que o GameEngine ja validou -- nunca a
	# rotacao visual).
	match vehicle_node.exit_direction:
		ExitDirection.Value.UP:
			stage.z = lane_z
		ExitDirection.Value.DOWN:
			stage.z = rows_depth + margin
		ExitDirection.Value.LEFT:
			stage.x = -margin
		ExitDirection.Value.RIGHT:
			stage.x = cols_width + margin
	# ETAPA 8 (secao 9 -- bug da curva exagerada ao SAIR da vaga rumo a area
	# de passageiros): so a direcao UP tem seu ponto de saida derivado de
	# lane_z, que em fases POLISHED fica bem perto do tabuleiro (-0.15,
	# contra o -0.78 generico). Isso criava um primeiro segmento de saida
	# MUITO curto, concentrando uma curva grande numa fatia minuscula do
	# comprimento/tempo total da animacao (ver _build_route_curve/
	# drive_route_polished em VehicleController) -- lido visualmente como um
	# giro brusco/diagonal logo que o veiculo deixa o tabuleiro. Fix: garante
	# uma folga MINIMA de saida (o mesmo "margin" ja usado pelas outras 3
	# direcoes) antes da curva -- e so a geometria do waypoint visual, nao
	# toca em GameEngine/pathfinding. Nao muda nada fora do caso
	# POLISHED+UP+lane_z comprimido: em fases CLASSIC lane_z ja e -0.78 (mais
	# negativo que -margin=-0.72), entao minf() nunca altera esse resultado.
	if vehicle_node.exit_direction == ExitDirection.Value.UP:
		stage.z = minf(stage.z, vehicle_node.position.z - margin)
		lane_z = stage.z
	route.append(stage)

	# IMPORTANTE: slot_position ja esta convertido para o espaco local de
	# Vehicles, exatamente o mesmo espaco de vehicle_node.position.
	var slot_position: Vector3 = _boarding_slot_position(slot_index)

	# Depois entra numa faixa comum de embarque. O ultimo ponto e SEMPRE o
	# Marker3D do slot logico convertido para o espaco correto.
	if vehicle_node.exit_direction == ExitDirection.Value.DOWN:
		var side_x: float = -margin
		if vehicle_node.position.x >= cols_width * 0.5:
			side_x = cols_width + margin
		route.append(Vector3(side_x, 0.31, rows_depth + margin))
		route.append(Vector3(side_x, 0.31, lane_z))
	elif vehicle_node.exit_direction == ExitDirection.Value.LEFT:
		route.append(Vector3(-margin, 0.31, lane_z))
	elif vehicle_node.exit_direction == ExitDirection.Value.RIGHT:
		route.append(Vector3(cols_width + margin, 0.31, lane_z))

	route.append(Vector3(slot_position.x, 0.31, lane_z))
	route.append(slot_position)
	return route

# reserved_dolls: os bonecos que vao embarcar NESTA leva, na MESMA ordem dos
# eventos "PassengerBoarded" -- ja escolhidos por _reserve_boarding_dolls()
# no instante do toque (sincrono), nao aqui. Isso importa porque agora
# varios veiculos podem estar animando ao mesmo tempo (varios toques
# concorrentes): se o boneco so fosse escolhido AQUI (quando a animacao de
# CADA carro finalmente chega nesse ponto), um carro que demorasse mais pra
# chegar podia acabar roubando visualmente o boneco que logicamente ja
# tinha embarcado em outro carro que chegou primeiro.
func _play_boarding_events(events: Array, reserved_dolls: Array[PassengerController]) -> void:
	# ETAPA 4: na fase 950 o embarque roda em cascata (varios passageiros
	# correndo ao mesmo tempo, ver _play_boarding_events_polished) em vez do
	# loop sequencial abaixo (um boneco so comeca depois do anterior
	# terminar). Toda fase normal continua exatamente no loop original,
	# inalterado.
	if is_polished:
		await _play_boarding_events_polished(events, reserved_dolls)
		return
	var doll_cursor := 0
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event == null:
			continue
		if event.type == "PassengerBoarded":
			var boarded_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var target_vehicle: VehicleController = vehicle_nodes.get(boarded_vehicle_id) as VehicleController
			var passenger: PassengerController = reserved_dolls[doll_cursor] if doll_cursor < reserved_dolls.size() else null
			doll_cursor += 1
			if target_vehicle == null or passenger == null or not is_instance_valid(passenger):
				continue
			var color_id: String = String(event.payload.get("color_id", "red"))
			await passenger.walk_to_and_board(target_vehicle.get_boarding_point())
			target_vehicle.animate_boarding_bounce()
			AudioManager.play_sfx("passenger_board")
			_polish_effects.boarding_spark(target_vehicle.get_boarding_point(), color_id)
			# Contador regressivo no proprio carro: sempre o numero real do
			# evento (capacity - occupied_seats), nunca reconsultado depois --
			# assim continua certo mesmo com varios veiculos animando juntos.
			var remaining: int = maxi(int(event.payload.get("capacity", 0)) - int(event.payload.get("occupied_seats", 0)), 0)
			var boarding_marker: Marker3D = _vehicle_slot_markers.get(boarded_vehicle_id) as Marker3D
			if boarding_marker != null:
				boarding_area.set_slot_label_text(boarding_marker, str(remaining))
		elif event.type == "SlotFreed":
			var completed_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var completed_node: VehicleController = vehicle_nodes.get(completed_vehicle_id) as VehicleController
			var freed_marker: Marker3D = _vehicle_slot_markers.get(completed_vehicle_id) as Marker3D
			if freed_marker != null:
				boarding_area.set_slot_label_text(freed_marker, "")
			_vehicle_slot_markers.erase(completed_vehicle_id)
			if completed_node != null:
				AudioManager.play_sfx("vehicle_complete")
				AudioManager.vibrate(30)
				_polish_effects.vehicle_complete_burst(completed_node.global_position, completed_node.color_id)
				completed_node.set_waiting_slot_mode(false)
				AudioManager.play_sfx("car_driving")
				await completed_node.drive_away_from_pickup(float(state.board_cols) * CELL_SIZE)
				completed_node.queue_free()
				vehicle_nodes.erase(completed_vehicle_id)

# ETAPA 4 (Polish Test, fase 950 exclusivamente): mesma leitura de eventos de
# _play_boarding_events() acima, mas cada PassengerBoarded dispara sua propria
# corrida (_run_cascaded_boarding) SEM aguardar (fire-and-forget) em vez de um
# "await" sequencial por boneco -- e isso que cria a cascata pedida (varios
# passageiros correndo ao mesmo tempo, item 4), com um pequeno atraso entre um
# disparo e o proximo (item 10, por capacidade do veiculo). Um SlotFreed so
# libera o veiculo pra sair depois que TODOS os embarques em cascata daquele
# veiculo terminarem visualmente (_pending_polish_boardings, item 16) --
# a logica ja concluiu no GameEngine antes disso, isto e so a apresentacao.
func _play_boarding_events_polished(events: Array, reserved_dolls: Array[PassengerController]) -> void:
	var doll_cursor := 0
	var cascade_index_by_vehicle: Dictionary = {}
	# ETAPA 4B: garante que a fila so reorganiza visualmente UMA vez por leva,
	# logo depois que o primeiro passageiro dela ja tiver comecado a sair de
	# verdade (ver comentario completo em PassengerCrowdController.advance_dolls_polished e em
	# _reserve_boarding_dolls, que deliberadamente NAO reorganiza mais aqui).
	var queue_advance_started := false
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event == null:
			continue
		if event.type == "PassengerBoarded":
			var boarded_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var target_vehicle: VehicleController = vehicle_nodes.get(boarded_vehicle_id) as VehicleController
			var passenger: PassengerController = reserved_dolls[doll_cursor] if doll_cursor < reserved_dolls.size() else null
			doll_cursor += 1
			if target_vehicle == null or passenger == null or not is_instance_valid(passenger):
				continue
			var color_id: String = String(event.payload.get("color_id", "red"))
			var remaining: int = maxi(int(event.payload.get("capacity", 0)) - int(event.payload.get("occupied_seats", 0)), 0)
			var boarding_marker: Marker3D = _vehicle_slot_markers.get(boarded_vehicle_id) as Marker3D
			var cascade_index: int = int(cascade_index_by_vehicle.get(boarded_vehicle_id, 0))
			cascade_index_by_vehicle[boarded_vehicle_id] = cascade_index + 1
			var stagger_delay: float = float(cascade_index) * _polish_cascade_interval(target_vehicle.type_id)
			_pending_polish_boardings[boarded_vehicle_id] = int(_pending_polish_boardings.get(boarded_vehicle_id, 0)) + 1
			_run_cascaded_boarding(passenger, target_vehicle, boarded_vehicle_id, color_id, remaining, stagger_delay, boarding_marker)
			# NAO aguardado de proposito -- varios podem estar correndo juntos.
			# _run_cascaded_boarding ja rodou sincronamente ate seu proprio
			# primeiro "await" (o pop/passo-pra-fora dentro de
			# walk_to_and_board_polished, para cascade_index 0/stagger_delay 0.0)
			# antes desta linha executar -- ou seja, o primeiro passageiro desta
			# leva ja esta visivelmente saindo da fila neste ponto. So agora e
			# seguro reorganizar o resto da fila (fire-and-forget, com o stagger
			# proprio de PassengerCrowdController.advance_dolls_polished).
			if not queue_advance_started:
				queue_advance_started = true
				_passenger_crowd.advance_dolls_polished()
		elif event.type == "SlotFreed":
			var completed_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			# Item 16: espera os embarques visuais em cascata desse veiculo
			# terminarem antes de deixa-lo sair, mesmo que o GameEngine ja
			# tenha concluido a logica (o motor nao sabe nada sobre esta
			# espera -- e puramente de apresentacao). Este e o momento exato em
			# que o "ULTIMO PASSAGEIRO TERMINA" (ETAPA 4B, SINCRONIZACAO DO
			# VEICULO).
			while int(_pending_polish_boardings.get(completed_vehicle_id, 0)) > 0:
				await get_tree().process_frame
			var completed_node: VehicleController = vehicle_nodes.get(completed_vehicle_id) as VehicleController
			var freed_marker: Marker3D = _vehicle_slot_markers.get(completed_vehicle_id) as Marker3D
			if freed_marker != null:
				boarding_area.set_slot_label_text(freed_marker, "")
				# ETAPA 5, item 7: "+" some com pop, piso/borda pulsa e uma
				# particula verde curta marca "esta vaga acabou de abrir".
				_polish_effects.slot_freed_feedback_polished(freed_marker)
			_vehicle_slot_markers.erase(completed_vehicle_id)
			_pending_polish_boardings.erase(completed_vehicle_id)
			if completed_node != null:
				AudioManager.play_sfx("vehicle_complete")
				AudioManager.vibrate(30)
				_polish_effects.vehicle_complete_burst(completed_node.global_position, completed_node.color_id)
				# ETAPA 5/8: recompensa visual "+10" e o contador DEV continuam
				# EXCLUSIVOS da PolishTest (fase 950 literal) -- nunca aparecem em
				# fases reais (1-3), mesmo com presentation_profile POLISHED. Nunca
				# passa por Wallet/save real (ver _polish_local_coin_balance).
				if state.level_id == POLISH_TEST_LEVEL_ID:
					_polish_local_coin_balance += 10
					_polish_effects.coin_popup(completed_node.global_position)
					hud.show_polish_test_coin_counter(_polish_local_coin_balance)
				# ETAPA 4B (SINCRONIZACAO DO VEICULO, pedido explicito): pequena
				# pausa (~0.10s) + micro reacao de "lotado" ANTES de sair, pra
				# separar visualmente "terminou embarque" de "carro foi embora".
				# Substitui o set_waiting_slot_mode(false) generico que havia aqui:
				# aquele reset usa OUTRO sistema de escala (BOARD_VEHICLE_SCALE,
				# fixo por tipo) e brigava, num salto sem transicao, com a escala
				# "estacionada" polida (POLISH_TYPE_PARKED_SCALE_MULTIPLIER) --
				# um dos fatores que contribuia para o veiculo parecer "errado"
				# bem no instante em que comecava a sair (ver Problema 2 do pedido).
				await get_tree().create_timer(0.10).timeout
				if is_instance_valid(completed_node):
					await completed_node.animate_vehicle_full_polished()
				AudioManager.play_sfx("car_driving")
				if is_instance_valid(completed_node):
					await completed_node.drive_away_from_pickup_polished(float(state.board_cols) * CELL_SIZE)
					completed_node.queue_free()
				vehicle_nodes.erase(completed_vehicle_id)

# Worker de UM embarque em cascata: espera seu proprio atraso escalonado
# (stagger_delay), corre ate a porta, e so entao toca o bounce/som/faisca/
# contador -- chamado SEM "await" pelo chamador (fire-and-forget), entao
# varios destes rodam ao mesmo tempo para o mesmo veiculo (e para veiculos
# diferentes, ver item 15/concorrencia). Sempre decrementa
# _pending_polish_boardings no final (inclusive nos caminhos de saida
# antecipada), pra nunca travar um SlotFreed esperando por um embarque que
# nao vai mais acontecer (ex.: veiculo removido no meio do caminho).
func _run_cascaded_boarding(passenger: PassengerController, target_vehicle: VehicleController, vehicle_id: String, color_id: String, remaining: int, stagger_delay: float, boarding_marker: Marker3D) -> void:
	if stagger_delay > 0.0:
		await get_tree().create_timer(stagger_delay).timeout
	if is_instance_valid(passenger) and is_instance_valid(target_vehicle):
		await passenger.walk_to_and_board_polished(target_vehicle.get_boarding_point())
		if is_instance_valid(target_vehicle):
			target_vehicle.animate_boarding_bounce()
		_polish_effects.play_board_sfx_throttled()
		if is_instance_valid(target_vehicle):
			_polish_effects.boarding_spark(target_vehicle.get_boarding_point(), color_id)
		if boarding_marker != null:
			boarding_area.set_slot_label_text_pop_bump(boarding_marker, str(remaining))
	_pending_polish_boardings[vehicle_id] = maxi(int(_pending_polish_boardings.get(vehicle_id, 1)) - 1, 0)

# Item 10 do pedido: intervalo entre disparos da cascata, por tipo de
# veiculo (proxy direto da capacidade -- small_car=16/medium_car=24/bus=40).
# Onibus recebe gente numa "corrente" mais rapida que carro pequeno, sem
# nunca virar uma massa sobreposta (o passo minimo ainda deixa cada
# passageiro visivelmente separado do anterior).
func _polish_cascade_interval(vehicle_type_id: String) -> float:
	# ETAPA 4B: intervalos aumentados levemente (pedido explicito) para
	# melhorar a leitura individual de cada passageiro sem deixar a cascata
	# lenta -- small_car 0.10->0.11, medium_car 0.085->0.095, bus 0.07->0.08.
	match vehicle_type_id:
		"bus", "mini_bus":
			return 0.08
		"medium_car", "van":
			return 0.095
		_:
			return 0.11


# Chamada SINCRONA, no instante do toque (antes de qualquer await em
# _process_vehicle_tap) -- reserva, na ordem certa, um boneco 3D real da
# fila para cada evento "PassengerBoarded" desta leva, e ja tira esses
# bonecos da fila visual (PassengerCrowdController). Isso e o que garante a identidade certa mesmo com
# varios veiculos animando ao mesmo tempo: quem reserva primeiro (ordem real
# dos toques) fica com os bonecos da frente, nao quem termina de andar
# primeiro.
func _reserve_boarding_dolls(events: Array) -> Array[PassengerController]:
	var reserved: Array[PassengerController] = []
	var popped_any := false
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == "PassengerBoarded":
			var color_id: String = String(event.payload.get("color_id", "red"))
			reserved.append(_passenger_crowd.pop_front_doll(color_id))
			popped_any = true
	# ETAPA 4B: na fase 950 a reorganizacao VISUAL da fila (bonecos restantes
	# deslizando pra fechar o buraco) fica pra depois -- ver
	# _play_boarding_events_polished/PassengerCrowdController.advance_dolls_polished, chamada so
	# quando o primeiro passageiro desta leva ja tiver claramente comecado a
	# sair. Antes disso o embarque nem comecou visualmente (o veiculo ainda
	# vai dirigir ate a vaga), entao reorganizar aqui (na hora do toque, como
	# a fase normal sempre fez) dava a impressao de "a fila inteira mudou antes
	# de alguem sair". O pop/reserva em si (PassengerCrowdController.pop_front_doll acima)
	# continua exatamente aqui, sincrono -- e o que garante a identidade certa
	# com toques concorrentes, isso nunca muda.
	if popped_any and not is_polished:
		_passenger_crowd.advance_dolls()
	return reserved

func _message_from_events(events: Array) -> String:
	if _has_event(events, "Win"):
		return "Fase concluida!"
	if _has_event(events, "GameOver"):
		return "Sem movimentos possiveis."
	if _has_event(events, "PassengerBoarded"):
		return "Passageiros embarcaram."
	if _has_event(events, "VehicleParked"):
		return "Veiculo aguardando sua cor."
	return "Escolha o proximo veiculo."

func _has_event(events: Array, event_type: String) -> bool:
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == event_type:
			return true
	return false

# VFX leve de embarque (etapa 10 - polimento): poucas particulas coloridas
# no ponto de embarque, sem asset novo (mesma tecnica procedural do
# confete de vitoria, so que menor e na cor do passageiro).
func _setup_camera() -> void:
	var center: Vector3 = board.get_board_center()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# ETAPA 8: qualquer fase POLISHED (950, 1, 2 ou 3) usa pitch/altura
	# diferentes -- toda fase CLASSIC cai no "else" com os mesmos
	# CAMERA_PITCH_DEGREES/CAMERA_HEIGHT de sempre, entao o resultado
	# numerico pras fases CLASSIC e IDENTICO ao de antes desta etapa.
	var pitch_degrees: float = POLISH_CAMERA_PITCH_DEGREES if is_polished else CAMERA_PITCH_DEGREES
	var camera_height: float = POLISH_CAMERA_HEIGHT if is_polished else CAMERA_HEIGHT
	camera.rotation_degrees = Vector3(pitch_degrees, 0.0, 0.0)

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)

	# A camera olha de cima em angulo (pitch_degrees). pitch_sin e a taxa de
	# conversao entre "size" (extensao vertical ortogonal) e profundidade real
	# no chao (Z); pitch_cos entra na relacao entre a altura da camera e o
	# quanto ela precisa se deslocar em Z pra um dado Z do mundo cair numa
	# fracao de tela especifica.
	var pitch_rad: float = deg_to_rad(pitch_degrees)
	var pitch_sin: float = sin(pitch_rad)
	var pitch_cos: float = cos(pitch_rad)

	# Os dois "Z do mundo" que TEM que cair exatamente logo abaixo da faixa de
	# HUD de cima e logo acima da de baixo: nao e mais "as linhas do
	# tabuleiro", e sim "a area de embarque inteira" (que fica ANTES da linha
	# 0, ver BOARDING_AREA_DEPTH) ate "a ultima linha do tabuleiro + folga".
	# Tratar so as linhas do tabuleiro (sem contar a area de embarque) foi
	# exatamente o bug relatado: a plataforma/letreiros ficavam escondidos
	# atras do HUD de cima em fases com HUD maior.
	# ETAPA 2C: a PolishTest agora usa sua PROPRIA profundidade de area de
	# embarque (POLISH_BOARDING_AREA_DEPTH), calculada a partir do layout novo
	# de vagas+passageiros (ver constante acima) -- nao mais a BOARDING_AREA_DEPTH
	# compartilhada, que continua exatamente igual e intocada para toda fase
	# normal. Isso e o que garante que a ultima fileira de passageiros (ate 40,
	# pior caso de um onibus) nunca mais caia atras do HUD superior.
	var boarding_area_depth: float = POLISH_BOARDING_AREA_DEPTH if is_polished else BOARDING_AREA_DEPTH
	var top_z: float = -boarding_area_depth
	var bottom_z: float = float(state.board_rows) * CELL_SIZE + BOARD_EDGE_MARGIN

	var top_fraction: float = HUD_TOP_UNSAFE_FRACTION + CAMERA_FRAME_SAFETY_FRACTION
	var bottom_fraction: float = 1.0 - HUD_BOTTOM_UNSAFE_FRACTION - CAMERA_FRAME_SAFETY_FRACTION

	# PolishTest: em vez de esticar o conteudo pra preencher a faixa util
	# INTEIRA (100%, o comportamento padrao de sempre, mantido abaixo para
	# toda fase normal), encolhe a faixa-alvo para POLISH_BOARD_FILL_FRACTION
	# dela, centralizada -- e o "respiro"/composicao de diorama pedido, sem
	# mudar em nada o calculo usado pelas fases normais (content_top_fraction
	# == top_fraction e width_margin_scale == 1.0 quando is_polished e
	# false, entao a formula abaixo fica byte-a-byte igual a de antes).
	var content_top_fraction: float = top_fraction
	var content_bottom_fraction: float = bottom_fraction
	var width_margin_scale: float = 1.0
	if is_polished:
		var usable_band: float = bottom_fraction - top_fraction
		var content_band: float = usable_band * POLISH_BOARD_FILL_FRACTION
		var band_margin: float = (usable_band - content_band) * 0.5
		content_top_fraction = top_fraction + band_margin
		content_bottom_fraction = bottom_fraction - band_margin
		width_margin_scale = 1.0 / POLISH_WIDTH_FILL_FRACTION

	var required_by_width: float = (float(state.board_cols) * CELL_SIZE + 2.7) / maxf(aspect, 0.35) * width_margin_scale
	# Tamanho minimo pra caber (area de embarque + tabuleiro + folga) exatamente
	# entre as duas fracoes de tela acima (ou dentro da faixa encolhida, no
	# PolishTest).
	var required_by_depth: float = absf(pitch_sin) * (bottom_z - top_z) / maxf(content_bottom_fraction - content_top_fraction, 0.01)
	camera.size = maxf(required_by_width, required_by_depth)

	# Ancora SEMPRE o topo da area de embarque (top_z) exatamente em
	# content_top_fraction, nunca centraliza pelo meio da tela: se "size"
	# acabou maior que o minimo (largura do tabuleiro mandou mais que
	# profundidade), a folga extra sobra embaixo -- nunca escondendo a area de
	# embarque atras do HUD de cima.
	camera.position = Vector3(center.x, center.y + camera_height, center.z)
	camera.position.z = top_z - (camera.size * (0.5 - content_top_fraction) + camera_height * pitch_cos) / pitch_sin
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.current = true
	_camera_base_size = camera.size
	_camera_base_position = camera.position

# --- Reacoes de camera (FASE D: game feel) ---
# Pequeno pulso de zoom-in ao confirmar um toque valido: reforca o feedback
# tatil sem mexer no enquadramento fixo usado pelo resto do jogo.
func _camera_pulse_valid_tap() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "size", _camera_base_size * 0.97, 0.06)
	tween.tween_property(camera, "size", _camera_base_size, 0.12)

# Pequeno "shake" horizontal ao tocar num veiculo bloqueado -- so a camera
# balanca; o tabuleiro e os veiculos continuam exatamente no lugar certo.
func _camera_shake_blocked() -> void:
	# O ramo de veiculo bloqueado nao usa is_animating (o jogador pode tocar
	# varias vezes seguidas rapido nele), entao um shake anterior ainda em
	# andamento e interrompido e a camera realinhada na base antes de comecar
	# o novo -- evita deriva acumulada de toques repetidos.
	if _camera_shake_tween != null and _camera_shake_tween.is_valid():
		_camera_shake_tween.kill()
	var base: Vector3 = _camera_base_position
	camera.position = base
	var tween := create_tween()
	_camera_shake_tween = tween
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "position", base + Vector3(0.18, 0.0, 0.0), 0.045)
	tween.tween_property(camera, "position", base + Vector3(-0.16, 0.0, 0.0), 0.045)
	tween.tween_property(camera, "position", base + Vector3(0.09, 0.0, 0.0), 0.045)
	tween.tween_property(camera, "position", base, 0.05)

# Pequeno zoom-out ao vencer a fase, pra "respirar" e mostrar o tabuleiro
# inteiro com o confete caindo antes do HUD de vitoria assumir a tela.
func _camera_zoom_out_for_win() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "size", _camera_base_size * 1.12, 0.5)

# --- Game Over (Fase F): reduz um pouco a saturacao da cena pra reforcar
# que a partida travou, sem escurecer a ponto de esconder o tabuleiro. A
# proxima fase (via restart) sempre reseta isso em _load_level_number().
func _apply_game_over_desaturation() -> void:
	var env: Environment = world_environment.environment
	if env == null:
		return
	env.adjustment_enabled = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(env, "adjustment_saturation", 0.42, 0.45)

func _reset_scene_saturation() -> void:
	var env: Environment = world_environment.environment
	if env == null:
		return
	env.adjustment_saturation = 1.0

func _clear_all_visuals() -> void:
	for root: Node3D in [vehicles_root, passengers_root, vfx_root]:
		for child: Node in root.get_children():
			child.free()
	vehicle_nodes.clear()
	_passenger_crowd.reset()

