extends CanvasLayer

var game: Node2D
var overlay: Control
var contents: GridContainer
var heading: Label
var status: Label
var heat_label: Label
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
	var panel := WoodPanel.new()
	panel.custom_minimum_size.x = 310
	panel.add_theme_stylebox_override("panel", game.get("shop").create_style("#805733", "#392818", 5, 12))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	heading = game.get("shop").create_label("CONTENIDO", 20)
	heading.add_theme_color_override("font_outline_color", Color("#352516"))
	heading.add_theme_constant_override("outline_size", 3)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close: Button = game.get("shop").create_button("×")
	close.custom_minimum_size = Vector2(40, 40)
	close.pressed.connect(close_inspector)
	header.add_child(close)
	status = game.get("shop").create_label("", 13, Color("#f0d5a4"))
	column.add_child(status)
	contents = GridContainer.new()
	contents.columns = 2
	contents.add_theme_constant_override("h_separation", 8)
	contents.add_theme_constant_override("v_separation", 8)
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
	heading.text = "CONTENIDO"
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
		"furnace": return game.get_node("Furnaces").stored_items(cell)
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
	match kind:
		"furnace":
			status.text = "Horno · Nv. 1"
			var data: Dictionary = game.get_node("Furnaces").machines[cell]
			if not str(data.get("input", "")).is_empty():
				status.text += " · %.1f / 4 s" % float(data.get("elapsed", 0.0)) if data.get("burning", false) else " · Sin combustible"
			if heat_label != null: heat_label.text = "%d / 40" % int(game.get_node("Furnaces").machines[cell]["fuel"])
		"compactor":
			var data: Dictionary = game.get_node("Compactors").machines[cell]
			status.text = "Compactador"
			if int(data["count"]) == 2: status.text += " · %.1f / 4 s" % float(data["elapsed"])
		"launcher": status.text = "Lanzapepitas"
		"drill": status.text = "Taladro"
	if withdrawal_blocked: status.text += " · Sin espacio libre."
	var signature: String = var_to_str(items)
	if signature == last_contents: return
	last_contents = signature
	withdraw_buttons.clear()
	heat_label = null
	for child in contents.get_children():
		contents.remove_child(child)
		child.queue_free()
	if kind == "furnace":
		var heat := make_slot()
		heat.tooltip_text = "Carbón Nv. 4: +20 combustible. El carbón convertido ya no puede retirarse."
		var flame := SlotSymbol.new()
		flame.flame = true
		flame.custom_minimum_size = Vector2(48, 48)
		heat_label = fill_slot(heat, flame, "%d / 40" % int(game.get_node("Furnaces").machines[cell]["fuel"]))
		contents.add_child(heat)
	for item: String in items:
		var button := make_slot()
		button.tooltip_text = game.get("shop").RESOURCE_LABELS.get(item, item) + "\nRetirar una unidad."
		var art: Control = game.get("shop").create_item_preview("ore:" + item)
		fill_slot(button, art, str(items[item]))
		button.pressed.connect(withdraw.bind(item))
		contents.add_child(button)
		withdraw_buttons[item] = button
	if items.is_empty():
		var empty := make_slot()
		empty.tooltip_text = "Entrada: pepita de latón Nv. 4." if kind == "furnace" else "Sin materiales almacenados."
		var tray := SlotSymbol.new()
		tray.custom_minimum_size = Vector2(48, 48)
		fill_slot(empty, tray, "—")
		contents.add_child(empty)

func make_slot() -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(126, 122)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_stylebox_override("normal", game.get("shop").create_style("#302113", "#c09355", 2, 12))
	slot.add_theme_stylebox_override("hover", game.get("shop").create_style("#49301a", "#e6bd79", 2, 12))
	slot.add_theme_stylebox_override("pressed", game.get("shop").create_style("#21180f", "#e6bd79", 2, 12))
	return slot

func fill_slot(slot: Button, art: Control, value: String) -> Label:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(art)
	var count: Label = game.get("shop").create_label(value, 18, Color("#fff0ce"))
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_color_override("font_outline_color", Color("#18130f"))
	count.add_theme_constant_override("outline_size", 3)
	column.add_child(count)
	return count

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
			if not game.get_node("Furnaces").remove_material(cell, item): return false
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

class WoodPanel extends PanelContainer:
	func _draw() -> void:
		draw_rect(Rect2(5, 68, size.x - 10, 9), Color("#ae7e48"))
		for x in [12.0, size.x - 12.0]:
			for y in [12.0, size.y - 12.0]:
				draw_circle(Vector2(x, y), 4, Color("#483b2b"))
				draw_circle(Vector2(x - 1, y - 1), 3, Color("#a9a593"))

class SlotSymbol extends Control:
	var flame: bool = false

	func _draw() -> void:
		var factor: float = minf(size.x, size.y) / 52.0
		draw_set_transform(size * 0.5, 0, Vector2.ONE * factor)
		if flame:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -23), Vector2(-9, -8), Vector2(-8, -2), Vector2(-14, -7), Vector2(-17, 6), Vector2(-12, 18), Vector2(0, 22), Vector2(13, 15), Vector2(16, 3), Vector2(7, -7), Vector2(5, 4), Vector2(0, 0)]), Color("#f08b22"))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -4), Vector2(-7, 7), Vector2(-4, 16), Vector2(4, 17), Vector2(9, 8), Vector2(4, 3), Vector2(3, 8)]), Color("#ffcf48"))
		else:
			draw_rect(Rect2(-17, -13, 34, 29), Color("#533d25"), false, 2)
			draw_line(Vector2(-11, 9), Vector2(11, 9), Color("#82623c"), 2)
