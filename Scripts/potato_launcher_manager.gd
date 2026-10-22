extends RefCounted

signal fired(cell: Vector2i)
signal changed
const Catalog = preload("res://Scripts/content_catalog.gd")

const CAPACITY: int = 5
const FIRE_INTERVAL: float = 4.0
const UPGRADED_CAPACITY: int = 7
const UPGRADED_FIRE_INTERVAL: float = 2.0
const RANGE: float = 300.0
const ENGAGEMENT_TOP: float = -200.0
const DAMAGE_MULTIPLIER: float = 0.5
const UPGRADED_DAMAGE_MULTIPLIER: float = 1.0

var grid: RefCounted
var mining: RefCounted
var conveyors: RefCounted
var drills: RefCounted
var launchers: Dictionary = {}
var world: Node2D
var shots: Array[Dictionary] = []
var focused_enemy: WeakRef
var capacity: int = CAPACITY
var fire_interval: float = FIRE_INTERVAL
var damage_multiplier: float = DAMAGE_MULTIPLIER

func setup(grid_manager: RefCounted, mining_manager: RefCounted, conveyor_manager: RefCounted, drill_manager: RefCounted, world_node: Node2D) -> void:
	grid = grid_manager
	mining = mining_manager
	mining.launchers = self
	conveyors = conveyor_manager
	drills = drill_manager
	world = world_node

func dispose() -> void:
	grid = null
	mining = null
	conveyors = null
	drills = null
	world = null
	shots.clear()

func can_place(cell: Vector2i) -> bool:
	return ((grid.owned_tiles.has(cell) and (grid.is_valid_cell(cell) or grid.is_ammo_cell(cell))) or grid.defense_tiles.has(cell)) and cell != grid.sale_cell and not launchers.has(cell) and not conveyors.belts.has(cell) and not drills.drills.has(cell) and not mining.occupied_by_machine(cell) and mining.vein_at(cell) == "" and mining.nuggets_at(cell) == 0

func place(cell: Vector2i, level: int = 1) -> bool:
	if not can_place(cell):
		return false
	launchers[cell] = {"ammo": [], "cooldown": 0.0, "angle": -PI * 0.5, "level": clampi(level,1,2)}
	world.get("progression").record_launchers(launchers)
	changed.emit()
	return true

func level_at(cell: Vector2i) -> int:
	return int(launchers.get(cell,{}).get("level",1))

func capacity_at(cell: Vector2i) -> int:
	if launchers.get(cell,{}).has("weapon"): return int(Catalog.WEAPONS[launchers[cell]["weapon"]]["capacity"] * (1.0 + industrial_rank() * 0.25))
	return UPGRADED_CAPACITY if level_at(cell) == 2 else capacity

func interval_at(cell: Vector2i) -> float:
	if launchers.get(cell,{}).has("weapon"): return Catalog.WEAPONS[launchers[cell]["weapon"]]["interval"] * (1.0 - industrial_rank() * 0.1)
	return UPGRADED_FIRE_INTERVAL if level_at(cell) == 2 else fire_interval

func industrial_rank() -> int:
	return int(world.campaign.state.get("arsenal_rank",0)) if world.get("campaign") != null else 0

func can_fuse(source: Vector2i, destination: Vector2i) -> bool:
	if not world.get("progression").is_item_unlocked("launcher_2"): return false
	if source == destination or not launchers.has(source) or not launchers.has(destination): return false
	if level_at(source) != 1 or level_at(destination) != 1: return false
	if world.get("cycle").is_night: return false
	return launchers[source]["ammo"].size() + launchers[destination]["ammo"].size() <= UPGRADED_CAPACITY

func fuse(source: Vector2i, destination: Vector2i) -> bool:
	if not can_fuse(source,destination): return false
	var ammo: Array = launchers[destination]["ammo"].duplicate()
	ammo.append_array(launchers[source]["ammo"])
	launchers.erase(source)
	launchers.erase(destination)
	var construction: Node = world.get_node("Construction")
	construction.plans[destination] = {"item":"launcher_2", "direction":0, "paid":world.get("economy").LAUNCHER_PRICE * 2, "delivered":{}, "ammo":ammo}
	construction.changed.emit()
	changed.emit()
	return true

func move(source: Vector2i, destination: Vector2i) -> bool:
	if not launchers.has(source) or (source != destination and not can_place(destination)):
		return false
	var data: Dictionary = launchers[source]
	launchers.erase(source)
	launchers[destination] = data
	changed.emit()
	return true

func is_active_position(cell: Vector2i) -> bool:
	return grid.is_defense_position(cell) and grid.defense_tiles.has(cell)

func ammo_units(kind: String) -> int:
	if kind in ["bullet","grenade","rocket","battery"]: return 1
	if kind.get_slice("_",0) not in ["coal","copper","iron","gold"]: return 0
	if kind not in mining.ORE_KINDS or "_ingot" in kind: return 0
	return mining.ore_level(kind)

func round_kind(kind: String) -> String:
	return kind.get_slice("_",0)

func can_receive(cell: Vector2i, kind: String = "") -> bool:
	if not launchers.has(cell): return false
	var weapon: String = launchers[cell].get("weapon","")
	if not kind.is_empty():
		if not weapon.is_empty() and kind != Catalog.WEAPONS[weapon]["ammo"]: return false
		if weapon.is_empty() and kind in Catalog.AMMO: return false
	var units: int = 1 if kind.is_empty() else ammo_units(kind)
	return units > 0 and (launchers[cell]["ammo"] as Array).size() + units <= capacity_at(cell)

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell,kind) or ammo_units(kind) == 0: return false
	var ammo: Array = launchers[cell]["ammo"]
	for i in range(ammo_units(kind)): ammo.append(round_kind(kind))
	changed.emit()
	return true

func focus(enemy: Node2D) -> void:
	var previous: Node2D = focused_enemy.get_ref() if focused_enemy != null else null
	if is_instance_valid(previous):
		previous.focused = false
		previous.queue_redraw()
	focused_enemy = weakref(enemy)
	enemy.focused = true
	enemy.queue_redraw()

func in_range(cell: Vector2i, target_position: Vector2) -> bool:
	var reach: float = range_at(cell)
	return target_position.y >= ENGAGEMENT_TOP and grid.get_cell_rect(cell).get_center().distance_squared_to(target_position) <= reach * reach

func range_at(cell: Vector2i) -> float:
	var value: float = Catalog.WEAPONS[launchers[cell]["weapon"]]["range"] if launchers.get(cell,{}).has("weapon") else RANGE
	if world.cycle.is_night and world.cycle.day >= 21 and world.cycle.day % 7 == 0: value *= 0.85
	return value

func advance(delta: float) -> void:
	var visual_changed: bool = false
	for i in range(shots.size() - 1, -1, -1):
		shots[i]["time"] = float(shots[i]["time"]) - delta
		if float(shots[i]["time"]) <= 0.0:
			shots.remove_at(i)
			visual_changed = true
	if world.get("cycle").defeated:
		if visual_changed: changed.emit()
		return
	for key in launchers:
		var cell: Vector2i = key
		if not is_active_position(cell): continue
		var data: Dictionary = launchers[cell]
		data["cooldown"] = maxf(0.0, float(data["cooldown"]) - delta)
		var ammo: Array = data["ammo"]
		if ammo.is_empty() or float(data["cooldown"]) > 0.0:
			continue
		var center: Vector2 = grid.get_cell_rect(cell).get_center()
		var nearest: Node2D = null
		var distance_squared: float = range_at(cell) * range_at(cell)
		for candidate in world.get_tree().get_nodes_in_group("zombies"):
			if not candidate is Node2D or not is_instance_valid(candidate):
				continue
			var target: Node2D = candidate as Node2D
			var local_target: Vector2 = world.to_local(target.global_position)
			var distance: float = center.distance_squared_to(local_target)
			if in_range(cell,local_target) and distance < distance_squared:
				nearest = target
				distance_squared = distance
		var priority: Node2D = focused_enemy.get_ref() if focused_enemy != null else null
		if is_instance_valid(priority) and priority.is_in_group("zombies") and in_range(cell,world.to_local(priority.global_position)):
			nearest = priority
		if nearest == null:
			continue
		var target_position: Vector2 = world.to_local(nearest.global_position)
		data["angle"] = (target_position - center).angle()
		var kind: String = str(ammo.pop_front())
		data["cooldown"] = interval_at(cell)
		var damage: float = ammo_damage(kind, level_at(cell))
		var weapon: String = data.get("weapon","")
		if not weapon.is_empty():
			damage = Catalog.WEAPONS[weapon]["damage"] * (1.0 + industrial_rank() * 0.2)
			var radius: float = Catalog.WEAPONS[weapon]["radius"]
			if radius > 0:
				for other: Node2D in world.zombie_manager.living_zombies():
					if other != nearest and other.position.distance_squared_to(nearest.position) <= radius * radius:
						other.take_damage(damage * 0.65)
						if weapon == "tesla": other.apply_slow(2.0)
			if weapon == "tesla": nearest.apply_slow(2.0)
		if nearest.has_method("take_damage"):
			nearest.call("take_damage", damage)
		elif nearest.has_method("apply_damage"):
			nearest.call("apply_damage", damage)
		shots.append({"from": center, "to": target_position, "time": 0.45 if weapon in ["grenadier","rocketeer"] else 0.16, "kind": kind, "weapon":weapon})
		fired.emit(cell)
		visual_changed = true
	if visual_changed:
		changed.emit()

func ammo_damage(kind: String, level: int = 1) -> float:
	var multiplier: float = UPGRADED_DAMAGE_MULTIPLIER if level == 2 else damage_multiplier
	return float({"coal":1,"copper":2,"iron":3,"gold":4}.get(round_kind(kind),1)) * multiplier
