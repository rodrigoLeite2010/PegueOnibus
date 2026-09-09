class_name HUDController
extends CanvasLayer

signal restart_requested

const COLOR_MAP := {
	"red": Color("#ff4b4b"),
	"blue": Color("#2f91ff"),
	"green": Color("#35de45"),
	"yellow": Color("#ffd236"),
	"purple": Color("#9349ff"),
	"pink": Color("#ff43c8"),
	"orange": Color("#ff7b20"),
}

var _root: Control
var _title: Label
var _moves: Label
var _queue_holder: HBoxContainer
var _slots_holder: HBoxContainer
var _message: Label
var _modal: PanelContainer

func _ready() -> void:
	_build_static_ui()

func update_state(state: GameState, text: String = "") -> void:
	if _root == null:
		_build_static_ui()
	_title.text = "Fase %s" % state.level_id
	_moves.text = "%s mov." % state.moves
	_message.text = text
	_render_queue(state.passenger_queue)
	_render_slots(state)
	_update_modal(state)
	_refresh_mouse_filters(self)

func _build_static_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_add_soft_top_panel()
	_add_top_buttons()
	_add_level_title()
	_add_queue_holder()
	_add_slots_holder()
	_add_message_label()
	_add_boosters()
	_refresh_mouse_filters(self)

func _add_soft_top_panel() -> void:
	var panel := Panel.new()
	panel.anchor_right = 1.0
	panel.offset_bottom = 292
	panel.add_theme_stylebox_override("panel", _style(Color(1.0, 0.75, 0.78, 0.94), Color.TRANSPARENT, 0, 0))
	_root.add_child(panel)

func _add_top_buttons() -> void:
	var restart := _round_button("↺")
	restart.position = Vector2(28, 30)
	restart.pressed.connect(func() -> void: restart_requested.emit())
	_root.add_child(restart)

	var pause := _round_button("Ⅱ")
	pause.anchor_left = 1.0
	pause.anchor_right = 1.0
	pause.position = Vector2(-92, 30)
	_root.add_child(pause)

	_moves = Label.new()
	_moves.anchor_right = 1.0
	_moves.offset_top = 28
	_moves.offset_bottom = 76
	_moves.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_moves.add_theme_font_size_override("font_size", 22)
	_moves.add_theme_color_override("font_color", Color("#4d566b"))
	_root.add_child(_moves)

func _add_level_title() -> void:
	_title = Label.new()
	_title.text = "Fase 1"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 48)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_shadow_color", Color("#4d566b"))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 5)
	_title.anchor_right = 1.0
	_title.offset_top = 76
	_title.offset_bottom = 138
	_root.add_child(_title)

func _add_queue_holder() -> void:
	_queue_holder = HBoxContainer.new()
	_queue_holder.anchor_left = 0.08
	_queue_holder.anchor_right = 0.92
	_queue_holder.offset_top = 142
	_queue_holder.offset_bottom = 205
	_queue_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_queue_holder.add_theme_constant_override("separation", 7)
	_root.add_child(_queue_holder)

func _add_slots_holder() -> void:
	var strip := Panel.new()
	strip.anchor_right = 1.0
	strip.offset_top = 214
	strip.offset_bottom = 332
	strip.add_theme_stylebox_override("panel", _style(Color(0.42, 0.45, 0.53, 0.94), Color(0.9, 0.94, 1.0, 0.45), 0, 0))
	_root.add_child(strip)

	_slots_holder = HBoxContainer.new()
	_slots_holder.anchor_left = 0.08
	_slots_holder.anchor_right = 0.92
	_slots_holder.offset_top = 226
	_slots_holder.offset_bottom = 320
	_slots_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_holder.add_theme_constant_override("separation", 13)
	_root.add_child(_slots_holder)

func _add_message_label() -> void:
	_message = Label.new()
	_message.anchor_right = 1.0
	_message.anchor_top = 1.0
	_message.anchor_bottom = 1.0
	_message.offset_top = -205
	_message.offset_bottom = -165
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 22)
	_message.add_theme_color_override("font_color", Color("#4d566b"))
	_root.add_child(_message)

func _add_boosters() -> void:
	var holder := HBoxContainer.new()
	holder.anchor_left = 0.06
	holder.anchor_right = 0.94
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_top = -160
	holder.offset_bottom = -36
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_theme_constant_override("separation", 18)
	_root.add_child(holder)

	for label_text: String in ["VIP", "Organizar", "Dica"]:
		var button := Button.new()
		button.text = label_text
		button.custom_minimum_size = Vector2(185, 104)
		button.add_theme_font_size_override("font_size", 27)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_shadow_color", Color(0.1, 0.18, 0.28, 0.45))
		button.add_theme_constant_override("shadow_offset_y", 3)
		button.add_theme_stylebox_override("normal", _style(Color("#35aeea"), Color("#2588bf"), 24, 2))
		button.add_theme_stylebox_override("pressed", _style(Color("#2588bf"), Color("#1f719f"), 24, 2))
		holder.add_child(button)

func _refresh_mouse_filters(node: Node) -> void:
	if node is BaseButton:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	elif node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_refresh_mouse_filters(child)

func _render_queue(queue: Array[String]) -> void:
	_clear(_queue_holder)
	var visible_count: int = mini(queue.size(), 12)
	for index: int in range(visible_count):
		var color_id: String = queue[index]
		var passenger := PassengerChip.new()
		var color: Color = COLOR_MAP.get(color_id, Color.WHITE)
		passenger.body_color = color
		if index == 0:
			passenger.scale = Vector2(1.12, 1.12)
		_queue_holder.add_child(passenger)

func _render_slots(state: GameState) -> void:
	_clear(_slots_holder)
	for slot: WaitingSlotState in state.waiting_slots:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(76, 86)
		label.rotation_degrees = -10
		label.add_theme_font_size_override("font_size", 20)
		if slot.is_empty():
			label.text = ""
			label.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.03), Color("#f0f5ff"), 12, 4))
		else:
			var vehicle: VehicleState = state.vehicles[slot.vehicle_id]
			var color: Color = COLOR_MAP.get(vehicle.color_id, Color.WHITE)
			label.text = "%s/%s" % [vehicle.occupied_seats, vehicle.capacity]
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_stylebox_override("normal", _style(color, color.darkened(0.2), 12, 3))
		_slots_holder.add_child(label)

	for index: int in range(2):
		var add_slot := Label.new()
		add_slot.text = "+"
		add_slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_slot.custom_minimum_size = Vector2(76, 86)
		add_slot.rotation_degrees = -10
		add_slot.add_theme_font_size_override("font_size", 36)
		add_slot.add_theme_color_override("font_color", Color("#72ea86"))
		add_slot.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.03), Color("#72ea86"), 12, 4))
		_slots_holder.add_child(add_slot)

func _update_modal(state: GameState) -> void:
	if state.status == GameState.PLAYING:
		if _modal != null:
			_modal.queue_free()
			_modal = null
		return
	if _modal != null:
		return

	_modal = PanelContainer.new()
	_modal.anchor_left = 0.18
	_modal.anchor_right = 0.82
	_modal.anchor_top = 0.34
	_modal.anchor_bottom = 0.62
	_modal.add_theme_stylebox_override("panel", _style(Color.WHITE, Color("#dbe5f4"), 26, 3))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_modal.add_child(box)
	var title := Label.new()
	title.text = "Vitoria!" if state.status == GameState.WON else "Travou"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#3d4658"))
	box.add_child(title)
	var button := Button.new()
	button.text = "Reiniciar"
	button.custom_minimum_size = Vector2(180, 56)
	button.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(button)
	_root.add_child(_modal)

func _round_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(64, 64)
	button.add_theme_font_size_override("font_size", 34)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color("#35aeea"), Color("#2588bf"), 17, 2))
	button.add_theme_stylebox_override("pressed", _style(Color("#2588bf"), Color("#1f719f"), 17, 2))
	return button

func _style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.14, 0.18, 0.26, 0.24)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 6)
	style.set_content_margin(SIDE_LEFT, 12)
	style.set_content_margin(SIDE_RIGHT, 12)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_BOTTOM, 10)
	return style

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		child.queue_free()
