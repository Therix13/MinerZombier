extends "res://tests/interactions.gd"

func toggle_dev() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F10
	event.pressed = true
	Input.parse_input_event(event)
	await settle()

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.zombie_manager.set_process(false)
	var panel: Control = game.shop.get_node("CyclePanel")
	game._process(5.0)
	check(panel.visible and game.cycle.day_remaining == 300,"Normal first-day tutorial remains visible and untimed")
	await toggle_dev()
	check(game.economy.developer_mode and game.cycle.tutorial_skipped,"F10 enables DEV and skips the tutorial")
	check(not panel.visible,"DEV completely hides the tutorial/preparation window")
	var guide: Node = game.get_node_or_null("TutorialGuide")
	check(guide == null or not guide.pointer.visible,"DEV leaves no tutorial arrow on screen")
	game._process(150.0)
	game.phase_clock.update_clock()
	check(game.cycle.day_remaining == 150 and game.phase_clock.time_label.text == "14:00","The first DEV day advances from 06:00 to 14:00 in 150 seconds")
	check(not "tutorial" in game.phase_clock.tooltip_text,"DEV clock describes the timed day instead of the tutorial")
	var saves: Node = game.get_node("SaveGame")
	check(saves.restore_snapshot(saves.snapshot()),"A partially elapsed DEV day can be saved and restored")
	check(game.economy.developer_mode and game.cycle.day_remaining == 150 and not panel.visible,"Reload preserves the DEV clock and hidden tutorial window")
	paused = true
	game._process(10)
	check(game.cycle.day_remaining == 150,"Pausing still freezes the DEV day clock")
	paused = false
	await toggle_dev()
	check(not game.economy.developer_mode and not panel.visible,"Leaving DEV does not bring back the skipped tutorial")
	await toggle_dev()
	check(game.cycle.day_remaining == 150,"Toggling DEV again does not reset the day's remaining time")
	game.cycle.day_remaining = 0.1
	game._process(0.2)
	check(game.cycle.day == 1 and game.cycle.is_night and game.zombie_manager.active_wave,"The first DEV day automatically starts night one after its five minutes even when unarmed")
	check(game.get_node_or_null("BarrierBreach") == null and not panel.visible,"DEV night starts without the tutorial's fence cinematic or window")
	print("RESULT: %d passed, %d failed; DEV first-day clock" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
