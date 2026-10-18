extends Node2D

var game: Node2D
var cycle: RefCounted
var last_step: int = -1
var last_state: Array = []
var pulse: float = 0.0
var resupply_step: int = -1
var resupply_taught: bool = false
var last_transitioning: bool = false
var pointer: GuidePointer
var click_mouse := StyleBoxFlat.new()
var click_button := StyleBoxFlat.new()

func _ready() -> void:
	game = get_parent() as Node2D
	cycle = game.get("cycle")
	game.get("renderer").tutorial = cycle
	z_index = 1000
	click_mouse.bg_color = Color("#192920")
	click_mouse.border_color = Color("#f0c777")
	click_mouse.set_border_width_all(1)
	click_mouse.set_corner_radius_all(7)
	click_button.set_corner_radius_all(3)
	pointer = GuidePointer.new()
	pointer.name = "TutorialPointer"
	game.get("shop").add_child(pointer)
	pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cycle.changed.connect(on_step_changed)
	get_viewport().size_changed.connect(focus_objective)
	on_step_changed()

func on_step_changed() -> void:
	if cycle.is_research_tutorial_active():
		game.cancel_placement.call_deferred()
		clear_interaction()
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
		update_ui_pointer()
		return
	var vein: Dictionary = cycle.mining.coal_veins.get(cycle.TUTORIAL_COAL_CELL, {})
	var shop: Control = game.get("shop")
	var state: Array = [cycle.tutorial_step, game.get("placing_coal"), game.get("placing_belt"), game.get("placing_launcher"), cycle.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL), vein.get("progress", 0), cycle.ammo_damage(), cycle.economy.coins, shop.shop_open, shop.shop_animating, shop.shop_title.text]
	if state != last_state:
		last_state = state
		game.get("shop").update_cycle()
	update_ui_pointer()
	queue_redraw()

func update_ui_pointer() -> void:
	var shop: Control = game.get("shop")
	pointer.target = shop.tutorial_ui_target()
	if resupply_active() and resupply_step != 1 and not game.get("camera_controller").transitioning:
		pointer.target = shop.view_button
	pointer.pulse = pulse
	pointer.queue_redraw()

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
		queue_redraw()

func apply_resupply_card(shop: Control) -> void:
	shop.cycle_heading.text = "APRENDE A RECARGAR"
	shop.cycle_badge.text = "%02d / 03" % (resupply_step + 1)
	shop.cycle_steps.hide()
	match resupply_step:
		0:
			shop.cycle_title.text = "Sin munición"
			shop.cycle_goal.text = "Pulsa MINA para recargar."
		1:
			shop.cycle_title.text = "Recarga el arma"
			shop.cycle_goal.text = "Extrae una pepita y arrástrala al arma."
		2:
			shop.cycle_title.text = "¡Arma recargada!"
			shop.cycle_goal.text = "Pulsa DEFENSIVA para regresar."
	shop.cycle_action.hide()

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
	return is_over_control(game.get("shop").get_node("CyclePanel"), position)

func is_over_control(control: Control, position: Vector2) -> bool:
	if not control.is_visible_in_tree(): return false
	var local: Vector2 = control.get_global_transform_with_canvas().affine_inverse() * position
	return Rect2(Vector2.ZERO, control.size).has_point(local)

func _input(event: InputEvent) -> void:
	if not cycle.is_guided_tutorial_active():
		return
	# Victory must be dismissible before the day-two lesson takes input.
	var victory: Control = game.get("night_victory_overlay")
	if victory != null and victory.visible:
		return
	if event is InputEventKey:
		# Pause, display settings, and keyboard navigation remain accessible.
		if event.keycode in [KEY_P, KEY_R, KEY_F10] or event.physical_keycode in [KEY_P, KEY_R, KEY_F10]:
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var shop: Control = game.get("shop")
	if (shop.shop_open or shop.shop_animating) and is_over_control(shop.shop_panel, event.position):
		return
	if not shop.tutorial_purchase().is_empty() and is_over_control(shop.shop_button, event.position):
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
		0:
			if game.get("placing_coal"): result.append(cycle.TUTORIAL_COAL_CELL)
		1, 5:
			if cycle.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL) > 0:
				result.append(cycle.TUTORIAL_ORE_CELL)
				result.append(cycle.grid.sale_cell if cycle.tutorial_step == 1 else cycle.grid.defense_cell("left"))
			else:
				result.append(cycle.TUTORIAL_COAL_CELL)
		4:
			if game.get("placing_launcher"): result.append(cycle.grid.defense_cell("left"))
		6: result.append(cycle.grid.defense_cell("left"))
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
	if cells.size() == 1 and cycle.mining.vein_at(cells[0]) != "" and (not lesson or cycle.tutorial_step in [1, 5]):
		draw_mining_click(cells[0])
	if cells.size() == 2 and (not lesson or cycle.tutorial_step in [1, 5]):
		var source: Vector2 = cycle.grid.get_cell_rect(cells[0]).get_center()
		var destination: Vector2 = cycle.grid.get_cell_rect(cells[1]).get_center()
		var direction: Vector2 = (destination - source).normalized()
		var end: Vector2 = destination - direction * 15.0
		var color := Color(0.94, 0.78, 0.47, glow)
		draw_line(source + direction * 15.0, end, color, 1.5, true)
		draw_line(end, end - direction.rotated(0.55) * 8.0, color, 1.5, true)
		draw_line(end, end - direction.rotated(-0.55) * 8.0, color, 1.5, true)

func draw_mining_click(cell: Vector2i) -> void:
	var rect: Rect2 = cycle.grid.get_cell_rect(cell)
	var press: float = 0.5 + 0.5 * sin(pulse * 5.5)
	var origin: Vector2 = Vector2(rect.get_center().x, rect.position.y - 15.0 + 1.5 * sin(pulse * 3.0) + press)
	draw_style_box(click_mouse, Rect2(origin - Vector2(7, 10), Vector2(14, 20)))
	click_button.bg_color = Color("#64734c").lerp(Color("#f0c777"), press)
	draw_style_box(click_button, Rect2(origin + Vector2(-5.5, -8.5), Vector2(5, 8)))
	draw_line(origin + Vector2(0, -8.5), origin + Vector2(0, -1), Color("#f0c777"), 0.8, true)
	draw_line(origin + Vector2(-5.5, 0), origin + Vector2(5.5, 0), Color("#f0c777"), 0.8, true)
	var flash := Color(0.94, 0.78, 0.47, press)
	draw_line(origin + Vector2(-10, -7), origin + Vector2(-14, -9), flash, 1.0, true)
	draw_line(origin + Vector2(-7, -12), origin + Vector2(-9, -16), flash, 1.0, true)
	draw_line(origin + Vector2(-12, -2), origin + Vector2(-16, -2), flash, 1.0, true)

class GuidePointer extends Control:
	var target: Control
	var pulse: float = 0.0
	var outline := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 100
		outline.bg_color = Color.TRANSPARENT
		outline.set_border_width_all(2)
		outline.set_corner_radius_all(9)

	func _draw() -> void:
		if not is_instance_valid(target) or not target.is_visible_in_tree(): return
		var transform: Transform2D = get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas()
		var rect: Rect2 = (transform * Rect2(Vector2.ZERO, target.size)).grow(4.0)
		var color := Color(0.95, 0.78, 0.47, 0.75 + 0.25 * sin(pulse * 4.0))
		outline.border_color = color
		draw_style_box(outline, rect)
		var tip := Vector2(rect.position.x - 7.0, rect.get_center().y)
		var tail: Vector2 = tip - Vector2(20.0 + 3.0 * sin(pulse * 4.0), 0)
		draw_line(tail, tip - Vector2(4, 0), color, 2.0, true)
		draw_colored_polygon(PackedVector2Array([tip, tip - Vector2(9, 6), tip - Vector2(9, -6)]), color)
