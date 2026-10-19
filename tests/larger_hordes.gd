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
	for day in [1,2,3,5,10,18,100]:
		check(manager.wave_size(day) == mini(160,24 + (day - 1) * 8),"Day %d uses the increased horde progression" % day)
	manager.start_wave(18)
	check(manager.wave_total == 160 and manager.spawn_interval() < 0.6,"Late hordes spawn more frequently inside the same ninety-second window")
	for i in range(200):
		manager._process(1)
		for z: Node in manager.living_zombies(): z.set_process(false)
	check(manager.living_zombies().size() == 64 and manager.spawn_count == 64,"A crowded battlefield enforces the sixty-four-enemy limit")
	check(manager.active_wave and game.cycle.is_night,"A full battlefield does not discard the rest of the wave at dawn")
	var saves: Node = game.get_node("SaveGame")
	var state: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(state) and saves.restore_snapshot(state),"Large hordes and sixty-four live enemies can be saved and restored")
	check(manager.wave_total == 160 and manager.spawn_count == 64 and manager.living_zombies().size() == 64,"Loading preserves all enemies and the outstanding spawn queue")
	for z: Node in manager.living_zombies(): z.set_process(false)
	manager.living_zombies()[0].take_damage(100)
	manager._process(1)
	check(manager.living_zombies().size() == 64 and manager.spawn_count == 65,"Freeing one slot admits the next queued enemy")
	while manager.spawn_count < manager.wave_total:
		clear_enemies()
		manager._process(1)
		for z: Node in manager.living_zombies(): z.set_process(false)
	check(manager.active_wave and manager.spawn_count == 160,"Every enemy in the finite horde spawns before victory")
	clear_enemies()
	manager._process(0)
	check(not manager.active_wave and not game.cycle.is_night,"Clearing the larger horde still completes the night")
	print("RESULT: %d passed, %d failed; larger hordes" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
