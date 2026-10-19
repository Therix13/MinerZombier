extends Node2D

const ArtAtlas = preload("res://Scripts/art_atlas.gd")
var rasterizing: bool = false

signal smelted(cell: Vector2i)
signal changed

const PRICE: int = 350
const CAPACITY: int = 40
const PROCESS_TIME: float = 4.0
const FUEL_COST: int = 20
const IRON_FUEL_COST: int = 40
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const FUEL_VALUES := {"coal": 1, "coal_2": 3, "coal_3": 8, "coal_4": 20}
var machines: Dictionary = {}
var game: Node2D
var mining: RefCounted
var grid: RefCounted

func _ready() -> void:
	game = get_parent() as Node2D
	mining = game.get("mining")
	grid = game.get("grid")
	mining.furnaces = self
	changed.connect(queue_redraw)
	changed.connect(game.redraw_world)

func _exit_tree() -> void:
	if mining != null and mining.furnaces == self: mining.furnaces = null

func can_place(cell: Vector2i) -> bool:
	return mining.can_move_nugget(cell) and grid.is_valid_cell(cell) and cell != grid.sale_cell and not game.get("conveyors").belts.has(cell) and not game.get("launchers").launchers.has(cell)

func place(cell: Vector2i, output_direction: int = 0) -> bool:
	if not can_place(cell): return false
	machines[cell] = {"fuel": 0, "input": "", "output": "", "elapsed": 0.0, "burning": false, "direction": posmod(output_direction, 4)}
	changed.emit()
	return true

func can_receive_state(data: Dictionary, kind: String) -> bool:
	if FUEL_VALUES.has(kind): return int(data["fuel"]) < CAPACITY
	return kind in ["copper_4", "iron_4", "gold_4"] and str(data.get("input", "")).is_empty() and str(data.get("output", "")).is_empty()

func can_receive(cell: Vector2i, kind: String) -> bool:
	return machines.has(cell) and can_receive_state(machines[cell], kind)

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell, kind): return false
	if FUEL_VALUES.has(kind):
		machines[cell]["fuel"] = mini(CAPACITY, int(machines[cell]["fuel"]) + int(FUEL_VALUES[kind]))
		machines[cell].erase("fuel_items")
	else:
		machines[cell]["input"] = kind
		machines[cell]["elapsed"] = 0.0
		machines[cell]["burning"] = false
	changed.emit()
	return true

func plan_inputs(cell: Vector2i, candidates: Array) -> Array:
	# Reserve both fuel space and the material slot before belts remove anything.
	var reserved: Dictionary = machines[cell].duplicate(true)
	var accepted: Array = []
	for candidate: Dictionary in candidates:
		var kind: String = candidate["kind"]
		if not can_receive_state(reserved, kind): continue
		accepted.append(candidate)
		if FUEL_VALUES.has(kind): reserved["fuel"] = mini(CAPACITY, int(reserved["fuel"]) + int(FUEL_VALUES[kind]))
		else: reserved["input"] = kind
	return accepted

func stored_items(cell: Vector2i) -> Dictionary:
	var items: Dictionary = {}
	if not machines.has(cell): return items
	for slot in ["input", "output"]:
		var kind: String = machines[cell].get(slot, "")
		if not kind.is_empty(): items[kind] = int(items.get(kind, 0)) + 1
	return items

func remove_material(cell: Vector2i, kind: String) -> bool:
	if not machines.has(cell): return false
	for slot in ["input", "output"]:
		if machines[cell].get(slot, "") != kind: continue
		machines[cell][slot] = ""
		machines[cell]["elapsed"] = 0.0
		machines[cell]["burning"] = false
		changed.emit()
		return true
	return false

func process_smelting(delta: float) -> void:
	for cell: Vector2i in machines:
		var data: Dictionary = machines[cell]
		if not str(data.get("output", "")).is_empty():
			try_output(cell)
			continue
		if str(data.get("input", "")).is_empty(): continue
		if not data.get("burning", false):
			var cost: int = IRON_FUEL_COST if data["input"] == "iron_4" else FUEL_COST
			if int(data["fuel"]) < cost: continue
			data["fuel"] = int(data["fuel"]) - cost
			data["burning"] = true
			changed.emit()
		data["elapsed"] = minf(PROCESS_TIME, float(data.get("elapsed", 0.0)) + maxf(delta, 0.0))
		queue_redraw()
		if float(data["elapsed"]) < PROCESS_TIME: continue
		data["output"] = str(data["input"]).get_slice("_", 0) + "_ingot"
		data["input"] = ""
		mining.resource_created.emit(str(data["output"]))
		smelted.emit(cell)
		data["elapsed"] = PROCESS_TIME
		data["burning"] = false
		changed.emit()
		try_output(cell)

func try_output(cell: Vector2i) -> void:
	var kind: String = machines[cell].get("output", "")
	if kind.is_empty(): return
	var belts: RefCounted = game.get("conveyors")
	var at: Vector2i = cell + DIRECTIONS[posmod(int(machines[cell].get("direction", 0)), 4)]
	if at == grid.sale_cell or not mining.can_move_nugget(at): return
	if belts.belts.has(at) and not belts.accepts_from(at, cell): return
	mining.items_for(kind)[at] = 1
	machines[cell]["output"] = ""
	machines[cell]["elapsed"] = 0.0
	mining.changed.emit()
	changed.emit()

func _input(event: InputEvent) -> void:
	if game == null or not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_R: return
	var mover: Node = game.get_node_or_null("WorldInteractions")
	if mover == null or not mover.phase_allows() or (game.get("cycle").is_night and not mover.placing_furnace): return
	if not mover.placing_furnace and not (game.get("holding_object") and game.get("held_object_type") == "furnace"): return
	game.set("placement_direction", posmod(int(game.get("placement_direction")) + 1, 4))
	if game.get("holding_object"): game.set("dragging_object", true)
	queue_redraw()
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not game.get("cycle").defeated: process_smelting(delta)
	var mover: Node = game.get_node_or_null("WorldInteractions")
	if mover != null and (mover.placing_furnace or game.get("held_object_type") == "furnace"): queue_redraw()

func _draw() -> void:
	if game == null: return
	for cell: Vector2i in machines:
		if game.get("dragging_object") and game.get("held_object_type") == "furnace" and game.get("held_object_cell") == cell: continue
		draw_machine(grid.get_cell_rect(cell).get_center(), machines[cell])
	var mover: Node = game.get_node_or_null("WorldInteractions")
	if mover != null and mover.placing_furnace and not game.get("shop").shop_open and not game.get("shop").shop_animating:
		var cell: Vector2i = grid.world_to_cell(game.get_local_mouse_position())
		draw_machine(grid.get_cell_rect(cell).get_center(), {"fuel": 0, "direction": game.get("placement_direction")})
		draw_rect(grid.get_cell_rect(cell).grow(-1), Color("#f0c777") if can_place(cell) else Color("#df7770"), false, 2)
	if game.get("dragging_object") and game.get("held_object_type") == "furnace" and machines.has(game.get("held_object_cell")):
		var data: Dictionary = machines[game.get("held_object_cell")].duplicate()
		data["direction"] = game.get("placement_direction")
		draw_machine(game.get("drag_world_position"), data)

func draw_machine(center: Vector2, data: Dictionary) -> void:
	var cached: bool = not rasterizing and ArtAtlas.paint(self, "furnace:%d:%d" % [int(data.get("direction", 0)), 1 if int(data["fuel"]) > 0 else 0], center)
	if not cached:
		draw_rect(Rect2(center - Vector2(21, 21), Vector2(42, 42)), Color("#392d28"))
		for y in range(4):
			for x in range(3):
				draw_rect(Rect2(center + Vector2(-19 + x * 13, -19 + y * 10), Vector2(12, 9)), Color("#94714e") if (x + y) % 2 == 0 else Color("#78604b"))
		draw_rect(Rect2(center + Vector2(-13, -7), Vector2(26, 22)), Color("#292c2d"))
		draw_rect(Rect2(center + Vector2(-10, -4), Vector2(20, 14)), Color("#d98a38") if int(data["fuel"]) > 0 else Color("#13171a"))
		for x in [-7, 0, 7]: draw_line(center + Vector2(x, -4), center + Vector2(x, 11), Color("#3b3830"), 2)
	draw_rect(Rect2(center + Vector2(-13, 17), Vector2(26, 2)), Color("#272b2c"))
	draw_rect(Rect2(center + Vector2(-13, 17), Vector2(26.0 * float(data["fuel"]) / CAPACITY, 2)), Color("#efba61"))

	# Smelting progress is separate from the thin fuel gauge below the fire.
	if data.get("burning", false) or not str(data.get("output", "")).is_empty():
		var progress: float = clampf(float(data.get("elapsed", 0.0)) / PROCESS_TIME, 0.0, 1.0)
		draw_rect(Rect2(center + Vector2(-16, -17), Vector2(32, 4)), Color("#292c2d"))
		draw_rect(Rect2(center + Vector2(-16, -17), Vector2(32 * progress, 4)), Color("#f6bc5c"))
	if cached: return
	var outward: Vector2 = Vector2(DIRECTIONS[posmod(int(data.get("direction", 0)), 4)])
	var side := Vector2(-outward.y, outward.x)
	var tip: Vector2 = center + outward * 22
	draw_line(center + outward * 14, tip - outward * 3, Color("#f7d57b"), 3)
	draw_colored_polygon(PackedVector2Array([tip, tip - outward * 8 + side * 5, tip - outward * 8 - side * 5]), Color("#f7d57b"))
