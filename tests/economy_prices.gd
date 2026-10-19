extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	mover = game.get_node("WorldInteractions")
	var expected := {"coal": [3,8,20,50], "brass": [5,15,40,100], "iron": [10,30,75,175], "gold": [30,75,200,500]}
	var cell := Vector2i(15,1)
	var sale_belt := Vector2i(15,0)
	for material: String in expected:
		for tier in range(1,5):
			var kind: String = material if tier == 1 else material + "_" + str(tier)
			var value: int = expected[material][tier-1]
			check(game.economy.sale_value(kind) == value,"Exact configured sale price for %s" % kind)
			if kind not in game.mining.ORE_KINDS: continue
			clear_items()
			put(cell,{kind: 1})
			var balance: int = game.economy.coins
			check(mover.drop("nugget",cell,game.grid.sale_cell) and game.economy.coins == balance + value,"Manual sale pays the configured price once: %s" % kind)
			game.conveyors.place(sale_belt,0)
			put(sale_belt,{kind: 1})
			balance = game.economy.coins
			game.conveyors.tick()
			game.conveyors.tick()
			check(game.economy.coins == balance + value and game.mining.nuggets_at(sale_belt) == 0,"Conveyor sale pays the same price once: %s" % kind)
	var ingots := {"brass": [150,400,1000,2500], "iron": [350,1000,2500,7500], "gold": [1000,2500,7500,20000]}
	for material: String in ingots:
		for tier in range(1,5):
			clear_items()
			var kind: String = material + "_ingot" + ("" if tier == 1 else "_" + str(tier))
			put(cell,{kind: 1})
			var balance: int = game.economy.coins
			var value: int = ingots[material][tier-1]
			check(game.economy.sale_value(kind) == value and mover.drop("nugget",cell,game.grid.sale_cell) and game.economy.coins == balance + value,"Ingot pays its configured sale price: %s" % kind)
	clear_items()
	for material: String in {"coal": 100,"brass": 500,"iron": 5000,"gold": 50000}:
		var price: int = {"coal": 100,"brass": 500,"iron": 5000,"gold": 50000}[material]
		check(mover.item_price(material) == price,"Placement quotes the updated vein price: %s" % material)
		game.mining.place_vein(cell,1,material)
		check(mover.resale_value("vein",cell) == price / 2,"Vein resale retains half of the new purchase price: %s" % material)
		game.mining.veins_for(material).erase(cell)
	check(game.economy.GOLD_VEIN_PRICE == 50000,"Gold vein costs 50000")
	game.economy.toggle_developer_mode()
	game.shop.open_category("VETAS")
	for material: String in ["coal","brass","iron","gold"]:
		var label: Label = game.shop.purchase_buttons[material].get_meta("price_label")
		check(label.text == "◆ %d" % mover.item_price(material),"Store displays the current vein price: %s" % material)
	print("RESULT: ",passed," passed; ",failed," failed; economy prices")
	game.queue_free()
	await settle()
	quit(0 if failed == 0 else 1)
