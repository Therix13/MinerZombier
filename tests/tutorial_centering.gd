extends "res://tests/interactions.gd"

func run_checks() -> void:
	root.show()
	var args := OS.get_cmdline_user_args()
	game = load("res://main.tscn").instantiate()
	if "--legacy" in args: game.set_script(load(OS.get_environment("GODOT_LEGACY_MAIN")))
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	var guide: Node2D = game.get_node("TutorialGuide")
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		display.resolution = resolution
		display.window_mode = 0
		display.apply_display(false)
		await settle()
		for step in range(7):
			game.cycle.tutorial_step = step
			guide.focus_objective()
			await settle()
			var entrance: Vector2 = game.get_global_transform_with_canvas() * game.grid.get_cell_rect(game.grid.sale_cell).get_center()
			check(absf(entrance.x - root.get_visible_rect().size.x * 0.5) < 1, "Tutorial step %d centers the entrance at %s" % [step, resolution])
			if step >= 3:
				var platform: Rect2 = game.get_global_transform_with_canvas() * game.grid.get_cell_rect(game.grid.defense_cell("left"))
				var card: Control = game.shop.get_node("CyclePanel")
				var card_rect: Rect2 = card.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, card.size)
				check(not platform.intersects(card_rect), "The tutorial card leaves the left defense platform clickable at %s" % resolution)
		if DisplayServer.get_name() != "headless" and "--capture" in args and resolution == Vector2i(1920, 1080):
			game.cycle.tutorial_step = 1
			game.mining.place_vein(game.cycle.TUTORIAL_COAL_CELL, 1)
			guide.focus_objective()
			game.shop.update_cycle()
			game.redraw_world()
			await settle()
			root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/tutorial-centered.png")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; tutorial centering")
	quit(1 if failed else 0)
