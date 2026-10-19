extends "res://tests/interactions.gd"

func run_checks() -> void:
	var args := OS.get_cmdline_user_args()
	game = load("res://main.tscn").instantiate()
	if "--legacy" in args: game.set_script(load(OS.get_environment("GODOT_LEGACY_MAIN")))
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var manager: Node2D = game.zombie_manager
	manager.set_process(false)
	var shop: Control = game.shop
	var player: RefCounted = game.progression
	game.grid.purchase_defense_platforms()
	var platform: Vector2i = game.grid.defense_cell("left")
	game.launchers.place(platform)
	game.launchers.receive(platform, "coal")
	game.cycle.tutorial_step = game.cycle.TUTORIAL_LAST_STEP
	game.cycle.barrier_broken = true
	game.start_night()
	game.mining.items_for("coal_3")[Vector2i(14,1)] = 1
	game.mining.items_for("coal_3")[Vector2i(15,1)] = 1
	game.mining.fuse(Vector2i(14,1),Vector2i(15,1))
	get_nodes_in_group("zombies")[0].take_damage(100)
	await settle()
	check(player.is_item_unlocked("furnace") and not shop.notice_item_ids.is_empty() and not shop.unlock_notice.visible and not shop.unlock_notice_backdrop.visible, "Crafting during combat queues the automatic unlock without showing or timing its alert")
	manager._process(2.0)
	check(game.cycle.is_night and manager.active_wave and manager.cleared_time == 0, "An empty battlefield does not end the night while more zombies are due")
	manager.spawn_zombie()
	get_nodes_in_group("zombies")[0].take_damage(100)
	var coins: int = game.economy.coins
	manager._process(1.0)
	check(game.cycle.is_night and game.cycle.day == 1 and not game.night_victory_overlay.visible and game.economy.coins == coins, "The final kill leaves night active without granting early victory rewards")
	var extra: Node2D = manager.ZombieScript.new()
	extra.setup(Vector2.ZERO, Vector2.ZERO, 1)
	manager.add_child(extra)
	extra.set_process(false)
	manager._process(0.5)
	check(manager.cleared_time == 0 and game.cycle.is_night, "A new living enemy resets the victory countdown")
	extra.take_damage(100)
	manager._process(2.99)
	await settle()
	check(game.cycle.is_night and not shop.unlock_notice.visible and not game.night_victory_overlay.visible, "Unlock alerts and victory remain deferred throughout the full three-second delay")
	manager._process(0.01)
	await settle()
	check(game.cycle.day == 2 and not game.cycle.is_night and game.night_victory_overlay.visible and game.economy.coins == coins, "Exactly three clear seconds end the wave and display its victory without adding gold")
	check(not shop.unlock_notice.visible and not shop.notice_item_ids.is_empty(), "Queued unlocks waits behind the victory screen")
	var rewarded: int = game.economy.coins
	manager._process(3.0)
	check(game.economy.coins == rewarded and game.cycle.day == 2, "Repeated updates cannot repeat night rewards")
	game.dismiss_night_victory_popup()
	await settle()
	check(shop.unlock_notice.visible and shop.unlock_notice_backdrop.visible and shop.unlock_notice_accept.visible, "After victory, queued unlocks displays until acknowledged with Aceptar")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; wave end")
	quit(1 if failed else 0)
