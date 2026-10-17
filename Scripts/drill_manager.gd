extends RefCounted

signal changed

const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const DRILL_INTERVAL := 0.6

var grid: RefCounted
var mining: RefCounted
var conveyors: RefCounted
var drills: Dictionary = {}
var accumulator: float = 0.0
var drill_interval: float = DRILL_INTERVAL
var levels: Dictionary = {}
var timers: Dictionary = {}

func level_at(cell: Vector2i) -> int:
	return int(levels.get(cell, 1))

func interval_at(cell: Vector2i) -> float:
	return maxf(0.3, drill_interval - (level_at(cell) - 1) * 0.15)

func upgrade(cell: Vector2i) -> bool:
	if not drills.has(cell) or level_at(cell) >= 3:
		return false
	levels[cell] = level_at(cell) + 1
	timers[cell] = minf(float(timers.get(cell, 0.0)), interval_at(cell))
	changed.emit()
	return true

func setup(grid_manager: RefCounted, mining_manager: RefCounted, conveyor_manager: RefCounted) -> void:
	grid = grid_manager
	mining = mining_manager
	conveyors = conveyor_manager

func dispose() -> void:
	grid = null
	mining = null
	conveyors = null

func can_place(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and grid.is_valid_cell(cell) and not grid.is_defense_position(cell) and not drills.has(cell) and mining.vein_at(cell) == "" and mining.nuggets_at(cell) == 0 and not conveyors.belts.has(cell)

func points_to_vein(cell: Vector2i, direction: int) -> bool:
	return mining.vein_at(cell + DIRECTIONS[direction]) != ""

func place(cell: Vector2i, direction: int) -> bool:
	if not grid.owned_tiles.has(cell) or not can_place(cell):
		return false
	drills[cell] = direction
	levels[cell] = 1
	timers[cell] = 0.0
	changed.emit()
	return true

func move(source: Vector2i, destination: Vector2i, direction: int) -> bool:
	if not drills.has(source):
		return false
	if source != destination and not can_place(destination):
		return false
	if not grid.is_valid_cell(destination):
		return false
	var current_level: int = level_at(source)
	var timer: float = float(timers.get(source, 0.0))
	drills.erase(source)
	levels.erase(source)
	timers.erase(source)
	drills[destination] = direction
	levels[destination] = current_level
	timers[destination] = timer
	changed.emit()
	return true

func advance(delta: float) -> void:
	for key in drills:
		var cell: Vector2i = key
		var interval: float = interval_at(cell)
		var timer: float = float(timers.get(cell, 0.0)) + maxf(0.0, delta)
		var steps: int = mini(floori(timer / interval + 0.000001), 8)
		timers[cell] = maxf(0.0, timer - floori(timer / interval + 0.000001) * interval) if steps > 0 else timer
		for index in range(steps):
			work_at(cell)

func work_at(cell: Vector2i) -> void:
	var target: Vector2i = cell + DIRECTIONS[int(drills[cell])]
	if mining.vein_at(target) != "":
		mining.mine(target)

func tick() -> void:
	for key in drills:
		var cell: Vector2i = key
		work_at(cell)
