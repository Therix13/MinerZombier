extends SceneTree

var passed: int = 0
var failed: int = 0
var game: Node2D
var upgrades: CanvasLayer

func _initialize() -> void:
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
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func mouse(point: Vector2, button: MouseButton) -> void:
	if DisplayServer.get_name() != "headless":
		# Input.warp_mouse takes window pixels, including fullscreen viewport scaling.
		Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await settle()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await settle()

func control_point(control: Control) -> Vector2:
	return root.get_screen_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))

func right_click(cell: Vector2i) -> void:
	var point: Vector2 = root.get_screen_transform() * (game.get_global_transform_with_canvas() * game.grid.get_cell_rect(cell).get_center())
	await mouse(point, MOUSE_BUTTON_RIGHT)

func run_checks() -> void:
	root.show()
	root.size = Vector2i(1280, 720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_name: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://" + scene_name).instantiate()
	if "--legacy" in args:
		var legacy_script: String = OS.get_environment("GODOT_LEGACY_MAIN")
		if legacy_script.is_empty():
			push_error("Set GODOT_LEGACY_MAIN when using --legacy.")
			quit(1)
			return
		game.set_script(load(legacy_script))
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	upgrades = game.get_node("BuildingUpgrades")
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	display.resolution = Vector2i(1280, 720)
	display.apply_display(false)
	await settle()
	game.grid.expand()
	game.economy.add(10000)
	var mining: RefCounted = game.mining
	var drills: RefCounted = game.drills
	var belts: RefCounted = game.conveyors
	var launchers: RefCounted = game.launchers
	var vein_a := Vector2i(14, 0)
	var vein_b := Vector2i(16, 0)
	mining.place_vein(vein_a, 1)
	mining.place_vein(vein_b, 1)
	var coins: int = game.economy.coins
	check(not upgrades.upgrade_at(vein_a) and game.economy.coins == coins, "Building upgrades cannot bypass the tutorial")
	game.cycle.day = 2
	game.cycle.changed.emit()
	game.progression.add_experience(1000)
	game.progression.research("drill")
	var points: int = game.progression.research_points
	check(upgrades.upgrade_at(vein_a) and game.economy.coins == coins - 100, "A building improvement spends the correct coin price once")
	check(game.progression.research_points == points, "Construction upgrades never spend research points")
	check(mining.clicks_required(vein_a) == 5 and mining.clicks_required(vein_b) == 7, "Improving one vein leaves the neighboring vein unchanged")
	for index in range(5):
		mining.mine(vein_a)
		mining.mine(vein_b)
	check(mining.nuggets_at(Vector2i(15, 0)) == 1 and mining.nuggets_at(Vector2i(17, 0)) == 0, "The improved vein actually produces ore earlier than its neighbor")
	mining.mine(vein_b)
	mining.mine(vein_b)
	check(mining.nuggets_at(Vector2i(17, 0)) == 1, "Unimproved veins still need seven actions")
	mining.remove_one_nugget(Vector2i(15, 0))
	mining.remove_one_nugget(Vector2i(17, 0))
	drills.place(Vector2i(14, 1), 0)
	drills.place(Vector2i(16, 1), 0)
	upgrades.upgrade_at(Vector2i(14, 1))
	drills.advance(0.45)
	check(mining.coal_veins[vein_a]["progress"] == 1 and mining.coal_veins[vein_b]["progress"] == 0, "Only the upgraded drill works at its faster interval")
	drills.advance(0.15)
	check(mining.coal_veins[vein_a]["progress"] == 1 and mining.coal_veins[vein_b]["progress"] == 1, "The neighboring drill retains its own clock")
	drills.advance(0.01)
	check(mining.coal_veins[vein_b]["progress"] == 1, "Fractional timer rounding does not grant a second mining action")
	var belt_a := Vector2i(13, 2)
	var belt_b := Vector2i(15, 2)
	belts.place(belt_a, 1)
	belts.place(Vector2i(14, 2), 1)
	belts.place(belt_b, 1)
	belts.place(Vector2i(16, 2), 1)
	mining.coal_nuggets[belt_a] = 1
	mining.coal_nuggets[belt_b] = 1
	upgrades.upgrade_at(belt_a)
	belts.advance(3.0)
	check(mining.nuggets_at(Vector2i(14, 2)) == 1 and mining.nuggets_at(belt_b) == 1, "Only the upgraded belt transports its ore after three seconds")
	belts.advance(1.0)
	check(mining.nuggets_at(Vector2i(16, 2)) == 1 and mining.nuggets_at(belt_b) == 0, "The neighboring belt retains its four-second interval")
	game.grid.purchase_defense_platforms()
	var left: Vector2i = game.grid.defense_cell("left")
	var right: Vector2i = game.grid.defense_cell("right")
	launchers.place(left)
	launchers.place(right)
	for index in range(5):
		launchers.receive(left, "coal")
		launchers.receive(right, "coal")
	upgrades.upgrade_at(left)
	check(launchers.capacity_at(left) == 6 and launchers.capacity_at(right) == 5, "Only the selected launcher's magazine expands")
	upgrades.upgrade_at(left)
	check(launchers.capacity_at(left) == 8 and is_equal_approx(launchers.damage_at(left), 0.75) and launchers.interval_at(left) == 3.0 and launchers.damage_at(right) == 0.5, "Level three improves the selected turret without changing other turrets")
	for index in range(3): check(launchers.receive(left, "coal"), "Expanded magazine accepts extra round %d" % index)
	check(not launchers.receive(left, "coal") and not launchers.receive(right, "coal"), "Magazine limits apply separately to each turret")
	var enemies: Array[Node2D] = []
	for cell: Vector2i in [left, right]:
		var enemy: Node2D = load("res://Scripts/zombie.gd").new()
		enemy.setup(game.grid.get_cell_rect(cell).get_center() + Vector2(0, -30), Vector2.ZERO, 10.0)
		game.add_child(enemy)
		enemy.set_process(false)
		enemies.append(enemy)
	launchers.advance(0.0)
	check(is_equal_approx(enemies[0].health, 9.25) and is_equal_approx(enemies[1].health, 9.5), "Real shots use each turret's own damage")
	launchers.advance(3.0)
	check(is_equal_approx(enemies[0].health, 8.5) and is_equal_approx(enemies[1].health, 9.5), "Only the upgraded turret fires again after three seconds")
	var saved_coins: int = game.economy.coins
	check(not upgrades.upgrade_at(left) and game.economy.coins == saved_coins, "A max-level turret cannot spend more coins")
	game.cycle.is_night = true
	check(not upgrades.upgrade_at(right) and game.economy.coins == saved_coins, "Nighttime upgrades are blocked without charging")
	game.cycle.is_night = false
	game.night_victory_overlay.show()
	check(not upgrades.upgrade_at(right), "Victory overlays block upgrades")
	game.night_victory_overlay.hide()
	paused = true
	check(not upgrades.upgrade_at(right), "Pause blocks upgrades")
	paused = false
	game.economy.coins = 0
	check(not upgrades.upgrade_at(right) and launchers.level_at(right) == 1, "Insufficient coins cannot improve a building")
	game.economy.coins = saved_coins
	var old_timer: float = float(drills.timers[Vector2i(14, 1)])
	check(drills.move(Vector2i(14, 1), Vector2i(12, 1), 0) and drills.level_at(Vector2i(12, 1)) == 2 and drills.timers[Vector2i(12, 1)] == old_timer, "Moving a drill preserves its improvement and its clock")
	check(belts.move(belt_a, Vector2i(12, 2), 1) and belts.level_at(Vector2i(12, 2)) == 2, "Moving a belt preserves its improvement")
	mining.move_vein(vein_a, Vector2i(12, 0), 1)
	check(mining.clicks_required(Vector2i(12, 0)) == 5 and mining.level_at(vein_b) == 1, "Moving a vein preserves its improvement without changing a neighbor")
	launchers.launchers.erase(right)
	var ammo_count: int = launchers.launchers[left]["ammo"].size()
	check(launchers.move(left, right) and launchers.level_at(right) == 3 and launchers.launchers[right]["ammo"].size() == ammo_count, "Moving a launcher preserves level, ammunition, and cooldown")
	for enemy in enemies: enemy.queue_free()
	await settle()
	await right_click(vein_b)
	check(upgrades.panel.visible and upgrades.selected_cell == vein_b and not game.camera_controller.dragging, "A real right click opens the selected building without leaving camera drag active")
	check(upgrades.panel.size.x <= 320 and upgrades.panel.size.y <= 220, "Building details stay in a compact panel without blank padding")
	coins = game.economy.coins
	await mouse(control_point(upgrades.upgrade_button), MOUSE_BUTTON_LEFT)
	check(mining.level_at(vein_b) == 2 and game.economy.coins == coins - 100, "The real upgrade button improves and charges only the selected building")
	if DisplayServer.get_name() != "headless" and "--capture" in args:
		var folder: String = OS.get_environment("RESEARCH_CAPTURE_DIR")
		if folder.is_empty(): folder = OS.get_user_data_dir()
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder.path_join("building-upgrade.png"))
		print("CAPTURE: ", folder.path_join("building-upgrade.png"))
	upgrades.panel.hide()
	var belt_cell := Vector2i(12, 2)
	var belt_point: Vector2 = root.get_screen_transform() * (game.get_global_transform_with_canvas() * game.grid.get_cell_rect(belt_cell).get_center())
	await mouse(belt_point, MOUSE_BUTTON_LEFT)
	check(upgrades.panel.visible and upgrades.selected_cell == belt_cell and not game.holding_object, "A real left click opens a machine's improvements after releasing selection")
	upgrades.panel.hide()
	display.resolution = Vector2i(2560, 1440)
	display.apply_display(false)
	await settle()
	await right_click(vein_b)
	check(upgrades.panel.visible and Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(upgrades.panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, upgrades.panel.size)), "QHD scaling keeps building controls within the visible viewport")
	game.queue_free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; upgrades=", scene_name)
	quit(1 if failed > 0 else 0)
