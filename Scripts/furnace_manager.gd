extends Node2D

signal changed

const PRICE: int = 350
const CAPACITY: int = 40
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
	machines[cell] = {"fuel": 0, "fuel_items": []}
	changed.emit()
	return true

func can_receive(cell: Vector2i, kind: String) -> bool:
	return machines.has(cell) and FUEL_VALUES.has(kind) and int(machines[cell]["fuel"]) + int(FUEL_VALUES[kind]) <= CAPACITY

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell, kind): return false
	machines[cell]["fuel"] = int(machines[cell]["fuel"]) + int(FUEL_VALUES[kind])
	machines[cell]["fuel_items"].append(kind)
	changed.emit()
	return true

func remove_fuel(cell: Vector2i, kind: String) -> bool:
	if not machines.has(cell): return false
	var items: Array = machines[cell]["fuel_items"]
	var index: int = items.find(kind)
	if index < 0: return false
	items.remove_at(index)
	machines[cell]["fuel"] = int(machines[cell]["fuel"]) - int(FUEL_VALUES[kind])
	changed.emit()
	return true

func _process(_delta: float) -> void:
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
