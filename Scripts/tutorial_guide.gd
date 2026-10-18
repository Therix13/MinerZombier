extends Node2D

var game: Node2D
var cycle: RefCounted
var last_step: int = -1
var last_state: Array = []
var pulse: float = 0.0
var resupply_step: int = -1
var resupply_taught: bool = false
var last_transitioning: bool = false

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
	pulse += delta
	if not cycle.is_tutorial_active():
		update_resupply()
		return
	var vein: Dictionary = cycle.mining.coal_veins.get(cycle.TUTORIAL_COAL_CELL, {})
	var state: Array = [cycle.tutorial_step, game.get("placing_coal"), game.get("placing_belt"), game.get("placing_launcher"), cycle.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL), vein.get("progress", 0), cycle.ammo_damage(), cycle.economy.coins]
	if state != last_state:
		last_state = state
		game.get("shop").update_cycle()
	queue_redraw()

func resupply_active() -> bool:
	return resupply_step >= 0 and cycle.is_night and not cycle.defeated

func update_resupply() -> void:
	var previous: int = resupply_step
	var controller: RefCounted = game.get("camera_controller")
	if not cycle.is_night or cycle.defeated:
		resupply_step = -1
	elif resupply_step < 0 and not resupply_taught and not cycle.has_ammo():
		var wave: Node = game.get("zombie_manager")
		# The last killing shot should not start a lesson after victory.
		if wave.active_wave and (wave.spawn_count < wave.wave_total or not get_tree().get_nodes_in_group("zombies").is_empty()):
			resupply_taught = true
			resupply_step = 0 if controller.defense_view else 1
	if resupply_active() and not controller.transitioning:
		if cycle.has_ammo():
			resupply_step = -1 if controller.defense_view else 2
		elif resupply_step == 0 and not controller.defense_view:
			resupply_step = 1
		elif resupply_step == 2:
			resupply_step = 0 if controller.defense_view else 1
	if previous != resupply_step or (resupply_active() and last_transitioning != controller.transitioning):
		game.get("shop").update_cycle()
		queue_redraw()
	last_transitioning = controller.transitioning
	if resupply_active():
		var button: Button = game.get("shop").view_button
		button.modulate = Color.WHITE.lerp(Color("#f0c777"), 0.35 + 0.2 * sin(pulse * 4.0)) if resupply_step != 1 else Color.WHITE
		queue_redraw()
	elif previous >= 0:
		game.get("shop").view_button.modulate = Color.WHITE

func apply_resupply_card(shop: Control) -> void:
	shop.cycle_heading.text = "APRENDE A RECARGAR"
	shop.cycle_badge.text = "%02d / 03" % (resupply_step + 1)
	shop.cycle_steps.hide()
	match resupply_step:
		0:
			shop.cycle_title.text = "Sin munición"
			shop.cycle_goal.text = "Cambia a la mina para recargar."
			shop.cycle_action.text = "IR A LA MINA"
		1:
			shop.cycle_title.text = "Recarga el arma"
			shop.cycle_goal.text = "Extrae una pepita y arrástrala al arma."
			shop.cycle_action.text = "ARRASTRA LA PEPITA"
		2:
			shop.cycle_title.text = "¡Arma recargada!"
			shop.cycle_goal.text = "Regresa a la defensa."
			shop.cycle_action.text = "VOLVER A DEFENSA"
	shop.cycle_action.disabled = resupply_step == 1 or game.get("camera_controller").transitioning

func resupply_action() -> void:
	if resupply_active() and resupply_step != 1:
		game.get("shop").request_view_toggle()

func resupply_targets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var controller: RefCounted = game.get("camera_controller")
	if not resupply_active() or resupply_step != 1 or controller.defense_view or controller.transitioning:
		return result
	for items: Dictionary in [cycle.mining.coal_nuggets, cycle.mining.brass_nuggets]:
		for cell: Vector2i in items:
			if int(items[cell]) <= 0: continue
			result.append(cell)
			for platform: Vector2i in cycle.launchers.launchers:
				if cycle.launchers.can_receive(platform):
					result.append(platform)
					return result
			return result
	for veins: Dictionary in [cycle.mining.coal_veins, cycle.mining.brass_veins]:
		if not veins.is_empty():
			result.append(veins.keys()[0])
			break
	return result

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
	if cycle == null or (not cycle.is_tutorial_active() and not resupply_active()):
		return
	var lesson: bool = cycle.is_tutorial_active()
	var cells: Array[Vector2i] = targets() if lesson else resupply_targets()
	var glow: float = 0.65 + 0.25 * sin(pulse * 3.0)
	for index in range(cells.size()):
		var rect: Rect2 = cycle.grid.get_cell_rect(cells[index]).grow(-1.5)
		var color := Color("#f0c777")
		if cells.size() == 2 and index == 0 and (not lesson or cycle.tutorial_step in [1, 5]):
			color = Color("#b6d98e")
		draw_rect(rect, Color(color, 0.12))
		draw_rect(rect, Color(color, glow), false, 2.0)
	if cells.size() == 2 and (not lesson or cycle.tutorial_step in [1, 5]):
		var source: Vector2 = cycle.grid.get_cell_rect(cells[0]).get_center()
		var destination: Vector2 = cycle.grid.get_cell_rect(cells[1]).get_center()
		var direction: Vector2 = (destination - source).normalized()
		var end: Vector2 = destination - direction * 15.0
		var color := Color(0.94, 0.78, 0.47, glow)
		draw_line(source + direction * 15.0, end, color, 1.5, true)
		draw_line(end, end - direction.rotated(0.55) * 8.0, color, 1.5, true)
		draw_line(end, end - direction.rotated(-0.55) * 8.0, color, 1.5, true)
