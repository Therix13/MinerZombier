extends CanvasLayer

const NAMES := {"coal": "Veta de carbón", "brass": "Veta de latón", "belt": "Cinta", "drill": "Taladro", "launcher": "Lanzapapas"}
const PRICES := {"coal": [100, 200], "brass": [100, 200], "belt": [50, 100], "drill": [150, 300], "launcher": [200, 400]}

var game: Node2D
var shop: Control
var screen: Control
var panel: PanelContainer
var title: Label
var stats: Label
var upgrade_button: Button
var selected_cell := Vector2i(-999, -999)
var right_press := Vector2.INF

func _ready() -> void:
	layer = 30
	game = get_parent() as Node2D
	shop = game.get("shop")
	# Older scenes may still connect their old global bonus callback.
	var progression: RefCounted = game.get("progression")
	for connection in progression.technology_unlocked.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == game and callback.get_method() == &"apply_technologies":
			progression.technology_unlocked.disconnect(callback)
	build_interface()
	get_viewport().size_changed.connect(update_layout)
	update_layout()

func build_interface() -> void:
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 250
	panel.add_theme_stylebox_override("panel", shop.create_style("#192920", "#c9a469", 2, 10))
	screen.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	title = shop.create_label("", 16, Color("#efd29b"))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.add_theme_font_size_override("font_size", 21)
	close.pressed.connect(panel.hide)
	header.add_child(close)
	stats = shop.create_label("", 14, Color("#bed1ac"))
	stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(stats)
	upgrade_button = shop.create_button("")
	upgrade_button.custom_minimum_size.y = 38
	upgrade_button.pressed.connect(on_upgrade_pressed)
	column.add_child(upgrade_button)
	panel.hide()

func update_layout() -> void:
	scale = (game.get("ui_layer") as CanvasLayer).scale
	screen.size = get_viewport().get_visible_rect().size / scale.x
	panel.hide()

func can_edit() -> bool:
	var cycle: RefCounted = game.get("cycle")
	var victory: Control = game.get("night_victory_overlay")
	return not get_tree().paused and not cycle.is_tutorial_active() and not cycle.is_night and not cycle.defeated and not shop.shop_open and not shop.shop_animating and (victory == null or not victory.visible) and not is_placing()

func is_placing() -> bool:
	return game.get("placing_coal") or game.get("placing_brass") or game.get("placing_belt") or game.get("placing_drill") or game.get("placing_launcher")

func kind_at(cell: Vector2i) -> String:
	if game.get("launchers").launchers.has(cell):
		return "launcher"
	if game.get("drills").drills.has(cell):
		return "drill"
	if game.get("conveyors").belts.has(cell):
		return "belt"
	return game.get("mining").vein_at(cell)

func manager_for(kind: String) -> RefCounted:
	return game.get({"coal": "mining", "brass": "mining", "belt": "conveyors", "drill": "drills", "launcher": "launchers"}.get(kind, "mining"))

func price_at(cell: Vector2i) -> int:
	var kind: String = kind_at(cell)
	if kind.is_empty():
		return 0
	var level: int = manager_for(kind).level_at(cell)
	return int(PRICES[kind][level - 1]) if level < 3 else 0

func upgrade_at(cell: Vector2i) -> bool:
	if not can_edit():
		return false
	var kind: String = kind_at(cell)
	if kind.is_empty():
		return false
	var manager: RefCounted = manager_for(kind)
	var price: int = price_at(cell)
	if manager.level_at(cell) >= 3 or not game.get("economy").spend(price):
		return false
	if not manager.upgrade(cell):
		if not game.get("economy").developer_mode:
			game.get("economy").add(price)
		return false
	game.redraw_world()
	return true

func on_upgrade_pressed() -> void:
	upgrade_at(selected_cell)
	refresh_panel()

func number(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".").replace(".", ",")

func refresh_panel() -> void:
	var kind: String = kind_at(selected_cell)
	if kind.is_empty():
		panel.hide()
		return
	var manager: RefCounted = manager_for(kind)
	var level: int = manager.level_at(selected_cell)
	title.text = "%s · %s" % [NAMES[kind], ["I", "II", "III"][level - 1]]
	var maximum: bool = level >= 3
	var arrow: String = "" if maximum else " → "
	match kind:
		"coal", "brass":
			var clicks: int = manager.clicks_required(selected_cell)
			stats.text = "%d%s%s clics" % [clicks, arrow, "" if maximum else str(maxi(3, clicks - 2))]
		"belt", "drill":
			var interval: float = manager.interval_at(selected_cell)
			var next: float = interval - (1.0 if kind == "belt" else 0.15)
			stats.text = "%s%s%s s" % [number(interval), arrow, "" if maximum else number(next)]
		"launcher":
			var damage: float = manager.damage_at(selected_cell)
			var next_damage: float = 0.65 if level == 1 else 0.75
			stats.text = "Daño %s%s%s\nCarga %d%s%s · %s%s%s s" % [number(damage), arrow, "" if maximum else number(next_damage), manager.capacity_at(selected_cell), arrow, "" if maximum else str(6 if level == 1 else 8), number(manager.interval_at(selected_cell)), arrow, "" if maximum else number(manager.interval_at(selected_cell) - 0.5)]
	upgrade_button.text = "NIVEL MÁXIMO" if maximum else "MEJORAR · %d" % price_at(selected_cell)
	upgrade_button.disabled = maximum or not can_edit() or not game.get("economy").can_afford(price_at(selected_cell))

func show_for_cell(cell: Vector2i, point: Vector2) -> bool:
	if not can_edit() or kind_at(cell).is_empty():
		return false
	selected_cell = cell
	refresh_panel()
	panel.reset_size()
	var local: Vector2 = screen.get_global_transform_with_canvas().affine_inverse() * point
	panel.position = local + Vector2(12, 12)
	panel.position.x = clampf(panel.position.x, 8, maxf(8, screen.size.x - panel.size.x - 8))
	panel.position.y = clampf(panel.position.y, 8, maxf(8, screen.size.y - panel.size.y - 8))
	panel.show()
	return true

func over_ui(point: Vector2) -> bool:
	for control: Control in [shop.get_node("CyclePanel"), shop.view_button, shop.shop_button, shop.money_box, shop.progression_panel]:
		var local: Vector2 = control.get_global_transform_with_canvas().affine_inverse() * point
		if control.is_visible_in_tree() and Rect2(Vector2.ZERO, control.size).has_point(local):
			return true
	return false

func _process(_delta: float) -> void:
	# A legacy scene may have its own purchase methods. Refund any locked item.
	var item: String = "brass" if game.get("placing_brass") else ("drill" if game.get("placing_drill") else (str(game.get("belt_shape")) if game.get("placing_belt") else ""))
	if not item.is_empty() and not game.get("progression").is_item_unlocked(item):
		game.cancel_placement()
	if panel.visible:
		if not can_edit():
			panel.hide()
		else:
			refresh_panel()

func _input(event: InputEvent) -> void:
	if not can_edit() or not event is InputEventMouseButton:
		return
	if panel.visible:
		var local: Vector2 = panel.get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed and not Rect2(Vector2.ZERO, panel.size).has_point(local):
			panel.hide()
			get_viewport().set_input_as_handled()
		return
	if over_ui(event.position):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			right_press = event.position
		elif event.position.distance_to(right_press) < 8.0:
			right_press = Vector2.INF
			var cell: Vector2i = game.get("grid").world_to_cell(game.get_local_mouse_position())
			if show_for_cell(cell, event.position):
				game.get("camera_controller").dragging = false
				get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and game.get("holding_object") and not game.get("dragging_object") and game.get("held_object_type") in ["belt", "drill", "launcher"]:
		show_for_cell.call_deferred(game.get("held_object_cell"), event.position)
