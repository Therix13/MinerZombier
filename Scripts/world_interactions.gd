extends Node

var game: Node2D
var grid: RefCounted
var shift_batch: bool = false
var placing_resource: String = ""
var placing_furnace: bool = false
var placing_iron: bool = false
var placing_saw: bool = false

func _ready() -> void:
	game = get_parent() as Node2D
	grid = game.get("grid")
	game.get("renderer").interactions = self

func stores() -> Dictionary:
	var result: Dictionary = {"coal_vein": game.get("mining").coal_veins, "brass_vein": game.get("mining").brass_veins, "belt": game.get("conveyors").belts, "entry": game.get("conveyors").last_junction_entry, "drill": game.get("drills").drills, "launcher": game.get("launchers").launchers, "compactor": game.get_node("Compactors").machines}
	result["blueprint"] = game.get_node("Construction").plans
	result["iron_vein"] = game.get("mining").iron_veins
	result["saw"] = game.get_node("Saws").machines
	result["furnace"] = game.get_node("Furnaces").machines
	result.merge(game.get("mining").nugget_stores())
	return result

func cell_data(cell: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var maps: Dictionary = stores()
	for kind in maps:
		if maps[kind].has(cell):
			var value: Variant = maps[kind][cell]
			if kind in game.get("mining").ORE_KINDS and int(value) <= 0:
				continue
			result[kind] = value.duplicate(true) if value is Dictionary or value is Array else value
	if result.has("belt"):
		result["belt"] = game.get("conveyors").belt_data(cell).duplicate(true)
	return result

func has_kind(cell: Vector2i, kind: String) -> bool:
	var data: Dictionary = cell_data(cell)
	if kind == "nugget": return game.get("mining").nuggets_at(cell) > 0
	if kind == "vein": return data.has("coal_vein") or data.has("brass_vein") or data.has("iron_vein")
	return data.has(kind)

func can_hold(cell: Vector2i, data: Dictionary) -> bool:
	if (not grid.owned_tiles.has(cell) and not grid.defense_tiles.has(cell)) or cell == grid.sale_cell:
		return false
	var buildings: int = 0
	for kind in ["coal_vein", "brass_vein", "iron_vein", "blueprint", "drill", "belt", "launcher", "compactor", "furnace", "saw"]:
		if data.has(kind): buildings += 1
	if buildings > 1:
		return false
	var ore: bool = false
	for kind: String in game.get("mining").ORE_KINDS:
		if data.has(kind): ore = true
	if data.has("launcher"):
		return grid.defense_tiles.has(cell) and not ore
	if grid.is_defense_position(cell):
		return data.is_empty()
	if data.has("coal_vein") or data.has("brass_vein") or data.has("iron_vein") or data.has("drill") or data.has("compactor") or data.has("furnace") or data.has("saw"):
		return grid.is_valid_cell(cell) and not ore
	return grid.is_valid_cell(cell) or grid.is_ammo_cell(cell)

func phase_allows(allow_transition: bool = false) -> bool:
	var cycle: RefCounted = game.get("cycle")
	var shop: Control = game.get("shop")
	var victory: Control = game.get("night_victory_overlay")
	return not get_tree().paused and not cycle.defeated and not shop.shop_open and not shop.shop_animating and (victory == null or not victory.visible) and (allow_transition or not game.get("camera_controller").transitioning)

func toggle_night_view() -> void:
	if not game.get("cycle").is_night or not phase_allows(true):
		return
	clear_drag()
	var controller: RefCounted = game.get("camera_controller")
	controller.set_defense_view(not controller.defense_view)
	game.get("shop").set_view_mode(controller.defense_view)

func can_drop(kind: String, source: Vector2i, destination: Vector2i) -> bool:
	if not phase_allows() or (not grid.owned_tiles.has(source) and not grid.defense_tiles.has(source)) or not has_kind(source, kind) or not game.get("cycle").allows_interaction(kind, source, destination, true):
		return false
	if destination == grid.sale_cell and kind != "nugget": return can_sell(kind, source)
	if game.get_node("Construction").plans.has(source): return false
	if game.get_node("Construction").plans.has(destination):
		return kind == "nugget" and game.get_node("Construction").can_receive(destination, game.get("mining").nugget_type(source))
	if kind == "belt" and loaded_belt(source):
		return false
	if kind == "nugget" and game.get("mining").occupied_by_saw(destination):
		return game.get_node("Saws").can_receive(destination, game.get("mining").nugget_type(source))
	if kind == "nugget" and game.get("mining").occupied_by_furnace(destination):
		return game.get_node("Furnaces").can_receive(destination, game.get("mining").nugget_type(source))
	if kind == "nugget" and game.get("mining").occupied_by_compactor(destination):
		return game.get_node("Compactors").can_receive(destination, game.get("mining").nugget_type(source))
	if kind == "nugget" and source != destination:
		if game.get("launchers").launchers.has(destination):
			return game.get("launchers").can_receive(destination, game.get("mining").nugget_type(source))
		if game.get("mining").can_fuse(source, destination): return true
	if game.get("cycle").is_night:
		# Mine and reload during combat, while buildings remain in place.
		return kind == "nugget" and (source == destination or game.get("launchers").can_receive(destination) or game.get("mining").can_move_nugget(destination))
	if source == destination:
		return true
	if kind == "nugget":
		if destination == grid.sale_cell or game.get("launchers").can_receive(destination):
			return true
		if game.get("mining").can_move_nugget(destination):
			return true
	# Swapping another object must not move a loaded conveyor indirectly.
	if loaded_belt(source) or loaded_belt(destination):
		return false
	return can_hold(destination, cell_data(source)) and can_hold(source, cell_data(destination))

func loaded_belt(cell: Vector2i) -> bool:
	return game.get("conveyors").belts.has(cell) and game.get("mining").nuggets_at(cell) > 0

func resale_value(kind: String, source: Vector2i) -> int:
	var economy: RefCounted = game.get("economy")
	var price: int = 0
	match kind:
		"vein": price = item_price(game.get("mining").vein_at(source))
		"belt": price = economy.CONVEYOR_PRICE
		"drill": price = economy.DRILL_PRICE
		"launcher": price = economy.LAUNCHER_PRICE
		"compactor": price = game.get_node("Compactors").PRICE
		"saw": price = game.get_node("Saws").PRICE
		"furnace": price = game.get_node("Furnaces").PRICE
	if kind == "vein": price *= 1 << (game.get("mining").vein_level(source) - 1)
	return floori(price * 0.5)

func can_sell(kind: String, source: Vector2i) -> bool:
	var cycle: RefCounted = game.get("cycle")
	return kind in ["vein", "belt", "drill", "launcher", "compactor", "furnace", "saw"] and phase_allows() and not cycle.is_night and not cycle.is_guided_tutorial_active() and (grid.owned_tiles.has(source) or grid.defense_tiles.has(source)) and has_kind(source, kind) and not (kind == "belt" and loaded_belt(source))

func sell(kind: String, source: Vector2i) -> bool:
	if not can_sell(kind, source): return false
	var data: Dictionary = cell_data(source)
	var refund: int = resale_value(kind, source)
	if kind == "launcher":
		for ore: String in data["launcher"]["ammo"]:
			data[ore] = int(data.get(ore, 0)) + 1
	elif kind == "compactor" and int(data["compactor"]["count"]) > 0:
		var ore: String = data["compactor"]["kind"]
		data[ore] = int(data.get(ore, 0)) + int(data["compactor"]["count"])
	if kind == "saw":
		var contents: Dictionary = game.get_node("Saws").stored_items(source)
		for ore: String in contents: data[ore] = int(data.get(ore,0)) + int(contents[ore])
	if kind == "furnace":
		for ore: String in game.get_node("Furnaces").stored_items(source):
			data[ore] = int(data.get(ore, 0)) + 1
	if kind == "vein":
		data.erase("coal_vein")
		data.erase("brass_vein")
		data.erase("iron_vein")
	else:
		data.erase(kind)
	if kind == "belt": data.erase("entry")
	apply_cells({source: data})
	game.get("economy").add(refund)
	return true

func swaps_contents(kind: String, source: Vector2i, destination: Vector2i) -> bool:
	if kind == "vein" and game.get("mining").can_fuse_veins(source, destination): return false
	if kind == "nugget" and game.get("mining").occupied_by_machine(destination): return false
	if game.get("cycle").is_night:
		return false
	return source != destination and not cell_data(destination).is_empty() and not (kind == "nugget" and (destination == grid.sale_cell or game.get("launchers").can_receive(destination) or game.get("mining").can_move_nugget(destination))) and can_drop(kind, source, destination)

func rotate_data(data: Dictionary, direction: int) -> void:
	for kind in ["coal_vein", "brass_vein", "iron_vein", "blueprint", "belt", "compactor", "furnace", "saw"]:
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
	game.get_node("Compactors").changed.emit()
	game.get_node("Saws").changed.emit()
	game.get_node("Furnaces").changed.emit()

func drop(kind: String, source: Vector2i, destination: Vector2i, direction: int = -1) -> bool:
	if not can_drop(kind, source, destination):
		return false
	if destination == grid.sale_cell and kind != "nugget": return sell(kind, source)
	var mining: RefCounted = game.get("mining")
	var launchers: RefCounted = game.get("launchers")
	if kind == "vein" and mining.can_fuse_veins(source, destination): return mining.fuse_veins(source, destination)
	if kind == "nugget" and source != destination:
		if game.get_node("Construction").plans.has(destination):
			var ore: String = mining.nugget_type(source)
			if not game.get_node("Construction").receive(destination, ore): return false
			mining.remove_one_nugget(source, ore)
			mining.changed.emit()
			return true
		if mining.can_fuse(source, destination): return mining.fuse(source, destination)
		if mining.occupied_by_saw(destination):
			var ore: String = mining.nugget_type(source)
			if not game.get_node("Saws").receive(destination,ore): return false
			mining.remove_one_nugget(source,ore)
			mining.changed.emit()
			return true
		if mining.occupied_by_furnace(destination):
			var ore: String = mining.nugget_type(source)
			if not game.get_node("Furnaces").receive(destination, ore): return false
			mining.remove_one_nugget(source, ore)
			mining.changed.emit()
			return true
		if mining.occupied_by_compactor(destination):
			var ore: String = mining.nugget_type(source)
			if not game.get_node("Compactors").receive(destination, ore): return false
			mining.remove_one_nugget(source, ore)
			mining.changed.emit()
			return true
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
		if mining.can_move_nugget(destination):
			mining.move_nugget(source, destination)
			return true
	var origin: Dictionary = cell_data(source)
	if kind != "nugget":
		var rotation: int = direction
		if rotation < 0: rotation = int(origin.get("furnace", {}).get("direction", 0)) if kind == "furnace" else 1
		rotate_data(origin, rotation)
	if source == destination:
		apply_cells({source: origin})
	else:
		apply_cells({source: cell_data(destination), destination: origin})
	return true

func world_cell(point: Vector2) -> Vector2i:
	return grid.world_to_cell(game.get_global_transform_with_canvas().affine_inverse() * point)

func pick_kind(cell: Vector2i, _point: Vector2) -> String:
	var mining: RefCounted = game.get("mining")
	if game.get_node("Construction").plans.has(cell): return "blueprint"
	if mining.nuggets_at(cell) > 0:
		return "nugget"
	if mining.occupied_by_saw(cell): return "saw"
	if mining.vein_at(cell) != "": return "vein"
	if game.get("drills").drills.has(cell): return "drill"
	if game.get("launchers").launchers.has(cell): return "launcher"
	if game.get("conveyors").belts.has(cell): return "belt"
	if game.get("mining").occupied_by_compactor(cell): return "compactor"
	if game.get("mining").occupied_by_furnace(cell): return "furnace"
	return ""

func clear_drag() -> void:
	game.set("holding_object", false)
	game.set("dragging_object", false)
	game.set("held_object_type", "")
	game.redraw_world()
	game.get_node("Compactors").queue_redraw()
	game.get_node("Furnaces").queue_redraw()

func placement_active() -> bool:
	return placing_saw or placing_iron or placing_furnace or not placing_resource.is_empty() or game.get("placing_coal") or game.get("placing_brass") or game.get("placing_belt") or game.get("placing_drill") or game.get("placing_launcher") or game.get_node("Compactors").placing

func selected_item() -> String:
	if placing_saw: return "saw"
	if placing_iron: return "iron"
	if placing_furnace: return "furnace"
	if not placing_resource.is_empty(): return "resource:" + placing_resource
	if game.get("placing_coal"): return "coal"
	if game.get("placing_brass"): return "brass"
	if game.get("placing_belt"): return game.get("belt_shape")
	if game.get("placing_drill"): return "drill"
	if game.get("placing_launcher"): return "launcher"
	if game.get_node("Compactors").placing: return "compactor"
	return ""

func selection_available() -> bool:
	if not placing_resource.is_empty(): return game.get("economy").developer_mode
	return game.get("progression").is_item_unlocked(selected_item())

func select_resource(kind: String) -> bool:
	var cycle: RefCounted = game.get("cycle")
	if not game.get("economy").developer_mode or kind not in game.get("mining").ORE_KINDS or get_tree().paused or cycle.is_night or cycle.defeated or cycle.is_guided_tutorial_active(): return false
	cancel_active()
	placing_resource = kind
	game.get("shop").close_shop()
	game.redraw_world()
	return true

func item_price(item: String) -> int:
	var economy: RefCounted = game.get("economy")
	match item:
		"coal": return economy.COAL_VEIN_PRICE
		"brass": return economy.BRASS_VEIN_PRICE
		"iron": return economy.IRON_VEIN_PRICE
		"straight", "corner_right", "corner_left", "junction": return economy.CONVEYOR_PRICE
		"drill": return economy.DRILL_PRICE
		"launcher": return economy.LAUNCHER_PRICE
		"compactor": return game.get_node("Compactors").PRICE
		"saw": return game.get_node("Saws").PRICE
		"furnace": return game.get_node("Furnaces").PRICE
	return -1

func select_item(item: String) -> bool:
	var cycle: RefCounted = game.get("cycle")
	var shop: Control = game.get("shop")
	var action: String = "buy_conveyor" if item in ["straight", "corner_right", "corner_left", "junction"] else "buy_" + item
	if get_tree().paused or cycle.is_night or cycle.defeated or not cycle.allows_action(action) or not shop.tutorial_allows_item(item) or not game.get("progression").is_item_unlocked(item): return false
	var price: int = item_price(item)
	if price < 0 or not game.get("economy").can_afford(price): return false
	cancel_active()
	game.set("placement_paid", false)
	game.set("placement_direction", 1)
	match item:
		"saw": placing_saw = true
		"iron": placing_iron = true
		"furnace": placing_furnace = true
		"coal": game.set("placing_coal", true)
		"brass": game.set("placing_brass", true)
		"straight", "corner_right", "corner_left", "junction":
			game.set("placing_belt", true)
			game.set("belt_shape", item)
		"drill": game.set("placing_drill", true)
		"launcher":
			game.set("placing_launcher", true)
			game.set("placing_free_launcher", false)
		"compactor":
			game.get_node("Compactors").placing = true
			game.get_node("Compactors").paid = false
			game.get_node("Compactors").direction = 1
	shop.close_shop()
	game.redraw_world()
	return true

func place_selected(cell: Vector2i) -> bool:
	if not placing_resource.is_empty():
		var cycle: RefCounted = game.get("cycle")
		var mining: RefCounted = game.get("mining")
		if not selection_available() or not phase_allows() or cycle.is_night or cycle.is_guided_tutorial_active() or not mining.can_move_nugget(cell): return false
		mining.items_for(placing_resource)[cell] = 1
		mining.changed.emit()
		if Input.is_key_pressed(KEY_SHIFT): shift_batch = true
		else: cancel_active()
		game.redraw_world()
		return true
	var item: String = selected_item()
	var cycle: RefCounted = game.get("cycle")
	var placing: String = item if item in ["coal", "launcher"] else ("belt" if game.get("placing_belt") else "other")
	if item.is_empty() or not selection_available() or not phase_allows() or cycle.is_night or not cycle.allows_world_press(cell, placing): return false
	if not can_place_item(cell, item): return false
	var economy: RefCounted = game.get("economy")
	var price: int = item_price(item)
	# Compatibility with older embedded controllers that prepaid a direct buy call.
	var prepaid: bool = game.get_node("Compactors").paid if item == "compactor" else game.get("placement_paid")
	if not prepaid and not economy.spend(price): return false
	var direction: int = game.get("placement_direction")
	if game.get_node("Construction").has_recipe(item):
		game.get_node("Construction").place(cell, item, direction, 0 if economy.developer_mode else price)
	else:
		build_selected(cell, item, direction)
	game.set("placement_paid", false)
	game.get_node("Compactors").paid = false
	if cycle.is_guided_tutorial_active() or not Input.is_key_pressed(KEY_SHIFT) or not economy.can_afford(item_price(item)):
		cancel_active()
	else:
		shift_batch = true
	game.redraw_world()
	return true

func can_place_item(cell: Vector2i, item: String) -> bool:
	var valid: bool = false
	match item:
		"coal", "brass", "iron": valid = game.get("mining").can_place_vein(cell) and not game.get("launchers").launchers.has(cell)
		"straight", "corner_right", "corner_left", "junction": valid = game.get("conveyors").can_place(cell)
		"drill": valid = game.get("drills").can_place(cell) and not game.get("launchers").launchers.has(cell)
		"launcher": valid = game.get("launchers").can_place(cell)
		"compactor": valid = game.get_node("Compactors").can_place(cell)
		"saw": valid = game.get_node("Saws").can_place(cell)
		"furnace": valid = game.get_node("Furnaces").can_place(cell)
	return valid

func build_selected(cell: Vector2i, item: String, direction: int) -> void:
	var cycle: RefCounted = game.get("cycle")
	match item:
		"coal", "brass", "iron": game.get("mining").place_vein(cell, direction, item)
		"straight", "corner_right", "corner_left", "junction": game.get("conveyors").place(cell, direction, item)
		"drill": game.get("drills").place(cell, direction)
		"launcher":
			game.get("launchers").place(cell)
			cycle.use_free_launcher()
			game.set("placing_free_launcher", false)
		"compactor": game.get_node("Compactors").place(cell, direction)
		"saw": game.get_node("Saws").place(cell,direction)
		"furnace": game.get_node("Furnaces").place(cell, direction)

func cancel_active() -> bool:
	var inspector: Node = game.get_node_or_null("ToolInspector")
	if inspector != null and inspector.close_inspector(): return true
	if not placement_active() and not game.get("holding_object"): return false
	game.cancel_placement()
	game.get_node("Compactors").cancel_placement()
	placing_resource = ""
	placing_furnace = false
	placing_iron = false
	placing_saw = false
	shift_batch = false
	clear_drag()
	return true

func _process(_delta: float) -> void:
	if (placing_furnace or placing_iron or placing_saw) and (game.get("cycle").is_night or game.get("cycle").defeated): cancel_active()
	var cycle: RefCounted = game.get("cycle")
	if not placing_resource.is_empty() and (not game.get("economy").developer_mode or cycle.is_night or cycle.defeated or cycle.is_guided_tutorial_active()):
		cancel_active()
		return
	if not placement_active():
		shift_batch = false
		return
	if game.get("cycle").is_guided_tutorial_active(): return
	if Input.is_key_pressed(KEY_SHIFT): shift_batch = true
	elif shift_batch: cancel_active()

func _input(event: InputEvent) -> void:
	if placing_iron and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and phase_allows():
		game.set("placement_direction", posmod(int(game.get("placement_direction")) + 1, 4))
		game.redraw_world()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event.keycode == KEY_SHIFT or event.physical_keycode == KEY_SHIFT) and placement_active() and not game.get("cycle").is_guided_tutorial_active():
		if event.pressed:
			shift_batch = true
		else:
			cancel_active()
			get_viewport().set_input_as_handled()
		return
	if game.get("cycle").is_night and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_P or event.physical_keycode == KEY_P):
		toggle_night_view()
		get_viewport().set_input_as_handled()
		return
	if game.get("cycle").is_tutorial_active() or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.pressed or not game.get("holding_object"):
		return
	if not game.get("dragging_object") and event.position.distance_to(game.get("drag_start_position")) < 8.0:
		if game.get("held_object_type") in ["blueprint", "drill", "compactor", "furnace", "launcher", "saw"] and phase_allows():
			var tool_kind: String = game.get("held_object_type")
			var at: Vector2i = game.get("held_object_cell")
			clear_drag()
			game.get_node("ToolInspector").open_tool(tool_kind, at)
			get_viewport().set_input_as_handled()
			return
		if game.get("cycle").is_night:
			if phase_allows() and game.get("held_object_type") == "vein":
				game.get("mining").mine(game.get("held_object_cell"))
			clear_drag()
			get_viewport().set_input_as_handled()
		return
	var destination: Vector2i = world_cell(event.position)
	drop(game.get("held_object_type"), game.get("held_object_cell"), destination, game.get("placement_direction"))
	clear_drag()
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if placement_active() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		place_selected(world_cell(event.position))
		get_viewport().set_input_as_handled()
		return
	if game.get("camera_controller").transitioning and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		return
	if game.get("cycle").is_tutorial_active() or not phase_allows() or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed or game.get("holding_object"):
		return
	if game.get("placing_coal") or game.get("placing_brass") or game.get("placing_belt") or game.get("placing_drill") or game.get("placing_launcher") or game.get_node("Compactors").placing:
		return
	var cell: Vector2i = world_cell(event.position)
	var kind: String = pick_kind(cell, event.position)
	if kind.is_empty(): return
	if game.get("cycle").is_night and (kind not in ["vein", "nugget", "furnace", "compactor", "drill", "launcher", "saw"] or (game.get("camera_controller").defense_view and grid.is_valid_cell(cell))):
		return
	game.set("held_object_type", kind)
	game.set("held_object_cell", cell)
	game.set("holding_object", true)
	game.set("dragging_object", false)
	game.set("drag_start_position", event.position)
	game.set("drag_world_position", game.get_global_transform_with_canvas().affine_inverse() * event.position)
	var data: Dictionary = cell_data(cell)
	if kind == "vein":
		game.set("placement_direction", int(data[game.get("mining").vein_at(cell) + "_vein"]["direction"]))
	elif kind == "belt":
		game.set("placement_direction", int(data["belt"]["direction"]))
	elif kind == "drill":
		game.set("placement_direction", int(data["drill"]))
	elif kind in ["compactor", "furnace", "saw"]:
		game.set("placement_direction", int(data[kind].get("direction", 0)))
	get_viewport().set_input_as_handled()
