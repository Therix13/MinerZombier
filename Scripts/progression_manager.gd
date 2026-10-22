extends RefCounted

signal changed
signal items_unlocked(items: Array[String])

const ConstructionScript = preload("res://Scripts/construction_manager.gd")
const BASE_ITEMS := ["coal", "defense_platforms", "launcher"]
const NEXT_VEIN := {"coal":"copper", "copper":"iron", "iron":"gold"}

var unlocked: Dictionary = {}
var created_resources: Dictionary = {}
var completed_veins: Dictionary = {}
var mining: RefCounted
var developer_mode: bool = false:
	set(value):
		if developer_mode == value: return
		developer_mode = value
		changed.emit()

func setup(mining_manager: RefCounted) -> void:
	mining = mining_manager
	mining.resource_created.connect(record_resource)
	mining.vein_fused.connect(record_vein)
	mining.vein_placed.connect(record_placed_vein)

func dispose() -> void:
	if mining != null:
		mining.resource_created.disconnect(record_resource)
		mining.vein_fused.disconnect(record_vein)
		mining.vein_placed.disconnect(record_placed_vein)
	mining = null

func is_item_unlocked(item: String) -> bool:
	return item in BASE_ITEMS or unlocked.has(item) or (developer_mode and (item == "expansion" or item in NEXT_VEIN.values() or ConstructionScript.RECIPES.has(item)))

func has_launcher_pair(weapons: Dictionary) -> bool:
	var count: int = 0
	for weapon: Dictionary in weapons.values():
		if int(weapon.get("level",1)) == 1: count += 1
	return count >= 2

func record_launchers(weapons: Dictionary) -> void:
	if has_launcher_pair(weapons):
		var items: Array[String] = ["launcher_2"]
		unlock_items(items)

func record_night_completed(night: int) -> void:
	if night >= 2:
		var items: Array[String] = ["launcher_2"]
		unlock_items(items)

func restore_launcher_milestones(day: int, weapons: Dictionary, plans: Dictionary) -> void:
	# Recognize conditions already met in saves created before this unlock existed.
	if day >= 3 or has_launcher_pair(weapons): unlocked["launcher_2"] = true
	for weapon: Dictionary in weapons.values():
		if int(weapon.get("level",1)) == 2: unlocked["launcher_2"] = true
	for plan: Dictionary in plans.values():
		if plan.get("item") == "launcher_2": unlocked["launcher_2"] = true

func record_placed_vein(cell: Vector2i) -> void:
	if mining.vein_at(cell) == "copper":
		var items: Array[String] = ["expansion"]
		unlock_items(items)

func restore_vein_milestones() -> void:
	if created_resources.has("copper_ingot_3") or unlocked.has("straight"):
		unlocked["filter"] = true
	# Older saves did not track the first copper placement as a separate milestone.
	if not mining.copper_veins.is_empty() or completed_veins.has("copper") or unlocked.has("iron") or unlocked.has("gold"):
		unlocked["expansion"] = true

func record_vein(cell: Vector2i) -> void:
	record_placed_vein(cell)
	if mining.vein_level(cell) != 4: return
	var material: String = mining.vein_at(cell)
	completed_veins[material] = true
	if NEXT_VEIN.has(material):
		var next_items: Array[String] = [str(NEXT_VEIN[material])]
		unlock_items(next_items)

func record_resource(kind: String) -> void:
	created_resources[kind] = true
	var available: Array[String] = []
	for item: String in ConstructionScript.RECIPES:
		if item == "launcher_2": continue # Only obtained by fusing two level-one weapons.
		if unlocked.has(item): continue
		var recipe: Dictionary = ConstructionScript.RECIPES[item]
		var highest: int = 0
		for ingredient: String in recipe: highest = maxi(highest, mining.ore_level(ingredient))
		for ingredient: String in recipe:
			if mining.ore_level(ingredient) == highest and created_resources.has(ingredient):
				available.append(item)
				break
	unlock_items(available)

func unlock_items(items: Array[String]) -> void:
	var fresh: Array[String] = []
	for item: String in items:
		if unlocked.has(item): continue
		unlocked[item] = true
		fresh.append(item)
	if fresh.is_empty(): return
	changed.emit()
	# DEV already exposes the full catalog; retain milestones without redundant notices.
	if not developer_mode: items_unlocked.emit(fresh)
