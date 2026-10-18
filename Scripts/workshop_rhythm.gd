extends Node2D

# Original procedural score: one clock for percussion, bass and tuned machinery.
const BPM := 100.0
const BEAT := 60.0 / BPM
const RATE := 22050
const LOOP_BEATS := 16
const DIRECTIONS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
var game: Node2D
var clock := 0.0
var music_volume := 0.45
var effects_volume := 0.65
var music: AudioStreamPlayer
var tension: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var cooldowns: Dictionary = {}
var impacts: Array[Dictionary] = []
var pending: Dictionary = {}
var machine_beat := -1
var night_mix := 0.0

func _ready() -> void:
	game = get_parent()
	z_index = 2
	var config := ConfigFile.new()
	if config.load("user://workshop_audio.cfg") == OK:
		music_volume = clampf(float(config.get_value("audio", "music", music_volume)), 0, 1)
		effects_volume = clampf(float(config.get_value("audio", "effects", effects_volume)), 0, 1)
	music = make_player(make_score(false))
	tension = make_player(make_score(true))
	for kind in ["mine", "belt", "press", "fire", "finish", "shot", "sale"]:
		sounds[kind] = make_effect(kind)
	for i in range(12): voices.append(make_player(null))
	game.get("mining").struck.connect(on_struck)
	game.get_node("Saws").cut.connect(func(cell: Vector2i): feedback("finish", cell))
	game.get_node("Construction").completed.connect(func(cell: Vector2i): feedback("finish", cell))
	game.get("mining").vein_fused.connect(func(cell: Vector2i): feedback("finish", cell))
	game.get("conveyors").transported.connect(on_transport)
	game.get("launchers").fired.connect(func(cell: Vector2i): feedback("shot", cell))
	game.get("mining").fusion_completed.connect(func(_kind: String): request_sound("finish"))
	game.get("mining").sale_completed.connect(func(_kind: String): request_sound("sale"))
	game.get("conveyors").sale_completed.connect(func(_kind: String): request_sound("sale"))
	game.get_node("Furnaces").smelted.connect(func(cell: Vector2i): feedback("finish", cell))
	music.volume_db = linear_to_db(maxf(music_volume, 0.0001)) - 8.0
	tension.volume_db = -80
	music.play()
	tension.play()
	install_controls.call_deferred()

func _exit_tree() -> void:
	for player in [music, tension] + voices:
		if not is_instance_valid(player): continue
		player.stop()
		player.stream = null
	sounds.clear()

func make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player

func wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()): bytes.encode_s16(i * 2, int(clampf(samples[i], -0.95, 0.95) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream

func note(samples: PackedFloat32Array, start: float, duration: float, frequency: float, gain: float, kind: int, rng: RandomNumberGenerator) -> void:
	var first := int(start * RATE)
	for j in range(int(duration * RATE)):
		var t := float(j) / RATE
		var envelope := minf(t * 250.0, 1.0) * exp(-t * (9.0 if kind == 0 else 20.0)) * clampf((duration - t) * 150.0, 0, 1)
		var tone := sin(TAU * frequency * t) + 0.25 * sin(TAU * frequency * 2.0 * t)
		if kind == 1: tone = sin(TAU * (48.0 * t + 5.0 * (1.0 - exp(-t * 25.0))))
		if kind == 2: tone = rng.randf_range(-1, 1) * 0.75 + sin(TAU * 180.0 * t) * 0.25
		if kind == 3: tone = rng.randf_range(-1, 1) * sin(TAU * 4200 * t)
		var index := first + j
		# Wrap note tails across the loop boundary to avoid a seam.
		samples[index % samples.size()] += tone * envelope * gain

func make_score(dark: bool) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(LOOP_BEATS * BEAT * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7021
	var roots := [110.0, 87.307, 130.813, 97.999]
	var melody := [0, 7, 12, 7, 3, 7, 15, 10]
	for beat in range(LOOP_BEATS):
		var at := beat * BEAT
		var root_note: float = roots[beat / 4]
		if dark:
			if beat % 2 == 0: note(samples, at, 0.3, 55, 0.23, 1, rng)
			if beat % 4 == 2: note(samples, at, 0.15, 180, 0.12, 2, rng)
			note(samples, at + BEAT * 0.5, 0.055, 3000, 0.035, 3, rng)
		else:
			note(samples, at, 0.48, root_note, 0.22, 0, rng)
			if beat % 4 in [0, 2]: note(samples, at, 0.22, 55, 0.20, 1, rng)
			if beat % 4 in [1, 3]: note(samples, at, 0.09, 180, 0.075, 2, rng)
			for half in range(2):
				note(samples, at + half * BEAT * 0.5, 0.07, 3000, 0.025, 3, rng)
				var pitch: float = root_note * 2 * pow(2, float(melody[(beat * 2 + half) % 8]) / 12.0)
				note(samples, at + half * BEAT * 0.5, 0.32, pitch, 0.085 if half == 0 else 0.055, 0, rng)
	return wav(samples, true)

func make_effect(kind: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(RATE * 0.36))
	var rng := RandomNumberGenerator.new()
	rng.seed = 199
	match kind:
		"mine":
			note(samples, 0, 0.1, 220, 0.5, 2, rng)
			note(samples, 0, 0.2, 440, 0.15, 0, rng)
		"belt": note(samples, 0, 0.07, 330, 0.25, 2, rng)
		"press":
			note(samples, 0, 0.2, 55, 0.55, 1, rng)
			note(samples, 0.04, 0.12, 220, 0.2, 2, rng)
		"fire": note(samples, 0, 0.13, 4000, 0.12, 3, rng)
		"shot":
			note(samples, 0, 0.16, 55, 0.6, 1, rng)
			note(samples, 0, 0.07, 180, 0.3, 2, rng)
		"finish", "sale":
			note(samples, 0, 0.22, 660, 0.32, 0, rng)
			note(samples, 0.09, 0.25, 880, 0.24, 0, rng)
	return wav(samples)

func request_sound(kind: String) -> void:
	# Coalesce simultaneous factory actions; twelve drills never become twelve loud hits.
	if float(cooldowns.get(kind, 0.0)) <= 0: pending[kind] = true

func feedback(kind: String, cell: Vector2i) -> void:
	if impacts.size() < 64: impacts.append({"cell": cell, "age": 0.0, "kind": kind})
	request_sound(kind)

func on_struck(cell: Vector2i) -> void:
	feedback("mine", cell)

func on_transport(source: Vector2i, destination: Vector2i, kind: String) -> void:
	feedback("belt", destination)
	# A short moving glint follows the actual successful transfer.
	if impacts.size() >= 64: impacts.pop_front()
	impacts.append({"cell": source, "to": destination, "age": 0.0, "kind": "transfer", "material": kind})

func _process(delta: float) -> void:
	if game.get("cycle").defeated:
		music.stream_paused = true
		tension.stream_paused = true
		pending.clear()
		return
	clock = maxf(0.0, music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	night_mix = move_toward(night_mix, 1.0 if game.get("cycle").is_night else 0.0, delta * 0.5)
	music.volume_db = linear_to_db(maxf(music_volume, 0.0001)) - 8.0
	tension.volume_db = linear_to_db(maxf(music_volume * night_mix, 0.0001)) - 10.0
	for kind: String in cooldowns: cooldowns[kind] = maxf(0, float(cooldowns[kind]) - delta)
	for i in range(impacts.size() - 1, -1, -1):
		impacts[i]["age"] += delta
		if impacts[i]["age"] >= 0.35:
			impacts.remove_at(i)
			game.get("renderer").queue_redraw()
	var beat := int(clock / BEAT)
	if beat != machine_beat:
		machine_beat = beat
		for cell: Vector2i in game.get_node("Compactors").machines:
			var data: Dictionary = game.get_node("Compactors").machines[cell]
			if int(data["count"]) == 2 and float(data["elapsed"]) < 4: request_sound("press")
		for cell: Vector2i in game.get_node("Furnaces").machines:
			if game.get_node("Furnaces").machines[cell].get("burning", false): request_sound("fire")
	for kind: String in pending:
		for voice in voices:
			if voice.playing: continue
			voice.stream = sounds[kind]
			voice.volume_db = linear_to_db(maxf(effects_volume, 0.0001)) - 12.0
			voice.play()
			cooldowns[kind] = 0.08 if kind in ["mine", "shot"] else 0.15
			break
	pending.clear()
	queue_redraw()
	if not impacts.is_empty(): game.get("renderer").queue_redraw()

func nugget_position(cell: Vector2i, kind: String, target: Vector2) -> Vector2:
	for impact: Dictionary in impacts:
		if impact.get("to") != cell or impact.get("material") != kind: continue
		var from: Vector2 = game.get("grid").get_cell_rect(impact["cell"]).get_center()
		var progress: float = clampf(float(impact["age"]) / 0.3, 0, 1)
		return from.lerp(target, progress * progress * (3 - 2 * progress))
	return target

func _draw() -> void:
	if game == null: return
	var grid: RefCounted = game.get("grid")
	for cell: Vector2i in game.get("drills").drills:
		if hidden_for_drag(cell): continue
		var direction: int = game.get("drills").drills[cell]
		if game.get("mining").vein_at(cell + Vector2i(DIRECTIONS[direction])) == "": continue
		var center: Vector2 = grid.get_cell_rect(cell).get_center()
		var angle: float = clock / BEAT * TAU
		var push: Vector2 = DIRECTIONS[direction] * (1 + sin(angle) * 1.5)
		draw_arc(center + push, 7, angle, angle + PI * 1.4, 12, Color("#e9ca7b"), 2)
	for cell: Vector2i in game.get("conveyors").belts:
		if hidden_for_drag(cell): continue
		var center: Vector2 = grid.get_cell_rect(cell).get_center()
		var direction: Vector2 = DIRECTIONS[game.get("conveyors").belt_direction(cell)]
		var side := Vector2(-direction.y, direction.x)
		for i in range(3):
			var offset: float = fmod(clock / BEAT * 5 + i * 10, 30) - 15
			var pos := center + direction * offset
			draw_line(pos + side * 12, pos + side * 15, Color("#d3ad6d"), 1.5)
	for cell: Vector2i in game.get_node("Compactors").machines:
		if hidden_for_drag(cell): continue
		var data: Dictionary = game.get_node("Compactors").machines[cell]
		if int(data["count"]) != 2 or float(data["elapsed"]) >= 4: continue
		var center: Vector2 = grid.get_cell_rect(cell).get_center()
		var gap: float = 6 - 3 * cos(clock / BEAT * TAU)
		for sign_value in [-1, 1]: draw_rect(Rect2(center + Vector2(-12, gap * sign_value - 1), Vector2(24, 3)), Color("#e2bd70"))
	for cell: Vector2i in game.get_node("Furnaces").machines:
		if hidden_for_drag(cell): continue
		if not game.get_node("Furnaces").machines[cell].get("burning", false): continue
		var center: Vector2 = grid.get_cell_rect(cell).get_center()
		for i in range(3):
			var height: float = 4 + 4 * (0.5 + 0.5 * sin(clock * 17 + i * 2))
			draw_line(center + Vector2(-7 + 7 * i, 9), center + Vector2(-7 + 7 * i, 9 - height), Color("#ffd17b"), 2)
		for i in range(2):
			var phase: float = fmod(clock * 0.8 + i * 0.5, 1)
			draw_circle(center + Vector2(sin(clock + i) * 3, -23 - phase * 10), 1 + phase, Color(0.45, 0.38, 0.3, (1 - phase) * 0.4))
	for impact: Dictionary in impacts:
		var center: Vector2 = grid.get_cell_rect(impact["cell"]).get_center()
		var progress: float = float(impact["age"]) / 0.35
		var color := Color(1, 0.79, 0.39, 1 - progress)
		if impact["kind"] == "transfer":
			draw_circle(center.lerp(grid.get_cell_rect(impact["to"]).get_center(), progress), 2, color)
		else:
			for i in range(4):
				var radial := Vector2.from_angle(i * TAU / 4 + 0.4)
				var pos := center + radial * (8 + progress * 12)
				draw_line(pos, pos + radial * 3, color, 1.5)

func hidden_for_drag(cell: Vector2i) -> bool:
	return game.get("dragging_object") and game.get("held_object_cell") == cell

func install_controls() -> void:
	for child in game.get_children():
		if not child is CanvasLayer or not child.has_method("toggle_pause_menu"): continue
		var page: VBoxContainer = child.settings_page
		var heading := page.get_child(0) as Label
		if heading != null: heading.text = "AJUSTES"
		for kind in ["music", "effects"]:
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = "Música" if kind == "music" else "Efectos"
			label.custom_minimum_size.x = 90
			row.add_child(label)
			var slider := HSlider.new()
			slider.name = "MusicVolume" if kind == "music" else "EffectsVolume"
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.max_value = 100
			slider.value = (music_volume if kind == "music" else effects_volume) * 100
			slider.value_changed.connect(func(value: float): set_volume(kind, value / 100.0))
			row.add_child(slider)
			page.add_child(row)
			page.move_child(row, page.get_child_count() - 2)
		break

func set_volume(kind: String, value: float) -> void:
	if kind == "music": music_volume = clampf(value, 0, 1)
	else: effects_volume = clampf(value, 0, 1)
	music.volume_db = linear_to_db(maxf(music_volume, 0.0001)) - 8.0
	tension.volume_db = linear_to_db(maxf(music_volume * night_mix, 0.0001)) - 10.0
	for voice in voices: voice.volume_db = linear_to_db(maxf(effects_volume, 0.0001)) - 12.0
	var config := ConfigFile.new()
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.save("user://workshop_audio.cfg")
