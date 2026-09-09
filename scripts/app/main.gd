extends Node

# Ponto de entrada do jogo: so registra o "host" das telas no AppRouter e
# manda abrir a Home. Dali pra frente cada tela navega pelo AppRouter
# (Home -> Mapa -> Jogo -> volta ao Mapa ao vencer, etapa 9 da especificacao).
func _ready() -> void:
	print("Pega Passageiro - App carregado.")
	AppRouter.attach($ScreenHost)
	AppRouter.go_home()
