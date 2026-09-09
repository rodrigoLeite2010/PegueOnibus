class_name HomeScreenController
extends CanvasLayer

# Tela inicial (etapa 9 - Progressao). "Jogar" abre direto a fase mais
# avancada ainda nao vencida; "Mapa de fases" deixa escolher qualquer fase
# ja desbloqueada. O botao de engrenagem abre o mesmo popup de
# configuracoes (efeitos/vibracao) que ja existe na pausa do HUD.

@onready var _root: Control = $Root
@onready var _play_button: Button = $Root/PlayButton
@onready var _map_button: Button = $Root/MapButton
@onready var _settings_button: Button = $Root/Settings

var _coin_badge: PanelContainer
var _coin_label: Label
var _settings_popup: PanelContainer

func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_map_button.pressed.connect(func() -> void: AppRouter.go_map())
	_settings_button.pressed.connect(_on_settings_pressed)
	_build_coin_badge()
	Wallet.coins_changed.connect(_on_coins_changed)

func _on_play_pressed() -> void:
	AppRouter.go_game(ProgressService.get_next_playable_level())

func _on_settings_pressed() -> void:
	if _settings_popup != null:
		_close_settings_popup()
		return
	_open_settings_popup()

# --- Moedas: mesmo badge simples do HUD, so pra mostrar o total antes de
# entrar numa fase. ---

func _build_coin_badge() -> void:
	_coin_badge = PanelContainer.new()
	_coin_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_badge.position = Vector2(28.0, 28.0)
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

# --- Configuracoes: mesmo conteudo do popup de pausa do HUD (secao 15 da
# especificacao: ligar/desligar efeitos e vibracao), disponivel tambem fora
# de uma partida. ---

func _open_settings_popup() -> void:
	_settings_popup = PanelContainer.new()
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

func _on_color_symbols_toggled(value: bool) -> void:
	AccessibilitySettings.set_color_symbols_enabled(value)

func _close_settings_popup() -> void:
	if _settings_popup != null:
		_settings_popup.queue_free()
		_settings_popup = null

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
