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
		"coal": game.buy_coal_vein()
		"brass": game.buy_brass_vein()
		"belt": game.buy_conveyor()
		"drill": game.buy_drill()
		"launcher": game.buy_launcher()
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
		check(mover.placement_active() and game.economy.coins == coins - prices[kind], kind + " preview is prepaid")
		await key(KEY_ESCAPE)
		check(not mover.placement_active() and not display.menu_open and not paused and game.economy.coins == coins, kind + " ESC refunds without opening pause")
		await purchase(kind)
		await shift(true)
		await place_at(left if kind == "launcher" else a)
		await place_at(right if kind == "launcher" else b)
		check(mover.placement_active() and game.economy.coins == coins - 3 * prices[kind], kind + " Shift repeats with a prepaid next preview")
		await shift(false)
		check(not mover.placement_active() and game.economy.coins == coins - 2 * prices[kind], kind + " releasing Shift cancels and refunds only the unused preview")
	await key(KEY_ESCAPE)
	check(display.menu_open and paused, "Idle ESC still pauses")
	await key(KEY_ESCAPE)
	check(not display.menu_open and not paused, "ESC resumes pause")
	clear_items()
	var balance: int = game.economy.coins
	await shift(true)
	await purchase("belt")
	await shift(false)
	check(not mover.placement_active() and game.economy.coins == balance, "Releasing Shift before the first placement refunds the whole purchase")
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
	check(game.launchers.launchers.has(left) and game.economy.coins == balance and not game.cycle.free_launcher_available, "A free first turret stays free while cancelling its paid repeat refunds correctly")
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
