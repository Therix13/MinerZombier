extends "res://tests/timed_hordes.gd"

const Catalog = preload("res://Scripts/content_catalog.gd")

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.campaign.set_process(false)
	game.cycle.skip_tutorial()
	game.camera_controller.stop_transition()
	game.grid.expand()
	manager = game.zombie_manager
	manager.set_process(false)
	mover = game.get_node("WorldInteractions")
	var campaign: Node = game.campaign
	var saves: Node = game.get_node("SaveGame")
	var spot := Vector2i(15,2)
	for material: String in Catalog.MATERIALS:
		check(game.mining.place_vein(spot,1,material) and game.mining.vein_at(spot) == material,"New vein material exists: " + material)
		game.mining.veins_for(material).erase(spot)
		for tier in range(1,4):
			var source: String = material + ("_%d" % tier if tier > 1 else "")
			var target: String = material + "_%d" % (tier + 1)
			game.mining.items_for(source)[spot] = 1
			game.mining.items_for(source)[spot + Vector2i.RIGHT] = 1
			check(game.mining.fuse(spot,spot + Vector2i.RIGHT) and game.mining.nugget_type(spot + Vector2i.RIGHT) == target,"New material fuses correctly: " + target)
			game.mining.items_for(target).clear()
	for item: String in Catalog.AMMO: check(game.mining.next_tier(item).is_empty() and game.get_node("Compactors").family(item).is_empty(),"Manufactured ammunition cannot create unsupported tiers: " + item)
	game.progression.record_resource("copper_ingot_3")
	game.shop.accept_unlock_notice()
	check(game.progression.is_item_unlocked("nitrate") and game.progression.is_item_unlocked("sulfur"),"Crafted ingredient milestones unlock nitrates and sulfur")
	game.progression.completed_veins["gold"] = true
	game.progression.restore_vein_milestones()
	check(game.progression.is_item_unlocked("tungsten"),"A maxed gold vein unlocks tungsten")
	for ingredient: String in Catalog.CRAFTS["powder"]["cost"]:
		game.mining.items_for(ingredient)[Vector2i(14,0)] = 1
	check(campaign.craft("powder") and campaign.total("nitrate_4") == 0 and campaign.total("coal_4") == 0,"Gunpowder reserves exactly its nitrate, sulfur and coal ingredients")
	campaign.advance_workshop(2)
	var partial: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(partial) and saves.restore_snapshot(partial) and campaign.state["job"]["elapsed"] == 2,"An unfinished recipe persists without refunding or duplicating ingredients")
	campaign.advance_workshop(2)
	check(campaign.total("powder") == 8 and campaign.state["job"].is_empty(),"A completed recipe produces exactly eight gunpowder")
	campaign.advance_workshop(100)
	check(campaign.total("powder") == 8,"An idle workshop never duplicates a completed batch")
	game.mining.items_for("copper_ingot")[Vector2i(14,1)] = 1
	check(campaign.craft("bullet"),"Copper and gunpowder can produce real bullets")
	campaign.advance_workshop(3)
	check(campaign.total("bullet") == 12 and campaign.total("powder") == 7,"One powder and one copper ingot yield twelve bullets")
	check(campaign.state["achievements"].has("bullet_1") and campaign.achievements().size() == 37,"Crafting unlocks real achievements from the thirty-seven-entry catalog")
	game.mining.items_for("iron_ingot_2")[Vector2i(16,1)] = 1
	check(campaign.craft("rocket"),"An explosive batch can reserve its real iron and gunpowder ingredients")
	for tile: Vector2i in game.grid.owned_tiles:
		if game.mining.can_move_nugget(tile): game.mining.items_for("coal")[tile] = 1
	campaign.advance_workshop(7)
	check(not campaign.state["job"].is_empty() and campaign.total("rocket") == 0,"A completed batch waits safely when the mine has no output space")
	game.mining.items_for("coal").erase(game.mining.items_for("coal").keys()[0])
	campaign.advance_workshop(0)
	check(campaign.state["job"].is_empty() and campaign.total("rocket") == 2,"Freeing one tile delivers the waiting batch exactly once")
	for items: Dictionary in game.mining.nugget_stores().values(): items.clear()
	game.cycle.day = 2
	game.cycle.is_night = true
	game.economy.coins = 1000
	game.on_wave_completed()
	var reward: int = game.economy.coins
	game.on_wave_completed()
	check(reward == 1180 and game.economy.coins == reward,"The night reward is paid once before advancing the day")
	var victory: Dictionary = saves.snapshot()
	check(saves.restore_snapshot(victory) and game.economy.coins == reward,"Reloading a completed night does not pay its reward again")
	game.dismiss_night_victory_popup()
	game.camera_controller.stop_transition()
	game.shop.accept_unlock_notice()
	game.economy.coins = 1000000
	var plans: Node = game.get_node("Construction")
	for weapon: String in Catalog.WEAPONS:
		game.progression.unlocked[weapon] = true
		check(mover.select_item(weapon) and mover.place_selected(spot) and plans.plans[spot]["item"] == weapon,"Industrial weapon can be purchased as a real blueprint: " + weapon)
		for ingredient: String in plans.RECIPES[weapon]:
			for amount in range(plans.RECIPES[weapon][ingredient]): plans.receive(spot,ingredient)
		check(game.launchers.launchers[spot]["weapon"] == weapon,"Completing its blueprint creates the correct industrial weapon: " + weapon)
		game.launchers.launchers.erase(spot)
	game.grid.purchase_defense_platforms()
	var cell: Vector2i = game.grid.defense_cell("left")
	for weapon: String in Catalog.WEAPONS:
		game.launchers.launchers.clear()
		game.launchers.place(cell,2)
		game.launchers.launchers[cell]["weapon"] = weapon
		check(game.launchers.capacity_at(cell) == Catalog.WEAPONS[weapon]["capacity"] and game.launchers.interval_at(cell) == Catalog.WEAPONS[weapon]["interval"],"Weapon has its own magazine and fire cadence: " + weapon)
		check(not game.launchers.receive(cell,"coal_4") and game.launchers.receive(cell,Catalog.WEAPONS[weapon]["ammo"]),"Weapon accepts only the manufactured ammunition it requires: " + weapon)
		var position: Vector2 = game.grid.get_cell_rect(cell).get_center() + Vector2(0,-70)
		var first: Node2D = enemy("walker",position)
		var second: Node2D = enemy("walker",position + Vector2(10,0))
		game.launchers.advance(4)
		check(first.health <= 0 or second.health <= 0,"The new weapon actually kills its selected target: " + weapon)
		if float(Catalog.WEAPONS[weapon]["radius"]) > 0: check(first.health <= 0 and second.health <= 0,"Area weapon damages nearby enemies: " + weapon)
		check(game.launchers.launchers[cell]["ammo"].is_empty(),"Each shot consumes one manufactured round: " + weapon)
		clear_enemies()
	var full: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(full) and saves.restore_snapshot(full),"Extended resources, weapons, magazine capacities and campaign state round-trip")
	var legacy: Dictionary = saves.snapshot()
	legacy.erase("campaign")
	legacy["launchers"].clear()
	for material: String in Catalog.MATERIALS: legacy["veins"].erase(material)
	for kind: String in game.mining.EXTRA_KINDS: legacy["resources"].erase(kind)
	check(saves.valid_snapshot(legacy) and saves.restore_snapshot(legacy) and campaign.state["kills"] == 0,"Existing saves migrate to empty new stores and clean campaign counters")
	manager.active_wave = true
	var healer: Node2D = enemy("healer")
	var ally: Node2D = enemy("armored",healer.position + Vector2(30,0))
	ally.health = 1
	healer._process(0.1)
	check(ally.health > 1,"A healer restores nearby allies rather than merely having more health")
	var shield: Node2D = enemy("shielder",healer.position)
	ally.armor = 0
	shield._process(0.1)
	check(ally.armor > 0,"Shield bearers restore nearby armor")
	clear_enemies()
	var swarm: Node2D = enemy("swarm")
	swarm.take_damage(100)
	check(manager.living_zombies().size() == 2 and manager.living_zombies()[0].archetype == "crawler","Killing a hive spawns two actual crawlers")
	clear_enemies()
	for boss: String in ["warden","broodmother","executor"]:
		var z: Node2D = enemy(boss,Vector2(744,-100))
		z.attack_timer = 0
		z._process(0.1)
		check(z.phase == "windup","Boss telegraphs its attack: " + boss)
		z._process(2)
		z._process(1)
		check(z.phase == "exposed","Boss presents a real counterattack window: " + boss)
		z.apply_slow(2)
		var boss_save: Dictionary = saves.snapshot()
		check(saves.valid_snapshot(boss_save) and saves.restore_snapshot(boss_save),"Boss phase, support state and electric slow survive loading: " + boss)
		for enemy_node: Node in manager.living_zombies(): enemy_node.set_process(false)
		clear_enemies()
	game.zombie_manager.active_wave = false
	game.economy.coins = 1000000
	check(campaign.expand_gallery() and game.grid.cave_width == 11 and campaign.expand_gallery() and game.grid.cave_width == 15 and not campaign.expand_gallery(),"Late-game galleries expand to eleven and fifteen tiles, then stop charging")
	check(campaign.add_platforms() and campaign.add_platforms() and game.grid.defense_tiles.size() == 6 and not campaign.add_platforms(),"Industrial defenses support six actual turret platforms")
	var expanded: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(expanded) and saves.restore_snapshot(expanded) and game.grid.cave_width == 15 and game.grid.defense_tiles.size() == 6,"Expanded ownership and all defense platforms survive reload")
	manager.base_health = 90
	check(campaign.repair() and manager.base_health == 100 and not campaign.repair(),"Repairs cap at full health and cannot charge when already full")
	check(not campaign.upgrade_arsenal(),"Industrial upgrades cannot be bought before their required night")
	campaign.state["best_night"] = 25
	for ingredient: String in Catalog.INDUSTRIAL_UPGRADES[0]["cost"]:
		game.mining.items_for(ingredient)[Vector2i(14,1)] = 2
	check(campaign.upgrade_arsenal() and campaign.state["arsenal_rank"] == 1 and campaign.total("iron_ingot_4") == 0,"A late-game arsenal upgrade consumes its money and ingots exactly once")
	game.launchers.launchers.clear()
	game.launchers.place(cell,2)
	game.launchers.launchers[cell]["weapon"] = "pistol"
	while game.launchers.receive(cell,"bullet"): pass
	check(game.launchers.capacity_at(cell) == 30 and game.launchers.interval_at(cell) < 0.65,"Arsenal improvements increase real magazine capacity and fire cadence")
	var upgraded: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(upgraded) and saves.restore_snapshot(upgraded) and game.launchers.launchers[cell]["ammo"].size() == 30,"Upgraded industrial magazines and progression survive saving")
	var unchanged: int = game.economy.coins
	check(not campaign.upgrade_arsenal() and game.economy.coins == unchanged,"The next upgrade remains gated until night one hundred without charging")
	var all_valid: bool = true
	for day in range(1,901):
		var size: int = manager.wave_size(day)
		for index in range(size): all_valid = all_valid and manager.archetype_for(day,index,size) in Enemy.TYPES
	check(all_valid and Catalog.chapter(900)["start"] == 601,"All nine hundred scheduled nights use valid enemy archetypes and chapter progression")
	check(Enemy.TYPES.size() == 18,"The bestiary includes eighteen distinct enemy types")
	campaign.set_process(true)
	campaign.open_panel()
	campaign.show_tab("Taller")
	await settle()
	check(campaign.overlay.visible and paused,"The real workshop panel opens modally with recipes and inventory")
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/content-workshop.png")
	campaign.show_tab("Bestiario")
	await settle()
	check(manager.living_zombies().is_empty() and saves.snapshot()["enemies"].is_empty(),"Animated bestiary previews never become combat enemies or enter saves")
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/content-bestiary.png")
	campaign.page.get_parent().scroll_vertical = 1200
	await settle()
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/content-bestiary-advanced.png")
	campaign.close_panel()
	check(not paused and not campaign.overlay.visible,"Closing the campaign panel resumes gameplay")
	print("RESULT: %d passed, %d failed; industrial content expansion" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
