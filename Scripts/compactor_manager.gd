extends Node2D

const ArtAtlas = preload("res://Scripts/art_atlas.gd")
var rasterizing: bool = false

signal changed

const PRICE: int = 300
const REQUIRED_POINTS: int = 8
const MAX_POINTS: int = 15
const FAST_PROCESS_TIME: float = 1.0
const PROCESS_TIME: float = 4.0
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
	economy.add(economy.sale_value(kind))

func can_place(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and grid.is_valid_cell(cell) and not grid.is_defense_position(cell) and cell != grid.sale_cell and not mining.occupied_by_machine(cell) and mining.vein_at(cell) == "" and mining.nuggets_at(cell) == 0 and not game.get("drills").drills.has(cell) and not game.get("conveyors").belts.has(cell) and not game.get("launchers").launchers.has(cell)

func place(cell: Vector2i, output_direction: int) -> bool:
	if not can_place(cell): return false
	machines[cell] = {"direction": posmod(output_direction, 4), "kind": "", "points": 0, "inventory": {}, "elapsed": 0.0}
	changed.emit()
	return true

func family(kind: String) -> String:
	if kind not in mining.ORE_KINDS or kind in preload("res://Scripts/content_catalog.gd").AMMO: return ""
	var suffix: String = kind.get_slice("_",kind.get_slice_count("_") - 1)
	return kind.trim_suffix("_" + suffix) if suffix.is_valid_int() else kind

func input_points(kind: String) -> int:
	return 0 if family(kind).is_empty() else 1 << (mining.ore_level(kind) - 1)

func process_time(data: Dictionary) -> float:
	return FAST_PROCESS_TIME if int(data.get("inventory",{}).get(str(data["kind"]) + "_4",0)) > 0 else PROCESS_TIME

func is_compacting(data: Dictionary) -> bool:
	return int(data["points"]) >= REQUIRED_POINTS and float(data["elapsed"]) < process_time(data)

func accepts(data: Dictionary, kind: String) -> bool:
	var material: String = family(kind)
	return not material.is_empty() and int(data["points"]) < REQUIRED_POINTS and (data["kind"] == "" or data["kind"] == material)

func can_receive(cell: Vector2i, kind: String) -> bool:
	return machines.has(cell) and accepts(machines[cell],kind)

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell,kind): return false
	var data: Dictionary = machines[cell]
	data["kind"] = family(kind)
	data["points"] = int(data["points"]) + input_points(kind)
	data["inventory"][kind] = int(data["inventory"].get(kind,0)) + 1
	changed.emit()
	return true

func plan_inputs(cell: Vector2i, candidates: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var reserved: Dictionary = machines[cell].duplicate(true)
	for candidate: Dictionary in candidates:
		var kind: String = candidate["kind"]
		if not accepts(reserved,kind): continue
		result.append(candidate)
		reserved["kind"] = family(kind)
		reserved["points"] = int(reserved["points"]) + input_points(kind)
	return result

func stored_items(cell: Vector2i) -> Dictionary:
	return machines[cell]["inventory"].duplicate()

func remove_material(cell: Vector2i, kind: String) -> bool:
	if not machines.has(cell): return false
	var data: Dictionary = machines[cell]
	if int(data["inventory"].get(kind,0)) <= 0: return false
	data["inventory"][kind] -= 1
	if data["inventory"][kind] == 0: data["inventory"].erase(kind)
	data["points"] -= input_points(kind)
	data["elapsed"] = 0.0
	if data["points"] == 0: data["kind"] = ""
	changed.emit()
	return true

func consume_cycle(data: Dictionary) -> void:
	var remaining: int = REQUIRED_POINTS
	for tier in range(4,0,-1):
		var kind: String = str(data["kind"]) + ("_" + str(tier) if tier > 1 else "")
		var units: int = 1 << (tier - 1)
		var used: int = mini(int(data["inventory"].get(kind,0)),remaining / units)
		if used == 0: continue
		data["inventory"][kind] -= used
		if data["inventory"][kind] == 0: data["inventory"].erase(kind)
		remaining -= used * units
	data["points"] -= REQUIRED_POINTS
	data["elapsed"] = 0.0
	if data["points"] == 0: data["kind"] = ""

func process_outputs(delta: float = 0.0) -> void:
	for cell: Vector2i in machines:
		var data: Dictionary = machines[cell]
		if int(data["points"]) < REQUIRED_POINTS: continue
		var duration: float = process_time(data)
		var previous_time: float = float(data["elapsed"])
		data["elapsed"] = minf(duration,previous_time + maxf(delta,0.0))
		if data["elapsed"] != previous_time: queue_redraw()
		if float(data["elapsed"]) < duration: continue
		var destination: Vector2i = cell + DIRECTIONS[int(data["direction"])]
		var kind: String = str(data["kind"]) + "_4"
		var launchers: RefCounted = game.get("launchers")
		var belts: RefCounted = game.get("conveyors")
		if destination == grid.sale_cell:
			consume_cycle(data)
			mining.sale_completed.emit(kind)
		elif launchers.can_receive(destination,kind):
			if not launchers.receive(destination,kind): continue
			consume_cycle(data)
		elif mining.can_move_nugget(destination) and (not belts.belts.has(destination) or belts.accepts_from(destination,cell)):
			mining.items_for(kind)[destination] = 1
			consume_cycle(data)
		else:
			continue
		mining.resource_created.emit(kind)
		mining.fusion_completed.emit(kind)
		mining.changed.emit()
		changed.emit()

func buy() -> void:
	game.get_node("WorldInteractions").select_item("compactor")

func cancel_placement() -> void:
	if not placing: return
	placing = false
	if paid: game.get("economy").add(PRICE)
	paid = false
	queue_redraw()

func other_placement() -> bool:
	return game.get("placing_coal") or game.get("placing_copper") or game.get("placing_belt") or game.get("placing_drill") or game.get("placing_launcher")

func _process(delta: float) -> void:
	if placing and (other_placement() or not game.get("cycle").allows_action("buy_compactor") or game.get("cycle").defeated): cancel_placement()
	if not game.get("cycle").defeated: process_outputs(delta)
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
	var cell: Vector2i = grid.world_to_cell(game.get_local_mouse_position())
	game.get_node("WorldInteractions").place_selected(cell)
	get_viewport().set_input_as_handled()

func _draw() -> void:
	if game == null: return
	for cell: Vector2i in machines:
		if game.get("dragging_object") and game.get("held_object_type") == "compactor" and cell == game.get("held_object_cell"): continue
		draw_machine(grid.get_cell_rect(cell).get_center(), machines[cell])
	if placing and not game.get("shop").shop_open and not game.get("shop").shop_animating:
		var cell: Vector2i = grid.world_to_cell(game.get_local_mouse_position())
		draw_machine(grid.get_cell_rect(cell).get_center(), {"direction": direction, "points": 0, "inventory": {}, "kind": ""})
		draw_rect(grid.get_cell_rect(cell).grow(-1), Color("#f0c777") if can_place(cell) else Color("#df7770"), false, 2)
	if game.get("dragging_object") and game.get("held_object_type") == "compactor" and machines.has(game.get("held_object_cell")):
		var data: Dictionary = machines[game.get("held_object_cell")].duplicate()
		data["direction"] = game.get("placement_direction")
		draw_machine(game.get("drag_world_position"), data)

func draw_machine(center: Vector2, data: Dictionary) -> void:
	var cached: bool = not rasterizing and ArtAtlas.paint(self, "compactor:%d" % int(data["direction"]), center)
	if not cached:
		var rect := Rect2(center - Vector2(21, 21), Vector2(42, 42))
		draw_rect(rect, Color("#292b2d"))
		draw_rect(rect.grow(-3), Color("#697377"))
		draw_rect(rect, Color("#d1ad6b"), false, 2)
		draw_rect(Rect2(center + Vector2(-12, -14), Vector2(24, 5)), Color("#c2a064"))
		draw_rect(Rect2(center + Vector2(-12, 6), Vector2(24, 5)), Color("#c2a064"))
		draw_line(center + Vector2(-16, -9), center + Vector2(-16, 10), Color("#333c40"), 4)
		draw_line(center + Vector2(16, -9), center + Vector2(16, 10), Color("#333c40"), 4)
	var points: int = int(data.get("points",0))
	draw_rect(Rect2(center + Vector2(-10,12),Vector2(20,8)),Color("#697377"))
	for index in range(REQUIRED_POINTS):
		draw_circle(center + Vector2(-14 + index * 4,16),1.3,Color("#eac978") if index < points else Color("#303638"))
	if points > 0:
		draw_circle(center + Vector2(0,-1),5,Color("#c77c48") if str(data["kind"]).begins_with("copper") else Color("#29292d"))
	if points >= REQUIRED_POINTS:
		draw_rect(Rect2(center + Vector2(-12,-3),Vector2(24,4)),Color("#303638"))
		draw_rect(Rect2(center + Vector2(-12,-3),Vector2(24 * clampf(float(data["elapsed"]) / process_time(data),0,1),4)),Color("#eac978"))
	if cached: return
	var output := Vector2(DIRECTIONS[int(data["direction"])])
	var tip := center + output * 21
	var side := Vector2(-output.y, output.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - output * 7 + side * 4, tip - output * 7 - side * 4]), Color("#ffe084"))
