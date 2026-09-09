class_name PassengerChip
extends Control

@export var body_color: Color = Color.WHITE
@export var symbol: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(38, 54)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var shadow := Color(0.12, 0.16, 0.22, 0.22)
	draw_circle(Vector2(w * 0.5 + 2.0, h * 0.22 + 2.0), w * 0.21, shadow)
	draw_circle(Vector2(w * 0.5, h * 0.22), w * 0.21, body_color.lightened(0.14))
	_draw_capsule_rect(Rect2(w * 0.2 + 2.0, h * 0.36 + 2.0, w * 0.6, h * 0.54), shadow)
	_draw_capsule_rect(Rect2(w * 0.2, h * 0.36, w * 0.6, h * 0.54), body_color)
	draw_rect(Rect2(w * 0.31, h * 0.57, w * 0.12, h * 0.34), body_color.darkened(0.08))
	draw_rect(Rect2(w * 0.57, h * 0.57, w * 0.12, h * 0.34), body_color.darkened(0.08))
	draw_circle(Vector2(w * 0.42, h * 0.2), w * 0.035, Color(1, 1, 1, 0.55))
	if symbol != "" and AccessibilitySettings.color_symbols_enabled:
		_draw_symbol(w, h)

# Simbolo de acessibilidade a daltonismo (etapa 10): um marcador unico por
# cor, sobre o "rosto" do passageiro, pra quem nao distingue as cores do
# jogo pela tonalidade sozinha.
func _draw_symbol(w: float, h: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size := int(w * 0.42)
	var text_size: Vector2 = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := Vector2(w * 0.5 - text_size.x * 0.5, h * 0.22 + text_size.y * 0.32)
	draw_string(font, pos, symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, body_color.darkened(0.55))

func _draw_capsule_rect(rect: Rect2, color: Color) -> void:
	var radius := rect.size.x * 0.5
	draw_rect(Rect2(rect.position.x, rect.position.y + radius, rect.size.x, rect.size.y - radius), color)
	draw_circle(rect.position + Vector2(radius, radius), radius, color)
	draw_circle(rect.position + Vector2(radius, rect.size.y - radius), radius, color)
