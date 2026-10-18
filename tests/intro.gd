extends "res://tests/building_controls.gd"

const IntroScript = preload("res://Scripts/intro_cinematic.gd")

func _initialize() -> void:
	Engine.remove_meta(IntroScript.SESSION_KEY)
	call_deferred("run_checks")

func run_checks() -> void:
	root.show()
	root.size = Vector2i(1280,720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://"+scene).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	await settle()
	var intro: CanvasLayer = game.get_node("IntroCinematic")
	intro.set_process(false)
	check(paused and not game.get_node("CanvasLayer").visible,"Opening cinematic pauses simulation and hides the HUD")
	check(Engine.has_meta(IntroScript.SESSION_KEY),"Opening is marked seen for this session")
	check(game.economy.coins == 100 and game.progression.total_experience == 0 and game.grid.owned_tiles.size() == 9,"Opening grants no money, resources or buildings")
	check(intro.film.renderer.get_script() == preload("res://Scripts/world_renderer.gd") and intro.film.renderer.grid == game.grid,"Film renders the real current mine with the gameplay artwork")
	intro.elapsed = 4
	intro.present_frame()
	var barrier: Node2D = intro.film.barrier
	var restrained := true
	for actor: Node2D in barrier.actors:
		restrained = restrained and actor.position.y < barrier.FENCE_Y and not actor.is_in_group("zombies")
	check(restrained and barrier.destruction == 0 and get_nodes_in_group("zombies").is_empty(),"Zombies wait behind an intact fence without becoming active combat targets")
	check("cerca" in intro.title.text,"Opening explains why the zombies cannot enter")
	if DisplayServer.get_name() != "headless":
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/fence-opening.png")
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	await key(KEY_ESCAPE)
	check(display.menu_open and paused,"Escape keeps real pause and settings accessible during the film")
	var time: float = intro.elapsed
	intro._process(2)
	check(intro.elapsed == time,"Pause menu stops the cinematic timeline")
	await key(KEY_ESCAPE)
	check(not display.menu_open and paused,"Closing pause returns to the cinematic without starting gameplay")
	await click_control(intro.skip_button)
	await settle()
	check(not paused and game.cycle.is_tutorial_active() and game.get_node("CanvasLayer").visible,"Skipping the opening starts the protected tutorial")
	check(game.has_node("TutorialBarrier") and not game.cycle.barrier_broken,"The real-world fence remains during the tutorial")
	mover = game.get_node("WorldInteractions")
	shop = game.shop
	compactors = game.get_node("Compactors")
	# Prepare readiness without using money or changing combat state.
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	var launcher: Vector2i = game.grid.defense_cell("left")
	game.launchers.place(launcher)
	for index in range(4): game.launchers.receive(launcher,"coal")
	game.cycle.tutorial_step = game.cycle.TUTORIAL_LAST_STEP
	game.cycle.changed.emit()
	await settle()
	check(game.has_node("BarrierBreach") and paused and not game.cycle.is_night,"Tutorial completion starts the second scene automatically")
	var breach: CanvasLayer = game.get_node("BarrierBreach")
	breach.set_process(false)
	check(breach.film.renderer.launchers == game.launchers,"The collapse shows the actual player's defenses")
	check(not game.cycle.start_night(),"Combat cannot start before the collapse scene finishes")
	breach.elapsed = 4
	breach.present_frame()
	check(breach.film.barrier.destruction > 0 and breach.film.barrier.destruction < 1,"The fence breaks progressively with moving boards")
	if DisplayServer.get_name() != "headless":
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/fence-collapse.png")
	breach.elapsed = breach.runtime_duration()
	breach.present_frame()
	check(breach.film.barrier.destruction == 1,"The fence is destroyed before the first night")
	breach._process(0)
	await settle()
	check(not paused and game.cycle.is_night and game.cycle.barrier_broken and game.zombie_manager.active_wave,"Ending the collapse starts the first actual horde exactly once")
	check(game.zombie_manager.spawn_count == 1 and game.cycle.day == 1,"The cinematic itself never spawned or consumed real enemies")
	check(game.shop.get_node("CyclePanel").visible and game.get_node("CanvasLayer").visible,"Combat restores both HUD and defense card")
	game.free()
	await settle()
	Engine.remove_meta(IntroScript.SESSION_KEY)
	game = load("res://"+scene).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	await settle()
	await key(KEY_F10)
	check(game.economy.developer_mode and game.cycle.tutorial_skipped and game.cycle.barrier_broken and not paused,"F10 during the opening skips the film and the full tutorial")
	check(not game.has_node("BarrierBreach") and not game.cycle.is_night and game.economy.coins == 100,"DEV skip triggers neither the collapse nor a premature night or rewards")
	game.free()
	await settle()
	print("RESULT: ",passed," passed; ",failed," failed; fence story; ",scene)
	quit(1 if failed else 0)
