extends SceneTree

const IntroScript = preload("res://Scripts/intro_cinematic.gd")
var passed: int = 0
var failed: int = 0
var game: Node2D
var intro: CanvasLayer
var scene_name: String = "main.tscn"
var capture: bool = false

func _initialize() -> void:
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

func load_game() -> void:
	game = load("res://" + scene_name).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	intro = game.get_node_or_null("IntroCinematic")

func go_to(value: float, filename: String = "") -> void:
	intro.elapsed = value
	intro.present_frame()
	await settle()
	if capture and not filename.is_empty() and DisplayServer.get_name() != "headless":
		var folder: String = OS.get_environment("INTRO_CAPTURE_DIR")
		if folder.is_empty():
			folder = OS.get_user_data_dir()
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder.path_join(filename + ".png"))
		print("CAPTURE: ", folder.path_join(filename + ".png"))

func send_key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await settle()

func click_skip() -> void:
	var button: Button = intro.skip_button
	var point: Vector2 = root.get_screen_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(root.get_screen_transform().affine_inverse() * point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await settle()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		Input.parse_input_event(event)
		await settle()

func skip_is_drawn() -> bool:
	var picture: Image = root.get_texture().get_image()
	var button: Button = intro.skip_button
	var rect: Rect2 = button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size)
	var lit_pixels: int = 0
	for y in range(ceili(rect.position.y), floori(rect.end.y)):
		for x in range(ceili(rect.position.x), floori(rect.end.x)):
			if picture.get_pixel(x, y).get_luminance() > 0.1:
				lit_pixels += 1
	return lit_pixels > 20

func pristine() -> bool:
	return game.economy.coins == 500 and game.progression.total_experience == 0 and game.cycle.day == 1 and game.cycle.tutorial_step == 0 and game.grid.owned_tiles.size() == 9 and game.launchers.launchers.is_empty() and get_nodes_in_group("zombies").is_empty()

func run_checks() -> void:
	root.show()
	root.size = Vector2i(1280, 720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		scene_name = args[0]
	capture = "--capture" in args
	await load_game()
	check(intro != null and paused and not game.ui_layer.visible, "Introduction starts automatically and hides and pauses gameplay")
	if intro == null:
		quit(1)
		return
	intro.set_process(false)
	game.display_settings.resolution = Vector2i(1280, 720)
	game.display_settings.apply_display(false)
	await settle()
	check(intro.layer < game.display_settings.layer, "Pause and display settings remain above the introduction")
	check(Engine.has_meta(IntroScript.SESSION_KEY), "A session marks its introduction as seen")
	check(pristine(), "Cinematic armies and buildings never enter the playable game state")
	await go_to(2.0, "intro-title")
	check(intro.title.text == "Día 0: El Comienzo De Todo" and intro.title.visible and intro.title.modulate.a == 1.0, "Opening card has the requested white title on black")
	await go_to(9.0, "intro-battle")
	check(not intro.title.visible and intro.fade.color.a == 0.0, "Opening card transitions into the battle")
	await send_key(KEY_P)
	await send_key(KEY_R)
	await send_key(KEY_F10)
	check(pristine() and not game.shop.shop_open and not game.camera_controller.defense_view, "Game hotkeys cannot mutate the paused tutorial during the film")
	await send_key(KEY_ESCAPE)
	check(game.display_settings.menu_open and paused, "Escape opens the real pause menu during the film")
	intro._process(2.0)
	check(intro.elapsed == 9.0, "Movie timeline freezes while pause or settings is open")
	game.display_settings.open_settings()
	check(game.display_settings.settings_page.visible, "Display settings are accessible without dismissing the introduction")
	await send_key(KEY_ESCAPE)
	await send_key(KEY_ESCAPE)
	check(not game.display_settings.menu_open and paused, "Closing pause returns to the movie while gameplay stays paused")
	intro._process(0.1)
	check(is_equal_approx(intro.elapsed, 9.1), "Movie continues after closing pause")
	await go_to(21.1, "intro-collapse")
	if DisplayServer.get_name() != "headless":
		check(skip_is_drawn(), "Skip text remains visibly drawn after returning from pause and settings")
	await go_to(24.4, "intro-overrun")
	check(intro.film.zombie_position(0).x < 340.0, "The horde visibly overruns the defenses and reaches the mine before the fall")
	await go_to(26.6, "intro-ruins")
	check(intro.film.abandoned and not intro.film.daylight, "The defeated mine becomes an abandoned ruin")
	await go_to(30.7, "intro-three-years")
	check(intro.title.visible and intro.title.text == "3 años después", "Time jump displays three years later")
	await go_to(38.3, "intro-arrival")
	check(intro.film.abandoned and intro.film.daylight, "The returning miner walks through the overgrown remains of the same mine")
	var display: CanvasLayer = game.display_settings
	display.resolution = Vector2i(2560, 1440)
	display.apply_display(false)
	await settle()
	check(intro.screen.size == Vector2(2560, 1440) and intro.frame.scale.is_equal_approx(Vector2(2, 2)), "Film and skip control scale correctly at QHD")
	await go_to(38.3, "intro-arrival-qhd")
	check(pristine(), "Completing the story does not grant coins, EXP, defenses, or enemies")
	intro._process(IntroScript.DURATION)
	await settle()
	check(not paused and game.ui_layer.visible and not game.has_node("IntroCinematic"), "Natural completion removes the film and resumes the tutorial")
	check(game.cycle.is_tutorial_active() and game.cycle.tutorial_step == 0, "The first guided tutorial step is ready after the arrival")
	check(not game.shop.cycle_action.disabled and not game.shop.cycle_action.text.is_empty(), "The tutorial purchase button becomes available")
	game.restart_game()
	await scene_changed
	await settle()
	game = current_scene
	check(not paused and not game.has_node("IntroCinematic"), "Restarting a game in the same session does not replay the film")
	# A fresh process/session still offers the introduction, including its skip button.
	game.free()
	Engine.remove_meta(IntroScript.SESSION_KEY)
	await load_game()
	intro.set_process(false)
	await go_to(6.0)
	var old_intro: WeakRef = weakref(intro)
	await click_skip()
	check(old_intro.get_ref() == null and not paused and game.ui_layer.visible, "The real skip button immediately releases the film and its pause")
	check(pristine() and game.cycle.is_tutorial_active(), "Skipping starts the same untouched tutorial")
	# Scene removal from external code must release an introduction-owned pause.
	game.free()
	Engine.remove_meta(IntroScript.SESSION_KEY)
	await load_game()
	intro.set_process(false)
	await send_key(KEY_ESCAPE)
	intro.queue_free()
	await settle()
	check(paused and game.display_settings.menu_open, "Removing the film preserves an open pause menu")
	game.display_settings.close_menu()
	check(not paused and game.ui_layer.visible, "Closing that menu no longer leaves the tutorial permanently paused")
	game.free()
	await settle()
	if "--realtime" in args:
		Engine.remove_meta(IntroScript.SESSION_KEY)
		await load_game()
		var start: int = Time.get_ticks_msec()
		await intro.finished
		await settle()
		var duration: float = float(Time.get_ticks_msec() - start) / 1000.0
		check(duration > 40.0 and duration < 50.0 and not paused, "The full introduction plays and finishes in real time without timeline jumps")
		check(pristine() and game.cycle.is_tutorial_active(), "Real-time playback hands control to a clean tutorial")
		game.free()
		await settle()
	print("RESULT: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
