extends Control

var game: Node2D
var time_label: Label
var detail: Label
var action: Button
var bar: ProgressBar
var last_state: Array = []
var speed_controls: HBoxContainer
var night_speed: int = 1

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
	var style: StyleBoxFlat = game.shop.create_style("#192d26","#b98b50",2,10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",3)
	panel.add_child(column)
	time_label = game.shop.create_label("",17,Color("#f0d39a"))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time_label)
	bar = ProgressBar.new()
	bar.custom_minimum_size.y = 5
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background",game.shop.create_style("#304335","#304335",0,3))
	bar.add_theme_stylebox_override("fill",game.shop.create_style("#d6ae67","#d6ae67",0,3))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bar)
	detail = game.shop.create_label("",10,Color("#b6c9b0"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)
	action = game.shop.create_button("Adelantar noche")
	action.custom_minimum_size.y = 28
	action.pressed.connect(on_action)
	column.add_child(action)
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
	size = Vector2(300,92 if game.cycle.is_night else 116)
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

func update_clock() -> void:
	var cycle: RefCounted = game.cycle
	visible = cycle.day > 1 or cycle.is_night or cycle.defeated
	if not visible: return
	var remaining: float = game.zombie_manager.remaining_time() if cycle.is_night else cycle.day_remaining
	var seconds: int = ceili(remaining)
	var signature: Array = [seconds,cycle.day,cycle.is_night,cycle.defeated,cycle.can_start_night(),game.zombie_manager.retreat_started]
	if signature == last_state: return
	last_state = signature
	update_layout()
	time_label.text = "%s %d · %02d:%02d" % ["HORDA" if cycle.is_night else "DÍA",cycle.day,seconds / 60,seconds % 60]
	bar.max_value = 120 if cycle.is_night else 300
	bar.value = remaining
	detail.text = game.zombie_manager.announcement() + "\nClic en un zombi para priorizarlo" if cycle.is_night else "Gestiona la base · La noche comenzará automáticamente"
	action.visible = not cycle.is_night
	action.disabled = not cycle.can_start_night()
	if cycle.defeated:
		time_label.text = "BASE DESTRUIDA"
		detail.text = "La horda ha roto la entrada."
		action.text = "Nueva partida"
		action.visible = true
		action.disabled = false
