class_name HUDController
extends CanvasLayer

signal restart_requested
signal continue_requested
signal hint_requested

const COLOR_MAP := {
	"red": Color("#ff4b4b"),
	"blue": Color("#2f91ff"),
	"green": Color("#35de45"),
	"yellow": Color("#ffd236"),
	"purple": Color("#9349ff"),
	"pink": Color("#ff43c8"),
	"orange": Color("#ff7b20"),
}

# Layout denso (etapa "queue/slots como na referencia"): quantas celulas o
# grid da fila comporta de uma vez (colunas=8 no HUD.tscn -> 3 linhas cheias).
# Uma celula fica sempre reservada pro rotulo "+N" quando ha mais passageiros
# do que cabem aqui -- ver _render_queue.
const QUEUE_GRID_CAPACITY := 14

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Title
@onready var _moves: Label = $Root/Moves
@onready var _queue_holder: GridContainer = $Root/QueueHolder
@onready var _message: Label = $Root/Message
@onready var _restart: Button = $Root/Restart
@onready var _pause: Button = $Root/Pause
@onready var _hint: Button = $Root/Boosters/Dica

var _modal: PanelContainer
var _coin_badge: PanelContainer
var _coin_label: Label
var _settings_popup: PanelContainer
var _queue_chips: Array[PassengerChip] = []
var _queue_more_label: Label

func _ready() -> void:
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	_pause.pressed.connect(_on_pause_pressed)
	_hint.pressed.connect(func() -> void: hint_requested.emit())
	_build_coin_badge()
	Wallet.coins_changed.connect(_on_coins_changed)

func update_state(state: GameState, text: String = "", progress_text: String = "", stars: int = -1) -> void:
	_title.text = "Fase %s" % state.level_id
	if progress_text != "":
		_title.tooltip_text = "Progresso %s" % progress_text
	_moves.text = "%s mov." % state.moves
	_message.text = text
	# Passageiros agora sao mostrados como pessoas 3D junto das vagas.
	_update_modal(state, stars)

func _on_pause_pressed() -> void:
	if _settings_popup != null:
		_close_settings_popup()
		return
	_open_settings_popup()

func show_message(text: String) -> void:
	_message.text = text

# Reaproveita os PassengerChip em vez de destruir/recriar a cada
# atualizacao (etapa 10 - performance): o toque num veiculo dispara varias
# chamadas de update_state seguidas, e recriar ate 11 controles com
# _draw() a cada uma pesava mais do que precisava.
func _render_queue(queue: Array[String]) -> void:
	var visible_count: int = mini(queue.size(), QUEUE_GRID_CAPACITY)
	if queue.size() > QUEUE_GRID_CAPACITY:
		# Reserva a ultima celula do grid pro rotulo "+N" (etapa layout denso):
		# sem isso o grid ganharia uma linha extra so pra caber o rotulo.
		visible_count = QUEUE_GRID_CAPACITY - 1
	for index: int in range(visible_count):
		var color_id: String = queue[index]
		var passenger: PassengerChip = _queue_chip_at(index)
		passenger.body_color = COLOR_MAP.get(color_id, Color.WHITE)
		passenger.symbol = AccessibilitySettings.symbol_for(color_id)
		passenger.custom_minimum_size = Vector2(30, 44)
		if index == 0:
			passenger.custom_minimum_size = Vector2(34, 48)
		passenger.visible = true
		passenger.queue_redraw()
	for extra_index: int in range(visible_count, _queue_chips.size()):
		_queue_chips[extra_index].visible = false

	if _queue_more_label == null:
		_queue_more_label = Label.new()
		_queue_more_label.add_theme_font_size_override("font_size", 17)
		_queue_more_label.add_theme_color_override("font_color", Color("#eef1f6"))
		_queue_more_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_queue_holder.add_child(_queue_more_label)
	if queue.size() > visible_count:
		_queue_more_label.text = "+%s" % (queue.size() - visible_count)
		_queue_more_label.visible = true
	else:
		_queue_more_label.visible = false

# Cria um PassengerChip novo so na primeira vez que esse indice e usado;
# dai em diante o mesmo no e sempre reaproveitado (a fila de uma fase so
# encolhe, nunca cresce, entao nao ha necessidade de reordenar os nos).
func _queue_chip_at(index: int) -> PassengerChip:
	if index < _queue_chips.size():
		return _queue_chips[index]
	var passenger := PassengerChip.new()
	_queue_holder.add_child(passenger)
	_queue_chips.append(passenger)
	return passenger

func _update_modal(state: GameState, stars: int = -1) -> void:
	if state.status == GameState.PLAYING:
		if _modal != null:
			_modal.queue_free()
			_modal = null
		return
	if _modal != null:
		return

	_modal = PanelContainer.new()
	_modal.anchor_left = 0.16
	_modal.anchor_right = 0.84
	_modal.anchor_top = 0.37
	_modal.anchor_bottom = 0.61
	_modal.add_theme_stylebox_override("panel", _modal_style())
	# Entrada moderna (Fase F): nunca aparece "seco" -- comeca invisivel e
	# reduzido, e so ganha vida com o fade+scale no fim desta funcao.
	_modal.modulate.a = 0.0
	_modal.scale = Vector2(0.82, 0.82)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_modal.add_child(box)
	var title := Label.new()
	title.text = "Vitoria!" if state.status == GameState.WON else "Travou"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#3d4658"))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Todos os passageiros embarcaram." if state.status == GameState.WON else "Nao ha mais uma jogada valida."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color("#667085"))
	box.add_child(subtitle)
	if state.status == GameState.WON and stars >= 0:
		box.add_child(_build_stars_row(stars))
	var button := Button.new()
	button.text = "Ver mapa" if state.status == GameState.WON else "Tentar novamente"
	button.custom_minimum_size = Vector2(230, 58)
	if state.status == GameState.WON:
		button.pressed.connect(func() -> void: continue_requested.emit())
	else:
		button.pressed.connect(func() -> void: restart_requested.emit())
	button.disabled = true
	box.add_child(button)
	_root.add_child(_modal)

	# O tamanho por ancoras so fica definido depois que o no entra na arvore
	# e passa por um frame de layout -- espera esse frame antes de fixar o
	# pivot central, senao o scale-in cresceria a partir do canto.
	await get_tree().process_frame
	if not is_instance_valid(_modal):
		return
	_modal.pivot_offset = _modal.size * 0.5

	var entrance := create_tween()
	if state.status == GameState.WON:
		# Da tempo das particulas/som/moedas (ja disparados pelo GameController)
		# acabarem de chamar atencao antes do painel assumir a tela, seguindo a
		# sequencia da especificacao: particulas -> som -> moedas -> botao.
		entrance.tween_interval(0.35)
	entrance.set_trans(Tween.TRANS_BACK)
	entrance.set_ease(Tween.EASE_OUT)
	entrance.tween_property(_modal, "modulate:a", 1.0, 0.22)
	entrance.parallel().tween_property(_modal, "scale", Vector2.ONE, 0.32)
	entrance.tween_callback(func() -> void: button.disabled = false)

# Estrelas ganhas na fase (etapa 9, decisao confirmada: baseado em toques
# bloqueados). So aparece no modal de vitoria.
func _build_stars_row(stars: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for i: int in range(3):
		var star := Label.new()
		star.text = "★" if i < stars else "☆"
		star.add_theme_font_size_override("font_size", 34)
		star.add_theme_color_override("font_color", Color("#ffd233") if i < stars else Color("#d7deea"))
		row.add_child(star)
	return row

func _modal_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color("#dbe5f4")
	style.set_border_width_all(3)
	style.set_corner_radius_all(26)
	style.shadow_color = Color(0.08, 0.12, 0.2, 0.26)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 8)
	style.set_content_margin(SIDE_LEFT, 22)
	style.set_content_margin(SIDE_RIGHT, 22)
	style.set_content_margin(SIDE_TOP, 22)
	style.set_content_margin(SIDE_BOTTOM, 22)
	return style

# --- Moedas (secao 14 da especificacao: contador com numero animado e
# feedback ao receber recompensa) ---

func _build_coin_badge() -> void:
	_coin_badge = PanelContainer.new()
	_coin_badge.name = "CoinBadge"
	_coin_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_badge.position = Vector2(28.0, 100.0)
	_coin_badge.pivot_offset = Vector2(48.0, 17.0)
	_coin_badge.add_theme_stylebox_override("panel", _coin_badge_style())

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_coin_badge.add_child(row)

	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_stylebox_override("panel", _coin_icon_style())
	row.add_child(icon)

	_coin_label = Label.new()
	_coin_label.text = str(Wallet.total_coins)
	_coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_label.add_theme_font_size_override("font_size", 18)
	_coin_label.add_theme_color_override("font_color", Color("#5a4300"))
	row.add_child(_coin_label)

	_root.add_child(_coin_badge)

func _on_coins_changed(new_total: int) -> void:
	if _coin_label != null:
		_coin_label.text = str(new_total)

# Chamado pelo GameController quando a fase e vencida: algumas moedinhas
# voam do meio da tela at o contador (escala + rotacao + trajetoria em
# curva, como pede a especificacao), sem depender de nenhum asset novo.
func play_coin_reward(amount: int) -> void:
	if amount <= 0 or _coin_badge == null:
		return
	var flying_coin_count := 6
	var start_pos: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var target_pos: Vector2 = _coin_badge.get_global_rect().get_center()
	for i: int in range(flying_coin_count):
		var jitter := Vector2(randf_range(-26.0, 26.0), randf_range(-18.0, 18.0))
		var from: Vector2 = start_pos + jitter
		var control := Vector2(lerpf(from.x, target_pos.x, 0.5), minf(from.y, target_pos.y) - 110.0)
		var is_last: bool = i == flying_coin_count - 1
		_animate_flying_coin(from, control, target_pos, i * 0.06, is_last)

func _make_flying_coin() -> Control:
	var coin := PanelContainer.new()
	coin.custom_minimum_size = Vector2(20, 20)
	coin.size = Vector2(20, 20)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.pivot_offset = Vector2(10, 10)
	# Fica por cima do painel de vitoria/derrota, que tambem aparece na hora
	# em que a fase e vencida (senao as moedas voariam escondidas atras dele).
	coin.z_index = 100
	coin.add_theme_stylebox_override("panel", _coin_icon_style())
	return coin

func _animate_flying_coin(from: Vector2, control: Vector2, target: Vector2, delay: float, is_last: bool) -> void:
	var coin: Control = _make_flying_coin()
	_root.add_child(coin)
	coin.global_position = from
	coin.modulate.a = 0.0
	coin.scale = Vector2(0.4, 0.4)

	var duration := 0.5
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(coin, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(coin, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(coin, "rotation_degrees", 540.0, duration)
	tween.parallel().tween_method(
		func(t: float) -> void: coin.global_position = _quad_bezier(from, control, target, t),
		0.0, 1.0, duration
	)
	tween.tween_callback(_on_flying_coin_arrived.bind(coin, is_last))

func _on_flying_coin_arrived(coin: Control, is_last: bool) -> void:
	AudioManager.play_sfx("coin")
	coin.queue_free()
	if is_last:
		_bump_coin_badge()

func _quad_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var a: Vector2 = p0.lerp(p1, t)
	var b: Vector2 = p1.lerp(p2, t)
	return a.lerp(b, t)

func _bump_coin_badge() -> void:
	if _coin_badge == null:
		return
	var bump := create_tween()
	bump.tween_property(_coin_badge, "scale", Vector2(1.18, 1.18), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bump.tween_property(_coin_badge, "scale", Vector2.ONE, 0.14)

func _coin_badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.92)
	style.border_color = Color("#e6c34a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(17)
	style.shadow_color = Color(0.1, 0.15, 0.22, 0.22)
	style.shadow_size = 4
	style.set_content_margin(SIDE_LEFT, 10)
	style.set_content_margin(SIDE_RIGHT, 12)
	style.set_content_margin(SIDE_TOP, 5)
	style.set_content_margin(SIDE_BOTTOM, 5)
	return style

func _coin_icon_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#ffd233")
	style.border_color = Color("#c98f0a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	style.shadow_color = Color(0.1, 0.15, 0.22, 0.2)
	style.shadow_size = 1
	return style

# --- Configuracoes (Pause): liga/desliga efeitos e vibracao (secao 15 da
# especificacao). Nao ha musica ainda, entao nao expomos esse toggle - um
# controle sem efeito repetiria o problema dos botoes VIP/Organizar/Dica. ---

func _open_settings_popup() -> void:
	_settings_popup = PanelContainer.new()
	_settings_popup.name = "SettingsPopup"
	_settings_popup.anchor_left = 0.14
	_settings_popup.anchor_right = 0.86
	_settings_popup.anchor_top = 0.40
	_settings_popup.anchor_bottom = 0.60
	_settings_popup.add_theme_stylebox_override("panel", _modal_style())

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_settings_popup.add_child(box)

	var title := Label.new()
	title.text = "Configuracoes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#3d4658"))
	box.add_child(title)

	box.add_child(_build_toggle_row("Efeitos sonoros", AudioManager.sfx_enabled, _on_sfx_toggled))
	box.add_child(_build_toggle_row("Vibracao", AudioManager.vibration_enabled, _on_vibration_toggled))
	box.add_child(_build_toggle_row("Simbolos de cor (daltonismo)", AccessibilitySettings.color_symbols_enabled, _on_color_symbols_toggled))

	var close_button := Button.new()
	close_button.text = "Fechar"
	close_button.custom_minimum_size = Vector2(150, 44)
	close_button.pressed.connect(_close_settings_popup)
	box.add_child(close_button)

	_root.add_child(_settings_popup)

func _build_toggle_row(label_text: String, initial: bool, on_toggle: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("#3d4658"))
	row.add_child(label)

	var toggle := CheckButton.new()
	toggle.button_pressed = initial
	toggle.toggled.connect(on_toggle)
	row.add_child(toggle)
	return row

func _on_sfx_toggled(value: bool) -> void:
	AudioManager.set_sfx_enabled(value)

func _on_vibration_toggled(value: bool) -> void:
	AudioManager.set_vibration_enabled(value)

# Simbolos de cor por acessibilidade a daltonismo (etapa 10). Nao redesenha
# retroativamente veiculos ja no tabuleiro (a seta deles e fixada quando o
# veiculo aparece); a fila e as vagas de espera atualizam na hora, porque
# sao redesenhadas a cada update_state.
func _on_color_symbols_toggled(value: bool) -> void:
	AccessibilitySettings.set_color_symbols_enabled(value)

func _close_settings_popup() -> void:
	if _settings_popup != null:
		_settings_popup.queue_free()
		_settings_popup = null

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		child.queue_free()
