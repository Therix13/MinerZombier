extends "res://tests/interactions.gd"

var strikes := 0

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	mover = game.get_node("WorldInteractions")
	mover.set_process(false)
	var settings: CanvasLayer = game.display_settings
	settings.resolution = Vector2i(1280,720)
	settings.window_mode = 0
	settings.apply_display(false)
	game.cycle.tutorial_skipped = true
	game.mining.struck.connect(func(_cell: Vector2i): strikes += 1)
	var cell := Vector2i(15,1)
	game.mining.place_vein(cell,1,"coal")
	await settle()
	await mouse_move(point(cell))
	settings.set_auto_click(false)
	mover.advance_auto_click(1.0)
	check(strikes == 0,"Manual mode never mines merely by hovering")
	settings.set_auto_click(true)
	settings.auto_click_enabled = false
	settings.load_gameplay_settings()
	check(settings.auto_click_enabled,"Automatic mining preference survives reloading settings")
	for i in range(5): mover.advance_auto_click(0.15)
	check(strikes == 5 and game.mining.nuggets_at(cell+Vector2i.RIGHT) == 1,"Hovering a vein produces normal mining hits and a normal resource")
	mover.advance_auto_click(10.0)
	check(strikes == 6,"A slow frame cannot produce a burst of accumulated clicks")
	await mouse_move(point(cell+Vector2i.RIGHT))
	mover.advance_auto_click(1.0)
	check(strikes == 6 and game.mining.nuggets_at(cell+Vector2i.RIGHT) == 1,"Hovering resources does not click, sell or move them")
	await mouse_move(point(cell))
	game.shop.open_shop()
	mover.advance_auto_click(1.0)
	check(strikes == 6,"Shop blocks automatic mining")
	game.shop.close_shop()
	await create_timer(0.4).timeout
	game.placing_coal = true
	mover.advance_auto_click(1.0)
	check(strikes == 6,"Placement blocks automatic mining")
	game.placing_coal = false
	game.holding_object = true
	mover.advance_auto_click(1.0)
	check(strikes == 6,"Dragging blocks automatic mining")
	game.holding_object = false
	settings.open_settings()
	mover.advance_auto_click(1.0)
	check(strikes == 6 and paused,"Pause and settings block automatic mining")
	settings.auto_click_checkbox.button_pressed = false
	check(not settings.auto_click_enabled,"The settings checkbox disables automatic mining immediately")
	settings.close_menu()
	await mouse_move(point(cell))
	mover.advance_auto_click(1.0)
	check(strikes == 6,"Disabling the checkbox restores manual-only mining")
	settings.ask_auto_click(func(): pass)
	check(paused and settings.auto_click_prompt.visible,"The warning is modal and waits for an explicit choice")
	settings.answer_auto_click(true)
	check(not paused and settings.auto_click_enabled and not settings.auto_click_prompt.visible,"Accepting enables automatic mining and resumes the game")
	settings.ask_auto_click(func(): pass)
	settings.answer_auto_click(false)
	check(not paused and not settings.auto_click_enabled,"Declining keeps manual mining available")
	game.queue_free()
	await process_frame
	print("RESULT: %d passed, %d failed; automatic mining" % [passed,failed])
	quit(1 if failed > 0 else 0)
