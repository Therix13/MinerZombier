extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	mover = game.get_node("WorldInteractions")
	game.cycle.skip_tutorial()
	game.cycle.day = 2
	game.cycle.day_remaining = 300
	var clock: Control = game.phase_clock
	clock.update_clock()
	check(clock.time_label.text == "06:00" and not clock.phase_icon.night,"Five-minute preparation begins at 06:00 with a sun")
	check(clock.size.y <= 42,"The day HUD is a single compact row")
	game.cycle.advance_day(150)
	clock.update_clock()
	check(clock.time_label.text == "14:00","Half the preparation phase advances eight game hours")
	check(game.cycle.advance_day(150),"The sixteen-hour day still lasts exactly 300 simulated seconds")
	clock.update_clock()
	check(clock.time_label.text == "22:00","The day reaches 22:00 before the horde")
	game.cycle.barrier_broken = true
	game.cycle.start_night(true)
	game.zombie_manager.start_wave(2)
	game.zombie_manager.set_process(false)
	clock.update_clock()
	check(clock.time_label.text == "22:00" and clock.phase_icon.night,"Night starts at 22:00 with a moon")
	for elapsed in [30.0,60.0,119.75,120.0]:
		game.zombie_manager.wave_elapsed = elapsed
		clock.update_clock()
		var expected: String = {30.0:"00:00",60.0:"02:00",119.75:"05:59",120.0:"06:00"}[elapsed]
		check(clock.time_label.text == expected,"Night wraps midnight correctly at " + expected)
	game.zombie_manager.wave_elapsed = 60
	var saves: Node = game.get_node("SaveGame")
	check(saves.restore_snapshot(saves.snapshot()),"Existing phase counters remain compatible with saves")
	game.zombie_manager.set_process(false)
	clock.update_clock()
	check(clock.time_label.text == "02:00","Reload restores the correct time of night")
	game.camera_controller.stop_transition()
	game.camera_controller.set_defense_view(false)
	game.camera_controller.stop_transition()
	game.shop.set_view_mode(false)
	var source := Vector2i(15,1)
	for kind: String in ["coal_4","copper_ingot_3"]:
		game.mining.items_for(kind)[source] = 1
		var coins: int = game.economy.coins
		await drag(source,game.grid.sale_cell)
		check(game.mining.nuggets_at(source) == 0 and game.economy.coins == coins + game.economy.sale_value(kind),"A real night drag sells " + kind + " for its full price")
	game.mining.items_for("coal")[source] = 1
	paused = true
	check(not mover.can_drop("nugget",source,game.grid.sale_cell),"Paused gameplay still blocks selling")
	paused = false
	game.cycle.complete_night()
	clock.update_clock()
	await settle()
	check(clock.get_child(0).size.y <= 42 and clock.time_label.size.y <= 28,"Rendered panel and clock stay on a single short row")
	check(clock.time_label.text == "06:00" and not clock.phase_icon.night,"Dawn begins the next five-minute day at 06:00")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/compact-day-clock.png")
	print("RESULT: %d passed, %d failed; day clock and night sales" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
