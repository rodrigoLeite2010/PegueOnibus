class_name Passenger3D
extends Node3D

# Etapa 10A: wrapper do novo personagem 3D (passenger_01.glb), usado por
# PassengerController._build_glb_visual() quando use_glb_visual == true.
# Isola o GLB do resto do codigo: nenhum outro arquivo referencia
# "passenger_01.glb" diretamente (ver auditoria em ENTREGA_ETAPA_10A.md /
# ENTREGA_ETAPA_10A_1.md).
#
# VisualRoot concentra TODA correcao de escala/rotacao do modelo (Passos 4/5
# do pedido) -- nunca o proprio Passenger3D nem o GLB original, que continua
# intocado. Isso deixa o wrapper pronto para, em etapas futuras: trocar de
# personagem (trocar so o filho de VisualRoot), variar escala/rotacao por
# instancia, aplicar variacoes de material/cor (Etapa 10B) e, se um modelo
# futuro vier com Skeleton3D/AnimationPlayer, encontra-los via os metodos
# abaixo sem precisar mudar quem usa Passenger3D.
#
# ETAPA 10A.1: o passenger_01.glb foi substituido por uma versao retopologizada
# (~10 mil triangulos) com Auto Rig humanoide -- agora tem Armature/Skeleton3D/
# AnimationPlayer com 3 clipes (preset_biped_idle/walk/run, ver auditoria).
# Este wrapper ganhou play_idle()/play_walk()/play_run() para que
# PassengerController toque a animacao certa em cada momento (esperando na
# fila = idle, reorganizando = walk, correndo pro veiculo = run), SEM usar
# root motion: a posicao/trajetoria continua 100% controlada pelos Tweens de
# PassengerController (ver step_to/walk_to_and_board*) -- a animacao aqui e
# puramente visual, "in place".
#
# NOTA (Etapa 10A.1): get_visual_root()/get_animation_player()/get_skeleton()
# resolvem sob demanda via get_node_or_null()/busca na arvore local, em vez
# de @onready. PassengerController chama has_animations()/play_idle() logo
# apos instantiate()+add_child(), no MESMO frame -- @onready so roda quando
# o no recebe NOTIFICATION_READY (proximo frame nesse caso), entao um
# @onready aqui ficaria null bem no instante em que _build_glb_visual()
# precisa dele. A resolucao sob demanda funciona porque a hierarquia
# VisualRoot -> passenger_01 ja existe assim que o PackedScene e
# instanciado, independente de estar ou nao dentro da SceneTree.
#
# ETAPA 10C: Passenger3D.tscn NAO tem mais o .glb pre-instanciado dentro de
# VisualRoot (era so passenger_01 antes). Agora VisualRoot comeca vazio e
# configure() e quem instancia o modelo escolhido (passenger_01 OU
# passenger_02, ver passenger_visual_variants.gd) como filho dele, em tempo
# de execucao -- e por isso que configure() precisa ser chamado ANTES de
# qualquer outro metodo (get_skeleton/get_animation_player/
# get_mesh_instance/set_passenger_color/has_animations/play_*), ver
# PassengerController._build_glb_visual(). A escolha do modelo acontece
# uma unica vez por instancia (Passo 4 do pedido) e nunca muda depois --
# nenhum outro metodo deste arquivo troca o filho de VisualRoot.

const ANIM_IDLE := "preset_biped_idle"
const ANIM_WALK := "preset_biped_walk"
const ANIM_RUN := "preset_biped_run"

# ETAPA 10B: recolore SOMENTE a camiseta (ver auditoria em
# ENTREGA_ETAPA_10B.md -- o GLB tem um unico MeshInstance3D/uma unica
# surface/um unico material, com pele/cabelo/camiseta/calca/tenis todos na
# MESMA textura albedo, entao nao existe separacao por material/surface
# para duplicar cor por parte do corpo). O shader identifica a camiseta em
# tempo real pelo matiz original dela (amarelo) e troca so matiz/saturacao
# dentro dessa faixa, preservando o valor (V do HSV) -- ou seja, mantem
# sombra/dobra/brilho da textura, so muda a cor. Pele/cabelo/calca/tenis tem
# matiz bem diferente e nunca entram na mascara. Ver comentarios completos
# em assets/vfx/passenger_shirt_tint.gdshader.
const SHIRT_SHADER := preload("res://assets/vfx/passenger_shirt_tint.gdshader")

# As 3 animacoes vem do GLB com loop_mode NONE (Tripo nao marcou loop no
# export). Sao forcadas para LOOP_LINEAR na primeira vez que qualquer
# instancia as usa -- como o recurso Animation e compartilhado por todas as
# instancias do MESMO modelo (mesma AnimationLibrary vindo do cache de
# import), isto so precisa acontecer uma vez por recurso, nao por
# passageiro.
# ETAPA 10C: isto ERA um unico `static var bool` (fazia sentido com um
# modelo so). Com passenger_01 E passenger_02 tendo cada um seu proprio
# recurso Animation (nomes iguais, "preset_biped_idle" etc., mas objetos
# DIFERENTES -- um por GLB), um bool unico configuraria o loop do
# passenger_01 e depois pularia o passenger_02 achando que "ja fez",
# deixando as animacoes da menina em loop_mode NONE (paravam no ultimo
# frame em vez de repetir). Agora e um Dictionary chaveado pelo proprio
# recurso Animation, entao cada recurso (de cada modelo) e configurado
# exatamente uma vez, independente de quantos modelos existam.
static var _configured_loop_animations: Dictionary = {}

var _animation_player_cache: AnimationPlayer
var _animation_player_resolved: bool = false

# ETAPA 10B: mesh/material sao resolvidos e o ShaderMaterial e montado uma
# UNICA vez por instancia (na primeira chamada de set_passenger_color()) --
# nunca por frame, nunca durante a animacao (Passo 9 do pedido). Chamadas
# seguintes so atualizam o parametro "tint_color" do MESMO ShaderMaterial.
var _mesh_instance_cache: MeshInstance3D
var _mesh_instance_resolved: bool = false
var _shirt_material: ShaderMaterial

# ETAPA 10C: perfil (Dictionary de PassengerVisualVariants.PROFILES) da
# variante escolhida para ESTA instancia -- ver configure(). Fica vazio
# ({}) ate configure() rodar; set_passenger_color() usa os campos
# "shirt_hue*" dele para montar a mascara certa para o modelo certo.
var _variant_profile: Dictionary = {}
var _variant_configured: bool = false

func get_visual_root() -> Node3D:
	return get_node_or_null("VisualRoot") as Node3D

# ETAPA 10C (Passo 4/5 do pedido): escolhe UMA VEZ (guard _variant_configured
# -- chamadas repetidas nao fazem nada) qual modelo (passenger_01 ou
# passenger_02) esta instancia usa, e instancia esse .glb dentro de
# VisualRoot. `seed_key` normalmente e o color_id do passageiro (PassengerController
# ja tem essa informacao disponivel -- nao precisamos inventar nada novo nem
# PassengerController precisa saber que isto influencia o MODELO escolhido,
# so que "ajuda a variar visualmente", ver Passo 8: ele so pede idle/walk/
# run, nunca pergunta se e o modelo masculino ou feminino).
#
# A escolha usa hash(seed_key + instance_id) em vez de randf()/randi() cru:
# como o mesmo hash sempre da o mesmo resultado para a MESMA instancia, o
# modelo nunca muda sozinho entre chamadas (mesmo se configure() fosse
# chamado de novo por engano) -- e o instance_id garante que passageiros
# diferentes, mesmo com o mesmo color_id, quase sempre caem em ramos
# diferentes do hash, dando a distribuicao ~50/50 pedida (Passo 5) sem
# risco de "todo mundo ficou igual por acidente".
func configure(seed_key: String) -> void:
	if _variant_configured:
		return
	_variant_configured = true

	var profiles: Array = PassengerVisualVariants.PROFILES
	var seed_value: int = hash(seed_key + str(get_instance_id()))
	var variant_index: int = PassengerVisualVariants.pick_index(seed_value)
	_variant_profile = profiles[variant_index]

	var visual_root: Node3D = get_visual_root()
	if visual_root == null:
		return
	var model_scene: PackedScene = _variant_profile.get("scene") as PackedScene
	if model_scene == null:
		return
	var model_instance: Node3D = model_scene.instantiate() as Node3D
	if model_instance == null:
		return
	visual_root.add_child(model_instance)

	# Passo 2 do pedido: correcao de escala/rotacao/posicao POR MODELO,
	# sempre em cima de VisualRoot -- nunca no proprio GLB. Auditoria da
	# Etapa 10C mediu passenger_01 e passenger_02 com altura/pes
	# praticamente identicos (ver passenger_visual_variants.gd), entao os
	# dois perfis atuais usam 1.0/0.0/ZERO -- os campos existem prontos
	# para quando isso mudar.
	visual_root.scale = Vector3.ONE * float(_variant_profile.get("scale", 1.0))
	visual_root.rotation_degrees.y = float(_variant_profile.get("rotation_degrees", 0.0))
	visual_root.position = _variant_profile.get("position_offset", Vector3.ZERO)

	# O modelo acabou de ser criado -- qualquer cache antigo (nao deveria
	# existir nenhum neste ponto, mas fica defensivo) precisa ser
	# reavaliado contra a arvore nova.
	_mesh_instance_resolved = false
	_mesh_instance_cache = null
	_animation_player_resolved = false
	_animation_player_cache = null

func get_skeleton() -> Skeleton3D:
	var visual_root: Node3D = get_visual_root()
	if visual_root == null:
		return null
	return _find_first(visual_root, "Skeleton3D") as Skeleton3D

func get_mesh_instance() -> MeshInstance3D:
	if not _mesh_instance_resolved:
		var visual_root: Node3D = get_visual_root()
		_mesh_instance_cache = (_find_first(visual_root, "MeshInstance3D") as MeshInstance3D) if visual_root != null else null
		_mesh_instance_resolved = true
	return _mesh_instance_cache

# ETAPA 10B (Passo 4 do pedido): PassengerController continua sendo a fonte
# de verdade do color_id -> Color (COLOR_MAP); aqui so recebemos a Color ja
# resolvida, para Passenger3D continuar isolado do resto do jogo (mesma
# filosofia do resto deste arquivo -- nenhum outro script referencia
# "passenger_01.glb" diretamente, e este wrapper tambem nao precisa saber o
# que e um "color_id" logico, so pintar a camiseta na cor recebida).
#
# Passo 5 do pedido: cada Passenger3D monta o SEU PROPRIO ShaderMaterial
# (nunca reaproveita/edita o material compartilhado do GLB original) e usa
# set_surface_override_material() -- isso, por si so, ja impede qualquer
# instancia de influenciar a cor de outra (mudar um passageiro para
# vermelho nunca reaplica no material-base compartilhado, entao os outros
# nunca "viram vermelho junto"). O material original do MeshInstance3D
# nunca e modificado.
func set_passenger_color(shirt_color: Color) -> void:
	var mesh_instance: MeshInstance3D = get_mesh_instance()
	if mesh_instance == null:
		return

	if _shirt_material == null:
		var original_material: Material = mesh_instance.get_active_material(0)
		var albedo_tex: Texture2D
		var normal_tex: Texture2D
		var orm_tex: Texture2D
		if original_material is StandardMaterial3D:
			var std_mat := original_material as StandardMaterial3D
			albedo_tex = std_mat.albedo_texture
			normal_tex = std_mat.normal_texture
			orm_tex = std_mat.roughness_texture
		elif original_material is ORMMaterial3D:
			var orm_mat := original_material as ORMMaterial3D
			albedo_tex = orm_mat.albedo_texture
			normal_tex = orm_mat.normal_texture
			orm_tex = orm_mat.orm_texture
		else:
			# Material do GLB nao e o esperado (ex.: um modelo futuro sem
			# textura albedo) -- nao ha o que recolorir com seguranca, entao
			# preserva o material original em vez de arriscar um shader sem
			# as texturas certas.
			return

		var material := ShaderMaterial.new()
		material.shader = SHIRT_SHADER
		material.set_shader_parameter("albedo_texture", albedo_tex)
		material.set_shader_parameter("normal_texture", normal_tex)
		material.set_shader_parameter("orm_texture", orm_tex)
		# ETAPA 10C: cada variante tem sua propria roupa/matiz original (ver
		# passenger_visual_variants.gd) -- nunca assume que a faixa medida
		# para o passenger_01 (camiseta amarela) serve para o passenger_02
		# (moletom rosa) ou qualquer modelo futuro.
		material.set_shader_parameter("shirt_hue", _variant_profile.get("shirt_hue", 0.1211))
		material.set_shader_parameter("shirt_hue_full", _variant_profile.get("shirt_hue_full", 0.028))
		material.set_shader_parameter("shirt_hue_zero", _variant_profile.get("shirt_hue_zero", 0.050))
		material.set_shader_parameter("shirt_sat_floor", _variant_profile.get("shirt_sat_floor", 0.25))
		_shirt_material = material
		# set_surface_override_material() e por instancia de MeshInstance3D --
		# nunca toca o recurso Material compartilhado do GLB original.
		mesh_instance.set_surface_override_material(0, _shirt_material)

	_shirt_material.set_shader_parameter("tint_color", shirt_color)

func get_animation_player() -> AnimationPlayer:
	if not _animation_player_resolved:
		var visual_root: Node3D = get_visual_root()
		_animation_player_cache = (_find_first(visual_root, "AnimationPlayer") as AnimationPlayer) if visual_root != null else null
		_animation_player_resolved = true
	return _animation_player_cache

# true quando o modelo atual tem as 3 animacoes esperadas. PassengerController
# usa isto para decidir entre tocar animacao esqueletal ou (se um modelo
# futuro vier sem rig, como o da Etapa 10A original) cair de volta no bounce
# procedural de _body_root -- nunca os dois ao mesmo tempo.
func has_animations() -> bool:
	var ap: AnimationPlayer = get_animation_player()
	return ap != null and ap.has_animation(ANIM_IDLE)

# Passo 3: idle em loop enquanto o passageiro espera na fila. `desync_offset`
# (segundos, qualquer valor >= 0) e usado como ponto de partida dentro do
# clipe para que uma fila inteira nao fique perfeitamente sincronizada -- ver
# PassengerController._build_glb_visual(), que sorteia um valor por boneco.
func play_idle(desync_offset: float = 0.0) -> void:
	var ap: AnimationPlayer = get_animation_player()
	if ap == null or not ap.has_animation(ANIM_IDLE):
		return
	_ensure_loop_configured(ap)
	if ap.current_animation != ANIM_IDLE:
		ap.play(ANIM_IDLE)
	var length: float = ap.get_animation(ANIM_IDLE).length
	if length > 0.0 and desync_offset > 0.0:
		ap.seek(fmod(desync_offset, length), true)

# Passo 4: caminhada enquanto o boneco se reorganiza na fila (step_to()).
func play_walk() -> void:
	var ap: AnimationPlayer = get_animation_player()
	if ap == null or not ap.has_animation(ANIM_WALK):
		return
	_ensure_loop_configured(ap)
	if ap.current_animation != ANIM_WALK:
		ap.play(ANIM_WALK)

# Passo 5: corrida durante walk_to_and_board()/walk_to_and_board_polished().
func play_run() -> void:
	var ap: AnimationPlayer = get_animation_player()
	if ap == null or not ap.has_animation(ANIM_RUN):
		return
	_ensure_loop_configured(ap)
	if ap.current_animation != ANIM_RUN:
		ap.play(ANIM_RUN)

func _ensure_loop_configured(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for anim_name: String in [ANIM_IDLE, ANIM_WALK, ANIM_RUN]:
		if not ap.has_animation(anim_name):
			continue
		var anim: Animation = ap.get_animation(anim_name)
		if _configured_loop_animations.has(anim):
			continue
		anim.loop_mode = Animation.LOOP_LINEAR
		_configured_loop_animations[anim] = true

func _find_first(node: Node, class_name_hint: String) -> Node:
	for child: Node in node.get_children():
		if child.is_class(class_name_hint):
			return child
		var found: Node = _find_first(child, class_name_hint)
		if found != null:
			return found
	return null
