extends "res://tests/interactions.gd"

func old_materials(value: Variant) -> Variant:
	if value is String: return value.replace("copper","brass")
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[old_materials(key)] = old_materials(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value: result.append(old_materials(entry))
		return result
	return value

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	game.display_settings.resolution = Vector2i(1280,720)
	game.display_settings.window_mode = 0
	game.display_settings.apply_display(false)
	await settle()
	mover = game.get_node("WorldInteractions")
	var weapons: RefCounted = game.launchers
	var construction: Node = game.get_node("Construction")
	var saves: Node = game.get_node("SaveGame")
	var a := Vector2i(14,1)
	var b := Vector2i(16,1)
	check(game.progression.is_item_unlocked("launcher") and not construction.has_recipe("launcher"),"Rusty level-one launcher is available without a recipe")
	check(mover.item_price("launcher") == 500,"Rusty launcher costs 500 gold")
	game.economy.coins = 499
	check(not mover.select_item("launcher") and not weapons.launchers.has(a),"Cannot buy a launcher with less than 500 gold")
	game.economy.coins = 1000
	check(mover.select_item("launcher"),"Select the first rusty launcher")
	await create_timer(0.4).timeout
	check(mover.place_selected(a) and weapons.level_at(a) == 1 and not construction.plans.has(a) and game.economy.coins == 500,"First paid placement immediately builds a rusty level-one launcher")
	check(mover.select_item("launcher"),"Select the second rusty launcher")
	await create_timer(0.4).timeout
	check(mover.place_selected(b) and weapons.level_at(b) == 1 and game.economy.coins == 0,"Second launcher also costs exactly 500")
	game.shop.accept_unlock_notice()
	check(weapons.receive(a,"copper") and weapons.receive(b,"coal"),"Both basic launchers accept level-one ammunition")
	check(weapons.receive(a,"copper_2") and weapons.launchers[a]["ammo"].size() == 3,"Higher-tier nuggets now add multiple rounds to a basic launcher")
	check(mover.can_drop("launcher",a,b) and not mover.swaps_contents("launcher",a,b),"Dragging two basic launchers offers fusion rather than swapping")
	await drag(a,b)
	check(not weapons.launchers.has(a) and not weapons.launchers.has(b) and construction.plans.has(b),"Actual mouse drag consumes two basics and creates a blueprint")
	if not construction.plans.has(b):
		print("RESULT: %d passed, %d failed" % [passed,failed])
		quit(1)
		return
	check(construction.plans[b]["item"] == "launcher_2" and construction.plans[b]["ammo"].size() == 4,"Fusion keeps the ammunition in the tier-two blueprint")
	check(not construction.receive(b,"copper_3") and not construction.receive(b,"iron_ingot_3"),"Upgrade refuses nuggets and the wrong metal")
	check(construction.receive(b,"copper_ingot_3") and construction.plans.has(b),"One copper ingot level three partly supplies the upgrade")
	var partial: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(partial) and saves.restore_snapshot(partial),"Partly supplied upgrade with ammunition survives save and reload")
	check(construction.plans[b]["delivered"].get("copper_ingot_3") == 1 and construction.plans[b]["ammo"].size() == 4,"Reload preserves both paid materials and ammunition")
	check(construction.receive(b,"copper_ingot") and not construction.plans.has(b) and weapons.level_at(b) == 2,"One copper ingot level one completes level two")
	check(weapons.launchers[b]["ammo"].size() == 4,"Completed upgrade retains ammunition")
	check(weapons.place(a) and not weapons.can_fuse(a,b),"Level two cannot fuse further")
	var saved: Dictionary = saves.snapshot()
	check(saves.restore_snapshot(saved) and weapons.level_at(a) == 1 and weapons.level_at(b) == 2,"Both launcher levels survive reload")
	check(game.economy.sale_value("copper_4") == 100 and game.economy.sale_value("copper_ingot_3") == 1000,"Copper retains existing ore and ingot prices")
	check(construction.RECIPES["launcher_2"] == {"copper_ingot_3":1,"copper_ingot":1},"Tier-two upgrade has exactly the requested copper recipe")
	var legacy: Dictionary = old_materials(saved)
	legacy.erase("material_revision")
	legacy["launchers"][b].erase("level")
	legacy["resources"]["brass_ingot_3"][Vector2i(15,2)] = 1
	legacy["veins"]["brass"][Vector2i(14,2)] = {"level":3,"direction":1,"progress":2}
	legacy["progression"]["unlocked"]["brass"] = true
	legacy["cycle"]["brass_ingot_3_created"] = true
	legacy["blueprints"][Vector2i(16,2)] = {"item":"launcher", "direction":0, "paid":200, "delivered":{"brass_ingot_3":1}}
	var bytes: PackedByteArray = var_to_bytes(legacy)
	var file := FileAccess.open("user://legacy-copper-test.dat",FileAccess.WRITE)
	file.store_buffer("MZSV0001".to_utf8_buffer())
	file.store_64(bytes.size())
	file.store_buffer(saves.checksum(bytes).to_utf8_buffer())
	file.store_buffer(bytes)
	file.close()
	check(not saves.read_file("user://legacy-copper-test.dat").is_empty(),"Real legacy file passes checksum validation and material migration")
	check(saves.valid_snapshot(legacy) and saves.restore_snapshot(legacy),"Legacy brass save migrates successfully")
	check(game.mining.items_for("copper_ingot_3").get(Vector2i(15,2)) == 1 and game.mining.vein_at(Vector2i(14,2)) == "copper","Legacy ingots and veins become copper without loss")
	check(game.cycle.copper_ingot_3_created and game.progression.is_item_unlocked("copper") and weapons.level_at(b) == 2,"Migration preserves tutorial milestones, unlocks and finished old weapons")
	check(construction.plans[Vector2i(16,2)]["item"] == "launcher_2" and construction.plans[Vector2i(16,2)]["delivered"].get("copper_ingot_3") == 1,"Legacy launcher blueprint keeps its delivered ingot as a tier-two plan")
	check(construction.receive(Vector2i(16,2),"copper_ingot") and weapons.level_at(Vector2i(16,2)) == 2,"Legacy partial blueprint completes with the missing copper ingot")
	var bad: Dictionary = saves.snapshot()
	bad["launchers"][b]["level"] = 3
	check(not saves.valid_snapshot(bad),"Saves reject unsupported weapon levels")
	clear_items()
	weapons.place(a)
	weapons.place(b)
	game.cycle.is_night = true
	check(not weapons.can_fuse(a,b) and not mover.drop("launcher",a,b),"Combat blocks launcher fusion")
	game.cycle.is_night = false
	for index in range(5): weapons.receive(a,"coal")
	weapons.receive(b,"coal_2")
	check(weapons.can_fuse(a,b),"Fusion permits seven rounds to fit the upgraded capacity")
	weapons.receive(b,"coal")
	check(not weapons.can_fuse(a,b),"Fusion never discards ammunition beyond capacity")
	clear_items()
	weapons.place(a)
	weapons.place(b)
	weapons.receive(a,"copper")
	check(weapons.fuse(a,b) and construction.cancel(b) and game.mining.items_for("copper").size() == 1 and game.economy.coins == 1000,"Canceling a fused blueprint refunds both paid basics and preserves its ammo")
	print("RESULT: %d passed, %d failed; copper and launcher fusion" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
