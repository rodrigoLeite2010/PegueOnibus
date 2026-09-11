class_name VehicleVisualLibrary
extends RefCounted

# Etapa "cada type_id carrega o modelo correto": o tipo (type_id) e a UNICA
# fonte de verdade pra escolher o GLB -- nunca color_id, nunca um heuristico
# de tamanho visual. "small_car"/"medium_car"/"bus" sao os nomes oficiais;
# "car"/"van" ficam mapeados pros mesmos GLBs de small_car/medium_car como
# aliases de compatibilidade, porque LevelGenerator e os level_XXX.json
# existentes ainda usam esses type_id (ver comentario em get_for_vehicle).
# "bus" agora tem GLB proprio (bus.tres/Bus.tscn) -- deixou de cair no
# placeholder procedural. Se aparecer um type_id futuro sem entrada aqui,
# get_for_vehicle() cai automaticamente no fallback de emergencia.
const MODEL_RESOURCE_BY_TYPE := {
	"small_car": "res://resources/vehicle_types/red.tres",
	"car": "res://resources/vehicle_types/red.tres",
	"medium_car": "res://resources/vehicle_types/medium_car.tres",
	"van": "res://resources/vehicle_types/medium_car.tres",
	"bus": "res://resources/vehicle_types/bus.tres",
}

# Escala centralizada por tipo -- nao espalhar esses numeros pelo codigo.
# Para recalibrar o tamanho de um modelo depois do teste visual, mude
# somente aqui.
const VISUAL_SCALE_SMALL_CAR := 4.0

# CORRECAO (feedback do print: "carro ficou gigante"): 4.0 era o valor do
# CarSmall copiado sem calibrar. medium_car.glb tem uma malha ~10x maior em
# unidades nativas do que car_test.glb (medi via bounding box dos dois GLBs:
# comprimento Z nativo do CarSmall = 0.438, do CarMedium = 4.549). Como os
# dois tipos usam o mesmo footprint logico (length=2 -- "van"/"medium_car"
# nao entra no caso especial de "bus" em VehicleDefinition), a escala certa
# e a que faz o CarMedium ocupar o MESMO comprimento visual que o CarSmall
# ja ocupa corretamente: 4.0 * (0.438 / 4.549) =~ 0.385. Se mais pra frente
# quiserem o medium visivelmente maior que o small (nome sugere isso), e so
# aumentar este numero um pouco -- sem mexer em footprint/GameEngine.
const VISUAL_SCALE_MEDIUM_CAR := 0.385

# CORRECAO: 0.385 (copiado do medium_car sem calibrar) estava
# ABSURDAMENTE errado pro onibus -- bus.glb foi exportado numa escala
# nativa completamente diferente dos outros GLBs (comprimento nativo no
# eixo X = 1087.87, contra 4.55 do medium_car e 0.44 do small_car; ou
# seja, quase 1000x maior em unidades de arquivo). Medi o bounding box de
# bus.glb direto (mesma tecnica usada pro medium_car) e recalculei pra
# ocupar o footprint logico do onibus (length=3 -> profundidade alvo
# 2.64, ver VehicleDefinition._apply_default_footprint_if_needed): 2.64 /
# 1087.87 =~ 0.002427. Com 0.385 o onibus apareceria ~158x maior do que
# deveria (uma versao bem mais grave do bug do "carro gigante").
const VISUAL_SCALE_BUS := 0.002427

const MODEL_SCALE_BY_TYPE := {
	"small_car": VISUAL_SCALE_SMALL_CAR,
	"car": VISUAL_SCALE_SMALL_CAR,
	"medium_car": VISUAL_SCALE_MEDIUM_CAR,
	"van": VISUAL_SCALE_MEDIUM_CAR,
	"bus": VISUAL_SCALE_BUS,
}

const RESOURCE_BY_COLOR := {
	"red": "res://resources/vehicle_types/red.tres",
	"blue": "res://resources/vehicle_types/blue.tres",
	"green": "res://resources/vehicle_types/green.tres",
	"yellow": "res://resources/vehicle_types/yellow.tres",
	"purple": "res://resources/vehicle_types/purple.tres",
	"pink": "res://resources/vehicle_types/pink.tres",
	"orange": "res://resources/vehicle_types/orange.tres",
}

static func get_for_vehicle(type_id: String, color_id: String) -> VehicleVisualResource:
	# type_id e SEMPRE quem decide o modelo -- color_id so entra depois,
	# jah dentro de VehicleController, pra recolorir o modelo escolhido
	# (set_vehicle_color). Nenhum tamanho visual/footprint e consultado aqui.
	var model_path: String = MODEL_RESOURCE_BY_TYPE.get(type_id, "")
	if model_path != "" and ResourceLoader.exists(model_path):
		var resource := load(model_path) as VehicleVisualResource
		if resource != null:
			# Escala centralizada por tipo (ver MODEL_SCALE_BY_TYPE) em vez
			# de depender do valor salvo dentro do .tres.
			resource.model_scale = MODEL_SCALE_BY_TYPE.get(type_id, resource.model_scale)
		return resource
	# type_id sem entrada em MODEL_RESOURCE_BY_TYPE (hoje nenhum tipo em uso
	# cai aqui) vira fallback de emergencia: sem model_scene, o placeholder
	# procedural entra em VehicleController.rebuild().
	return get_for_color(color_id)

static func get_for_color(color_id: String) -> VehicleVisualResource:
	var path: String = RESOURCE_BY_COLOR.get(color_id, "")
	if path != "" and ResourceLoader.exists(path):
		return load(path) as VehicleVisualResource
	return null
