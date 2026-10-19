extends "res://tests/interactions.gd"

func elapsed_over_real_time() -> float:
	var wave: Node = game.zombie_manager
	var before: float = wave.wave_elapsed
	var started: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < 200000:
		await process_frame
	return (wave.wave_elapsed - before) / (float(Time.get_ticks_usec() - started) / 1000000.0)

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	var clock: Control = game.phase_clock
	check(not clock.speed_controls.visible and Engine.time_scale == 1.0,"Night speed controls stay hidden during preparation")
	game.cycle.skip_tutorial()
	game.cycle.barrier_broken = true
	game.cycle.day = 2
	check(game.cycle.start_night(true),"Start a night for speed testing")
	game.zombie_manager.start_wave(2)
	await settle()
	check(clock.speed_controls.visible and clock.night_speed == 1,"Night begins with visible controls at normal speed")
	check(clock.speed_controls.global_position == Vector2(80,20),"Controls sit immediately beside the view button")
	for index in range(3):
		var button: Button = clock.speed_controls.get_child(index)
		button.pressed.emit()
		await settle()
		var multiplier: int = [1,2,4][index]
		check(Engine.time_scale == multiplier and button.button_pressed,"Arrow button selects ×%d" % multiplier)
		var rate: float = await elapsed_over_real_time()
		check(absf(rate - multiplier) < 0.6,"Real-time horde countdown advances at ×%d (measured %.2f)" % [multiplier,rate])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/night-speed.png")
	paused = true
	await settle()
	check(Engine.time_scale == 1.0,"Pausing restores normal UI speed")
	paused = false
	await settle()
	check(Engine.time_scale == 4.0,"Resuming restores the selected night speed")
	game.cycle.complete_night()
	check(not clock.speed_controls.visible and Engine.time_scale == 1.0 and clock.night_speed == 1,"Dawn immediately hides controls and restores ×1")
	game.dismiss_night_victory_popup()
	game.cycle.start_night(true)
	clock.set_night_speed(2)
	check(Engine.time_scale == 2.0,"A later night supports acceleration")
	game.cycle.lose_night()
	check(not clock.speed_controls.visible and Engine.time_scale == 1.0,"Defeat also hides controls and restores ×1")
	game.cycle.defeated = false
	game.cycle.is_night = true
	clock.set_night_speed(4)
	game.queue_free()
	await settle()
	check(Engine.time_scale == 1.0,"Leaving the game never leaves global time accelerated")
	print("RESULT: %d passed, %d failed; night speed" % [passed,failed])
	quit(1 if failed else 0)
