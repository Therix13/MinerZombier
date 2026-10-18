extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	Engine.set_meta(&"mine_defense_intro_seen", true)
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", description)
	else:
		failed += 1
		print("FAIL: ", description)

func run_checks() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_name: String = args[0] if not args.is_empty() else "main.tscn"
	var scene: PackedScene = load("res://" + scene_name)
	if scene == null:
		check(false, "Scene loads")
		quit(1)
		return
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	check(game.get("cycle") != null and game.get("shop") != null, "Game and shop initialize")
	if game.get("cycle") == null:
		quit(1)
		return
	var grid: RefCounted = game.get("grid")
	var mining: RefCounted = game.get("mining")
	var conveyors: RefCounted = game.get("conveyors")
	var economy: RefCounted = game.get("economy")
	var drills: RefCounted = game.get("drills")
	var launchers: RefCounted = game.get("launchers")
	var cycle: RefCounted = game.get("cycle")
	check(economy.get("coins") == 500 and grid.get("owned_tiles").size() == 9, "Initial economy and 3x3 base")
	check(mining.call("place_vein", Vector2i(14, 0), 1), "Place coal vein in owned cell")
	for i in range(5):
		mining.call("mine", Vector2i(14, 0))
	check(mining.call("nuggets_at", Vector2i(15, 0)) == 1, "Five mining actions produce coal")
	mining.call("move_nugget", Vector2i(15, 0), grid.get("sale_cell"))
	check(economy.get("coins") == 505 and cycle.get("coal_sold") == 1 and cycle.get("tutorial_step") == 1, "The first manual sale pays without granting the five-sale bonus")
	for sale in range(4):
		for i in range(5): mining.call("mine", Vector2i(14, 0))
		mining.call("move_nugget", Vector2i(15, 0), grid.get("sale_cell"))
	check(economy.get("coins") == 525 and cycle.get("coal_sold") == 5 and cycle.get("tutorial_step") == 2, "Five manual sales pay only their sale prices")
	for nugget in range(2):
		for click in range(5): mining.mine(cycle.TUTORIAL_COAL_CELL)
		mining.move_nugget(cycle.TUTORIAL_ORE_CELL, cycle.TUTORIAL_FUSION_CELL)
	mining.move_nugget(cycle.TUTORIAL_FUSION_CELL, grid.sale_cell)
	check(cycle.fusion_sold and economy.coins == 540, "Fusion follows the five sales and pays only for its sold product")
	game.call("buy_expansion")
	check(grid.get("cave_width") == 7 and grid.get("cave_height") == 5 and economy.get("coins") == 40, "Purchase expands base to 7x5")
	check(conveyors.call("place", Vector2i(15, 0), 0), "Place conveyor toward sale point")
	mining.call("move_vein", Vector2i(14, 0), Vector2i(15, 1), 0)
	check(drills.call("place", Vector2i(15, 2), 0), "Place drill facing vein")
	for i in range(5):
		drills.call("tick")
	check(mining.call("nuggets_at", Vector2i(15, 0)) == 1, "Drill produces coal onto conveyor")
	conveyors.call("tick")
	check(economy.get("coins") == 45 and mining.call("nuggets_at", Vector2i(15, 0)) == 0, "Conveyor sells coal and pays economy")
	check(cycle.get("coal_sold") == 6, "Conveyor coal sale also updates sale count")
	grid.call("purchase_defense_platforms")
	cycle.call("refresh_tutorial")
	var defense_cell: Vector2i = grid.call("defense_cell", "left")
	check(launchers.call("place", defense_cell), "Place launcher on defense platform")
	for i in range(4):
		launchers.call("receive", defense_cell, "coal")
	check(cycle.call("can_start_night"), "Tutorial and ammunition unlock first night")
	game.call("start_night")
	var zombies: Array[Node] = get_nodes_in_group("zombies")
	check(cycle.get("is_night") and zombies.size() == 1, "Night starts and first zombie spawns")
	if not zombies.is_empty():
		var zombie: Node2D = zombies[0] as Node2D
		var prior_health: float = zombie.get("health")
		var rect: Rect2 = grid.call("get_cell_rect", defense_cell)
		zombie.position = rect.get_center() + Vector2(0, -50)
		launchers.call("advance", 0.01)
		check(zombie.get("health") < prior_health, "Loaded launcher damages zombie in range")
	var manager: Node = game.get("zombie_manager")
	manager.set_process(false)
	manager.call("spawn_zombie")
	for zombie in get_nodes_in_group("zombies"):
		zombie.call("take_damage", 100.0)
	manager.call("_process", 3.0)
	check(cycle.get("day") == 2 and not cycle.get("is_night"), "Cleared wave advances to day 2")
	var popup: Control = game.get("night_victory_overlay")
	check(popup != null, "Both scenes use the shared controller with victory popup")
	if popup != null:
		check(popup.visible and game.get("night_victory_title").text == "Noche 1: Superada", "External main script shows night victory popup")
		game.call("dismiss_night_victory_popup")
		check(not popup.visible, "Continue dismisses victory popup")
	var target: Vector2i = Vector2i(0, 0)
	check(not grid.get("owned_tiles").has(target), "Movement check targets an unpurchased cell")
	mining.call("move_vein", Vector2i(15, 1), target, 1)
	check(mining.call("vein_at", target) == "", "Dragging vein respects purchased base boundaries")
	check(mining.call("vein_at", Vector2i(15, 1)) == "coal", "Rejected vein move preserves source")
	check(not conveyors.call("move", Vector2i(15, 0), target, 1), "Dragging conveyor rejects unpurchased terrain")
	check(conveyors.get("belts").has(Vector2i(15, 0)), "Rejected conveyor move preserves source")
	check(not drills.call("move", Vector2i(15, 2), target, 1), "Dragging drill rejects unpurchased terrain")
	check(drills.get("drills").has(Vector2i(15, 2)), "Rejected drill move preserves source")
	mining.call("mine", Vector2i(15, 1))
	for i in range(6):
		mining.call("mine", Vector2i(15, 1))
	mining.call("move_nugget", Vector2i(15, 0), target)
	check(mining.call("nuggets_at", target) == 0 and mining.call("nuggets_at", Vector2i(15, 0)) == 1, "Dragging ore rejects unpurchased terrain without losing ore")
	var ammo_cell: Vector2i = defense_cell + Vector2i(0, 1)
	mining.call("move_nugget", Vector2i(15, 0), ammo_cell)
	check(mining.call("nuggets_at", ammo_cell) == 1, "Ore can still move onto purchased ammunition connections")
	check(conveyors.call("place", defense_cell + Vector2i(0, 2), 0), "Conveyors can still use purchased ammunition connections")
	check(conveyors.call("move", Vector2i(15, 0), Vector2i(15, 0), 1), "Conveyor can rotate in its own cell")
	check(drills.call("move", Vector2i(15, 2), Vector2i(15, 2), 1), "Drill can rotate in its own cell")
	mining.call("move_vein", Vector2i(15, 1), Vector2i(15, 1), 1)
	check(mining.get("coal_veins")[Vector2i(15, 1)]["direction"] == 1, "Vein can rotate in its own cell")
	print("RESULT: ", passed, " passed; ", failed, " failed; scene=", scene_name)
	quit(1 if failed > 0 else 0)
