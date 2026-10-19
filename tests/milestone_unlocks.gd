extends "res://tests/interactions.gd"

var shop: Control
var player: RefCounted
var mining: RefCounted
var left := Vector2i(14,1)
var right := Vector2i(15,1)

func acknowledge() -> void:
	shop.accept_unlock_notice()
	await settle()

func fuse_resource(kind: String) -> void:
	for inventory: Dictionary in mining.nugget_stores().values():
		inventory.erase(left)
		inventory.erase(right)
	mining.items_for(kind)[left] = 1
	mining.items_for(kind)[right] = 1
	check(mining.fuse(left,right),"Actual fusion creates the next tier of " + kind)
	await settle()

func fuse_vein(material: String) -> void:
	for inventory: Dictionary in mining.nugget_stores().values():
		inventory.erase(left)
		inventory.erase(right)
	for veins: Dictionary in [mining.coal_veins,mining.copper_veins,mining.iron_veins,mining.gold_veins]: veins.clear()
	mining.place_vein(left,1,material)
	mining.place_vein(right,1,material)
	mining.veins_for(material)[left]["level"] = 3
	mining.veins_for(material)[right]["level"] = 3
	check(mining.fuse_veins(left,right),"Two level-three veins create level-four " + material)
	await settle()

func run_checks() -> void:
	root.show()
	var args := OS.get_cmdline_user_args()
	var scene: String = args[0] if not args.is_empty() else "main.tscn"
	game = load("res://"+scene).instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"):
			child.resolution = Vector2i(1280,720)
			child.window_mode = 0
			child.apply_display(false)
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	shop = game.shop
	player = game.progression
	mining = game.mining
	mover = game.get_node("WorldInteractions")
	for name: String in ["Compactors","Furnaces","Saws"]: game.get_node(name).set_process(false)
	check(not player.has_method("add_experience") and not player.has_method("research"),"EXP and research APIs have been removed")
	shop.show_categories()
	check(not shop.category_buttons.has("INVESTIGACIÓN"),"No research tab remains in the menu")
	check(shop.view_button.position.x == 20,"View control moves into the space freed by EXP")
	shop.open_category("VETAS")
	check(shop.purchase_buttons.keys() == ["coal"],"Only coal veins are available initially")
	shop.open_category("DEFENSA")
	check(shop.purchase_buttons.has("launcher") and player.is_item_unlocked("launcher"),"Rusty launcher is available without crafting a material milestone")
	shop.open_category("HERRAMIENTAS")
	check(shop.shop_title.text != "HERRAMIENTAS" and not shop.category_has_items("HERRAMIENTAS"),"The empty tool category remains hidden and cannot be opened")
	shop.close_shop()
	await create_timer(0.4).timeout
	await fuse_resource("coal_3")
	check(player.is_item_unlocked("furnace") and not player.is_item_unlocked("copper"),"Coal nuggets level four unlock the furnace, but not the copper vein")
	check(shop.unlock_notice.visible and shop.notice_item_ids == ["furnace"],"A crafted material announces its automatic unlock")
	await create_timer(3.2).timeout
	check(shop.unlock_notice.visible,"Unlock notice still waits for Aceptar")
	await acknowledge()
	await fuse_vein("coal")
	check(player.is_item_unlocked("copper") and not player.is_item_unlocked("iron"),"A coal vein level four unlocks only the next mineral")
	mining.coal_veins.clear()
	check(player.is_item_unlocked("copper"),"Unlocks persist after removing the milestone vein")
	await acknowledge()
	await fuse_vein("copper")
	check(player.is_item_unlocked("iron") and not player.is_item_unlocked("gold"),"A copper vein level four unlocks iron")
	await acknowledge()
	await fuse_vein("iron")
	check(player.is_item_unlocked("gold"),"An iron vein level four unlocks gold")
	await acknowledge()
	mining.iron_veins.clear()
	await fuse_resource("copper")
	check(not player.is_item_unlocked("straight"),"Copper level two does not unlock belts")
	await fuse_resource("copper_2")
	for item: String in ["straight","corner_right","corner_left","junction"]:
		check(not player.is_item_unlocked(item),"Copper nuggets level three do not unlock " + item)
	await acknowledge()
	await fuse_resource("iron")
	check(not player.is_item_unlocked("saw"),"The saw waits for its highest required tier")
	await fuse_resource("iron_2")
	check(player.is_item_unlocked("saw"),"Iron nugget level three unlocks the saw")
	await acknowledge()
	await fuse_resource("iron_ingot_2")
	check(not player.is_item_unlocked("compactor"),"Iron ingot level three does not unlock the compactor")
	await fuse_resource("iron_ingot_3")
	check(player.is_item_unlocked("compactor"),"Iron ingot level four unlocks the compactor")
	await acknowledge()
	await fuse_resource("copper_ingot")
	check(not player.is_item_unlocked("drill") and player.is_item_unlocked("launcher"),"Lower copper ingots do not unlock the drill; rusty launcher stays available")
	await fuse_resource("copper_ingot_2")
	check(player.is_item_unlocked("drill") and player.is_item_unlocked("launcher"),"Copper ingot level three unlocks the drill while rusty launchers remain available")
	for item: String in ["straight","corner_right","corner_left","junction"]:
		check(player.is_item_unlocked(item),"Copper ingot level three unlocks " + item)
	await acknowledge()
	shop.open_category("DEFENSA")
	check(shop.purchase_buttons.has("launcher") and "Sin materiales" in shop.purchase_buttons["launcher"].tooltip_text,"Basic launcher catalog advertises construction without materials")
	shop.close_shop()
	await create_timer(0.4).timeout
	for inventory: Dictionary in mining.nugget_stores().values(): inventory.clear()
	game.economy.add(1000)
	var at := Vector2i(16,2)
	check(mover.select_item("launcher"),"Unlocked launcher can be selected")
	await create_timer(0.4).timeout
	check(mover.place_selected(at),"Launcher blueprint can be placed in an ordinary mine cell")
	var construction: Node = game.get_node("Construction")
	check(not construction.plans.has(at) and game.launchers.level_at(at) == 1,"Paid placement directly creates a basic launcher")
	check(not mining.can_move_nugget(at) and not mining.can_place_vein(at),"Stored launchers reserve their ordinary cell")
	game.launchers.receive(at,"copper")
	var enemy := DummyZombie.new()
	game.add_child(enemy)
	enemy.position = game.grid.get_cell_rect(at).get_center() + Vector2(0,-80)
	enemy.add_to_group("zombies")
	game.launchers.advance(10)
	check(enemy.hits == 0 and game.launchers.launchers[at]["ammo"].size() == 1,"A launcher outside defense positions cannot fire or consume ammo")
	check(not game.cycle.can_start_night(),"An armed launcher stored in the mine cannot start a night")
	game.grid.purchase_defense_platforms()
	var platform: Vector2i = game.grid.defense_cell("left")
	check(mover.drop("launcher",at,platform),"A completed launcher can move from the mine to its defense platform")
	enemy.position = game.grid.get_cell_rect(platform).get_center() + Vector2(0,-80)
	check(game.cycle.can_start_night(),"An armed launcher on its platform enables the next night")
	game.launchers.advance(4)
	check(enemy.hits == 1 and game.launchers.launchers[platform]["ammo"].is_empty(),"A designated defense position fires and consumes exactly one round")
	check(mover.drop("launcher",platform,at),"Launcher can be moved back to an ordinary cell")
	check(game.launchers.move(at,Vector2i(17,2)),"Direct launcher movement also supports ordinary cells")
	check(not game.launchers.can_place(game.grid.sale_cell) and not game.launchers.can_place(Vector2i(0,0)),"Launcher placement rejects the chest and unowned cells")
	check(construction.place(platform,"launcher_2",0,1000),"Tier-two launcher blueprint can be constructed on its platform")
	construction.receive(platform,"copper_ingot_3")
	check(construction.cancel(platform) and mining.nuggets_at(platform) == 0 and not mining.items_for("copper_ingot_3").is_empty(),"Canceling a platform blueprint returns its ingredients to usable mine cells")
	for item: String in ["straight","corner_right","corner_left","junction"]:
		var belt_at := Vector2i(17,3)
		check(construction.place(belt_at,item,1,50),"Belt plan can be placed: " + item)
		check(not construction.receive(belt_at,"copper_3") and construction.plans.has(belt_at),"Belt refuses a tier-three nugget: " + item)
		check(construction.receive(belt_at,"copper_ingot_3") and game.conveyors.belts.has(belt_at),"One tier-three copper ingot builds: " + item)
		game.conveyors.belts.erase(belt_at)
	# Real furnace output and compactor output must also report material milestones.
	player.unlocked.erase("furnace")
	var compactors: Node = game.get_node("Compactors")
	var machine_at := Vector2i(14,3)
	check(compactors.place(machine_at,1),"Compactor fixture fits an empty cell")
	compactors.receive(machine_at,"coal_3")
	compactors.receive(machine_at,"coal_3")
	compactors.process_outputs(4)
	check(player.is_item_unlocked("furnace"),"Automatic fusion reports crafted materials to progression")
	await acknowledge()
	var furnace: Node = game.get_node("Furnaces")
	check(furnace.place(Vector2i(16,3)),"Furnace fixture fits an empty cell")
	furnace.receive(Vector2i(16,3),"coal_4")
	furnace.receive(Vector2i(16,3),"copper_4")
	furnace.process_smelting(4)
	check(player.created_resources.has("copper_ingot"),"Smelting records the real ingot output")
	var fresh: RefCounted = load("res://Scripts/progression_manager.gd").new()
	fresh.developer_mode = true
	check(fresh.is_item_unlocked("gold") and fresh.is_item_unlocked("launcher") and fresh.is_item_unlocked("compactor"),"DEV exposes every mineral and recipe without milestones")
	fresh.developer_mode = false
	check(not fresh.is_item_unlocked("gold") and fresh.is_item_unlocked("launcher"),"Leaving DEV restores mineral locks while keeping basic launchers available")
	print("RESULT: %d passed, %d failed; material milestones" % [passed,failed])
	quit(1 if failed else 0)

class DummyZombie extends Node2D:
	var hits: int = 0
	func take_damage(_damage: float) -> void:
		hits += 1
