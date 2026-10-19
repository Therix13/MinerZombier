extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	game.economy.coins = 0
	var stored := Vector2i(14,2)
	var platform: Vector2i = game.grid.defense_cell("left")
	game.launchers.place(stored)
	game.cycle.tutorial_step = 13
	game.cycle.refresh_tutorial()
	check(game.cycle.TUTORIAL_DISPLAY_STEPS == 15 and game.cycle.tutorial_title() == "Carga la munición","Redundant weapon construction lesson is removed")
	check(game.cycle.tutorial_purchase_price() == 0 and not game.cycle.needs_tutorial_income(),"Existing stored launcher never requires another purchase budget")
	check(game.shop.tutorial_purchase().is_empty() and "Mueve tu lanzapepitas" in game.cycle.tutorial_text(),"Guide asks only to move the existing launcher")
	check(game.cycle.workshop_targets() == [stored,platform],"Arrow points from the stored weapon to its defense platform")
	check(game.launchers.move(stored,platform) and game.cycle.tutorial_step == 13,"Moving the existing weapon continues directly to loading")
	check("100" in game.cycle.tutorial_text() and not "lanzapepitas" in game.cycle.tutorial_text(),"Missing ammunition supply never asks to repurchase the existing launcher")
	game.mining.items_for("coal")[stored] = 1
	check(game.cycle.tutorial_purchase_price() == 0 and game.shop.tutorial_purchase().is_empty(),"Loose ammunition avoids any unnecessary new vein purchase")
	game.mining.items_for("coal").clear()
	for i in range(5): game.launchers.receive(platform,"coal")
	check(game.cycle.tutorial_step == 14 and game.cycle.can_start_night(),"Full ammunition proceeds directly to starting the night")
	var saves: Node = game.get_node("SaveGame")
	var data: Dictionary = saves.snapshot()
	data["tutorial_revision"] = 2
	for step: int in [13,14,15,16]:
		data["cycle"]["tutorial_step"] = step
		check(saves.valid_snapshot(data) and saves.restore_snapshot(data),"Old tutorial step %d still loads" % step)
		check(game.cycle.tutorial_step == (13 if step == 13 else step - 1),"Old tutorial step %d maps to the merged sequence" % step)
	data["tutorial_revision"] = 3
	data["cycle"]["tutorial_step"] = 13
	data["launchers"].clear()
	check(saves.restore_snapshot(data) and game.cycle.tutorial_purchase_price() == 500,"New players without a launcher still receive its correct purchase price")
	game.queue_free()
	await settle()
	print("RESULT: %d passed, %d failed; existing launcher tutorial" % [passed,failed])
	quit(1 if failed else 0)
