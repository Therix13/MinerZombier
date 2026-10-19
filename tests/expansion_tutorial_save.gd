extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	Engine.set_meta(&"mine_defense_skip_start_screen", true)
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
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var saves: Node = game.get_node("SaveGame")
	var legacy: Dictionary = saves.snapshot()
	legacy.erase("tutorial_revision")
	legacy["coins"] = 203
	legacy["cycle"]["brass_ingot_3_created"] = true
	legacy["progression"]["unlocked"]["expansion"] = true
	legacy["resources"]["brass_ingot_3"][Vector2i(14,1)] = 1
	for old_step: int in [11,12,13,14]:
		legacy["cycle"]["tutorial_step"] = old_step
		check(saves.restore_snapshot(legacy), "Legacy defense lesson %d loads" % old_step)
		check(game.cycle.tutorial_step == 11 and game.economy.coins == 203, "Unexpanded legacy games resume at expansion without losing gold")
		check(game.mining.items_for("brass_ingot_3").get(Vector2i(14,1)) == 1, "Migration preserves the crafted ingot")
	check(game.cycle.needs_tutorial_income() and "500" in game.cycle.tutorial_text(), "Migrated tutorial first asks for expansion funds")
	game.economy.coins = 500
	check(game.shop.tutorial_purchase().get("category") == "EXPANSION", "With enough gold the migrated tutorial points to expansion")
	var expanded := legacy.duplicate(true)
	expanded["grid"]["width"] = 7
	expanded["grid"]["height"] = 5
	expanded["cycle"]["tutorial_step"] = 11
	check(saves.restore_snapshot(expanded) and game.cycle.tutorial_step == 12, "Already expanded legacy games retain the defense lesson")
	legacy["cycle"]["tutorial_step"] = 15
	check(saves.restore_snapshot(legacy) and not game.cycle.is_tutorial_active(), "Completed legacy tutorials stay completed")
	var updated: Dictionary = saves.snapshot()
	updated["cycle"]["tutorial_step"] = 12
	check(updated["tutorial_revision"] == 2 and saves.restore_snapshot(updated) and game.cycle.tutorial_step == 12, "New saves keep their exact lesson on reload")
	updated["tutorial_revision"] = 999
	check(not saves.valid_snapshot(updated), "Unknown tutorial revisions are rejected")
	print("Expansion tutorial saves: %d passed, %d failed" % [passed,failed])
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
