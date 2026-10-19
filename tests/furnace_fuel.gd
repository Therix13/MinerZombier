extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	var furnace: Node = game.get_node("Furnaces")
	furnace.set_process(false)
	var cell := Vector2i(15,1)
	var output := cell + Vector2i.UP
	check(furnace.place(cell),"A furnace can be placed for fuel accounting")
	furnace.receive(cell,"copper_4")
	furnace.machines[cell]["fuel"] = 19
	check(not game.cycle.furnace_fueled(),"The tutorial does not treat nineteen fuel as ready to smelt")
	furnace.process_smelting(100)
	check(not furnace.machines[cell]["burning"] and furnace.machines[cell]["elapsed"] == 0 and furnace.machines[cell]["fuel"] == 19,"Nineteen fuel cannot start or partially process a twenty-fuel batch")
	furnace.machines[cell]["fuel"] = 0
	check(furnace.receive(cell,"coal_4") and furnace.receive(cell,"coal_4") and furnace.machines[cell]["fuel"] == 40,"Two level-four coal nuggets fill the forty-fuel furnace")
	check(game.cycle.furnace_fueled(),"The fuel lesson recognizes a furnace with at least twenty fuel")
	check(not furnace.receive(cell,"coal_4"),"A full furnace rejects more fuel")
	for batch in range(2):
		if batch > 0: furnace.receive(cell,"copper_4")
		furnace.process_smelting(1.0)
		check(furnace.machines[cell]["fuel"] == 20 * (1-batch) and furnace.machines[cell]["burning"],"Batch %d consumes exactly twenty fuel once at ignition" % batch)
		furnace.process_smelting(3.0)
		check(game.mining.nugget_type(output) == "copper_ingot" and furnace.machines[cell]["fuel"] == 20 * (1-batch),"Batch %d finishes without charging fuel a second time" % batch)
		game.mining.items_for("copper_ingot").erase(output)
	furnace.receive(cell,"copper_4")
	furnace.process_smelting(100)
	check(furnace.machines[cell]["fuel"] == 0 and furnace.machines[cell]["input"] == "copper_4" and game.mining.nuggets_at(output) == 0,"Forty fuel makes two ingots and cannot make a third")
	furnace.remove_material(cell,"copper_4")
	furnace.receive(cell,"iron_4")
	for fuel in [20,39]:
		furnace.machines[cell]["fuel"] = fuel
		furnace.process_smelting(100)
		check(furnace.machines[cell]["fuel"] == fuel and not furnace.machines[cell]["burning"] and furnace.machines[cell]["elapsed"] == 0 and furnace.machines[cell]["input"] == "iron_4","Iron cannot start or consume fuel with only %d fuel" % fuel)
	furnace.receive(cell,"coal")
	furnace.process_smelting(1)
	check(furnace.machines[cell]["fuel"] == 0 and furnace.machines[cell]["burning"] and furnace.machines[cell]["elapsed"] == 1,"Iron consumes exactly forty fuel once at ignition")
	furnace.process_smelting(3)
	check(game.mining.nugget_type(output) == "iron_ingot" and furnace.machines[cell]["input"] == "" and furnace.machines[cell]["fuel"] == 0,"One level-four iron nugget yields one level-one iron ingot")
	game.mining.items_for("iron_ingot").erase(output)
	furnace.receive(cell,"gold_4")
	furnace.receive(cell,"coal_4")
	furnace.process_smelting(4)
	check(game.mining.nugget_type(output) == "gold_ingot" and furnace.machines[cell]["fuel"] == 0,"Gold retains its existing twenty-fuel cost")
	game.queue_free()
	await process_frame
	print("RESULT: %d passed, %d failed; furnace fuel accounting" % [passed,failed])
	quit(1 if failed else 0)
