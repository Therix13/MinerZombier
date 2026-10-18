extends Node2D

signal changed

const PRICE: int = 350
const CAPACITY: int = 40
const PROCESS_TIME: float = 4.0
const FUEL_COST: int = 1
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

func place(cell: Vector2i) -> bool:
	if not can_place(cell): return false
	machines[cell] = {"fuel": 0, "input": "", "output": "", "elapsed": 0.0, "burning": false}
	changed.emit()
	return true

func can_receive_state(data: Dictionary, kind: String) -> bool:
	if kind == "coal_4": return int(data["fuel"]) + FUEL_VALUES[kind] <= CAPACITY
	return kind == "brass_4" and str(data.get("input", "")).is_empty() and str(data.get("output", "")).is_empty()

func can_receive(cell: Vector2i, kind: String) -> bool:
	return machines.has(cell) and can_receive_state(machines[cell], kind)

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell, kind): return false
	if kind == "coal_4":
		machines[cell]["fuel"] = int(machines[cell]["fuel"]) + FUEL_VALUES[kind]
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
		if kind == "coal_4": reserved["fuel"] = int(reserved["fuel"]) + FUEL_VALUES[kind]
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
			if int(data["fuel"]) < FUEL_COST: continue
			data["fuel"] = int(data["fuel"]) - FUEL_COST
			data["burning"] = true
			changed.emit()
		data["elapsed"] = minf(PROCESS_TIME, float(data.get("elapsed", 0.0)) + maxf(delta, 0.0))
		if float(data["elapsed"]) < PROCESS_TIME: continue
		data["input"] = ""
		data["output"] = "brass_ingot"
		data["elapsed"] = 0.0
		data["burning"] = false
		changed.emit()
		try_output(cell)

func try_output(cell: Vector2i) -> void:
	var kind: String = machines[cell].get("output", "")
	if kind.is_empty(): return
	var belts: RefCounted = game.get("conveyors")
	for direction: Vector2i in DIRECTIONS:
		var at: Vector2i = cell + direction
		if not belts.belts.has(at) or not mining.can_move_nugget(at) or not belts.accepts_from(at, cell): continue
		mining.items_for(kind)[at] = 1
		machines[cell]["output"] = ""
		mining.changed.emit()
		changed.emit()
		return

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
		draw_machine(grid.get_cell_rect(cell).get_center(), {"fuel": 0})
		draw_rect(grid.get_cell_rect(cell).grow(-1), Color("#f0c777") if can_place(cell) else Color("#df7770"), false, 2)
	if game.get("dragging_object") and game.get("held_object_type") == "furnace" and machines.has(game.get("held_object_cell")):
		draw_machine(game.get("drag_world_position"), machines[game.get("held_object_cell")])

func draw_machine(center: Vector2, data: Dictionary) -> void:
	draw_rect(Rect2(center - Vector2(21, 21), Vector2(42, 42)), Color("#392d28"))
	for y in range(4):
		for x in range(3):
			draw_rect(Rect2(center + Vector2(-19 + x * 13, -19 + y * 10), Vector2(12, 9)), Color("#94714e") if (x + y) % 2 == 0 else Color("#78604b"))
	draw_rect(Rect2(center + Vector2(-13, -7), Vector2(26, 22)), Color("#292c2d"))
	draw_rect(Rect2(center + Vector2(-10, -4), Vector2(20, 14)), Color("#d98a38") if int(data["fuel"]) > 0 else Color("#13171a"))
	for x in [-7, 0, 7]: draw_line(center + Vector2(x, -4), center + Vector2(x, 11), Color("#3b3830"), 2)
	draw_rect(Rect2(center + Vector2(-13, 17), Vector2(26, 2)), Color("#272b2c"))
	draw_rect(Rect2(center + Vector2(-13, 17), Vector2(26.0 * float(data["fuel"]) / CAPACITY, 2)), Color("#efba61"))
