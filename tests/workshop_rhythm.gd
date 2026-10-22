extends "res://tests/building_controls.gd"

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	mover = game.get_node("WorldInteractions")
	compactors = game.get_node("Compactors")
	compactors.set_process(false)
	var furnace: Node = game.get_node("Furnaces")
	furnace.set_process(false)
	var rhythm: Node = game.get_node("WorkshopRhythm")
	check(rhythm.music.playing and rhythm.tension.playing, "Both musical layers start together")
	check(rhythm.music.stream.loop_end == rhythm.tension.stream.loop_end and rhythm.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Musical layers share the same seamless sixteen-beat loop")
	var stream: AudioStreamWAV = rhythm.music.stream
	check(absf(float(stream.loop_end) / stream.mix_rate - 9.6) < 0.001, "A 100 BPM musical loop matches the existing 0.6 second drill cadence")
	var peak := 0
	var energy := 0.0
	for i in range(0, stream.data.size(), 2):
		var sample := absi(stream.data.decode_s16(i))
		peak = maxi(peak, sample)
		energy += float(sample) * sample
	check(peak > 1000 and peak < 31000 and energy > 0, "Generated score contains audible PCM with clipping headroom")
	check(rhythm.voices.size() == 12 and rhythm.sounds.size() == 10, "The effect pool and ten distinct tool and weapon sounds are available")
	rhythm.set_process(false)
	rhythm.pending.clear()
	var c := Vector2i(14, 2)
	game.mining.place_vein(c, 1)
	game.mining.mine(c)
	check(rhythm.pending.has("mine") and rhythm.impacts.back()["cell"] == c, "A real mining strike produces sound and particles together")
	rhythm.pending.clear()
	check(not game.mining.mine(Vector2i(-1, -1)) and rhythm.pending.is_empty(), "A rejected mining action stays silent")
	for i in range(100): rhythm.feedback("mine", c)
	check(rhythm.pending.size() == 1 and rhythm.impacts.size() <= 64, "Simultaneous actions coalesce and particle count stays bounded")
	rhythm._process(0.01)
	check(rhythm.pending.is_empty() and rhythm.cooldowns.get("mine", 0) > 0, "One grouped strike starts playback and a short rate limit")
	rhythm.request_sound("mine")
	check(rhythm.pending.is_empty(), "Rate limiting prevents loud repeated strikes in one frame")
	clear_items()
	var source := Vector2i(14, 2)
	var target := source + Vector2i.RIGHT
	game.conveyors.place(source, 1)
	game.conveyors.place(target, 1)
	put(source, {"copper": 1})
	rhythm.pending.clear()
	game.conveyors.tick()
	check(rhythm.pending.has("belt") and game.mining.nugget_type(target) == "copper", "Successful conveyor movement triggers its mechanical click")
	var endpoint: Vector2 = game.grid.get_cell_rect(target).get_center()
	check(rhythm.nugget_position(target, "copper", endpoint) == game.grid.get_cell_rect(source).get_center(), "The arriving nugget visually starts at the source of its real transfer")
	check(rhythm.nugget_position(target, "coal", endpoint) == endpoint, "A different resource never inherits an unrelated sliding animation")
	rhythm.pending.clear()
	game.conveyors.tick()
	check(rhythm.pending.is_empty(), "Blocked conveyors do not play fake delivery sounds")
	furnace.place(Vector2i(16, 2), 0)
	furnace.receive(Vector2i(16, 2), "coal_4")
	furnace.receive(Vector2i(16, 2), "copper_4")
	furnace.process_smelting(4)
	check(rhythm.pending.has("finish"), "Finishing a real furnace batch plays a completion chime")
	rhythm.set_process(true)
	await create_timer(0.1).timeout
	var day_mix: float = rhythm.night_mix
	game.cycle.is_night = true
	await create_timer(0.1).timeout
	check(rhythm.night_mix > day_mix, "The horde adds percussion with a smooth mix")
	game.cycle.is_night = false
	var display: CanvasLayer
	for child in game.get_children():
		if child.has_method("toggle_pause_menu"): display = child
	var music_slider: HSlider = display.settings_page.find_child("MusicVolume", true, false)
	var effects_slider: HSlider = display.settings_page.find_child("EffectsVolume", true, false)
	check(music_slider != null and effects_slider != null, "Settings expose separate music and effects controls")
	var old_music: float = rhythm.music_volume
	var old_effects: float = rhythm.effects_volume
	music_slider.value = 0
	effects_slider.value = 0
	await settle()
	check(rhythm.music_volume == 0 and rhythm.effects_volume == 0 and rhythm.music.volume_db <= -80, "Both volume controls can mute audio")
	music_slider.value = old_music * 100
	effects_slider.value = old_effects * 100
	paused = true
	var frozen: float = rhythm.clock
	await create_timer(0.1, true).timeout
	check(rhythm.clock == frozen and not rhythm.can_process() and rhythm.music.stream_paused and rhythm.tension.stream_paused, "Pausing freezes music-driven animations and tool scheduling")
	paused = false
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		clear_items()
		game.mining.place_vein(Vector2i(14, 2), 1)
		game.drills.place(Vector2i(13, 2), 1)
		game.conveyors.place(Vector2i(15, 2), 1)
		compactors.place(Vector2i(16, 2), 0)
		compactors.receive(Vector2i(16, 2), "copper_3")
		compactors.receive(Vector2i(16, 2), "copper_3")
		furnace.place(Vector2i(15, 1), 1)
		furnace.receive(Vector2i(15, 1), "coal_4")
		furnace.receive(Vector2i(15, 1), "copper_4")
		furnace.process_smelting(2)
		await create_timer(3.1).timeout
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/workshop-rhythm.png")
		await create_timer(0.2).timeout
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/workshop-rhythm-next.png")
		stream.save_to_wav("/workspace/.onboarding/display-test/workshop-score.wav")
		display.toggle_pause_menu()
		display.open_settings()
		await settle()
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/workshop-audio-settings.png")
		display.toggle_pause_menu()
	print("RESULT: ", passed, " passed; ", failed, " failed; workshop rhythm")
	game.queue_free()
	await settle()
	await create_timer(0.1).timeout
	quit(0 if failed == 0 else 1)
