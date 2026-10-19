extends "res://tests/interactions.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	game.cycle.skip_tutorial()
	game.cycle.day = 5
	game.cycle.is_night = true
	game.cycle.changed.emit()
	game.defense_zone.set_night(true)
	var manager: Node = game.zombie_manager
	manager.start_wave(5)
	manager.set_process(false)
	for z: Node in manager.living_zombies(): z.depart()
	await settle()
	game.camera_controller.stop_transition()
	game.camera_controller.set_defense_view(true)
	await create_timer(0.8).timeout
	game.camera_controller.stop_transition()
	game.camera_controller.fit_defense_view()
	game.shop.set_view_mode(true)
	var center: float = game.grid.get_cell_rect(game.grid.sale_cell).get_center().x
	var index := 0
	var boss: Node2D
	for kind: String in preload("res://Scripts/zombie.gd").TYPES:
		var z: Node2D = preload("res://Scripts/zombie.gd").new()
		var at := Vector2(center - 200 + (index % 4) * 120,-420 + (index / 4) * 210)
		z.setup(at,Vector2(center,-28))
		z.configure(kind)
		manager.connect_zombie(z)
		manager.add_child(z)
		z.set_process(false)
		if kind in ["brute","bomber"]:
			z.phase = "windup"
			z.ability_timer = 1.5
		if kind == "plague": boss = z
		z.queue_redraw()
		index += 1
	for side: String in ["left","right"]:
		var cell: Vector2i = game.grid.defense_cell(side)
		game.launchers.place(cell,2)
		game.launchers.receive(cell,"copper_4")
		game.launchers.receive(cell,"gold")
	manager.launch_acid(Vector2(center - 30,-300),2,3)
	manager.advance_acid(0.5)
	game.redraw_world()
	await settle()
	game.phase_clock.update_clock()
	var at: Vector2 = root.get_screen_transform() * (game.get_global_transform_with_canvas() * boss.position)
	await mouse_move(at)
	await mouse_button(at,true)
	await mouse_button(at,false)
	check(boss.focused and game.launchers.focused_enemy.get_ref() == boss,"Clicking a live boss selects it as the priority target")
	check(not game.shop.get_node("CyclePanel").visible and game.get_node_or_null("TutorialGuide") == null,"No tutorial window or logic remains in later hordes")
	check(game.phase_clock.visible and "02:00" in game.phase_clock.time_label.text,"The compact night clock displays two minutes")
	check(manager.living_zombies().size() == 7,"All seven enemy types share the battlefield")
	for enemy: Node2D in manager.living_zombies():
		check(enemy.body_sprite.texture == preload("res://Scripts/zombie.gd").get_body_atlas(),"Special enemy reuses the shared body texture: " + enemy.archetype)
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/horde-variants.png")
		check(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) < 300,"Variants, telegraphs and acid stay below 300 draw calls")
	manager.set_process(true)
	game.set_process(true)
	await settle()
	var original_elapsed: float = manager.wave_elapsed
	var original_day: float = game.cycle.day_remaining
	paused = true
	await create_timer(0.1,true).timeout
	check(manager.wave_elapsed == original_elapsed and game.cycle.day_remaining == original_day,"Pause freezes both phase counters")
	paused = false
	print("RESULT: %d passed, %d failed; horde visuals and controls" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
