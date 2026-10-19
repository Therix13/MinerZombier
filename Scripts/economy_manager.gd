extends RefCounted

signal money_changed(amount: int)

const START_COINS := 100
const EXPANSION_PRICE := 500
const COAL_VEIN_PRICE := 100
const CONVEYOR_PRICE := 50
const DRILL_PRICE := 200
const LAUNCHER_PRICE := 200
const DEFENSE_TILE_PRICE := 1000
const COAL_SELL_PRICE := 3
const BRASS_VEIN_PRICE := 500
const BRASS_SELL_PRICE := 5
const IRON_VEIN_PRICE := 5000
const IRON_SELL_PRICE := 10
const GOLD_VEIN_PRICE := 50000
const GOLD_SELL_PRICE := 30

const NUGGET_SELL_PRICES := {
	"coal": [3, 8, 20, 50],
	"brass": [5, 15, 40, 100],
	"iron": [10, 30, 75, 175],
	"gold": [30, 75, 200, 500],
}
const INGOT_SELL_PRICES := {
	"brass": [150, 400, 1000, 2500],
	"iron": [350, 1000, 2500, 7500],
	"gold": [1000, 2500, 7500, 20000],
}

var coins: int = START_COINS
var developer_mode: bool = false

func sale_value(kind: String) -> int:
	var material: String = kind.get_slice("_", 0)
	var suffix: String = kind.get_slice("_", kind.get_slice_count("_") - 1)
	var level: int = int(suffix) if suffix.is_valid_int() else 1
	if "_ingot" in kind:
		return int(INGOT_SELL_PRICES.get(material, [135, 405, 1215, 3645])[clampi(level, 1, 4) - 1])
	var prices: Array = NUGGET_SELL_PRICES.get(material, NUGGET_SELL_PRICES["coal"])
	return int(prices[clampi(level, 1, 4) - 1])

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
