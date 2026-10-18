extends SceneTree

var passed: int = 0
var failed: int = 0
var game: Node2D

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
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func cell_point(cell: Vector2i) -> Vector2:
	return root.get_screen_transform() * (game.get_global_transform_with_canvas() * game.grid.get_cell_rect(cell).get_center())

func move_mouse(at: Vector2) -> void:
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

func click(at: Vector2) -> void:
	await move_mouse(at)
	await mouse_button(at, true)
	await mouse_button(at, false)

func toggle_key() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_P
		event.physical_keycode = KEY_P
		event.pressed = pressed
		Input.parse_input_event(event)
		await settle()

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
	var shop: Control = game.shop
	var controller: RefCounted = game.camera_controller
	var mover: Node = game.get_node("WorldInteractions")
	var vein := Vector2i(14, 0)
	var ore := Vector2i(15, 0)
	game.cycle.day = 2
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	game.mining.place_vein(vein, 1)
	var platform: Vector2i = game.grid.defense_cell("left")
	game.launchers.place(platform)
	for i in range(5): game.launchers.receive(platform, "coal")
	# Keep the entrance and mine visible together, as after the tutorial.
	game.camera.zoom = Vector2.ONE * 2.0
	game.camera.position = Vector2(744, 180)
	controller.clamp_position()
	game.cycle.changed.emit()
	game.start_night()
	await settle()
	check(game.cycle.is_night and controller.defense_view and not shop.view_button.disabled, "Night starts in defense with the mine button enabled")
	var manager: Node2D = game.zombie_manager
	manager.set_process(false)
	manager.spawn_zombie()
	manager.spawn_zombie()
	for zombie: Node2D in get_nodes_in_group("zombies"):
		zombie.set_process(false)
		zombie.position = game.grid.get_cell_rect(platform).get_center() + Vector2(0, -50)
	for i in range(5): game.launchers.advance(4.0)
	await settle()
	check(game.launchers.launchers[platform]["ammo"].is_empty() and get_nodes_in_group("zombies").size() == 1, "Five shots leave the second wave active with one wounded enemy")
	var button: Button = shop.view_button
	await click(root.get_screen_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5)))
	check(not controller.defense_view and button.text == "DEFENSIVA", "A real click on MINA opens the mine during combat")
	check(game.cycle.is_night and manager.active_wave and not paused, "Changing views does not pause or complete the wave")
	var survivor: Node2D = get_nodes_in_group("zombies")[0]
	var health: float = manager.base_health
	survivor.attacking = true
	survivor.attack_timer = 0.0
	survivor._process(0.01)
	check(manager.base_health < health, "Enemies continue attacking while the mine is open")
	for i in range(7): await click(cell_point(vein))
	check(game.mining.nuggets_at(ore) == 1, "Real mine clicks produce a nugget during the night")
	check(not mover.drop("vein", vein, Vector2i(13, 0)), "Mining at night does not unlock moving buildings")
	var ammo_connection: Vector2i = platform + Vector2i(0, 1)
	game.conveyors.place(ammo_connection, 0)
	check(mover.drop("nugget", ore, ammo_connection) and game.conveyors.belts.has(ammo_connection), "Night ore moves onto a belt without exchanging the belt's position")
	await move_mouse(cell_point(ammo_connection))
	await mouse_button(cell_point(ammo_connection), true)
	await move_mouse(cell_point(platform))
	await mouse_button(cell_point(platform), false)
	check(game.launchers.launchers[platform]["ammo"].size() == 1 and game.mining.nuggets_at(ammo_connection) == 0, "A real drag reloads the empty weapon with the extracted nugget")
	check(game.conveyors.belts.has(ammo_connection) and shop.shop_button.disabled, "Reloading preserves the belt and the nighttime shop lock")
	await toggle_key()
	check(controller.defense_view and button.text == "MINA", "P returns to defense during the same wave")
	await toggle_key()
	check(not controller.defense_view, "P can reopen the mine during the same wave")
	await toggle_key()
	game.launchers.advance(4.0)
	manager._process(0.01)
	await settle()
	check(game.cycle.day == 3 and not game.cycle.is_night and game.night_victory_overlay.visible, "The reloaded sixth shot completes the second night normally")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; night resupply=", scene)
	quit(1 if failed else 0)
