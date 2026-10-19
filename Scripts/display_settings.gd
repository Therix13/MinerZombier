extends CanvasLayer

signal changed

enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }

const TARGET_FPS := 120
const SETTINGS_PATH := "user://display_settings.cfg"
const PAUSE_ACTION: StringName = &"mine_defense_pause"
const INTERFACE_WIDTH: float = 1280.0
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var resolution := Vector2i(1920, 1080)
var window_mode: int = WindowMode.FULLSCREEN
var vsync_enabled := false
var vsync_checkbox: CheckBox
var menu_open: bool = false
var previously_paused: bool = false
var previous_focus: WeakRef
var menu_root: Control
var overlay: Control
var pause_page: VBoxContainer
var settings_page: VBoxContainer
var continue_button: Button
var settings_button: Button
var save_button: Button
var title_button: Button
var save_status: Label
var quit_button: Button
var apply_button: Button
var back_button: Button
var mode_selector: OptionButton
var resolution_selector: OptionButton
var pause_event_received: bool = false
var auto_click_enabled: bool = false
var auto_click_checkbox: CheckBox
var auto_click_prompt: Control
var auto_click_accept: Button
var auto_click_decline: Button
var auto_click_answer: Callable
var prompt_previously_paused: bool = false

func _ready() -> void:
	Engine.max_fps = TARGET_FPS
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
	load_gameplay_settings()
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
	var saved_vsync: Variant = config.get_value("display", "vsync", false)
	vsync_enabled = saved_vsync if saved_vsync is bool else false

func load_gameplay_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK: return
	var enabled: Variant = config.get_value("gameplay", "auto_click", false)
	auto_click_enabled = enabled if enabled is bool else false

func set_auto_click(enabled: bool) -> void:
	auto_click_enabled = enabled
	auto_click_checkbox.set_pressed_no_signal(enabled)
	if save_settings() != OK:
		push_warning("No se pudo guardar la opción de clic automático.")

func ask_auto_click(answer: Callable) -> void:
	auto_click_answer = answer
	prompt_previously_paused = get_tree().paused
	get_tree().paused = true
	auto_click_prompt.show()
	auto_click_accept.grab_focus()

func answer_auto_click(enabled: bool) -> void:
	if not auto_click_prompt.visible: return
	set_auto_click(enabled)
	auto_click_prompt.hide()
	get_tree().paused = prompt_previously_paused
	var answer: Callable = auto_click_answer
	auto_click_answer = Callable()
	if answer.is_valid(): answer.call()

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "width", resolution.x)
	config.set_value("display", "height", resolution.y)
	config.set_value("display", "mode", window_mode)
	config.set_value("display", "fullscreen", window_mode == WindowMode.FULLSCREEN)
	config.set_value("display", "vsync", vsync_enabled)
	config.set_value("gameplay", "auto_click", auto_click_enabled)
	return config.save(SETTINGS_PATH)

func apply_display(persist: bool = true) -> void:
	Engine.max_fps = TARGET_FPS
	var window: Window = get_window()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED, window.get_window_id())
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
		if save_error != OK:
			push_warning("No se pudo guardar la configuración de pantalla.")

func update_layout() -> void:
	if menu_root == null:
		return
	scale = Vector2.ONE * interface_scale()
	menu_root.size = get_viewport().get_visible_rect().size / interface_scale()

func build_interface() -> void:
	menu_root = Control.new()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_root)
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
	save_button = make_button("GUARDAR Y SALIR")
	save_button.pressed.connect(func():
		var saves: Node = get_parent().get_node_or_null("SaveGame")
		if saves != null: saves.return_to_start()
	)
	pause_page.add_child(save_button)
	save_button.tooltip_text = "Guarda tu partida y el inicio de cada día, y vuelve al menú principal."
	title_button = save_button
	save_status = Label.new()
	save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_status.add_theme_font_size_override("font_size",14)
	save_status.add_theme_color_override("font_color",Color("#bad4ab"))
	pause_page.add_child(save_status)
	quit_button = make_button("GUARDAR Y CERRAR EL JUEGO")
	quit_button.pressed.connect(quit_game)
	pause_page.add_child(quit_button)
	settings_page = VBoxContainer.new()
	settings_page.add_theme_constant_override("separation", 14)
	pages.add_child(settings_page)
	add_label(settings_page, "AJUSTES", 27)
	add_label(settings_page, "Modo de ventana", 17)
	mode_selector = OptionButton.new()
	mode_selector.add_item("Ventana", WindowMode.WINDOWED)
	mode_selector.add_item("Ventana sin bordes", WindowMode.BORDERLESS)
	mode_selector.add_item("Pantalla completa", WindowMode.FULLSCREEN)
	mode_selector.custom_minimum_size.y = 42
	settings_page.add_child(mode_selector)
	add_label(settings_page, "Resolución", 17)
	resolution_selector = OptionButton.new()
	for candidate: Vector2i in RESOLUTIONS:
		resolution_selector.add_item("%d × %d" % [candidate.x, candidate.y])
	resolution_selector.custom_minimum_size.y = 42
	settings_page.add_child(resolution_selector)
	vsync_checkbox = CheckBox.new()
	vsync_checkbox.text = "Sincronización vertical"
	vsync_checkbox.tooltip_text = "Evita cortes de imagen; los FPS se limitan a la frecuencia de tu pantalla."
	vsync_checkbox.button_pressed = vsync_enabled
	vsync_checkbox.custom_minimum_size.y = 32
	vsync_checkbox.add_theme_font_size_override("font_size", 17)
	vsync_checkbox.add_theme_color_override("font_color", Color("#f3dfb8"))
	settings_page.add_child(vsync_checkbox)
	auto_click_checkbox = CheckBox.new()
	auto_click_checkbox.text = "Clic automático sobre vetas"
	auto_click_checkbox.button_pressed = auto_click_enabled
	auto_click_checkbox.custom_minimum_size.y = 42
	auto_click_checkbox.add_theme_font_size_override("font_size", 19)
	auto_click_checkbox.add_theme_color_override("font_color", Color("#f3dfb8"))
	auto_click_checkbox.toggled.connect(set_auto_click)
	settings_page.add_child(auto_click_checkbox)
	add_label(settings_page, "Mina al dejar el ratón encima de una veta.", 16)
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
	build_auto_click_prompt()

func build_auto_click_prompt() -> void:
	auto_click_prompt = Control.new()
	auto_click_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(auto_click_prompt)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.03, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_click_prompt.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_click_prompt.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 520
	panel.add_theme_stylebox_override("panel", make_style("#352516", "#a87843"))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	add_label(column, "JUEGA A TU RITMO", 27)
	var description: Label = add_label(column, "Este juego requiere muchos clics.\n¿Quieres activar el clic automático?\n\nSolo mina vetas al dejar el ratón encima.\nPuedes cambiarlo en Ajustes.", 19)
	description.custom_minimum_size.x = 460
	auto_click_accept = make_button("ACTIVAR CLIC AUTOMÁTICO")
	auto_click_accept.pressed.connect(answer_auto_click.bind(true))
	column.add_child(auto_click_accept)
	auto_click_decline = make_button("CONTINUAR CON CLIC MANUAL")
	auto_click_decline.pressed.connect(answer_auto_click.bind(false))
	column.add_child(auto_click_decline)
	auto_click_prompt.hide()

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
	if menu_open or auto_click_prompt.visible:
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
	vsync_checkbox.button_pressed = vsync_enabled
	mode_selector.select(window_mode)
	resolution_selector.select(RESOLUTIONS.find(resolution))
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
	vsync_enabled = vsync_checkbox.button_pressed
	window_mode = mode_selector.get_selected_id()
	resolution = RESOLUTIONS[resolution_selector.selected]
	apply_display()

func quit_game() -> void:
	var saves: Node = get_parent().get_node_or_null("SaveGame")
	if saves != null: saves.quit_game()
	else: get_tree().quit()

func toggle_pause_menu() -> void:
	if not menu_open:
		open_menu()
	elif settings_page.visible:
		show_pause_page()
	else:
		close_menu()

func _process(_delta: float) -> void:
	if auto_click_prompt.visible: return
	if start_screen_open(): return
	# Input state still updates when a Control or another _input callback
	# consumes ESC. Keep the shortcut working in that case, even when paused.
	if Input.is_action_just_pressed(PAUSE_ACTION) and not pause_event_received:
		if not cancel_pending_action(): toggle_pause_menu()
	pause_event_received = false

func cancel_pending_action() -> bool:
	if menu_open or get_tree().paused: return false
	var interactions: Node = get_parent().get_node_or_null("WorldInteractions")
	return interactions != null and interactions.cancel_active()

func start_screen_open() -> bool:
	var saves: Node = get_parent().get_node_or_null("SaveGame")
	return saves != null and not saves.playing

func handle_key_event(event: InputEvent) -> bool:
	if auto_click_prompt.visible:
		return event is InputEventKey and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
	if start_screen_open(): return false
	if not event is InputEventKey or not event.pressed:
		return false
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		pause_event_received = true
		if not event.echo:
			if not cancel_pending_action(): toggle_pause_menu()
		return true
	if event.echo:
		return false
	if event.keycode == KEY_BACKSPACE and not get_tree().paused and get_parent().has_method("cancel_placement"):
		cancel_pending_action()
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
