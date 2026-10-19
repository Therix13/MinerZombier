extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.cycle.barrier_broken = true
	game.grid.purchase_defense_platforms()
	var manager: Node = game.zombie_manager
	manager.set_process(false)
	for side: String in ["left","right"]: game.launchers.place(game.grid.defense_cell(side))
	var seen: Dictionary = {}
	for day in range(1,11):
		game.cycle.day = day
		game.cycle.is_night = true
		manager.base_health = 100
		manager.start_wave(day)
		var max_active := 0
		for tick in range(480):
			for cell: Vector2i in game.launchers.launchers:
				if game.launchers.launchers[cell]["ammo"].size() <= 1: game.launchers.receive(cell,"coal_4" if day == 1 else "gold_4")
			for enemy: Node in manager.living_zombies():
				enemy.set_process(false)
				seen[enemy.archetype] = true
				enemy._process(0.25)
			var priority: Node2D
			var best_score := -1
			for enemy: Node2D in manager.living_zombies():
				var reachable := false
				for cell: Vector2i in game.launchers.launchers:
					if game.launchers.in_range(cell,enemy.position): reachable = true
				if not reachable: continue
				var score: int = 100 if enemy.archetype == "plague" and enemy.phase == "exposed" else (90 if enemy.archetype == "spitter" else (85 if enemy.archetype == "bomber" else (80 if enemy.phase == "exposed" else (5 if enemy.archetype == "plague" else 30))))
				if score > best_score:
					priority = enemy
					best_score = score
			if priority != null: game.launchers.focus(priority)
			game.launchers.advance(0.25)
			manager._process(0.25)
			max_active = maxi(max_active,manager.living_zombies().size())
		check(not manager.active_wave and game.cycle.day == day + 1,"Day %d completes a full two-minute survival simulation" % day)
		check(manager.base_health > 0,"Day %d remains survivable with supplied launchers and tactical target priority" % day)
		check(max_active <= manager.MAX_ZOMBIES,"Day %d respects the active-enemy performance limit" % day)
		game.night_victory_overlay.hide()
		await settle()
	check(seen.size() == 7,"Ten nights actually exercise every enemy archetype")
	print("RESULT: %d passed, %d failed; ten-night combat simulation" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
