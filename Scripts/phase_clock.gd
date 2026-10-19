extends Control

var game: Node2D
var time_label: Label
var day_label: Label
var phase_icon: PhaseIcon
var action: Button
var last_state: Array = []
var speed_controls: HBoxContainer
var night_speed: int = 1

class PhaseIcon extends Control:
	var night: bool = false
	func _draw() -> void:
		var center := size * 0.5
		if night:
			draw_circle(center,10,Color("#d1e2e6"))
			draw_circle(center + Vector2(5,-4),9,Color("#192d26"))
		else:
			draw_circle(center,6,Color("#efc368"))
			for i in range(8):
				var ray := Vector2.RIGHT.rotated(i * TAU / 8)
				draw_line(center + ray * 9,center + ray * 12,Color("#efc368"),2,true)

class SpeedButton extends Button:
	var multiplier: int = 1
	var arrows: int = 1
	func _draw() -> void:
		var color := Color("#ffe2a0") if button_pressed else Color("#d7bc8c")
		var left: float = (size.x - (arrows * 8 - 2)) * 0.5
		for i in range(arrows):
			var at := Vector2(left + i * 8,8)
			draw_colored_polygon(PackedVector2Array([at,at + Vector2(0,12),at + Vector2(7,6)]),color)
		var label: String = "×%d" % multiplier
		var font: Font = ThemeDB.fallback_font
		draw_string(font,Vector2((size.x - font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x) * 0.5,35),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)


func _ready() -> void:
	game = get_parent().get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style: StyleBoxFlat = game.shop.create_style("#192d26","#8f7952",1,8)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	panel.add_child(row)
	phase_icon = PhaseIcon.new()
	phase_icon.custom_minimum_size = Vector2(26,26)
	phase_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(phase_icon)
	time_label = game.shop.create_label("06:00",19,Color("#f0d39a"))
	time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(time_label)
	day_label = game.shop.create_label("",12,Color("#a7baa4"))
	day_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(day_label)
	action = game.shop.create_button("»")
	action.custom_minimum_size = Vector2(28,26)
	action.tooltip_text = "Adelantar hasta las 22:00"
	action.pressed.connect(on_action)
	row.add_child(action)
	build_speed_controls()
	game.cycle.changed.connect(sync_speed)
	update_layout()
	update_clock()

func build_speed_controls() -> void:
	speed_controls = HBoxContainer.new()
	speed_controls.add_theme_constant_override("separation",4)
	add_child(speed_controls)
	var group := ButtonGroup.new()
	for index in range(3):
		var button := SpeedButton.new()
		button.multiplier = [1,2,4][index]
		button.arrows = index + 1
		button.custom_minimum_size = Vector2(48,42)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = index == 0
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Velocidad de la noche ×%d" % button.multiplier
		button.add_theme_stylebox_override("normal",game.shop.create_style("#61401e","#b98b50",2,7))
		button.add_theme_stylebox_override("hover",game.shop.create_style("#80592d","#f0ce87",2,7))
		button.add_theme_stylebox_override("pressed",game.shop.create_style("#91652f","#ffe2a0",3,7))
		button.pressed.connect(set_night_speed.bind(button.multiplier))
		speed_controls.add_child(button)
	sync_speed()

func set_night_speed(multiplier: int) -> void:
	if not game.cycle.is_night or game.cycle.defeated or multiplier not in [1,2,4]: return
	night_speed = multiplier
	sync_speed()

func sync_speed() -> void:
	var active: bool = game.cycle.is_night and not game.cycle.defeated
	if not active: night_speed = 1
	speed_controls.visible = active
	Engine.time_scale = float(night_speed) if active and can_tick() else 1.0
	for button: SpeedButton in speed_controls.get_children():
		button.set_pressed_no_signal(button.multiplier == night_speed)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func update_layout() -> void:
	var logical: Vector2 = get_viewport().get_visible_rect().size / game.ui_layer.scale.x
	size = Vector2(260 if game.cycle.defeated else 200,38)
	position = Vector2((logical.x - size.x) * 0.5,16)
	if speed_controls != null: speed_controls.position = Vector2(80,20) - position

func can_tick() -> bool:
	if game.get_tree().paused or game.cycle.defeated: return false
	if game.night_victory_overlay != null and game.night_victory_overlay.visible: return false
	if game.shop.unlock_notice_backdrop != null and game.shop.unlock_notice_backdrop.visible: return false
	return game.get_node_or_null("IntroCinematic") == null and game.get_node_or_null("BarrierBreach") == null

func on_action() -> void:
	if game.cycle.defeated: game.restart_game()
	elif game.cycle.can_start_night(): game.start_night()

func _process(_delta: float) -> void:
	sync_speed()
	update_clock()

func clock_minutes() -> int:
	if game.cycle.is_night:
		var elapsed: float = clampf(game.zombie_manager.wave_elapsed,0.0,120.0)
		return (22 * 60 + floori(elapsed / 120.0 * 8 * 60)) % (24 * 60)
	var elapsed: float = 300.0 - clampf(game.cycle.day_remaining,0.0,300.0)
	# The first day's tutorial is untimed and stays at sunrise until night begins.
	if game.cycle.day == 1: elapsed = 0.0
	return 6 * 60 + floori(elapsed / 300.0 * 16 * 60)

func update_clock() -> void:
	var cycle: RefCounted = game.cycle
	visible = true
	var minutes: int = clock_minutes()
	var signature: Array = [minutes,cycle.day,cycle.is_night,cycle.defeated,cycle.can_start_night()]
	if signature == last_state: return
	last_state = signature
	update_layout()
	time_label.text = "%02d:%02d" % [minutes / 60,minutes % 60]
	day_label.text = "Día %d" % cycle.day
	phase_icon.night = cycle.is_night
	phase_icon.queue_redraw()
	tooltip_text = "Noche · 22:00–06:00 · 2 minutos\nClic en un zombi para priorizarlo" if cycle.is_night else "Día · 06:00–22:00 · 5 minutos"
	if cycle.day == 1 and not cycle.is_night: tooltip_text = "Día 1 · Completa el tutorial para comenzar la primera noche"
	action.text = "»"
	action.tooltip_text = "Adelantar hasta las 22:00"
	action.visible = not cycle.is_night and cycle.can_start_night()
	action.disabled = not cycle.can_start_night()
	if cycle.defeated:
		time_label.text = "Base destruida"
		day_label.text = ""
		action.text = "↻"
		action.tooltip_text = "Nueva partida"
		action.visible = true
		action.disabled = false
