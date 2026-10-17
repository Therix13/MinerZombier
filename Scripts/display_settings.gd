extends CanvasLayer

signal changed

const SETTINGS_PATH := "user://display_settings.cfg"
const INTERFACE_WIDTH: float = 1280.0
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var resolution := Vector2i(1920, 1080)
var fullscreen: bool = true
var menu_open: bool = false
var previously_paused: bool = false
var menu_root: Control
var overlay: Control
var settings_button: Button
var mode_selector: OptionButton
var resolution_selector: OptionButton
var status: Label

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless":
		load_settings()
		apply_display(false)
	build_interface()
	update_layout()
	get_viewport().size_changed.connect(update_layout)

func interface_scale() -> float:
	if DisplayServer.get_name() == "headless" and get_window().content_scale_size == Vector2i.ZERO:
		return 1.0
	return float(resolution.x) / INTERFACE_WIDTH

func load_settings() -> void:
	var screen_size: Vector2i = DisplayServer.screen_get_size(get_window().current_screen)
	resolution = RESOLUTIONS[0]
	for candidate: Vector2i in RESOLUTIONS:
		if candidate.x <= screen_size.x and candidate.y <= screen_size.y:
			resolution = candidate
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var width: Variant = config.get_value("display", "width", resolution.x)
	var height: Variant = config.get_value("display", "height", resolution.y)
	if width is int and height is int and Vector2i(width, height) in RESOLUTIONS:
		resolution = Vector2i(width, height)
	var saved_mode: Variant = config.get_value("display", "fullscreen", true)
	if saved_mode is bool:
		fullscreen = saved_mode

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "width", resolution.x)
	config.set_value("display", "height", resolution.y)
	config.set_value("display", "fullscreen", fullscreen)
	return config.save(SETTINGS_PATH)

func apply_display(persist: bool = true) -> void:
	var window: Window = get_window()
	# The selected resolution is the actual 2D render target, capped at QHD.
	# Native fullscreen fills the monitor without changing its display mode.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_factor = 1.0
	window.content_scale_size = resolution
	if DisplayServer.get_name() != "headless" and not window.is_embedded():
		if fullscreen:
			window.mode = Window.MODE_FULLSCREEN
		else:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
			var available := Vector2i(maxi(usable.size.x - 40, 1), maxi(usable.size.y - 80, 1))
			var fit: float = minf(1.0, minf(float(available.x) / resolution.x, float(available.y) / resolution.y))
			window.min_size = Vector2i(mini(800, available.x), mini(450, available.y))
			window.size = Vector2i(Vector2(resolution) * fit)
			window.position = usable.position + (usable.size - window.size) / 2
	update_layout()
	changed.emit()
	if persist and save_settings() != OK and status != null:
		status.text = "Aplicado. No se pudo guardar la selección para el próximo inicio."

func update_layout() -> void:
	if menu_root == null:
		return
	scale = Vector2.ONE * interface_scale()
	menu_root.size = get_viewport().get_visible_rect().size / interface_scale()

func build_interface() -> void:
	menu_root = Control.new()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_root)
	settings_button = make_button("⚙")
	settings_button.tooltip_text = "Pantalla y resolución · F11: pantalla completa"
	settings_button.position = Vector2(214, 20)
	settings_button.size = Vector2(58, 58)
	settings_button.pressed.connect(open_menu)
	menu_root.add_child(settings_button)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_root.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.03, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	panel.add_theme_stylebox_override("panel", make_style("#352516", "#a87843"))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	add_label(column, "PANTALLA", 27)
	add_label(column, "Modo de pantalla", 17)
	mode_selector = OptionButton.new()
	mode_selector.add_item("Pantalla completa")
	mode_selector.add_item("Ventana")
	mode_selector.custom_minimum_size.y = 42
	column.add_child(mode_selector)
	add_label(column, "Resolución del juego", 17)
	resolution_selector = OptionButton.new()
	for candidate: Vector2i in RESOLUTIONS:
		resolution_selector.add_item("%d × %d%s" % [candidate.x, candidate.y, " · 2K / QHD" if candidate.x == 2560 else ""])
	resolution_selector.custom_minimum_size.y = 42
	column.add_child(resolution_selector)
	status = add_label(column, "La imagen se adapta al monitor sin deformarse.\nF11: alternar pantalla completa. Esc: cerrar.", 15)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var apply_button := make_button("APLICAR")
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(apply_selection)
	row.add_child(apply_button)
	var close_button := make_button("CERRAR")
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(close_menu)
	row.add_child(close_button)
	overlay.hide()

func add_label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#f3dfb8"))
	parent.add_child(label)
	return label

func make_style(background: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_stylebox_override("normal", make_style("#60401f", "#a87843"))
	button.add_theme_stylebox_override("hover", make_style("#80562a", "#e0ad66"))
	button.add_theme_stylebox_override("pressed", make_style("#352516", "#a87843"))
	return button

func open_menu() -> void:
	if menu_open:
		return
	mode_selector.select(0 if fullscreen else 1)
	resolution_selector.select(RESOLUTIONS.find(resolution))
	previously_paused = get_tree().paused
	menu_open = true
	overlay.show()
	get_tree().paused = true
	mode_selector.grab_focus()

func close_menu() -> void:
	if not menu_open:
		return
	menu_open = false
	overlay.hide()
	get_tree().paused = previously_paused
	settings_button.grab_focus()

func apply_selection() -> void:
	if mode_selector.selected == 0 and get_window().is_embedded():
		status.text = "Ejecuta el juego en una ventana independiente para usar pantalla completa."
		return
	resolution = RESOLUTIONS[resolution_selector.selected]
	fullscreen = mode_selector.selected == 0
	status.text = "Configuración aplicada. F11: alternar pantalla completa."
	apply_display()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER):
		if not get_window().is_embedded():
			fullscreen = not fullscreen
			apply_display()
			mode_selector.select(0 if fullscreen else 1)
		get_viewport().set_input_as_handled()
	elif menu_open and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if menu_open:
		get_tree().paused = previously_paused
