extends Node

# Autoload (ver [autoload] em project.godot). Etapa 10 da especificacao
# (roadmap oficial, item 10 - "Polimento": acessibilidade). Guarda se os
# simbolos de acessibilidade a daltonismo estao ligados - um simbolo unico
# por cor, mostrado junto com a cor nos lugares onde ela sozinha decide uma
# jogada (fila de passageiros, vagas de espera e seta de saida dos
# veiculos). Ligado por padrao, pode ser desligado nas Configuracoes (Home
# ou Pausa).

signal color_symbols_changed(enabled: bool)

const SAVE_PATH := "user://accessibility_settings.cfg"

const SYMBOLS := {
	"red": "▲",
	"blue": "●",
	"green": "■",
	"yellow": "★",
	"purple": "◆",
	"pink": "✚",
	"orange": "✖",
}

var color_symbols_enabled: bool = true

func _ready() -> void:
	_load()

func symbol_for(color_id: String) -> String:
	return String(SYMBOLS.get(color_id, ""))

func set_color_symbols_enabled(value: bool) -> void:
	if color_symbols_enabled == value:
		return
	color_symbols_enabled = value
	_save()
	color_symbols_changed.emit(color_symbols_enabled)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		color_symbols_enabled = true
		return
	color_symbols_enabled = bool(config.get_value("accessibility", "color_symbols_enabled", true))

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("accessibility", "color_symbols_enabled", color_symbols_enabled)
	config.save(SAVE_PATH)
