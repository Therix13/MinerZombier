extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.zombie_manager.set_process(false)
	var progress: RefCounted = game.progression
	var weapons: RefCounted = game.launchers
	var saves: Node = game.get_node("SaveGame")
	var construction: Node = game.get_node("Construction")
	var notices: Array = []
	progress.items_unlocked.connect(func(items: Array[String]):
		if "launcher_2" in items: notices.append(items.duplicate())
	)
	var a := Vector2i(14,0)
	var b := Vector2i(15,0)
	check(not progress.is_item_unlocked("launcher_2"),"The upgrade begins locked")
	progress.record_resource("copper_ingot_3")
	game.shop.accept_unlock_notice()
	check(not progress.is_item_unlocked("launcher_2"),"Crafting copper does not replace the requested unlock conditions")
	check(weapons.place(a) and not progress.is_item_unlocked("launcher_2"),"One placed level-one launcher does not unlock level two")
	check(not weapons.place(a) and not progress.is_item_unlocked("launcher_2"),"A failed placement never counts as a second weapon")
	check(weapons.place(b) and progress.is_item_unlocked("launcher_2"),"Placing the second level-one launcher unlocks the upgrade immediately")
	check(notices.size() == 1 and game.shop.notice_item_ids.has("launcher_2"),"Two-weapon unlock produces exactly one notification")
	game.shop.accept_unlock_notice()
	var pair_save: Dictionary = saves.snapshot()
	weapons.launchers.erase(b)
	check(progress.is_item_unlocked("launcher_2"),"Removing one weapon never relocks a learned upgrade")
	check(saves.restore_snapshot(pair_save) and weapons.can_fuse(a,b),"The unlocked pair survives saving and remains fusible")
	check(weapons.fuse(a,b) and construction.plans.has(b),"The upgrade is still obtained by fusion into a blueprint")
	check(not weapons.launchers.has(b) and not construction.receive(b,"copper_3"),"Unlocking grants neither a free finished weapon nor a nugget recipe")
	check(construction.receive(b,"copper_ingot_3") and construction.receive(b,"copper_ingot") and weapons.level_at(b) == 2,"The existing two copper-ingot ingredients complete the unlocked upgrade")
	# Independently exercise the night threshold with no weapons placed.
	weapons.launchers.clear()
	progress.unlocked.erase("launcher_2")
	game.cycle.day = 1
	game.cycle.is_night = true
	game.on_wave_completed()
	check(game.cycle.day == 2 and not progress.is_item_unlocked("launcher_2"),"Surviving night one alone does not unlock level two")
	game.dismiss_night_victory_popup()
	game.camera_controller.stop_transition()
	game.cycle.is_night = true
	game.cycle.lose_night()
	check(not progress.is_item_unlocked("launcher_2"),"Losing night two does not award its unlock")
	game.cycle.defeated = false
	game.cycle.is_night = true
	game.on_wave_completed()
	check(game.cycle.day == 3 and progress.is_item_unlocked("launcher_2"),"Surviving night two unlocks the upgrade without placing a pair")
	check(saves.day_checkpoint["progression"]["unlocked"].has("launcher_2"),"The next dawn checkpoint includes the night-two reward")
	progress.record_night_completed(3)
	progress.record_night_completed(4)
	check(notices.size() == 2,"Later victories never repeat the same unlock notification")
	var completed: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(completed) and saves.restore_snapshot(completed) and progress.is_item_unlocked("launcher_2"),"Night-awarded upgrade is persisted with the normal progression state")
	var legacy: Dictionary = completed.duplicate(true)
	legacy["progression"]["unlocked"].erase("launcher_2")
	check(saves.restore_snapshot(legacy) and progress.is_item_unlocked("launcher_2"),"Older saves past night two automatically recognize the milestone")
	legacy = pair_save.duplicate(true)
	legacy["progression"]["unlocked"].erase("launcher_2")
	check(saves.restore_snapshot(legacy) and progress.is_item_unlocked("launcher_2"),"Older saves with two placed launchers also recognize the milestone")
	print("RESULT: %d passed, %d failed; launcher level-two unlock" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
