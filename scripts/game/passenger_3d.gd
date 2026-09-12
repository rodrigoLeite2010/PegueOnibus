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

const ANIM_IDLE := "preset_biped_idle"
const ANIM_WALK := "preset_biped_walk"
const ANIM_RUN := "preset_biped_run"

# As 3 animacoes vem do GLB com loop_mode NONE (Tripo nao marcou loop no
# export). Sao forcadas para LOOP_LINEAR na primeira vez que qualquer
# instancia as usa -- como o recurso Animation e compartilhado por todas as
# instancias de Passenger3D (mesmo AnimationLibrary vindo do cache de import),
# isto so precisa acontecer uma vez por execucao do jogo, nao por passageiro.
static var _loop_configured: bool = false

var _animation_player_cache: AnimationPlayer
var _animation_player_resolved: bool = false

func get_visual_root() -> Node3D:
	return get_node_or_null("VisualRoot") as Node3D

func get_skeleton() -> Skeleton3D:
	var visual_root: Node3D = get_visual_root()
	if visual_root == null:
		return null
	return _find_first(visual_root, "Skeleton3D") as Skeleton3D

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
	if _loop_configured or ap == null:
		return
	for anim_name: String in [ANIM_IDLE, ANIM_WALK, ANIM_RUN]:
		if ap.has_animation(anim_name):
			ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_loop_configured = true

func _find_first(node: Node, class_name_hint: String) -> Node:
	for child: Node in node.get_children():
		if child.is_class(class_name_hint):
			return child
		var found: Node = _find_first(child, class_name_hint)
		if found != null:
			return found
	return null
