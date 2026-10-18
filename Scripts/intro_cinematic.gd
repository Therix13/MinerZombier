extends CanvasLayer

signal finished

const SESSION_KEY: StringName = &"mine_defense_intro_seen"
const DURATION := 9.0
const BREACH_DURATION := 7.0
const FRAME_SIZE := Vector2(1280, 720)

var breach: bool = false
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
var film: BarrierCanvas
var title: Label
var fade: ColorRect
var skip_button: Button
var blast_sound: AudioStreamWAV
var wind_sound: AudioStreamWAV
var sound_players: Array[AudioStreamPlayer] = []
var ambience: AudioStreamPlayer
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
	film = BarrierCanvas.new()
	film.source_game = game
	film.breach = breach
	frame.add_child(film)
	fade = ColorRect.new()
	fade.z_index = 200
	fade.size = FRAME_SIZE
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fade)
	title = Label.new()
	title.z_index = 201
	title.position = Vector2(40, 642)
	title.size = Vector2(1060, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
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
	elapsed = minf(runtime_duration(), elapsed + delta)
	present_frame()
	update_audio()
	if elapsed >= runtime_duration():
		finish()

func _input(event: InputEvent) -> void:
	if ended or (is_instance_valid(display) and display.menu_open): return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F10 or event.physical_keycode == KEY_F10):
		get_viewport().set_input_as_handled()
		if not game.get("economy").developer_mode: game.get("economy").toggle_developer_mode()
		finish()

func runtime_duration() -> float:
	return BREACH_DURATION if breach else DURATION

func present_frame() -> void:
	film.time = elapsed
	film.present()
	title.visible = true
	if breach:
		title.text = "La cerca está cediendo…" if elapsed < 3.0 else "¡Han roto la cerca! Defiende la mina."
	else:
		title.text = "La cerca contiene a los zombis." if elapsed < 4.5 else "Prepara la mina antes de que consigan entrar."
	title.modulate.a = smoothstep(0.4,1.1,elapsed) * (1.0 - smoothstep(runtime_duration()-0.8,runtime_duration(),elapsed))
	fade.color.a = maxf(1.0-smoothstep(0,0.7,elapsed),smoothstep(runtime_duration()-0.6,runtime_duration(),elapsed))
	skip_button.modulate.a = smoothstep(0.6,1.5,elapsed)

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
	ambience.volume_db = -29.0
	if breach and elapsed >= 2.8 and last_blast < 0:
		last_blast = 0
		play_sound(blast_sound,-17,1.1)

func play_sound(stream: AudioStreamWAV, volume: float, pitch: float) -> void:
	for player in sound_players:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume
			player.pitch_scale = pitch
			player.play()
			return


class BarrierCanvas extends Node2D:
	var source_game: Node
	var breach := false
	var time := 0.0
	var world: Node2D
	var renderer: Node2D
	var zone: Node2D
	var barrier: Node2D

	func _ready() -> void:
		world = Node2D.new()
		add_child(world)
		zone = preload("res://Scripts/defense_zone.gd").new()
		zone.setup(source_game.get("grid"))
		zone.set_night(true)
		world.add_child(zone)
		renderer = preload("res://Scripts/world_renderer.gd").new()
		renderer.launchers = source_game.get("launchers")
		renderer.setup(source_game.get("grid"),source_game.get("mining"),source_game.get("conveyors"),source_game.get("drills"))
		world.add_child(renderer)
		var base := preload("res://Scripts/zombie_manager.gd").new()
		base.setup(source_game.get("grid"))
		base.base_health = source_game.get("zombie_manager").base_health
		world.add_child(base)
		base.set_process(false)
		barrier = preload("res://Scripts/tutorial_barrier.gd").new()
		barrier.grid = source_game.get("grid")
		world.add_child(barrier)
		barrier.set_process(false)
		add_child(FilmBars.new())

	func present() -> void:
		var center: float = source_game.get("grid").get_cell_rect(source_game.get("grid").sale_cell).get_center().x
		var focus_y: float = lerpf(-180.0,30.0,smoothstep(0,7,time)) if not breach else lerpf(-140.0,-30.0,smoothstep(1,6,time))
		var zoom: float = 0.9 if not breach else 1.05
		var destruction: float = smoothstep(2,5.5,time) if breach else 0.0
		var shake: Vector2 = Vector2(sin(time*47),cos(time*61)) * sin(destruction * PI) * 4
		world.scale = Vector2.ONE * zoom
		world.position = Vector2(640,325) - Vector2(center,focus_y)*zoom + shake
		barrier.time = time
		barrier.destruction = destruction
		barrier.present()
		renderer.queue_redraw()

class FilmBars extends Node2D:
	func _init() -> void:
		z_index = 100

	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,64),Color.BLACK)
		draw_rect(Rect2(0,638,1280,82),Color.BLACK)
