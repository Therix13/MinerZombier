extends "res://tests/building_controls.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	mover = game.get_node("WorldInteractions")
	compactors = game.get_node("Compactors")
	compactors.set_process(false)
	game.get_node("Furnaces").set_process(false)
	var mining: RefCounted = game.mining
	var a := Vector2i(14,1)
	var b := Vector2i(15,1)
	var out := Vector2i(16,1)
	var cash: int = game.economy.coins
	var xp: int = game.progression.total_experience
	for material: String in ["coal", "brass"]:
		var veins: Dictionary = mining.brass_veins if material == "brass" else mining.coal_veins
		for tier in range(1, 4):
			clear_items()
			mining.place_vein(a, 3, material)
			mining.place_vein(b, 1, material)
			veins[a]["level"] = tier
			veins[b]["level"] = tier
			veins[a]["progress"] = 3
			veins[b]["progress"] = 2
			check(mining.can_fuse_veins(a,b) and not mover.swaps_contents("vein",a,b), "%s level %d merges instead of swapping" % [material,tier])
			if tier == 1:
				game.redraw_world()
				await settle()
				await drag(a,b)
			else: check(mover.drop("vein",a,b,3), "Programmatic vein drops use the same fusion path")
			check(not veins.has(a) and mining.vein_level(b) == tier + 1 and veins[b]["direction"] == 1 and veins[b]["progress"] == 0, "Fusion creates exactly one next-tier vein, preserves its outlet and resets progress")
			check(game.economy.coins == cash and game.progression.total_experience == xp, "Vein fusion grants no free coins or EXP")
			var price: int = game.economy.BRASS_VEIN_PRICE if material == "brass" else game.economy.COAL_VEIN_PRICE
			check(mover.resale_value("vein",b) == price * int(pow(2,tier)) / 2, "The fused vein retains half the combined purchase value")
		clear_items()
		mining.place_vein(a,3,material)
		mining.place_vein(b,1,material)
		veins[a]["level"] = 4
		veins[b]["level"] = 4
		check(not mining.can_fuse_veins(a,b) and not mining.fuse_veins(a,b) and veins.size() == 2, "Level-four veins never become level five or lose either vein")
		veins[b]["level"] = 3
		check(not mining.can_fuse_veins(a,b), "Different vein levels cannot fuse")
		clear_items()
		mining.place_vein(b,1,material)
		for tier in range(1,5):
			veins[b]["level"] = tier
			veins[b]["progress"] = 0
			mining.drop_random.seed = 700 + tier
			var histogram: Dictionary = {}
			var valid := true
			for sample in range(1000):
				for strike in range(mining.hardness(material)):
					if not mining.mine(b): valid = false
				var kind: String = mining.nugget_type(out)
				var level: int = mining.ore_level(kind)
				valid = valid and kind.begins_with(material) and mining.nuggets_at(out) == 1 and level in ([1] if tier == 1 else [tier,tier-1])
				histogram[level] = int(histogram.get(level,0)) + 1
				mining.remove_one_nugget(out,kind)
			check(valid, "%s level %d always drops exactly one nugget of an allowed tier" % [material,tier])
			check(histogram.get(1,0) == 1000 if tier == 1 else absi(int(histogram.get(tier,0)) - 500) < 70, "%s level %d follows its 100%% or 50/50 drop distribution" % [material,tier])
			check(mining.rolled_vein_level(tier,0) == tier and mining.rolled_vein_level(tier,0.499) == tier and mining.rolled_vein_level(tier,0.5) == maxi(1,tier-1), "Exact probability boundaries never skip an extra tier")
		veins[b]["level"] = 4
		veins[b]["progress"] = mining.hardness(material) - 1
		mining.items_for("coal")[out] = 1
		var state: int = mining.drop_random.state
		check(not mining.mine(b) and mining.drop_random.state == state and veins[b]["progress"] == mining.hardness(material) - 1, "Blocked output preserves both progress and the random sequence")
		mining.remove_one_nugget(out,"coal")
		veins[b]["progress"] = 0
		game.drills.place(a,1)
		for strike in range(mining.hardness(material)): game.drills.tick()
		check(mining.nugget_type(out) in [material+"_4", material+"_3"] and mining.nuggets_at(out) == 1, "Automatic drills use the upgraded vein's drops")
		clear_items()
	mining.place_vein(a,1,"coal")
	mining.place_vein(b,1,"brass")
	check(not mining.can_fuse_veins(a,b), "Coal and brass veins cannot fuse together")
	clear_items()
	mining.place_vein(a,3)
	mining.place_vein(b,1)
	mining.coal_veins[a].erase("level")
	mining.coal_veins[b].erase("level")
	check(mining.fuse_veins(a,b) and mining.vein_level(b) == 2, "Legacy vein dictionaries behave as level one")
	mining.move_vein(b,out,2)
	check(mining.vein_level(out) == 2 and mining.coal_veins[out]["direction"] == 2, "Moving and rotating an upgraded vein preserves its level")
	mining.place_vein(b,1)
	mining.coal_veins[b]["level"] = 2
	game.cycle.is_night = true
	check(not mover.drop("vein",b,out), "Nighttime construction locks also prevent vein fusion")
	game.cycle.is_night = false
	game.cycle.tutorial_skipped = false
	game.cycle.tutorial_step = 2
	check(not mover.drop("vein",b,out) and not game.cycle.fusion_taught, "Vein fusion cannot bypass the nugget tutorial")
	game.cycle.skip_tutorial()
	var value: int = mover.resale_value("vein",out)
	check(mover.sell("vein",out) and game.economy.coins == cash + value, "Selling the upgraded vein pays its preserved resale value once")
	if DisplayServer.get_name() != "headless":
		clear_items()
		for tier in range(1,5):
			for material: String in ["coal","brass"]:
				var cell := Vector2i(12 + tier,1 if material == "coal" else 3)
				mining.place_vein(cell,1,material)
				var veins: Dictionary = mining.brass_veins if material == "brass" else mining.coal_veins
				veins[cell]["level"] = tier
		game.redraw_world()
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/vein-levels.png")
	print("RESULT: ", passed, " passed; ", failed, " failed; vein levels and drops")
	game.queue_free()
	await settle()
	await create_timer(0.15).timeout
	quit(0 if failed == 0 else 1)
