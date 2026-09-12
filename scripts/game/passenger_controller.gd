class_name PassengerController
extends Node3D

@export var color_id: String = "red"

const COLOR_MAP := {
	"red": Color("#ff4b4b"),
	"blue": Color("#2f91ff"),
	"green": Color("#35de45"),
	"yellow": Color("#ffd236"),
	"purple": Color("#9349ff"),
	"pink": Color("#ff43c8"),
	"orange": Color("#ff7b20"),
}

# ETAPA 4 (Polish Test, fase 950 exclusivamente): quando true, _build() liga o
# idle procedural "polido" (start_polish_idle(), amplitude/fase variadas) em
# vez do bounce padrao compartilhado abaixo; e o unico uso desta flag. Toda
# fase normal chama setup(color_id) sem o segundo argumento, entao continua
# exatamente no bounce padrao de sempre.
var is_polish: bool = false

# ETAPA 6 (item 8): fator de escala exclusivo da PolishTest -- ver uso em
# _build() e pop_in().
const POLISH_SCALE := 1.12

var _body_root: Node3D
var _leg_pivots: Array[Node3D] = []
var _arm_pivots: Array[Node3D] = []
var _idle_tween: Tween
var _walk_tween: Tween
# Tween ATIVO que move `position` (fila avancando via step_to() OU o
# embarque completo de walk_to_and_board()). Varios veiculos podem estar
# animando ao mesmo tempo (toques concorrentes), entao o MESMO boneco pode
# receber um novo comando de movimento antes do anterior terminar (ex.: a
# fila avanca de novo enquanto ele ainda desliza para a posicao antiga, ou
# ele e reservado para embarcar enquanto ainda tem um step_to() pendente).
# Sem cancelar o tween antigo, os dois competem sobre a mesma propriedade
# `position` e o boneco fica "preso" entre os dois destinos -- exatamente o
# bug relatado de passageiros sobrepondo. _kill_move() garante que so o
# tween mais recente continua vivo.
var _move_tween: Tween

func _ready() -> void:
	_build()

func setup(p_color_id: String, p_is_polish: bool = false) -> void:
	color_id = p_color_id
	is_polish = p_is_polish
	_build()

# Velocidade dobrada em relacao ao original (0.57s -> 0.285s do total ate
# sumir dentro do carro). Uma rodada seguinte tentou dobrar de novo (~0.15s)
# mas ficou rapido demais e foi revertida a pedido -- fica neste ponto. O
# ciclo de passada acompanha a mesma proporcao (ver _start_walk_cycle).
func walk_to_and_board(target: Vector3) -> void:
	# Apresentacao apenas: a regra/assentos ja foram confirmados pelo GameEngine.
	# O boneco agora percorre uma rota curta em 3 trechos, vira para a direcao
	# do movimento, balanca bracos/pernas e faz um "hop" final para dentro.
	# _kill_move() primeiro: com toques concorrentes este boneco pode ter sido
	# reservado (tirado da fila) enquanto AINDA tinha um step_to() da fila em
	# andamento -- sem cancelar aquele tween antigo, ele continuaria puxando o
	# boneco de volta para a posicao de fila ao mesmo tempo que este tween tenta
	# leva-lo ate a porta do veiculo, fazendo-o parecer preso/sobrepondo a fila.
	_kill_move()
	var start: Vector3 = position
	var approach: Vector3 = target + Vector3(0.0, 0.0, 0.34)
	var middle: Vector3 = start.lerp(approach, 0.58)
	middle.y += 0.025

	_face_towards(middle)
	_start_walk_cycle(0.0425)

	var tween := create_tween()
	_move_tween = tween
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", middle, 0.045)
	tween.tween_property(self, "position", approach, 0.035)
	await tween.finished

	_face_towards(target)
	var hop := create_tween()
	_move_tween = hop
	hop.set_trans(Tween.TRANS_QUAD)
	hop.set_ease(Tween.EASE_OUT)
	hop.parallel().tween_property(self, "position", target + Vector3(0.0, 0.19, 0.0), 0.025)
	hop.parallel().tween_property(self, "scale", Vector3(0.78, 0.78, 0.78), 0.025)
	await hop.finished

	var enter := create_tween()
	_move_tween = enter
	enter.set_trans(Tween.TRANS_BACK)
	enter.set_ease(Tween.EASE_IN)
	enter.parallel().tween_property(self, "position", target + Vector3(0.0, 0.10, -0.05), 0.025)
	enter.parallel().tween_property(self, "scale", Vector3(0.06, 0.06, 0.06), 0.025)
	await enter.finished
	_stop_walk_cycle()
	_kill_idle()
	_move_tween = null
	queue_free()

# ETAPA 4 (Polish Test, fase 950 exclusivamente): variante "polida" de
# walk_to_and_board(), usada SOMENTE quando GameController detecta
# state.level_id == POLISH_TEST_LEVEL_ID (ver GameController.
# _run_cascaded_boarding). Mais lenta/vistosa que a versao rapida acima
# (duracao ~0.35-0.65s dependendo da distancia, vs os ~0.13s fixos dela):
# trajetoria com arco (Bezier quadratico amostrado por tween_method, sem
# Curve3D novo), bounce vertical de corrida e leve inclinacao pra frente
# durante o trajeto, e nos ultimos ~20% um encolhimento em duas etapas
# (1.0->0.65->0) em vez do "hop + escala direto pra quase-zero" da versao
# rapida. O destino final continua sendo exatamente "target" (o
# BoardingPoint real do veiculo, ver VehicleController.get_boarding_point).
func walk_to_and_board_polished(target: Vector3) -> void:
	_kill_move()
	_kill_idle()

	# ETAPA 4B (itens 1 e 2 do pedido "PASSAGEIRO QUE ESTA CORRENDO"): antes
	# de correr de verdade, um pequeno pop de escala + um passo curto pra fora
	# do grupo. Sem isto o boneco saia direto da posicao da fila reto rumo ao
	# veiculo, o que -- somado a reorganizacao da fila -- dava a impressao de
	# "teleportou e a fila inteira mudou". So DEPOIS deste passo o boneco conta
	# como "claramente saindo" (ver PassengerCrowdController.advance_dolls_polished,
	# que so reorganiza a fila apos o primeiro _run_cascaded_boarding() desta
	# leva passar por este ponto).
	var pop_start: Vector3 = position
	var away_direction: Vector3 = pop_start - target
	away_direction.y = 0.0
	if away_direction.length() < 0.001:
		away_direction = Vector3(0.0, 0.0, 1.0)
	else:
		away_direction = away_direction.normalized()
	var pop_target: Vector3 = pop_start + away_direction * 0.10 + Vector3(0.0, 0.02, 0.0)
	_face_towards(target)
	var pop_tween := create_tween()
	_move_tween = pop_tween
	pop_tween.set_trans(Tween.TRANS_BACK)
	pop_tween.set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(self, "scale", Vector3.ONE * 1.12, 0.045)
	pop_tween.parallel().tween_property(self, "position", pop_target, 0.05)
	pop_tween.tween_property(self, "scale", Vector3.ONE, 0.035)
	await pop_tween.finished

	var start: Vector3 = position
	var distance: float = start.distance_to(target)
	var total_duration: float = clampf(distance * 0.9, 0.35, 0.65)
	var enter_duration: float = clampf(total_duration * 0.22, 0.10, 0.16)
	var run_duration: float = maxf(total_duration - enter_duration, 0.08)

	# Ponto de controle elevado/lateral no meio do trajeto (item 6: "pequeno
	# arco", nao uma linha reta no chao -- ETAPA 4B aumentou levemente o arco
	# vertical E acrescentou uma variacao lateral por passageiro, pra cada um
	# ficar visualmente distinguivel do seguinte em vez de todos seguirem
	# exatamente a mesma curva). Sem Curve3D dedicado -- um Bezier quadratico
	# amostrado a cada passo do tween_method e suficiente e mais barato para
	# uma corrida curta como esta (item 14: performance).
	var control: Vector3 = start.lerp(target, 0.5)
	control.y += clampf(distance * 0.19, 0.06, 0.16)
	var lateral_dir: Vector3 = Vector3(-(target.z - start.z), 0.0, target.x - start.x)
	if lateral_dir.length() > 0.001:
		control += lateral_dir.normalized() * randf_range(-0.14, 0.14)
	var run_target: Vector3 = start.lerp(target, 0.80)

	_face_towards(control)
	# Passada mais lenta que a versao rapida (0.0425s por quarto de passada),
	# coerente com a corrida mais vistosa pedida aqui.
	_start_walk_cycle(0.11)
	var bounce_cycles: float = clampf(run_duration * 6.0, 2.0, 6.0)

	var run_tween := create_tween()
	_move_tween = run_tween
	run_tween.set_trans(Tween.TRANS_SINE)
	run_tween.set_ease(Tween.EASE_IN_OUT)
	run_tween.tween_method(_apply_bezier_run_progress.bind(start, control, run_target, bounce_cycles), 0.0, 1.0, run_duration)
	await run_tween.finished

	_stop_walk_cycle()
	if _body_root != null:
		_body_root.rotation_degrees.x = 0.0
	_face_towards(target)

	# Item 8: nos ultimos ~20% do trajeto o passageiro nao some instantaneo --
	# aproxima do BoardingPoint enquanto encolhe em duas etapas (1.0->0.65,
	# depois 0.65->0) antes de ser liberado.
	var enter := create_tween()
	_move_tween = enter
	enter.set_trans(Tween.TRANS_SINE)
	enter.set_ease(Tween.EASE_IN)
	enter.tween_property(self, "position", target, enter_duration * 0.45)
	enter.parallel().tween_property(self, "scale", Vector3.ONE * 0.65, enter_duration * 0.45)
	enter.tween_property(self, "scale", Vector3.ZERO, enter_duration * 0.55)
	await enter.finished
	_move_tween = null
	queue_free()

# Amostra um ponto do Bezier quadratico start->control->run_target no
# progresso "t" (0..1) e aplica: (a) a posicao resultante, com um bounce
# vertical rapido somado por cima (item 7: "sensacao de passos", barato --
# so um seno, sem Curve3D nem _process por frame); (b) o giro instantaneo
# pra tangente do trajeto (igual ao resto do jogo faz em curvas de veiculo);
# (c) uma leve inclinacao pra frente em _body_root (item 7, opcional),
# sempre voltando a 0 no final da corrida (ver walk_to_and_board_polished).
func _apply_bezier_run_progress(t: float, p0: Vector3, control: Vector3, p2: Vector3, bounce_cycles: float) -> void:
	if not is_instance_valid(self):
		return
	var a: Vector3 = p0.lerp(control, t)
	var b: Vector3 = control.lerp(p2, t)
	var base_position: Vector3 = a.lerp(b, t)
	var bounce: float = absf(sin(t * PI * bounce_cycles)) * 0.05
	position = base_position + Vector3(0.0, bounce, 0.0)

	var tangent: Vector3 = b - a
	if Vector2(tangent.x, tangent.z).length() > 0.001:
		rotation.y = atan2(tangent.x, tangent.z)
	if _body_root != null:
		_body_root.rotation_degrees.x = -4.5

# ETAPA 4 (item 3): micro "pop" de escala nos passageiros da COR CORRETA no
# instante em que o veiculo delas estaciona, antes do primeiro comecar a
# correr -- comunica "e a vez dessas pessoas". Anima so _body_root (nunca
# `scale`/`position` do no raiz, que step_to()/walk_to_and_board_polished()
# usam), entao nunca compete com o resto do movimento do boneco. Chamada
# so pelos primeiros visiveis da cor (ver PassengerCrowdController.
# react_for_color), nunca nos 40 de uma vez.
func polish_color_react() -> void:
	if _body_root == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_body_root, "scale", Vector3.ONE * 1.06, 0.06)
	tween.tween_property(_body_root, "scale", Vector3.ONE, 0.06)

# ETAPA 4 (item 2): idle procedural sutil, so usado quando is_polish==true
# (ver _build()). Em vez do bounce padrao (amplitude/fase fixas, todo mundo
# sincronizado), cada boneco sorteia sua propria amplitude (0.025-0.045),
# periodo (0.8-1.3s) e um atraso inicial aleatorio (0..periodo) -- e esse
# atraso inicial, antes do loop comecar de fato, que garante que bonecos
# nunca pulam todos juntos (pedido explicito do item 2).
func start_polish_idle() -> void:
	_kill_idle()
	if _body_root == null:
		return
	var amplitude: float = randf_range(0.025, 0.045)
	var period: float = randf_range(0.8, 1.3)
	var initial_delay: float = randf() * period
	var delay_tween := create_tween()
	_idle_tween = delay_tween
	delay_tween.tween_interval(initial_delay)
	delay_tween.tween_callback(_begin_polish_idle_loop.bind(amplitude, period))

func _begin_polish_idle_loop(amplitude: float, period: float) -> void:
	if _body_root == null:
		return
	var half: float = period * 0.5
	var idle := create_tween()
	_idle_tween = idle
	idle.set_loops()
	idle.set_trans(Tween.TRANS_SINE)
	idle.set_ease(Tween.EASE_IN_OUT)
	idle.tween_property(_body_root, "position:y", amplitude, half)
	idle.tween_property(_body_root, "position:y", 0.0, half)

func _face_towards(target: Vector3) -> void:
	var delta: Vector3 = target - position
	if Vector2(delta.x, delta.z).length() < 0.001:
		return
	rotation.y = atan2(delta.x, delta.z)

func _build() -> void:
	_kill_idle()
	_stop_walk_cycle()
	# free() (nao queue_free()) e importante aqui: setup() chama _build() logo
	# depois que _ready() ja rodou um _build() com a cor padrao, e com
	# queue_free() os dois corpos ficavam sobrepostos por um frame antes da
	# remocao diferida acontecer.
	for child: Node in get_children():
		child.free()

	_body_root = Node3D.new()
	_body_root.name = "BodyRoot"
	add_child(_body_root)

	# ETAPA 6 (item 8, PolishTest/fase 950 apenas): leve aumento de escala
	# (12%) pra melhorar legibilidade -- so quando is_polish, entao fases
	# normais continuam exatamente na escala 1.0 de sempre. Fica no proprio
	# PassengerController (nao em _body_root) pra nao interferir com o
	# bounce/idle, que so anima _body_root.position.y.
	if is_polish:
		scale = Vector3.ONE * POLISH_SCALE
		_add_polish_shadow()

	var shirt_color: Color = COLOR_MAP.get(color_id, Color.WHITE)
	var skin := Color("#f2b58a")
	var dark := shirt_color.darkened(0.14)
	var shoe := Color("#263238")

	# Torso toy-like, com silhueta mais humana do que a capsula anterior.
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.18, 0.24, 0.12)
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 0.27, 0.0)
	torso.material_override = _material(shirt_color, 0.46)
	_body_root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.105
	head_mesh.height = 0.21
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.48, 0.0)
	head.material_override = _material(skin, 0.58)
	_body_root.add_child(head)

	# Cabelo simples: hemisferio visual escuro deslocado para tras/cima.
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.108
	hair_mesh.height = 0.105
	hair.mesh = hair_mesh
	hair.position = Vector3(0.0, 0.525, -0.018)
	hair.scale = Vector3(1.0, 0.55, 1.0)
	hair.material_override = _material(Color("#3c2a24"), 0.7)
	_body_root.add_child(hair)

	# Olhos minimos para o personagem ler como pessoa mesmo pequeno na tela.
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.012
		eye_mesh.height = 0.024
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.034, 0.492, 0.092)
		eye.material_override = _material(Color("#20252b"), 0.8)
		_body_root.add_child(eye)

	_leg_pivots.clear()
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "LegPivot"
		hip.position = Vector3(side * 0.045, 0.16, 0.0)
		_body_root.add_child(hip)
		_leg_pivots.append(hip)

		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.052, 0.16, 0.055)
		leg.mesh = leg_mesh
		leg.position = Vector3(0.0, -0.08, 0.0)
		leg.material_override = _material(dark, 0.55)
		hip.add_child(leg)

		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.072, 0.05, 0.115)
		foot.mesh = foot_mesh
		foot.position = Vector3(0.0, -0.17, 0.028)
		foot.material_override = _material(shoe, 0.7)
		hip.add_child(foot)

	_arm_pivots.clear()
	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.name = "ArmPivot"
		shoulder.position = Vector3(side * 0.125, 0.34, 0.0)
		_body_root.add_child(shoulder)
		_arm_pivots.append(shoulder)

		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.045, 0.16, 0.05)
		arm.mesh = arm_mesh
		arm.position = Vector3(0.0, -0.075, 0.0)
		arm.material_override = _material(shirt_color.lightened(0.04), 0.5)
		shoulder.add_child(arm)

		var hand := MeshInstance3D.new()
		var hand_mesh := SphereMesh.new()
		hand_mesh.radius = 0.032
		hand_mesh.height = 0.064
		hand.mesh = hand_mesh
		hand.position = Vector3(0.0, -0.17, 0.0)
		hand.material_override = _material(skin, 0.6)
		shoulder.add_child(hand)

	# Leve bounce idle para nao parecer uma peca totalmente estatica. Na fase
	# 950 (item 2 da Etapa 4) isto vira o idle "polido" abaixo -- amplitude
	# maior e fase inicial variada por boneco; toda fase normal continua com
	# este bounce padrao, inalterado.
	if is_polish:
		start_polish_idle()
	else:
		var idle := create_tween()
		_idle_tween = idle
		idle.set_loops()
		idle.set_trans(Tween.TRANS_SINE)
		idle.set_ease(Tween.EASE_IN_OUT)
		idle.tween_property(_body_root, "position:y", 0.018, 0.34)
		idle.tween_property(_body_root, "position:y", 0.0, 0.34)

# step_duration e o tempo de CADA quarto de passada. walk_to_and_board() usa
# um valor menor (passada mais rapida, ver acima); step_to() (fila 3D
# avancando um lugar) continua no ritmo original, sem pressa.
func _start_walk_cycle(step_duration: float = 0.085) -> void:
	if _leg_pivots.size() < 2 or _arm_pivots.size() < 2:
		return
	_stop_walk_cycle()
	var cycle := create_tween()
	_walk_tween = cycle
	cycle.set_loops()
	cycle.set_trans(Tween.TRANS_SINE)
	cycle.set_ease(Tween.EASE_IN_OUT)
	cycle.tween_property(_leg_pivots[0], "rotation_degrees:x", 28.0, step_duration)
	cycle.parallel().tween_property(_leg_pivots[1], "rotation_degrees:x", -28.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[0], "rotation_degrees:x", -22.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[1], "rotation_degrees:x", 22.0, step_duration)
	cycle.tween_property(_leg_pivots[0], "rotation_degrees:x", -28.0, step_duration)
	cycle.parallel().tween_property(_leg_pivots[1], "rotation_degrees:x", 28.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[0], "rotation_degrees:x", 22.0, step_duration)
	cycle.parallel().tween_property(_arm_pivots[1], "rotation_degrees:x", -22.0, step_duration)

func _stop_walk_cycle() -> void:
	if _walk_tween != null and _walk_tween.is_valid():
		_walk_tween.kill()
	_walk_tween = null
	for pivot: Node3D in _leg_pivots:
		pivot.rotation_degrees = Vector3.ZERO
	for pivot: Node3D in _arm_pivots:
		pivot.rotation_degrees = Vector3.ZERO

func _kill_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null

func _kill_move() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null

# Passo curto da fila avancando (FASE C): reaproveita o ciclo de caminhada
# por um instante, sem repetir toda a coreografia de embarque completo.
func step_to(target: Vector3) -> void:
	# Idem: um toque concorrente pode chamar step_to() de novo (a fila avancou
	# mais uma vez) antes do deslocamento anterior deste MESMO boneco terminar.
	# Cancela o tween antigo ANTES de checar a distancia -- inclusive no caso
	# em que o novo alvo por coincidencia ja esta perto de onde o boneco esta
	# agora (aquele tween antigo continuaria competindo com a proxima chamada
	# de step_to()/walk_to_and_board() se ninguem o cancelasse aqui). Os dois
	# competirem sobre `position` e o motivo dos bonecos aparecerem sobrepostos
	# uns aos outros quando dois carros sao chamados quase ao mesmo tempo.
	_kill_move()
	if position.distance_to(target) < 0.01:
		_stop_walk_cycle()
		return
	_face_towards(target)
	_start_walk_cycle()
	var tween := create_tween()
	_move_tween = tween
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", target, 0.26)
	await tween.finished
	_stop_walk_cycle()

# Usado quando um novo boneco aparece no fim da fila 3D visivel.
func pop_in() -> void:
	var target_scale: Vector3 = Vector3.ONE * POLISH_SCALE if is_polish else Vector3.ONE
	scale = Vector3.ZERO
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", target_scale, 0.22)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

# ETAPA 6 (item 8, PolishTest/fase 950 apenas): sombra achatada e suave aos
# pes do passageiro. Fica FORA de _body_root de proposito -- o bounce idle
# so anima _body_root.position.y, entao a sombra permanece fixa no chao em
# vez de subir/descer junto (o que pareceria flutuante). Uma unica
# SphereMesh achatada, sem luz (unshaded): custo desprezivel mesmo com
# varios passageiros na tela.
func _add_polish_shadow() -> void:
	var shadow := MeshInstance3D.new()
	shadow.name = "PolishShadow"
	var shadow_mesh := SphereMesh.new()
	shadow_mesh.radius = 0.12
	shadow_mesh.height = 0.02
	shadow.mesh = shadow_mesh
	shadow.position = Vector3(0.0, 0.006, 0.0)
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.22)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shadow_material
	add_child(shadow)
