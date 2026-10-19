extends "res://tests/interactions.gd"

const Enemy = preload("res://Scripts/zombie.gd")
var manager: Node

func enemy(kind: String, at := Vector2(744,-150)) -> Node2D:
	var z: Node2D = Enemy.new()
	z.setup(at,Vector2(at.x,-28))
	z.configure(kind)
	manager.connect_zombie(z)
	manager.add_child(z)
	z.set_process(false)
	return z

func clear_enemies() -> void:
	for z: Node in manager.living_zombies(): z.depart()
	manager.acid_shots.clear()
	manager.acid_pools.clear()

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	manager = game.zombie_manager
	manager.set_process(false)
	game.cycle.skip_tutorial()
	game.cycle.barrier_broken = true
	game.cycle.is_night = true
	manager.start_wave(1)
	check(manager.wave_total == 6 and manager.remaining_time() == 120,"First horde has a fixed two-minute duration")
	clear_enemies()
	manager._process(3)
	check(manager.active_wave and game.cycle.day == 1,"An early empty battlefield does not skip the rest of the timed horde")
	manager._process(114)
	check(manager.retreat_started and manager.wave_elapsed == 117,"Last three seconds visibly end enemy attacks and spawning")
	var before: float = manager.base_health
	manager._on_base_attacked(50)
	check(manager.base_health == before,"Retreating enemies cannot attack after dawn begins")
	manager._process(3)
	await settle()
	check(not game.cycle.is_night and game.cycle.day == 2 and game.cycle.day_remaining == 300,"Surviving two minutes starts a five-minute preparation day")
	check(game.get_node_or_null("TutorialGuide") == null and not game.shop.get_node("CyclePanel").visible,"Tutorial logic, arrows and its window disappear permanently after night one")
	check(not game.phase_clock.can_tick(),"Victory review preserves the full preparation budget")
	game.dismiss_night_victory_popup()
	game.camera_controller.stop_transition()
	game.cycle.day_remaining = 0.1
	game.launchers.launchers.clear()
	game._process(0.2)
	check(game.cycle.is_night and manager.active_wave and manager.wave_day == 2,"Countdown automatically starts the next horde even without ammunition")
	clear_enemies()
	check(manager.archetype_for(2,1,8) == "runner" and manager.archetype_for(3,2,10) == "armored","New days introduce faster and armored enemies")
	check(manager.archetype_for(4,3,12) == "spitter" and manager.archetype_for(3,5,10) == "brute","Acid enemies and a charging minijefe have distinct spawn milestones")
	check(manager.archetype_for(5,0,14) == "plague" and manager.archetype_for(6,4,16) == "bomber","Boss nights and explosives expand the enemy roster")
	var walker: Node2D = enemy("walker",Vector2(744,-300))
	var runner: Node2D = enemy("runner",Vector2(744,-300))
	walker._process(1)
	runner._process(1)
	check(runner.position.y > walker.position.y and runner.max_health == walker.max_health,"Runner difficulty comes from speed rather than extra health")
	walker.depart()
	runner.depart()
	var armored: Node2D = enemy("armored")
	armored.take_damage(1)
	check(armored.health == 2 and armored.armor == 0.5,"Armor absorbs damage before health")
	armored.take_damage(1)
	check(armored.health == 1.5 and armored.armor == 0,"Breaking armor carries excess damage into health")
	armored.depart()
	var brute: Node2D = enemy("brute")
	brute._process(0.01)
	check(brute.phase == "windup" and brute.position.y == -150,"Miniboss telegraphs its charge before moving")
	brute._process(1.5)
	brute._process(1)
	check(brute.phase == "exposed" and manager.base_health == before - 8,"Charge impact leaves a four-second counterattack opening")
	var hp: float = brute.health
	brute.take_damage(1)
	check(brute.health == hp - 2,"Counterattack opening doubles damage and bypasses armor")
	brute.depart()
	var spitter: Node2D = enemy("spitter",Vector2(744,-100))
	spitter.attack_timer = 0
	spitter._process(0.1)
	check(spitter.phase == "windup" and manager.acid_shots.is_empty(),"Acid attack is telegraphed rather than dealing instant invisible damage")
	spitter._process(1)
	check(manager.acid_shots.size() == 1,"Spitter releases a visible, timed acid projectile")
	before = manager.base_health
	manager.advance_acid(0.5)
	check(manager.base_health == before,"Traveling acid does not hit early")
	manager.advance_acid(0.8)
	check(manager.base_health < before and manager.acid_pools.size() == 1,"Acid impact damages the base and leaves a temporary pool")
	spitter.depart()
	manager.acid_shots.clear()
	manager.acid_pools.clear()
	var boss: Node2D = enemy("plague",Vector2(744,-100))
	hp = boss.health
	boss.take_damage(1)
	check(is_equal_approx(boss.health,hp - 0.3),"Boss shield reduces damage outside the exposed phase")
	boss.attack_timer = 0
	boss._process(0.1)
	boss._process(2)
	check(manager.acid_shots.size() == 3 and boss.phase == "exposed" and boss.ability_timer == 5,"Boss volley drops its shield for five seconds")
	hp = boss.health
	boss.take_damage(1)
	check(boss.health == hp - 2,"Boss vulnerability window rewards focusing fire")
	var saves: Node = game.get_node("SaveGame")
	var state: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(state) and saves.restore_snapshot(state),"Wave clock, acid volley and boss state survive save and reload")
	check(manager.acid_shots.size() == 3 and manager.living_zombies()[0].phase == "exposed" and manager.living_zombies()[0].archetype == "plague","Reload does not reset the boss or erase its projectiles")
	clear_enemies()
	var bomber: Node2D = enemy("bomber",Vector2(744,-50))
	bomber._process(0.1)
	before = manager.base_health
	check(bomber.phase == "windup" and manager.base_health == before,"Explosive enemy warns before detonating")
	bomber.take_damage(10)
	check(manager.base_health == before,"Killing an explosive during its warning prevents the blast")
	var legacy: Dictionary = saves.snapshot()
	legacy.erase("combat_revision")
	legacy["cycle"].erase("day_remaining")
	legacy["wave"].erase("wave_elapsed")
	legacy["wave"].erase("retreat_started")
	legacy.erase("acid_shots")
	legacy.erase("acid_pools")
	check(saves.valid_snapshot(legacy) and saves.restore_snapshot(legacy),"Old saves migrate into the timed horde system")
	clear_enemies()
	manager.active_wave = false
	game.cycle.is_night = false
	game.cycle.day_remaining = 90
	game.cycle.advance_day(1)
	check(game.cycle.day_remaining == 89,"Preparation timer spends active management time")
	game.get_tree().paused = true
	check(not game.phase_clock.can_tick(),"Settings and game pause freeze preparation time")
	game.get_tree().paused = false
	game.cycle.is_night = true
	manager.active_wave = true
	manager.retreat_started = false
	manager.base_health = 1
	manager.launch_acid(Vector2(744,-100),2,3)
	manager.advance_acid(2)
	check(game.cycle.defeated and manager.base_health == 0 and manager.acid_shots.is_empty() and manager.acid_pools.is_empty(),"Fatal acid volley ends combat once and safely clears all hazards")
	print("RESULT: %d passed, %d failed; timed hordes and enemy mechanics" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
