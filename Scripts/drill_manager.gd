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

func setup(grid_manager: RefCounted, mining_manager: RefCounted, conveyor_manager: RefCounted) -> void:
	grid = grid_manager
	mining = mining_manager
	conveyors = conveyor_manager

func dispose() -> void:
	grid = null
	mining = null
	conveyors = null

func can_place(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and grid.is_valid_cell(cell) and not grid.is_defense_position(cell) and not drills.has(cell) and mining.vein_at(cell) == "" and mining.nuggets_at(cell) == 0 and not conveyors.belts.has(cell) and not mining.occupied_by_machine(cell)

func points_to_vein(cell: Vector2i, direction: int) -> bool:
	return mining.vein_at(cell + DIRECTIONS[direction]) != ""

func place(cell: Vector2i, direction: int) -> bool:
	if not grid.owned_tiles.has(cell) or not can_place(cell):
		return false
	drills[cell] = direction
	changed.emit()
	return true

func move(source: Vector2i, destination: Vector2i, direction: int) -> bool:
	if not drills.has(source):
		return false
	if source != destination and not can_place(destination):
		return false
	if not grid.is_valid_cell(destination):
		return false
	drills.erase(source)
	drills[destination] = direction
	changed.emit()
	return true

func advance(delta: float) -> void:
	accumulator += delta
	if accumulator < drill_interval:
		return
	var steps: int = mini(floori(accumulator / drill_interval), 8)
	accumulator = fmod(accumulator, drill_interval)
	for i in range(steps):
		tick()

func tick() -> void:
	for key in drills:
		var cell: Vector2i = key
		var target: Vector2i = cell + DIRECTIONS[int(drills[cell])]
		if mining.vein_at(target) != "":
			mining.mine(target)
