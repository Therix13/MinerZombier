extends "res://tests/timed_hordes.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.cycle.barrier_broken = true
	game.cycle.is_night = true
	manager = game.zombie_manager
	manager.set_process(false)
	manager.start_wave(1)
	clear_enemies()
	manager.spawn_count = manager.wave_total
	var survivor: Node2D = enemy("walker",Vector2(744,-28))
	manager.wave_elapsed = 116
	manager._process(1)
	check(not survivor.retreating and survivor.phase == "advance","Survivor does not retreat at 117 seconds")
	manager._process(3)
	check(manager.active_wave and game.cycle.is_night and manager.living_zombies().has(survivor),"Dawn preserves the same living enemy and active combat")
	survivor.attacking = true
	survivor.attack_timer = 0
	var health: float = manager.base_health
	survivor._process(1)
	check(manager.base_health < health,"Survivor continues melee damage after the night timer expires")
	manager.launch_acid(Vector2(744,-100),2,1)
	check(manager.acid_shots.size() == 1,"Acid attacks remain enabled after dawn")
	health = manager.base_health
	manager._process(2)
	check(manager.base_health < health and manager.active_wave,"Acid still damages the base without ending combat")
	var saves: Node = game.get_node("SaveGame")
	var state: Dictionary = saves.snapshot()
	state["wave"]["retreat_started"] = true
	state["enemies"][0]["retreating"] = true
	state["enemies"][0]["phase"] = "retreat"
	check(saves.valid_snapshot(state) and saves.restore_snapshot(state),"Legacy retreat saves remain loadable at dawn")
	survivor = manager.living_zombies()[0]
	survivor.set_process(false)
	check(not manager.retreat_started and not survivor.retreating and survivor.phase == "advance","Loading restores legacy survivors to active combat")
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	var cell: Vector2i = game.grid.defense_cell("left")
	game.launchers.place(cell)
	game.launchers.launchers[cell]["ammo"].assign(["gold"])
	survivor.position = game.grid.get_cell_rect(cell).get_center() + Vector2(0,-40)
	var second: Node2D = enemy("walker")
	game.launchers.advance(4)
	check(not survivor.is_in_group("zombies") and game.launchers.launchers[cell]["ammo"].is_empty(),"Turret can kill a remaining enemy after dawn")
	manager._process(0)
	check(manager.active_wave and second.is_in_group("zombies"),"One kill does not erase other survivors")
	second.take_damage(100)
	manager.spawn_count = manager.wave_total - 1
	manager.spawn_timer = 0
	manager._process(0)
	check(manager.active_wave and manager.spawn_count == manager.wave_total and manager.living_zombies().size() == 1,"A queued enemy still spawns instead of being discarded at dawn")
	manager.living_zombies()[0].set_process(false)
	manager.living_zombies()[0].take_damage(100)
	manager._process(0)
	check(not manager.active_wave and not game.cycle.is_night and game.cycle.day == 2,"Only clearing the entire horde starts the next day")
	check(game.cycle.day_remaining == 300,"Next day retains the complete five-minute preparation time")
	game.dismiss_night_victory_popup()
	game.cycle.is_night = true
	manager.start_wave(2)
	manager.wave_elapsed = 120
	manager.base_health = 1
	manager._on_base_attacked(2)
	check(game.cycle.defeated and manager.base_health == 0,"Survivors can still destroy the base after dawn")
	print("RESULT: %d passed, %d failed; persistent night enemies" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
