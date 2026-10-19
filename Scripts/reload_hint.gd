extends Control

const GuidePointer = preload("res://Scripts/tutorial_guide.gd").GuidePointer

var game: Node2D
var session: Node
var card: PanelContainer
var message: Label
var accept: Button
var pointer: Control
var active: bool = false
var weapon := Vector2i(-999,-999)
var pulse: float = 0.0
var last_defense: int = -1

func _ready() -> void:
	game = get_parent().get_parent()
	session = game.get_node("SaveGame")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card = PanelContainer.new()
	card.position = Vector2(20,138)
	card.custom_minimum_size.x = 270
	var style: StyleBoxFlat = game.shop.create_style("#192d26","#d6ae67",2,10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel",style)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",7)
	card.add_child(column)
	column.add_child(game.shop.create_label("Torreta sin munición",17,Color("#f0d39a")))
	message = game.shop.create_label("",14,Color("#c3d1ba"))
	message.custom_minimum_size.x = 246
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	accept = game.shop.create_button("Entendido")
	accept.custom_minimum_size.y = 30
	accept.add_theme_font_size_override("font_size",14)
	accept.pressed.connect(dismiss)
	column.add_child(accept)
	pointer = GuidePointer.new()
	add_child(pointer)
	hide()

func dismiss() -> void:
	active = false
	hide()

func find_empty_weapon() -> Vector2i:
	for cell: Vector2i in game.launchers.launchers:
		if game.launchers.is_active_position(cell) and game.launchers.launchers[cell]["ammo"].is_empty(): return cell
	return Vector2i(-999,-999)

func _process(delta: float) -> void:
	var night: bool = game.cycle.is_night and not game.cycle.defeated and not game.zombie_manager.retreat_started
	if not night:
		if active: dismiss()
		return
	if not active:
		if session.reload_hint_seen or not game.zombie_manager.active_wave or not game.phase_clock.can_tick(): return
		weapon = find_empty_weapon()
		if weapon == Vector2i(-999,-999): return
		if game.zombie_manager.living_zombies().is_empty(): return
		session.reload_hint_seen = true
		session.queue_save()
		active = true
		show()
	if not game.launchers.launchers.has(weapon) or not game.launchers.launchers[weapon]["ammo"].is_empty():
		dismiss()
		return
	var defense: bool = game.camera_controller.defense_view
	if int(defense) != last_defense:
		last_defense = int(defense)
		message.text = "Pulsa el pico o P para ir a la mina y recargar." if defense else "Arrastra una pepita a la torreta. Usa P para volver a defender."
	pointer.target = game.shop.view_button
	pointer.visible = defense and not game.shop.shop_open
	pulse += delta
	pointer.pulse = pulse
	if pointer.visible: pointer.queue_redraw()
