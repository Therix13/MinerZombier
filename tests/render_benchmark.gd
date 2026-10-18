# Native benchmark at 1920 x 1080 with the FPS cap disabled for measurement.
# Keep the same engine, driver, hardware and workload when comparing revisions.
extends SceneTree
var game: Node2D
var frames := 90
var report: Dictionary = {}
func _initialize() -> void:
	Engine.set_meta(&"mine_defense_intro_seen", true)
	Engine.max_fps = 0
	call_deferred("run")
func measure(label: String, film: Node = null) -> void:
	for i in range(20):
		if film != null:
			film.time = 12.0 + i / 60.0
			film.present()
		await process_frame
	var times: Array[float] = []
	var calls := 0.0
	var last := Time.get_ticks_usec()
	for i in range(frames):
		if film != null:
			film.time = 12.0 + i / 60.0
			film.present()
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	times.sort()
	report[label] = {"median_ms": times[frames / 2], "p95_ms": times[int(frames * 0.95)], "draw_calls": calls / frames}
	print("BENCH ", label, " ", JSON.stringify(report[label]))
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	for node in game.get_children():
		if node.has_method("toggle_pause_menu"):
			node.resolution = Vector2i(1920,1080)
			node.window_mode = 0
			node.apply_display(false)
	game.cycle.skip_tutorial()
	await measure("idle")
	game.grid.expand()
	game.economy.toggle_developer_mode()
	var furnaces: Node = game.get_node("Furnaces")
	var compactors: Node = game.get_node("Compactors")
	for row in range(5):
		game.mining.place_vein(Vector2i(12, row), 1)
		game.conveyors.place(Vector2i(13, row), 1)
		game.conveyors.place(Vector2i(14, row), 1)
		compactors.place(Vector2i(15, row), 1)
		compactors.receive(Vector2i(15, row), "brass")
		compactors.receive(Vector2i(15, row), "brass")
		furnaces.place(Vector2i(16, row), 1)
		furnaces.receive(Vector2i(16, row), "coal_4")
		furnaces.receive(Vector2i(16, row), "brass_4")
		game.mining.items_for("brass")[Vector2i(14,row)] = 1
	game.redraw_world()
	await measure("factory")
	var intro: Node = load("res://Scripts/intro_cinematic.gd").new()
	game.add_child(intro)
	intro.set_process(false)
	intro.elapsed = 4.0
	intro.present_frame()
	await measure("cinematic", intro.film)
	intro.finish()
	var path := "/workspace/.onboarding/display-test/performance-" + OS.get_environment("BENCH_LABEL") + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit()
