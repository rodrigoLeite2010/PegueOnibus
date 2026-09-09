extends Node

# Autoload (ver [autoload] em project.godot). Qualquer script chama
# `AudioManager.play_sfx("tap_valid")` sem precisar de referencia a um node.
# Guarda os efeitos sonoros como placeholders originais (sintetizados, sem
# nenhum asset de terceiros) em assets/audio/ - trocar por audio definitivo
# depois e so substituir os arquivos .ogg, sem tocar neste script.
#
# Secao 15 da especificacao: "Permitir desligar musica, efeitos e vibracao
# separadamente." sfx_enabled e vibration_enabled controlam algo que existe
# hoje; music_enabled fica guardado pra quando houver trilha musical (ainda
# nao existe, entao nao expomos esse toggle na UI - evita repetir o problema
# dos botoes que nao faziam nada).

const SFX_PATHS := {
	"tap_valid": "res://assets/audio/tap_valid.ogg",
	"blocked": "res://assets/audio/blocked.ogg",
	"passenger_board": "res://assets/audio/passenger_board.ogg",
	"vehicle_complete": "res://assets/audio/vehicle_complete.ogg",
	"coin": "res://assets/audio/coin.ogg",
	"win": "res://assets/audio/win.ogg",
	"game_over": "res://assets/audio/game_over.ogg",
}

const SETTINGS_PATH := "user://audio_settings.cfg"
const SFX_PLAYER_POOL_SIZE := 6

var sfx_enabled: bool = true
var music_enabled: bool = true
var vibration_enabled: bool = true

var _sfx_streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_player_index: int = 0

func _ready() -> void:
	_load_settings()
	for sfx_id: String in SFX_PATHS.keys():
		var path: String = SFX_PATHS[sfx_id]
		if ResourceLoader.exists(path):
			_sfx_streams[sfx_id] = load(path)
	for _i: int in range(SFX_PLAYER_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)

func play_sfx(sfx_id: String) -> void:
	if not sfx_enabled:
		return
	if not _sfx_streams.has(sfx_id):
		return
	var player: AudioStreamPlayer = _sfx_players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _sfx_players.size()
	player.stream = _sfx_streams[sfx_id]
	player.play()

func vibrate(duration_ms: int) -> void:
	if vibration_enabled:
		Input.vibrate_handheld(duration_ms)

func set_sfx_enabled(value: bool) -> void:
	sfx_enabled = value
	_save_settings()

func set_music_enabled(value: bool) -> void:
	music_enabled = value
	_save_settings()

func set_vibration_enabled(value: bool) -> void:
	vibration_enabled = value
	_save_settings()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	sfx_enabled = bool(config.get_value("audio", "sfx_enabled", true))
	music_enabled = bool(config.get_value("audio", "music_enabled", true))
	vibration_enabled = bool(config.get_value("audio", "vibration_enabled", true))

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("audio", "vibration_enabled", vibration_enabled)
	config.save(SETTINGS_PATH)
