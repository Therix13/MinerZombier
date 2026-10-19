extends Control

var game: Node2D
var time_label: Label
var detail: Label
var action: Button
var bar: ProgressBar
var last_state: Array = []

func _ready() -> void:
	game = get_parent().get_parent()
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
	update_layout()
	update_clock()

func update_layout() -> void:
	var logical: Vector2 = get_viewport().get_visible_rect().size / game.ui_layer.scale.x
	size = Vector2(300,92 if game.cycle.is_night else 116)
	position = Vector2((logical.x - size.x) * 0.5,16)

func can_tick() -> bool:
	if game.get_tree().paused or game.cycle.defeated: return false
	if game.night_victory_overlay != null and game.night_victory_overlay.visible: return false
	if game.shop.unlock_notice_backdrop != null and game.shop.unlock_notice_backdrop.visible: return false
	return game.get_node_or_null("IntroCinematic") == null and game.get_node_or_null("BarrierBreach") == null

func on_action() -> void:
	if game.cycle.defeated: game.restart_game()
	elif game.cycle.can_start_night(): game.start_night()

func _process(_delta: float) -> void:
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
