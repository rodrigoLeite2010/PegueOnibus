class_name BoardingAreaController
extends Node3D

# ETAPA 7 (refatoracao segura, SEM mudanca visual/gameplay): extraido de
# GameController. O script e anexado DIRETO ao no "BoardingArea" ja existente
# na cena (ver scenes/game/Game.tscn) -- e por isso que todo metodo abaixo
# fala de si mesmo em vez de uma referencia externa "boarding_area.xxx": este
# SCRIPT agora E o BoardingArea. GameController guarda a mesma referencia de
# sempre (@onready var boarding_area: BoardingAreaController = $BoardingArea)
# e passa a chamar boarding_area.setup(...)/get_slot_marker(...)/etc. em vez
# de metodos privados proprios. O codigo interno de cada funcao e exatamente
# o mesmo de antes, so mudou de arquivo e (nos poucos metodos public API)
# perdeu o prefixo "_".
#
# Reune: criacao dos 4 docks ativos + 2 bloqueados, os Marker3D dos slots,
# SlotLabel/SlotPlus, aparencia dos docks, e a posicao de onde os passageiros
# "nascem" visualmente (PassengerQueueStart) em relacao aos docks. NAO reune
# a logica da fila de passageiros em si (zig-zag, avanco, reserva) -- isso
# fica em PassengerCrowdController (proxima extracao desta mesma etapa);
# nem o feedback de particula/popup de vaga liberada -- isso ja foi pra
# PolishEffectsController (100% efeito visual: tweens de pop/pulse +
# particula), nao estrutura/aparencia de vaga.
#
# GameEngine/GameState continuam sendo a UNICA fonte de verdade sobre quais
# vagas existem e quem esta estacionado onde -- este controller nunca
# duplica esse estado, so o representa visualmente a partir dos parametros
# que setup() recebe.

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
#   9.00 -- ver _setup_polish).
const ACTIVE_BOARDING_SLOTS := 4
const AD_LOCKED_SLOTS := 2
const TOTAL_VISUAL_SLOTS := ACTIVE_BOARDING_SLOTS + AD_LOCKED_SLOTS
const POLISH_SLOT_WIDTH := 1.45
const POLISH_SLOT_DEPTH := 2.40
const POLISH_LOCKED_SLOT_WIDTH := 0.75
const POLISH_SLOT_GAP := 0.28
const POLISH_SLOT_GAP_TO_BOARD := 0.15
# ETAPA 6B (item 9): passageiros e vagas mais proximos -- leitura imediata
# "PASSAGEIROS -> DOCKS -> ESTACIONAMENTO" como camadas conectadas, sem
# faixa vazia entre a fila e as vagas. POLISH_BOARDING_AREA_DEPTH (usada so
# pelo enquadramento de camera, em GameController) fica intocada.
const POLISH_GAP_PASSENGERS_TO_SLOTS := 0.12
# ETAPA 6B (item 1, PolishTest/fase 950 exclusivamente): UNICA fonte da
# orientacao final de um veiculo estacionado. Aplicada em cada Marker3D
# Slot0..Slot3 (ver _setup_polish) e repassada ao VehicleController (ver
# GameController._process_vehicle_tap ->
# VehicleController.drive_route_polished/snap_polish_parked_orientation).
# NUNCA calculada a partir de tangente da curva, direcao de entrada,
# exit_direction ou rotacao residual -- exatamente o que o ticket proibe.
const POLISH_PARKED_YAW_DEGREES := 180.0

# ETAPA 4 (item 9): tween de "bump" em andamento por Label3D -- ver
# set_slot_label_text_pop_bump(). Um onibus de 40 lugares dispara bumps mais
# rapido do que a duracao de cada bump, entao guardamos o tween atual pra
# poder matar o anterior antes de comecar um novo.
var _slot_label_pop_tweens: Dictionary = {}


# Chamado por GameController._load_level_number() logo depois de
# board.setup()/environment.setup(), no mesmo padrao de parametros. Faixa de
# embarque fisica: os slots continuam sendo definidos pela regra (GameEngine
# via waiting_slots_count), mas agora existe uma plataforma/rua visivel no
# mesmo mundo 3D.
func setup(waiting_slots_count: int, board_cols: int, cell_size: float, polish_mode: bool) -> void:
	for child: Node in get_children():
		child.free()

	# ETAPA 2C: a fase 950 usa uma geometria de vagas completamente separada
	# (tamanho real calculado a partir do small_car -- ver constantes
	# POLISH_SLOT_* acima), entao os dois caminhos foram divididos em duas
	# funcoes proprias em vez de dividir formulas com "* algo_scale" no meio
	# do caminho comum. Isso elimina qualquer risco de uma variavel
	# compartilhada acidentalmente mudar o resultado numerico de uma fase
	# normal: _setup_normal() abaixo e byte-a-byte a MESMA funcao de antes da
	# Etapa 2B/2C (nunca mais tocada desde entao, so movida de arquivo).
	if polish_mode:
		_setup_polish(waiting_slots_count, board_cols, cell_size)
	else:
		_setup_normal(waiting_slots_count, board_cols, cell_size)

# Consultado por GameController._build_route_to_waiting_slot() -- unica
# constante de layout que uma funcao FORA deste controller ainda precisa
# (o planejamento de rota do veiculo alinha a faixa de aproximacao ANTES da
# entrada da vaga, pra nunca cruzar lateralmente por cima do piso dela).
func get_slot_gap_to_board() -> float:
	return POLISH_SLOT_GAP_TO_BOARD

func get_slot_marker(slot_index: int) -> Marker3D:
	return get_node_or_null("Slot%d" % slot_index) as Marker3D

# Atualiza o Label3D "SlotLabel" (contador regressivo) de UMA vaga especifica.
# Texto vazio = vaga livre (sem numero flutuando a toa sobre o asfalto).
func set_slot_label_text(marker: Marker3D, text: String) -> void:
	if marker == null:
		return
	var label: Label3D = marker.get_node_or_null("SlotLabel") as Label3D
	if label != null:
		label.text = text
	var plus_label: Label3D = marker.get_node_or_null("SlotPlus") as Label3D
	if plus_label != null:
		plus_label.visible = text == ""
	# ETAPA 3B: icone de carrinho (so existia nas vagas da fase 950 antes da
	# Etapa 6B, item 7, remove-lo) some/aparece junto com o numero, pra
	# reforcar a leitura "carro estacionado aqui" sem duplicar nenhum Label3D.
	# get_node_or_null retorna null tanto nas vagas normais quanto agora nas
	# da PolishTest (o no nao existe mais), entao isto nunca muda nada.
	var icon_label: Label3D = marker.get_node_or_null("SlotVehicleIcon") as Label3D
	if icon_label != null:
		icon_label.visible = text != ""

# ETAPA 3 (Polish Test, fase 950 exclusivamente): mesmo texto/logica de
# set_slot_label_text() acima (nao duplica o Label3D, nao muda a logica de
# decremento 24->23 etc.), so acrescenta um POP de escala (0 -> 1.15 -> 1.0)
# no instante em que o contador aparece pela primeira vez ao carro estacionar.
# Chamada SOMENTE no ponto de estacionamento inicial em
# GameController._process_vehicle_tap; os decrementos por passageiro em
# _play_boarding_events continuam chamando set_slot_label_text() normal, sem
# pop.
func set_slot_label_text_pop(marker: Marker3D, text: String) -> void:
	set_slot_label_text(marker, text)
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
	# Icone do carrinho aparece com o mesmo pop, ja que os dois formavam o
	# mesmo bloco visual "carrinho / numero" antes da Etapa 6B remover o
	# icone (item 7); o get_node_or_null abaixo so retorna null agora.
	var icon_label: Label3D = marker.get_node_or_null("SlotVehicleIcon") as Label3D
	if icon_label != null:
		icon_label.scale = Vector3.ZERO
		var icon_tween := create_tween()
		icon_tween.set_trans(Tween.TRANS_BACK)
		icon_tween.set_ease(Tween.EASE_OUT)
		icon_tween.tween_property(icon_label, "scale", Vector3.ONE * 1.15, 0.10)
		icon_tween.tween_property(icon_label, "scale", Vector3.ONE, 0.08)

# ETAPA 4 (item 9): igual a set_slot_label_text_pop() acima, mas para os
# decrementos DEPOIS do primeiro (que ja aparece com o pop "de zero" acima)
# -- aqui o numero ja esta visivel, entao o pop e um pequeno "bump"
# (1.0 -> ~1.15 -> 1.0) em vez de crescer a partir do zero. Mesmo Label3D
# existente, nenhum contador novo.
func set_slot_label_text_pop_bump(marker: Marker3D, text: String) -> void:
	set_slot_label_text(marker, text)
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

func _setup_normal(waiting_slots_count: int, board_cols: int, cell_size: float) -> void:
	var count: int = mini(maxi(waiting_slots_count, 1), ACTIVE_BOARDING_SLOTS)
	var visual_count: int = TOTAL_VISUAL_SLOTS
	var board_width: float = float(board_cols) * cell_size
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
	add_child(queue_start)

	# Letreiros (Label3D com billboard, sempre de frente pra camera): dao
	# nome as duas areas e reforcam a leitura de "estacao profissional" em
	# vez de uma faixa generica. Puramente decorativos, sem Control/HUD.
	# A fila principal agora esta no HUD. Mantemos apenas um titulo discreto na area 3D.
	_add_boarding_label("BoardingAreaLabel", "EMBARQUE", Vector3(board_width * 0.5, 0.88, -0.58), 24)

	for index: int in range(count):
		var marker := Marker3D.new()
		marker.name = "Slot%d" % index
		marker.position = Vector3(first_x + spacing * float(index), 0.31, slot_z)
		add_child(marker)

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
		# real assim que um veiculo estaciona ali (ver GameController.
		# _process_vehicle_tap / _play_boarding_events / set_slot_label_text).
		# Fonte bem maior e contorno grosso pra ler de longe -- e ESTE numero
		# que representa a quantidade de passageiros que faltam pro carro,
		# direto em cima dele.
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
		add_child(marker)

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
# constantes POLISH_SLOT_* acima); as 2 bloqueadas ficam mais estreitas
# (nunca recebem carro) mas com a MESMA profundidade, pra alinhar na mesma
# faixa visual -- uma unica linha de 6 vagas "de verdade" (nao uma tira
# fina), com o piso por baixo, uma transicao curta ate o tabuleiro, e os
# Marker3D Slot0..Slot3 exatamente no centro geometrico de cada retangulo
# (o veiculo estacionado usa esse Marker3D direto como posicao final -- ver
# GameController._process_vehicle_tap).
func _setup_polish(waiting_slots_count: int, board_cols: int, cell_size: float) -> void:
	var count: int = mini(maxi(waiting_slots_count, 1), ACTIVE_BOARDING_SLOTS)
	var board_width: float = float(board_cols) * cell_size

	# Fronteiras Z explicitas (em vez de "spacing"/formulas herdadas): a
	# vaga fica logo acima do tabuleiro (borda proxima = -POLISH_SLOT_GAP_TO_BOARD),
	# com POLISH_SLOT_DEPTH de profundidade real.
	var slot_row_near_z: float = -POLISH_SLOT_GAP_TO_BOARD
	var slot_row_far_z: float = slot_row_near_z - POLISH_SLOT_DEPTH
	var slot_row_center_z: float = (slot_row_near_z + slot_row_far_z) * 0.5
	# Passageiros comecam logo depois da borda de tras das vagas (curta
	# transicao pedida no item 5); a fileira MAIS funda de passageiros
	# (ver POLISH_BOARDING_AREA_DEPTH em GameController) e o que define
	# quanto espaco a camera reserva no topo, entao nunca invade o HUD.
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
	add_child(queue_start)

	# "ESTACIONAMENTO" identifica o tabuleiro logo abaixo das vagas (pedido
	# no diagrama da Etapa 2C), nao mais "EMBARQUE" acima delas.
	_add_boarding_label("BoardingAreaLabel", "ESTACIONAMENTO", Vector3(board_width * 0.5, 0.70, 0.22), 20)

	for index: int in range(count):
		var marker := Marker3D.new()
		marker.name = "Slot%d" % index
		# O Marker3D fica exatamente no centro geometrico do retangulo
		# (Frame/Pad abaixo sao filhos dele em posicao local (0,*,0)) -- e
		# tambem o destino final do veiculo (ver GameController.
		# _process_vehicle_tap: vehicle_node.global_position =
		# final_marker.global_position), entao o carro estacionado SEMPRE cai
		# no centro visual da vaga.
		marker.position = Vector3(slot_centers_x[index], 0.31, slot_row_center_z)
		# ETAPA 6B (item 1): a orientacao final do veiculo estacionado vem
		# DAQUI, e so daqui -- ver POLISH_PARKED_YAW_DEGREES acima e
		# VehicleController.snap_polish_parked_orientation().
		marker.rotation_degrees.y = POLISH_PARKED_YAW_DEGREES
		add_child(marker)

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
		# set_slot_label_text acima).
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
		# get_node_or_null("SlotVehicleIcon") em set_slot_label_text() e
		# set_slot_label_text_pop() continuam ali por seguranca (retornam
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
		add_child(marker)

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
# esta funcao -- so _setup_polish() (fase 950).
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
	add_child(mesh_instance)

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
	add_child(label)
