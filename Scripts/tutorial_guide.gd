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
	game.get_node("Construction").changed.connect(cycle.refresh_tutorial)
	game.get_node("Furnaces").changed.connect(cycle.refresh_tutorial)
	get_viewport().size_changed.connect(focus_objective)
	var barrier := preload("res://Scripts/tutorial_barrier.gd").new()
	barrier.name = "TutorialBarrier"
	barrier.live_game = game
	barrier.grid = cycle.grid
	game.add_child(barrier)
	on_step_changed()

func on_step_changed() -> void:
	if cycle.is_research_tutorial_active():
		game.cancel_placement.call_deferred()
		clear_interaction()
	if not cycle.is_tutorial_active():
		queue_redraw()
		return
	if last_step != cycle.tutorial_step:
		if last_step < 0: focus_objective.call_deferred()
		last_step = cycle.tutorial_step
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
	# Leave room around the centered defense platforms for the tutorial card.
	var columns: float = 16.0 if cycle.tutorial_step >= 4 else 12.0
	var zoom: float = clampf(view_size.x / (columns * cycle.grid.TILE_SIZE), controller.min_zoom, controller.max_zoom)
	camera.zoom = Vector2.ONE * zoom
	var center_x: float = cycle.grid.get_cell_rect(cycle.grid.sale_cell).get_center().x
	camera.position = Vector2(center_x, 162.0 if cycle.tutorial_step >= 4 else cycle.grid.GRID_OFFSET_Y + 20.0)
	controller.clamp_position()
	camera.force_update_scroll()
	game.get("shop").set_view_mode(false)

func _process(delta: float) -> void:
	pulse += delta
	if not cycle.is_tutorial_active():
		update_resupply()
		update_ui_pointer()
		return
	var vein: Dictionary = cycle.mining.coal_veins.get(cycle.coal_cell, {})
	var shop: Control = game.get("shop")
	var state: Array = [cycle.tutorial_step, game.get("placing_coal"), game.get("placing_belt"), game.get("placing_launcher"), cycle.mining.nuggets_at(cycle.coal_output()), vein.get("progress", 0), cycle.ammo_damage(), cycle.economy.coins, shop.shop_open, shop.shop_animating, shop.shop_title.text]
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
	resupply_step = -1

func apply_resupply_card(shop: Control) -> void:
	shop.cycle_heading.text = "APRENDE A RECARGAR"
	shop.cycle_badge.text = "%02d / 03" % (resupply_step + 1)
	shop.cycle_steps.hide()
	match resupply_step:
		0:
			shop.cycle_title.text = "Sin munición"
			shop.cycle_goal.text = "Pulsa el pico para bajar a la mina."
		1:
			shop.cycle_title.text = "Recarga el arma"
			shop.cycle_goal.text = "Extrae una pepita y arrástrala al arma."
		2:
			shop.cycle_title.text = "¡Arma recargada!"
			shop.cycle_goal.text = "Pulsa el escudo para volver a defender."
	shop.cycle_action.hide()

func resupply_targets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var controller: RefCounted = game.get("camera_controller")
	if not resupply_active() or resupply_step != 1 or controller.defense_view or controller.transitioning:
		return result
	for kind: String in ["coal", "brass"]:
		var items: Dictionary = cycle.mining.items_for(kind)
		for cell: Vector2i in items:
			if int(items[cell]) <= 0: continue
			result.append(cell)
			for platform: Vector2i in cycle.launchers.launchers:
				if cycle.launchers.can_receive(platform, kind):
					result.append(platform)
					return result
			return result
	for veins: Dictionary in [cycle.mining.coal_veins, cycle.mining.brass_veins]:
		if not veins.is_empty():
			result.append(veins.keys()[0])
			break
	return result

func placing_kind() -> String:
	if game.get_node("WorldInteractions").placing_furnace: return "furnace"
	if game.get("placing_brass"): return "brass"
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
	game.get("shop").handle_outside_click(event)

func targets() -> Array[Vector2i]:
	if cycle.tutorial_step >= 5:
		var targets: Array[Vector2i] = cycle.workshop_targets()
		if not targets.is_empty(): return targets
		match placing_kind():
			"brass": return [cycle.brass_cell]
			"furnace": return [cycle.furnace_cell]
			"launcher": return [cycle.grid.defense_cell("left")]
		return []
	if cycle.advanced_vein_lesson() and not cycle.needs_tutorial_income():
		var pair: Array[Vector2i] = cycle.vein_fusion_targets()
		if not pair.is_empty(): return pair
		var cells: Array[Vector2i] = []
		if game.get("placing_coal"): cells.append(cycle.next_vein_cell())
		return cells
	if cycle.tutorial_step == 6:
		if cycle.needs_tutorial_income(): return cycle.income_targets()
		if cycle.needs_ammo_vein():
			var cells: Array[Vector2i] = []
			if game.get("placing_coal"): cells.append(cycle.TUTORIAL_NEW_VEIN_CELL)
			return cells
		if cycle.mining.nuggets_at(cycle.tutorial_output_cell()) > 0: return [cycle.tutorial_output_cell(),cycle.grid.defense_cell("left") if cycle.mining.nugget_type(cycle.tutorial_output_cell()) == "coal" else cycle.grid.sale_cell]
		return [cycle.tutorial_mining_cell()]
	if cycle.vein_lesson_active() and not cycle.needs_tutorial_income():
		if cycle.mining.coal_veins.has(cycle.TUTORIAL_NEW_VEIN_CELL): return [cycle.TUTORIAL_NEW_VEIN_CELL,cycle.coal_cell]
		var cells: Array[Vector2i] = []
		if game.get("placing_coal"): cells.append(cycle.TUTORIAL_NEW_VEIN_CELL)
		return cells
	var result: Array[Vector2i] = []
	if cycle.advanced_income(): return cycle.income_targets()
	if cycle.tutorial_step == 2 or cycle.needs_tutorial_income():
		if cycle.mining.nugget_type(cycle.TUTORIAL_FUSION_CELL) == "coal_2":
			return [cycle.TUTORIAL_FUSION_CELL, cycle.grid.sale_cell]
		if cycle.mining.nuggets_at(cycle.coal_output()) > 0:
			return [cycle.coal_output(), cycle.TUTORIAL_FUSION_CELL]
		return [cycle.coal_cell]
	match cycle.tutorial_step:
		0:
			if game.get("placing_coal"): result.append(cycle.coal_cell)
		1, 6:
			if cycle.tutorial_step == 6 and cycle.mining.nugget_type(cycle.coal_output()) in ["coal_2", "coal_3", "coal_4"]:
				return [cycle.coal_output(), cycle.grid.sale_cell]
			if cycle.mining.nuggets_at(cycle.coal_output()) > 0:
				return [cycle.coal_output(), cycle.grid.sale_cell if cycle.tutorial_step == 1 else cycle.grid.defense_cell("left")]
			return [cycle.coal_cell]
		5:
			if game.get("placing_launcher"): result.append(cycle.grid.defense_cell("left"))
		7: result.append(cycle.grid.defense_cell("left"))
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
		if cells.size() == 2 and index == 0 and (not lesson or (cycle.tutorial_step in [1, 2] or cycle.tutorial_step >= 5 or cycle.needs_tutorial_income() or cycle.vein_lesson_active() or cycle.advanced_vein_lesson())):
			color = Color("#b6d98e")
		draw_rect(rect, Color(color, 0.12))
		draw_rect(rect, Color(color, glow), false, 2.0)
	if cells.size() == 1 and cycle.mining.vein_at(cells[0]) != "" and (not lesson or (cycle.tutorial_step in [1, 2] or cycle.tutorial_step >= 5 or cycle.needs_tutorial_income() or cycle.vein_lesson_active() or cycle.advanced_vein_lesson())):
		draw_mining_click(cells[0])
	if cells.size() == 2 and (not lesson or (cycle.tutorial_step in [1, 2] or cycle.tutorial_step >= 5 or cycle.needs_tutorial_income() or cycle.vein_lesson_active() or cycle.advanced_vein_lesson())):
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
