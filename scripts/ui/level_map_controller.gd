class_name LevelMapController
extends CanvasLayer

# Mapa de fases (etapa 9 - Progressao). Mostra toda fase ja desbloqueada
# (numero + estrelas + botao "Jogar") e mais algumas bloqueadas como teaser,
# igual ao teaser de vagas extras que ja existe no HUD. E reconstruido do
# zero toda vez que a tela abre (o AppRouter sempre instancia de novo), entao
# ja aparece atualizado depois de vencer uma fase.

const ROWS_AHEAD_LOCKED := 3

@onready var _back: Button = $Root/Back
@onready var _level_list: VBoxContainer = $Root/ScrollContainer/LevelList

func _ready() -> void:
	_back.pressed.connect(func() -> void: AppRouter.go_home())
	_build_level_list()

func _build_level_list() -> void:
	for child: Node in _level_list.get_children():
		child.queue_free()
	var highest_unlocked: int = ProgressService.get_highest_unlocked()
	var last_level: int = highest_unlocked + ROWS_AHEAD_LOCKED
	for level_number: int in range(1, last_level + 1):
		_level_list.add_child(_build_level_row(level_number, level_number <= highest_unlocked))

func _build_level_row(level_number: int, unlocked: bool) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 96)
	card.add_theme_stylebox_override("panel", _card_style(unlocked))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)

	var number_label := Label.new()
	number_label.text = str(level_number)
	number_label.custom_minimum_size = Vector2(72, 0)
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.add_theme_font_size_override("font_size", 32)
	number_label.add_theme_color_override("font_color", Color.WHITE if unlocked else Color("#8b93a3"))
	row.add_child(number_label)

	if unlocked:
		var stars_row := _build_stars_row(ProgressService.get_stars(level_number))
		stars_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stars_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_child(stars_row)

		var play_button := Button.new()
		play_button.text = "Jogar"
		play_button.custom_minimum_size = Vector2(120, 56)
		play_button.pressed.connect(func() -> void: AppRouter.go_game(level_number))
		row.add_child(play_button)
	else:
		var lock_label := Label.new()
		lock_label.text = "Bloqueada"
		lock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lock_label.add_theme_font_size_override("font_size", 20)
		lock_label.add_theme_color_override("font_color", Color("#8b93a3"))
		row.add_child(lock_label)

		var lock_icon := Label.new()
		lock_icon.text = "🔒"
		lock_icon.custom_minimum_size = Vector2(120, 56)
		lock_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_icon.add_theme_font_size_override("font_size", 26)
		row.add_child(lock_icon)

	return card

func _build_stars_row(stars: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i: int in range(3):
		var star := Label.new()
		star.text = "★" if i < stars else "☆"
		star.add_theme_font_size_override("font_size", 22)
		star.add_theme_color_override("font_color", Color("#ffd233") if i < stars else Color("#c7cfdd"))
		row.add_child(star)
	return row

func _card_style(unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.62, 0.90, 1) if unlocked else Color(0.85, 0.87, 0.91, 1)
	style.border_color = Color(0.08, 0.43, 0.68, 1) if unlocked else Color(0.72, 0.75, 0.80, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.1, 0.15, 0.22, 0.2)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 4)
	style.set_content_margin(SIDE_LEFT, 16)
	style.set_content_margin(SIDE_RIGHT, 16)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_BOTTOM, 10)
	return style
