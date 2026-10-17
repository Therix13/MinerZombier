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
	fade.size = FRAME_SIZE
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fade)
	title = Label.new()
	title.position = Vector2(60, 260)
	title.size = Vector2(1160, 200)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(title)
	skip_button = Button.new()
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

func present_frame() -> void:
	film.time = elapsed
	film.queue_redraw()
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


class FilmCanvas extends Node2D:
	var time: float = 0.0
	var battle_time: float = 0.0
	var destruction: float = 0.0
	var abandoned: bool = false
	var daylight: bool = false
	const TURRETS := [Vector2(340, 427), Vector2(478, 448), Vector2(592, 438)]

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color.BLACK)
		if time < TITLE_END or (time >= RUINS_END and time < YEARS_END):
			return
		battle_time = maxf(0.0, time - TITLE_END)
		daylight = time >= YEARS_END
		abandoned = time >= FALL_END
		destruction = 1.0 if abandoned else smoothstep(BATTLE_END, FALL_END - 0.6, time)
		var zoom: float = lerpf(1.0, 1.08, clampf(battle_time / 20.0, 0.0, 1.0))
		var center := Vector2(610, 350)
		if daylight:
			zoom = lerpf(1.02, 1.16, smoothstep(YEARS_END, ARRIVAL_END, time))
			center = Vector2(520, 380)
		var shake := Vector2.ZERO
		if not abandoned and destruction > 0.0:
			shake = Vector2(sin(time * 47.0), cos(time * 61.0)) * sin(destruction * PI) * 5.0
		draw_set_transform(Vector2(640, 360) - center * zoom + shake, 0.0, Vector2.ONE * zoom)
		draw_landscape()
		draw_mine()
		if not abandoned:
			draw_horde()
		for index in range(TURRETS.size()):
			draw_turret(TURRETS[index], index)
		if not abandoned:
			draw_combat()
		else:
			draw_debris()
		if daylight:
			draw_overgrowth()
			draw_arrival()
		else:
			draw_weather()
		draw_foreground()
		draw_set_transform(Vector2.ZERO)
		# Cinematic bars remain fixed while the landscape camera moves.
		draw_rect(Rect2(0, 0, 1280, 64), Color.BLACK)
		draw_rect(Rect2(0, 638, 1280, 82), Color.BLACK)
		if time > BATTLE_END and time < FALL_END:
			var flash: float = pow(maxf(0.0, 1.0 - fmod(time - BATTLE_END, 1.25) / 0.1), 2.0) * 0.13
			draw_rect(Rect2(0, 64, 1280, 574), Color(1.0, 0.72, 0.45, flash))

	func box(x: float, y: float, width: float, height: float, color: String) -> void:
		draw_rect(Rect2(x, y, width, height), Color(color))

	func polygon(points: Array, color: String) -> void:
		draw_colored_polygon(PackedVector2Array(points), Color(color))

	func draw_landscape() -> void:
		box(-180, -100, 1640, 850, "#8a9a91" if daylight else "#0c1922")
		for band in range(14):
			var tint := Color("#c0bfa4") if daylight else Color("#34434a")
			tint.a = 0.018 + band * 0.004
			draw_rect(Rect2(-180, 80 + band * 25, 1640, 26), tint)
		if daylight:
			draw_circle(Vector2(940, 169), 42, Color("#c9c9aa"))
		else:
			draw_circle(Vector2(942, 164), 34, Color("#899b98"))
			draw_circle(Vector2(954, 155), 30, Color("#17252e"))
		for index in range(7):
			var x: float = fposmod(index * 227.0 - battle_time * 1.3, 1600.0) - 180.0
			draw_rect(Rect2(x, 130 + index % 3 * 35, 180 + index % 2 * 110, 16), Color(0.65, 0.7, 0.67, 0.06))
		polygon([Vector2(-180, 405), Vector2(50, 214), Vector2(180, 318), Vector2(360, 170), Vector2(612, 344), Vector2(795, 223), Vector2(1030, 336), Vector2(1280, 200), Vector2(1460, 380), Vector2(1460, 560), Vector2(-180, 560)], "#6b817b" if daylight else "#182c35")
		polygon([Vector2(-180, 430), Vector2(5, 343), Vector2(138, 383), Vector2(302, 300), Vector2(490, 385), Vector2(690, 338), Vector2(920, 422), Vector2(1130, 322), Vector2(1460, 410), Vector2(1460, 600), Vector2(-180, 600)], "#4e675f" if daylight else "#213636")
		for index in range(35):
			var x: float = index * 47.0 - 120
			var y: float = 372 + sin(index * 2.7) * 26
			draw_pine(Vector2(x, y), 0.5 + float(index % 4) * 0.16, "#3e574c" if daylight else "#172c2b")
		box(-180, 462, 1640, 300, "#52604b" if daylight else "#26372f")
		polygon([Vector2(100, 492), Vector2(650, 475), Vector2(1460, 542), Vector2(1460, 685), Vector2(590, 551), Vector2(100, 540)], "#747362" if daylight else "#4b4b3c")
		for index in range(100):
			var x: float = fposmod(index * 137.7, 1600.0) - 160
			var y: float = 475 + fposmod(index * 71.3, 230.0)
			box(x, y, 3 + index % 5, 2, "#636951" if daylight else "#3d4939")

	func draw_pine(at: Vector2, factor: float, color: String) -> void:
		draw_rect(Rect2(at + Vector2(-3, -60) * factor, Vector2(6, 65) * factor), Color(color).darkened(0.2))
		for tier in range(3):
			var top: Vector2 = at + Vector2(0, -116 + tier * 27) * factor
			draw_colored_polygon(PackedVector2Array([top, top + Vector2(-30 - tier * 8, 56) * factor, top + Vector2(30 + tier * 8, 56) * factor]), Color(color))

	func draw_mine() -> void:
		# The same silhouettes survive into the ruins three years later.
		polygon([Vector2(-180, 510), Vector2(-180, 210), Vector2(25, 148), Vector2(140, 205), Vector2(246, 324), Vector2(325, 506)], "#3d4b47" if daylight else "#2a3433")
		polygon([Vector2(-180, 295), Vector2(27, 170), Vector2(129, 224), Vector2(47, 272), Vector2(142, 344), Vector2(250, 441), Vector2(133, 407), Vector2(62, 339)], "#4c5a50" if daylight else "#35413c")
		box(113, 364, 156, 154, "#212b28")
		box(124, 375, 130, 137, "#0d1515")
		box(132, 390, 110, 123, "#080e10")
		for index in range(3):
			var x: float = 110 + index * 72
			box(x, 366, 13, 154, "#675841" if daylight else "#756448")
			box(x + 3, 369, 3, 148, "#8a7752")
		box(106, 358, 166, 20, "#847149")
		box(108, 359, 162, 4, "#b19760")
		for index in range(8):
			box(115 + index * 19, 363, 7, 11, "#272e2c")
		# Mine rails and automated ore transport.
		for index in range(11):
			box(148 + index * 21, 498 + index * 2.0, 10, 21, "#544739")
		draw_line(Vector2(145, 497), Vector2(394, 522), Color("#6c7770"), 4)
		draw_line(Vector2(141, 511), Vector2(390, 540), Color("#6c7770"), 4)
		draw_factory()
		# Steel walls lose panels as the horde breaks through.
		for index in range(9):
			var x: float = 285 + index * 45
			if destruction > float(index % 4 + 1) / 5.0:
				box(x, 511, 38, 7, "#3d4844")
				continue
			box(x, 477, 41, 39, "#1b2828")
			box(x + 3, 480, 35, 29, "#52615b")
			box(x + 5, 481, 31, 3, "#8a9180")
			draw_line(Vector2(x + 7, 485), Vector2(x + 32, 506), Color("#35453f"), 3)
			box(x - 1, 476, 4, 43, "#89927a")
		if not abandoned:
			for index in range(3):
				var x: float = 270 + index * 170
				box(x, 384, 5, 95, "#59645a")
				if destruction < 0.8:
					box(x - 3, 380, 12, 6, "#edd59a")
					var alpha: float = (1.0 - destruction) * 0.035
					for size in range(4):
						draw_circle(Vector2(x + 3, 383), 12 + size * 13, Color(1.0, 0.8, 0.4, alpha))

	func draw_factory() -> void:
		var ruined: bool = destruction > 0.75
		# Armored processing building, lit windows, cooling stacks.
		box(282, 347 if not ruined else 392, 187, 125 if not ruined else 80, "#222f2d")
		box(289, 354 if not ruined else 400, 173, 110 if not ruined else 65, "#4d5b50" if daylight else "#3e4c45")
		if not ruined:
			box(274, 335, 204, 16, "#73816a")
			box(279, 336, 192, 4, "#a3a180")
			for index in range(4):
				box(303 + index * 39, 370, 22, 26, "#152528")
				box(306 + index * 39, 373, 16, 18, "#d8bd77" if destruction < 0.35 else "#333d35")
				box(313 + index * 39, 372, 2, 21, "#65705a")
			box(321, 283, 20, 52, "#45524b")
			box(317, 280, 28, 8, "#75826f")
			box(413, 260, 24, 75, "#3b4843")
			box(409, 256, 32, 9, "#7d866c")
		box(310, 420, 47, 44, "#152321")
		box(315, 425, 37, 37, "#5b6756" if destruction < 0.4 else "#2c3932")
		for index in range(3):
			box(319, 430 + index * 8, 29, 3, "#303f39")
		# Advanced drill and conveyor, with moving ore before the collapse.
		box(239, 445, 57, 39, "#24322d")
		box(243, 449, 49, 29, "#827850" if not abandoned else "#5c6050")
		box(250, 441, 35, 10, "#a39868" if not abandoned else "#73705a")
		for index in range(4):
			box(248 + index * 11, 457, 5, 12, "#303f37")
		box(295, 468, 216, 17, "#1c2828")
		box(295, 470, 216, 3, "#88917a")
		for index in range(13):
			var shift: float = 0.0 if abandoned else fmod(battle_time * 18.0, 16.0)
			box(297 + index * 16 + shift, 475, 6, 7, "#59604c")
		for index in range(5):
			var x: float = 300 + fmod(index * 43.0 + (0.0 if abandoned else battle_time * 18.0), 200.0)
			box(x, 461, 11, 7, "#ba9c57" if not abandoned else "#657059")
		# Tall headframe: the strongest visual landmark, broken after the fall.
		var top: float = lerpf(236.0, 382.0, destruction)
		draw_line(Vector2(500, 468), Vector2(520, top), Color("#77816b"), 11)
		draw_line(Vector2(559, 468), Vector2(540, top), Color("#77816b"), 11)
		for index in range(3):
			var y: float = lerpf(top + 15, 444.0, float(index) / 3.0)
			draw_line(Vector2(509, y + 45), Vector2(550, y), Color("#4b5b4b"), 5)
			draw_line(Vector2(509, y), Vector2(550, y + 45), Color("#4b5b4b"), 5)
		box(512, top - 8, 38, 15, "#a3996c" if not abandoned else "#686d53")
		if not abandoned:
			draw_arc(Vector2(530, top), 16, 0, TAU, 16, Color("#b2ab7f"), 4)
			var rotation: float = battle_time * 1.5
			draw_line(Vector2(530, top) - Vector2.from_angle(rotation) * 13, Vector2(530, top) + Vector2.from_angle(rotation) * 13, Color("#7f8a70"), 3)

	func draw_turret(at: Vector2, index: int) -> void:
		var disabled_at: float = 0.24 + index * 0.26
		var broken: bool = destruction > disabled_at
		draw_ellipse_shadow(at + Vector2(0, 45), Vector2(31, 9))
		box(at.x - 23, at.y + 19, 46, 26, "#1b2928")
		box(at.x - 18, at.y + 21, 36, 19, "#64715e" if not broken else "#3d4940")
		box(at.x - 25, at.y + 40, 50, 6, "#a08b57" if not broken else "#64654b")
		if broken:
			polygon([at + Vector2(-22, 21), at + Vector2(-14, 5), at + Vector2(4, 10), at + Vector2(18, 27)], "#465148")
			draw_line(at + Vector2(2, 17), at + Vector2(34, 27), Color("#737c64"), 9)
			if not abandoned:
				draw_fire(at + Vector2(0, 10), index, 0.8)
			return
		box(at.x - 12, at.y, 24, 29, "#26362e")
		box(at.x - 15, at.y - 7, 35, 26, "#8a9065")
		box(at.x - 11, at.y - 4, 29, 5, "#bdba84")
		box(at.x - 15, at.y + 12, 35, 6, "#566a4d")
		box(at.x + 13, at.y - 5, 38, 8, "#b8ba92")
		box(at.x + 13, at.y + 7, 38, 8, "#879678")
		box(at.x + 47, at.y - 7, 8, 24, "#3c4c40")
		box(at.x - 9, at.y + 2, 5, 5, "#b4d798")
		var shot_phase: float = fposmod(battle_time * 3.1 - index * 0.7, 1.0)
		if shot_phase < 0.16:
			var tip: Vector2 = at + Vector2(56, 4)
			polygon([tip, tip + Vector2(17, -12), tip + Vector2(11, -2), tip + Vector2(25, 3), tip + Vector2(10, 8), tip + Vector2(14, 15)], "#f3d68b")
			draw_circle(tip, 17, Color(1.0, 0.7, 0.3, 0.12))

	func zombie_position(index: int) -> Vector2:
		var row: int = index / 11
		var column: int = index % 11
		var advance: float = battle_time * (14.0 + row % 3 * 2.4)
		advance += smoothstep(BATTLE_END - 2.0, FALL_END, time) * 500.0
		var x: float = 1020 + column * 42 + row % 2 * 20 - advance
		# Initial casualties are replaced by a second, denser wave.
		if time < BATTLE_END and x < 690:
			x += 530.0
		return Vector2(maxf(230 + column * 29.0, x), 459 + row * 16 + sin(index * 7.1) * 8)

	func draw_horde() -> void:
		for index in range(99):
			var at: Vector2 = zombie_position(index)
			if at.x > 1410:
				continue
			var kind: int = 0
			if index % 13 == 0:
				kind = 1 # armored veteran
			elif index % 17 == 0:
				kind = 2 # massive brute
			elif index % 19 == 0:
				kind = 3 # glowing spitter
			var dying: bool = time < BATTLE_END and index % 7 == 0 and fposmod(battle_time + index * 0.27, 3.0) < 0.4
			if dying:
				draw_ellipse_shadow(at + Vector2(0, 4), Vector2(12, 4))
				box(at.x - 9, at.y - 3, 17, 7, "#57694b")
			else:
				draw_zombie(at, kind, index)

	func draw_zombie(at: Vector2, kind: int, index: int) -> void:
		var size: float = 1.65 if kind == 2 else 1.0
		var bob: float = sin(battle_time * (5.0 if kind == 2 else 9.0) + index) * 1.2
		var skin: Color = Color("#8b9d69")
		var clothes: Color = Color("#3b4d42")
		if kind == 1:
			clothes = Color("#68757b")
		elif kind == 2:
			skin = Color("#9a8b73")
			clothes = Color("#4a4037")
		elif kind == 3:
			skin = Color("#94bd59")
			clothes = Color("#3e5342")
		draw_ellipse_shadow(at, Vector2(10, 3) * size)
		var top: Vector2 = at + Vector2(0, bob)
		draw_rect(Rect2(top + Vector2(-6, -22) * size, Vector2(13, 17) * size), clothes)
		draw_rect(Rect2(top + Vector2(-7, -34) * size, Vector2(15, 14) * size), skin.darkened(0.2))
		draw_rect(Rect2(top + Vector2(-6, -34) * size, Vector2(12, 11) * size), skin)
		draw_rect(Rect2(top + Vector2(-7, -30) * size, Vector2(4, 3) * size), Color("#e2d17d") if kind != 3 else Color("#d9fa8b"))
		var stride: float = sin(battle_time * 8.0 + index) * 3.5
		draw_rect(Rect2(top + Vector2(-5 + stride, -8) * size, Vector2(4, 8) * size), clothes.darkened(0.3))
		draw_rect(Rect2(top + Vector2(2 - stride, -8) * size, Vector2(4, 8) * size), clothes.darkened(0.3))
		draw_rect(Rect2(top + Vector2(-16, -20) * size, Vector2(13, 5) * size), skin)
		if kind == 1:
			draw_rect(Rect2(top + Vector2(-9, -37), Vector2(20, 8)), Color("#8d9993"))
			draw_rect(Rect2(top + Vector2(-8, -25), Vector2(17, 12)), Color("#7c8780"))
		elif kind == 2:
			for spike in range(3):
				draw_line(top + Vector2(1 + spike * 4, -36), top + Vector2(spike * 5, -45), Color("#b5ab8a"), 3)
		elif kind == 3:
			draw_circle(top + Vector2(3, -17), 4, Color("#b5d75b"))
			draw_circle(top + Vector2(3, -17), 11, Color(0.65, 0.9, 0.25, 0.09))

	func draw_combat() -> void:
		for index in range(3):
			if destruction > 0.24 + index * 0.26:
				continue
			var start: Vector2 = TURRETS[index] + Vector2(56, 4)
			var phase: float = fposmod(battle_time * 3.1 - index * 0.7, 1.0)
			var target := Vector2(850 + index * 65 - battle_time * 4, 469 + index * 30)
			var point: Vector2 = start.lerp(target, phase)
			draw_line(point - (target - start).normalized() * 20, point, Color("#f1d799"), 2)
			if phase > 0.83:
				draw_explosion(target, (phase - 0.83) / 0.17, 19, index)
		# Special zombies lob acid over the fortifications.
		for index in range(3):
			var phase: float = fposmod(battle_time * 0.38 + index * 0.35, 1.0)
			var start := Vector2(1100 - battle_time * 12, 500 + index * 20)
			var target := Vector2(455 + index * 30, 435)
			var point: Vector2 = start.lerp(target, phase) + Vector2(0, -sin(phase * PI) * 170)
			draw_circle(point, 4, Color("#b2cc61"))
			draw_circle(point, 10, Color(0.7, 0.9, 0.3, 0.1))
		if time >= BATTLE_END:
			for index in range(6):
				var age: float = time - BATTLE_END - index * 0.9
				if age >= 0.0 and age < 1.4:
					draw_explosion(Vector2(580 - index * 64, 427 - index % 2 * 30), age / 1.4, 70, index)
			for index in range(4):
				if destruction > index * 0.15:
					draw_fire(Vector2(300 + index * 60, 412 - index % 2 * 48), index + 4, 1.3)
		# Smoke drifts from stacks, then expands into the falling mine.
		for index in range(22):
			var age: float = fposmod(battle_time * 0.21 + index * 0.17, 1.0)
			var origin := Vector2(330 if index % 2 == 0 else 425, 278 if index % 2 == 0 else 256)
			origin.y += destruction * 120
			var at: Vector2 = origin + Vector2(age * 95, -age * 145)
			var radius: float = (10 + age * 25) * (1.0 + destruction)
			draw_circle(at, radius, Color(0.13, 0.17, 0.17, (1.0 - age) * (0.2 + destruction * 0.35)))

	func draw_explosion(at: Vector2, phase: float, radius: float, seed_value: int) -> void:
		var alpha: float = 1.0 - phase
		for index in range(6):
			var angle: float = index * TAU / 6.0 + seed_value
			var offset: Vector2 = Vector2.from_angle(angle) * phase * radius * 0.8
			draw_circle(at + offset, (1.0 - phase * 0.7) * radius * 0.35, Color(1.0, 0.55 + index % 2 * 0.2, 0.25, alpha))
		for index in range(9):
			var direction: Vector2 = Vector2.from_angle(index * 2.4 + seed_value)
			var point: Vector2 = at + direction * phase * radius * 1.4 + Vector2(0, phase * phase * 40)
			draw_rect(Rect2(point, Vector2(4, 4)), Color(1.0, 0.83, 0.48, alpha))

	func draw_fire(at: Vector2, seed_value: int, factor: float) -> void:
		for index in range(6):
			var phase: float = fposmod(time * 1.7 + index * 0.19 + seed_value * 0.31, 1.0)
			var x: float = sin(index * 5.1 + seed_value) * 13 * factor
			var y: float = -phase * 55 * factor
			var color := Color(0.95, 0.35 + phase * 0.35, 0.15, 1.0 - phase)
			draw_rect(Rect2(at + Vector2(x, y), Vector2(10, 17) * (1.0 - phase * 0.7) * factor), color)
		for index in range(4):
			var phase: float = fposmod(time * 0.3 + index * 0.27 + seed_value, 1.0)
			draw_circle(at + Vector2(phase * 35, -30 - phase * 80) * factor, (9 + phase * 20) * factor, Color(0.12, 0.15, 0.14, (1.0 - phase) * 0.4))

	func draw_debris() -> void:
		for index in range(29):
			var at := Vector2(210 + fposmod(index * 77.3, 430), 460 + fposmod(index * 39.1, 105))
			var color := Color("#5c6554") if daylight else Color("#3a453d")
			draw_colored_polygon(PackedVector2Array([at, at + Vector2(9 + index % 14, -8 - index % 7), at + Vector2(23 + index % 10, 2), at + Vector2(4, 5)]), color)
		if not daylight:
			for index in range(4):
				draw_fire(Vector2(310 + index * 70, 440 + index % 2 * 30), index, 0.5)
			for index in range(14):
				var x: float = 250 + fposmod(index * 67.3 + time * 6.0, 390)
				var y: float = 450 - fposmod(time * 12 + index * 19, 180)
				box(x, y, 2, 2, "#d29c5a")

	func draw_overgrowth() -> void:
		for index in range(45):
			var at := Vector2(100 + fposmod(index * 73.1, 540), 456 + fposmod(index * 37.9, 91))
			for blade in range(3):
				draw_line(at + Vector2(blade * 3, 0), at + Vector2(blade * 5 - 3, -8 - index % 9), Color("#738259") if index % 3 else Color("#899366"), 2)
		for index in range(8):
			var at := Vector2(118 + index % 3 * 70, 388 + index * 13)
			draw_line(at, at + Vector2(8, 36), Color("#506d48"), 4)
			for leaf in range(3):
				draw_ellipse_shadow(at + Vector2(leaf % 2 * 10, leaf * 11), Vector2(7, 3), Color("#6e8654"))
		# Broken cables, a fallen beacon, and rust on the abandoned conveyor.
		draw_polyline(PackedVector2Array([Vector2(275, 380), Vector2(291, 425), Vector2(347, 463), Vector2(407, 451)]), Color("#343d31"), 2)
		draw_line(Vector2(485, 509), Vector2(548, 530), Color("#655f43"), 5)
		box(543, 524, 12, 10, "#8c7951")
		for index in range(7):
			box(302 + index * 25, 473, 12, 5, "#87664a")
		# Sparse drifting dust in the morning light.
		for index in range(22):
			var x: float = fposmod(index * 71.3 + time * 5.0, 1300)
			var y: float = 290 + fposmod(index * 39.7 + sin(time + index) * 5, 250)
			draw_rect(Rect2(x, y, 2, 2), Color(0.9, 0.88, 0.7, 0.25))

	func draw_arrival() -> void:
		var progress: float = smoothstep(YEARS_END + 0.4, ARRIVAL_END - 0.7, time)
		var at := Vector2(lerpf(1060, 255, progress), lerpf(572, 517, progress))
		var walking: bool = progress > 0.0 and progress < 1.0
		var bob: float = absf(sin(time * 7)) * 1.5 if walking else 0.0
		var step: float = sin(time * 7.0) * 4 if walking else 0.0
		draw_ellipse_shadow(at + Vector2(0, 2), Vector2(15, 4))
		# Backpack and pickaxe distinguish the returning miner from the horde.
		box(at.x + 5, at.y - 33 + bob, 13, 22, "#3a4034")
		box(at.x + 7, at.y - 31 + bob, 9, 16, "#817153")
		draw_line(at + Vector2(10, -8), at + Vector2(19, -40), Color("#8f7954"), 3)
		draw_line(at + Vector2(12, -42), at + Vector2(25, -37), Color("#acb2a1"), 4)
		box(at.x - 7, at.y - 30 + bob, 15, 23, "#776445")
		box(at.x - 7, at.y - 28 + bob, 4, 18, "#b69961")
		box(at.x - 7 + step, at.y - 8, 6, 9, "#2d3730")
		box(at.x + 3 - step, at.y - 8, 6, 9, "#2d3730")
		box(at.x - 9, at.y - 45 + bob, 17, 17, "#c2a47c")
		box(at.x - 12, at.y - 48 + bob, 24, 7, "#b9a366")
		box(at.x - 8, at.y - 53 + bob, 16, 8, "#9a864d")
		box(at.x - 13, at.y - 46 + bob, 5, 5, "#f4dda0")
		box(at.x - 8, at.y - 37 + bob, 3, 3, "#33382e")
		box(at.x - 13, at.y - 25 + bob, 8, 6, "#b39a74")
		# Hand lantern casts a warm pool against the cold, abandoned mine.
		var lantern: Vector2 = at + Vector2(-16, -15 + bob)
		for index in range(4):
			draw_circle(lantern, 13 + index * 12, Color(1.0, 0.75, 0.3, 0.025))
		draw_rect(Rect2(lantern + Vector2(-4, -3), Vector2(8, 11)), Color("#e8c780"))
		draw_rect(Rect2(lantern + Vector2(-2, -1), Vector2(4, 7)), Color("#ffedb6"))
		draw_arc(lantern + Vector2(0, -4), 4, PI, TAU, 8, Color("#74694d"), 1.5)

	func draw_ellipse_shadow(at: Vector2, radius: Vector2, color := Color(0.02, 0.05, 0.04, 0.3)) -> void:
		var points := PackedVector2Array()
		for index in range(16):
			points.append(at + Vector2.from_angle(index * TAU / 16.0) * radius)
		draw_colored_polygon(points, color)

	func draw_weather() -> void:
		for index in range(110):
			var x: float = fposmod(index * 101.7 - battle_time * 110, 1600) - 130
			var y: float = fposmod(index * 67.3 + battle_time * 310, 690)
			draw_line(Vector2(x, y), Vector2(x - 5, y + 12), Color(0.6, 0.72, 0.72, 0.13), 1)
		# Low fog helps separate the horde silhouettes from the distant forest.
		for index in range(4):
			draw_rect(Rect2(-180, 568 + index * 11, 1640, 12), Color(0.36, 0.44, 0.39, 0.025))

	func draw_foreground() -> void:
		polygon([Vector2(-180, 644), Vector2(80, 601), Vector2(260, 651), Vector2(483, 617), Vector2(700, 658), Vector2(1020, 606), Vector2(1460, 647), Vector2(1460, 820), Vector2(-180, 820)], "#253e34" if daylight else "#0b1b1b")
		for index in range(6):
			var x: float = -75 + index * 285
			draw_pine(Vector2(x, 675 + index % 2 * 37), 1.0 + index % 2 * 0.3, "#253e34" if daylight else "#0b1b1b")
