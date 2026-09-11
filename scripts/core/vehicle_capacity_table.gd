class_name VehicleCapacityTable
extends RefCounted

# Capacidades de referencia por tipo de veiculo (Etapa 1 do novo roadmap):
# preparar a escala antes dos GLBs reais de pequeno/medio/onibus existirem.
# AINDA NAO esta ligado a nada -- cada VehicleDefinition continua trazendo
# seu proprio "capacity" no JSON da fase, exatamente como hoje. Serve de
# referencia pronta pra quando fases novas forem desenhadas em torno dessa
# escala (etapa 2: substituir o visual pelos tres tipos de veiculo 3D).
const DEFAULT_CAPACITY := {
	"small_car": 16,
	"car": 16,
	"medium_car": 24,
	"van": 24,
	"bus": 40,
}

static func default_for(type_id: String) -> int:
	return DEFAULT_CAPACITY.get(type_id, 2)
