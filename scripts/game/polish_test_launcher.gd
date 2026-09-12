extends Node

# Bootstrap MINIMO para a etapa de polimento visual (pedido explicito do
# usuario: uma fase/cena de teste separada, sem duplicar logica). Nao recria
# NADA do jogo: instancia a MESMA Game.tscn/GameController usada pelo fluxo
# real (a mesma cena que AppRouter.go_game() instancia), so que fora do
# Home/Mapa, e chama start_level() direto com a fase de teste abaixo.
#
# Nao mexe em AppRouter, Main.tscn, HomeScreen nem LevelMapScreen -- e uma
# porta de entrada extra e isolada, so para abrir esta fase sozinha no editor
# (ver instrucoes de uso: rodar scenes/game/PolishTest.tscn com F6).
const GAME_SCENE := preload("res://scenes/game/Game.tscn")

# levels/level_950.json e uma copia exata de levels/level_900.json (fase de
# QA ja validada nesta mesma sessao: capacidades 16/24/40, 7 veiculos, 160
# passageiros, 4 vagas, solucionavel), com o "id" trocado de 900 para 950
# para nao colidir com aquele arquivo. Nenhuma regra/capacidade/cor foi
# alterada -- e a mesma fase, com outro numero.
const POLISH_TEST_LEVEL_NUMBER := 950

func _ready() -> void:
	var game: GameController = GAME_SCENE.instantiate() as GameController
	add_child(game)
	game.start_level(POLISH_TEST_LEVEL_NUMBER)
