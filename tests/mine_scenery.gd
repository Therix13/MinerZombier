extends "res://tests/interactions.gd"

const Scenery = preload("res://Scripts/mine_scenery.gd")

func capture(name: String) -> void:
	game.redraw_world()
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/" + name + ".png")

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	game.cycle.day = 2
	game.cycle.changed.emit()
	game.camera_controller.stop_transition()
	game.camera.position = Vector2(744,285)
	game.camera.zoom = Vector2.ONE * 2.2
	game.camera.force_update_scroll()
	game.mining.place_vein(Vector2i(12,0),1,"coal")
	game.mining.place_vein(Vector2i(12,3),1,"copper")
	game.drills.place(Vector2i(12,1),0)
	game.drills.place(Vector2i(12,4),0)
	game.conveyors.place(Vector2i(13,0),1)
	game.conveyors.place(Vector2i(14,0),1)
	game.get_node("Compactors").place(Vector2i(15,0),1)
	game.get_node("Furnaces").place(Vector2i(16,0),0)
	game.get_node("Furnaces").receive(Vector2i(16,0),"coal_4")
	game.get_node("Furnaces").receive(Vector2i(16,0),"copper_4")
	game.get_node("Saws").place(Vector2i(16,2),1)
	game.mining.items_for("coal_4")[Vector2i(14,2)] = 1
	game.mining.items_for("copper_ingot_3")[Vector2i(15,3)] = 1
	game.launchers.place(game.grid.defense_cell("left"),2)
	game.launchers.place(game.grid.defense_cell("right"))
	game.launchers.receive(game.grid.defense_cell("left"),"gold_4")
	game.launchers.receive(game.grid.defense_cell("right"),"coal_4")
	check(Scenery.texture != null and Scenery.builds == 1,"Terrain atlas is shared and generated only once")
	check(Scenery.texture.get_size() == Vector2(1,1),"Minimalist terrain uses a single neutral texel rather than pixel noise")
	check(game.grid.sale_cell == Vector2i(15,-1) and game.grid.get_cell_rect(game.grid.sale_cell).get_center() == Vector2(744,196),"Mine portal keeps the existing sales cell and interaction geometry")
	game.shop.accept_unlock_notice()
	await capture("mine-gallery-day")
	var rebuilds: int = game.renderer.ground_rebuilds
	for i in range(5):
		game.renderer.queue_redraw()
		await settle()
	check(game.renderer.ground_rebuilds == rebuilds and Scenery.builds == 1,"Machine redraws reuse the retained rock and floor background")
	if DisplayServer.get_name() != "headless":
		var calls: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		check(calls < 250,"Detailed mine remains below 250 draw calls (%d)" % calls)
		var img: Image = root.get_texture().get_image()
		var white := 0
		for y in range(0,img.get_height(),16):
			for x in range(0,img.get_width(),16):
				var color: Color = img.get_pixel(x,y)
				if color.r > 0.97 and color.g > 0.97 and color.b > 0.97: white += 1
		check(white < 10,"The mine view has no remaining white landscape")
	game.camera_controller.defense_view = true
	game.camera_controller.fit_defense_view()
	game.shop.set_view_mode(true)
	await capture("mine-approach-day")
	game.cycle.is_night = true
	game.defense_zone.set_night(true)
	game.zombie_manager.start_wave(5)
	game.zombie_manager.set_process(false)
	for enemy: Node in game.zombie_manager.living_zombies(): enemy.set_process(false)
	for index in range(4):
		var enemy: Node2D = preload("res://Scripts/zombie.gd").new()
		enemy.setup(Vector2(644+index*65,-210-index*60),Vector2(744,-28))
		enemy.configure(["walker","runner","armored","spitter"][index])
		game.zombie_manager.connect_zombie(enemy)
		game.zombie_manager.add_child(enemy)
		enemy.set_process(false)
	await capture("mine-approach-night")
	if DisplayServer.get_name() != "headless":
		check(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) < 250,"Night exterior and enemy effects remain batched")
	check(game.get_node("SaveGame").valid_snapshot(game.get_node("SaveGame").snapshot()),"Landscape changes preserve save compatibility")
	print("RESULT: %d passed, %d failed; mine scenery" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
