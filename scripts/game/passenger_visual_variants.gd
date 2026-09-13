class_name PassengerVisualVariants
extends RefCounted

# ETAPA 10C: fonte UNICA de configuracao de cada modelo 3D de passageiro.
# Nem passenger_3d.gd, nem passenger_controller.gd, nem
# passenger_crowd_controller.gd guardam caminho de .glb ou parametro de
# mascara de cor soltos -- tudo fica so aqui (Passo 3 do pedido: "nao
# espalhar caminhos dos GLBs pelo projeto"). Passenger3D.configure() e
# quem le este array; PassengerController nunca precisa saber quantas
# variantes existem nem o que cada uma representa (Passo 8: ele so pede
# idle/walk/run, nunca "homem" ou "mulher").
#
# Adicionar um passenger_03/04/05/06 no futuro (Etapa 10C deixa preparado,
# mas NAO cria nada disso ainda -- Passo 12) e so incluir mais uma entrada
# neste array, com os proprios numeros medidos (auditoria abaixo). Nenhum
# outro arquivo precisa mudar.
#
# Campos de cada perfil:
# - scene: PackedScene do .glb (nunca um wrapper -- Passenger3D e o unico
#   wrapper, instanciado uma vez por Passenger3D.tscn; o .glb escolhido
#   aqui e instanciado DENTRO do VisualRoot em tempo de execucao, ver
#   Passenger3D.configure()).
# - scale / rotation_degrees / position_offset: correcao POR MODELO
#   aplicada em cima do VisualRoot (nunca no GLB original nem no proprio
#   Passenger3D), para compensar pequena diferenca de escala/altura/
#   orientacao entre modelos, sem tocar em gameplay (Passo 2 do pedido).
#   Auditoria da Etapa 10C (bounding box Y do accessor POSITION de cada
#   .glb, comparado node a node): passenger_01 vai de y=-0.0001 a
#   y=0.9809 (altura ~0.9811, pes praticamente em y=0); passenger_02 vai
#   de y=0.0008 a y=0.9798 (altura ~0.9790, pes tambem praticamente em
#   y=0). Diferenca de altura ~0.2%, pes a menos de 1mm de diferenca -- os
#   dois vieram do mesmo pipeline de retopologia/rig e ficam
#   indistinguiveis em jogo, entao NENHUMA correcao foi necessaria agora
#   (ambos com 1.0/0.0/ZERO). Os campos existem prontos para quando um
#   futuro passenger_0N vier com proporcao diferente.
# - shirt_hue / shirt_hue_full / shirt_hue_zero / shirt_sat_floor:
#   parametros da mascara de recoloracao (Etapa 10B) MEDIDOS na textura
#   albedo DESTE modelo especifico (histograma de matiz/saturacao da
#   textura basecolor de cada .glb, ver ENTREGA_ETAPA_10C.md) -- nunca
#   assumidos iguais entre modelos (Passo 7 do pedido: "nao assumir que a
#   mascara da camiseta do passenger_01 serve diretamente para
#   passenger_02"). passenger_01 tem a camiseta amarela original (matiz
#   ~44 graus); passenger_02 tem o moletom rosa original (matiz ~339
#   graus) -- a calca azul/tenis/pele/cabelo do passenger_02 ficam bem
#   longe dessa faixa (calca ~200-220 graus, cabelo ~10-20 graus, pele
#   ~20-30 graus) e nunca entram na mascara.
const PROFILES := [
	{
		"scene": preload("res://assets/characters/passengers/passenger_01.glb"),
		"scale": 1.0,
		"rotation_degrees": 0.0,
		"position_offset": Vector3.ZERO,
		"shirt_hue": 0.1211,      # ~44 graus (camiseta amarela original)
		"shirt_hue_full": 0.028,  # ~10 graus
		"shirt_hue_zero": 0.050,  # ~18 graus
		"shirt_sat_floor": 0.25,
	},
	{
		"scene": preload("res://assets/characters/passengers/passenger_02.glb"),
		"scale": 1.0,
		"rotation_degrees": 0.0,
		"position_offset": Vector3.ZERO,
		"shirt_hue": 0.9417,      # ~339 graus (moletom rosa original)
		"shirt_hue_full": 0.028,  # ~10 graus
		"shirt_hue_zero": 0.050,  # ~18 graus
		"shirt_sat_floor": 0.25,
	},
]

# Passo 4/5 do pedido: escolha estavel (nunca muda depois de escolhida para
# a mesma instancia) e bem distribuida (hash() espalha bem, evitando tanto
# "sempre alterna 1-2-1-2" quanto "quase todo mundo igual" por acidente).
# seed_value normalmente vem de hash(color_id + str(get_instance_id())),
# montado por Passenger3D.configure() -- ver ali.
static func pick_index(seed_value: int) -> int:
	return posmod(seed_value, PROFILES.size())
