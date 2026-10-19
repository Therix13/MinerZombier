extends SceneTree

var passed: int = 0
var failed: int = 0
var game: Node2D
var mover: Node

func _initialize() -> void:
	Engine.set_meta(&"mine_defense_skip_start_screen", true)
	Engine.set_meta(&"mine_defense_intro_seen", true)
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", description)
	else:
		failed += 1
		print("FAIL: ", description)

func settle() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func clear_items() -> void:
	for map in mover.stores().values(): map.clear()
	game.redraw_world()

func put(cell: Vector2i, data: Dictionary) -> void:
	for kind in data: mover.stores()[kind][cell] = data[kind].duplicate(true) if data[kind] is Dictionary or data[kind] is Array else data[kind]

func point(cell: Vector2i, offset := Vector2.ZERO) -> Vector2:
	return root.get_screen_transform() * (game.get_global_transform_with_canvas() * (game.grid.get_cell_rect(cell).get_center() + offset))

func mouse_move(at: Vector2) -> void:
	if DisplayServer.get_name() != "headless": Input.warp_mouse(at)
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	await settle()

func mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	await settle()

func drag(source: Vector2i, destination: Vector2i, offset := Vector2.ZERO) -> void:
	await mouse_move(point(source, offset))
	await mouse_button(point(source, offset), true)
	await mouse_move(point(destination))
	await mouse_button(point(destination), false)

func run_checks() -> void:
	root.show()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://" + scene).instantiate()
	if "--legacy" in args: game.set_script(load(OS.get_environment("GODOT_LEGACY_MAIN")))
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	display.resolution = Vector2i(1280, 720)
	display.window_mode = 0
	display.apply_display(false)
	await settle()
	mover = game.get_node("WorldInteractions")
	game.cycle.day = 2
	game.cycle.changed.emit()
	game.grid.expand()
	var a := Vector2i(14, 1)
	var b := Vector2i(16, 1)
	var samples := [
		{"coal_vein": {"direction": 3, "progress": 4}},
		{"copper_vein": {"direction": 3, "progress": 2}},
		{"drill": 3},
		{"belt": {"direction": 3, "shape": "junction"}, "coal": 3, "entry": 2},
		{"coal": 2},
		{"copper": 4},
	]
	var types := ["vein", "vein", "drill", "belt", "nugget", "nugget"]
	var coins: int = game.economy.coins
	for first in range(samples.size()):
		for second in range(samples.size()):
			clear_items()
			put(a, samples[first])
			put(b, samples[second])
			if first == 3 or second == 3:
				check(not mover.can_drop(types[first], a, b) and not mover.drop(types[first], a, b, 3) and mover.cell_data(a) == samples[first] and mover.cell_data(b) == samples[second], "Swap %d/%d cannot displace a loaded belt in either cell" % [first, second])
			elif first == second and types[first] == "vein":
				check(mover.drop("vein", a, b, 3) and mover.cell_data(a).is_empty() and game.mining.vein_level(b) == 2, "Matching level-one veins fuse rather than swap")
			else:
				check(mover.can_drop(types[first], a, b) and mover.drop(types[first], a, b, 3) and mover.cell_data(a) == samples[second] and mover.cell_data(b) == samples[first], "Swap %d/%d preserves both complete items and their resources" % [first, second])
	check(game.economy.coins == coins and game.progression.total_experience == 0, "Swapping never grants coins or EXP")
	var before: Dictionary = mover.cell_data(a)
	check(not mover.drop("nugget", a, Vector2i(0, 0)) and mover.cell_data(a) == before, "A rejected swap outside owned land preserves all contents")
	for ore: String in ["coal", "copper"]:
		clear_items()
		put(a, {"belt": {"direction": 1, "shape": "junction"}, "entry": 2, ore: 2})
		before = mover.cell_data(a)
		check(not mover.drop("belt", a, b) and not game.conveyors.move(a, b, 3) and not game.conveyors.move(a, a, 3) and mover.cell_data(a) == before, "A belt carrying %s cannot move or rotate through either manager" % ore)
		put(b, {"belt": {"direction": 0, "shape": "straight"}})
		check(not mover.swaps_contents("nugget", a, b) and mover.drop("nugget", a, b) and game.mining.nuggets_at(a) == 1 and game.mining.nuggets_at(b) == 1 and game.conveyors.belt_shape(a) == "junction" and game.conveyors.belt_shape(b) == "straight", "Ore can be removed onto another belt without moving either conveyor")
		game.mining.remove_one_nugget(a, ore)
		check(game.conveyors.move(a, a, 2) and mover.drop("belt", a, Vector2i(15, 2)) and game.conveyors.belts.has(Vector2i(15, 2)), "A cleared belt becomes movable again")
	clear_items()
	game.grid.purchase_defense_platforms()
	var left: Vector2i = game.grid.defense_cell("left")
	var right: Vector2i = game.grid.defense_cell("right")
	put(left, {"launcher": {"ammo": ["coal", "copper"], "cooldown": 2.3, "angle": 0.7}})
	put(right, {"launcher": {"ammo": ["copper"], "cooldown": 1.2, "angle": 1.3}})
	var left_data: Dictionary = mover.cell_data(left)
	var right_data: Dictionary = mover.cell_data(right)
	check(mover.drop("launcher", left, right) and mover.cell_data(left) == right_data and mover.cell_data(right) == left_data, "Launcher swaps preserve ammunition, cooldown, and aim")
	put(a, {"belt": {"direction": 1, "shape": "straight"}, "coal": 1})
	before = mover.cell_data(a)
	check(not mover.drop("belt", a, left) and mover.cell_data(a) == before and mover.cell_data(left) == right_data, "Invalid platform swaps preserve both buildings")
	check(mover.drop("nugget", a, left) and game.launchers.launchers[left]["ammo"].size() == 2 and game.conveyors.belts.has(a) and game.mining.nuggets_at(a) == 0, "Loading ammunition still consumes ore without moving its belt")
	put(a, {"coal": 1})
	check(mover.drop("nugget", a, game.grid.sale_cell) and game.economy.coins == coins + 5 and game.progression.total_experience == 1, "Selling still consumes one nugget and awards the normal rewards")
	clear_items()
	put(a, {"coal": 1})
	put(b, {"copper": 1})
	game.cycle.is_night = true
	check(not mover.drop("nugget", a, b), "Nighttime cannot bypass movement restrictions")
	game.cycle.is_night = false
	game.cycle.day = 1
	game.cycle.tutorial_step = 1
	check(not mover.drop("nugget", a, b), "Tutorial restrictions also apply to swaps")
	game.cycle.day = 2
	check_defense_warning()
	clear_items()
	put(a, {"belt": {"direction": 1, "shape": "straight"}})
	put(b, {"coal": 1})
	game.redraw_world()
	game.set_process(true)
	await settle()
	await drag(a, b)
	check(game.conveyors.belts.has(b) and game.mining.nuggets_at(a) == 1 and not game.holding_object, "A real drag swaps a belt with the nugget blocking its destination")
	clear_items()
	put(a, {"belt": {"direction": 1, "shape": "straight"}, "coal": 1})
	put(b, {"copper_vein": {"direction": 2, "progress": 5}})
	await drag(a, b, Vector2(18, 0))
	check(game.conveyors.belts.has(a) and game.mining.nuggets_at(a) == 1 and game.mining.copper_veins[b]["progress"] == 5 and not game.holding_object, "Dragging the edge cannot move a loaded belt or swap its destination")
	await drag(a, Vector2i(15, 2), Vector2(18, 0))
	check(game.conveyors.belts.has(a) and game.mining.nuggets_at(a) == 0 and game.mining.nuggets_at(Vector2i(15, 2)) == 1, "Dragging a loaded cell removes only its ore and leaves the conveyor in place")
	clear_items()
	put(a, {"coal_vein": {"direction": 1, "progress": 0}})
	await mouse_move(point(a))
	await mouse_button(point(a), true)
	await mouse_button(point(a), false)
	check(game.mining.coal_veins[a]["progress"] == 1, "Ordinary vein clicks still mine instead of swapping")
	display.open_menu()
	await settle()
	var labels: Array[String] = []
	for child in display.pause_page.get_children():
		if child is Label: labels.append(child.text)
	check(labels == ["PAUSA"], "Pause contains no footer help text")
	display.open_settings()
	await settle()
	labels.clear()
	for child in display.settings_page.get_children():
		if child is Label: labels.append(child.text)
	check(labels == ["AJUSTES", "Modo de ventana", "Resolución"], "Settings retains the current heading and window labels alongside audio controls")
	check(display.mode_selector.item_count == 3 and display.resolution_selector.item_count == 4, "All window modes and resolutions remain selectable")
	if DisplayServer.get_name() != "headless" and "--capture" in args:
		root.get_texture().get_image().save_png(OS.get_user_data_dir().path_join("clean-settings.png"))
	display.close_menu()
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; interactions=", scene)
	quit(1 if failed else 0)

func check_defense_warning() -> void:
	clear_items()
	game.cycle.day = 4
	game.cycle.changed.emit()
	check(game.cycle.needs_defense_warning() and "Alto riesgo" in game.shop.cycle_goal.text, "Night 4 warns when both purchased platforms are empty")
	var left: Vector2i = game.grid.defense_cell("left")
	var right: Vector2i = game.grid.defense_cell("right")
	game.launchers.place(left)
	game.launchers.receive(left, "coal")
	check(game.cycle.needs_defense_warning() and "2 torretas" in game.shop.cycle_goal.text and not game.shop.cycle_action.disabled, "One placed turret warns about defeat while still allowing the player to start")
	game.launchers.place(right)
	check(not game.cycle.needs_defense_warning() and not "Alto riesgo" in game.shop.cycle_goal.text, "Placing the second turret immediately clears the warning")
	game.launchers.launchers.erase(right)
	game.launchers.changed.emit()
	check(game.cycle.needs_defense_warning() and "Alto riesgo" in game.shop.cycle_goal.text, "Removing a turret immediately restores the risk warning")
	game.cycle.is_night = true
	game.cycle.changed.emit()
	check(not game.cycle.needs_defense_warning() and game.shop.cycle_goal.text == "Resiste la oleada y protege la entrada.", "The preparation warning is cleared once combat starts")
	game.cycle.is_night = false
	game.cycle.defeated = true
	game.cycle.changed.emit()
	check(not game.cycle.needs_defense_warning() and game.shop.cycle_title.text == "Base destruida", "The defeat screen does not show the preparation warning")
	game.cycle.defeated = false
	game.cycle.day = 3
	game.cycle.changed.emit()
	check(not game.cycle.needs_defense_warning() and not "Alto riesgo" in game.shop.cycle_goal.text, "Earlier nights keep their normal preparation message")
	game.cycle.day = 2
	game.cycle.changed.emit()
