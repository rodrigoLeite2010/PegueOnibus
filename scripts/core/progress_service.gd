extends Node

# Autoload (ver [autoload] em project.godot). Etapa 9 da especificacao
# (roadmap oficial, item 9 - "Progressao"): "save local" mais completo.
# Wallet ja guarda as moedas e AudioManager ja guarda as opcoes de audio;
# este arquivo guarda so o progresso entre fases - ate onde o jogador
# desbloqueou e a melhor pontuacao em estrelas de cada fase - para
# alimentar a Home e o Mapa de fases.

const SAVE_PATH := "user://progress.cfg"
const FIRST_LEVEL := 1

var highest_unlocked: int = FIRST_LEVEL
var _stars_by_level: Dictionary = {}

func _ready() -> void:
	_load()

func get_highest_unlocked() -> int:
	return highest_unlocked

# Fase que o botao "Jogar" da Home deve abrir direto (a mais avancada que
# o jogador ainda pode jogar).
func get_next_playable_level() -> int:
	return highest_unlocked

func get_stars(level_number: int) -> int:
	return int(_stars_by_level.get(level_number, 0))

# Chamado pelo GameController quando uma fase e vencida: guarda a melhor
# pontuacao (nunca piora uma pontuacao ja salva) e libera a proxima fase.
func report_level_result(level_number: int, stars: int) -> void:
	var best: int = maxi(get_stars(level_number), stars)
	_stars_by_level[level_number] = best
	if level_number >= highest_unlocked:
		highest_unlocked = level_number + 1
	_save()

func _load() -> void:
	_stars_by_level.clear()
	highest_unlocked = FIRST_LEVEL
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	highest_unlocked = int(config.get_value("progress", "highest_unlocked", FIRST_LEVEL))
	if config.has_section("stars"):
		for key: String in config.get_section_keys("stars"):
			if key.is_valid_int():
				_stars_by_level[key.to_int()] = int(config.get_value("stars", key, 0))

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "highest_unlocked", highest_unlocked)
	for level_number: int in _stars_by_level.keys():
		config.set_value("stars", str(level_number), _stars_by_level[level_number])
	config.save(SAVE_PATH)
