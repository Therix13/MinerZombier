extends RefCounted

signal money_changed(amount: int)

const START_COINS := 100
const EXPANSION_PRICE := 500
const COAL_VEIN_PRICE := 100
const CONVEYOR_PRICE := 50
const DRILL_PRICE := 200
const LAUNCHER_PRICE := 200
const DEFENSE_TILE_PRICE := 100
const COAL_SELL_PRICE := 5
const BRASS_VEIN_PRICE := 150
const BRASS_SELL_PRICE := 7
const IRON_VEIN_PRICE := 200
const IRON_SELL_PRICE := 9

var coins: int = START_COINS
var developer_mode: bool = false

func sale_value(kind: String) -> int:
	var base: int = IRON_SELL_PRICE if kind.begins_with("iron") else (BRASS_SELL_PRICE if kind.begins_with("brass") else COAL_SELL_PRICE)
	# A level-one ingot preserves the value of its level-four ore input.
	var suffix: String = kind.get_slice("_", kind.get_slice_count("_") - 1)
	var level: int = int(suffix) if suffix.is_valid_int() else 1
	return base * (27 if "_ingot" in kind else 1) * int(pow(3, level - 1))

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
