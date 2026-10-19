extends CanvasLayer

var session: Node
var screen: Control
var main_page: VBoxContainer
var confirmation: VBoxContainer
var continue_button: Button
var new_button: Button
var summary: Label
var message: Label
var load_page: VBoxContainer
var file_list: VBoxContainer
var file_scroll: ScrollContainer
var file_buttons: Dictionary = {}

func _ready() -> void:
	layer = 250
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen)
	var backdrop := MineBackdrop.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440,0)
	var style: StyleBoxFlat = session.game.shop.create_style("#192d26", "#d4ac68", 2, 18)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 28
	style.content_margin_bottom = 26
	style.shadow_color = Color(0,0,0,0.55)
	style.shadow_size = 22
	panel.add_theme_stylebox_override("panel",style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	panel.add_child(column)
	var art_row := HBoxContainer.new()
	art_row.alignment = BoxContainer.ALIGNMENT_CENTER
	art_row.add_theme_constant_override("separation",14)
	column.add_child(art_row)
	for kind: String in ["ore:coal_3","ore:copper_ingot_3","launcher"]:
		art_row.add_child(session.game.shop.create_item_preview(kind,Vector2(58,58)))
	add_text(column,"MINER ZOMBIER",34,Color("#ffe0a1"))
	add_text(column,"Extrae · Fusiona · Resiste",15,Color("#aac7b2"))
	var line := HSeparator.new()
	column.add_child(line)
	main_page = VBoxContainer.new()
	main_page.add_theme_constant_override("separation",11)
	column.add_child(main_page)
	continue_button = button("CARGAR PARTIDA")
	continue_button.pressed.connect(show_load_page)
	main_page.add_child(continue_button)
	summary = add_text(main_page,"",13,Color("#aac7b2"))
	new_button = button("NUEVA PARTIDA")
	new_button.pressed.connect(request_new_game)
	main_page.add_child(new_button)
	var exit := button("SALIR")
	exit.pressed.connect(session.quit_game)
	main_page.add_child(exit)
	load_page = VBoxContainer.new()
	load_page.add_theme_constant_override("separation",10)
	column.add_child(load_page)
	add_text(load_page,"ARCHIVOS DE PARTIDA",21,Color("#ffe0a1"))
	add_text(load_page,"Continúa tu partida o vuelve al inicio de un día.",13,Color("#aac7b2"))
	file_scroll = ScrollContainer.new()
	file_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	load_page.add_child(file_scroll)
	file_list = VBoxContainer.new()
	file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_list.add_theme_constant_override("separation",8)
	file_scroll.add_child(file_list)
	var back := button("VOLVER")
	back.pressed.connect(close_load_page)
	load_page.add_child(back)
	load_page.hide()
	confirmation = VBoxContainer.new()
	confirmation.add_theme_constant_override("separation",12)
	column.add_child(confirmation)
	add_text(confirmation,"¿Empezar de nuevo?",22,Color("#ffe0a1"))
	add_text(confirmation,"Al guardar, se iniciará un nuevo archivo de días.",14,Color("#e0c4a3"))
	var confirm := button("CREAR NUEVA PARTIDA")
	confirm.pressed.connect(func(): session.begin("new"))
	confirmation.add_child(confirm)
	var cancel := button("CANCELAR")
	cancel.pressed.connect(cancel_confirmation)
	confirmation.add_child(cancel)
	confirmation.hide()
	message = add_text(column,"Usa «Guardar y salir» para conservar tu progreso.",12,Color("#90a68f"))
	session.status_changed.connect(func(text: String, success: bool):
		if not success: message.text = text
	)
	get_viewport().size_changed.connect(update_layout)
	session.game.display_settings.changed.connect(update_layout)
	update_layout()

func button(text: String) -> Button:
	var result: Button = session.game.shop.create_button(text)
	result.custom_minimum_size.y = 48
	result.add_theme_font_size_override("font_size",17)
	return result

func add_text(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label: Label = session.game.shop.create_label(text,font_size,color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func update_layout() -> void:
	var factor: float = session.game.display_settings.interface_scale()
	scale = Vector2.ONE * factor
	screen.size = get_viewport().get_visible_rect().size / factor
	file_scroll.custom_minimum_size.y = clampf(screen.size.y - 370,110,300)

func show_screen() -> void:
	show()
	main_page.show()
	load_page.hide()
	confirmation.hide()
	refresh_save()
	update_layout()
	if continue_button.disabled: new_button.grab_focus()
	else: continue_button.grab_focus()

func refresh_save() -> void:
	var data: Dictionary = session.read_save()
	continue_button.disabled = data.is_empty()
	if data.is_empty() and (FileAccess.file_exists(session.path) or FileAccess.file_exists(session.path + ".bak")):
		summary.text = "No se pudo leer la partida guardada."
		return
	summary.text = "Aún no hay una partida guardada." if data.is_empty() else "Día %d · %d monedas · %s" % [data["cycle"]["day"],data["coins"],"Noche" if data["cycle"]["is_night"] else "Preparación"]

func show_load_page() -> void:
	for child: Node in file_list.get_children():
		file_list.remove_child(child)
		child.queue_free()
	file_buttons.clear()
	for entry: Dictionary in session.list_saves():
		var action: String = entry["action"]
		var card := button("")
		card.custom_minimum_size.y = 82
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.pressed.connect(func(): session.begin(action))
		var content := HBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 14
		content.offset_right = -14
		content.add_theme_constant_override("separation",14)
		card.add_child(content)
		var icon: Control = session.game.shop.create_item_preview("ore:copper_ingot_3" if action == "continue" else "ore:coal_3",Vector2(44,44))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(icon)
		var texts := VBoxContainer.new()
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(texts)
		var title: Label = add_text(texts,"Último guardado · Día %d" % entry["day"] if action == "continue" else "Día %d · Inicio del día" % entry["day"],17,Color("#ffe0a1"))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		var detail: String = "%d monedas · %s" % [entry["coins"],("Noche" if entry["night"] else "Partida en curso") if action == "continue" else "06:00"]
		var subtitle: Label = add_text(texts,detail,13,Color("#aac7b2"))
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
		file_list.add_child(card)
		file_buttons[action] = card
	main_page.hide()
	confirmation.hide()
	load_page.show()
	file_scroll.scroll_vertical = 0
	update_layout()
	if not file_buttons.is_empty(): file_buttons.values()[0].grab_focus()

func close_load_page() -> void:
	load_page.hide()
	main_page.show()
	continue_button.grab_focus()

func request_new_game() -> void:
	if session.read_save().is_empty():
		session.begin("new")
		return
	main_page.hide()
	confirmation.show()
	confirmation.get_child(2).grab_focus()

func cancel_confirmation() -> void:
	confirmation.hide()
	main_page.show()
	new_button.grab_focus()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		if confirmation.visible: cancel_confirmation()
		elif load_page.visible: close_load_page()
		get_viewport().set_input_as_handled()

class MineBackdrop extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("#101e24"))
		var horizon: float = size.y * 0.42
		var center_x: float = size.x * 0.5
		draw_circle(Vector2(size.x*0.82,horizon*0.35),38,Color("#697d71"))
		draw_circle(Vector2(size.x*0.82+13,horizon*0.35-8),34,Color("#101e24"))
		for index in range(12):
			var x: float = float(index) * size.x / 11
			var height: float = 60 + float(index%4)*22
			draw_colored_polygon(PackedVector2Array([Vector2(x-75,horizon+15),Vector2(x,horizon-height),Vector2(x+75,horizon+15)]),Color("#1d342e"))
		draw_rect(Rect2(0,horizon,size.x,size.y-horizon),Color("#172a25"))
		var tile: float = 52
		for y in range(int((size.y-horizon)/tile)+1):
			for x in range(int(size.x/tile)+1):
				var rect := Rect2(float(x)*tile,horizon+float(y)*tile,tile-1,tile-1)
				draw_rect(rect,Color("#233b30") if absi(int(float(x)*tile-center_x)) < 265 else Color("#192b29"))
				if x%4 == 0 and y%3 == 1:
					draw_circle(rect.position+Vector2(17,19),4,Color("#435244"))
		# A quiet mine entrance and copper rails frame the menu without animating the world.
		for x: float in [center_x-295,center_x+295]:
			draw_rect(Rect2(x-4,horizon-6,8,size.y-horizon+6),Color("#8f6c3d"))
			for y in range(int((size.y-horizon)/tile)+1):
				draw_rect(Rect2(x-17,horizon+float(y)*tile+22,34,7),Color("#6f5535"))
		draw_rect(Rect2(0,0,size.x,5),Color("#b58a4e"))
