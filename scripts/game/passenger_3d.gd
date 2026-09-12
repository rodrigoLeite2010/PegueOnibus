class_name Passenger3D
extends Node3D

# Etapa 10A: wrapper do novo personagem 3D (passenger_01.glb), usado por
# PassengerController._build_glb_visual() quando use_glb_visual == true.
# Isola o GLB do resto do codigo: nenhum outro arquivo referencia
# "passenger_01.glb" diretamente (ver auditoria em ENTREGA_ETAPA_10A.md).
#
# VisualRoot concentra TODA correcao de escala/rotacao do modelo (Passos 4/5
# do pedido) -- nunca o proprio Passenger3D nem o GLB original, que continua
# intocado. Isso deixa o wrapper pronto para, em etapas futuras: trocar de
# personagem (trocar so o filho de VisualRoot), variar escala/rotacao por
# instancia, aplicar variacoes de material/cor (Etapa 10B) e, se um modelo
# futuro vier com Skeleton3D/AnimationPlayer, encontra-los via os metodos
# abaixo sem precisar mudar quem usa Passenger3D.

@onready var visual_root: Node3D = $VisualRoot

func get_visual_root() -> Node3D:
	return visual_root

func get_skeleton() -> Skeleton3D:
	return _find_first(visual_root, "Skeleton3D") as Skeleton3D

func get_animation_player() -> AnimationPlayer:
	return _find_first(visual_root, "AnimationPlayer") as AnimationPlayer

func _find_first(node: Node, class_name_hint: String) -> Node:
	for child: Node in node.get_children():
		if child.is_class(class_name_hint):
			return child
		var found: Node = _find_first(child, class_name_hint)
		if found != null:
			return found
	return null
