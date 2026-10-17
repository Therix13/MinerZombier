extends CanvasLayer

signal changed

enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }

const SETTINGS_PATH := "user://display_settings.cfg"
const PAUSE_ACTION: StringName = &"mine_defense_pause"
const INTERFACE_WIDTH: float = 1280.0
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var resolution := Vector2i(1920, 1080)
var window_mode: int = WindowMode.FULLSCREEN
var menu_open: bool = false
var previously_paused: bool = false
var previous_focus: WeakRef
var menu_root: Control
var overlay: Control
var pause_button: Button
var pause_page: VBoxContainer
var settings_page: VBoxContainer
var continue_button: Button
var settings_button: Button
var quit_button: Button
var apply_button: Button
var back_button: Button
var mode_selector: OptionButton
var resolution_selector: OptionButton
var status: Label
var pause_event_received: bool = false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action(PAUSE_ACTION):
		InputMap.add_action(PAUSE_ACTION)
		var pause_key := InputEventKey.new()
		pause_key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event(PAUSE_ACTION, pause_key)
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

func is_editor_embedded() -> bool:
	return Engine.is_embedded_in_editor() or get_window().is_embedded()

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
	# Migrate the previous two-mode configuration without losing preferences.
	var old_fullscreen: Variant = config.get_value("display", "fullscreen", true)
	if old_fullscreen is bool:
		window_mode = WindowMode.FULLSCREEN if old_fullscreen else WindowMode.WINDOWED
	var saved_mode: Variant = config.get_value("display", "mode", window_mode)
	if saved_mode is int and saved_mode in WindowMode.values():
		window_mode = saved_mode

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "width", resolution.x)
	config.set_value("display", "height", resolution.y)
	config.set_value("display", "mode", window_mode)
	config.set_value("display", "fullscreen", window_mode == WindowMode.FULLSCREEN)
	return config.save(SETTINGS_PATH)

func apply_display(persist: bool = true) -> void:
	var window: Window = get_window()
	# Render at the selected resolution, keeping the image's aspect ratio.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_factor = 1.0
	window.content_scale_size = resolution
	if DisplayServer.get_name() != "headless" and not is_editor_embedded():
		var screen_index: int = window.current_screen
		if window_mode == WindowMode.FULLSCREEN:
			window.unresizable = false
			window.borderless = false
			window.mode = Window.MODE_FULLSCREEN
		elif window_mode == WindowMode.BORDERLESS:
			window.mode = Window.MODE_WINDOWED
			window.borderless = true
			window.unresizable = true
			window.size = DisplayServer.screen_get_size(screen_index)
			window.position = DisplayServer.screen_get_position(screen_index)
		else:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			window.unresizable = false
			var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen_index)
			var available := Vector2i(maxi(usable.size.x - 40, 1), maxi(usable.size.y - 80, 1))
			var fit: float = minf(1.0, minf(float(available.x) / resolution.x, float(available.y) / resolution.y))
			window.min_size = Vector2i(mini(800, available.x), mini(450, available.y))
			window.size = Vector2i(Vector2(resolution) * fit)
			window.position = usable.position + (usable.size - window.size) / 2
	update_layout()
	changed.emit()
	if persist:
		var save_error: Error = save_settings()
		if status != null:
			status.text = display_hint(true)
			if save_error != OK:
				status.text += "\nNo se pudo guardar la selección para el próximo inicio."

func display_hint(applied: bool = false) -> String:
	if is_editor_embedded():
		return "El editor controla esta ventana. Ejecuta el juego en una ventana independiente para probar los modos de pantalla. La resolución sí se aplica."
	if applied:
		return "Configuración aplicada."
	return "Hasta 2560 × 1440 (2K / QHD).\nSin bordes y pantalla completa ocupan todo el monitor."

func update_layout() -> void:
	if menu_root == null:
		return
	scale = Vector2.ONE * interface_scale()
	menu_root.size = get_viewport().get_visible_rect().size / interface_scale()

func build_interface() -> void:
	menu_root = Control.new()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_root)
	pause_button = make_button("PAUSA · ESC")
	pause_button.tooltip_text = "Continuar, ajustes y salir del juego"
	pause_button.position = Vector2(214, 20)
	pause_button.size = Vector2(150, 58)
	pause_button.pressed.connect(open_menu)
	menu_root.add_child(pause_button)
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
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", make_style("#352516", "#a87843"))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var pages := VBoxContainer.new()
	margin.add_child(pages)
	pause_page = VBoxContainer.new()
	pause_page.add_theme_constant_override("separation", 16)
	pages.add_child(pause_page)
	add_label(pause_page, "PAUSA", 29)
	continue_button = make_button("CONTINUAR")
	continue_button.pressed.connect(close_menu)
	pause_page.add_child(continue_button)
	settings_button = make_button("AJUSTES")
	settings_button.pressed.connect(open_settings)
	pause_page.add_child(settings_button)
	quit_button = make_button("SALIR DEL JUEGO")
	quit_button.pressed.connect(quit_game)
	pause_page.add_child(quit_button)
	add_label(pause_page, "ESC: continuar · Retroceso: cancelar colocación al jugar", 15)
	settings_page = VBoxContainer.new()
	settings_page.add_theme_constant_override("separation", 14)
	pages.add_child(settings_page)
	add_label(settings_page, "AJUSTES DE PANTALLA", 27)
	add_label(settings_page, "Modo de ventana", 17)
	mode_selector = OptionButton.new()
	mode_selector.add_item("Ventana", WindowMode.WINDOWED)
	mode_selector.add_item("Ventana sin bordes", WindowMode.BORDERLESS)
	mode_selector.add_item("Pantalla completa", WindowMode.FULLSCREEN)
	mode_selector.custom_minimum_size.y = 42
	settings_page.add_child(mode_selector)
	add_label(settings_page, "Resolución del juego", 17)
	resolution_selector = OptionButton.new()
	for candidate: Vector2i in RESOLUTIONS:
		resolution_selector.add_item("%d × %d%s" % [candidate.x, candidate.y, " · 2K / QHD" if candidate.x == 2560 else ""])
	resolution_selector.custom_minimum_size.y = 42
	settings_page.add_child(resolution_selector)
	status = add_label(settings_page, display_hint(), 15)
	status.custom_minimum_size.y = 64
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	settings_page.add_child(row)
	apply_button = make_button("APLICAR")
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(apply_selection)
	row.add_child(apply_button)
	back_button = make_button("VOLVER")
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(show_pause_page)
	row.add_child(back_button)
	settings_page.hide()
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
	var focused: Control = get_viewport().gui_get_focus_owner()
	previous_focus = weakref(focused) if focused != null else null
	previously_paused = get_tree().paused
	menu_open = true
	overlay.show()
	get_tree().paused = true
	show_pause_page()

func show_pause_page() -> void:
	settings_page.hide()
	pause_page.show()
	continue_button.grab_focus()

func open_settings() -> void:
	if not menu_open:
		open_menu()
	mode_selector.select(window_mode)
	resolution_selector.select(RESOLUTIONS.find(resolution))
	status.text = display_hint()
	pause_page.hide()
	settings_page.show()
	mode_selector.grab_focus()

func close_menu() -> void:
	if not menu_open:
		return
	menu_open = false
	overlay.hide()
	get_tree().paused = previously_paused
	var focused: Control = previous_focus.get_ref() as Control if previous_focus != null else null
	if is_instance_valid(focused) and focused.is_visible_in_tree():
		focused.grab_focus()
	previous_focus = null

func apply_selection() -> void:
	window_mode = mode_selector.get_selected_id()
	resolution = RESOLUTIONS[resolution_selector.selected]
	apply_display()

func quit_game() -> void:
	get_tree().quit()

func toggle_pause_menu() -> void:
	if not menu_open:
		open_menu()
	elif settings_page.visible:
		show_pause_page()
	else:
		close_menu()

func _process(_delta: float) -> void:
	# Input state still updates when a Control or another _input callback
	# consumes ESC. Keep the shortcut working in that case, even when paused.
	if Input.is_action_just_pressed(PAUSE_ACTION) and not pause_event_received:
		toggle_pause_menu()
	pause_event_received = false

func handle_key_event(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed:
		return false
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		pause_event_received = true
		if not event.echo:
			toggle_pause_menu()
		return true
	if event.echo:
		return false
	if event.keycode == KEY_BACKSPACE and not get_tree().paused and get_parent().has_method("cancel_placement"):
		get_parent().cancel_placement()
		return true
	if event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER):
		if is_editor_embedded():
			open_settings()
		else:
			window_mode = WindowMode.WINDOWED if window_mode == WindowMode.FULLSCREEN else WindowMode.FULLSCREEN
			apply_display()
			mode_selector.select(window_mode)
		return true
	return false

func _input(event: InputEvent) -> void:
	if handle_key_event(event):
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if menu_open:
		get_tree().paused = previously_paused
