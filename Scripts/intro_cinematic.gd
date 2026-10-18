extends CanvasLayer

signal finished

const SESSION_KEY: StringName = &"mine_defense_intro_seen"
const TITLE_END := 4.2
const BATTLE_END := 18.2
const FALL_END := 25.2
const RUINS_END := 28.8
const YEARS_END := 32.8
const ARRIVAL_END := 41.5
const DURATION := 43.0
const FRAME_SIZE := Vector2(1280, 720)

var elapsed: float = 0.0
var game: Node
var display: CanvasLayer
var game_ui: CanvasLayer
var world_visibility: Dictionary = {}
var ui_was_visible: bool = true
var previously_paused: bool = false
var owns_pause: bool = false
var ended: bool = false
var screen: Control
var frame: Control
var film: FilmCanvas
var title: Label
var fade: ColorRect
var skip_button: Button
var shot_sound: AudioStreamWAV
var blast_sound: AudioStreamWAV
var wind_sound: AudioStreamWAV
var sound_players: Array[AudioStreamPlayer] = []
var ambience: AudioStreamPlayer
var last_shot: int = -1
var last_blast: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150
	game = get_parent()
	for child in game.get_children():
		if child is CanvasLayer and child.has_method("toggle_pause_menu"):
			display = child
	game_ui = game.get_node_or_null("CanvasLayer") as CanvasLayer
	previously_paused = get_tree().paused
	# A scene restarted in this session goes directly back to its tutorial.
	Engine.set_meta(SESSION_KEY, true)
	if game_ui != null:
		ui_was_visible = game_ui.visible
		game_ui.hide()
	# The opaque film covers the game; exclude that paused world from rendering.
	for child in game.get_children():
		if child is CanvasItem and not child is Camera2D:
			world_visibility[child] = child.visible
			child.hide()
	build_screen()
	build_audio()
	get_tree().paused = true
	owns_pause = true
	get_viewport().size_changed.connect(update_layout)
	update_layout()
	present_frame()

func build_screen() -> void:
	screen = Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(black)
	frame = Control.new()
	frame.size = FRAME_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	screen.add_child(frame)
	film = FilmCanvas.new()
	frame.add_child(film)
	fade = ColorRect.new()
	fade.z_index = 200
	fade.size = FRAME_SIZE
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fade)
	title = Label.new()
	title.z_index = 201
	title.position = Vector2(60, 260)
	title.size = Vector2(1160, 200)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(title)
	skip_button = Button.new()
	skip_button.z_index = 202
	skip_button.text = "Omitir"
	skip_button.position = Vector2(1140, 660)
	skip_button.size = Vector2(104, 40)
	skip_button.flat = true
	skip_button.add_theme_font_size_override("font_size", 16)
	skip_button.add_theme_color_override("font_color", Color("#a6aaa8"))
	skip_button.add_theme_color_override("font_hover_color", Color.WHITE)
	skip_button.pressed.connect(finish)
	frame.add_child(skip_button)

func update_layout() -> void:
	screen.size = get_viewport().get_visible_rect().size
	var factor: float = minf(screen.size.x / FRAME_SIZE.x, screen.size.y / FRAME_SIZE.y)
	frame.scale = Vector2.ONE * factor
	frame.position = (screen.size - FRAME_SIZE * factor) * 0.5

func _process(delta: float) -> void:
	var menu_open: bool = is_instance_valid(display) and display.menu_open
	for player in sound_players:
		player.stream_paused = menu_open
	ambience.stream_paused = menu_open
	if ended or menu_open:
		return
	elapsed = minf(DURATION, elapsed + delta)
	present_frame()
	update_audio()
	if elapsed >= DURATION:
		finish()

func _input(event: InputEvent) -> void:
	if ended or (is_instance_valid(display) and display.menu_open): return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F10 or event.physical_keycode == KEY_F10):
		get_viewport().set_input_as_handled()
		if not game.get("economy").developer_mode: game.get("economy").toggle_developer_mode()
		finish()

func present_frame() -> void:
	film.time = elapsed
	film.present()
	title.visible = elapsed < TITLE_END or (elapsed >= RUINS_END and elapsed < YEARS_END)
	title.text = "Día 0: El Comienzo De Todo" if elapsed < TITLE_END else "3 años después"
	var local_time: float = elapsed if elapsed < TITLE_END else elapsed - RUINS_END
	var length: float = TITLE_END if elapsed < TITLE_END else YEARS_END - RUINS_END
	title.modulate.a = smoothstep(0.15, 1.1, local_time) * (1.0 - smoothstep(length - 1.0, length - 0.1, local_time))
	var darkness: float = 0.0
	if elapsed < TITLE_END:
		darkness = 1.0
	elif elapsed < TITLE_END + 1.2:
		darkness = 1.0 - smoothstep(TITLE_END, TITLE_END + 1.2, elapsed)
	elif absf(elapsed - FALL_END) < 0.45:
		darkness = 1.0 - smoothstep(0.0, 0.45, absf(elapsed - FALL_END))
	elif elapsed >= RUINS_END - 0.9 and elapsed < YEARS_END:
		darkness = smoothstep(RUINS_END - 0.9, RUINS_END, elapsed)
	elif elapsed >= YEARS_END and elapsed < YEARS_END + 1.0:
		darkness = 1.0 - smoothstep(YEARS_END, YEARS_END + 1.0, elapsed)
	elif elapsed >= ARRIVAL_END:
		darkness = smoothstep(ARRIVAL_END, DURATION - 0.2, elapsed)
	# Keep the white title above the black image fade.
	fade.color.a = darkness
	skip_button.modulate.a = smoothstep(0.6, 1.5, elapsed)

func finish() -> void:
	if ended:
		return
	ended = true
	restore_game()
	finished.emit()
	queue_free()

func restore_game() -> void:
	if not owns_pause:
		return
	owns_pause = false
	for item in world_visibility:
		if is_instance_valid(item): item.visible = world_visibility[item]
	world_visibility.clear()
	if is_instance_valid(game_ui):
		game_ui.visible = ui_was_visible
	# If removed from code while the pause menu is open, let that menu own pause.
	if is_instance_valid(display) and display.menu_open:
		display.previously_paused = previously_paused
	else:
		get_tree().paused = previously_paused
	if is_instance_valid(game):
		var guide: Node = game.get_node_or_null("TutorialGuide")
		if guide != null:
			guide.focus_objective.call_deferred()

func _exit_tree() -> void:
	restore_game()

func build_audio() -> void:
	# Short generated sounds keep the introduction self-contained in this .gd.
	shot_sound = synthesize_sound(0.15, 0)
	blast_sound = synthesize_sound(0.9, 1)
	wind_sound = synthesize_sound(3.0, 2)
	wind_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind_sound.loop_end = wind_sound.data.size() / 2
	for index in range(5):
		var player := AudioStreamPlayer.new()
		player.volume_db = -18.0
		add_child(player)
		sound_players.append(player)
	ambience = AudioStreamPlayer.new()
	ambience.stream = wind_sound
	ambience.volume_db = -30.0
	add_child(ambience)
	ambience.play()

func synthesize_sound(seconds: float, kind: int) -> AudioStreamWAV:
	const RATE := 22050
	var count: int = int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 853 + kind
	var low_noise: float = 0.0
	for index in range(count):
		var time: float = float(index) / RATE
		var phase: float = float(index) / count
		var noise: float = random.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.035 if kind == 2 else 0.2)
		var value: float
		if kind == 0:
			value = (noise * 0.4 + sin(time * TAU * (180.0 - phase * 110.0)) * 0.6) * exp(-phase * 9.0)
		elif kind == 1:
			value = (low_noise * 1.7 + sin(time * TAU * 48.0) * 0.2) * exp(-phase * 4.0) * minf(time * 150.0, 1.0)
		else:
			value = low_noise * 0.8 + sin(time * TAU * 40.0) * 0.08 + sin(time * TAU * 61.0) * 0.04
		# A smooth loop seam also avoids pops when skipping or switching scenes.
		value *= minf(1.0, float(mini(index, count - index - 1)) / 220.0)
		data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 28000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

func update_audio() -> void:
	var battle_time: float = elapsed - TITLE_END
	var battle: bool = elapsed >= TITLE_END + 0.7 and elapsed < FALL_END
	ambience.volume_db = -26.0 if battle else -33.0
	if not battle:
		return
	var shot: int = floori(battle_time / 0.32)
	if shot != last_shot and elapsed < BATTLE_END + 3.5:
		last_shot = shot
		play_sound(shot_sound, -23.0, 0.85 + float(shot % 4) * 0.12)
	var blast: int = floori((elapsed - BATTLE_END) / 1.25)
	if elapsed >= BATTLE_END and blast != last_blast:
		last_blast = blast
		play_sound(blast_sound, -15.0, 0.8 + float(blast % 3) * 0.1)

func play_sound(stream: AudioStreamWAV, volume: float, pitch: float) -> void:
	for player in sound_players:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume
			player.pitch_scale = pitch
			player.play()
			return


class FilmZombie extends "res://Scripts/zombie.gd":
	# Use the actual zombie artwork without joining the playable enemy group.
	func _ready() -> void:
		set_process(false)
		queue_redraw()


class FilmCompactors extends "res://Scripts/compactor_manager.gd":
	func _ready() -> void:
		game = get_parent()
		grid = game.get("grid")
		set_process(false)

	func _input(_event: InputEvent) -> void:
		pass

	func _unhandled_input(_event: InputEvent) -> void:
		pass


class FilmWorld extends Node2D:
	var grid: RefCounted
	var dragging_object: bool = false


class FilmCanvas extends Node2D:
	const Grid = preload("res://Scripts/grid_manager.gd")
	const Mining = preload("res://Scripts/mining_manager.gd")
	const Belts = preload("res://Scripts/conveyor_manager.gd")
	const Drills = preload("res://Scripts/drill_manager.gd")
	const Launchers = preload("res://Scripts/potato_launcher_manager.gd")
	const Renderer = preload("res://Scripts/world_renderer.gd")
	const Zone = preload("res://Scripts/defense_zone.gd")
	const Base = preload("res://Scripts/zombie_manager.gd")
	const Damage = preload("res://Scripts/zombie.gd").HitEffect
	const TURRET_COLUMNS := [10, 12, 14, 16, 18, 20]
	const HORDE_SIZE: int = 80
	var time: float = 0.0
	var battle_time: float = 0.0
	var destruction: float = 0.0
	var abandoned: bool = false
	var daylight: bool = false
	var world: FilmWorld
	var grid: RefCounted
	var mining: RefCounted
	var belts: RefCounted
	var drills: RefCounted
	var launchers: RefCounted
	var renderer: Node2D
	var terrain: Node2D
	var zone: Node2D
	var base: Node2D
	var compactors: Node2D
	var actors: Array[Node2D] = []
	var hits: Array[Node2D] = []
	var miner: Node2D
	var scenery: FilmDetails
	var machine_cells: Array[Vector2i] = []
	var ore_phase: int = -999
	var last_scenery_state := Vector3(-1, -1, -1)

	func _ready() -> void:
		world = FilmWorld.new()
		add_child(world)
		grid = Grid.new()
		grid.cave_width = 11
		grid.cave_height = 7
		grid.apply_cave_size()
		world.grid = grid
		for column: int in TURRET_COLUMNS:
			grid.defense_tiles[Vector2i(column, -3)] = true
			for row in [-2, -1]: grid.ammo_tiles[Vector2i(column, row)] = true
		grid.apply_cave_size()
		mining = Mining.new()
		mining.setup(grid)
		belts = Belts.new()
		belts.setup(grid, mining)
		drills = Drills.new()
		drills.setup(grid, mining, belts)
		mining.conveyors = belts
		mining.drills = drills
		belts.drills = drills
		launchers = Launchers.new()
		launchers.setup(grid, mining, belts, drills, world)
		belts.launchers = launchers
		terrain = FilmTerrain.new()
		terrain.grid = grid
		world.add_child(terrain)
		zone = Zone.new()
		world.add_child(zone)
		zone.setup(grid)
		zone.set_night(true)
		renderer = Renderer.new()
		renderer.setup(grid, mining, belts, drills)
		renderer.launchers = launchers
		world.add_child(renderer)
		compactors = FilmCompactors.new()
		world.add_child(compactors)
		base = Base.new()
		world.add_child(base)
		base.setup(grid)
		base.set_process(false)
		for column: int in TURRET_COLUMNS:
			for row in [-2, -1]: belts.place(Vector2i(column, row), 0)
		for column in [10, 12, 14, 18, 20]:
			var vein := Vector2i(column, 5)
			var kind: String = "brass" if column >= 18 else "coal"
			mining.place_vein(vein, 0, kind)
			drills.place(Vector2i(column, 6), 0)
			for row in range(5):
				var cell := Vector2i(column, row)
				if row == 2 and column in [12, 18]:
					compactors.machines[cell] = {"direction": 0, "kind": kind, "count": 4, "elapsed": 0.0}
				else:
					belts.place(cell, 0)
					machine_cells.append(cell)
		for index in range(HORDE_SIZE):
			var actor := FilmZombie.new()
			actor.z_index = 20
			world.add_child(actor)
			actors.append(actor)
			actor.scale = Vector2.ONE * (1.3 if index % 11 == 0 else 1.0)
			actor.modulate = Color("#c5b1d2") if index % 13 == 0 else Color.WHITE
			var hit := Damage.new()
			hit.amount = 2
			hit.z_index = 30
			world.add_child(hit)
			hit.set_process(false)
			hits.append(hit)
		miner = ArrivalMiner.new()
		miner.z_index = 40
		world.add_child(miner)
		scenery = FilmDetails.new()
		scenery.film = self
		scenery.z_index = 35
		world.add_child(scenery)
		add_child(FilmBars.new())

	func _exit_tree() -> void:
		mining.dispose()
		belts.dispose()
		drills.dispose()
		launchers.dispose()

	func zombie_position(index: int) -> Vector2:
		var row: int = index / 10
		var column: int = index % 10
		var advance: float = battle_time * 18.0 + smoothstep(BATTLE_END - 1, FALL_END, time) * 430
		var y: float = -430 - row * 32 + advance
		# Before the collapse, defenders hold the first ranks away from the entrance.
		if time < BATTLE_END and y > -70: y -= 480
		var spread: float = lerpf(32, 17, clampf((y + 640) / 830, 0, 1))
		return Vector2(744 + (column - 4.5) * spread + sin(index * 4.1) * 7, minf(194 + row * 10, y))

	func present() -> void:
		battle_time = maxf(0, time - TITLE_END)
		daylight = time >= YEARS_END
		abandoned = time >= FALL_END
		destruction = 1.0 if abandoned else smoothstep(BATTLE_END, FALL_END - 0.6, time)
		world.visible = time >= TITLE_END and not (time >= RUINS_END and time < YEARS_END)
		if not world.visible: return
		zone.set_night(not daylight)
		var reveal: float = smoothstep(TITLE_END + 1.5, TITLE_END + 5.5, time)
		var focus := Vector2(744, lerpf(240, -100, reveal))
		var zoom: float = lerpf(0.85, 0.72, reveal)
		if time >= BATTLE_END:
			focus.y = lerpf(-100, 210, smoothstep(BATTLE_END, FALL_END + 0.5, time))
			zoom = lerpf(0.72, 0.8, smoothstep(BATTLE_END, FALL_END + 0.5, time))
		if daylight:
			focus.y = lerpf(230, 245, smoothstep(YEARS_END, ARRIVAL_END, time))
			zoom = lerpf(0.8, 1.1, smoothstep(YEARS_END, ARRIVAL_END, time))
		var shake := Vector2(sin(time * 47), cos(time * 61)) * sin(destruction * PI) * 3
		world.scale = Vector2.ONE * zoom
		world.position = Vector2(640, 350) - focus * zoom + shake
		launchers.launchers.clear()
		launchers.shots.clear()
		for index in range(TURRET_COLUMNS.size()):
			if destruction > 0.12 + index * 0.14: continue
			var cell := Vector2i(TURRET_COLUMNS[index], -3)
			var origin: Vector2 = grid.get_cell_rect(cell).get_center()
			var target: Vector2 = zombie_position((floori(battle_time * 2) + index * 11) % HORDE_SIZE)
			launchers.launchers[cell] = {"ammo": ["brass_2", "brass_2", "brass_2", "brass_2", "brass_2"], "angle": (target - origin).angle()}
			if fmod(battle_time + index * 0.07, 0.32) < 0.16 and target.y > -650:
				launchers.shots.append({"from": origin, "to": target, "kind": "brass_2"})
		var phase: int = -1 if abandoned else floori(battle_time * 2)
		if phase != ore_phase:
			ore_phase = phase
			for items in mining.nugget_stores().values(): items.clear()
			if not abandoned:
				for index in range(machine_cells.size()):
					var cell: Vector2i = machine_cells[index]
					if posmod(index + phase, 3) == 0:
						mining.items_for("brass" if cell.x >= 17 else "coal")[cell] = 1
		for cell: Vector2i in compactors.machines:
			compactors.machines[cell]["elapsed"] = fmod(battle_time, 4)
		compactors.modulate = Color("#45403a") if abandoned else Color.WHITE
		renderer.modulate = Color("#766c5d") if abandoned else Color.WHITE
		terrain.modulate = renderer.modulate
		# The extended terrain is a retained grid; camera transforms move it for free.
		base.base_health = 100 * (1 - destruction)
		base.visible = not abandoned
		for index in range(actors.size()):
			var actor: Node2D = actors[index]
			if abandoned:
				actor.hide()
				hits[index].hide()
				continue
			actor.position = zombie_position(index)
			actor.visible = not abandoned and actor.position.y >= -660
			actor.walking_time = time * 8 + index
			actor.attacking = actor.position.y >= 160
			if index % 4 == 0:
				if battle_time > 6: actor.limbs.erase("left_arm")
				elif "left_arm" not in actor.limbs: actor.limbs.append("left_arm")
			actor.queue_redraw()
			var hit: Node2D = hits[index]
			hit.visible = actor.visible and index % 4 == 0 and fmod(battle_time + index * 0.13, 2.7) < 0.7
			if not hit.visible: continue
			hit.position = actor.position
			hit.age = fmod(battle_time + index * 0.13, 2.7)
			hit.limb = "left_arm" if battle_time > 6 else ""
			hit.limb_position = Vector2(-12 - hit.age * 12, minf(18, -hit.age * 35 + hit.age * hit.age * 80))
			hit.angle = hit.age * 4
			hit.queue_redraw()
		miner.visible = daylight
		miner.position = Vector2(lerpf(480, 744, smoothstep(YEARS_END + 0.5, ARRIVAL_END - 0.8, time)), lerpf(465, 218, smoothstep(YEARS_END + 0.5, ARRIVAL_END - 0.8, time)))
		miner.walk = time * 7
		if miner.visible: miner.queue_redraw()
		renderer.queue_redraw()
		compactors.queue_redraw()
		if base.visible: base.queue_redraw()
		var scenery_state := Vector3(destruction, float(abandoned), float(daylight))
		if scenery_state != last_scenery_state or (destruction > 0 and not abandoned):
			scenery.queue_redraw()
			last_scenery_state = scenery_state
		queue_redraw()

class FilmBars extends Node2D:
	func _init() -> void:
		z_index = 100

	func _draw() -> void:
		# Letterbox and framing stay fixed; all world art comes from game scripts.
		draw_rect(Rect2(0, 0, 1280, 64), Color.BLACK)
		draw_rect(Rect2(0, 638, 1280, 82), Color.BLACK)


class FilmTerrain extends Node2D:
	var grid: RefCounted

	func _draw() -> void:
		# Extend the same mine tiles to the frame edges during wide camera shots.
		var tile: float = grid.TILE_SIZE
		# Cover every shot with one background and a batched line set.
		var bounds := Rect2(-tile * 16, grid.GRID_OFFSET_Y, tile * 64, tile * 64)
		draw_rect(bounds, Color("#383838"))
		preload("res://Scripts/world_renderer.gd").draw_grid_lines(self, bounds, tile, Vector2(0, grid.GRID_OFFSET_Y))


class ArrivalMiner extends Node2D:
	var walk: float = 0.0

	func _draw() -> void:
		var bob: float = sin(walk) * 1.5
		draw_circle(Vector2(0, 14), 12, Color(0, 0, 0, 0.2))
		draw_rect(Rect2(-7, 10, 5, 12), Color("#594632"))
		draw_rect(Rect2(2, 10, 5, 12), Color("#594632"))
		draw_rect(Rect2(-9, bob, 18, 17), Color("#ad8149"))
		draw_circle(Vector2(0, -7 + bob), 9, Color("#deb785"))
		draw_rect(Rect2(-10, -17 + bob, 20, 8), Color("#e0b359"))
		draw_circle(Vector2(0, -14 + bob), 3, Color("#fff1b0"))
		draw_line(Vector2(10, 2 + bob), Vector2(19, 16 + bob), Color("#b88850"), 3)
		draw_line(Vector2(11, 3 + bob), Vector2(20, -2 + bob), Color("#a5b2b1"), 4)


class FilmDetails extends Node2D:
	var film: FilmCanvas

	func _draw() -> void:
		var ruin: float = film.destruction
		if ruin > 0:
			for index in range(film.TURRET_COLUMNS.size()):
				if ruin <= 0.12 + index * 0.14: continue
				var at: Vector2 = film.grid.get_cell_rect(Vector2i(film.TURRET_COLUMNS[index], -3)).get_center()
				draw_circle(at, 15, Color("#30332d"))
				draw_line(at + Vector2(-7, 9), at + Vector2(18, -3), Color("#927045"), 9)
				draw_line(at + Vector2(-16, -12), at + Vector2(-3, 7), Color("#66716c"), 4)
			for index in range(38):
				var at := Vector2(510 + fmod(index * 71.0, 470), 60 + fmod(index * 47.0, 420))
				if ruin < float(index % 7) / 7: continue
				draw_set_transform(at, sin(index * 2.1))
				draw_rect(Rect2(-10, -3, 20, 6), Color("#393630") if index % 2 else Color("#8f7045"))
				draw_set_transform(Vector2.ZERO)
				if not film.abandoned:
					var flame: float = 5 + sin(film.time * 13 + index) * 2
					draw_circle(at, flame, Color("#c87337"))
					draw_circle(at + Vector2(0, -4), flame * 0.5, Color("#edc369"))
					draw_circle(at + Vector2(sin(index) * 10, -20 - fmod(film.time * 15 + index * 8, 35)), 12, Color(0.15, 0.17, 0.18, 0.35))
			var door: Vector2 = film.grid.get_cell_rect(film.grid.sale_cell).get_center()
			draw_line(door + Vector2(-14, -14), door + Vector2(12, 8), Color(0.12, 0.1, 0.08, ruin), 5)
			draw_line(door + Vector2(12, 8), door + Vector2(-5, 20), Color(0.12, 0.1, 0.08, ruin), 4)
		if film.daylight:
			for index in range(50):
				var at := Vector2(490 + fmod(index * 61.0, 510), 90 + fmod(index * 43.0, 460))
				draw_line(at, at + Vector2(-3, -8), Color("#4f7545"), 2)
				draw_line(at, at + Vector2(4, -5), Color("#70884c"), 2)
