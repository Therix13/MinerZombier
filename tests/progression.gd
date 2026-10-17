extends SceneTree

const ProgressionScript = preload("res://Scripts/progression_manager.gd")
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

func settle() -> void:
	await process_frame
	await process_frame

func check_level_rules() -> void:
	var player: RefCounted = ProgressionScript.new()
	var levels: Array[int] = []
	player.level_up.connect(func(value: int) -> void: levels.append(value))
	player.add_experience(-50)
	player.award_sale("unknown")
	check(player.total_experience == 0, "Invalid rewards do not change EXP")
	player.add_experience(24)
	check(player.level == 1 and player.research_points == 0, "No early level or research point")
	check(not player.research("drill"), "Minimum level is required for research")
	player.add_experience(96)
	check(player.level == 4 and player.experience == 0 and player.research_points == 3 and levels == [2, 3, 4], "Large rewards grant each level and its research point")
	check(not player.research("unknown") and not player.research("mining_i"), "Unknown and removed global technologies spend no points")
	check(not player.research("junction_belt"), "Unlocks require their prerequisite")
	check(player.research("curved_belts") and player.research_points == 2, "A new item unlock spends its research cost")
	check(not player.research("curved_belts") and player.research_points == 2, "Duplicate research is refused")
	check(player.is_item_unlocked("corner_right") and player.is_item_unlocked("corner_left"), "One curved-belt research unlocks both directions")
	check(player.research("junction_belt") and player.research_points == 0 and player.is_item_unlocked("junction"), "Advanced unlock costs two points and unlocks the T belt")
	check(not player.research("drill") and not player.is_item_unlocked("drill"), "Insufficient points leave an item locked")
	check(player.is_item_unlocked("coal") and player.is_item_unlocked("straight") and player.is_item_unlocked("launcher") and not player.is_item_unlocked("unknown"), "Tutorial items stay available and unknown items stay locked")

func run_checks() -> void:
	check_level_rules()
	root.size = Vector2i(1280, 720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_name: String = args[0] if not args.is_empty() else "main.tscn"
	var game: Node2D = load("res://" + scene_name).instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	var cycle: RefCounted = game.cycle
	cycle.day = 2
	cycle.changed.emit()
	var mining: RefCounted = game.mining
	var belts: RefCounted = game.conveyors
	var player: RefCounted = game.progression
	var shop: Control = game.shop
	var manager: Node2D = game.zombie_manager
	manager.set_process(false)
	var coins: int = game.economy.coins
	game.buy_drill()
	game.buy_brass_vein()
	game.buy_corner_conveyor()
	game.buy_left_corner_conveyor()
	game.buy_junction_conveyor()
	check(game.economy.coins == coins and not game.placing_drill and not game.placing_brass and not game.placing_belt, "Controller refuses all locked purchases without spending coins")
	mining.place_vein(Vector2i(15, 1), 0)
	for index in range(7): mining.mine(Vector2i(15, 1))
	check(player.total_experience == 0, "Mining alone does not duplicate sale EXP")
	mining.move_nugget(Vector2i(15, 0), game.grid.sale_cell)
	check(player.total_experience == 2, "Manual coal sale awards EXP")
	belts.place(Vector2i(15, 0), 0)
	for index in range(7): mining.mine(Vector2i(15, 1))
	belts.advance(4.0)
	check(player.total_experience == 4, "Conveyor sale awards the same EXP")
	mining.place_vein(Vector2i(14, 1), 0, "brass")
	for index in range(7): mining.mine(Vector2i(14, 1))
	mining.move_nugget(Vector2i(14, 0), game.grid.sale_cell)
	check(player.total_experience == 7, "Brass sales retain their EXP reward")
	manager.start_wave(1)
	var enemy: Node = get_nodes_in_group("zombies")[0]
	enemy.take_damage(0.25)
	check(player.total_experience == 7, "Nonlethal hits do not award kill EXP")
	enemy.take_damage(100.0)
	enemy.take_damage(100.0)
	check(player.total_experience == 17, "A kill awards EXP exactly once")
	manager.spawn_zombie()
	get_nodes_in_group("zombies")[0].take_damage(100.0)
	check(player.level == 2 and player.experience == 2 and player.research_points == 1, "Sales and kills level up and award research points")
	manager._process(0.01)
	check(shop.level_label.text.contains("NIVEL 2") and shop.experience_bar.value == 2, "Subtle XP HUD shows the new level")
	shop.open_shop()
	await create_timer(0.4).timeout
	shop.open_category("BASE")
	check(not shop.item_buttons["coal"]["button"].disabled and not shop.item_buttons["straight"]["button"].disabled, "Basic store items need no research")
	check(shop.item_buttons["drill"]["button"].disabled and shop.item_buttons["brass"]["button"].disabled and shop.item_buttons["corner_left"]["button"].disabled and shop.item_buttons["junction"]["button"].disabled, "The store visibly locks items behind research")
	var locked_coins: int = game.economy.coins
	shop.item_buttons["drill"]["button"].pressed.emit()
	check(not game.placing_drill and game.economy.coins == locked_coins, "Synthetic locked-button events cannot buy a locked item")
	shop.open_category("INVESTIGACIÓN")
	await settle()
	check(shop.shop_title.text == "INVESTIGACIÓN" and shop.research_buttons.size() == 4, "Research category contains four item unlocks")
	check(not shop.progression_panel.visible, "The XP HUD stays hidden while the shop is open")
	var before_coins: int = game.economy.coins
	shop.research_buttons["drill"].pressed.emit()
	check(player.has_research("drill") and player.research_points == 0 and player.is_item_unlocked("drill"), "Research button permanently unlocks a new store item")
	check(game.economy.coins == before_coins, "Research spends points, not construction coins")
	check(shop.research_buttons["drill"].disabled and shop.research_buttons["drill"].tooltip_text.contains("Desbloqueado"), "Unlocked cards show their completed state")
	check(mining.mining_clicks == 7 and game.drills.drill_interval == 0.6 and belts.move_interval == 4.0 and game.launchers.damage_multiplier == 0.5, "Research does not change global construction statistics")
	var button_id: int = shop.research_buttons["drill"].get_instance_id()
	player.add_experience(40)
	game.economy.add(1)
	check(shop.research_buttons["drill"].get_instance_id() == button_id, "EXP and coin changes preserve research controls")
	shop.research_buttons["brass"].pressed.emit()
	check(player.has_research("brass") and player.research_points == 0, "The next level and prerequisite unlock the new mineral")
	shop.open_category("BASE")
	check(not shop.item_buttons["drill"]["button"].disabled and not shop.item_buttons["brass"]["button"].disabled, "Unlocked items become purchasable without reopening the game")
	shop.item_buttons["drill"]["button"].pressed.emit()
	check(game.placing_drill and game.economy.coins == before_coins + 1 - 200, "An unlocked store item still costs its normal coins")
	game.cancel_placement()
	await create_timer(0.4).timeout
	shop.open_shop()
	await create_timer(0.4).timeout
	shop.open_category("INVESTIGACIÓN")
	player.add_experience(1000)
	var points: int = player.research_points
	shop.research_buttons["junction_belt"].pressed.emit()
	check(not player.has_research("junction_belt") and player.research_points == points, "Button events cannot bypass item prerequisites")
	cycle.is_night = true
	cycle.changed.emit()
	game.research_technology("curved_belts")
	check(shop.research_buttons["curved_belts"].disabled and not player.has_research("curved_belts") and player.research_points == points, "Research is blocked during combat")
	cycle.is_night = false
	game.night_victory_overlay.show()
	game.research_technology("curved_belts")
	check(not player.has_research("curved_belts"), "Victory overlays cannot be bypassed by research")
	game.night_victory_overlay.hide()
	cycle.defeated = true
	game.research_technology("curved_belts")
	check(not player.has_research("curved_belts"), "Defeat blocks research")
	cycle.defeated = false
	cycle.changed.emit()
	shop.research_buttons["curved_belts"].pressed.emit()
	shop.research_buttons["junction_belt"].pressed.emit()
	check(player.unlocked.size() == 4 and player.is_item_unlocked("junction"), "All four researches unlock only their intended items")
	var level: int = player.level
	var experience: int = player.total_experience
	cycle.is_night = true
	cycle.complete_night()
	check(player.level == level and player.total_experience == experience and player.unlocked.size() == 4, "Unlocks and EXP survive a day change without a fake sale reward")
	root.size = Vector2i(800, 600)
	await settle()
	var scroll: ScrollContainer = shop.shop_scroll
	scroll.ensure_control_visible(shop.research_buttons["junction_belt"])
	await settle()
	var last: Rect2 = shop.research_buttons["junction_belt"].get_global_rect()
	var visible: Rect2 = scroll.get_global_rect()
	check(last.position.y >= visible.position.y - 1 and last.end.y <= visible.end.y + 1, "Last research remains reachable in a smaller window")
	game.queue_free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; progression=", scene_name)
	quit(1 if failed > 0 else 0)
