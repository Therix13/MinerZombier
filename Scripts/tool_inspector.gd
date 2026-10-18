extends CanvasLayer

var game: Node2D
var overlay: Control
var contents: VBoxContainer
var heading: Label
var status: Label
var fuel_bar: ProgressBar
var kind: String = ""
var cell: Vector2i
var last_contents: String = ""
var withdraw_buttons: Dictionary = {}
var withdrawal_blocked: bool = false

func _ready() -> void:
	game = get_parent() as Node2D
	layer = 170
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.48)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 360
	panel.add_theme_stylebox_override("panel", game.get("shop").create_style("#352516", "#a87843", 3, 12))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	heading = game.get("shop").create_label("", 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close: Button = game.get("shop").create_button("×")
	close.custom_minimum_size = Vector2(40, 40)
	close.pressed.connect(close_inspector)
	header.add_child(close)
	status = game.get("shop").create_label("", 16)
	column.add_child(status)
	fuel_bar = ProgressBar.new()
	fuel_bar.max_value = 40
	fuel_bar.show_percentage = false
	fuel_bar.add_theme_stylebox_override("background", game.get("shop").create_style("#211d17", "#211d17", 0, 4))
	fuel_bar.add_theme_stylebox_override("fill", game.get("shop").create_style("#d98a38", "#d98a38", 0, 4))
	fuel_bar.custom_minimum_size.y = 8
	column.add_child(fuel_bar)
	contents = VBoxContainer.new()
	column.add_child(contents)
	overlay.hide()
	update_layout()
	get_viewport().size_changed.connect(update_layout)

func update_layout() -> void:
	var factor: float = game.get_node("CanvasLayer").scale.x
	scale = Vector2.ONE * factor
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	overlay.size = get_viewport().get_visible_rect().size / factor

func is_open() -> bool:
	return overlay != null and overlay.visible

func open_tool(tool_kind: String, at: Vector2i) -> void:
	if game.get("cycle").is_guided_tutorial_active() or get_tree().paused: return
	kind = tool_kind
	cell = at
	if not exists(): return
	heading.text = {"furnace": "HORNO · NV. 1", "compactor": "COMPACTADOR", "drill": "TALADRO", "launcher": "LANZAPEPITAS"}[kind]
	last_contents = ""
	withdrawal_blocked = false
	update_layout()
	overlay.show()
	refresh()

func close_inspector() -> bool:
	if not is_open(): return false
	overlay.hide()
	return true

func exists() -> bool:
	return game.get_node("WorldInteractions").stores().get(kind, {}).has(cell)

func inventory() -> Dictionary:
	var items: Array = []
	match kind:
		"furnace": items = game.get_node("Furnaces").machines[cell]["fuel_items"]
		"launcher": items = game.get("launchers").launchers[cell]["ammo"]
		"compactor":
			var data: Dictionary = game.get_node("Compactors").machines[cell]
			for index in range(int(data["count"])): items.append(data["kind"])
	var result: Dictionary = {}
	for item: String in items: result[item] = int(result.get(item, 0)) + 1
	return result

func refresh() -> void:
	if not exists():
		close_inspector()
		return
	var items: Dictionary = inventory()
	fuel_bar.visible = kind == "furnace"
	match kind:
		"furnace":
			fuel_bar.value = game.get_node("Furnaces").machines[cell]["fuel"]
			status.text = "Combustible · %d / 40" % int(fuel_bar.value)
		"compactor":
			var data: Dictionary = game.get_node("Compactors").machines[cell]
			status.text = "Material · %d / 2" % int(data["count"])
			if int(data["count"]) == 2: status.text += " · %.1f / 4 s" % float(data["elapsed"])
		"launcher": status.text = "Munición · %d / %d" % [game.get("launchers").launchers[cell]["ammo"].size(), game.get("launchers").capacity]
		"drill": status.text = "Sin materiales almacenados."
	if withdrawal_blocked: status.text += "\nNo hay casillas libres."
	var signature: String = var_to_str(items)
	if signature == last_contents: return
	last_contents = signature
	withdraw_buttons.clear()
	for child in contents.get_children():
		contents.remove_child(child)
		child.queue_free()
	for item: String in items:
		var button: Button = game.get("shop").create_art_button("ore:" + item, item)
		button.get_meta("price_label").text = "×%d · Retirar" % items[item]
		button.get_meta("price_label").show()
		button.tooltip_text = "Retirar una pepita a una casilla libre."
		button.pressed.connect(withdraw.bind(item))
		contents.add_child(button)
		withdraw_buttons[item] = button
	if items.is_empty() and kind != "drill": contents.add_child(game.get("shop").create_label("Vacío", 15))

func withdraw(item: String) -> bool:
	if not is_open() or not exists() or not inventory().has(item) or get_tree().paused or game.get("cycle").defeated or game.get("cycle").is_guided_tutorial_active(): return false
	var mining: RefCounted = game.get("mining")
	var candidates: Array = game.get("grid").owned_tiles.keys()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(cell) < b.distance_squared_to(cell))
	var destination := Vector2i(-999, -999)
	for at: Vector2i in candidates:
		if at != game.get("grid").sale_cell and mining.can_move_nugget(at):
			destination = at
			break
	if destination.x == -999:
		withdrawal_blocked = true
		refresh()
		return false
	withdrawal_blocked = false
	match kind:
		"furnace":
			if not game.get_node("Furnaces").remove_fuel(cell, item): return false
		"compactor":
			var machine: Node = game.get_node("Compactors")
			machine.machines[cell]["count"] = int(machine.machines[cell]["count"]) - 1
			machine.machines[cell]["elapsed"] = 0.0
			if int(machine.machines[cell]["count"]) == 0: machine.machines[cell]["kind"] = ""
			machine.changed.emit()
		"launcher":
			var ammo: Array = game.get("launchers").launchers[cell]["ammo"]
			ammo.remove_at(ammo.find(item))
			game.get("launchers").changed.emit()
	mining.items_for(item)[destination] = 1
	mining.changed.emit()
	refresh()
	return true

func _process(_delta: float) -> void:
	if is_open():
		if game.get("cycle").defeated or game.get("cycle").is_guided_tutorial_active() or (game.get("night_victory_overlay") != null and game.get("night_victory_overlay").visible): close_inspector()
		else: refresh()
