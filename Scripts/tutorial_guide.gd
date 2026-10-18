extends Node2D

var game: Node2D
var cycle: RefCounted
var last_step: int = -1
var last_state: Array = []
var pulse: float = 0.0

func _ready() -> void:
	game = get_parent() as Node2D
	cycle = game.get("cycle")
	game.get("renderer").tutorial = cycle
	z_index = 1000
	cycle.changed.connect(on_step_changed)
	get_viewport().size_changed.connect(focus_objective)
	on_step_changed()

func on_step_changed() -> void:
	if not cycle.is_tutorial_active():
		queue_redraw()
		return
	if last_step != cycle.tutorial_step:
		last_step = cycle.tutorial_step
		# This also cancels/refunds Shift-repeat purchases in older scene scripts.
		game.cancel_placement.call_deferred()
		focus_objective.call_deferred()
	game.get("shop").update_cycle()
	queue_redraw()

func focus_objective() -> void:
	if not cycle.is_tutorial_active():
		return
	var controller: RefCounted = game.get("camera_controller")
	controller.set_defense_view(false)
	controller.dragging = false
	var camera: Camera2D = game.get("camera")
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: float = clampf(view_size.x / (12.0 * cycle.grid.TILE_SIZE), controller.min_zoom, controller.max_zoom)
	camera.zoom = Vector2.ONE * zoom
	camera.position = Vector2(14.5 * cycle.grid.TILE_SIZE, 162.0 if cycle.tutorial_step >= 3 else cycle.grid.GRID_OFFSET_Y + 20.0)
	controller.clamp_position()
	camera.force_update_scroll()
	game.get("shop").set_view_mode(false)

func _process(delta: float) -> void:
	if not cycle.is_tutorial_active():
		return
	pulse += delta
	var vein: Dictionary = cycle.mining.coal_veins.get(cycle.TUTORIAL_COAL_CELL, {})
	var state: Array = [cycle.tutorial_step, game.get("placing_coal"), game.get("placing_belt"), game.get("placing_launcher"), cycle.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL), vein.get("progress", 0), cycle.ammo_damage(), cycle.economy.coins]
	if state != last_state:
		last_state = state
		game.get("shop").update_cycle()
	queue_redraw()

func placing_kind() -> String:
	if game.get("placing_coal"):
		return "coal"
	if game.get("placing_belt"):
		return "belt"
	if game.get("placing_launcher"):
		return "launcher"
	return "other" if game.get("placing_brass") or game.get("placing_drill") else ""

func clear_interaction() -> void:
	game.set("holding_object", false)
	game.set("dragging_object", false)
	game.set("held_object_type", "")
	game.redraw_world()

func is_over_card(position: Vector2) -> bool:
	var panel: Control = game.get("shop").get_node("CyclePanel")
	var local: Vector2 = panel.get_global_transform_with_canvas().affine_inverse() * position
	return Rect2(Vector2.ZERO, panel.size).has_point(local)

func _input(event: InputEvent) -> void:
	if not cycle.is_tutorial_active():
		return
	if event is InputEventKey:
		# Pause, display settings, and keyboard navigation remain accessible.
		if event.keycode in [KEY_P, KEY_R, KEY_F10] or event.physical_keycode in [KEY_P, KEY_R, KEY_F10]:
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		return
	var cell: Vector2i = cycle.grid.world_to_cell(game.get_local_mouse_position())
	if not event.pressed and game.get("holding_object"):
		if not cycle.allows_interaction(game.get("held_object_type"), game.get("held_object_cell"), cell, game.get("dragging_object")):
			clear_interaction()
			get_viewport().set_input_as_handled()
		return
	if is_over_card(event.position):
		return
	if not event.pressed or not cycle.allows_world_press(cell, placing_kind()):
		get_viewport().set_input_as_handled()
	elif not placing_kind().is_empty():
		game.set("placement_direction", 1)

func targets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	match cycle.tutorial_step:
		0: result.append(cycle.TUTORIAL_COAL_CELL)
		1, 5:
			if cycle.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL) > 0:
				result.append(cycle.TUTORIAL_ORE_CELL)
				result.append(cycle.grid.sale_cell if cycle.tutorial_step == 1 else cycle.grid.defense_cell("left"))
			else:
				result.append(cycle.TUTORIAL_COAL_CELL)
		3:
			result.append(cycle.grid.defense_cell("left"))
			result.append(cycle.grid.defense_cell("right"))
		4, 6: result.append(cycle.grid.defense_cell("left"))
	return result

func _draw() -> void:
	if cycle == null or not cycle.is_tutorial_active():
		return
	var cells: Array[Vector2i] = targets()
	var glow: float = 0.65 + 0.25 * sin(pulse * 3.0)
	for index in range(cells.size()):
		var rect: Rect2 = cycle.grid.get_cell_rect(cells[index]).grow(-1.5)
		var color := Color("#f0c777")
		if cells.size() == 2 and index == 0 and cycle.tutorial_step in [1, 5]:
			color = Color("#b6d98e")
		draw_rect(rect, Color(color, 0.12))
		draw_rect(rect, Color(color, glow), false, 2.0)
	if cells.size() == 2 and cycle.tutorial_step in [1, 5]:
		var source: Vector2 = cycle.grid.get_cell_rect(cells[0]).get_center()
		var destination: Vector2 = cycle.grid.get_cell_rect(cells[1]).get_center()
		var direction: Vector2 = (destination - source).normalized()
		var end: Vector2 = destination - direction * 15.0
		var color := Color(0.94, 0.78, 0.47, glow)
		draw_line(source + direction * 15.0, end, color, 1.5, true)
		draw_line(end, end - direction.rotated(0.55) * 8.0, color, 1.5, true)
		draw_line(end, end - direction.rotated(-0.55) * 8.0, color, 1.5, true)
