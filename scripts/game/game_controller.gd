class_name GameController
extends Node3D

const CELL_SIZE := 1.0
const LEVEL_DIR := "res://levels"
const LEVEL_PATTERN := "level_%03d.json"
const HINT_COST := 15
# Os passageiros agora aparecem no proprio mundo 3D, perto das vagas, em vez
# de uma fila resumida no HUD. 40 cobre exatamente a maior capacidade oficial
# (onibus), entao um onibus de 40 lugares pode mostrar 40 pessoas reais
# aguardando e entrando uma a uma.
const MAX_VISIBLE_QUEUE_DOLLS := 40
const CROWD_COLUMNS := 8
const CROWD_COLUMN_SPACING := 0.52
const CROWD_ROW_SPACING := 0.58
# Quando um passageiro passa a ser visivel pela primeira vez (fila com mais
# gente do que MAX_VISIBLE_QUEUE_DOLLS de uma vez), ele nao aparece pronto na
# posicao final: nasce um pouco mais a direita da propria fileira e anda ate
# o lugar (ver _spawn_queue_doll_walking_in), reforcando a leitura de "entrando
# pela direita, andando ate a fila".
const CROWD_ENTRY_OFFSET_X := 1.35
const ACTIVE_BOARDING_SLOTS := 4
const AD_LOCKED_SLOTS := 2
const TOTAL_VISUAL_SLOTS := ACTIVE_BOARDING_SLOTS + AD_LOCKED_SLOTS

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
# e o ponto onde os passageiros nascem -- ver _setup_boarding_area) ANTES da
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

# --- ETAPA 2 do Polish Test (composicao visual) ---
# Tudo abaixo so entra em vigor quando state.level_id == POLISH_TEST_LEVEL_ID
# (a fase 950, carregada exclusivamente por scenes/game/PolishTest.tscn via
# scripts/game/polish_test_launcher.gd). Nenhuma fase normal passa por esse
# id, entao a aparencia de todas as outras fases fica exatamente igual a
# antes desta etapa -- ver os "if is_polish_test" em _setup_camera() e
# _spawn_vehicles().
const POLISH_TEST_LEVEL_ID := 950
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

# --- ETAPA 2C: vagas com tamanho real (calculado a partir do small_car) ---
# small_car na PolishTest (medido direto no GLB -- car_test.glb, bounding box
# nativo X=0.310/Z=0.438 -- e recalculado com VISUAL_SCALE_SMALL_CAR=4.0 e o
# multiplicador da Etapa 2B, 1.30, em cima de BOARD_VEHICLE_SCALE=0.86):
#   largura final = 0.310 * 4.0 * (0.86*1.30) = 1.386
#   comprimento final = 0.438 * 4.0 * (0.86*1.30) = 1.959
# A vaga ativa usa esses valores + margem (dentro dos 15-25% pedidos: 15% na
# largura pra sobrar espaco pras 6 vagas caberem numa linha so, 22% no
# comprimento -- era o eixo que estava "fita fina" no feedback):
#   largura = 1.386 * 1.15 =~ 1.60 | comprimento = 1.959 * 1.22 =~ 2.40
# As 2 vagas bloqueadas usam o MESMO comprimento (pra alinhar na mesma faixa
# visual) mas largura bem menor (nunca recebem carro de verdade, so o
# cadeado -- nao precisam do tamanho de um small_car).
# ETAPA 6B (itens 5-6): a Etapa 3B calculava estas 3 constantes pra caber
# "tudo numa linha so", com gap minimo de 0.12 -- exatamente o que fazia as
# 4 vagas ativas lerem como uma tira/plataforma unica no video de teste
# real. Aqui reduzimos largura (~9%) e largura-bloqueada (~25%, valor ainda
# perto do original) e mais que dobramos o gap, priorizando "4 vagas
# claramente separadas" sobre a compactacao original:
#   4*1.45 + 2*0.75 + 5*0.28 = 8.70 (cabe com folga na largura do tabuleiro,
#   9.00 -- ver _setup_boarding_area_polish).
const POLISH_SLOT_WIDTH := 1.45
const POLISH_SLOT_DEPTH := 2.40
const POLISH_LOCKED_SLOT_WIDTH := 0.75
const POLISH_SLOT_GAP := 0.28
const POLISH_SLOT_GAP_TO_BOARD := 0.15
# ETAPA 6B (item 9): passageiros e vagas mais proximos -- leitura imediata
# "PASSAGEIROS -> DOCKS -> ESTACIONAMENTO" como camadas conectadas, sem
# faixa vazia entre a fila e as vagas. POLISH_BOARDING_AREA_DEPTH (usada so
# pelo enquadramento de camera) fica intocada.
const POLISH_GAP_PASSENGERS_TO_SLOTS := 0.12
# ETAPA 6B (item 1, PolishTest/fase 950 exclusivamente): UNICA fonte da
# orientacao final de um veiculo estacionado. Aplicada em cada Marker3D
# Slot0..Slot3 (ver _setup_boarding_area_polish) e repassada ao
# VehicleController (ver _process_vehicle_tap ->
# VehicleController.drive_route_polished/snap_polish_parked_orientation).
# NUNCA calculada a partir de tangente da curva, direcao de entrada,
# exit_direction ou rotacao residual -- exatamente o que o ticket proibe.
const POLISH_PARKED_YAW_DEGREES := 180.0
# ETAPA 2B, item D (mantido/ajustado): fileiras em zigue-zague em vez da
# "matriz perfeita" relatada. ETAPA 2C aumenta as colunas de 7 para 8 (menos
# fileiras pra caber os mesmos 40 bonecos, ver POLISH_BOARDING_AREA_DEPTH)
# especificamente pra tirar o grupo de baixo do titulo "FASE 950".
const POLISH_CROWD_COLUMNS := 8
const POLISH_CROWD_COLUMN_SPACING := 0.58
const POLISH_CROWD_ROW_SPACING := 0.62
const POLISH_CROWD_ROW_STAGGER := 0.29

# ETAPA 4B: atraso entre o step_to() de um boneco da fila e o do proximo
# quando a fila reorganiza pra fechar um buraco (_advance_queue_dolls_polished)
# -- pedido explicito: "primeiro desloca / 0.02s / segundo / 0.02s / terceiro".
const POLISH_QUEUE_ADVANCE_STAGGER := 0.02
# Profundidade total (Z) reservada pela area de embarque da PolishTest, do
# limite Z=0 do tabuleiro ate a fileira MAIS de tras de passageiros possivel
# (pior caso: MAX_VISIBLE_QUEUE_DOLLS=40 bonecos, POLISH_CROWD_COLUMNS=8 ->
# ceil(40/8)=5 fileiras). Calculado, nao chutado, pra nunca mais deixar
# nenhuma fileira de passageiro cair por tras do proprio limite reservado
# (era exatamente o bug: a Etapa 2B usava a mesma BOARDING_AREA_DEPTH das
# fases normais, 3.05, mas com 40 bonecos as ultimas fileiras iam ate
# Z=-4.38 -- 1.33 alem do limite -- ou seja, apareciam ATRAS/dentro da faixa
# do HUD superior). So entra na formula da camera quando is_polish_test;
# BOARDING_AREA_DEPTH continua exatamente igual para toda fase normal.
const POLISH_BOARDING_AREA_DEPTH := 5.5

@onready var board: BoardController = $Board
@onready var environment: EnvironmentController = $GameEnvironment
@onready var vehicles_root: Node3D = $Vehicles
@onready var passengers_root: Node3D = $Passengers
@onready var vfx_root: Node3D = $VFX
@onready var boarding_area: Node3D = $BoardingArea
@onready var camera: Camera3D = $Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var hud: HUDController = $HUD

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
var _queue_dolls: Array[PassengerController] = []
var _queue_reveal_count: int = 0
# ETAPA 4 (Polish Test, fase 950 exclusivamente): vehicle_id -> quantos
# embarques em cascata (_run_cascaded_boarding) ainda estao rodando para
# aquele veiculo. Um veiculo so pode sair (drive_away_from_pickup) quando
# este numero chegar a 0 -- ver _play_boarding_events_polished, item 16 do
# pedido. Nunca usado/consultado fora da fase 950.
var _pending_polish_boardings: Dictionary = {}
# ETAPA 4: Label3D (SlotLabel) -> Tween ativo do micro "bump" do contador
# (_set_slot_label_text_pop_bump). Num onibus de 40 lugares o intervalo entre
# embarques (~0.07s) e menor que a duracao do proprio bump (~0.12s), entao
# sem isto dois tweens ficariam competindo sobre a mesma propriedade "scale"
# do mesmo Label3D (o mesmo tipo de bug ja documentado em PassengerController
# para bonecos concorrentes). So guarda no maximo 4 entradas (uma por slot
# ativo da fase 950), nunca cresce sem limite.
var _slot_label_pop_tweens: Dictionary = {}
var _camera_base_size: float = 14.0
var _camera_base_position: Vector3 = Vector3.ZERO
var _camera_shake_tween: Tween
# ETAPA 5 (Polish Test, fase 950 exclusivamente): saldo de moedas LOCAL e
# temporario desta sessao de teste (+10 por veiculo completado, itens 8-9 do
# pedido) -- NUNCA passa por Wallet.add_coins nem e persistido; reseta a
# cada _load_level_number(). Existe so para o feedback visual "+10" e o
# contador separado no HUD (ver _spawn_polish_coin_popup e
# HUDController.show_polish_test_coin_counter). Fora da fase 950 nunca e
# incrementado nem lido.
var _polish_local_coin_balance: int = 0
# ETAPA 5, item 1: um onibus de 40 lugares dispara ate 40 embarques em
# cascata numa janela curta -- tocar "passenger_board" a cada um deles
# soaria como ruido sobreposto. _play_polish_board_sfx_throttled() so deixa
# passar um som novo se ja passou esse intervalo minimo desde o ultimo
# (o feedback visual/particula continua em TODOS os embarques, so o som e
# limitado em frequencia). So usado no caminho da fase 950.
var _last_polish_board_sfx_ms: int = -1000000
const POLISH_BOARD_SFX_MIN_INTERVAL_MS := 45

func _ready() -> void:
	hud.restart_requested.connect(restart_level)
	hud.continue_requested.connect(_on_continue_requested)
	hud.hint_requested.connect(_on_hint_requested)
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
	var is_polish_test_level: bool = state.level_id == POLISH_TEST_LEVEL_ID
	if is_polish_test_level:
		_apply_polish_environment()
	else:
		_restore_default_environment()
	board.setup(state.board_rows, state.board_cols, CELL_SIZE, is_polish_test_level)
	environment.setup(state.board_rows, state.board_cols, CELL_SIZE, is_polish_test_level)
	_setup_boarding_area()
	_rebuild_queue_dolls()
	_spawn_vehicles()
	_refresh_selectable_highlights()
	_setup_camera()
	hud.update_state(state, "Toque em um veiculo livre.", _level_position_text(), -1)
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
	var is_polish_test: bool = state.level_id == POLISH_TEST_LEVEL_ID
	for vehicle_id: String in state.vehicles.keys():
		var vehicle: VehicleState = state.vehicles[vehicle_id]
		if vehicle.status != VehicleState.ON_BOARD:
			continue
		var vehicle_node := preload("res://scenes/game/Vehicle.tscn").instantiate() as VehicleController
		vehicles_root.add_child(vehicle_node)
		vehicle_node.setup_from_state(vehicle, CELL_SIZE, is_polish_test)
		if is_polish_test:
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
	# ETAPA 3 (Polish Test): so na fase 950, um veiculo em plena animacao
	# "polida" (feedback de bloqueio, dirigindo, estacionando/bounce) ignora
	# novos toques -- ver VehicleController.is_polish_busy(). Isolado por
	# is_polish_test pra nao mudar nada no comportamento das fases normais.
	var is_polish_test: bool = state.level_id == POLISH_TEST_LEVEL_ID
	if is_polish_test and vehicle_node.is_polish_busy():
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
		if is_polish_test:
			vehicle_node.animate_blocked_polished()
		else:
			vehicle_node.animate_blocked()
		_camera_shake_blocked()
		AudioManager.play_sfx("blocked")
		AudioManager.vibrate(45)
		hud.update_state(state, "Esse veiculo esta bloqueado.", _level_position_text())
		return
	if no_slot:
		vehicle_node.animate_no_slot()
		AudioManager.vibrate(35)
		hud.update_state(state, "As vagas de espera estao ocupadas.", _level_position_text())
		return

	_begin_tap_animation()
	if is_polish_test:
		vehicle_node.animate_valid_tap_polished()
		# ETAPA 5, item 3: particula discreta na base do veiculo ao confirmar
		# o toque -- so na fase 950.
		_spawn_tap_spark(vehicle_node.global_position)
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
	# ver POLISH_PARKED_YAW_DEGREES) pro VehicleController desde o comeco da
	# aproximacao -- em vez de ele calcular um heading a partir de
	# posicao/tangente da curva (fonte antiga, agora proibida pelo ticket).
	var final_marker: Marker3D = _boarding_slot_marker(slot_index)
	var slot_yaw_degrees: float = final_marker.global_rotation_degrees.y if final_marker != null else 0.0
	hud.show_message("Veiculo a caminho dos passageiros...")
	AudioManager.play_sfx("car_driving")
	if is_polish_test:
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
		if is_polish_test:
			vehicle_node.snap_polish_parked_orientation(slot_yaw_degrees)
		# Numero regressivo aparece no instante em que o carro encosta na vaga
		# (ainda ninguem embarcou -- os PassengerBoarded desta leva so tocam
		# durante _play_boarding_events logo abaixo, e cada um atualiza este
		# mesmo numero com o valor real do evento).
		var parked_vehicle: VehicleState = state.vehicles.get(vehicle_id) as VehicleState
		if parked_vehicle != null:
			var initial_count_text: String = str(maxi(parked_vehicle.capacity - parked_vehicle.occupied_seats, 0))
			if is_polish_test:
				_set_slot_label_text_pop(final_marker, initial_count_text)
				# ETAPA 3B: na fase 950 a escala "estacionada" (e a transicao ate
				# ela) ja foi aplicada dentro de drive_route_polished() (ver
				# VehicleController._drive_final_approach_polished) -- chamar
				# set_waiting_slot_mode(true) aqui por cima desfaria a transicao
				# suave com um snap pros fatores antigos (0.48/0.60/0.72).
				# ETAPA 4 (item 3): passageiros da cor certa reagem (micro pop)
				# antes do primeiro comecar a correr -- ver _play_boarding_events
				# logo abaixo, que so dispara a corrida em si.
				_react_queue_dolls_for_color(vehicle_node.color_id)
			else:
				_set_slot_label_text(final_marker, initial_count_text)
				vehicle_node.set_waiting_slot_mode(true)
	AudioManager.play_sfx("car_parking")
	AudioManager.vibrate(22)

	# Agora reproduzimos PassengerBoarded/SlotFreed na ordem dos eventos do motor.
	await _play_boarding_events(events, boarding_dolls)
	_sync_queue_dolls_to_state()

	if _has_event(events, "Win"):
		AudioManager.play_sfx("win")
		var coins_awarded: int = Wallet.award_win_bonus()
		hud.play_coin_reward(coins_awarded)
		_spawn_win_particles()
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
		if is_polish_test:
			_debug_dump_deadlock_state()

	_refresh_selectable_highlights()
	hud.update_state(state, _message_from_events(events), _level_position_text(), last_stars_earned)
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

func _boarding_slot_marker(slot_index: int) -> Marker3D:
	return boarding_area.get_node_or_null("Slot%d" % slot_index) as Marker3D

# Atualiza o Label3D "SlotLabel" (contador regressivo) de UMA vaga especifica.
# Texto vazio = vaga livre (sem numero flutuando a toa sobre o asfalto).
func _set_slot_label_text(marker: Marker3D, text: String) -> void:
	if marker == null:
		return
	var label: Label3D = marker.get_node_or_null("SlotLabel") as Label3D
	if label != null:
		label.text = text
	var plus_label: Label3D = marker.get_node_or_null("SlotPlus") as Label3D
	if plus_label != null:
		plus_label.visible = text == ""
	# ETAPA 3B: icone de carrinho (so existe nas vagas da fase 950 -- ver
	# _setup_boarding_area_polish) some/aparece junto com o numero, pra
	# reforcar a leitura "carro estacionado aqui" sem duplicar nenhum Label3D.
	# get_node_or_null retorna null nas vagas normais (nunca tem esse filho),
	# entao isto nunca muda nada fora da fase 950.
	var icon_label: Label3D = marker.get_node_or_null("SlotVehicleIcon") as Label3D
	if icon_label != null:
		icon_label.visible = text != ""

# ETAPA 3 (Polish Test, fase 950 exclusivamente): mesmo texto/logica de
# _set_slot_label_text() acima (nao duplica o Label3D, nao muda a logica de
# decremento 24->23 etc.), so acrescenta um POP de escala (0 -> 1.15 -> 1.0)
# no instante em que o contador aparece pela primeira vez ao carro estacionar.
# Chamada SOMENTE no ponto de estacionamento inicial em _process_vehicle_tap;
# os decrementos por passageiro em _play_boarding_events continuam chamando
# _set_slot_label_text() normal, sem pop.
func _set_slot_label_text_pop(marker: Marker3D, text: String) -> void:
	_set_slot_label_text(marker, text)
	if marker == null or text == "":
		return
	var label: Label3D = marker.get_node_or_null("SlotLabel") as Label3D
	if label == null:
		return
	label.scale = Vector3.ZERO
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE * 1.15, 0.10)
	tween.tween_property(label, "scale", Vector3.ONE, 0.08)
	# Icone do carrinho aparece com o mesmo pop, ja que os dois formam o
	# mesmo bloco visual "🚗 / numero" (item 7).
	var icon_label: Label3D = marker.get_node_or_null("SlotVehicleIcon") as Label3D
	if icon_label != null:
		icon_label.scale = Vector3.ZERO
		var icon_tween := create_tween()
		icon_tween.set_trans(Tween.TRANS_BACK)
		icon_tween.set_ease(Tween.EASE_OUT)
		icon_tween.tween_property(icon_label, "scale", Vector3.ONE * 1.15, 0.10)
		icon_tween.tween_property(icon_label, "scale", Vector3.ONE, 0.08)

func _event_slot_index(events: Array, vehicle_id: String) -> int:
	for item: Variant in events:
		var event: GameEvent = item as GameEvent
		if event != null and event.type == "VehicleParked" and String(event.payload.get("vehicle_id", "")) == vehicle_id:
			return int(event.payload.get("slot_index", 0))
	return 0

func _setup_boarding_area() -> void:
	# Faixa de embarque fisica: os slots continuam sendo definidos pela regra,
	# mas agora existe uma plataforma/rua visivel no mesmo mundo 3D. Isso tira
	# a sensacao de "carros flutuando acima do tabuleiro" e prepara o caminho
	# para passageiros correndo ate as portas.
	for child: Node in boarding_area.get_children():
		child.free()

	# ETAPA 2C: a fase 950 usa uma geometria de vagas completamente separada
	# (tamanho real calculado a partir do small_car -- ver constantes
	# POLISH_SLOT_* acima), entao os dois caminhos foram divididos em duas
	# funcoes proprias em vez de dividir formulas com "* algo_scale" no meio
	# do caminho comum. Isso elimina qualquer risco de uma variavel
	# compartilhada acidentalmente mudar o resultado numerico de uma fase
	# normal: _setup_boarding_area_normal() abaixo e byte-a-byte a MESMA
	# funcao de antes da Etapa 2B/2C (nunca mais tocada desde entao).
	if state.level_id == POLISH_TEST_LEVEL_ID:
		_setup_boarding_area_polish()
	else:
		_setup_boarding_area_normal()

func _setup_boarding_area_normal() -> void:
	var count: int = mini(maxi(state.waiting_slots.size(), 1), ACTIVE_BOARDING_SLOTS)
	var visual_count: int = TOTAL_VISUAL_SLOTS
	var board_width: float = float(state.board_cols) * CELL_SIZE
	var spacing: float = minf(1.34, (board_width - 0.55) / float(visual_count))
	var total_span: float = spacing * float(visual_count - 1)
	var first_x: float = board_width * 0.5 - total_span * 0.5
	var slot_z: float = -0.48

	# Plataforma clara e pista de acesso escura, ambas apenas visuais.
	_add_boarding_box(
		"Platform",
		Vector3(board_width + 0.65, 0.06, 1.26),
		Vector3(board_width * 0.5, 0.01, -0.50),
		Color("#ded3ba")
	)
	_add_boarding_box(
		"AccessLane",
		Vector3(board_width + 0.65, 0.035, 0.38),
		Vector3(board_width * 0.5, 0.035, -0.94),
		Color("#5b6b86")
	)

	# Faixa tracejada dourada no centro da pista (mesma cor de destaque usada
	# nas saidas do tabuleiro), em vez de uma linha branca solida.
	var lane_segment_count := 5
	var lane_span := board_width * 0.78
	for lane_index: int in range(lane_segment_count):
		var lane_t: float = (float(lane_index) - float(lane_segment_count - 1) * 0.5) / float(lane_segment_count)
		_add_boarding_box(
			"LaneLine%d" % lane_index,
			Vector3(lane_span / float(lane_segment_count) * 0.55, 0.018, 0.045),
			Vector3(board_width * 0.5 + lane_span * lane_t, 0.06, -0.94),
			Color("#ffd233")
		)

	# Ponto onde os passageiros "nascem" visualmente antes de caminhar.
	var queue_start := Marker3D.new()
	queue_start.name = "PassengerQueueStart"
	queue_start.position = Vector3(board_width * 0.5, 0.20, -1.28)
	boarding_area.add_child(queue_start)

	# Letreiros (Label3D com billboard, sempre de frente pra camera): dao
	# nome as duas areas e reforcam a leitura de "estacao profissional" em
	# vez de uma faixa generica. Puramente decorativos, sem Control/HUD.
	# A fila principal agora esta no HUD. Mantemos apenas um titulo discreto na area 3D.
	_add_boarding_label("BoardingAreaLabel", "EMBARQUE", Vector3(board_width * 0.5, 0.88, -0.58), 24)

	for index: int in range(count):
		var marker := Marker3D.new()
		marker.name = "Slot%d" % index
		marker.position = Vector3(first_x + spacing * float(index), 0.31, slot_z)
		boarding_area.add_child(marker)

		# Moldura sob o piso claro (mesma tecnica de _add_floor/_add_floor_shadow
		# do BoardController: uma caixa mais larga e um pouco mais baixa, com
		# uma folga pequena entre as duas pra nao dar z-fighting). A largura
		# some com base em "spacing" pra nunca invadir a vaga vizinha mesmo em
		# fases com slots mais apertados.
		var frame_width: float = minf(1.34, spacing * 0.94)
		var frame := MeshInstance3D.new()
		frame.name = "Frame"
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3(frame_width, 0.02, 1.02)
		frame.mesh = frame_mesh
		frame.position = Vector3(0.0, -0.32, 0.0)
		var frame_material := StandardMaterial3D.new()
		frame_material.albedo_color = Color("#7d8aa0")
		frame_material.roughness = 0.85
		frame.material_override = frame_material
		marker.add_child(frame)

		# Base maior e mais legivel, com linha clara na frente e separadores.
		var pad := MeshInstance3D.new()
		pad.name = "Pad"
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(minf(1.16, frame_width - 0.08), 0.026, 0.92)
		pad.mesh = pad_mesh
		pad.position = Vector3(0.0, -0.285, 0.0)
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color("#41516b")
		pad_material.roughness = 0.9
		pad.material_override = pad_material
		marker.add_child(pad)

		var stop_line := MeshInstance3D.new()
		var stop_mesh := BoxMesh.new()
		stop_mesh.size = Vector3(0.88, 0.018, 0.035)
		stop_line.mesh = stop_mesh
		stop_line.position = Vector3(0.0, -0.258, -0.30)
		var stop_material := StandardMaterial3D.new()
		stop_material.albedo_color = Color("#87f7aa")
		stop_line.material_override = stop_material
		marker.add_child(stop_line)

		# Numero da vaga, alto o suficiente pra continuar visivel mesmo com um
		# onibus estacionado ali (collider_height do onibus e 1.1). Sempre de
		# frente pra camera -- e a resposta direta ao pedido de "vagas fisicas,
		# nao so quadrados de HUD": agora cada vaga tem identidade propria no
		# mundo 3D, alem do card que ja existia no HUD.
		# Comeca vazio (vaga livre = sem numero); vira o contador regressivo
		# real assim que um veiculo estaciona ali (ver _process_vehicle_tap /
		# _play_boarding_events / _set_slot_label_text). Fonte bem maior e
		# contorno grosso pra ler de longe -- e ESTE numero que representa a
		# quantidade de passageiros que faltam pro carro, direto em cima dele.
		var slot_label := Label3D.new()
		slot_label.name = "SlotLabel"
		slot_label.text = ""
		slot_label.font_size = 46
		slot_label.outline_size = 14
		slot_label.modulate = Color.WHITE
		slot_label.outline_modulate = Color(0.12, 0.15, 0.2, 0.9)
		slot_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot_label.no_depth_test = true
		slot_label.position = Vector3(0.0, 0.62, 0.46)
		marker.add_child(slot_label)

		# Sinal de vaga livre, inspirado no layout de referencia. Some quando um
		# veiculo estaciona e volta quando a vaga e liberada.
		var slot_plus := Label3D.new()
		slot_plus.name = "SlotPlus"
		slot_plus.text = "+"
		slot_plus.font_size = 44
		slot_plus.outline_size = 10
		slot_plus.modulate = Color("#63ef91")
		slot_plus.outline_modulate = Color(0.08, 0.16, 0.12, 0.85)
		slot_plus.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot_plus.no_depth_test = true
		slot_plus.position = Vector3(0.0, 0.42, 0.02)
		marker.add_child(slot_plus)

	# Duas vagas extras aparecem bloqueadas para futuro desbloqueio por anuncio.
	# Elas NAO entram em GameState.waiting_slots e portanto nunca podem receber
	# um veiculo agora. Sao apenas a previsao visual do recurso futuro.
	for locked_index: int in range(AD_LOCKED_SLOTS):
		var visual_index: int = count + locked_index
		var marker := Marker3D.new()
		marker.name = "AdLockedSlot%d" % locked_index
		marker.position = Vector3(first_x + spacing * float(visual_index), 0.31, slot_z)
		boarding_area.add_child(marker)

		var frame := MeshInstance3D.new()
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3(minf(1.24, spacing * 0.92), 0.02, 1.02)
		frame.mesh = frame_mesh
		frame.position = Vector3(0.0, -0.32, 0.0)
		var frame_material := StandardMaterial3D.new()
		frame_material.albedo_color = Color("#596273")
		frame_material.roughness = 0.9
		frame.material_override = frame_material
		marker.add_child(frame)

		var pad := MeshInstance3D.new()
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(minf(1.08, spacing * 0.82), 0.026, 0.92)
		pad.mesh = pad_mesh
		pad.position = Vector3(0.0, -0.285, 0.0)
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color("#313846")
		pad_material.roughness = 0.92
		pad.material_override = pad_material
		marker.add_child(pad)

		var lock_label := Label3D.new()
		lock_label.text = "🔒"
		lock_label.font_size = 36
		lock_label.outline_size = 8
		lock_label.modulate = Color("#d7dbe3")
		lock_label.outline_modulate = Color(0.08, 0.10, 0.14, 0.9)
		lock_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lock_label.no_depth_test = true
		lock_label.position = Vector3(0.0, 0.42, 0.02)
		marker.add_child(lock_label)

		var ad_label := Label3D.new()
		ad_label.text = "ANUNCIO"
		ad_label.font_size = 16
		ad_label.outline_size = 5
		ad_label.modulate = Color("#aeb7c7")
		ad_label.outline_modulate = Color(0.08, 0.10, 0.14, 0.9)
		ad_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ad_label.no_depth_test = true
		ad_label.position = Vector3(0.0, 0.36, 0.36)
		marker.add_child(ad_label)

# ETAPA 2C: layout de vagas dedicado da PolishTest (fase 950). As 4 vagas
# ativas usam o tamanho REAL calculado a partir do small_car (ver as
# constantes POLISH_SLOT_* logo acima de POLISH_TEST_LEVEL_ID); as 2
# bloqueadas ficam mais estreitas (nunca recebem carro) mas com a MESMA
# profundidade, pra alinhar na mesma faixa visual -- uma unica linha de 6
# vagas "de verdade" (nao uma tira fina), com o piso por baixo, uma transicao
# curta ate o tabuleiro, e os Marker3D Slot0..Slot3 exatamente no centro
# geometrico de cada retangulo (o veiculo estacionado usa esse Marker3D
# direto como posicao final -- ver _process_vehicle_tap).
func _setup_boarding_area_polish() -> void:
	var count: int = mini(maxi(state.waiting_slots.size(), 1), ACTIVE_BOARDING_SLOTS)
	var board_width: float = float(state.board_cols) * CELL_SIZE

	# Fronteiras Z explicitas (em vez de "spacing"/formulas herdadas): a
	# vaga fica logo acima do tabuleiro (borda proxima = -POLISH_SLOT_GAP_TO_BOARD),
	# com POLISH_SLOT_DEPTH de profundidade real.
	var slot_row_near_z: float = -POLISH_SLOT_GAP_TO_BOARD
	var slot_row_far_z: float = slot_row_near_z - POLISH_SLOT_DEPTH
	var slot_row_center_z: float = (slot_row_near_z + slot_row_far_z) * 0.5
	# Passageiros comecam logo depois da borda de tras das vagas (curta
	# transicao pedida no item 5); a fileira MAIS funda de passageiros
	# (ver POLISH_BOARDING_AREA_DEPTH acima) e o que define quanto espaco a
	# camera reserva no topo, entao nunca invade o HUD.
	var queue_front_z: float = slot_row_far_z - POLISH_GAP_PASSENGERS_TO_SLOTS

	# Larguras de cada uma das 6 vagas visuais, na ordem em que aparecem da
	# esquerda pra direita: as 4 ativas usam POLISH_SLOT_WIDTH (tamanho real
	# do small_car + margem), as 2 bloqueadas usam POLISH_LOCKED_SLOT_WIDTH
	# (mais estreita -- nunca estacionam um carro de verdade).
	var slot_widths: Array[float] = []
	for _i: int in range(ACTIVE_BOARDING_SLOTS):
		slot_widths.append(POLISH_SLOT_WIDTH)
	for _i: int in range(AD_LOCKED_SLOTS):
		slot_widths.append(POLISH_LOCKED_SLOT_WIDTH)

	var total_row_width: float = 0.0
	for w: float in slot_widths:
		total_row_width += w
	total_row_width += POLISH_SLOT_GAP * float(slot_widths.size() - 1)

	# Centro X de cada vaga, andando da esquerda pra direita a partir da
	# borda esquerda do bloco inteiro (que fica centralizado no tabuleiro).
	var slot_centers_x: Array[float] = []
	var cursor_x: float = board_width * 0.5 - total_row_width * 0.5
	for w: float in slot_widths:
		slot_centers_x.append(cursor_x + w * 0.5)
		cursor_x += w + POLISH_SLOT_GAP

	# ETAPA 6B (item 5): a plataforma unica que cobria a fileira inteira das
	# vagas foi REMOVIDA de proposito. Era ela quem fazia as 4 vagas ativas
	# lerem como uma unica tira/plataforma branca no video de teste real,
	# por cima do Frame/Pad de cada vaga (cada uma ja tem cor propria -- ver
	# PolishPalette.SLOT_SURFACE azul-acinzentado + PolishPalette.BORDER
	# off-white, mais _add_slot_shadow por vaga). Sem piso comum por baixo
	# unificando o bloco, e com o gap aumentado (POLISH_SLOT_GAP), cada vaga
	# volta a ser reconhecivel individualmente.
	# Pista de acesso escura, uma faixa curta ligando o fim das vagas ao
	# tabuleiro (mesma leitura visual da versao normal, so que bem mais
	# curta -- essa era a "faixa vazia" que o pedido quer reduzida).
	var lane_near_z: float = 0.05
	var lane_far_z: float = slot_row_near_z - 0.05
	_add_boarding_box(
		"AccessLane",
		Vector3(total_row_width + 0.60, 0.035, maxf(lane_near_z - lane_far_z, 0.05)),
		Vector3(board_width * 0.5, 0.035, (lane_near_z + lane_far_z) * 0.5),
		Color("#5b6b86")
	)

	# Ponto onde os passageiros "nascem" visualmente, agora logo acima das
	# vagas (curta transicao) em vez de flutuando bem mais pra tras.
	var queue_start := Marker3D.new()
	queue_start.name = "PassengerQueueStart"
	queue_start.position = Vector3(board_width * 0.5, 0.20, queue_front_z)
	boarding_area.add_child(queue_start)

	# "ESTACIONAMENTO" identifica o tabuleiro logo abaixo das vagas (pedido
	# no diagrama da Etapa 2C), nao mais "EMBARQUE" acima delas.
	_add_boarding_label("BoardingAreaLabel", "ESTACIONAMENTO", Vector3(board_width * 0.5, 0.70, 0.22), 20)

	for index: int in range(count):
		var marker := Marker3D.new()
		marker.name = "Slot%d" % index
		# O Marker3D fica exatamente no centro geometrico do retangulo
		# (Frame/Pad abaixo sao filhos dele em posicao local (0,*,0)) -- e
		# tambem o destino final do veiculo (ver _process_vehicle_tap:
		# vehicle_node.global_position = final_marker.global_position),
		# entao o carro estacionado SEMPRE cai no centro visual da vaga.
		marker.position = Vector3(slot_centers_x[index], 0.31, slot_row_center_z)
		# ETAPA 6B (item 1): a orientacao final do veiculo estacionado vem
		# DAQUI, e so daqui -- ver POLISH_PARKED_YAW_DEGREES acima e
		# VehicleController.snap_polish_parked_orientation().
		marker.rotation_degrees.y = POLISH_PARKED_YAW_DEGREES
		boarding_area.add_child(marker)

		# ETAPA 3B (item 5): mais contraste pra vaga ficar claramente visivel --
		# borda quase branca (era um cinza-azulado medio, quase se perdia no
		# piso ao redor) e piso mais escuro/saturado que o entorno.
		var frame_width: float = POLISH_SLOT_WIDTH
		var frame := MeshInstance3D.new()
		frame.name = "Frame"
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3(frame_width, 0.02, POLISH_SLOT_DEPTH)
		frame.mesh = frame_mesh
		frame.position = Vector3(0.0, -0.32, 0.0)
		var frame_material := StandardMaterial3D.new()
		frame_material.albedo_color = PolishPalette.BORDER
		frame_material.roughness = 0.7
		frame.material_override = frame_material
		marker.add_child(frame)

		var pad := MeshInstance3D.new()
		pad.name = "Pad"
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(frame_width - 0.12, 0.026, POLISH_SLOT_DEPTH - 0.16)
		pad.mesh = pad_mesh
		pad.position = Vector3(0.0, -0.285, 0.0)
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = PolishPalette.SLOT_SURFACE
		pad_material.roughness = 0.92
		pad.material_override = pad_material
		marker.add_child(pad)
		_add_slot_shadow(marker, frame_width)
		_add_slot_corner_caps(marker, frame_width, POLISH_SLOT_DEPTH)

		var stop_line := MeshInstance3D.new()
		var stop_mesh := BoxMesh.new()
		stop_mesh.size = Vector3(frame_width - 0.24, 0.018, 0.035)
		stop_line.mesh = stop_mesh
		stop_line.position = Vector3(0.0, -0.258, POLISH_SLOT_DEPTH * -0.32)
		var stop_material := StandardMaterial3D.new()
		stop_material.albedo_color = Color("#87f7aa")
		stop_line.material_override = stop_material
		marker.add_child(stop_line)

		# ETAPA 3B (item 7): com o veiculo estacionado agora visualmente maior
		# (escala "parked" da Etapa 3B fica bem mais perto da escala de
		# tabuleiro do que os fatores antigos de set_waiting_slot_mode), o
		# contador em y=0.95 acabava atras do teto do carro -- subiu pra 1.55
		# (ainda relativo ao Marker3D, que fica no chao da vaga). ETAPA 6B
		# (item 7): o icone de carrinho em emoji que ficava logo acima foi
		# removido -- o proprio modelo 3D do veiculo ja comunica isso; o
		# contador some/aparece sozinho junto com a vaga (ver
		# _set_slot_label_text).
		var slot_label := Label3D.new()
		slot_label.name = "SlotLabel"
		slot_label.text = ""
		slot_label.font_size = 64
		slot_label.outline_size = 16
		slot_label.modulate = Color.WHITE
		slot_label.outline_modulate = Color(0.12, 0.15, 0.2, 0.9)
		slot_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot_label.no_depth_test = true
		slot_label.position = Vector3(0.0, 1.55, 0.0)
		marker.add_child(slot_label)

		# ETAPA 6B (item 7): icone de carrinho em emoji REMOVIDO -- o proprio
		# modelo 3D do veiculo estacionado ja comunica "e um carro" sem
		# precisar de um Label3D emoji flutuando por cima. Os
		# get_node_or_null("SlotVehicleIcon") em _set_slot_label_text() e
		# _set_slot_label_text_pop() continuam ali por seguranca (retornam
		# null agora, os "if != null" nunca mais executam -- zero efeito).

		# "+" grande e centralizado (item 2) quando a vaga esta livre.
		var slot_plus := Label3D.new()
		slot_plus.name = "SlotPlus"
		slot_plus.text = "+"
		slot_plus.font_size = 60
		slot_plus.outline_size = 12
		slot_plus.modulate = Color("#63ef91")
		slot_plus.outline_modulate = Color(0.08, 0.16, 0.12, 0.85)
		slot_plus.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot_plus.no_depth_test = true
		slot_plus.position = Vector3(0.0, 0.60, 0.0)
		marker.add_child(slot_plus)

	# Duas vagas bloqueadas: mesma profundidade (alinham na mesma faixa
	# visual), largura bem menor (nunca recebem carro de verdade) -- ETAPA 6B
	# (item 8) tambem as deixa mais estreitas que as vagas ativas de
	# proposito, pra nunca competirem visualmente com elas. Cadeado grande e
	# centralizado; "EM BREVE" pequeno abaixo, so decorativo.
	for locked_index: int in range(AD_LOCKED_SLOTS):
		var visual_index: int = count + locked_index
		var marker := Marker3D.new()
		marker.name = "AdLockedSlot%d" % locked_index
		marker.position = Vector3(slot_centers_x[visual_index], 0.31, slot_row_center_z)
		boarding_area.add_child(marker)

		# ETAPA 3B (item 5): borda mais escura/dessaturada que a das vagas
		# ativas (agora quase branca) -- reforca a leitura "desabilitada" por
		# contraste em vez de so pela cor do piso.
		var frame := MeshInstance3D.new()
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3(POLISH_LOCKED_SLOT_WIDTH, 0.02, POLISH_SLOT_DEPTH)
		frame.mesh = frame_mesh
		frame.position = Vector3(0.0, -0.32, 0.0)
		var frame_material := StandardMaterial3D.new()
		frame_material.albedo_color = PolishPalette.SLOT_SURFACE_LOCKED.darkened(0.1)
		frame_material.roughness = 0.95
		frame.material_override = frame_material
		marker.add_child(frame)

		var pad := MeshInstance3D.new()
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(POLISH_LOCKED_SLOT_WIDTH - 0.12, 0.026, POLISH_SLOT_DEPTH - 0.16)
		pad.mesh = pad_mesh
		pad.position = Vector3(0.0, -0.285, 0.0)
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = PolishPalette.SLOT_SURFACE_LOCKED.darkened(0.3)
		pad_material.roughness = 0.92
		pad.material_override = pad_material
		marker.add_child(pad)
		_add_slot_shadow(marker, POLISH_LOCKED_SLOT_WIDTH)

		_add_procedural_padlock(marker, Vector3(0.0, 0.62, 0.0))

		# ETAPA 6B (item 8): "ANUNCIO" -> "EM BREVE" -- deixa explicito que a
		# vaga e um espaco futuro (nao um anuncio publicitario generico),
		# reforcando junto com o cadeado e o contraste reduzido que estas 2
		# vagas sao secundarias, nunca competindo com as 4 vagas ativas.
		var ad_label := Label3D.new()
		ad_label.text = "EM BREVE"
		ad_label.font_size = 15
		ad_label.outline_size = 5
		ad_label.modulate = Color("#aeb7c7")
		ad_label.outline_modulate = Color(0.08, 0.10, 0.14, 0.9)
		ad_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ad_label.no_depth_test = true
		ad_label.position = Vector3(0.0, 0.20, 0.0)
		marker.add_child(ad_label)

# ETAPA 6 (item 7, vagas ativas: "pequena sombra"): sombra achatada sob a
# vaga inteira -- reforca a leitura de vaga individual sem custar mais que
# uma mesh estatica extra por vaga (4 no total, custo desprezivel).
func _add_slot_shadow(marker: Marker3D, width: float) -> void:
	var shadow := MeshInstance3D.new()
	var shadow_mesh := BoxMesh.new()
	shadow_mesh.size = Vector3(width + 0.10, 0.01, POLISH_SLOT_DEPTH + 0.10)
	shadow.mesh = shadow_mesh
	shadow.position = Vector3(0.0, -0.335, 0.02)
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.22)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shadow_material
	marker.add_child(shadow)

# ETAPA 6 (item 7: "cantos visualmente arredondados se possivel"): 4
# cilindros baixos nos cantos da vaga, mesma tecnica ja usada no tabuleiro
# (BoardController._add_rounded_corners) -- 100% procedural, custo minimo.
func _add_slot_corner_caps(marker: Marker3D, width: float, depth: float) -> void:
	var cap_color: Color = PolishPalette.BORDER
	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half_w, -0.31, -half_d),
		Vector3(half_w, -0.31, -half_d),
		Vector3(-half_w, -0.31, half_d),
		Vector3(half_w, -0.31, half_d),
	]
	for corner: Vector3 in corners:
		var cap := MeshInstance3D.new()
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.05
		cap_mesh.bottom_radius = 0.05
		cap_mesh.height = 0.021
		cap_mesh.radial_segments = 10
		cap.mesh = cap_mesh
		cap.position = corner
		var cap_material := StandardMaterial3D.new()
		cap_material.albedo_color = cap_color
		cap_material.roughness = 0.7
		cap.material_override = cap_material
		marker.add_child(cap)

# ETAPA 6 (item 7, vagas bloqueadas: "cadeado grande" -- "Nao usar icone
# emoji se houver alternativa simples usando Label/SVG/primitive
# existente"): cadeado 100% procedural (TorusMesh + BoxMesh + SphereMesh),
# substitui o antigo Label3D com o emoji "lock". Nenhuma fase normal chama
# esta funcao -- so _setup_boarding_area_polish() (fase 950).
func _add_procedural_padlock(marker: Marker3D, base_position: Vector3) -> void:
	var body_color := Color("#c7cdda")
	var shackle_color := Color("#9aa2b5")

	var shackle := MeshInstance3D.new()
	var shackle_mesh := TorusMesh.new()
	shackle_mesh.inner_radius = 0.05
	shackle_mesh.outer_radius = 0.10
	shackle.mesh = shackle_mesh
	shackle.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	shackle.position = base_position + Vector3(0.0, 0.13, 0.0)
	var shackle_material := StandardMaterial3D.new()
	shackle_material.albedo_color = shackle_color
	shackle_material.metallic = 0.3
	shackle_material.roughness = 0.4
	shackle.material_override = shackle_material
	marker.add_child(shackle)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.24, 0.20, 0.10)
	body.mesh = body_mesh
	body.position = base_position
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = body_color
	body_material.roughness = 0.55
	body.material_override = body_material
	marker.add_child(body)

	var keyhole := MeshInstance3D.new()
	var keyhole_mesh := SphereMesh.new()
	keyhole_mesh.radius = 0.028
	keyhole_mesh.height = 0.056
	keyhole.mesh = keyhole_mesh
	keyhole.position = base_position + Vector3(0.0, 0.0, 0.052)
	var keyhole_material := StandardMaterial3D.new()
	keyhole_material.albedo_color = Color(0.08, 0.10, 0.14)
	keyhole_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	keyhole.material_override = keyhole_material
	marker.add_child(keyhole)

func _add_boarding_box(name_text: String, box_size: Vector3, box_position: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name_text
	var box := BoxMesh.new()
	box.size = box_size
	mesh_instance.mesh = box
	mesh_instance.position = box_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	mesh_instance.material_override = material
	boarding_area.add_child(mesh_instance)

# Letreiro simples da area de embarque (Label3D com billboard), reaproveitado
# tanto para o titulo "PASSAGEIROS" quanto para "ESTACAO DE EMBARQUE". Sem
# acento nas strings porque a fonte padrao do projeto ja e usada assim em
# outros textos gerados por script (ver HUDController).
func _add_boarding_label(name_text: String, label_text: String, label_position: Vector3, size: int) -> void:
	var label := Label3D.new()
	label.name = name_text
	label.text = label_text
	label.font_size = size
	label.outline_size = size - 16
	label.modulate = Color("#2b3550")
	label.outline_modulate = Color(1.0, 1.0, 1.0, 0.92)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = label_position
	boarding_area.add_child(label)

func _boarding_slot_position(slot_index: int) -> Vector3:
	var marker: Marker3D = _boarding_slot_marker(slot_index)
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
	# tabuleiro (ver POLISH_SLOT_GAP_TO_BOARD/_setup_boarding_area_polish), e
	# o -0.78 generico acima ja fica DENTRO da vaga (que comeca em
	# -POLISH_SLOT_GAP_TO_BOARD = -0.15) -- o veiculo cruzava lateralmente por
	# cima do piso da vaga antes de virar pra entrar, em vez de alinhar ANTES
	# dela. Aqui o alinhamento em X passa a acontecer exatamente na entrada da
	# vaga; o trecho final ate o centro (ApproachPoint->SlotCenter, ver
	# VehicleController.drive_route_polished/_drive_final_approach_polished)
	# cobre a profundidade real da vaga de forma reta e explicita.
	if state.level_id == POLISH_TEST_LEVEL_ID:
		lane_z = -POLISH_SLOT_GAP_TO_BOARD
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
	if state.level_id == POLISH_TEST_LEVEL_ID:
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
			_spawn_boarding_spark(target_vehicle.get_boarding_point(), color_id)
			# Contador regressivo no proprio carro: sempre o numero real do
			# evento (capacity - occupied_seats), nunca reconsultado depois --
			# assim continua certo mesmo com varios veiculos animando juntos.
			var remaining: int = maxi(int(event.payload.get("capacity", 0)) - int(event.payload.get("occupied_seats", 0)), 0)
			var boarding_marker: Marker3D = _vehicle_slot_markers.get(boarded_vehicle_id) as Marker3D
			if boarding_marker != null:
				_set_slot_label_text(boarding_marker, str(remaining))
		elif event.type == "SlotFreed":
			var completed_vehicle_id: String = String(event.payload.get("vehicle_id", ""))
			var completed_node: VehicleController = vehicle_nodes.get(completed_vehicle_id) as VehicleController
			var freed_marker: Marker3D = _vehicle_slot_markers.get(completed_vehicle_id) as Marker3D
			if freed_marker != null:
				_set_slot_label_text(freed_marker, "")
			_vehicle_slot_markers.erase(completed_vehicle_id)
			if completed_node != null:
				AudioManager.play_sfx("vehicle_complete")
				AudioManager.vibrate(30)
				_spawn_vehicle_complete_burst(completed_node.global_position, completed_node.color_id)
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
	# verdade (ver comentario completo em _advance_queue_dolls_polished e em
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
			# proprio de _advance_queue_dolls_polished).
			if not queue_advance_started:
				queue_advance_started = true
				_advance_queue_dolls_polished()
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
				_set_slot_label_text(freed_marker, "")
				# ETAPA 5, item 7: "+" some com pop, piso/borda pulsa e uma
				# particula verde curta marca "esta vaga acabou de abrir".
				_play_slot_freed_feedback_polished(freed_marker)
			_vehicle_slot_markers.erase(completed_vehicle_id)
			_pending_polish_boardings.erase(completed_vehicle_id)
			if completed_node != null:
				AudioManager.play_sfx("vehicle_complete")
				AudioManager.vibrate(30)
				_spawn_vehicle_complete_burst(completed_node.global_position, completed_node.color_id)
				# ETAPA 5, itens 8-9: recompensa visual "+10" por veiculo
				# completado, EXCLUSIVA da PolishTest -- saldo local, nunca
				# Wallet/save real (ver _polish_local_coin_balance).
				_polish_local_coin_balance += 10
				_spawn_polish_coin_popup(completed_node.global_position)
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
		_play_polish_board_sfx_throttled()
		if is_instance_valid(target_vehicle):
			_spawn_boarding_spark(target_vehicle.get_boarding_point(), color_id)
		if boarding_marker != null:
			_set_slot_label_text_pop_bump(boarding_marker, str(remaining))
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

# Item 3 do pedido: reage (micro pop) nos primeiros bonecos visiveis da fila
# cuja cor bate com a do veiculo que acabou de estacionar -- so cosmetico,
# nunca mexe em _queue_dolls nem em quem vai realmente embarcar (isso
# continua 100% decidido por _reserve_boarding_dolls/eventos do GameEngine).
# Limitado a poucos bonecos de proposito (o pedido permite nao aplicar aos
# 40 de uma vez, por performance).
func _react_queue_dolls_for_color(color_id: String) -> void:
	var reacted := 0
	for doll: PassengerController in _queue_dolls:
		if reacted >= 10:
			break
		if is_instance_valid(doll) and doll.color_id == color_id:
			doll.polish_color_react()
			reacted += 1

# ETAPA 4 (item 9): igual a _set_slot_label_text_pop() da Etapa 3B, mas para
# os decrementos DEPOIS do primeiro (que ja aparece com o pop "de zero"
# daquela etapa) -- aqui o numero ja esta visivel, entao o pop e um pequeno
# "bump" (1.0 -> ~1.15 -> 1.0) em vez de crescer a partir do zero. Mesmo
# Label3D existente, nenhum contador novo.
func _set_slot_label_text_pop_bump(marker: Marker3D, text: String) -> void:
	_set_slot_label_text(marker, text)
	if marker == null or text == "":
		return
	var label: Label3D = marker.get_node_or_null("SlotLabel") as Label3D
	if label == null:
		return
	# Um onibus de 40 lugares dispara bumps mais rapido do que a duracao de
	# cada bump (ver comentario de _slot_label_pop_tweens) -- mata o anterior
	# e reseta a escala antes de comecar um novo, pra nunca competir sobre a
	# mesma propriedade.
	var previous_tween: Tween = _slot_label_pop_tweens.get(label) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	label.scale = Vector3.ONE
	# ETAPA 5, item 5: flash rapido de cor (branco -> verde claro -> branco,
	# ~0.10s no total) junto com o bump de escala existente -- reforca so
	# visualmente que o contador baixou; nao muda nenhum valor logico.
	label.modulate = Color.WHITE
	var tween := create_tween()
	_slot_label_pop_tweens[label] = tween
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE * 1.15, 0.06)
	tween.parallel().tween_property(label, "modulate", Color("#c8ffb8"), 0.05)
	tween.tween_property(label, "scale", Vector3.ONE, 0.06)
	tween.parallel().tween_property(label, "modulate", Color.WHITE, 0.05)

# Chamada SINCRONA, no instante do toque (antes de qualquer await em
# _process_vehicle_tap) -- reserva, na ordem certa, um boneco 3D real da
# fila para cada evento "PassengerBoarded" desta leva, e ja tira esses
# bonecos de _queue_dolls. Isso e o que garante a identidade certa mesmo com
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
			reserved.append(_pop_front_queue_doll(color_id))
			popped_any = true
	# ETAPA 4B: na fase 950 a reorganizacao VISUAL da fila (bonecos restantes
	# deslizando pra fechar o buraco) fica pra depois -- ver
	# _play_boarding_events_polished/_advance_queue_dolls_polished, chamada so
	# quando o primeiro passageiro desta leva ja tiver claramente comecado a
	# sair. Antes disso o embarque nem comecou visualmente (o veiculo ainda
	# vai dirigir ate a vaga), entao reorganizar aqui (na hora do toque, como
	# a fase normal sempre fez) dava a impressao de "a fila inteira mudou antes
	# de alguem sair". O pop/reserva em si (_pop_front_queue_doll acima)
	# continua exatamente aqui, sincrono -- e o que garante a identidade certa
	# com toques concorrentes, isso nunca muda.
	if popped_any and state.level_id != POLISH_TEST_LEVEL_ID:
		_advance_queue_dolls()
	return reserved

# --- Passageiros 3D esperando perto das vagas ---
# Em vez de resumir a fila no topo da HUD, mostramos pessoas reais no mundo.
# A ordem visual continua sendo a mesma ordem logica de state.passenger_queue.
# Ate 40 ficam visiveis de uma vez, exatamente a capacidade maxima oficial.

func _queue_slot_position(slot_index: int) -> Vector3:
	var queue_marker: Marker3D = boarding_area.get_node_or_null("PassengerQueueStart") as Marker3D
	var base_local: Vector3
	if queue_marker != null:
		base_local = passengers_root.to_local(queue_marker.global_position)
	else:
		base_local = Vector3(float(state.board_cols) * CELL_SIZE * 0.5, 0.20, -1.28)

	# Grade compacta centralizada: 10 pessoas por linha, ate 4 linhas para um
	# onibus de 40 lugares. A primeira linha fica mais perto dos carros.
	# ETAPA 2B, item D: so a fase 950 usa fileiras em zigue-zague (linhas
	# alternadas deslocadas por meio espacamento) em vez da grade perfeita
	# ("planilha") relatada, com colunas/espacamento levemente maiores -- toda
	# fase normal cai exatamente nas mesmas CROWD_COLUMNS/CROWD_COLUMN_SPACING/
	# CROWD_ROW_SPACING de sempre, com stagger_offset sempre 0.0.
	var is_polish_test: bool = state.level_id == POLISH_TEST_LEVEL_ID
	var columns_per_row: int = POLISH_CROWD_COLUMNS if is_polish_test else CROWD_COLUMNS
	var column_spacing: float = POLISH_CROWD_COLUMN_SPACING if is_polish_test else CROWD_COLUMN_SPACING
	var row_spacing: float = POLISH_CROWD_ROW_SPACING if is_polish_test else CROWD_ROW_SPACING

	var column: int = slot_index % columns_per_row
	var row: int = slot_index / columns_per_row
	var row_count: int = mini(columns_per_row, MAX_VISIBLE_QUEUE_DOLLS - row * columns_per_row)
	var row_width: float = float(maxi(row_count - 1, 0)) * column_spacing
	var stagger_offset: float = 0.0
	if is_polish_test and row % 2 == 1:
		stagger_offset = POLISH_CROWD_ROW_STAGGER * column_spacing
	var x_offset: float = float(column) * column_spacing - row_width * 0.5 + stagger_offset
	var z_offset: float = -float(row) * row_spacing
	return base_local + Vector3(x_offset, 0.0, z_offset)

func _rebuild_queue_dolls() -> void:
	for doll: PassengerController in _queue_dolls:
		if is_instance_valid(doll):
			doll.free()
	_queue_dolls.clear()
	_queue_reveal_count = mini(state.passenger_queue.size(), MAX_VISIBLE_QUEUE_DOLLS)
	for index: int in range(_queue_reveal_count):
		_queue_dolls.append(_spawn_queue_doll(index, state.passenger_queue[index]))

func _spawn_queue_doll(spawn_index: int, color_id: String) -> PassengerController:
	var doll := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	passengers_root.add_child(doll)
	doll.setup(color_id, state.level_id == POLISH_TEST_LEVEL_ID)
	doll.position = _queue_slot_position(_queue_dolls.size())
	return doll

# Mesma coisa que _spawn_queue_doll, mas para quando um boneco passa a ser
# visivel DEPOIS que a fase ja comecou (ver _sync_queue_dolls_to_state): em
# vez de aparecer pronto na posicao final, nasce mais a direita (fora da
# propria fileira) e anda ate o lugar com a mesma animacao de passo usada na
# fila avancando -- e a entrada "vindo andando da direita" pedida.
func _spawn_queue_doll_walking_in(slot_index: int, color_id: String) -> PassengerController:
	var doll := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	passengers_root.add_child(doll)
	doll.setup(color_id, state.level_id == POLISH_TEST_LEVEL_ID)
	var target: Vector3 = _queue_slot_position(slot_index)
	doll.position = target + Vector3(CROWD_ENTRY_OFFSET_X, 0.0, 0.0)
	doll.step_to(target)
	return doll

func _pop_front_queue_doll(color_id: String) -> PassengerController:
	if not _queue_dolls.is_empty():
		return _queue_dolls.pop_front()
	var fallback := preload("res://scenes/game/Passenger.tscn").instantiate() as PassengerController
	passengers_root.add_child(fallback)
	fallback.setup(color_id, state.level_id == POLISH_TEST_LEVEL_ID)
	fallback.position = _queue_slot_position(0)
	return fallback

func _advance_queue_dolls() -> void:
	# Cada passageiro restante avanca para a proxima posicao livre da grade.
	for index: int in range(_queue_dolls.size()):
		var doll: PassengerController = _queue_dolls[index]
		if is_instance_valid(doll):
			doll.step_to(_queue_slot_position(index))


# ETAPA 4B ("REORGANIZACAO DA FILA"): variante da funcao acima, exclusiva da
# fase 950 -- em vez de mandar TODOS os step_to() no mesmo instante (o que
# lia como um bloco inteiro reagindo junto), cada boneco restante recebe um
# pequeno atraso (POLISH_QUEUE_ADVANCE_STAGGER) em relacao ao anterior antes
# do seu proprio step_to() disparar -- step_to() ja anima cada um em 0.26s
# (dentro dos "0.20-0.28s" pedidos), entao o resultado e um efeito de onda
# sem sobreposicao. NAO precisa terminar de percorrer os 40 bonecos de uma
# vez: e fire-and-forget (chamada sem "await" -- ver _play_boarding_events_
# polished), entao o resto do jogo nunca fica bloqueado esperando a fila
# terminar de reorganizar visualmente.
func _advance_queue_dolls_polished() -> void:
	var count: int = _queue_dolls.size()
	for index: int in range(count):
		var doll: PassengerController = _queue_dolls[index] if index < _queue_dolls.size() else null
		if is_instance_valid(doll):
			doll.step_to(_queue_slot_position(index))
		if index < count - 1:
			await get_tree().create_timer(POLISH_QUEUE_ADVANCE_STAGGER).timeout


# Ressincroniza a fila visual com a fila LOGICA atual. Roda depois de cada
# leva de embarque. NAO destroi mais todos os bonecos toda vez (isso fazia a
# fila inteira "piscar"/teleportar de novo a cada carro que terminava,
# inclusive durante toques concorrentes que ainda estavam com bonecos no meio
# do caminho): so ajusta a DIFERENCA. Quem ja esta na tela e continua
# correspondendo a fila logica (a ordem e sempre preservada por
# _reserve_boarding_dolls/_advance_queue_dolls, que ja tiram e reordenam os
# bonecos certos no instante do toque) fica exatamente onde esta; so entra
# gente nova quando a fila logica tem mais passageiros do que os bonecos
# atuais mostram (fases com mais de MAX_VISIBLE_QUEUE_DOLLS passageiros no
# total) -- e so esses bonecos novos "andam" ate o lugar vindo de fora da
# fileira, pela direita (ver _spawn_queue_doll_walking_in).
func _sync_queue_dolls_to_state() -> void:
	var target_count: int = mini(state.passenger_queue.size(), MAX_VISIBLE_QUEUE_DOLLS)
	while _queue_dolls.size() > target_count:
		var extra: PassengerController = _queue_dolls.pop_back()
		if is_instance_valid(extra):
			extra.free()
	while _queue_dolls.size() < target_count:
		var slot_index: int = _queue_dolls.size()
		_queue_dolls.append(_spawn_queue_doll_walking_in(slot_index, state.passenger_queue[slot_index]))
	_queue_reveal_count = _queue_dolls.size()

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
func _spawn_boarding_spark(spawn_position: Vector3, color_id: String) -> void:
	var color: Color = VehicleController.COLOR_MAP.get(color_id, Color.WHITE)
	for i: int in range(8):
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.045, 0.045, 0.045)
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.15, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		piece.material_override = material
		vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.6, 1.2), randf_range(-1.0, 1.0))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.55, 0.28)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.28)
		tween.tween_callback(piece.queue_free)

# ETAPA 5, item 3 (PolishTest exclusivamente): particula discreta na base do
# veiculo ao confirmar um toque valido -- poucos elementos (6), sobe pouco e
# some rapido (~0.22s), reforca o toque sem competir com o proprio "pop" do
# carro (animate_valid_tap_polished, que e so escala).
func _spawn_tap_spark(spawn_position: Vector3) -> void:
	for i: int in range(6):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.035
		mesh.height = 0.035
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.05, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = material
		vfx_root.add_child(piece)
		var angle: float = (TAU / 6.0) * float(i)
		var direction := Vector3(cos(angle), 0.5, sin(angle))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.30, 0.22)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.22)
		tween.tween_callback(piece.queue_free)

# ETAPA 5, item 1 (PolishTest exclusivamente): ver comentario da variavel
# _last_polish_board_sfx_ms/POLISH_BOARD_SFX_MIN_INTERVAL_MS acima -- limita
# a FREQUENCIA do som de embarque durante a cascata (nunca o efeito visual),
# pra um onibus de 40 lugares nao soar como 40 sons colados.
func _play_polish_board_sfx_throttled() -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_polish_board_sfx_ms < POLISH_BOARD_SFX_MIN_INTERVAL_MS:
		return
	_last_polish_board_sfx_ms = now_ms
	AudioManager.play_sfx("passenger_board")

# ETAPA 5, item 7 (PolishTest exclusivamente): feedback rapido (~0.3s) no
# instante em que uma vaga fica livre -- o "+" aparece com pop (em vez de
# so trocar "visible" instantaneo), o piso da vaga pulsa (clareia e volta) e
# uma pequena particula verde sobe e some. Ensina visualmente "uma vaga
# acabou de abrir". Reaproveita os nos "SlotPlus"/"Pad" ja criados em
# _setup_boarding_area_polish(); nao cria nenhum no novo na vaga.
func _play_slot_freed_feedback_polished(marker: Marker3D) -> void:
	var plus_label: Label3D = marker.get_node_or_null("SlotPlus") as Label3D
	if plus_label != null:
		plus_label.scale = Vector3.ZERO
		var pop_tween := create_tween()
		pop_tween.set_trans(Tween.TRANS_BACK)
		pop_tween.set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(plus_label, "scale", Vector3.ONE * 1.2, 0.14)
		pop_tween.tween_property(plus_label, "scale", Vector3.ONE, 0.10)
	var pad: MeshInstance3D = marker.get_node_or_null("Pad") as MeshInstance3D
	if pad != null:
		var pad_material: StandardMaterial3D = pad.material_override as StandardMaterial3D
		if pad_material != null:
			var base_color: Color = pad_material.albedo_color
			var pulse_tween := create_tween()
			pulse_tween.tween_property(pad_material, "albedo_color", Color("#3f8f5c"), 0.10)
			pulse_tween.tween_property(pad_material, "albedo_color", base_color, 0.18)
	_spawn_slot_freed_spark(marker.global_position)

func _spawn_slot_freed_spark(spawn_position: Vector3) -> void:
	for i: int in range(6):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.04
		mesh.height = 0.04
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.05, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#63ef91")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = material
		vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-0.6, 0.6), randf_range(0.8, 1.3), randf_range(-0.6, 0.6))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.4, 0.3)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.3)
		tween.tween_callback(piece.queue_free)

# ETAPA 5, itens 8-9 (PolishTest exclusivamente): "+10" que aparece com pop,
# sobe levemente e desaparece (~0.75s), perto do veiculo/vaga que acabou de
# completar. Nunca toca em Wallet -- ver _polish_local_coin_balance.
func _spawn_polish_coin_popup(spawn_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = "+10"
	label.font_size = 48
	label.outline_size = 12
	label.modulate = Color("#ffd233")
	label.outline_modulate = Color(0.35, 0.22, 0.0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = spawn_position + Vector3(0.0, 0.9, 0.0)
	vfx_root.add_child(label)
	label.scale = Vector3.ZERO
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE, 0.12)
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector3(0.0, 0.55, 0.0), 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.40)
	tween.chain().tween_callback(label.queue_free)

func _spawn_win_particles() -> void:
	AudioManager.vibrate(90)
	var center: Vector3 = board.get_board_center()
	for i: int in range(30):
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.09, 0.035, 0.15)
		piece.mesh = mesh
		piece.position = center + Vector3(randf_range(-1.4, 1.4), 1.1, randf_range(-0.9, 0.9))
		piece.rotation_degrees = Vector3(randf_range(0.0, 180.0), randf_range(0.0, 180.0), randf_range(0.0, 180.0))
		var material := StandardMaterial3D.new()
		material.albedo_color = [Color("#ff4b4b"), Color("#35de45"), Color("#ffd236"), Color("#2f91ff"), Color("#ff43c8"), Color("#ff7b20")][i % 6]
		piece.material_override = material
		vfx_root.add_child(piece)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + Vector3(randf_range(-2.4, 2.4), randf_range(1.4, 2.6), randf_range(-2.4, 2.4)), 0.45)
		tween.tween_property(piece, "position:y", 0.1, 0.5)
		tween.tween_callback(piece.queue_free)

func _spawn_vehicle_complete_burst(spawn_position: Vector3, color_id: String) -> void:
	var color: Color = VehicleController.COLOR_MAP.get(color_id, Color.WHITE)
	for i: int in range(14):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.05
		mesh.height = 0.05
		piece.mesh = mesh
		piece.position = spawn_position + Vector3(0.0, 0.2, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = material
		vfx_root.add_child(piece)
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.7, 1.4), randf_range(-1.0, 1.0))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "position", piece.position + direction * 0.75, 0.34)
		tween.parallel().tween_property(piece, "scale", Vector3.ZERO, 0.34)
		tween.tween_callback(piece.queue_free)

func _setup_camera() -> void:
	var center: Vector3 = board.get_board_center()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# So a fase 950 (PolishTest) usa pitch/altura diferentes -- toda fase
	# normal cai no "else" com os mesmos CAMERA_PITCH_DEGREES/CAMERA_HEIGHT de
	# sempre, entao o resultado numerico pras fases normais e IDENTICO ao de
	# antes desta etapa (ver POLISH_TEST_LEVEL_ID acima).
	var is_polish_test: bool = state.level_id == POLISH_TEST_LEVEL_ID
	var pitch_degrees: float = POLISH_CAMERA_PITCH_DEGREES if is_polish_test else CAMERA_PITCH_DEGREES
	var camera_height: float = POLISH_CAMERA_HEIGHT if is_polish_test else CAMERA_HEIGHT
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
	var boarding_area_depth: float = POLISH_BOARDING_AREA_DEPTH if is_polish_test else BOARDING_AREA_DEPTH
	var top_z: float = -boarding_area_depth
	var bottom_z: float = float(state.board_rows) * CELL_SIZE + BOARD_EDGE_MARGIN

	var top_fraction: float = HUD_TOP_UNSAFE_FRACTION + CAMERA_FRAME_SAFETY_FRACTION
	var bottom_fraction: float = 1.0 - HUD_BOTTOM_UNSAFE_FRACTION - CAMERA_FRAME_SAFETY_FRACTION

	# PolishTest: em vez de esticar o conteudo pra preencher a faixa util
	# INTEIRA (100%, o comportamento padrao de sempre, mantido abaixo para
	# toda fase normal), encolhe a faixa-alvo para POLISH_BOARD_FILL_FRACTION
	# dela, centralizada -- e o "respiro"/composicao de diorama pedido, sem
	# mudar em nada o calculo usado pelas fases normais (content_top_fraction
	# == top_fraction e width_margin_scale == 1.0 quando is_polish_test e
	# false, entao a formula abaixo fica byte-a-byte igual a de antes).
	var content_top_fraction: float = top_fraction
	var content_bottom_fraction: float = bottom_fraction
	var width_margin_scale: float = 1.0
	if is_polish_test:
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
	_queue_dolls.clear()

