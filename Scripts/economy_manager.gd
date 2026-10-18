extends RefCounted

signal money_changed(amount: int)

const START_COINS := 500
const EXPANSION_PRICE := 500
const COAL_VEIN_PRICE := 100
const CONVEYOR_PRICE := 50
const DRILL_PRICE := 200
const LAUNCHER_PRICE := 200
const DEFENSE_TILE_PRICE := 100
const COAL_SELL_PRICE := 5
const BRASS_VEIN_PRICE := 150
const BRASS_SELL_PRICE := 7

var coins: int = START_COINS
var developer_mode: bool = false

func sale_value(kind: String) -> int:
	var base: int = BRASS_SELL_PRICE if kind.begins_with("brass") else COAL_SELL_PRICE
	# Four inputs plus a 50% processing bonus.
	return base * 6 if kind.ends_with("_2") else base

func can_afford(price: int) -> bool:
	return developer_mode or coins >= price

func spend(price: int) -> bool:
	if not can_afford(price):
		return false
	if developer_mode:
		return true
	coins -= price
	money_changed.emit(coins)
	return true

func add(amount: int) -> void:
	coins += amount
	money_changed.emit(coins)

func toggle_developer_mode() -> void:
	developer_mode = not developer_mode
	money_changed.emit(coins)
