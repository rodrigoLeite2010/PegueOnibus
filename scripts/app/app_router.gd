extends Node

# Autoload (ver [autoload] em project.godot). Etapa 9 da especificacao:
# Home, Mapa e Jogo passam a ser telas separadas; este singleton troca a
# tela ativa dentro do "ScreenHost" que main.gd registra, sem cada tela
# precisar saber instanciar/liberar a outra.

const HOME_SCENE := preload("res://scenes/ui/HomeScreen.tscn")
const MAP_SCENE := preload("res://scenes/ui/LevelMapScreen.tscn")
const GAME_SCENE := preload("res://scenes/game/Game.tscn")

var _host: Node = null
var _current: Node = null

func attach(host: Node) -> void:
	_host = host

func go_home() -> void:
	_replace(HOME_SCENE.instantiate())

func go_map() -> void:
	_replace(MAP_SCENE.instantiate())

func go_game(level_number: int) -> void:
	var instance: Node = GAME_SCENE.instantiate()
	_replace(instance)
	(instance as GameController).start_level(level_number)

func _replace(instance: Node) -> void:
	if _host == null:
		push_error("AppRouter.attach() precisa ser chamado antes de navegar.")
		return
	if _current != null:
		_host.remove_child(_current)
		_current.queue_free()
	_host.add_child(instance)
	_current = instance
