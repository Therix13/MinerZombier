extends "res://tests/interactions.gd"

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	var saves: Node = game.get_node("SaveGame")
	game.economy.coins = 765
	game.display_settings.open_menu()
	check(game.display_settings.quit_button.pressed.is_connected(game.display_settings.quit_game),"The single Save and exit button is wired to close the application")
	saves.path = "user://missing-quit-directory/slot.dat"
	game.display_settings.quit_button.pressed.emit()
	check(saves.playing and game.display_settings.menu_open and not saves.last_message.is_empty(),"A failed save prevents quitting and keeps the paused session intact")
	saves.path = "user://quit-only-test.dat"
	game.display_settings.quit_button.pressed.emit()
	var data: Dictionary = saves.read_save()
	check(not data.is_empty() and data["coins"] == 765,"The actual Save and exit action writes current progress before quitting")
	check(saves.list_saves().size() == 2,"Closing the application also commits the first morning archive")
	print("RESULT: %d passed, %d failed; save and application exit" % [passed,failed])
	if failed: quit(1)
