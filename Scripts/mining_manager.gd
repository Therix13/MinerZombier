extends RefCounted

signal changed
signal sale_completed(kind: String)

const COAL_CLICKS := 7
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var drills: RefCounted
var conveyors: RefCounted
var grid: RefCounted
var mining_clicks: int = COAL_CLICKS
var coal_veins: Dictionary = {}
var brass_veins: Dictionary = {}
var coal_nuggets: Dictionary = {}
var brass_nuggets: Dictionary = {}

func setup(grid_manager: RefCounted) -> void:
	grid = grid_manager

func dispose() -> void:
	drills = null
	conveyors = null
	grid = null

func vein_at(cell: Vector2i) -> String:
	if coal_veins.has(cell):
		return "coal"
	if brass_veins.has(cell):
		return "brass"
	return ""

func nuggets_at(cell: Vector2i) -> int:
	return int(coal_nuggets.get(cell, 0)) + int(brass_nuggets.get(cell, 0))

func nugget_type(cell: Vector2i) -> String:
	if int(coal_nuggets.get(cell, 0)) > 0:
		return "coal"
	if int(brass_nuggets.get(cell, 0)) > 0:
		return "brass"
	return ""

func can_place_vein(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and grid.is_valid_cell(cell) and not grid.is_defense_position(cell) and (drills == null or not drills.drills.has(cell)) and vein_at(cell) == "" and nuggets_at(cell) == 0 and (conveyors == null or not conveyors.belts.has(cell)) and cell != grid.sale_cell

func can_move_nugget(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and (grid.is_valid_cell(cell) or grid.is_ammo_cell(cell)) and not grid.is_defense_position(cell) and (drills == null or not drills.drills.has(cell)) and vein_at(cell) == "" and nuggets_at(cell) == 0

func place_vein(cell: Vector2i, direction: int, kind: String = "coal") -> bool:
	if not grid.owned_tiles.has(cell) or not can_place_vein(cell):
		return false
	var dictionary: Dictionary = brass_veins if kind == "brass" else coal_veins
	dictionary[cell] = {"direction": direction, "progress": 0}
	changed.emit()
	return true

func mine(cell: Vector2i) -> bool:
	var kind: String = vein_at(cell)
	if kind == "":
		return false
	var dictionary: Dictionary = brass_veins if kind == "brass" else coal_veins
	var vein: Dictionary = dictionary[cell]
	var progress: int = int(vein["progress"]) + 1
	if progress >= mining_clicks:
		var destination: Vector2i = cell + DIRECTIONS[int(vein["direction"])]
		if not grid.owned_tiles.has(destination) or not can_move_nugget(destination):
			return false
		if conveyors != null and conveyors.belts.has(destination) and not conveyors.accepts_from(destination, cell):
			return false
		var items: Dictionary = brass_nuggets if kind == "brass" else coal_nuggets
		items[destination] = 1
		progress = 0
	vein["progress"] = progress
	dictionary[cell] = vein
	changed.emit()
	return true

func move_vein(source: Vector2i, destination: Vector2i, direction: int) -> void:
	var kind: String = vein_at(source)
	if kind == "" or (destination != source and not can_place_vein(destination)):
		return
	var dictionary: Dictionary = brass_veins if kind == "brass" else coal_veins
	var vein: Dictionary = dictionary[source].duplicate(true)
	vein["direction"] = direction
	dictionary.erase(source)
	dictionary[destination] = vein
	changed.emit()

func move_nugget(source: Vector2i, destination: Vector2i) -> void:
	var kind: String = nugget_type(source)
	if source == destination or kind == "":
		return
	if destination == grid.sale_cell:
		remove_one_nugget(source, kind)
		sale_completed.emit(kind)
		changed.emit()
		return
	if not can_move_nugget(destination):
		return
	remove_one_nugget(source, kind)
	var items: Dictionary = brass_nuggets if kind == "brass" else coal_nuggets
	items[destination] = 1
	changed.emit()

func remove_one_nugget(cell: Vector2i, kind: String = "coal") -> void:
	var items: Dictionary = brass_nuggets if kind == "brass" else coal_nuggets
	var amount: int = int(items.get(cell, 0))
	if amount <= 1:
		items.erase(cell)
	else:
		items[cell] = amount - 1
