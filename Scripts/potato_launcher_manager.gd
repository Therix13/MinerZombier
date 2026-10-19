extends RefCounted

signal fired(cell: Vector2i)
signal changed

const CAPACITY: int = 5
const FIRE_INTERVAL: float = 4.0
const RANGE: float = 500.0
const DAMAGE_MULTIPLIER: float = 0.5

var grid: RefCounted
var mining: RefCounted
var conveyors: RefCounted
var drills: RefCounted
var launchers: Dictionary = {}
var world: Node2D
var shots: Array[Dictionary] = []
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
	changed.emit()
	return true

func level_at(cell: Vector2i) -> int:
	return int(launchers.get(cell,{}).get("level",1))

func can_fuse(source: Vector2i, destination: Vector2i) -> bool:
	if source == destination or not launchers.has(source) or not launchers.has(destination): return false
	if level_at(source) != 1 or level_at(destination) != 1: return false
	if world.get("cycle").is_night: return false
	return launchers[source]["ammo"].size() + launchers[destination]["ammo"].size() <= capacity

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

func can_receive(cell: Vector2i, kind: String = "") -> bool:
	return (kind.is_empty() or kind in ["coal", "copper"]) and launchers.has(cell) and (launchers[cell]["ammo"] as Array).size() < capacity

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell, kind) or kind not in ["coal", "copper"]:
		return false
	var ammo: Array = launchers[cell]["ammo"]
	ammo.append(kind)
	changed.emit()
	return true

func advance(delta: float) -> void:
	var visual_changed: bool = false
	for i in range(shots.size() - 1, -1, -1):
		shots[i]["time"] = float(shots[i]["time"]) - delta
		if float(shots[i]["time"]) <= 0.0:
			shots.remove_at(i)
			visual_changed = true
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
		var distance_squared: float = RANGE * RANGE
		for candidate in world.get_tree().get_nodes_in_group("zombies"):
			if not candidate is Node2D or not is_instance_valid(candidate):
				continue
			var target: Node2D = candidate as Node2D
			var distance: float = center.distance_squared_to(world.to_local(target.global_position))
			if distance < distance_squared:
				nearest = target
				distance_squared = distance
		if nearest == null:
			continue
		var target_position: Vector2 = world.to_local(nearest.global_position)
		data["angle"] = (target_position - center).angle()
		var kind: String = str(ammo.pop_front())
		data["cooldown"] = fire_interval
		var damage: float = ammo_damage(kind)
		if nearest.has_method("take_damage"):
			nearest.call("take_damage", damage)
		elif nearest.has_method("apply_damage"):
			nearest.call("apply_damage", damage)
		shots.append({"from": center, "to": target_position, "time": 0.16, "kind": kind})
		fired.emit(cell)
		visual_changed = true
	if visual_changed:
		changed.emit()

func ammo_damage(kind: String) -> float:
	return (2.0 if kind.begins_with("copper") else 1.0) * mining.material_units(kind) * damage_multiplier
