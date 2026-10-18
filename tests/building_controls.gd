extends "res://tests/compactor.gd"

func shift(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = pressed
	event.shift_pressed = pressed
	Input.parse_input_event(event)
	await settle()

func purchase(kind: String) -> void:
	match kind:
		"coal": mover.select_item("coal")
		"brass": mover.select_item("brass")
		"belt": mover.select_item("straight")
		"drill": mover.select_item("drill")
		"launcher": mover.select_item("launcher")
		"compactor": compactors.buy()
	await settle()

func place_at(cell: Vector2i) -> void:
	await mouse_move(point(cell))
	await mouse_button(point(cell), true)
	await mouse_button(point(cell), false)

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
	game.progression.add_experience(10000)
	for id in ["drill", "straight_belt", "brass", "curved_belts", "junction", "compactor"]: game.research_technology(id)
	game.economy.add(10000)
	game.cycle.free_launcher_available = false
	await settle()
	var a := Vector2i(14, 1)
	var b := Vector2i(16, 1)
	var left: Vector2i = game.grid.defense_cell("left")
	var right: Vector2i = game.grid.defense_cell("right")
	var prices := {"coal": 100, "brass": 150, "belt": 50, "drill": 200, "launcher": 200, "compactor": 300}
	for kind: String in prices:
		clear_items()
		var coins: int = game.economy.coins
		await purchase(kind)
		check(mover.placement_active() and game.economy.coins == coins, kind + " preview is selected without charging")
		await key(KEY_ESCAPE)
		check(not mover.placement_active() and not display.menu_open and not paused and game.economy.coins == coins, kind + " ESC cancels without charging or opening pause")
		await purchase(kind)
		await shift(true)
		await place_at(left if kind == "launcher" else a)
		await place_at(right if kind == "launcher" else b)
		check(mover.placement_active() and game.economy.coins == coins - 2 * prices[kind], kind + " Shift charges only the two placed items")
		await shift(false)
		check(not mover.placement_active() and game.economy.coins == coins - 2 * prices[kind], kind + " releasing Shift cancels the next preview without another charge")
	clear_items()
	var cash: int = game.economy.coins
	await purchase("coal")
	await place_at(Vector2i(0, 0))
	check(game.economy.coins == cash and mover.selected_item() == "coal", "An invalid grid click neither charges nor clears the selected item")
	shop.open_shop()
	await wait_shop()
	check(shop.money_box.visible and shop.money_box.get_global_rect().end.x < shop.shop_panel.get_global_rect().position.x and shop.money_label.text == str(cash), "Available money stays visible beside the open shop")
	if DisplayServer.get_name() != "headless" and "--capture" in args:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/shop-money.png")
	shop.open_category("BASE")
	await settle()
	shop.shop_scroll.ensure_control_visible(shop.item_buttons["drill"]["button"])
	await settle()
	await click_control(shop.item_buttons["drill"]["button"])
	await wait_shop()
	check(mover.selected_item() == "drill" and not game.placing_coal and game.economy.coins == cash, "A real menu click replaces a pending coal vein with a drill without charging")
	await buy_from_shop()
	check(mover.selected_item() == "compactor" and not game.placing_drill and game.economy.coins == cash, "The compacting machine replaces another pending item without charging")
	game.economy.add(-game.economy.coins)
	await place_at(a)
	check(game.economy.coins == 0 and not compactors.machines.has(a) and compactors.placing, "Funds are rechecked at placement if money changes after selection")
	game.economy.add(cash)
	await place_at(a)
	check(compactors.machines.has(a) and game.economy.coins == cash - 300 and not mover.placement_active(), "A successful placement charges exactly once and ends selection")
	await key(KEY_ESCAPE)
	check(display.menu_open and paused, "Idle ESC still pauses")
	await key(KEY_ESCAPE)
	check(not display.menu_open and not paused, "ESC resumes pause")
	clear_items()
	var balance: int = game.economy.coins
	await shift(true)
	await purchase("belt")
	await shift(false)
	check(not mover.placement_active() and game.economy.coins == balance, "Releasing Shift before the first placement leaves the balance unchanged")
	game.economy.add(50 - game.economy.coins)
	await purchase("belt")
	await shift(true)
	await place_at(a)
	await shift(false)
	check(not mover.placement_active() and game.economy.coins == 0 and game.conveyors.belts.has(a), "Running out of money ends repetition without removing the paid construction")
	game.economy.add(balance)
	clear_items()
	game.cycle.free_launcher_available = true
	await purchase("launcher")
	await shift(true)
	await place_at(left)
	await shift(false)
	check(game.launchers.launchers.has(left) and game.economy.coins == balance and not game.cycle.free_launcher_available, "A free first turret stays free while cancelling its next preview")
	clear_items()
	put(a, {"coal_vein": {"direction": 1, "progress": 0}})
	await mouse_move(point(a))
	await mouse_button(point(a), true)
	await mouse_move(point(b))
	await key(KEY_ESCAPE)
	await mouse_button(point(b), false)
	check(game.mining.coal_veins.has(a) and not game.mining.coal_veins.has(b) and not game.holding_object and not display.menu_open, "ESC cancels a dragged building without moving it or pausing")
	var samples := [
		["vein", {"coal_vein": {"direction": 1, "progress": 0}}, 50],
		["vein", {"brass_vein": {"direction": 1, "progress": 0}}, 75],
		["belt", {"belt": {"direction": 1, "shape": "straight"}}, 25],
		["belt", {"belt": {"direction": 1, "shape": "corner"}}, 25],
		["belt", {"belt": {"direction": 1, "shape": "junction"}}, 25],
		["drill", {"drill": 1}, 100],
		["launcher", {"launcher": {"ammo": ["coal", "brass", "coal_2", "brass_2"], "cooldown": 0.0, "angle": 0.0}}, 100],
		["compactor", {"compactor": {"direction": 1, "kind": "brass", "count": 3}}, 150],
	]
	for sample in samples:
		clear_items()
		var source: Vector2i = left if sample[0] == "launcher" else a
		put(source, sample[1])
		var coins: int = game.economy.coins
		var xp: int = game.progression.total_experience
		check(mover.drop(sample[0], source, game.grid.sale_cell) and game.economy.coins == coins + sample[2] and game.progression.total_experience == xp, sample[0] + " resells for half without granting EXP")
		check(not mover.sell(sample[0], source) and game.economy.coins == coins + sample[2], "Repeated sale never duplicates payment")
		if sample[0] == "launcher": check(game.mining.nuggets_at(source) == 4, "Selling a turret preserves all ammunition kinds")
		if sample[0] == "compactor": check(game.mining.items_for("brass").get(source, 0) == 3, "Selling a compactor preserves its partial batch")
	clear_items()
	put(a, {"belt": {"direction": 1, "shape": "straight"}, "coal": 1})
	check(not mover.drop("belt", a, game.grid.sale_cell) and game.conveyors.belts.has(a) and game.mining.nuggets_at(a) == 1, "Loaded belts remain immovable and cannot be sold underneath ore")
	game.mining.coal_nuggets.clear()
	game.cycle.is_night = true
	check(not mover.drop("belt", a, game.grid.sale_cell), "Combat prevents construction resale")
	game.cycle.is_night = false
	game.cycle.day = 1
	check(not mover.drop("belt", a, game.grid.sale_cell), "The guided tutorial prevents selling required constructions")
	game.cycle.day = 3
	game.set_process(true)
	await drag(a, game.grid.sale_cell)
	check(not game.conveyors.belts.has(a), "A real drag onto the chest sells an empty conveyor")
	game.free()
	await settle()
	print("RESULT: ", passed, " passed; ", failed, " failed; building controls")
	quit(1 if failed else 0)
