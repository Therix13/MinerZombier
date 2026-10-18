extends Node

var game: Node2D
var grid: RefCounted

func _ready() -> void:
	game = get_parent() as Node2D
	grid = game.get("grid")
	game.get("renderer").interactions = self

func stores() -> Dictionary:
	return {"coal_vein": game.get("mining").coal_veins, "brass_vein": game.get("mining").brass_veins, "coal": game.get("mining").coal_nuggets, "brass": game.get("mining").brass_nuggets, "belt": game.get("conveyors").belts, "entry": game.get("conveyors").last_junction_entry, "drill": game.get("drills").drills, "launcher": game.get("launchers").launchers}

func cell_data(cell: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var maps: Dictionary = stores()
	for kind in maps:
		if maps[kind].has(cell):
			var value: Variant = maps[kind][cell]
			if kind in ["coal", "brass"] and int(value) <= 0:
				continue
			result[kind] = value.duplicate(true) if value is Dictionary or value is Array else value
	if result.has("belt"):
		result["belt"] = game.get("conveyors").belt_data(cell).duplicate(true)
	return result

func has_kind(cell: Vector2i, kind: String) -> bool:
	var data: Dictionary = cell_data(cell)
	if kind == "nugget": return data.has("coal") or data.has("brass")
	if kind == "vein": return data.has("coal_vein") or data.has("brass_vein")
	return data.has(kind)

func can_hold(cell: Vector2i, data: Dictionary) -> bool:
	if (not grid.owned_tiles.has(cell) and not grid.defense_tiles.has(cell)) or cell == grid.sale_cell:
		return false
	var buildings: int = 0
	for kind in ["coal_vein", "brass_vein", "drill", "belt", "launcher"]:
		if data.has(kind): buildings += 1
	if buildings > 1:
		return false
	var ore: bool = data.has("coal") or data.has("brass")
	if data.has("launcher"):
		return grid.defense_tiles.has(cell) and not ore
	if grid.is_defense_position(cell):
		return data.is_empty()
	if data.has("coal_vein") or data.has("brass_vein") or data.has("drill"):
		return grid.is_valid_cell(cell) and not ore
	return grid.is_valid_cell(cell) or grid.is_ammo_cell(cell)

func phase_allows() -> bool:
	var cycle: RefCounted = game.get("cycle")
	var shop: Control = game.get("shop")
	var victory: Control = game.get("night_victory_overlay")
	return not get_tree().paused and not cycle.is_night and not cycle.defeated and not shop.shop_open and not shop.shop_animating and (victory == null or not victory.visible)

func can_drop(kind: String, source: Vector2i, destination: Vector2i) -> bool:
	if not phase_allows() or (not grid.owned_tiles.has(source) and not grid.defense_tiles.has(source)) or not has_kind(source, kind) or not game.get("cycle").allows_interaction(kind, source, destination, true):
		return false
	if source == destination:
		return true
	if kind == "nugget":
		if destination == grid.sale_cell or game.get("launchers").can_receive(destination):
			return true
		if cell_data(destination).is_empty():
			return game.get("mining").can_move_nugget(destination)
	return can_hold(destination, cell_data(source)) and can_hold(source, cell_data(destination))

func swaps_contents(kind: String, source: Vector2i, destination: Vector2i) -> bool:
	return source != destination and not cell_data(destination).is_empty() and not (kind == "nugget" and (destination == grid.sale_cell or game.get("launchers").can_receive(destination))) and can_drop(kind, source, destination)

func rotate_data(data: Dictionary, direction: int) -> void:
	for kind in ["coal_vein", "brass_vein", "belt"]:
		if data.has(kind): data[kind]["direction"] = posmod(direction, 4)
	if data.has("drill"): data["drill"] = posmod(direction, 4)

func apply_cells(cells: Dictionary) -> void:
	# Both destinations are validated before either cell changes. Signals are
	# emitted only after the complete swap, so observers never see half a move.
	var maps: Dictionary = stores()
	for cell in cells:
		for kind in maps:
			maps[kind].erase(cell)
	for cell in cells:
		for kind in cells[cell]:
			maps[kind][cell] = cells[cell][kind]
	game.get("mining").changed.emit()
	game.get("conveyors").changed.emit()
	game.get("drills").changed.emit()
	game.get("launchers").changed.emit()

func drop(kind: String, source: Vector2i, destination: Vector2i, direction: int = 1) -> bool:
	if not can_drop(kind, source, destination):
		return false
	var mining: RefCounted = game.get("mining")
	var launchers: RefCounted = game.get("launchers")
	if kind == "nugget" and source != destination:
		if destination == grid.sale_cell:
			mining.move_nugget(source, destination)
			return true
		if launchers.can_receive(destination):
			var ore: String = mining.nugget_type(source)
			if launchers.receive(destination, ore):
				mining.remove_one_nugget(source, ore)
				mining.changed.emit()
				return true
			return false
		if cell_data(destination).is_empty():
			mining.move_nugget(source, destination)
			return true
	var origin: Dictionary = cell_data(source)
	if kind != "nugget": rotate_data(origin, direction)
	if source == destination:
		apply_cells({source: origin})
	else:
		apply_cells({source: cell_data(destination), destination: origin})
	return true

func world_cell(point: Vector2) -> Vector2i:
	return grid.world_to_cell(game.get_global_transform_with_canvas().affine_inverse() * point)

func pick_kind(cell: Vector2i, point: Vector2) -> String:
	var mining: RefCounted = game.get("mining")
	var local: Vector2 = game.get_global_transform_with_canvas().affine_inverse() * point
	if mining.nuggets_at(cell) > 0:
		# The center picks up ore; the edge (or Shift) picks up its conveyor.
		if not game.get("conveyors").belts.has(cell) or (local.distance_to(grid.get_cell_rect(cell).get_center()) <= 14.0 and not Input.is_key_pressed(KEY_SHIFT)):
			return "nugget"
	if mining.vein_at(cell) != "": return "vein"
	if game.get("drills").drills.has(cell): return "drill"
	if game.get("launchers").launchers.has(cell): return "launcher"
	if game.get("conveyors").belts.has(cell): return "belt"
	return ""

func clear_drag() -> void:
	game.set("holding_object", false)
	game.set("dragging_object", false)
	game.set("held_object_type", "")
	game.redraw_world()

func _input(event: InputEvent) -> void:
	if game.get("cycle").is_tutorial_active() or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.pressed or not game.get("holding_object"):
		return
	if not game.get("dragging_object") and event.position.distance_to(game.get("drag_start_position")) < 8.0:
		return
	var destination: Vector2i = world_cell(event.position)
	drop(game.get("held_object_type"), game.get("held_object_cell"), destination, game.get("placement_direction"))
	clear_drag()
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if game.get("cycle").is_tutorial_active() or not phase_allows() or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed or game.get("holding_object"):
		return
	if game.get("placing_coal") or game.get("placing_brass") or game.get("placing_belt") or game.get("placing_drill") or game.get("placing_launcher"):
		return
	var cell: Vector2i = world_cell(event.position)
	var kind: String = pick_kind(cell, event.position)
	if kind.is_empty(): return
	game.set("held_object_type", kind)
	game.set("held_object_cell", cell)
	game.set("holding_object", true)
	game.set("dragging_object", false)
	game.set("drag_start_position", event.position)
	game.set("drag_world_position", game.get_global_transform_with_canvas().affine_inverse() * event.position)
	var data: Dictionary = cell_data(cell)
	if kind == "vein":
		game.set("placement_direction", int(data["brass_vein" if data.has("brass_vein") else "coal_vein"]["direction"]))
	elif kind == "belt":
		game.set("placement_direction", int(data["belt"]["direction"]))
	elif kind == "drill":
		game.set("placement_direction", int(data["drill"]))
	get_viewport().set_input_as_handled()
