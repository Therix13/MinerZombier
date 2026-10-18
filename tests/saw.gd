extends "res://tests/building_controls.gd"

func run_checks() -> void:
	root.show()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://"+scene).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	game.economy.coins = 10000
	mover = game.get_node("WorldInteractions")
	shop = game.shop
	compactors = game.get_node("Compactors")
	compactors.set_process(false)
	game.get_node("Furnaces").set_process(false)
	var saw: Node2D = game.get_node("Saws")
	saw.set_process(false)
	var inspector: CanvasLayer = game.get_node("ToolInspector")
	var a := Vector2i(14,1)
	var c := Vector2i(15,1)
	var out := Vector2i(16,1)
	check(not game.progression.is_item_unlocked("saw"),"Sierra respects research locks")
	game.progression.level = 3
	game.progression.research_points = 3
	game.progression.unlocked["furnace"] = true
	check(game.progression.research("saw") and game.progression.is_item_unlocked("saw"),"Research unlocks the Sierra at level three")
	check("saw" in shop.visible_shop_items("HERRAMIENTAS"),"Sierra appears in the tools category after research")
	var cash: int = game.economy.coins
	check(mover.select_item("saw") and game.economy.coins == cash,"Selecting the Sierra does not charge")
	await key(KEY_R)
	check(game.placement_direction == 2,"R rotates the preview")
	check(mover.place_selected(c) and game.get_node("Construction").plans.has(c) and not saw.machines.has(c),"Placement creates an inactive blueprint")
	game.get_node("Construction").receive(c,"brass_ingot")
	game.get_node("Construction").receive(c,"brass_ingot")
	check(saw.machines.has(c) and saw.machines[c]["direction"] == 2 and game.economy.coins == cash - saw.PRICE,"A completed blueprint becomes a Sierra with its chosen outlet")
	clear_items()
	for material in ["coal","brass","iron","brass_ingot","iron_ingot"]:
		for tier in range(2,5):
			clear_items()
			saw.place(c,1)
			var input: String = material + "_" + str(tier)
			var output: String = material if tier == 2 else material + "_" + str(tier-1)
			game.mining.items_for(input)[a] = 1
			check(mover.drop("nugget",a,c) and game.mining.nuggets_at(a) == 0,"Sierra consumes a single %s" % input)
			var xp: int = game.progression.total_experience
			cash = game.economy.coins
			saw.process_cutting(3.9)
			check(saw.stored_items(c) == {input:1} and game.mining.nuggets_at(out) == 0,"A four-second cut cannot finish early")
			game.mining.items_for("coal")[out] = 1
			saw.process_cutting(0.1)
			check(saw.stored_items(c) == {output:2} and not saw.can_receive(c,input),"The blocked output preserves exactly two %s" % output)
			saw.process_cutting(100)
			check(saw.stored_items(c) == {output:2} and game.progression.total_experience == xp and game.economy.coins == cash,"Waiting cannot duplicate items, coins or EXP")
			game.mining.remove_one_nugget(out,"coal")
			saw.process_cutting(0)
			check(game.mining.nugget_type(out) == output and game.mining.nuggets_at(out) == 1 and saw.stored_items(c) == {output:1},"First product exits without stacking on the grid")
			game.mining.remove_one_nugget(out,output)
			saw.process_cutting(0)
			check(game.mining.nugget_type(out) == output and saw.stored_items(c).is_empty() and saw.can_receive(c,input),"Second product exits and unlocks the next cut")
	clear_items()
	saw.place(c,1)
	for kind: String in ["coal","brass","iron","brass_ingot","iron_ingot","coal_ingot_2","coal_5",""]:
		check(not saw.receive(c,kind),"Sierra rejects level-one or invalid material: " + kind)
	game.mining.items_for("coal")[a] = 1
	check(not mover.drop("nugget",a,c) and game.mining.nuggets_at(a) == 1,"A rejected raw nugget stays in the player's source cell")
	clear_items()
	saw.place(c,1)
	game.conveyors.place(a,1)
	game.conveyors.place(c+Vector2i.UP,2)
	game.mining.items_for("brass_3")[a] = 1
	game.mining.items_for("iron_4")[c+Vector2i.UP] = 1
	game.conveyors.tick()
	check(saw.stored_items(c) == {"brass_3":1} and game.mining.nugget_type(c+Vector2i.UP) == "iron_4","Two incoming belts cannot overfill or lose a second input")
	game.conveyors.place(out,3)
	saw.process_cutting(4)
	check(saw.stored_items(c) == {"brass_2":2} and game.mining.nuggets_at(out) == 0,"A belt facing the wrong way blocks the output safely")
	game.conveyors.belts[out]["direction"] = 1
	saw.process_cutting(0)
	check(game.mining.nugget_type(out) == "brass_2" and saw.stored_items(c) == {"brass_2":1},"Correcting the conveyor releases one of the two products")
	clear_items()
	saw.place(c,1)
	saw.receive(c,"iron_4")
	saw.process_cutting(2)
	check(mover.drop("saw",c,a,2) and saw.machines[a]["input"] == "iron_4" and saw.machines[a]["elapsed"] == 2 and saw.machines[a]["direction"] == 2,"Moving a loaded Sierra preserves its material, progress and outlet")
	check(not game.drills.can_place(a) and not compactors.can_place(a) and not game.get_node("Furnaces").can_place(a),"Other machines cannot overlap the Sierra")
	game.redraw_world()
	await settle()
	await mouse_move(point(a))
	await mouse_button(point(a),true)
	await mouse_button(point(a),false)
	check(inspector.is_open() and inspector.kind == "saw" and inspector.status.text.begins_with("Sierra") and inspector.withdraw_buttons.has("iron_4"),"Real tool click displays Sierra contents and cutting progress")
	check(inspector.withdraw("iron_4") and saw.stored_items(a).is_empty(),"An unfinished input can be withdrawn without creating outputs")
	inspector.close_inspector()
	clear_items()
	saw.place(c,1)
	saw.receive(c,"coal_3")
	game.mining.items_for("coal")[out] = 1
	saw.process_cutting(4)
	cash = game.economy.coins
	check(mover.sell("saw",c) and game.economy.coins == cash + saw.PRICE/2 and game.mining.items_for("coal_2").get(c,0) == 2,"Selling pays half the tool price and preserves both pending products")
	clear_items()
	saw.place(c,1)
	saw.receive(c,"brass_4")
	saw.process_cutting(2)
	game.redraw_world()
	await settle()
	inspector.open_tool("saw",c)
	await settle()
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/saw.png")
	game.free()
	await settle()
	print("RESULT: ",passed," passed; ",failed," failed; Sierra; ",scene)
	quit(1 if failed else 0)
