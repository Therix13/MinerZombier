extends "res://tests/night_resupply.gd"

func dismiss_notice(shop: Control) -> void:
	shop.research_notice_timer.wait_time = 0.05
	shop.research_notice_timer.start()
	await create_timer(0.1).timeout
	shop.research_notice_timer.wait_time = 3.0

func run_checks() -> void:
	root.show()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://" + scene).instantiate()
	if "--legacy" in args: game.set_script(load(OS.get_environment("GODOT_LEGACY_MAIN")))
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	display.resolution = Vector2i(1280, 720)
	display.window_mode = 0
	display.apply_display(false)
	await settle()
	var shop: Control = game.shop
	var player: RefCounted = game.progression
	game.cycle.day = 2
	game.cycle.changed.emit()
	shop.open_shop()
	await create_timer(0.4).timeout
	shop.open_category("VETAS")
	await settle()
	check(shop.item_buttons.keys() == ["coal"] and shop.purchase_buttons.keys() == ["coal"], "A fresh store contains only the researched base item")
	var headings: Array[String] = []
	for child in shop.shop_content.get_children():
		if child is Label: headings.append(child.text)
	check(headings.is_empty(), "Hidden automation items leave no empty heading or gap")
	shop.request_item("drill", shop.drill_requested)
	check(not game.placing_drill, "A hidden item still cannot be purchased through its handler")
	if DisplayServer.get_name() != "headless" and "--capture" in args:
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/visible-store.png")
	shop.open_category("INVESTIGACIÓN")
	check(shop.research_buttons.is_empty() and not shop.research_notice.visible, "Level-one research has no higher-level cards or startup notice")
	player.add_experience(50)
	await settle()
	check(shop.research_buttons.keys() == ["drill", "straight_belt"], "Level two reveals only drill and straight-conveyor research")
	check(shop.research_notice.visible and shop.notice_research_ids == ["drill", "straight_belt"], "Crossing the threshold shows one notice with exactly the new researches")
	await settle()
	check(shop.research_notice.get_global_rect().get_center().distance_to(shop.get_global_rect().get_center()) < 2 and shop.research_notice_backdrop.visible and shop.research_notice_backdrop.color.a > 0.5, "The alert is centered over a dimmed background")
	check(is_equal_approx(shop.research_notice_timer.wait_time, 3.0), "Alerts close after three seconds")
	check(shop.research_notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and shop.research_notice_label.mouse_filter == Control.MOUSE_FILTER_IGNORE and not paused, "The brief notice neither captures clicks nor pauses gameplay")
	check(not shop.research_buttons.has("brass") and not shop.research_buttons.has("compactor") and not shop.research_buttons.has("junction_belt"), "Future-level research creates no controls")
	if DisplayServer.get_name() != "headless" and "--capture" in args:
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/new-research-notice.png")
	await click(control_point(shop.research_buttons["drill"]))
	shop.open_category("HERRAMIENTAS")
	check(shop.item_buttons.keys() == ["drill"], "Researching an item makes it appear in the normal store")
	player.award_night()
	check(shop.notice_research_ids == ["drill", "straight_belt"], "Research-point rewards do not repeat or expand the notice")
	shop.open_category("AUTOMATIZACIÓN")
	game.research_technology("straight_belt")
	check(shop.item_buttons.keys() == ["straight"], "An unlock refreshes an already open store immediately")
	await dismiss_notice(shop)
	check(not shop.research_notice.visible and not shop.research_notice_backdrop.visible and shop.notice_research_ids.is_empty(), "The timer removes the notice and its accumulated research list")
	shop.open_category("INVESTIGACIÓN")
	var card_id: int = shop.research_buttons["drill"].get_instance_id()
	player.add_experience(1)
	check(shop.research_buttons["drill"].get_instance_id() == card_id and not shop.research_notice.visible, "Ordinary EXP preserves the controls and does not announce anything")
	player.add_experience(79)
	check(shop.research_buttons.size() == 5 and not shop.research_buttons.has("junction_belt"), "Level three reveals only its own next research tier")
	check(shop.notice_research_ids == ["brass", "curved_belts", "compactor"] and not "Taladro" in shop.research_notice_label.text, "The next notification excludes researches announced at earlier levels")
	game.research_technology("brass")
	check(shop.research_buttons.has("compactor") and shop.research_buttons["compactor"].disabled, "Eligible-level research remains visible when points are insufficient")
	player.add_experience(128)
	check(shop.research_buttons.has("junction_belt") and shop.notice_research_ids == ["brass", "curved_belts", "compactor", "junction_belt"], "Quick consecutive thresholds merge new researches without duplicates")
	game.night_victory_overlay.show()
	await settle()
	check(not shop.research_notice.visible and not shop.notice_research_ids.is_empty(), "Victory temporarily defers an unread research notification")
	game.night_victory_overlay.hide()
	await settle()
	check(shop.research_notice.visible and shop.research_notice_timer.time_left > 2.5, "Dismissing victory reveals the notice with its full reading time")
	await dismiss_notice(shop)
	player.add_experience(205)
	check(player.level == 5 and not shop.research_notice.visible, "A level with no new research causes no empty notification")
	shop.close_shop()
	await create_timer(0.4).timeout
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	var platform: Vector2i = game.grid.defense_cell("left")
	game.launchers.place(platform)
	for index in range(5): game.launchers.receive(platform, "coal")
	var controller: RefCounted = game.camera_controller
	game.camera.zoom = Vector2.ONE * 2
	game.camera.position = Vector2(744, 220)
	controller.clamp_position()
	var day_position: Vector2 = game.camera.position
	var day_zoom: Vector2 = game.camera.zoom
	game.start_night()
	await wait_for_view()
	game.zombie_manager.set_process(false)
	game.zombie_manager.spawn_zombie()
	var zombies: Array[Node] = get_nodes_in_group("zombies")
	for zombie in zombies: zombie.set_process(false)
	var close_zombie: Node2D = zombies[0]
	close_zombie.position = Vector2(744, -48)
	game.shop.request_view_toggle()
	await wait_for_view()
	check(not controller.defense_view and controller.combat_mine_active and game.cycle.is_night, "Mine mode uses its special framing only while the horde is active")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(1280, 720)]:
		display.resolution = size
		display.apply_display(false)
		await settle()
		var transform: Transform2D = game.get_global_transform_with_canvas()
		var near_body: Rect2 = transform * Rect2(close_zombie.position + Vector2(-17, -27), Vector2(34, 51))
		check(root.get_visible_rect().encloses(near_body), "Nearby zombie and health bar remain visible from the mine at " + str(size))
		var far_point: Vector2 = transform * Vector2(744, -590)
		check(not root.get_visible_rect().has_point(far_point), "The distant spawning area stays outside the mine view at " + str(size))
		var cave: Rect2 = transform * Rect2(Vector2(12 * 48, game.grid.GRID_OFFSET_Y), Vector2(7 * 48, 5 * 48))
		check(root.get_visible_rect().encloses(cave), "The purchased mine remains fully visible beneath the near-base strip at " + str(size))
		var card: Control = shop.get_node("CyclePanel")
		var card_rect: Rect2 = card.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, card.size)
		check(not near_body.intersects(card_rect) and not cave.intersects(card_rect), "The tutorial card covers neither the near zombie nor the mine at " + str(size))
		if DisplayServer.get_name() != "headless" and "--capture" in args:
			root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/mine-horde-" + str(size.x) + ".png")
	var night_position: Vector2 = game.camera.position
	game.shop.request_view_toggle()
	await wait_for_view()
	game.shop.request_view_toggle()
	await wait_for_view()
	check(game.camera.position.is_equal_approx(night_position), "Repeated view changes preserve the mine's horde framing")
	game.on_wave_completed()
	await settle()
	check(not controller.combat_mine_active and game.camera.position.is_equal_approx(day_position) and game.camera.zoom.is_equal_approx(day_zoom), "Ending the horde restores the original daytime mine camera")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; visibility=", scene)
	quit(1 if failed else 0)
