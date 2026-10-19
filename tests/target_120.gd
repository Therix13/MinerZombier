extends "res://tests/interactions.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.cycle.skip_tutorial()
	var display: CanvasLayer = game.display_settings
	display.resolution = Vector2i(1280,720)
	display.window_mode = 0
	display.apply_display(false)
	check(Engine.max_fps == 120 and not display.vsync_enabled,"The runtime targets 120 FPS without a 60 Hz VSync ceiling by default")
	display.open_settings()
	display.vsync_checkbox.button_pressed = true
	display.apply_selection()
	check(display.vsync_enabled and Engine.max_fps == 120,"Players can enable VSync while retaining the 120 FPS cap")
	display.vsync_enabled = false
	display.load_settings()
	check(display.vsync_enabled,"VSync preference persists across settings reloads")
	display.vsync_checkbox.button_pressed = false
	display.apply_selection()
	display.close_menu()
	var rhythm: Node = game.get_node("WorkshopRhythm")
	check(rhythm.make_score(false) == rhythm.music.stream and rhythm.make_effect("mine") == rhythm.sounds["mine"],"Restarted games reuse prepared audio instead of synthesizing it again")
	var redraws := [0]
	rhythm.draw.connect(func(): redraws[0] += 1)
	await settle()
	var idle_redraws: int = redraws[0]
	for frame in range(8): await process_frame
	check(redraws[0] == idle_redraws,"An empty workshop does not rebuild an empty effects canvas every frame")
	game.mining.place_vein(Vector2i(15,1),1)
	game.mining.mine(Vector2i(15,1))
	await settle()
	check(redraws[0] > idle_redraws,"Real mining still animates particles immediately")
	var intro: Node = load("res://Scripts/intro_cinematic.gd").new()
	game.add_child(intro)
	intro.set_process(false)
	intro.elapsed = 4
	intro.present_frame()
	await settle()
	var draws := [0,0,0]
	intro.film.renderer.draw.connect(func(): draws[0] += 1)
	intro.film.barrier.draw.connect(func(): draws[1] += 1)
	var actor: Node2D = intro.film.barrier.actors[0]
	actor.draw.connect(func(): draws[2] += 1)
	check(actor.body_sprite != null and actor.body_sprite.texture == load("res://Scripts/zombie.gd").get_body_atlas(),"Decorative zombies retain the same shared artwork as combat zombies")
	for frame in range(8):
		intro.film.time = 4 + frame * 0.02
		intro.film.present()
		await process_frame
	check(draws == [0,0,0],"Camera movement does not rebuild the paused factory, intact fence or idle zombie geometry")
	intro.film.breach = true
	intro.film.time = 4
	intro.film.present()
	await settle()
	check(draws[1] > 0 and intro.film.barrier.destruction > 0,"The fence redraws when it actually breaks")
	intro.finish()
	await settle()
	var enemy: Node2D = load("res://Scripts/zombie.gd").new()
	enemy.setup(Vector2(0,-100),Vector2.ZERO,10)
	game.add_child(enemy)
	enemy.set_process(false)
	await settle()
	var commands := [0]
	enemy.draw.connect(func(): commands[0] += 1)
	var start: Vector2 = enemy.position
	for frame in range(8):
		enemy._process(1.0/120)
		await process_frame
	check(enemy.position != start and commands[0] == 0,"Combat movement updates the retained sprite without rebuilding its canvas")
	enemy.limbs.erase("left_arm")
	enemy.update_visual()
	check(enemy.last_body_state == enemy.body_state(),"Dismemberment immediately selects the correct retained sprite region")
	game.queue_free()
	await process_frame
	print("RESULT: %d passed, %d failed; 120 FPS runtime and retained rendering" % [passed,failed])
	quit(1 if failed else 0)
