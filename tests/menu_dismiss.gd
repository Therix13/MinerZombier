extends "res://tests/building_controls.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.cycle.skip_tutorial()
	mover = game.get_node("WorldInteractions")
	shop = game.shop
	var cell := Vector2i(14, 0)
	game.mining.place_vein(cell, 1)
	game.redraw_world()
	shop.open_shop()
	await wait_shop()
	await click_control(shop.category_buttons["VETAS"])
	check(shop.shop_open and shop.shop_title.text == "VETAS", "A category click navigates without dismissing the menu")
	var inside: Vector2 = root.get_screen_transform() * (shop.shop_panel.get_global_transform_with_canvas() * Vector2(20, shop.shop_panel.size.y - 20))
	await mouse_button(inside, true)
	await mouse_button(inside, false)
	check(shop.shop_open, "Clicking an empty part of the panel keeps it open")
	var cash: int = game.economy.coins
	await mouse_move(point(cell))
	await mouse_button(point(cell), true)
	check(not shop.shop_open, "An outside press closes the lateral menu")
	await mouse_button(point(cell), false)
	await wait_shop()
	check(game.mining.coal_veins[cell]["progress"] == 0 and not game.holding_object and game.economy.coins == cash, "Dismissal consumes the entire click without mining or buying behind the menu")
	await place_at(cell)
	check(game.mining.coal_veins[cell]["progress"] == 1, "The next normal world click works after dismissal")
	shop.open_shop()
	# Interrupt the opening tween immediately rather than waiting for it.
	await mouse_button(point(cell), true)
	await mouse_button(point(cell), false)
	await wait_shop()
	check(not shop.shop_open and not shop.shop_animating and game.mining.coal_veins[cell]["progress"] == 1, "An outside click safely reverses an opening menu animation")
	game.cycle.tutorial_skipped = false
	game.cycle.day = 2
	game.cycle.research_tutorial_pending = true
	game.progression.research_points = 2
	game.cycle.changed.emit()
	shop.open_shop()
	await wait_shop()
	shop.open_category("INVESTIGACIÓN")
	await settle()
	await place_at(cell)
	await wait_shop()
	check(not shop.shop_open and game.cycle.is_research_tutorial_active() and game.progression.research_points == 2, "Outside dismissal also works during the mandatory research lesson without completing it")
	check(game.mining.coal_veins[cell]["progress"] == 1, "The tutorial does not mine through the outside menu click")
	await click_control(shop.shop_button)
	await wait_shop()
	check(shop.shop_open, "The player can reopen the menu and continue the lesson")
	print("RESULT: ", passed, " passed; ", failed, " failed; outside menu dismissal")
	game.queue_free()
	await settle()
	await create_timer(0.15).timeout
	quit(0 if failed == 0 else 1)
