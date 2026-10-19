extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	mover = game.get_node("WorldInteractions")
	var cycle: RefCounted = game.cycle
	var mining: RefCounted = game.mining
	clear_items()
	var source := Vector2i(15,0)
	mining.place_vein(Vector2i(14,0),1,"coal")
	mining.coal_veins[Vector2i(14,0)]["level"] = 2
	mining.items_for("coal")[source] = 1
	mining.items_for("coal_2")[Vector2i(14,1)] = 1
	mining.items_for("coal_3")[Vector2i(15,1)] = 1
	cycle.coal_cell = Vector2i(14,0)
	cycle.tutorial_step = 3
	check(cycle.income_targets() == [source,Vector2i(16,0)],"Income arrow points to the adjacent free space rather than the distant preset")
	check(cycle.park_resource(source) == [source,Vector2i(16,0)],"Workshop arrows also choose the nearest free cell")
	mining.items_for("iron")[Vector2i(16,0)] = 1
	var next: Vector2i = cycle.nearest_resource_space(source)
	check(next == Vector2i(16,1),"Arrow recalculates the next closest free space when the adjacent cell fills")
	for cell: Vector2i in game.grid.owned_tiles:
		if game.grid.is_valid_cell(cell) and mining.can_move_nugget(cell): mining.items_for("gold")[cell] = 1
	check(cycle.income_targets() == [source,game.grid.sale_cell],"A full base still suggests selling to free space")
	print("RESULT: %d passed, %d failed; nearest tutorial space" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
