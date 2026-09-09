extends Node

# Autoload (ver [autoload] em project.godot). Contador de moedas cosmetico -
# secao 14 da especificacao: "Contador de moedas com icone 3D/2D proprio,
# numero animado e feedback ao receber recompensa." Ainda NAO existe loja,
# gasto ou economia real: isso e etapa de Progressao (roadmap oficial do
# documento, item 9), fora do escopo deste passo. Guarda apenas o total,
# persistido localmente.

signal coins_changed(new_total: int)

const SAVE_PATH := "user://wallet.cfg"
const WIN_REWARD := 20

var total_coins: int = 0

func _ready() -> void:
	_load()

func award_win_bonus() -> int:
	add_coins(WIN_REWARD)
	return WIN_REWARD

func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	total_coins += amount
	_save()
	coins_changed.emit(total_coins)

# Usado pela Dica (etapa 9 - Progressao): primeiro gasto real de moedas do
# jogo. Retorna false e nao mexe no saldo se nao houver moedas suficientes.
func spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true
	if total_coins < amount:
		return false
	total_coins -= amount
	_save()
	coins_changed.emit(total_coins)
	return true

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		total_coins = 0
		return
	total_coins = int(config.get_value("wallet", "total_coins", 0))

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("wallet", "total_coins", total_coins)
	config.save(SAVE_PATH)
