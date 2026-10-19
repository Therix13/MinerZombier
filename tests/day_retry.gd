extends "res://tests/interactions.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var saves: Node = game.get_node("SaveGame")
	var wave: Node = game.zombie_manager
	wave.set_process(false)
	mover = game.get_node("WorldInteractions")
	check(saves.day_checkpoint["coins"] == 100 and saves.day_checkpoint["cycle"]["day"] == 1,"A new game keeps an independent checkpoint of the first morning")
	game.economy.coins = 3
	game.mining.place_vein(Vector2i(14,0),1,"coal")
	game.cycle.is_night = true
	game.cycle.lose_night()
	game.restart_game()
	check(game.cycle.day == 1 and not game.cycle.defeated and not game.cycle.is_night and game.economy.coins == 100,"Defeat on day one returns to its original morning rather than keeping losses")
	check(game.mining.coal_veins.is_empty() and game.cycle.tutorial_step == 0 and game.get_node_or_null("TutorialGuide") != null,"Day one restores its original tutorial and empty base")
	game.cycle.skip_tutorial()
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	game.cycle.day = 2
	game.cycle.is_night = true
	game.cycle.barrier_broken = true
	game.economy.coins = 2588
	game.mining.place_vein(Vector2i(14,0),1,"coal")
	game.mining.coal_veins[Vector2i(14,0)]["level"] = 4
	game.mining.items_for("copper_ingot_3")[Vector2i(15,1)] = 1
	game.launchers.place(game.grid.defense_cell("left"),2)
	game.launchers.receive(game.grid.defense_cell("left"),"gold_4")
	game.get_node("Furnaces").place(Vector2i(16,1),0)
	game.get_node("Furnaces").machines[Vector2i(16,1)]["fuel"] = 27
	game.get_node("Construction").place(Vector2i(14,2),"drill",1,200)
	game.get_node("Construction").receive(Vector2i(14,2),"copper_ingot_3")
	game.progression.unlocked["furnace"] = true
	wave.base_health = 72.0
	game.cycle.complete_night()
	await settle()
	check(saves.day_checkpoint["cycle"]["day"] == 3 and saves.day_checkpoint["coins"] == 2588,"Dawn automatically replaces the checkpoint with the new day's assets")
	check(saves.valid_snapshot(saves.snapshot()),"The dawn checkpoint is a valid serializable save")
	game.economy.coins = 1
	game.mining.items_for("copper_ingot_3").clear()
	game.mining.coal_veins[Vector2i(14,0)]["level"] = 1
	game.get_node("Furnaces").machines[Vector2i(16,1)]["fuel"] = 0
	game.launchers.launchers[game.grid.defense_cell("left")]["ammo"].clear()
	game.get_node("Construction").plans.clear()
	game.progression.unlocked["gold"] = true
	game.cycle.start_night(true)
	wave.start_wave(3)
	wave.launch_acid(Vector2(744,-100),2,3)
	game.phase_clock.set_night_speed(4)
	wave._on_base_attacked(100)
	check(game.cycle.defeated and saves.day_checkpoint["coins"] == 2588,"Fatal combat cannot overwrite the morning checkpoint")
	saves.path = "user://day-retry-test.dat"
	check(saves.save_game(),"A defeated game writes its morning checkpoint to disk")
	var defeated_save: Dictionary = saves.read_save()
	saves.day_checkpoint.clear()
	check(saves.restore_snapshot(defeated_save) and saves.day_checkpoint["coins"] == 2588,"Reloading a defeated save restores its checkpoint independently of memory")
	game.phase_clock.update_clock()
	await settle()
	saves.test_mode = false
	var action: Button = game.phase_clock.action
	var at: Vector2 = root.get_screen_transform() * (action.get_global_transform_with_canvas() * (action.size * 0.5))
	await mouse_move(at)
	await mouse_button(at,true)
	await mouse_button(at,false)
	check(saves.read_save()["cycle"]["defeated"],"Retry waits for Save and exit before replacing the saved defeat")
	check(game.cycle.day == 3 and not game.cycle.defeated and not game.cycle.is_night and game.cycle.day_remaining == 300,"The actual retry button starts the same day with five preparation minutes")
	check(game.phase_clock.time_label.text == "06:00" and game.economy.coins == 2588 and wave.base_health == 72,"Retry restores 06:00, money and the health present at dawn")
	check(game.mining.vein_level(Vector2i(14,0)) == 4 and game.mining.items_for("copper_ingot_3").get(Vector2i(15,1)) == 1,"Retry restores vein levels and resources spent during the day")
	check(game.launchers.launchers[game.grid.defense_cell("left")]["ammo"].size() == 4 and game.get_node("Furnaces").machines[Vector2i(16,1)]["fuel"] == 27,"Retry restores morning ammunition and furnace fuel")
	check(game.get_node("Construction").plans[Vector2i(14,2)]["delivered"]["copper_ingot_3"] == 1 and not game.progression.unlocked.has("gold"),"Retry restores partial construction and progression without later gains")
	check(not wave.active_wave and wave.living_zombies().is_empty() and wave.acid_shots.is_empty() and wave.acid_pools.is_empty(),"Retry clears the failed horde and all acid hazards")
	check(not game.camera_controller.defense_view and not game.night_victory_overlay.visible and Engine.time_scale == 1.0,"Retry returns to the mine at normal speed without a victory popup")
	check(game.get_node_or_null("TutorialGuide") == null,"Retry after day one never brings back the tutorial")
	var bad: Dictionary = defeated_save.duplicate(true)
	bad["day_checkpoint"]["day_checkpoint"] = {}
	check(not saves.valid_snapshot(bad),"Nested checkpoints are rejected without recursive expansion")
	bad = defeated_save.duplicate(true)
	bad["day_checkpoint"]["coins"] = -1
	check(not saves.valid_snapshot(bad),"Invalid checkpoint contents cannot enter the save")
	var legacy: Dictionary = defeated_save.duplicate(true)
	legacy.erase("day_checkpoint")
	check(saves.restore_snapshot(legacy) and saves.retry_day(),"Old saves without a checkpoint can still retry the same day")
	check(game.cycle.day == 3 and game.economy.coins == 1 and wave.base_health == 100,"Legacy fallback preserves available assets and restores a viable morning")
	print("RESULT: %d passed, %d failed; day retry checkpoints" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
