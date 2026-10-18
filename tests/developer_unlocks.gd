extends "res://tests/compactor.gd"

func run_checks() -> void:
	root.show()
	var args := OS.get_cmdline_user_args()
	game = load("res://main.tscn").instantiate()
	if "--legacy" in args: game.set_script(load(OS.get_environment("GODOT_LEGACY_MAIN")))
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	display.resolution = Vector2i(1280, 720)
	display.window_mode = 0
	display.apply_display(false)
	await settle()
	mover = game.get_node("WorldInteractions")
	compactors = game.get_node("Compactors")
	compactors.set_process(false)
	shop = game.shop
	game.cycle.day = 3
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	game.economy.add(-game.economy.coins)
	var player: RefCounted = game.progression
	shop.open_shop()
	await wait_shop()
	shop.open_category("HERRAMIENTAS")
	check(shop.item_buttons.is_empty() and player.visible_researches().is_empty(), "Normal level-one play hides unresearched tools and future research")
	game.economy.toggle_developer_mode()
	check(shop.item_buttons.keys() == ["drill", "compactor"] and shop.money_label.text == "∞ DEV", "Enabling DEV immediately refreshes the already open store")
	check(player.level == 1 and player.research_points == 0 and player.unlocked.is_empty() and player.visible_researches().size() == 6, "DEV exposes every research tier without changing real level, points, or unlocks")
	check(not player.is_item_unlocked("unknown") and not player.has_research("unknown"), "DEV still refuses unknown item and research identifiers")
	for category: String in shop.ITEM_CATEGORIES:
		shop.open_category(category)
		check(shop.item_buttons.keys() == shop.ITEM_CATEGORIES[category], "DEV reveals every item in " + category)
		for item in shop.item_buttons:
			check(not shop.item_buttons[item]["button"].disabled, "DEV makes " + item + " selectable with zero coins")
	shop.open_category("INVESTIGACIÓN")
	check(shop.research_buttons.size() == 6, "The DEV research menu shows all six unlocks")
	for id in shop.research_buttons:
		check(shop.research_buttons[id].disabled and player.has_research(id), "DEV research is already unlocked: " + id)
	game.research_technology("compactor")
	check(player.unlocked.is_empty() and player.research_points == 0, "DEV access never buys or permanently records free research")
	shop.close_shop()
	await wait_shop()
	await buy_from_shop()
	var cell := Vector2i(14, 1)
	await mouse_move(point(cell))
	await mouse_button(point(cell), true)
	await mouse_button(point(cell), false)
	check(compactors.machines.has(cell) and game.economy.coins == 0, "An unresearched level-three machine can actually be placed for free in DEV")
	compactors.buy()
	check(compactors.placing, "DEV can select another unresearched machine")
	await key(KEY_F10)
	check(not game.economy.developer_mode and not player.developer_mode and not compactors.placing, "F10 restores normal locks and cancels an unavailable pending preview")
	check(compactors.machines.has(cell) and not player.is_item_unlocked("compactor"), "Leaving DEV keeps placed constructions while restoring purchase locks")
	check(player.unlocked.is_empty() and player.visible_researches().is_empty() and player.research_points == 0, "Leaving DEV restores the untouched normal research state")
	player.add_experience(50)
	game.research_technology("drill")
	await key(KEY_F10)
	check(player.is_item_unlocked("compactor") and player.unlocked.keys() == ["drill"], "DEV access coexists with legitimate research")
	await key(KEY_F10)
	check(player.is_item_unlocked("drill") and not player.is_item_unlocked("compactor") and player.unlocked.keys() == ["drill"], "Real research survives switching DEV on and off")
	shop.open_shop()
	await wait_shop()
	shop.open_category("HERRAMIENTAS")
	check(shop.item_buttons.keys() == ["drill"], "The normal store shows only the legitimately unlocked tool again")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; developer unlocks")
	quit(1 if failed else 0)
