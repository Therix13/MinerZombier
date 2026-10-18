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

func wait_for_view() -> void:
	var deadline: int = Time.get_ticks_msec() + 3000
	while game.camera_controller.transitioning and Time.get_ticks_msec() < deadline:
		await process_frame
	await settle()

func control_point(control: Control) -> Vector2:
	return root.get_screen_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))

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
	var mine_position: Vector2 = game.camera.position
	game.start_night()
	check(controller.transitioning and game.camera.position.is_equal_approx(mine_position), "Switching to defense begins a camera movement without teleporting")
	await create_timer(0.15).timeout
	check(game.camera.position.y < mine_position.y and game.camera.position.y > controller.to_position.y, "The camera travels upward through an intermediate position")
	check(not mover.can_drop("launcher", platform, game.grid.defense_cell("right")), "World interactions wait until the camera finishes moving")
	await wait_for_view()
	var center: Vector2 = game.get_global_transform_with_canvas() * game.grid.get_cell_rect(game.grid.sale_cell).get_center()
	check(absf(center.x - root.get_visible_rect().size.x * 0.5) < 0.01, "The defense entrance is centered horizontally on the screen")
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
	var guide: Node = game.get_node("TutorialGuide")
	check(guide.resupply_step == 0 and shop.cycle_title.text == "Sin munición" and not shop.cycle_action.visible and guide.pointer.target == shop.view_button, "The first shortage points to the real mine button without a shortcut")
	var button: Button = shop.view_button
	var defense_position: Vector2 = game.camera.position
	await click(control_point(button))
	check(controller.transitioning and not controller.defense_view and game.camera.position.y > defense_position.y and game.camera.position.y < mine_position.y, "The marked mine button moves the camera downward smoothly")
	await wait_for_view()
	check(not controller.defense_view and button.text == "DEFENSIVA", "The mine opens during combat")
	check(guide.resupply_step == 1 and guide.resupply_targets() == [vein] and not shop.cycle_action.visible, "The lesson highlights extraction before reloading")
	check(game.cycle.is_night and manager.active_wave and not paused, "Changing views does not pause or complete the wave")
	var survivor: Node2D = get_nodes_in_group("zombies")[0]
	var health: float = manager.base_health
	survivor.attacking = true
	survivor.attack_timer = 0.0
	survivor._process(0.01)
	check(manager.base_health < health, "Enemies continue attacking while the mine is open")
	for i in range(7): await click(cell_point(vein))
	check(game.mining.nuggets_at(ore) == 1, "Real mine clicks produce a nugget during the night")
	check(guide.resupply_targets() == [ore, platform], "The lesson points from the extracted nugget to the weapon")
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
	check(guide.resupply_step == 2 and guide.pointer.target == button and not shop.cycle_action.visible, "Reloading points to the real defense button")
	await click(control_point(button))
	await wait_for_view()
	check(controller.defense_view and button.text == "MINA" and not guide.resupply_active(), "Returning to defense completes the lesson")
	await click(control_point(button))
	await wait_for_view()
	check(not controller.defense_view, "MINA remains available after the lesson")
	await toggle_key()
	await wait_for_view()
	check(controller.defense_view and button.text == "MINA", "P returns to defense during the same wave")
	await toggle_key()
	await wait_for_view()
	check(not controller.defense_view, "P can reopen the mine during the same wave")
	await toggle_key()
	await wait_for_view()
	game.launchers.advance(4.0)
	manager._process(3.0)
	await settle()
	check(game.cycle.day == 3 and not game.cycle.is_night and game.night_victory_overlay.visible, "The reloaded sixth shot completes the second night normally")
	check(not guide.resupply_active(), "The last killing shot does not show an empty-ammo lesson after victory")
	game.dismiss_night_victory_popup()
	await wait_for_view()
	game.launchers.receive(platform, "coal")
	game.start_night()
	await wait_for_view()
	var next_zombie: Node2D = get_nodes_in_group("zombies")[0]
	next_zombie.set_process(false)
	next_zombie.position = game.grid.get_cell_rect(platform).get_center() + Vector2(0, -50)
	game.launchers.advance(4.0)
	await settle()
	check(game.cycle.is_night and not game.cycle.has_ammo() and not guide.resupply_active(), "Later shortages do not repeat the completed lesson")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; night resupply=", scene)
	quit(1 if failed else 0)
