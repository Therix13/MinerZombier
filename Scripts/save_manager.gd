extends Node

signal status_changed(message: String, success: bool)

const StartScreenScript = preload("res://Scripts/start_screen.gd")
const ZombieScript = preload("res://Scripts/zombie.gd")
const VERSION := 1
const TUTORIAL_REVISION := 2
const DEFAULT_PATH := "user://savegame.dat"
const SESSION_ACTION: StringName = &"mine_defense_session_action"
const SKIP_START: StringName = &"mine_defense_skip_start_screen"
const INTRO_KEY: StringName = &"mine_defense_intro_seen"
const AUTOSAVE_SECONDS := 15.0
const CYCLE_FIELDS := ["day", "is_night", "defeated", "tutorial_step", "fusion_taught", "vein_fusion_taught", "barrier_broken", "fusion_sold", "copper_ingot_sold", "copper_ingot_created", "copper_ingot_3_created", "level3_sold", "level4_sold", "coal_sold", "expansion_bonus_granted", "free_launcher_available", "tutorial_skipped", "funded_steps", "coal_cell", "copper_cell", "furnace_cell"]
const WAVE_FIELDS := ["spawn_timer", "spawn_from_left", "spawn_count", "wave_total", "wave_day", "active_wave", "base_health", "cleared_time"]
const ENEMY_FIELDS := ["position", "destination", "health", "max_health", "walking_time", "attacking", "attack_timer", "limbs"]
const CAMERA_FIELDS := ["mine_position", "mine_zoom", "combat_mine_active", "combat_mine_position", "combat_mine_zoom", "defense_view"]

var game: Node2D
var path: String = DEFAULT_PATH
var playing := false
var restoring := false
var loaded_game := false
var test_mode := false
var timer: Timer
var start_screen: CanvasLayer
var last_message := ""
var urgent_pending := false
var last_cycle_state: Array = []

func _ready() -> void:
	game = get_parent()
	path = str(Engine.get_meta(&"mine_defense_save_path", path))
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	timer = Timer.new()
	timer.wait_time = AUTOSAVE_SECONDS
	timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	timer.timeout.connect(save_game)
	add_child(timer)
	status_changed.connect(func(message: String, _success: bool): game.display_settings.save_status.text = message)
	initialize.call_deferred()

func initialize() -> void:
	test_mode = bool(Engine.get_meta(SKIP_START, false))
	if test_mode:
		playing = true
		game.shop.ensure_intro()
		return
	var action: String = str(Engine.get_meta(SESSION_ACTION, ""))
	Engine.remove_meta(SESSION_ACTION)
	if action == "new":
		playing = true
		get_tree().paused = false
		Engine.remove_meta(INTRO_KEY)
		save_game()
		timer.start()
		game.display_settings.ask_auto_click(game.shop.ensure_intro)
	elif action == "continue":
		var data: Dictionary = read_save()
		if not data.is_empty() and restore_snapshot(data):
			playing = true
			get_tree().paused = false
			timer.start()
		else:
			show_start_screen()
	else:
		show_start_screen()
	last_cycle_state = cycle_signature()
	game.cycle.changed.connect(schedule_save)
	game.progression.items_unlocked.connect(func(_items: Array[String]): queue_save())
	game.get_node("Construction").completed.connect(func(_cell: Vector2i): queue_save())

func cycle_signature() -> Array:
	return [game.cycle.day,game.cycle.is_night,game.cycle.defeated,game.cycle.tutorial_step]

func schedule_save() -> void:
	var state: Array = cycle_signature()
	if state == last_cycle_state: return
	last_cycle_state = state
	queue_save()

func queue_save() -> void:
	if not playing or restoring or test_mode or urgent_pending: return
	urgent_pending = true
	flush_urgent.call_deferred()

func flush_urgent() -> void:
	urgent_pending = false
	if playing and not restoring: save_game()

func show_start_screen() -> void:
	playing = false
	timer.stop()
	game.camera_controller.dragging = false
	if start_screen == null:
		start_screen = StartScreenScript.new()
		start_screen.name = "StartScreen"
		start_screen.session = self
		game.add_child(start_screen)
	get_tree().paused = true
	start_screen.show_screen()

func return_to_start() -> bool:
	if playing and not save_game(): return false
	game.display_settings.close_menu()
	game.get_node("WorldInteractions").cancel_active()
	show_start_screen()
	return true

func begin(action: String) -> void:
	if action == "continue" and read_save().is_empty():
		start_screen.refresh_save()
		return
	Engine.set_meta(SESSION_ACTION, action)
	get_tree().paused = false
	var scene_path: String = game.scene_file_path
	if scene_path.is_empty(): scene_path = "res://main.tscn"
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		Engine.remove_meta(SESSION_ACTION)
		show_start_screen()
		report("No se pudo abrir la partida.", false)

func quit_game() -> void:
	if playing and not save_game():
		game.display_settings.open_menu()
		return
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree(): quit_game()

func report(message: String, success: bool) -> void:
	last_message = message
	status_changed.emit(message, success)

func properties(object: Object, names: Array) -> Dictionary:
	var result: Dictionary = {}
	for key: String in names:
		var value: Variant = object.get(key)
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func snapshot() -> Dictionary:
	var enemies: Array = []
	for enemy: Node in get_tree().get_nodes_in_group("zombies"):
		if enemy is ZombieScript and game.is_ancestor_of(enemy) and enemy.health > 0:
			enemies.append(properties(enemy, ENEMY_FIELDS))
	var veins: Dictionary = {}
	for material: String in ["coal", "copper", "iron", "gold"]: veins[material] = game.mining.veins_for(material).duplicate(true)
	var camera_data: Dictionary = properties(game.camera_controller, CAMERA_FIELDS)
	camera_data["position"] = game.camera.position
	camera_data["zoom"] = game.camera.zoom.x
	return {
		"version": VERSION, "tutorial_revision": TUTORIAL_REVISION, "material_revision": 2, "saved_at": int(Time.get_unix_time_from_system()),
		"coins": game.economy.coins, "developer_mode": game.economy.developer_mode,
		"grid": {"width": game.grid.cave_width, "height": game.grid.cave_height, "platforms": not game.grid.defense_tiles.is_empty()},
		"veins": veins, "resources": game.mining.nugget_stores().duplicate(true),
		"belts": game.conveyors.belts.duplicate(true), "junctions": game.conveyors.last_junction_entry.duplicate(true),
		"belt_time": game.conveyors.accumulator, "drills": game.drills.drills.duplicate(true), "drill_time": game.drills.accumulator,
		"launchers": game.launchers.launchers.duplicate(true),
		"compactors": game.get_node("Compactors").machines.duplicate(true),
		"furnaces": game.get_node("Furnaces").machines.duplicate(true),
		"saws": game.get_node("Saws").machines.duplicate(true),
		"blueprints": game.get_node("Construction").plans.duplicate(true),
		"progression": {"unlocked": game.progression.unlocked.duplicate(true), "created_resources": game.progression.created_resources.duplicate(true), "completed_veins": game.progression.completed_veins.duplicate(true)},
		"cycle": properties(game.cycle, CYCLE_FIELDS), "wave": properties(game.zombie_manager, WAVE_FIELDS),
		"enemies": enemies, "camera": camera_data, "victory": game.night_victory_overlay.visible,
		"notices": game.shop.notice_item_ids.duplicate(),
	}

func checksum(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func save_game() -> bool:
	if not playing or restoring: return false
	var data: Dictionary = snapshot()
	if not valid_snapshot(data):
		report("No se pudo guardar el estado de la partida.", false)
		return false
	var bytes: PackedByteArray = var_to_bytes(data)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		report("No se pudo guardar. Revisa el espacio disponible.", false)
		return false
	file.store_buffer("MZSV0001".to_utf8_buffer())
	file.store_64(bytes.size())
	file.store_buffer(checksum(bytes).to_utf8_buffer())
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or read_file(path + ".tmp").is_empty():
		report("No se pudo completar el guardado.", false)
		return false
	if FileAccess.file_exists(path):
		if not read_file(path).is_empty():
			if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
			if DirAccess.rename_absolute(path, path + ".bak") != OK:
				report("No se pudo actualizar el guardado.", false)
				return false
		else:
			if DirAccess.remove_absolute(path) != OK:
				report("No se pudo actualizar el guardado.", false)
				return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		# A complete prior save remains available through the backup.
		report("No se pudo finalizar el guardado.", false)
		return false
	report("Partida guardada.", true)
	return true

func read_file(filename: String) -> Dictionary:
	if not FileAccess.file_exists(filename): return {}
	var file := FileAccess.open(filename, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024 or file.get_length() < 80: return {}
	if file.get_buffer(8).get_string_from_utf8() != "MZSV0001": return {}
	var size: int = file.get_64()
	if size != file.get_length() - 80: return {}
	var expected_hash: String = file.get_buffer(64).get_string_from_utf8()
	var bytes: PackedByteArray = file.get_buffer(size)
	file.close()
	if checksum(bytes) != expected_hash: return {}
	var decoded: Variant = bytes_to_var(bytes)
	if decoded is Dictionary: decoded = migrate_materials(decoded)
	return decoded if decoded is Dictionary and valid_snapshot(decoded) else {}

func read_save() -> Dictionary:
	var data: Dictionary = read_file(path)
	return read_file(path + ".bak") if data.is_empty() else data

func renamed_material(value: Variant) -> Variant:
	if value is String: return value.replace("brass","copper")
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[renamed_material(key)] = renamed_material(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value: result.append(renamed_material(entry))
		return result
	return value

func migrate_materials(data: Dictionary) -> Dictionary:
	if data.get("material_revision",1) != 1: return data
	var result: Dictionary = renamed_material(data)
	# Previously built copper weapons retain their finished tier-two version.
	if result.get("launchers") is Dictionary:
		for launcher: Variant in result["launchers"].values():
			if launcher is Dictionary and not launcher.has("level"): launcher["level"] = 2
	if result.get("blueprints") is Dictionary:
		for plan: Variant in result["blueprints"].values():
			if plan is Dictionary and plan.get("item") == "launcher": plan["item"] = "launcher_2"
	result["material_revision"] = 2
	return result

func restore_snapshot(data: Dictionary) -> bool:
	data = migrate_materials(data)
	if not valid_snapshot(data): return false
	restoring = true
	loaded_game = true
	Engine.set_meta(INTRO_KEY, true)
	game.get_node("WorldInteractions").cancel_active()
	game.shop.close_shop()
	game.shop.accept_unlock_notice()
	var map: Dictionary = data["grid"]
	game.grid.defense_tiles.clear()
	game.grid.ammo_tiles.clear()
	game.grid.cave_width = map["width"]
	game.grid.cave_height = map["height"]
	game.grid.apply_cave_size()
	if map["platforms"]: game.grid.purchase_defense_platforms()
	for material: String in data["veins"]: replace_dictionary(game.mining.veins_for(material),data["veins"][material])
	for kind: String in data["resources"]: replace_dictionary(game.mining.items_for(kind),data["resources"][kind])
	replace_dictionary(game.conveyors.belts,data["belts"])
	replace_dictionary(game.conveyors.last_junction_entry,data["junctions"])
	game.conveyors.accumulator = data["belt_time"]
	replace_dictionary(game.drills.drills,data["drills"])
	game.drills.accumulator = data["drill_time"]
	replace_dictionary(game.launchers.launchers,data["launchers"])
	game.launchers.shots.clear()
	for pair: Array in [["Compactors","compactors"],["Furnaces","furnaces"],["Saws","saws"],["Construction","blueprints"]]:
		replace_dictionary(game.get_node(pair[0]).get("plans" if pair[1] == "blueprints" else "machines"),data[pair[1]])
	for key: String in data["progression"]: replace_dictionary(game.progression.get(key),data["progression"][key])
	game.progression.restore_vein_milestones()
	var crafted: Dictionary = data["progression"]["created_resources"]
	var tutorial_defaults := {
		"copper_ingot_created": crafted.has("copper_ingot"),
		"copper_ingot_3_created": crafted.has("copper_ingot_3") or crafted.has("copper_ingot_4"),
	}
	for key: String in CYCLE_FIELDS:
		game.cycle.set(key,data["cycle"].get(key,tutorial_defaults.get(key,game.cycle.get(key))))
	# Revision 2 inserts expansion between ingot fusion and the defense lessons.
	if int(data.get("tutorial_revision",1)) < TUTORIAL_REVISION and game.cycle.tutorial_step >= 11:
		if game.cycle.day == 1 and not game.cycle.is_night and not game.cycle.tutorial_skipped and game.cycle.tutorial_step < 15 and game.grid.cave_width < 7:
			game.cycle.tutorial_step = 11
		else:
			game.cycle.tutorial_step += 1
	for enemy: Node in get_tree().get_nodes_in_group("zombies"):
		if game.is_ancestor_of(enemy):
			enemy.remove_from_group("zombies")
			enemy.queue_free()
	for key: String in WAVE_FIELDS: game.zombie_manager.set(key,data["wave"][key])
	for saved: Dictionary in data["enemies"]:
		var enemy: Node2D = game.zombie_manager.ZombieScript.new()
		enemy.setup(saved["position"],saved["destination"],saved["max_health"])
		for key: String in ENEMY_FIELDS:
			if key == "limbs": enemy.limbs.assign(saved[key])
			else: enemy.set(key,saved[key])
		enemy.z_index = 20
		enemy.base_attacked.connect(game.zombie_manager._on_base_attacked)
		enemy.defeated.connect(game.zombie_manager.zombie_defeated.emit)
		game.zombie_manager.add_child(enemy)
	game.economy.coins = data["coins"]
	game.economy.developer_mode = data["developer_mode"]
	game.progression.developer_mode = data["developer_mode"]
	game.night_victory_overlay.visible = data["victory"]
	if data["victory"]: game.night_victory_title.text = "Noche %d: Superada" % (game.cycle.day - 1)
	game.defense_zone.set_night(game.cycle.is_night)
	var controller: RefCounted = game.camera_controller
	controller.stop_transition()
	for key: String in CAMERA_FIELDS: controller.set(key,data["camera"][key])
	game.camera.position = data["camera"]["position"]
	game.camera.zoom = Vector2.ONE * data["camera"]["zoom"]
	controller.clamp_position()
	game.shop.set_view_mode(controller.defense_view)
	game.camera.force_update_scroll()
	# Do not replay tutorial focus or cinematic when loading an existing game.
	game.get_node("TutorialGuide").last_step = game.cycle.tutorial_step
	game.get_node("TutorialGuide").last_state.clear()
	game.cycle.changed.emit()
	game.economy.money_changed.emit(game.economy.coins)
	var notices: Array[String] = []
	notices.assign(data["notices"])
	game.shop.announce_unlocks(notices)
	game.zombie_manager.queue_redraw()
	game.redraw_world()
	restoring = false
	return true

func replace_dictionary(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	target.merge(source.duplicate(true))

func number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= minimum and value <= maximum

func cells(map: Variant) -> bool:
	if not map is Dictionary or map.size() > 200: return false
	for cell: Variant in map:
		if not cell is Vector2i or cell.x < 0 or cell.x >= 30 or cell.y < -3 or cell.y >= 40 or cell == Vector2i(15,-1): return false
	return true

func dictionary_keys(data: Dictionary, names: Array) -> bool:
	for key: String in names:
		if not data.get(key) is Dictionary: return false
	return true

func valid_snapshot(data: Dictionary) -> bool:
	data = migrate_materials(data)
	if not data.get("material_revision") is int or data.get("material_revision") != 2: return false
	if not data.get("tutorial_revision",1) is int or data.get("tutorial_revision",1) not in [1,TUTORIAL_REVISION]: return false
	if data.get("version") != VERSION or not number(data.get("saved_at"),0,1e12) or not number(data.get("coins"),0,1e12) or not data.get("developer_mode") is bool: return false
	if not dictionary_keys(data,["grid","veins","resources","belts","junctions","drills","launchers","compactors","furnaces","saws","blueprints","progression","cycle","wave","camera"]): return false
	var map: Dictionary = data["grid"]
	if not map.get("width") is int or not map.get("height") is int: return false
	if Vector2i(map.get("width",0),map.get("height",0)) not in [Vector2i(3,3),Vector2i(7,5)] or not map.get("platforms") is bool: return false
	for material: String in ["coal","copper","iron","gold"]:
		if not cells(data["veins"].get(material)): return false
		for vein: Variant in data["veins"][material].values():
			if not vein is Dictionary or not number(vein.get("level"),1,4) or not number(vein.get("direction"),0,3) or not number(vein.get("progress"),0,11): return false
	for kind: String in game.mining.ORE_KINDS:
		if not cells(data["resources"].get(kind)): return false
		for count: Variant in data["resources"][kind].values():
			if not count is int or not number(count,1,1000): return false
	for key: String in ["belts","junctions","drills","launchers","compactors","furnaces","saws","blueprints"]:
		if not cells(data[key]): return false
	for belt: Variant in data["belts"].values():
		if belt is int:
			if not number(belt,0,3): return false
		elif not belt is Dictionary or not number(belt.get("direction"),0,3) or belt.get("shape") not in ["straight","corner","corner_right","corner_left","junction"]: return false
	for direction: Variant in data["drills"].values():
		if not direction is int or not number(direction,0,3): return false
	for entry: Variant in data["junctions"].values():
		if not entry is int or not number(entry,-1,3): return false
	for launcher: Variant in data["launchers"].values():
		if not launcher is Dictionary or not launcher.get("level",1) is int or launcher.get("level",1) not in [1,2]: return false
		if not launcher is Dictionary or not number(launcher.get("cooldown"),0,4) or not number(launcher.get("angle"),-100,100) or not launcher.get("ammo") is Array or launcher["ammo"].size() > 5: return false
		for kind: Variant in launcher["ammo"]:
			if kind not in ["coal","copper"]: return false
	for key: String in ["compactors","furnaces","saws","blueprints"]:
		for machine: Variant in data[key].values():
			if not machine is Dictionary or not number(machine.get("direction"),0,3): return false
			if key == "blueprints":
				var recipes: Dictionary = game.get_node("Construction").RECIPES
				if machine.get("item") not in recipes or not number(machine.get("paid"),0,1e12) or not machine.get("delivered") is Dictionary: return false
				for item: Variant in machine["delivered"]:
					if item not in recipes[machine["item"]] or not number(machine["delivered"][item],0,recipes[machine["item"]][item]): return false
				if machine.has("ammo"):
					if machine["item"] != "launcher_2" or not machine["ammo"] is Array or machine["ammo"].size() > 5: return false
					for ammo: Variant in machine["ammo"]:
						if ammo not in ["coal","copper"]: return false
				continue
			if not number(machine.get("elapsed"),0,4): return false
			if key == "compactors":
				if machine.get("kind") not in [""] + game.mining.ORE_KINDS or not number(machine.get("count"),0,2): return false
			else:
				if machine.get("input") not in [""] + game.mining.ORE_KINDS or machine.get("output") not in [""] + game.mining.ORE_KINDS: return false
				if key == "furnaces" and (not number(machine.get("fuel"),0,40) or not machine.get("burning") is bool): return false
				if key == "saws":
					if not number(machine.get("count"),0,2) or not machine.get("pending") is Array or machine["pending"].size() != 2: return false
					for pending: Variant in machine["pending"]:
						if not pending is bool: return false
	if not dictionary_keys(data["progression"],["unlocked","created_resources","completed_veins"]): return false
	for item: Variant in data["progression"]["unlocked"]:
		if item not in game.shop.UNLOCK_VIEW or not data["progression"]["unlocked"][item] is bool: return false
	for item: Variant in data["progression"]["created_resources"]:
		if item not in game.mining.ORE_KINDS or not data["progression"]["created_resources"][item] is bool: return false
	for item: Variant in data["progression"]["completed_veins"]:
		if item not in ["coal","copper","iron","gold"] or not data["progression"]["completed_veins"][item] is bool: return false
	var cycle: Dictionary = data["cycle"]
	for key: String in CYCLE_FIELDS:
		if key not in ["copper_ingot_created","copper_ingot_3_created"] and not cycle.has(key): return false
	if not number(cycle["day"],1,1e6) or not number(cycle["tutorial_step"],0,game.cycle.TUTORIAL_LAST_STEP) or not number(cycle["coal_sold"],0,1e12) or not cycle["funded_steps"] is Dictionary: return false
	for key: String in CYCLE_FIELDS:
		if key in ["day","tutorial_step","coal_sold","funded_steps"] or (key in ["copper_ingot_created","copper_ingot_3_created"] and not cycle.has(key)): continue
		if key.ends_with("_cell"):
			if not cycle[key] is Vector2i: return false
		elif not cycle[key] is bool: return false
	for step: Variant in cycle["funded_steps"]:
		if step not in [2,3,4] or not cycle["funded_steps"][step] is bool: return false
	var wave: Dictionary = data["wave"]
	for key: String in WAVE_FIELDS:
		if not wave.has(key): return false
	if not number(wave["base_health"],0,100) or not number(wave["wave_day"],1,1e6) or not number(wave["wave_total"],0,12) or not number(wave["spawn_count"],0,wave["wave_total"]): return false
	if not wave["active_wave"] is bool or not wave["spawn_from_left"] is bool or not number(wave["spawn_timer"],-1e6,1e6) or not number(wave["cleared_time"],0,3): return false
	if not data.get("enemies") is Array or data["enemies"].size() > 12: return false
	for enemy: Variant in data["enemies"]:
		if not enemy is Dictionary: return false
		for key: String in ENEMY_FIELDS:
			if not enemy.has(key): return false
		if not enemy["position"] is Vector2 or not enemy["position"].is_finite() or not enemy["destination"] is Vector2 or not enemy["destination"].is_finite(): return false
		if not number(enemy["max_health"],0.5,1e9) or not number(enemy["health"],0.001,enemy["max_health"]) or not number(enemy["walking_time"],0,1e12) or not number(enemy["attack_timer"],-1e6,1e6) or not enemy["attacking"] is bool or not enemy["limbs"] is Array: return false
		for limb: Variant in enemy["limbs"]:
			if limb not in ["left_arm","right_arm","left_leg","right_leg"]: return false
	for key: String in CAMERA_FIELDS + ["position","zoom"]:
		if not data["camera"].has(key): return false
		var value: Variant = data["camera"][key]
		if key.ends_with("position"):
			if not value is Vector2 or not value.is_finite(): return false
		elif key.ends_with("zoom"):
			if not number(value,0.01,100): return false
		elif not value is bool: return false
	if not number(data.get("belt_time"),0,4) or not number(data.get("drill_time"),0,1) or not data.get("victory") is bool or not data.get("notices") is Array: return false
	for item: Variant in data["notices"]:
		if item not in game.shop.UNLOCK_VIEW: return false
	return true
