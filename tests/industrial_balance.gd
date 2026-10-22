extends "res://tests/timed_hordes.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.campaign.set_process(false)
	game.cycle.skip_tutorial()
	game.cycle.barrier_broken = true
	manager = game.zombie_manager
	manager.set_process(false)
	game.grid.purchase_defense_platforms(6)
	var samples := [1,3,6,10,15,20,21,30,50,100,200,500,900]
	for day: int in samples:
		clear_enemies()
		game.launchers.launchers.clear()
		manager.active_wave = false
		game.cycle.defeated = false
		game.cycle.is_night = true
		game.cycle.day = day
		game.night_victory_overlay.hide()
		manager.base_health = 100
		var count: int = 2 if day < 10 else (4 if day < 21 else 6)
		var i: int = 0
		for cell: Vector2i in game.grid.defense_tiles:
			if i >= count: break
			game.launchers.place(cell,1 if day == 1 else 2)
			if day >= 6:
				game.launchers.launchers[cell]["weapon"] = "pistol" if i < 2 else ("grenadier" if day < 21 else ("rocketeer" if i < 4 else "tesla"))
			i += 1
		game.campaign.state["arsenal_rank"] = 3 if day > 250 else (2 if day > 100 else (1 if day > 25 else 0))
		manager.start_wave(day)
		var max_active: int = 0
		var fired: int = 0
		for tick in range(1200):
			if not manager.active_wave: break
			for cell: Vector2i in game.launchers.launchers:
				var data: Dictionary = game.launchers.launchers[cell]
				var kind: String = "coal" if day == 1 else "copper"
				if data.has("weapon"): kind = game.launchers.Catalog.WEAPONS[data["weapon"]]["ammo"]
				while game.launchers.receive(cell,kind): pass
			for z: Node in manager.living_zombies():
				z.set_process(false)
				z._process(0.25)
			var priority: Node2D = null
			var best_score: int = -1
			for z: Node2D in manager.living_zombies():
				var score: int = 100 if z.archetype in ["plague","warden","broodmother","executor"] and z.phase == "exposed" else (95 if z.behavior() in ["spitter","plague"] else (90 if z.archetype == "healer" else (80 if z.archetype == "shielder" else (75 if z.phase == "exposed" else 0))))
				if score > best_score:
					priority = z
					best_score = score
			if priority != null: game.launchers.focus(priority)
			var rounds_before: int = 0
			for weapon: Dictionary in game.launchers.launchers.values(): rounds_before += weapon["ammo"].size()
			game.launchers.advance(0.25)
			var rounds_after: int = 0
			for weapon: Dictionary in game.launchers.launchers.values(): rounds_after += weapon["ammo"].size()
			fired += rounds_before - rounds_after
			manager._process(0.25)
			max_active = maxi(max_active,manager.living_zombies().size())
		check(not game.cycle.defeated and not manager.active_wave and game.cycle.day == day + 1,"Supplied era-appropriate defenses can clear night %d (base %.0f)" % [day,manager.base_health])
		check(max_active <= manager.MAX_ZOMBIES,"Night %d respects the sixty-four-enemy cap" % day)
		print("BALANCE: night=%d base=%.1f enemies=%d observed=%d shots=%d" % [day,manager.base_health,manager.wave_total,max_active,fired])
		game.dismiss_night_victory_popup()
		game.camera_controller.stop_transition()
		await settle()
	print("RESULT: %d passed, %d failed; supplied industrial combat balance" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
