extends "res://tests/interactions.gd"

const TEST_PATH := "user://test-session-save.dat"
var saves: Node
var original: Dictionary

func _initialize() -> void:
	Engine.set_meta(&"mine_defense_skip_start_screen", false)
	Engine.set_meta(&"mine_defense_save_path", TEST_PATH)
	Engine.remove_meta(&"mine_defense_session_action")
	Engine.remove_meta(&"mine_defense_intro_seen")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEST_PATH + suffix): DirAccess.remove_absolute(TEST_PATH + suffix)
	call_deferred("run_checks")

func control_point(control: Control) -> Vector2:
	return root.get_screen_transform() * (control.get_global_transform_with_canvas() * (control.size*0.5))

func click(control: Control) -> void:
	await mouse_move(control_point(control))
	await mouse_button(control_point(control),true)
	await mouse_button(control_point(control),false)

func wait_new_scene(old_id: int) -> void:
	var deadline: int = Time.get_ticks_msec()+8000
	while (current_scene == null or current_scene.get_instance_id() == old_id) and Time.get_ticks_msec() < deadline: await process_frame
	await settle()
	game = current_scene
	saves = game.get_node("SaveGame")
	mover = game.get_node("WorldInteractions")
	game.display_settings.resolution = Vector2i(1280,720)
	game.display_settings.window_mode = 0
	game.display_settings.apply_display(true)
	await settle()

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await wait_new_scene(-1)
	check(saves.start_screen != null and saves.start_screen.visible and paused and not saves.playing,"First launch presents a paused start screen")
	check(saves.start_screen.continue_button.disabled and not FileAccess.file_exists(TEST_PATH),"No save means Continuar is disabled and opening the title does not overwrite anything")
	check(game.get_node_or_null("IntroCinematic") == null,"The intro does not run underneath the start screen")
	var old_id: int = game.get_instance_id()
	await click(saves.start_screen.new_button)
	await wait_new_scene(old_id)
	check(game.display_settings.auto_click_prompt.visible and paused and game.get_node_or_null("IntroCinematic") == null,"New game asks about automatic mining before the cinematic")
	await click(game.display_settings.auto_click_decline)
	check(not game.display_settings.auto_click_prompt.visible and not game.display_settings.auto_click_enabled,"Manual mining choice closes the prompt")
	check(saves.playing and game.economy.coins == 100 and game.cycle.tutorial_step == 0,"Nueva partida starts a fresh game with the normal initial gold and tutorial")
	check(FileAccess.file_exists(TEST_PATH) and not saves.read_save().is_empty(),"A new game immediately creates a valid save")
	check(game.get_node_or_null("IntroCinematic") != null,"A fresh game retains the opening cinematic")
	if game.get_node_or_null("IntroCinematic") != null: game.get_node("IntroCinematic").finish()
	await settle()
	game.display_settings.open_menu()
	make_fixture()
	check(saves.valid_snapshot(saves.snapshot()),"Every active factory and partial blueprint can be serialized")
	await click(game.display_settings.save_button)
	check(game.display_settings.save_status.text == "Partida guardada.","The pause-menu save button writes a save and confirms success")
	original = saves.read_save()
	check(original["coins"] == 4321 and original["grid"]["width"] == 7,"Saved money and mine expansion match the game")
	check(FileAccess.file_exists(TEST_PATH+".bak"),"Saving again retains a prior complete backup")
	await click(game.display_settings.title_button)
	check(saves.start_screen.visible and paused and not saves.playing,"Pause can save and return to the main menu")
	check(not saves.start_screen.continue_button.disabled and "4321" in saves.start_screen.summary.text,"Continuar summarizes the saved game")
	await click(saves.start_screen.new_button)
	check(saves.start_screen.confirmation.visible and saves.read_save()["coins"] == 4321,"Starting over asks for confirmation before replacing the current save")
	await click(saves.start_screen.confirmation.get_child(3))
	check(not saves.start_screen.confirmation.visible and saves.read_save()["coins"] == 4321,"Canceling a new game keeps the save intact")
	old_id = game.get_instance_id()
	await click(saves.start_screen.continue_button)
	await wait_new_scene(old_id)
	game.display_settings.open_menu()
	check(not game.display_settings.auto_click_prompt.visible,"Continuing a save does not repeat the new-game prompt")
	check(saves.playing and saves.loaded_game and game.get_node_or_null("IntroCinematic") == null,"Continuar restores a fresh scene without replaying the opening")
	check(game.economy.coins == 4321 and game.grid.cave_width == 7 and game.grid.defense_tiles.size() == 2,"Loading restores money, cave ownership and defense platforms")
	check(game.mining.vein_level(Vector2i(14,0)) == 4 and game.mining.coal_veins[Vector2i(14,0)]["progress"] == 3,"Vein tiers, directions and mining progress survive loading")
	check(game.mining.nugget_type(Vector2i(15,4)) == "coal_4" and game.mining.nugget_type(Vector2i(18,4)) == "gold_ingot_4","Resource material, form and tier survive loading")
	check(game.conveyors.belt_shape(Vector2i(14,1)) == "junction" and game.conveyors.last_junction_entry[Vector2i(14,1)] == 2,"Belts retain their shape, direction and junction state")
	check(game.drills.drills[Vector2i(13,0)] == 1,"Drills retain their placement and rotation")
	check(game.launchers.launchers[Vector2i(12,-3)]["ammo"] == ["coal","brass"] and game.launchers.launchers[Vector2i(12,-3)]["cooldown"] > 0.75 and game.launchers.launchers[Vector2i(12,-3)]["cooldown"] <= 1.25,"Launcher ammunition and cooldown survive loading")
	check(machine_resumed("Compactors",Vector2i(12,2),"compactors"),"A partially processing compactor retains its inputs and progress")
	check(machine_resumed("Furnaces",Vector2i(14,2),"furnaces"),"A burning furnace retains fuel, input, output and elapsed time")
	check(machine_resumed("Saws",Vector2i(16,2),"saws"),"The saw preserves processing and both outlet states")
	check(game.get_node("Construction").plans[Vector2i(18,2)]["delivered"] == {"iron_ingot":1},"A partial blueprint remembers its delivered materials")
	check(game.progression.unlocked == original["progression"]["unlocked"] and game.progression.created_resources == original["progression"]["created_resources"],"Automatic unlocks and crafting milestones are restored")
	check(game.cycle.day == 3 and game.cycle.tutorial_step == 9 and game.cycle.funded_steps == {2:true,3:true,4:true},"Day and tutorial milestones are preserved")
	check(is_equal_approx(game.zombie_manager.base_health,73.0),"Base health is preserved")
	check(game.camera.position.is_equal_approx(original["camera"]["position"]),"Loading preserves the camera instead of refocusing the tutorial")
	var legacy: Dictionary = saves.snapshot()
	legacy["cycle"].erase("brass_ingot_created")
	legacy["cycle"].erase("brass_ingot_3_created")
	check(saves.valid_snapshot(legacy) and saves.restore_snapshot(legacy),"Saves from before the expanded tutorial remain loadable")
	check(not game.cycle.brass_ingot_created,"An old save without a crafted ingot starts with the proper default")
	# Persist a saw with one output blocked, then release only its pending item.
	game.mining.items_for("coal")[Vector2i(17,3)] = 1
	game.get_node("Saws").process_cutting(3.0)
	game.shop.accept_unlock_notice()
	var saw_state: Dictionary = saves.snapshot()
	check(saw_state["saws"][Vector2i(16,2)]["count"] == 1 and saw_state["saws"][Vector2i(16,2)]["pending"] == [false,true],"A saw can be saved with exactly one outlet pending")
	check(saves.restore_snapshot(saw_state),"A partial-output machine state can be restored")
	game.mining.items_for("coal").erase(Vector2i(17,3))
	game.get_node("Saws").try_output(Vector2i(16,2))
	check(game.mining.items_for("iron_3").size() == 2 and game.get_node("Saws").machines[Vector2i(16,2)]["count"] == 0,"Reloading a saw cannot duplicate the output it already delivered")
	game.get_node("Furnaces").process_smelting(2.0)
	var pending_furnace: Dictionary = saves.snapshot()
	check(pending_furnace["furnaces"][Vector2i(14,2)]["output"] == "brass_ingot","A furnace waiting for a free outlet keeps its completed ingot")
	check(saves.restore_snapshot(pending_furnace),"A blocked furnace product survives loading")
	game.mining.items_for("coal_3").erase(Vector2i(14,1))
	game.conveyors.belts[Vector2i(14,1)]["direction"] = 0
	game.get_node("Furnaces").try_output(Vector2i(14,2))
	check(game.mining.nugget_type(Vector2i(14,1)) == "brass_ingot" and game.get_node("Furnaces").machines[Vector2i(14,2)]["fuel"] == 0,"A restored furnace releases its existing ingot without burning fuel again")
	# Actual save/read operations cover integrity checks and backup recovery.
	game.economy.coins = 5000
	check(saves.save_game(),"A second snapshot can replace the first atomically")
	var primary := FileAccess.open(TEST_PATH,FileAccess.WRITE)
	primary.store_string("interrupted or corrupted save")
	primary.close()
	check(saves.read_save()["coins"] == 4321,"A corrupt primary save falls back to its complete backup")
	check(saves.save_game() and saves.read_save()["coins"] == 5000,"A recovered save can be written again without losing its backup")
	var invalid: Dictionary = saves.snapshot()
	invalid["grid"]["width"] = "wrong type"
	check(not saves.restore_snapshot(invalid) and game.economy.coins == 5000,"Invalid save data is rejected before changing the world")
	invalid = saves.snapshot()
	invalid["version"] = 999
	check(not saves.restore_snapshot(invalid),"Unsupported save versions cannot be loaded as current games")
	var real_path: String = saves.path
	saves.path = "user://missing-directory/test.dat"
	check(not saves.save_game() and not saves.last_message.is_empty(),"A write failure reports an error without destroying the valid save")
	saves.path = real_path
	# Tutorial and developer state survive independently of the larger fixture.
	var tutorial: Dictionary = saves.snapshot()
	tutorial["cycle"]["day"] = 1
	tutorial["cycle"]["tutorial_step"] = 3
	tutorial["cycle"]["tutorial_skipped"] = false
	tutorial["coins"] = 150
	tutorial["veins"]["coal"][Vector2i(14,0)]["level"] = 2
	tutorial["cycle"]["funded_steps"] = {2:true,3:true}
	check(saves.restore_snapshot(tutorial) and game.cycle.tutorial_step == 3 and game.cycle.funded_steps.has(3),"Incomplete tutorial lessons and earned batch budgets survive loading")
	var developer: Dictionary = saves.snapshot()
	developer["developer_mode"] = true
	developer["cycle"]["tutorial_skipped"] = true
	developer["cycle"]["tutorial_step"] = 6
	check(saves.restore_snapshot(developer) and game.economy.developer_mode and game.progression.developer_mode,"DEV mode survives a save independently of earned unlocks")
	game.economy.developer_mode = false
	game.progression.developer_mode = false
	game.cycle.day = 3
	game.cycle.tutorial_step = 9
	game.cycle.tutorial_skipped = true
	game.shop.accept_unlock_notice()
	# Resume an active horde, including damaged enemies and its spawn countdown.
	game.cycle.is_night = true
	game.zombie_manager.start_wave(3)
	var enemy: Node2D = get_nodes_in_group("zombies")[0]
	enemy.position += Vector2(30,90)
	enemy.health = 2.0
	enemy.limbs.erase("left_arm")
	enemy.attack_timer = 1.3
	game.zombie_manager.spawn_timer = 2.75
	var night: Dictionary = saves.snapshot()
	check(saves.save_game() and saves.restore_snapshot(saves.read_save()),"A mid-wave game can be saved and loaded")
	check(game.cycle.is_night and game.zombie_manager.active_wave and is_equal_approx(game.zombie_manager.spawn_timer,2.75),"The horde resumes its existing spawn schedule")
	var resumed: Node2D = get_nodes_in_group("zombies")[0]
	check(resumed.position == night["enemies"][0]["position"] and resumed.health == 2.0 and "left_arm" not in resumed.limbs,"Damaged zombies retain their positions, health and missing limbs")
	var before: float = game.zombie_manager.base_health
	resumed.base_attacked.emit(1.0)
	check(game.zombie_manager.base_health == before-1,"Restored enemies still damage the base through their signals")
	# Ordinary UI refreshes must not write files on every mining hit.
	var count := [0]
	saves.status_changed.connect(func(_text: String, success: bool):
		if success: count[0] += 1
	)
	for i in range(20): game.cycle.changed.emit()
	await settle()
	check(count[0] <= 1,"Repeated unchanged cycle signals do not cause save writes per frame")
	var calls: int = count[0]
	game.display_settings.close_menu()
	saves.timer.wait_time = 0.1
	saves.timer.start()
	await create_timer(0.25).timeout
	check(count[0] > calls,"The autosave timer writes automatically during play")
	saves.timer.stop()
	# Victory can be resumed without paying or completing a night twice.
	for zombie: Node in get_nodes_in_group("zombies"):
		zombie.remove_from_group("zombies")
		zombie.queue_free()
	game.zombie_manager.active_wave = false
	game.on_wave_completed()
	var victory: Dictionary = saves.snapshot()
	check(saves.restore_snapshot(victory) and game.night_victory_overlay.visible and not game.cycle.is_night,"A completed night resumes on its pending victory screen")
	check(game.cycle.day == 4,"Restoring a victory does not advance the day twice")
	# A new-game confirmation actually replaces the slot with a clean world.
	game.night_victory_overlay.hide()
	check(saves.return_to_start(),"Returning to the menu saves the latest progress")
	await click(saves.start_screen.new_button)
	old_id = game.get_instance_id()
	await click(saves.start_screen.confirmation.get_child(2))
	await wait_new_scene(old_id)
	if game.get_node_or_null("IntroCinematic") != null: game.get_node("IntroCinematic").finish()
	await click(game.display_settings.auto_click_accept)
	check(game.economy.coins == 100 and game.grid.cave_width == 3 and game.mining.coal_veins.is_empty() and game.progression.unlocked.is_empty(),"Confirming Nueva partida resets buildings, unlocks, money and cave size")
	check(saves.read_save()["coins"] == 100 and saves.read_save()["cycle"]["day"] == 1,"The new slot contains the fresh game")
	print("RESULT: %d passed, %d failed; start screen and persistence" % [passed,failed])
	quit(1 if failed else 0)

func make_fixture() -> void:
	game.grid.expand()
	game.grid.purchase_defense_platforms()
	game.economy.coins = 4321
	game.cycle.day = 3
	game.cycle.tutorial_step = 9
	game.cycle.funded_steps = {2:true,3:true,4:true}
	game.cycle.barrier_broken = true
	game.cycle.tutorial_skipped = true
	for material: String in ["coal","brass","iron","gold"]:
		var at: Vector2i = {"coal":Vector2i(14,0),"brass":Vector2i(16,0),"iron":Vector2i(12,0),"gold":Vector2i(18,0)}[material]
		game.mining.place_vein(at,1,material)
	game.mining.coal_veins[Vector2i(14,0)]["level"] = 4
	game.mining.coal_veins[Vector2i(14,0)]["progress"] = 3
	game.conveyors.place(Vector2i(14,1),2,"junction")
	game.conveyors.last_junction_entry[Vector2i(14,1)] = 2
	game.mining.items_for("coal_3")[Vector2i(14,1)] = 1
	game.drills.place(Vector2i(13,0),1)
	game.launchers.place(Vector2i(12,-3))
	game.launchers.receive(Vector2i(12,-3),"coal")
	game.launchers.receive(Vector2i(12,-3),"brass")
	game.launchers.launchers[Vector2i(12,-3)]["cooldown"] = 1.25
	game.launchers.place(Vector2i(16,4))
	var compactors: Node = game.get_node("Compactors")
	compactors.place(Vector2i(12,2),1)
	compactors.receive(Vector2i(12,2),"iron_ingot_3")
	compactors.receive(Vector2i(12,2),"iron_ingot_3")
	compactors.process_outputs(1.75)
	var furnace: Node = game.get_node("Furnaces")
	furnace.place(Vector2i(14,2))
	furnace.receive(Vector2i(14,2),"coal_4")
	furnace.receive(Vector2i(14,2),"brass_4")
	furnace.process_smelting(2)
	var saw: Node = game.get_node("Saws")
	saw.place(Vector2i(16,2),1)
	saw.receive(Vector2i(16,2),"iron_4")
	saw.process_cutting(1.1)
	game.get_node("Construction").place(Vector2i(18,2),"compactor",0,300)
	game.get_node("Construction").receive(Vector2i(18,2),"iron_ingot")
	game.mining.items_for("coal_4")[Vector2i(15,4)] = 1
	game.mining.items_for("gold_ingot_4")[Vector2i(18,4)] = 1
	game.progression.unlocked = {"expansion":true,"brass":true,"iron":true,"furnace":true,"launcher":true,"straight":true}
	game.progression.created_resources = {"coal_4":true,"brass_ingot_3":true}
	game.progression.completed_veins = {"coal":true,"brass":true}
	game.zombie_manager.base_health = 73
	game.redraw_world()

func machine_resumed(node_name: String, at: Vector2i, key: String) -> bool:
	var current: Dictionary = game.get_node(node_name).machines[at].duplicate(true)
	var saved: Dictionary = original[key][at]
	var elapsed: float = current["elapsed"]
	current["elapsed"] = saved["elapsed"]
	return current == saved and elapsed >= saved["elapsed"] and elapsed < float(saved["elapsed"]) + 0.5
