extends "res://tests/building_controls.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	mover = game.get_node("WorldInteractions")
	compactors = game.get_node("Compactors")
	compactors.set_process(false)
	var furnace: Node = game.get_node("Furnaces")
	furnace.set_process(false)
	var rhythm: Node = game.get_node("WorkshopRhythm")
	rhythm.set_process(false)
	var renderer: Node = game.renderer
	check(renderer.ground != null and renderer.ground.get_parent() == renderer, "Terrain has its own retained canvas")
	var rebuilds: int = renderer.ground_rebuilds
	for i in range(8):
		renderer.queue_redraw()
		await settle()
	check(renderer.ground_rebuilds == rebuilds, "Eight dynamic redraws never rebuild unchanged terrain")
	game.grid.expand()
	game.redraw_world()
	await settle()
	check(renderer.ground_rebuilds == rebuilds + 1, "Expanding the base invalidates terrain exactly once")
	var atlas: GDScript = load("res://Scripts/art_atlas.gd")
	check(atlas.prepare() and atlas.KEYS.size() == 109 and atlas.regions.size() == 109, "All 109 artwork states share one prepared atlas")
	var atlas_image: Image = atlas.texture.get_image()
	for key: String in atlas.KEYS:
		var region: Rect2 = atlas.regions[key]
		check(atlas_image.get_region(Rect2i(region)).get_used_rect().size != Vector2i.ZERO, "Cached artwork contains visible pixels: " + key)
	var zombie_script: GDScript = load("res://Scripts/zombie.gd")
	var enemy: Node2D = zombie_script.new()
	check(enemy.get_body_atlas() == zombie_script.get_body_atlas(), "All enemies reuse one body atlas")
	check(enemy.body_state() == 15, "The normal zombie sprite contains all four limbs")
	enemy.limbs.erase("left_arm")
	enemy.hit_flash = 0.1
	check(enemy.body_state() == 30, "Flashing and dismemberment select the matching cached sprite")
	enemy.free()
	for row in range(5):
		game.mining.place_vein(Vector2i(12, row), 1)
		game.conveyors.place(Vector2i(13, row), 1)
		game.conveyors.place(Vector2i(14, row), 1)
		compactors.place(Vector2i(15, row), 1)
		compactors.receive(Vector2i(15, row), "copper_3")
		compactors.receive(Vector2i(15, row), "copper_3")
		furnace.place(Vector2i(16, row), 1)
		furnace.receive(Vector2i(16, row), "coal_4")
		furnace.receive(Vector2i(16, row), "copper_4")
		game.mining.items_for("copper")[Vector2i(14,row)] = 1
	furnace.process_smelting(2)
	game.redraw_world()
	await settle()
	if DisplayServer.get_name() != "headless":
		var calls: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		check(calls < 250, "The representative factory stays below 250 draw calls (%d)" % calls)
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/optimized-factory.png")
		# Compare cached art to the retained original vector drawing at the same state.
		var cached: Image = root.get_texture().get_image()
		renderer.rasterizing = true
		furnace.rasterizing = true
		compactors.rasterizing = true
		game.redraw_world()
		furnace.queue_redraw()
		compactors.queue_redraw()
		await settle()
		var original: Image = root.get_texture().get_image()
		var different := 0
		for y in range(0, cached.get_height(), 2):
			for x in range(0, cached.get_width(), 2):
				var a: Color = cached.get_pixel(x,y)
				var b: Color = original.get_pixel(x,y)
				if maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) > 0.15: different += 1
		var fraction: float = float(different) / (cached.get_width() * cached.get_height() / 4.0)
		check(fraction < 0.02, "Cached artwork preserves the vector scene (%.3f%% differing pixels)" % (fraction * 100))
		renderer.rasterizing = false
		furnace.rasterizing = false
		compactors.rasterizing = false
		game.redraw_world()
		furnace.queue_redraw()
		compactors.queue_redraw()
	var original_visibility: Dictionary = {}
	for child in game.get_children():
		if child is CanvasItem and not child is Camera2D: original_visibility[child] = child.visible
	var intro: Node = load("res://Scripts/intro_cinematic.gd").new()
	game.add_child(intro)
	intro.set_process(false)
	intro.elapsed = 4.0
	intro.present_frame()
	await settle()
	check(not renderer.visible and not furnace.visible and not rhythm.visible, "The cinematic excludes the covered game from rendering")
	check(intro.film.barrier.actors.size() == intro.film.barrier.HORDE_SIZE, "The fence film retains its complete decorative horde")
	if DisplayServer.get_name() != "headless":
		var calls: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		check(calls < 350, "The full cinematic stays below 350 draw calls (%d)" % calls)
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/optimized-cinematic.png")
	intro.finish()
	await settle()
	var restored := true
	for child in original_visibility:
		if is_instance_valid(child) and child.visible != original_visibility[child]: restored = false
	check(restored and not paused, "Skipping the film restores the exact world visibility and gameplay")
	print("RESULT: ", passed, " passed; ", failed, " failed; render performance")
	game.queue_free()
	await settle()
	await create_timer(0.15).timeout
	quit(0 if failed == 0 else 1)
