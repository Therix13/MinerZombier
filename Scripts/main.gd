extends Node2D

const GridScript = preload("res://Scripts/grid_manager.gd")
const CameraScript = preload("res://Scripts/camera_controller.gd")
const EconomyScript = preload("res://Scripts/economy_manager.gd")
const MiningScript = preload("res://Scripts/mining_manager.gd")
const ShopScript = preload("res://Scripts/shop_manager.gd")
const RendererScript = preload("res://Scripts/world_renderer.gd")
const ConveyorScript = preload("res://Scripts/conveyor_manager.gd")
const DrillScript = preload("res://Scripts/drill_manager.gd")
const LauncherScript = preload("res://Scripts/potato_launcher_manager.gd")
const ZombieManagerScript = preload("res://Scripts/zombie_manager.gd")
const DefenseZoneScript = preload("res://Scripts/defense_zone.gd")
const CycleScript = preload("res://Scripts/day_night_manager.gd")
const ProgressionScript = preload("res://Scripts/progression_manager.gd")
const DisplaySettingsScript = preload("res://Scripts/display_settings.gd")

const DRAG_THRESHOLD := 8.0

var grid: RefCounted
var camera_controller: RefCounted
var economy: RefCounted
var mining: RefCounted
var conveyors: RefCounted
var drills: RefCounted
var launchers: RefCounted
var zombie_manager: Node2D
var defense_zone: Node2D
var cycle: RefCounted
var progression: RefCounted
var display_settings: CanvasLayer
var placing_free_launcher: bool = false
var shop: Control
var renderer: Node2D
var night_victory_overlay: Control
var night_victory_title: Label
var night_victory_shade: ColorRect
var night_victory_center: CenterContainer
var night_victory_continue_button: Button

var placement_paid: bool = false
var placing_coal: bool = false
var placing_brass: bool = false
var placing_belt: bool = false
var belt_shape: String = "straight"
var placing_drill: bool = false
var placing_launcher: bool = false
var placement_direction: int = 1
var holding_object: bool = false
var dragging_object: bool = false
var held_object_type: String = ""
var held_object_cell := Vector2i.ZERO
var drag_start_position := Vector2.ZERO
var drag_world_position := Vector2.ZERO

@onready var camera: Camera2D = $Camera2D
@onready var ui_layer: CanvasLayer = $CanvasLayer

func _ready() -> void:
	display_settings = DisplaySettingsScript.new()
	add_child(display_settings)
	grid = GridScript.new()
	economy = EconomyScript.new()
	progression = ProgressionScript.new()
	mining = MiningScript.new()
	mining.setup(grid)
	mining.changed.connect(redraw_world)
	mining.sale_completed.connect(on_sale_completed)
	conveyors = ConveyorScript.new()
	conveyors.setup(grid, mining)
	mining.conveyors = conveyors
	conveyors.changed.connect(redraw_world)
	conveyors.sale_completed.connect(on_sale_completed)
	drills = DrillScript.new()
	drills.setup(grid, mining, conveyors)
	drills.changed.connect(redraw_world)
	conveyors.drills = drills
	mining.drills = drills
	launchers = LauncherScript.new()
	launchers.setup(grid, mining, conveyors, drills, self)
	launchers.changed.connect(redraw_world)
	conveyors.launchers = launchers
	camera_controller = CameraScript.new()
	camera_controller.setup(camera, get_viewport(), grid)
	defense_zone = DefenseZoneScript.new()
	add_child(defense_zone)
	defense_zone.setup(grid)
	renderer = RendererScript.new()
	add_child(renderer)
	renderer.setup(grid, mining, conveyors, drills)
	renderer.launchers = launchers
	zombie_manager = ZombieManagerScript.new()
	add_child(zombie_manager)
	zombie_manager.setup(grid)
	zombie_manager.zombie_defeated.connect(on_zombie_defeated)
	cycle = CycleScript.new()
	cycle.setup(grid, mining, conveyors, launchers, economy)
	zombie_manager.wave_completed.connect(on_wave_completed)
	zombie_manager.base_destroyed.connect(on_base_destroyed)
	var old_label: Node = ui_layer.get_node_or_null("MoneyLabel")
	if old_label != null:
		old_label.hide()
	shop = ShopScript.new()
	ui_layer.add_child(shop)
	shop.setup(economy, grid)
	shop.set_cycle(cycle)
	shop.set_progression(progression)
	shop.night_requested.connect(start_night)
	shop.restart_requested.connect(restart_game)
	shop.technology_requested.connect(research_technology)
	shop.view_toggle_requested.connect(toggle_view)
	shop.expansion_requested.connect(buy_expansion)
	shop.coal_vein_requested.connect(buy_coal_vein)
	shop.brass_vein_requested.connect(buy_brass_vein)
	shop.conveyor_requested.connect(buy_conveyor)
	shop.corner_conveyor_requested.connect(buy_corner_conveyor)
	shop.left_corner_conveyor_requested.connect(buy_left_corner_conveyor)
	shop.junction_conveyor_requested.connect(buy_junction_conveyor)
	shop.drill_requested.connect(buy_drill)
	shop.launcher_requested.connect(buy_launcher)
	shop.left_defense_tile_requested.connect(buy_left_defense_tile)
	shop.right_defense_tile_requested.connect(buy_right_defense_tile)
	shop.defense_platforms_unlocked.connect(redraw_world)
	shop.defense_platforms_unlocked.connect(cycle.refresh_tutorial)
	build_night_victory_popup()
	display_settings.changed.connect(update_display_layout)
	get_viewport().size_changed.connect(update_display_layout)
	update_display_layout()
	redraw_world()

func update_display_layout() -> void:
	var factor: float = display_settings.interface_scale()
	ui_layer.scale = Vector2.ONE * factor
	shop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	shop.size = get_viewport().get_visible_rect().size / factor
	get_node("CapaVictoria").scale = Vector2.ONE * factor
	update_night_victory_layout()
	camera_controller.update_zoom_limits()

func _exit_tree() -> void:
	# RefCounted managers refer to each other. Break those cycles on scene
	# changes and shutdown so restarting does not retain the previous game.
	for manager in [cycle, mining, conveyors, drills, launchers]:
		if manager != null:
			manager.dispose()

func _process(delta: float) -> void:
	camera_controller.update()
	conveyors.advance(delta)
	drills.advance(delta)
	launchers.advance(delta)
	if cycle.is_night and not zombie_manager.active_wave and zombie_manager.wave_total > 0 and zombie_manager.spawn_count >= zombie_manager.wave_total and get_tree().get_nodes_in_group("zombies").is_empty():
		on_wave_completed()
	if holding_object:
		var mouse_position: Vector2 = get_viewport().get_mouse_position()
		if not dragging_object and mouse_position.distance_to(drag_start_position) >= DRAG_THRESHOLD:
			dragging_object = true
		if dragging_object:
			drag_world_position = get_local_mouse_position()
			redraw_world()
	var current_cell: Vector2i = grid.world_to_cell(get_local_mouse_position())
	var sale_hovered: bool = current_cell == grid.sale_cell and not shop.shop_open
	if current_cell != renderer.hovered_cell or sale_hovered != renderer.sale_hovered:
		renderer.hovered_cell = current_cell
		renderer.sale_hovered = sale_hovered
		redraw_world()

func redraw_world() -> void:
	renderer.placing_coal = placing_coal and not shop.shop_open
	renderer.placing_brass = placing_brass and not shop.shop_open
	renderer.placing_belt = placing_belt and not shop.shop_open
	renderer.placement_belt_shape = belt_shape
	renderer.held_belt_shape = conveyors.belt_shape(held_object_cell) if holding_object and held_object_type == "belt" else "straight"
	renderer.placing_drill = placing_drill and not shop.shop_open
	renderer.placing_launcher = placing_launcher and not shop.shop_open
	renderer.placement_direction = placement_direction
	renderer.holding_object = holding_object
	renderer.dragging_object = dragging_object
	renderer.held_object_type = held_object_type
	renderer.held_object_cell = held_object_cell
	renderer.drag_world_position = drag_world_position
	renderer.queue_redraw()

func buy_expansion() -> void:
	if not cycle.allows_action("expand"):
		return
	if cycle.is_night or cycle.defeated:
		return
	if grid.cave_width >= 7 or not economy.spend(economy.EXPANSION_PRICE):
		return
	grid.expand()
	cycle.refresh_tutorial()
	redraw_world()
	shop.close_shop()

func buy_brass_vein() -> void:
	get_node("WorldInteractions").select_item("brass")

func buy_coal_vein() -> void:
	get_node("WorldInteractions").select_item("coal")

func buy_conveyor() -> void:
	buy_belt("straight")

func buy_corner_conveyor() -> void:
	buy_belt("corner_right")

func buy_left_corner_conveyor() -> void:
	buy_belt("corner_left")

func buy_junction_conveyor() -> void:
	buy_belt("junction")

func buy_belt(shape: String) -> void:
	get_node("WorldInteractions").select_item(shape)

func buy_drill() -> void:
	get_node("WorldInteractions").select_item("drill")

func buy_left_defense_tile() -> void:
	buy_defense_tile("left")

func buy_right_defense_tile() -> void:
	buy_defense_tile("right")

func buy_defense_tile(_side: String) -> void:
	if not cycle.allows_action("unlock_defense"):
		return
	if cycle.is_night or cycle.defeated:
		return
	var left_cell: Vector2i = grid.defense_cell("left")
	var right_cell: Vector2i = grid.defense_cell("right")
	if grid.defense_tiles.has(left_cell) and grid.defense_tiles.has(right_cell):
		return
	if not economy.spend(economy.DEFENSE_TILE_PRICE):
		return
	if not grid.purchase_defense_platforms():
		if not economy.developer_mode:
			economy.add(economy.DEFENSE_TILE_PRICE)
		return
	cycle.refresh_tutorial()
	redraw_world()
	shop.close_shop()

func buy_launcher() -> void:
	get_node("WorldInteractions").select_item("launcher")

func cancel_placement() -> void:
	if placing_launcher:
		placing_launcher = false
		placing_free_launcher = false
		if placement_paid:
			economy.add(economy.LAUNCHER_PRICE)
	elif placing_brass:
		placing_brass = false
		if placement_paid:
			economy.add(economy.BRASS_VEIN_PRICE)
	elif placing_drill:
		placing_drill = false
		if placement_paid:
			economy.add(economy.DRILL_PRICE)
	elif placing_belt:
		placing_belt = false
		if placement_paid:
			economy.add(economy.CONVEYOR_PRICE)
	elif placing_coal:
		placing_coal = false
		if placement_paid:
			economy.add(economy.COAL_VEIN_PRICE)
	else:
		return
	placement_paid = false
	redraw_world()

func on_sale_completed(kind: String) -> void:
	economy.add(economy.BRASS_SELL_PRICE if kind == "brass" else economy.COAL_SELL_PRICE)
	progression.award_sale(kind)

func on_zombie_defeated() -> void:
	progression.add_experience(progression.ZOMBIE_EXPERIENCE)

func research_technology(technology_id: String) -> void:
	if not cycle.allows_action("research"):
		return
	if cycle.is_night or cycle.defeated or (night_victory_overlay != null and night_victory_overlay.visible):
		return
	progression.research(technology_id)

func _input(event: InputEvent) -> void:
	# Handle pause before placement, victory dialogs, or gameplay shortcuts.
	if display_settings != null and display_settings.handle_key_event(event):
		get_viewport().set_input_as_handled()
		return
	if display_settings != null and display_settings.menu_open:
		return
	if night_victory_overlay != null and night_victory_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			dismiss_night_victory_popup()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P or event.physical_keycode == KEY_P:
			toggle_view()
		elif event.keycode == KEY_F10 and cycle.allows_action("developer"):
			economy.toggle_developer_mode()
		elif event.keycode == KEY_R and not cycle.is_tutorial_active() and (placing_coal or placing_brass or placing_belt or placing_drill or placing_launcher or (holding_object and held_object_type in ["vein", "belt", "drill"])):
			placement_direction = (placement_direction + 1) % 4
			if holding_object:
				dragging_object = true
			redraw_world()
		elif event.keycode == KEY_BACKSPACE and (placing_coal or placing_brass or placing_belt or placing_drill or placing_launcher):
			cancel_placement()
	if event is InputEventMouseButton:
		camera_controller.handle_button(event, shop.shop_open or shop.shop_animating)
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			finish_object_interaction()

func _unhandled_input(event: InputEvent) -> void:
	if display_settings != null and display_settings.menu_open:
		return
	if night_victory_overlay != null and night_victory_overlay.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if cycle.is_night or cycle.defeated or shop.shop_open or holding_object:
			return
		var cell: Vector2i = grid.world_to_cell(get_local_mouse_position())
		var placing: String = "launcher" if placing_launcher else ("coal" if placing_coal else ("belt" if placing_belt else ("other" if placing_brass or placing_drill else "")))
		if not cycle.allows_world_press(cell, placing):
			return
		if get_node("WorldInteractions").placement_active():
			get_node("WorldInteractions").place_selected(cell)
			return
		if mining.nuggets_at(cell) > 0:
			held_object_type = "nugget"
		elif mining.vein_at(cell) != "":
			held_object_type = "vein"
			var vein: Dictionary = mining.veins_for(mining.vein_at(cell))[cell]
			placement_direction = int(vein["direction"])
		elif drills.drills.has(cell):
			held_object_type = "drill"
			placement_direction = int(drills.drills[cell])
		elif launchers.launchers.has(cell):
			held_object_type = "launcher"
		elif conveyors.belts.has(cell):
			held_object_type = "belt"
			placement_direction = conveyors.belt_direction(cell)
		else:
			return
		holding_object = true
		dragging_object = false
		held_object_cell = cell
		drag_start_position = get_viewport().get_mouse_position()
		drag_world_position = get_local_mouse_position()

func finish_object_interaction() -> void:
	if not holding_object:
		return
	var destination: Vector2i = grid.world_to_cell(get_local_mouse_position())
	if not cycle.allows_interaction(held_object_type, held_object_cell, destination, dragging_object):
		holding_object = false
		dragging_object = false
		held_object_type = ""
		redraw_world()
		return
	if not dragging_object and held_object_type == "vein":
		mining.mine(held_object_cell)
	elif dragging_object and held_object_type == "vein":
		if (not launchers.launchers.has(destination) and not conveyors.belts.has(destination) and not drills.drills.has(destination)) or destination == held_object_cell:
			mining.move_vein(held_object_cell, destination, placement_direction)
	elif dragging_object and held_object_type == "drill":
		if not launchers.launchers.has(destination):
			drills.move(held_object_cell, destination, placement_direction)
	elif dragging_object and held_object_type == "belt":
		conveyors.move(held_object_cell, destination, placement_direction)
	elif dragging_object and held_object_type == "launcher":
		launchers.move(held_object_cell, destination)
	elif dragging_object and held_object_type == "nugget":
		if launchers.can_receive(destination):
			var kind: String = mining.nugget_type(held_object_cell)
			if launchers.receive(destination, kind):
				mining.remove_one_nugget(held_object_cell, kind)
		else:
			mining.move_nugget(held_object_cell, destination)
	holding_object = false
	dragging_object = false
	held_object_type = ""
	redraw_world()

func toggle_view() -> void:
	if not cycle.allows_action("toggle_view"):
		return
	if cycle.is_night or cycle.defeated or (night_victory_overlay != null and night_victory_overlay.visible):
		return
	var next_view: bool = not camera_controller.defense_view
	camera_controller.set_defense_view(next_view)
	shop.set_view_mode(camera_controller.defense_view)

func start_night() -> void:
	if not cycle.can_start_night():
		return
	if placing_coal or placing_brass or placing_belt or placing_drill or placing_launcher:
		cancel_placement()
	holding_object = false
	dragging_object = false
	held_object_type = ""
	if not cycle.start_night():
		return
	camera_controller.set_defense_view(true)
	shop.set_view_mode(true)
	defense_zone.set_night(true)
	zombie_manager.start_wave(cycle.day)
	redraw_world()

func build_night_victory_popup() -> void:
	var victory_layer := CanvasLayer.new()
	victory_layer.name = "CapaVictoria"
	victory_layer.layer = 100
	add_child(victory_layer)
	night_victory_overlay = Control.new()
	night_victory_overlay.name = "VictoriaNocturna"
	night_victory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_layer.add_child(night_victory_overlay)
	night_victory_shade = ColorRect.new()
	night_victory_shade.color = Color(0.05, 0.04, 0.03, 0.75)
	night_victory_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	night_victory_overlay.add_child(night_victory_shade)
	night_victory_center = CenterContainer.new()
	night_victory_center.mouse_filter = Control.MOUSE_FILTER_PASS
	night_victory_overlay.add_child(night_victory_center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430.0, 215.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#352516")
	panel_style.border_color = Color("#c09352")
	panel_style.set_border_width_all(4)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	night_victory_center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	night_victory_title = Label.new()
	night_victory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	night_victory_title.add_theme_color_override("font_color", Color("#f3ca85"))
	night_victory_title.add_theme_font_size_override("font_size", 27)
	column.add_child(night_victory_title)
	var subtitle := Label.new()
	subtitle.text = "¡La mina ha resistido la oleada!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("#f0e0c8"))
	subtitle.add_theme_font_size_override("font_size", 16)
	column.add_child(subtitle)
	night_victory_continue_button = Button.new()
	night_victory_continue_button.text = "CONTINUAR"
	night_victory_continue_button.custom_minimum_size.y = 52.0
	night_victory_continue_button.add_theme_font_size_override("font_size", 18)
	night_victory_continue_button.add_theme_color_override("font_color", Color("#fff0d0"))
	night_victory_continue_button.add_theme_color_override("font_hover_color", Color("#ffdf9c"))
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color("#60401f")
	normal_style.border_color = Color("#a87843")
	normal_style.set_border_width_all(3)
	normal_style.set_corner_radius_all(8)
	night_victory_continue_button.add_theme_stylebox_override("normal", normal_style)
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color("#80562a")
	hover_style.border_color = Color("#e0ad66")
	night_victory_continue_button.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color("#352516")
	night_victory_continue_button.add_theme_stylebox_override("pressed", pressed_style)
	night_victory_continue_button.pressed.connect(dismiss_night_victory_popup)
	column.add_child(night_victory_continue_button)
	get_viewport().size_changed.connect(update_night_victory_layout)
	update_night_victory_layout()
	night_victory_overlay.hide()

func update_night_victory_layout() -> void:
	if night_victory_overlay == null:
		return
	var factor: float = display_settings.interface_scale() if display_settings != null else 1.0
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size / factor
	night_victory_overlay.position = Vector2.ZERO
	night_victory_overlay.size = viewport_size
	night_victory_shade.position = Vector2.ZERO
	night_victory_shade.size = viewport_size
	night_victory_center.position = Vector2.ZERO
	night_victory_center.size = viewport_size

func dismiss_night_victory_popup() -> void:
	if night_victory_overlay == null or not night_victory_overlay.visible:
		return
	night_victory_overlay.hide()
	camera_controller.set_defense_view(false)
	shop.set_view_mode(false)

func on_wave_completed() -> void:
	if not cycle.is_night:
		return
	var completed_night: int = cycle.day
	cycle.complete_night()
	defense_zone.set_night(false)
	night_victory_title.text = "Noche %d: Superada" % completed_night
	update_night_victory_layout()
	night_victory_overlay.show()
	night_victory_overlay.move_to_front()

func on_base_destroyed() -> void:
	cycle.lose_night()

func restart_game() -> void:
	get_tree().reload_current_scene()
