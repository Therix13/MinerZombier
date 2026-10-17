extends SceneTree

const MANAGER_NAMES := [
	"grid", "economy", "camera_controller", "mining",
	"conveyors", "drills", "launchers", "cycle", "progression",
]

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

func manager_refs(game: Node) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for name in MANAGER_NAMES:
		refs.append(weakref(game.get(name)))
	return refs

func check_released(refs: Array[WeakRef], description: String) -> void:
	for i in range(refs.size()):
		check(refs[i].get_ref() == null, description + ": " + MANAGER_NAMES[i])

func check_first_automated_sale(game: Node) -> void:
	var mining: RefCounted = game.get("mining")
	var conveyors: RefCounted = game.get("conveyors")
	var economy: RefCounted = game.get("economy")
	var cycle: RefCounted = game.get("cycle")
	check(mining.call("place_vein", Vector2i(15, 1), 0), "Fresh game places coal vein toward sale conveyor")
	check(conveyors.call("place", Vector2i(15, 0), 0), "Fresh game places sale conveyor")
	for i in range(7):
		mining.call("mine", Vector2i(15, 1))
	conveyors.call("tick")
	check(cycle.get("coal_sold") == 1 and cycle.get("tutorial_step") == 2, "First sale by conveyor advances tutorial without manual sale")
	check(economy.get("coins") == 1005, "First automated sale pays once and grants expansion bonus once")
	conveyors.call("tick")
	check(economy.get("coins") == 1005 and cycle.get("coal_sold") == 1, "Empty conveyor does not duplicate sale or tutorial reward")

func run_checks() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_name: String = args[0] if not args.is_empty() else "main.tscn"
	var scene: PackedScene = load("res://" + scene_name)
	var game: Node = scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check_first_automated_sale(game)
	for iteration in range(3):
		game.get("cycle").day = 2
		game.get("progression").add_experience(120)
		game.call("research_technology", "mining_i")
		game.call("research_technology", "mining_ii")
		var refs: Array[WeakRef] = manager_refs(game)
		game.call("restart_game")
		await scene_changed
		game = current_scene
		check_released(refs, "Restart %d frees previous manager" % (iteration + 1))
		check(game.get("economy").coins == 500 and game.get("cycle").day == 1, "Restart %d resets coins and day" % (iteration + 1))
		check(game.get("mining").coal_veins.is_empty() and game.get("conveyors").belts.is_empty(), "Restart %d resets placed objects" % (iteration + 1))
		check(game.get("progression").level == 1 and game.get("progression").experience == 0 and game.get("progression").total_experience == 0 and game.get("progression").research_points == 0 and game.get("progression").unlocked.is_empty(), "Restart %d resets progression for the new game" % (iteration + 1))
		check(game.get("mining").mining_clicks == 7 and is_equal_approx(game.get("drills").drill_interval, 0.6), "Restart %d resets technology effects" % (iteration + 1))
	# Close while a night is active, with enemies and their signal callbacks.
	game.get("grid").purchase_defense_platforms()
	var defense_cell: Vector2i = game.get("grid").defense_cell("left")
	game.get("launchers").place(defense_cell)
	game.get("launchers").receive(defense_cell, "coal")
	game.get("cycle").tutorial_step = 7
	game.call("start_night")
	check(not get_nodes_in_group("zombies").is_empty(), "Shutdown scenario has an active enemy")
	var final_refs: Array[WeakRef] = manager_refs(game)
	game.queue_free()
	await process_frame
	await process_frame
	check_released(final_refs, "Scene shutdown frees manager")
	check(get_nodes_in_group("zombies").is_empty(), "Scene shutdown removes active enemies")
	print("RESULT: ", passed, " passed; ", failed, " failed; lifecycle=", scene_name)
	quit(1 if failed > 0 else 0)
