extends "res://tests/interactions.gd"

class Target extends Node2D:
	var hits := 0
	var total := 0.0
	func take_damage(value: float) -> void:
		hits += 1
		total += value

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
	mover = game.get_node("WorldInteractions")
	var weapons: RefCounted = game.launchers
	var cell: Vector2i = game.grid.defense_cell("left")
	var source := Vector2i(14,2)
	weapons.place(cell)
	for material: String in ["coal","copper","iron","gold"]:
		for tier in range(1,5):
			var kind: String = material + ("_" + str(tier) if tier > 1 else "")
			weapons.launchers[cell]["ammo"].clear()
			game.mining.items_for(kind)[source] = 1
			check(mover.drop("nugget",source,cell),"Manual loading accepts " + kind)
			check(game.mining.nuggets_at(source) == 0 and weapons.launchers[cell]["ammo"].size() == tier,"One nugget converts to exactly %d rounds" % tier)
			for round_kind: String in weapons.launchers[cell]["ammo"]: check(round_kind == material,"Round preserves material without multiplying tier damage")
			weapons.launchers[cell]["ammo"].assign(["coal","coal","coal","coal"])
			if tier > 1:
				game.mining.items_for(kind)[source] = 1
				check(not mover.drop("nugget",source,cell) and game.mining.nugget_type(source) == kind,"Overflowing charge stays on the ground intact")
				game.mining.items_for(kind).clear()
	weapons.launchers[cell]["ammo"].clear()
	check(not weapons.receive(cell,"copper_ingot_4"),"Ingots cannot become ammunition")
	var belt := cell + Vector2i.DOWN
	game.conveyors.place(belt,0)
	game.mining.items_for("gold_4")[belt] = 1
	game.conveyors.tick()
	check(weapons.launchers[cell]["ammo"] == ["gold","gold","gold","gold"] and game.mining.nuggets_at(belt) == 0,"Conveyor loading uses the same tier-to-round conversion")
	game.mining.items_for("iron_2")[belt] = 1
	game.conveyors.tick()
	check(game.mining.nugget_type(belt) == "iron_2" and weapons.launchers[cell]["ammo"].size() == 4,"Conveyor never destroys a charge that does not fit")
	var target := Target.new()
	game.add_child(target)
	target.add_to_group("zombies")
	var center: Vector2 = game.grid.get_cell_rect(cell).get_center()
	target.position = Vector2(center.x,-250)
	weapons.advance(4)
	check(target.hits == 0 and weapons.launchers[cell]["ammo"].size() == 4,"Launcher cannot hit above the visible engagement zone")
	target.position = Vector2(center.x,-150)
	weapons.advance(4)
	check(target.hits == 1 and weapons.launchers[cell]["ammo"].size() == 3,"Entering visible range consumes exactly one round per shot")
	check(is_equal_approx(target.total,weapons.ammo_damage("gold")),"Nugget tier changes round count rather than per-shot damage")
	check(weapons.RANGE == 300 and not weapons.in_range(cell,center + Vector2(301,0)),"World-space range is reduced to 300")
	check(weapons.capacity_at(cell) == 5 and weapons.interval_at(cell) == 4.0 and weapons.damage_multiplier == 0.5,"Level one retains its capacity, cadence and damage multiplier")
	weapons.launchers[cell]["level"] = 2
	weapons.launchers[cell]["ammo"].clear()
	check(weapons.receive(cell,"coal_4") and weapons.receive(cell,"coal_3") and weapons.launchers[cell]["ammo"].size() == 7,"Level two accepts exactly seven rounds from mixed tiers")
	check(not weapons.receive(cell,"coal"),"Level two rejects an eighth round without consuming it")
	var upgraded_save: Dictionary = game.get_node("SaveGame").snapshot()
	check(game.get_node("SaveGame").valid_snapshot(upgraded_save),"A full seven-round level-two launcher is valid for saving")
	weapons.launchers[cell]["cooldown"] = 0.0
	var before_hits: int = target.hits
	var before_damage: float = target.total
	weapons.advance(0.01)
	weapons.advance(1.99)
	check(target.hits == before_hits + 1,"Level two waits the full two seconds between shots")
	weapons.advance(0.02)
	check(target.hits == before_hits + 2 and weapons.launchers[cell]["ammo"].size() == 5,"Level two fires again after two seconds and spends one round")
	check(is_equal_approx(target.total - before_damage, 2.0),"Two level-two coal shots deal one damage each")
	for material: String in ["coal","copper","iron","gold"]:
		check(is_equal_approx(weapons.ammo_damage(material,2),weapons.ammo_damage(material,1) * 2.0),"Level two doubles per-shot damage for " + material)
	target.queue_free()
	await settle()
	check(game.get_node("SaveGame").restore_snapshot(upgraded_save) and weapons.launchers[cell]["ammo"].size() == 7,"Reload preserves all seven rounds")
	weapons.launchers[cell]["ammo"].assign(["gold","gold","gold"])
	weapons.launchers[cell]["level"] = 1
	var near: Node2D = preload("res://Scripts/zombie.gd").new()
	near.setup(Vector2(center.x,-40),Vector2(center.x,-28))
	near.configure("walker")
	game.zombie_manager.add_child(near)
	near.set_process(false)
	var priority: Node2D = preload("res://Scripts/zombie.gd").new()
	priority.setup(Vector2(center.x,-120),Vector2(center.x,-28))
	priority.configure("armored")
	game.zombie_manager.add_child(priority)
	priority.set_process(false)
	weapons.focus(priority)
	weapons.launchers[cell]["cooldown"] = 0
	weapons.advance(0.01)
	check(near.health == near.max_health and priority.armor == 0,"Focused enemy receives the shot before a nearer enemy")
	near.depart()
	priority.depart()
	var inspector: Node = game.get_node("ToolInspector")
	game.drills.place(source,1)
	inspector.open_tool("drill",source)
	check(not inspector.is_open(),"Drills never open an empty inventory window")
	await mouse_move(point(source))
	await mouse_button(point(source),true)
	await mouse_button(point(source),false)
	check(not inspector.is_open() and not game.holding_object,"A real drill click closes the interaction without getting stuck")
	var saves: Node = game.get_node("SaveGame")
	check(saves.valid_snapshot(saves.snapshot()),"Iron and gold ammunition can be saved")
	print("RESULT: %d passed, %d failed; ammunition rounds" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
