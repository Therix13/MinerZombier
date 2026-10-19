extends RefCounted

signal struck(cell: Vector2i)
signal changed
signal sale_completed(kind: String)
signal fusion_completed(kind: String)
signal vein_fused(cell: Vector2i)

const COAL_CLICKS := 5
const BRASS_CLICKS := 7
const ORE_KINDS := ["coal", "brass", "coal_2", "brass_2", "coal_3", "brass_3", "coal_4", "brass_4", "brass_ingot", "brass_ingot_2", "brass_ingot_3", "brass_ingot_4", "iron", "iron_2", "iron_3", "iron_4", "iron_ingot", "iron_ingot_2", "iron_ingot_3", "iron_ingot_4", "gold", "gold_2", "gold_3", "gold_4", "gold_ingot", "gold_ingot_2", "gold_ingot_3", "gold_ingot_4"]
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var drills: RefCounted
var conveyors: RefCounted
var compactors: Node2D
var furnaces: Node2D
var saws: Node2D
var grid: RefCounted
var mining_clicks: int = COAL_CLICKS
var drop_random := RandomNumberGenerator.new()
var coal_veins: Dictionary = {}
var brass_veins: Dictionary = {}
var gold_veins: Dictionary = {}
var gold_items: Dictionary = {"gold": {}, "gold_2": {}, "gold_3": {}, "gold_4": {}, "gold_ingot": {}, "gold_ingot_2": {}, "gold_ingot_3": {}, "gold_ingot_4": {}}
var iron_veins: Dictionary = {}
var iron_items: Dictionary = {"iron": {}, "iron_2": {}, "iron_3": {}, "iron_4": {}, "iron_ingot": {}, "iron_ingot_2": {}, "iron_ingot_3": {}, "iron_ingot_4": {}}
var construction: Node2D
var coal_nuggets: Dictionary = {}
var brass_nuggets: Dictionary = {}
var coal_level2_nuggets: Dictionary = {}
var brass_level2_nuggets: Dictionary = {}
var coal_level3_nuggets: Dictionary = {}
var brass_level3_nuggets: Dictionary = {}
var coal_level4_nuggets: Dictionary = {}
var brass_level4_nuggets: Dictionary = {}
var ingots: Dictionary = {"brass_ingot": {}, "brass_ingot_2": {}, "brass_ingot_3": {}, "brass_ingot_4": {}}

func setup(grid_manager: RefCounted) -> void:
	grid = grid_manager
	drop_random.randomize()

func dispose() -> void:
	drills = null
	conveyors = null
	compactors = null
	furnaces = null
	saws = null
	grid = null
	construction = null

func vein_at(cell: Vector2i) -> String:
	if coal_veins.has(cell):
		return "coal"
	if brass_veins.has(cell):
		return "brass"
	if iron_veins.has(cell): return "iron"
	if gold_veins.has(cell): return "gold"
	return ""

func veins_for(kind: String) -> Dictionary:
	return gold_veins if kind == "gold" else (iron_veins if kind == "iron" else (brass_veins if kind == "brass" else coal_veins))

func vein_level(cell: Vector2i) -> int:
	var data: Dictionary = veins_for(vein_at(cell)).get(cell, {})
	return clampi(int(data.get("level", 1)), 1, 4)

func can_fuse_veins(source: Vector2i, destination: Vector2i) -> bool:
	var kind: String = vein_at(source)
	if source == destination or kind.is_empty() or vein_at(destination) != kind: return false
	if vein_level(source) >= 4 or vein_level(source) != vein_level(destination): return false
	for cell: Vector2i in [source, destination]:
		if not grid.is_valid_cell(cell) or not grid.owned_tiles.has(cell) or cell == grid.sale_cell or grid.is_defense_position(cell): return false
		if nuggets_at(cell) > 0 or occupied_by_machine(cell) or (drills != null and drills.drills.has(cell)) or (conveyors != null and conveyors.belts.has(cell)): return false
	return true

func fuse_veins(source: Vector2i, destination: Vector2i) -> bool:
	if not can_fuse_veins(source, destination): return false
	var veins: Dictionary = veins_for(vein_at(source))
	var result: Dictionary = veins[destination].duplicate(true)
	result["level"] = vein_level(destination) + 1
	result["progress"] = 0
	veins.erase(source)
	veins[destination] = result
	vein_fused.emit(destination)
	changed.emit()
	return true

func rolled_vein_level(level: int, roll: float) -> int:
	var tier: int = clampi(level, 1, 4)
	return tier if tier == 1 or roll < 0.5 else tier - 1

func nuggets_at(cell: Vector2i) -> int:
	var count: int = 0
	for items: Dictionary in nugget_stores().values(): count += int(items.get(cell, 0))
	return count

func nugget_stores() -> Dictionary:
	var result: Dictionary = {"coal": coal_nuggets, "brass": brass_nuggets, "coal_2": coal_level2_nuggets, "brass_2": brass_level2_nuggets, "coal_3": coal_level3_nuggets, "brass_3": brass_level3_nuggets, "coal_4": coal_level4_nuggets, "brass_4": brass_level4_nuggets, "brass_ingot": ingots["brass_ingot"], "brass_ingot_2": ingots["brass_ingot_2"], "brass_ingot_3": ingots["brass_ingot_3"], "brass_ingot_4": ingots["brass_ingot_4"]}

	result.merge(iron_items)
	result.merge(gold_items)
	return result

func items_for(kind: String) -> Dictionary:
	return nugget_stores().get(kind, {})

func material_units(kind: String) -> int:
	return (8 if "_ingot" in kind else 1) * int(pow(2, ore_level(kind) - 1))

func ore_level(kind: String) -> int:
	var suffix: String = kind.get_slice("_", kind.get_slice_count("_") - 1)
	return int(suffix) if suffix.is_valid_int() else 1

func next_tier(kind: String) -> String:
	if kind not in ORE_KINDS or ore_level(kind) >= 4: return ""
	var level: int = ore_level(kind)
	var base: String = kind.trim_suffix("_%d" % level) if level > 1 else kind
	return base + "_" + str(level + 1)

func can_fuse(source: Vector2i, destination: Vector2i) -> bool:
	var kind: String = nugget_type(source)
	return source != destination and not next_tier(kind).is_empty() and nugget_type(destination) == kind and nuggets_at(source) == 1 and nuggets_at(destination) == 1 and grid.owned_tiles.has(destination) and not grid.is_defense_position(destination) and vein_at(destination).is_empty() and not occupied_by_machine(destination) and (drills == null or not drills.drills.has(destination))

func fuse(source: Vector2i, destination: Vector2i) -> bool:
	if not can_fuse(source, destination): return false
	var kind: String = nugget_type(source)
	remove_one_nugget(source, kind)
	remove_one_nugget(destination, kind)
	var result: String = next_tier(kind)
	items_for(result)[destination] = 1
	fusion_completed.emit(result)
	changed.emit()
	return true

func occupied_by_compactor(cell: Vector2i) -> bool:
	return is_instance_valid(compactors) and compactors.machines.has(cell)

func occupied_by_furnace(cell: Vector2i) -> bool:
	return is_instance_valid(furnaces) and furnaces.machines.has(cell)

func occupied_by_saw(cell: Vector2i) -> bool:
	return is_instance_valid(saws) and saws.machines.has(cell)

func occupied_by_machine(cell: Vector2i) -> bool:
	return occupied_by_saw(cell) or occupied_by_compactor(cell) or occupied_by_furnace(cell) or (is_instance_valid(construction) and construction.plans.has(cell))

func nugget_type(cell: Vector2i) -> String:
	var inventories: Dictionary = nugget_stores()
	for kind: String in ORE_KINDS:
		if int(inventories[kind].get(cell, 0)) > 0: return kind
	return ""

func can_place_vein(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and grid.is_valid_cell(cell) and not grid.is_defense_position(cell) and (drills == null or not drills.drills.has(cell)) and vein_at(cell) == "" and nuggets_at(cell) == 0 and (conveyors == null or not conveyors.belts.has(cell)) and cell != grid.sale_cell and not occupied_by_machine(cell)

func can_move_nugget(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and (grid.is_valid_cell(cell) or grid.is_ammo_cell(cell)) and not grid.is_defense_position(cell) and (drills == null or not drills.drills.has(cell)) and vein_at(cell) == "" and nuggets_at(cell) == 0 and not occupied_by_machine(cell)

func place_vein(cell: Vector2i, direction: int, kind: String = "coal") -> bool:
	if not grid.owned_tiles.has(cell) or not can_place_vein(cell):
		return false
	var dictionary: Dictionary = veins_for(kind)
	dictionary[cell] = {"direction": direction, "progress": 0, "level": 1}
	changed.emit()
	return true

func hardness(kind: String) -> int:
	return {"coal": COAL_CLICKS, "brass": BRASS_CLICKS, "iron": 9, "gold": 11}.get(kind, COAL_CLICKS)

func mine(cell: Vector2i) -> bool:
	var kind: String = vein_at(cell)
	if kind == "":
		return false
	var dictionary: Dictionary = veins_for(kind)
	var vein: Dictionary = dictionary[cell]
	var progress: int = int(vein["progress"]) + 1
	if progress >= hardness(kind):
		var destination: Vector2i = cell + DIRECTIONS[int(vein["direction"])]
		if not grid.owned_tiles.has(destination) or not can_move_nugget(destination):
			return false
		if conveyors != null and conveyors.belts.has(destination) and not conveyors.accepts_from(destination, cell):
			return false
		# Roll only after the output is valid; blocked mining never rerolls a drop.
		var level: int = vein_level(cell)
		var tier: int = rolled_vein_level(level, drop_random.randf()) if level > 1 else 1
		var dropped_kind: String = kind if tier == 1 else kind + "_" + str(tier)
		items_for(dropped_kind)[destination] = 1
		progress = 0
	vein["progress"] = progress
	dictionary[cell] = vein
	struck.emit(cell)
	changed.emit()
	return true

func move_vein(source: Vector2i, destination: Vector2i, direction: int) -> void:
	if can_fuse_veins(source, destination):
		fuse_veins(source, destination)
		return
	var kind: String = vein_at(source)
	if kind == "" or (destination != source and not can_place_vein(destination)):
		return
	var dictionary: Dictionary = veins_for(kind)
	var vein: Dictionary = dictionary[source].duplicate(true)
	vein["direction"] = direction
	dictionary.erase(source)
	dictionary[destination] = vein
	changed.emit()

func move_nugget(source: Vector2i, destination: Vector2i) -> void:
	var kind: String = nugget_type(source)
	if source == destination or kind == "":
		return
	if can_fuse(source, destination):
		fuse(source, destination)
		return
	if destination == grid.sale_cell:
		remove_one_nugget(source, kind)
		sale_completed.emit(kind)
		changed.emit()
		return
	if not can_move_nugget(destination):
		return
	remove_one_nugget(source, kind)
	var items: Dictionary = items_for(kind)
	items[destination] = 1
	changed.emit()

func remove_one_nugget(cell: Vector2i, kind: String = "coal") -> void:
	var items: Dictionary = items_for(kind)
	var amount: int = int(items.get(cell, 0))
	if amount <= 1:
		items.erase(cell)
	else:
		items[cell] = amount - 1
