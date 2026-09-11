class_name ExitDirection
extends RefCounted

# Fonte oficial e tipada da direcao de saida de um veiculo (Etapa 1 do novo
# roadmap: "direcao obrigatoria"). O GameEngine e o VehicleController usam
# SEMPRE este enum -- nunca a rotacao visual do Node3D nem a seta -- pra
# decidir/mostrar a direcao. As fases em JSON continuam guardando texto
# ("up"/"down"/"left"/"right"), exatamente como hoje; a conversao pro enum
# tipado acontece uma unica vez, na fronteira de entrada (coerce()).

enum Value { UP, DOWN, LEFT, RIGHT }

static func from_string(text: String) -> Value:
	match text:
		"up": return Value.UP
		"down": return Value.DOWN
		"left": return Value.LEFT
		"right": return Value.RIGHT
	push_warning("ExitDirection desconhecida '%s', usando UP como fallback." % text)
	return Value.UP

static func to_string_id(value: Value) -> String:
	match value:
		Value.UP: return "up"
		Value.DOWN: return "down"
		Value.LEFT: return "left"
		Value.RIGHT: return "right"
	return "up"

# Aceita tanto o texto historico ("up"/"down"/...) quanto o proprio enum, pra
# nao exigir alterar de uma vez todo chamador existente (JSON de fases,
# LevelGenerator, testes, preview de assets) -- cada um continua passando o
# que ja passava, e ganha o valor tipado de saida sem precisar mudar.
static func coerce(value: Variant) -> Value:
	if value is String:
		return from_string(value)
	if value is int:
		return value as Value
	push_warning("ExitDirection.coerce recebeu tipo inesperado (%s), usando UP." % typeof(value))
	return Value.UP
