extends Node2D

signal changed

const PRICE: int = 300
const INPUT_COUNT: int = 4
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var game: Node2D
var grid: RefCounted
var mining: RefCounted
var machines: Dictionary = {}
var placing: bool = false
var paid: bool = false
var direction: int = 1

func _ready() -> void:
	game = get_parent() as Node2D
	grid = game.get("grid")
	mining = game.get("mining")
	mining.compactors = self
	changed.connect(queue_redraw)
	changed.connect(game.redraw_world)
	# Route sales here for current and older built-in scene controllers alike.
	# One sale event pays once, preserving the material and level of the item.
	for sale_signal: Signal in [mining.sale_completed, game.get("conveyors").sale_completed]:
		var old_handler := Callable(game, "on_sale_completed")
		if sale_signal.is_connected(old_handler): sale_signal.disconnect(old_handler)
		sale_signal.connect(on_sale_completed)

func _exit_tree() -> void:
	if mining != null and mining.compactors == self: mining.compactors = null

func on_sale_completed(kind: String) -> void:
	if kind not in mining.ORE_KINDS: return
	var economy: RefCounted = game.get("economy")
	var price: int = economy.BRASS_SELL_PRICE if kind.begins_with("brass") else economy.COAL_SELL_PRICE
	economy.add(price * mining.material_units(kind))
	game.get("progression").award_sale(kind)

func can_place(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and grid.is_valid_cell(cell) and not grid.is_defense_position(cell) and cell != grid.sale_cell and not machines.has(cell) and mining.vein_at(cell) == "" and mining.nuggets_at(cell) == 0 and not game.get("drills").drills.has(cell) and not game.get("conveyors").belts.has(cell) and not game.get("launchers").launchers.has(cell)

func place(cell: Vector2i, output_direction: int) -> bool:
	if not can_place(cell): return false
	machines[cell] = {"direction": posmod(output_direction, 4), "kind": "", "count": 0}
	changed.emit()
	return true

func can_receive(cell: Vector2i, kind: String) -> bool:
	if not machines.has(cell) or kind not in ["coal", "brass"]: return false
	var data: Dictionary = machines[cell]
	return int(data["count"]) < INPUT_COUNT and (data["kind"] == "" or data["kind"] == kind)

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell, kind): return false
	machines[cell]["kind"] = kind
	machines[cell]["count"] = int(machines[cell]["count"]) + 1
	changed.emit()
	return true

func process_outputs() -> void:
	for cell: Vector2i in machines:
		var data: Dictionary = machines[cell]
		if int(data["count"]) != INPUT_COUNT: continue
		var destination: Vector2i = cell + DIRECTIONS[int(data["direction"])]
		var kind: String = str(data["kind"]) + "_2"
		var launchers: RefCounted = game.get("launchers")
		var belts: RefCounted = game.get("conveyors")
		if destination == grid.sale_cell:
			data["count"] = 0
			data["kind"] = ""
			mining.sale_completed.emit(kind)
		elif launchers.can_receive(destination):
			if not launchers.receive(destination, kind): continue
			data["count"] = 0
			data["kind"] = ""
		elif mining.can_move_nugget(destination) and (not belts.belts.has(destination) or belts.accepts_from(destination, cell)):
			mining.items_for(kind)[destination] = 1
			data["count"] = 0
			data["kind"] = ""
		else:
			continue
		mining.changed.emit()
		changed.emit()

func buy() -> void:
	var shop: Control = game.get("shop")
	var cycle: RefCounted = game.get("cycle")
	if not shop.tutorial_allows_item("compactor") or not cycle.allows_action("buy_compactor") or cycle.is_night or cycle.defeated or placing or not game.get("progression").is_item_unlocked("compactor"): return
	if other_placement() or not game.get("economy").spend(PRICE): return
	paid = not game.get("economy").developer_mode
	placing = true
	direction = 1
	game.get_node("WorldInteractions").clear_drag()
	shop.close_shop()
	queue_redraw()

func cancel_placement() -> void:
	if not placing: return
	placing = false
	if paid: game.get("economy").add(PRICE)
	paid = false
	queue_redraw()

func other_placement() -> bool:
	return game.get("placing_coal") or game.get("placing_brass") or game.get("placing_belt") or game.get("placing_drill") or game.get("placing_launcher")

func _process(_delta: float) -> void:
	if placing and (other_placement() or not game.get("cycle").allows_action("buy_compactor") or game.get("cycle").is_night or game.get("cycle").defeated): cancel_placement()
	if not game.get("cycle").defeated: process_outputs()
	if placing or (game.get("holding_object") and game.get("held_object_type") == "compactor"): queue_redraw()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if placing and event.keycode == KEY_BACKSPACE:
		cancel_placement()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R:
		if placing:
			direction = posmod(direction + 1, 4)
		elif game.get("holding_object") and game.get("held_object_type") == "compactor":
			game.set("placement_direction", posmod(int(game.get("placement_direction")) + 1, 4))
			game.set("dragging_object", true)
		else: return
		queue_redraw()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not placing or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	if game.get("cycle").is_night or not game.get("cycle").allows_action("buy_compactor"): return
	if not game.get_node("WorldInteractions").phase_allows(): return
	var cell: Vector2i = grid.world_to_cell(game.get_local_mouse_position())
	if place(cell, direction):
		placing = false
		paid = false
		if Input.is_key_pressed(KEY_SHIFT) and not game.get("cycle").is_guided_tutorial_active() and game.get("economy").spend(PRICE):
			placing = true
			paid = not game.get("economy").developer_mode
	get_viewport().set_input_as_handled()

func _draw() -> void:
	if game == null: return
	for cell: Vector2i in machines:
		if game.get("dragging_object") and game.get("held_object_type") == "compactor" and cell == game.get("held_object_cell"): continue
		draw_machine(grid.get_cell_rect(cell).get_center(), machines[cell])
	if placing and not game.get("shop").shop_open and not game.get("shop").shop_animating:
		var cell: Vector2i = grid.world_to_cell(game.get_local_mouse_position())
		draw_machine(grid.get_cell_rect(cell).get_center(), {"direction": direction, "count": 0, "kind": ""})
		draw_rect(grid.get_cell_rect(cell).grow(-1), Color("#f0c777") if can_place(cell) else Color("#df7770"), false, 2)
	if game.get("dragging_object") and game.get("held_object_type") == "compactor" and machines.has(game.get("held_object_cell")):
		var data: Dictionary = machines[game.get("held_object_cell")].duplicate()
		data["direction"] = game.get("placement_direction")
		draw_machine(game.get("drag_world_position"), data)

func draw_machine(center: Vector2, data: Dictionary) -> void:
	var rect := Rect2(center - Vector2(21, 21), Vector2(42, 42))
	draw_rect(rect, Color("#292b2d"))
	draw_rect(rect.grow(-3), Color("#697377"))
	draw_rect(rect, Color("#d1ad6b"), false, 2)
	draw_rect(Rect2(center + Vector2(-12, -14), Vector2(24, 5)), Color("#c2a064"))
	draw_rect(Rect2(center + Vector2(-12, 6), Vector2(24, 5)), Color("#c2a064"))
	draw_line(center + Vector2(-16, -9), center + Vector2(-16, 10), Color("#333c40"), 4)
	draw_line(center + Vector2(16, -9), center + Vector2(16, 10), Color("#333c40"), 4)
	var count: int = int(data["count"])
	for index in range(INPUT_COUNT):
		draw_circle(center + Vector2(-12 + index * 8, 16), 2, Color("#eac978") if index < count else Color("#303638"))
	if count > 0:
		draw_circle(center + Vector2(0, -1), 5, Color("#dbb36b") if data["kind"] == "brass" else Color("#29292d"))
	var output := Vector2(DIRECTIONS[int(data["direction"])])
	var tip := center + output * 21
	var side := Vector2(-output.y, output.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - output * 7 + side * 4, tip - output * 7 - side * 4]), Color("#ffe084"))
