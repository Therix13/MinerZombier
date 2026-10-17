extends SceneTree

const ProgressionScript = preload("res://Scripts/progression_manager.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", description)
	else:
		failed += 1
		print("FAIL: ", description)

func check_level_rules() -> void:
	var player: RefCounted = ProgressionScript.new()
	var gained_levels: Array[int] = []
	player.connect("level_up", func(value: int) -> void: gained_levels.append(value))
	player.call("add_experience", -50)
	player.call("add_experience", 0)
	player.call("award_sale", "unknown")
	check(player.get("total_experience") == 0, "Invalid rewards do not grant or remove EXP")
	player.call("add_experience", 24)
	check(player.get("level") == 1 and player.get("research_points") == 0, "No early level or research point before threshold")
	player.call("add_experience", 96)
	check(player.get("level") == 4 and player.get("experience") == 0 and player.get("research_points") == 3, "Large reward grants all three levels and their points")
	check(gained_levels == [2, 3, 4], "One level-up event is sent for each earned level")
	check(not player.call("research", "unknown"), "Unknown technology cannot spend points")
	check(not player.call("research", "mining_ii"), "Advanced technology requires its prerequisite")
	check(player.call("research", "mining_i") and player.get("research_points") == 2, "First technology spends exactly one research point")
	check(not player.call("research", "mining_i") and player.get("research_points") == 2, "Repeat research does not spend points twice")
	check(player.call("research", "mining_ii") and player.get("research_points") == 0, "Advanced technology spends two points after prerequisite")
	check(not player.call("research", "logistics_i"), "Research is refused when points are exhausted")

func mine_once(mining: RefCounted, cell: Vector2i, actions: int) -> void:
	for i in range(actions):
		mining.call("mine", cell)

func buy_from_panel(shop: Control, technology_id: String) -> void:
	var button: Button = shop.get("research_buttons")[technology_id]
	button.pressed.emit()

func run_checks() -> void:
	check_level_rules()
	root.size = Vector2i(1152, 648)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_name: String = args[0] if not args.is_empty() else "main.tscn"
	var scene: PackedScene = load("res://" + scene_name)
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var mining: RefCounted = game.get("mining")
	var conveyors: RefCounted = game.get("conveyors")
	var drills: RefCounted = game.get("drills")
	var launchers: RefCounted = game.get("launchers")
	var player: RefCounted = game.get("progression")
	var cycle: RefCounted = game.get("cycle")
	var grid: RefCounted = game.get("grid")
	var manager: Node = game.get("zombie_manager")
	var shop: Control = game.get("shop")
	manager.set_process(false)
	await process_frame
	var hud_rect: Rect2 = shop.get("progression_panel").get_global_rect()
	check(hud_rect.end.x <= root.size.x and hud_rect.end.y <= root.size.y, "Progression HUD fits the standard window")
	check(not hud_rect.intersects(shop.get_node("CyclePanel").get_global_rect()), "Progression HUD does not overlap tutorial controls")
	root.size = Vector2i(800, 600)
	await process_frame
	await process_frame
	hud_rect = shop.get("progression_panel").get_global_rect()
	check(hud_rect.end.x <= root.size.x and hud_rect.end.y <= root.size.y, "Progression HUD also fits a smaller 800x600 window")
	check(player.get("level") == 1 and player.get("research_points") == 0, "Game starts at level one without research points")
	game.call("research_technology", "mining_i")
	check(not player.call("has_technology", "mining_i"), "Research respects minimum level even through controller")
	mining.call("place_vein", Vector2i(15, 1), 0)
	mine_once(mining, Vector2i(15, 1), 7)
	check(player.get("total_experience") == 0, "Mining alone does not duplicate the sale reward")
	mining.call("move_nugget", Vector2i(15, 0), grid.get("sale_cell"))
	check(player.get("total_experience") == 2, "Manual coal sale grants two EXP")
	conveyors.call("place", Vector2i(15, 0), 0)
	mine_once(mining, Vector2i(15, 1), 7)
	conveyors.call("advance", 4.0)
	check(player.get("total_experience") == 4, "Automatic coal sale grants the same EXP")
	mining.call("place_vein", Vector2i(14, 1), 0, "brass")
	mine_once(mining, Vector2i(14, 1), 7)
	mining.call("move_nugget", Vector2i(14, 0), grid.get("sale_cell"))
	check(player.get("total_experience") == 7, "Brass sale grants three EXP")
	manager.call("start_wave", 1)
	var enemy: Node2D = get_nodes_in_group("zombies")[0] as Node2D
	enemy.call("take_damage", 0.25)
	check(player.get("total_experience") == 7, "Nonlethal damage gives no kill reward")
	enemy.call("take_damage", 100.0)
	check(player.get("total_experience") == 17, "A zombie kill grants ten EXP")
	enemy.call("take_damage", 100.0)
	check(player.get("total_experience") == 17, "Repeated hits on a defeated zombie do not duplicate EXP")
	manager.call("spawn_zombie")
	enemy = get_nodes_in_group("zombies")[0] as Node2D
	enemy.call("take_damage", 100.0)
	check(player.get("level") == 2 and player.get("experience") == 2 and player.get("research_points") == 1, "Real sales and kills level up with leftover EXP and one research point")
	manager.call("_process", 0.01)
	manager.call("start_wave", 1)
	get_nodes_in_group("zombies")[0].queue_free()
	await process_frame
	await process_frame
	check(player.get("total_experience") == 27, "Removing an enemy without a kill grants no EXP")
	check(shop.get("level_label").text.contains("NIVEL 2") and shop.get("experience_bar").value == 2, "HUD shows current level and remaining EXP")
	shop.get("shop_button").pressed.emit()
	await create_timer(0.4).timeout
	for category_button in shop.get("shop_content").get_children():
		if category_button is Button and category_button.text.begins_with("TECNOLOGÍAS"):
			category_button.pressed.emit()
			break
	await process_frame
	await process_frame
	check(shop.get("shop_open") and shop.get("shop_title").text == "TECNOLOGÍAS", "Shop category opens research through its remaining UI entry point")
	check(shop.get("research_buttons").size() == 6, "Research panel offers all six technologies")
	check(not shop.get("progression_panel").visible, "HUD hides while shop is open so it cannot cover research controls")
	var scroll: ScrollContainer = shop.get("shop_scroll")
	var last_button: Button = shop.get("research_buttons")["defense_ii"]
	scroll.ensure_control_visible(last_button)
	await process_frame
	await process_frame
	var last_rect: Rect2 = last_button.get_global_rect()
	var scroll_rect: Rect2 = scroll.get_global_rect()
	check(scroll.size.y > 0 and last_rect.position.y >= scroll_rect.position.y - 1.0 and last_rect.end.y <= scroll_rect.end.y + 1.0, "Research scroll makes the last technology reachable in a smaller window")
	scroll.scroll_vertical = 0
	check(not shop.get("research_buttons")["mining_i"].disabled and shop.get("research_buttons")["mining_ii"].disabled, "Panel shows affordable research and locks advanced research")
	buy_from_panel(shop, "mining_i")
	check(player.call("has_technology", "mining_i") and player.get("research_points") == 0, "Research button unlocks technology and spends points")
	check(shop.get("research_buttons")["mining_i"].text == "INVESTIGADA" and shop.get("research_buttons")["mining_i"].disabled, "Researched button becomes disabled and marked as researched")
	check(shop.get("research_summary").text.contains("0 PI"), "Research summary refreshes after purchase")
	buy_from_panel(shop, "mining_i")
	check(player.get("research_points") == 0, "Duplicate button events cannot spend points twice")
	mine_once(mining, Vector2i(15, 1), 4)
	check(mining.call("nuggets_at", Vector2i(15, 0)) == 0, "Mining upgrade does not produce ore before five actions")
	mine_once(mining, Vector2i(15, 1), 1)
	check(mining.call("nuggets_at", Vector2i(15, 0)) == 1, "Mining upgrade produces ore after five actions on an existing vein")
	var original_button_id: int = shop.get("research_buttons")["mining_i"].get_instance_id()
	player.call("add_experience", 40)
	check(shop.get("research_buttons")["mining_i"].get_instance_id() == original_button_id, "Live EXP updates preserve research controls instead of rebuilding the page")
	player.call("add_experience", 55)
	buy_from_panel(shop, "mining_ii")
	check(player.call("has_technology", "mining_ii") and player.get("research_points") == 0, "Level four and prerequisite unlock advanced mining")
	player.call("add_experience", 1000)
	var prior_points: int = player.get("research_points")
	buy_from_panel(shop, "logistics_ii")
	check(not player.call("has_technology", "logistics_ii") and player.get("research_points") == prior_points, "Synthetic button event cannot bypass a prerequisite")
	buy_from_panel(shop, "logistics_i")
	check(is_equal_approx(conveyors.get("move_interval"), 3.0), "First logistics technology speeds up existing conveyors")
	buy_from_panel(shop, "logistics_ii")
	conveyors.set("accumulator", 0.0)
	conveyors.call("advance", 1.5)
	check(mining.call("nuggets_at", Vector2i(15, 0)) == 1, "Improved conveyor waits until its new movement interval")
	var experience_before_sale: int = player.get("total_experience")
	conveyors.call("advance", 0.5)
	check(mining.call("nuggets_at", Vector2i(15, 0)) == 0 and player.get("total_experience") == experience_before_sale + 2, "Advanced conveyor sells after two seconds and awards EXP once")
	check(shop.get("research_buttons")["mining_i"].get_instance_id() == original_button_id, "Sales do not replace research controls or reset the page")
	drills.call("place", Vector2i(15, 2), 0)
	drills.call("advance", 0.3)
	check(mining.get("coal_veins")[Vector2i(15, 1)]["progress"] == 1, "Advanced drill works after 0.3 seconds")
	grid.call("purchase_defense_platforms")
	var defense_cell: Vector2i = grid.call("defense_cell", "left")
	launchers.call("place", defense_cell)
	launchers.call("receive", defense_cell, "coal")
	manager.call("spawn_zombie")
	enemy = get_nodes_in_group("zombies")[0] as Node2D
	var rect: Rect2 = grid.call("get_cell_rect", defense_cell)
	enemy.call("setup", rect.get_center() + Vector2(0, -50), Vector2.ZERO, 10.0)
	enemy.set_process(false)
	buy_from_panel(shop, "defense_i")
	launchers.call("advance", 0.0)
	check(is_equal_approx(enemy.get("health"), 9.25), "Defense research increases actual coal-shot damage to 0.75")
	prior_points = player.get("research_points")
	cycle.set("is_night", true)
	cycle.emit_signal("changed")
	check(shop.get("research_buttons")["defense_ii"].disabled, "Research buttons disable during the night")
	game.call("research_technology", "defense_ii")
	check(not player.call("has_technology", "defense_ii") and player.get("research_points") == prior_points, "Controller refuses research during the night without spending points")
	cycle.set("is_night", false)
	cycle.emit_signal("changed")
	game.get("night_victory_overlay").show()
	game.call("research_technology", "defense_ii")
	check(not player.call("has_technology", "defense_ii"), "Research cannot bypass the victory overlay")
	game.get("night_victory_overlay").hide()
	cycle.set("defeated", true)
	game.call("research_technology", "defense_ii")
	check(not player.call("has_technology", "defense_ii"), "Research is blocked after defeat")
	cycle.set("defeated", false)
	cycle.emit_signal("changed")
	for i in range(5):
		launchers.call("receive", defense_cell, "coal")
	check(not launchers.call("receive", defense_cell, "coal"), "Original launcher capacity is five rounds")
	buy_from_panel(shop, "defense_ii")
	for i in range(3):
		check(launchers.call("receive", defense_cell, "coal"), "Expanded existing launcher accepts extra round %d" % (i + 1))
	check(not launchers.call("receive", defense_cell, "coal"), "Expanded magazine stops at eight rounds")
	check(is_equal_approx(launchers.get("launchers")[defense_cell]["cooldown"], 3.0), "Research shortens current launcher cooldown")
	launchers.call("advance", 3.0)
	check(is_equal_approx(enemy.get("health"), 8.5), "Expanded launcher fires its next shot after three seconds")
	var saved_level: int = player.get("level")
	var saved_experience: int = player.get("total_experience")
	cycle.set("is_night", true)
	cycle.call("complete_night")
	check(player.get("level") == saved_level and player.get("unlocked").size() == 6, "Levels and all six technologies survive the change of day")
	check(player.get("total_experience") == saved_experience, "Night coin reward does not masquerade as a mineral sale")
	print("RESULT: ", passed, " passed; ", failed, " failed; progression=", scene_name)
	quit(1 if failed > 0 else 0)
