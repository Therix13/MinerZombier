extends CanvasLayer
signal finished
const SESSION_KEY: StringName = &"mine_defense_intro_seen"
const FRAME_SIZE := Vector2(1280,720)
const SHOT_DURATION := 8.0
const DURATION := 32.0
const BREACH_DURATION := 9.0
const SHOTS := [
	{"title":"LO QUE DORMÍA BAJO LA MONTAÑA","chapter":"DÍA −9 / EL HALLAZGO","speaker":"MARA · Diario de la mina","text":"Taladramos una cámara sellada bajo la montaña. Aquel resplandor no era un mineral: era una colonia viva, dormida durante siglos."},
	{"title":"EL PROTOCOLO LÁZARO","chapter":"DÍA −8 / LA RUPTURA","speaker":"IVO · Registro de emergencia","text":"La compañía intentó estudiar sus esporas. Una sobrepresión rompió el contenedor y las lanzó a la ventilación del campamento. Los muertos volvieron a moverse."},
	{"title":"LA ÚLTIMA SALIDA","chapter":"DÍA −1 / LA EVACUACIÓN","speaker":"MARA · Mecánica de la mina","text":"Ivo conocía un refugio fuera del circuito contaminado. Sacamos a quienes pudimos mientras los infectados tomaban la superficie. Ya no quedaba otro camino."},
	{"title":"BIENVENIDO AL SECTOR 07","chapter":"DÍA 1 / EL REFUGIO","speaker":"MARA · Canal interno","text":"Este pozo tiene aire independiente, agua y un generador. Sus vetas nos darán metal para fabricar defensas. La compuerta resistirá unas horas. Hasta que llegue ayuda, ésta será nuestra casa."},
]
var breach: bool = false
var replay: bool = false
var elapsed: float = 0
var ended: bool = false
var game: Node
var screen: Control
var frame: Control
var film: Control
var fade: ColorRect
var title: Label
var chapter: Label
var speaker: Label
var subtitle: Label
var skip_button: Button
var next_button: Button
var shot: int = 0
var last_shot: int = -1
var ui_was_visible: bool = true
var game_ui: CanvasLayer
var world_visibility: Dictionary = {}
var previously_paused: bool = false
var owns_pause: bool = false
var players: Array[AudioStreamPlayer] = []
var active_player: int = 0
var audio_tween: Tween

func _ready() -> void:
	game = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 220
	previously_paused = get_tree().paused
	Engine.set_meta(SESSION_KEY,true)
	game_ui = game.get_node_or_null("CanvasLayer")
	if game_ui != null:
		ui_was_visible = game_ui.visible
		game_ui.hide()
	for child: Node in game.get_children():
		if child is CanvasItem and not child is Camera2D:
			world_visibility[child] = child.visible
			child.hide()
	build_screen()
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.volume_db = -80
		add_child(player)
		players.append(player)
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
	black.color = Color("#05090f")
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(black)
	frame = Control.new()
	frame.size = FRAME_SIZE
	frame.clip_contents = true
	screen.add_child(frame)
	film = preload("res://Scripts/cinematic_stage.gd").new()
	film.size = FRAME_SIZE
	frame.add_child(film)
	var column := VBoxContainer.new()
	column.position = Vector2(76,465)
	column.size = Vector2(1128,165)
	column.add_theme_constant_override("separation",10)
	frame.add_child(column)
	chapter = text_label(13,Color("#e9b879"))
	title = text_label(31,Color("#f4eee5"))
	speaker = text_label(14,Color("#aac9d2"))
	subtitle = text_label(20,Color("#e0e2e1"))
	subtitle.custom_minimum_size.x = 1128
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for item: Label in [chapter,title,speaker,subtitle]: column.add_child(item)
	skip_button = game.shop.create_button("Omitir introducción")
	skip_button.position = Vector2(76,650)
	skip_button.size = Vector2(220,36)
	skip_button.custom_minimum_size.y = 36
	skip_button.add_theme_font_size_override("font_size",14)
	skip_button.pressed.connect(finish)
	frame.add_child(skip_button)
	next_button = game.shop.create_button("Siguiente  →")
	next_button.position = Vector2(994,650)
	next_button.size = Vector2(210,36)
	next_button.custom_minimum_size.y = 36
	next_button.add_theme_font_size_override("font_size",14)
	next_button.pressed.connect(next_shot)
	frame.add_child(next_button)
	fade = ColorRect.new()
	fade.size = FRAME_SIZE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color.BLACK
	frame.add_child(fade)

func text_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	return label

func update_layout() -> void:
	screen.size = get_viewport().get_visible_rect().size
	var factor: float = minf(screen.size.x/1280,screen.size.y/720)
	frame.scale = Vector2.ONE*factor
	frame.position = (screen.size-FRAME_SIZE*factor)*.5

func runtime_duration() -> float:
	return BREACH_DURATION if breach else DURATION

func next_shot() -> void:
	if ended: return
	if breach or shot == 3: finish()
	else:
		elapsed = (shot+1)*SHOT_DURATION
		present_frame()

func _process(delta: float) -> void:
	if ended: return
	var display: Node = game.get("display_settings")
	var menu_open: bool = display != null and display.menu_open
	for player: AudioStreamPlayer in players: player.stream_paused = menu_open
	if menu_open: return
	elapsed = minf(runtime_duration(),elapsed+delta/maxf(.001,Engine.time_scale))
	present_frame()
	if elapsed >= runtime_duration(): finish()

func present_frame() -> void:
	shot = 2 if breach else clampi(int(elapsed/SHOT_DURATION),0,3)
	var local_time: float = elapsed if breach else fmod(elapsed,SHOT_DURATION)
	film.shot = shot
	film.time = local_time
	film.progress = local_time/(BREACH_DURATION if breach else SHOT_DURATION)
	film.present()
	var entry: Dictionary = SHOTS[shot]
	chapter.text = "22:00 / LA PRIMERA HORDA" if breach else entry["chapter"]
	title.text = "LA COMPUERTA ESTÁ CEDIENDO" if breach else entry["title"]
	speaker.text = "IVO · Canal de defensa" if breach else entry["speaker"]
	subtitle.text = "Las vibraciones de la maquinaria los han guiado hasta nosotros. ¡La puerta exterior ha caído! Mantén las torretas cargadas y protege la entrada." if breach else entry["text"]
	subtitle.visible_ratio = clampf(local_time/1.0,0,1)
	var opacity: float = smoothstep(.25,.9,local_time)
	for label: Label in [title,chapter,speaker,subtitle]: label.modulate.a = opacity
	fade.color.a = maxf(1-smoothstep(0,.7,local_time),smoothstep((BREACH_DURATION if breach else SHOT_DURATION)-.45,(BREACH_DURATION if breach else SHOT_DURATION),local_time))
	next_button.text = "Entrar a la mina  →" if shot == 3 else ("Defender  →" if breach else "Siguiente  →")
	if last_shot != shot:
		last_shot = shot
		crossfade_audio(shot)

func crossfade_audio(index: int) -> void:
	if players.is_empty(): return
	if audio_tween != null: audio_tween.kill()
	var previous: AudioStreamPlayer = players[active_player]
	active_player = 1-active_player
	var next: AudioStreamPlayer = players[active_player]
	next.stream = preload("res://Scripts/cinematic_audio.gd").score(index)
	next.volume_db = -48
	next.play()
	var volume: float = .45
	if game.get_node_or_null("WorkshopRhythm") != null: volume = game.get_node("WorkshopRhythm").music_volume
	var target: float = linear_to_db(maxf(volume,.0001))-7
	audio_tween = create_tween().set_parallel(true)
	audio_tween.tween_property(previous,"volume_db",-80,.6)
	audio_tween.tween_property(next,"volume_db",target,.6)

func _input(event: InputEvent) -> void:
	if ended: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			if not game.economy.developer_mode: game.economy.toggle_developer_mode()
			finish()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			finish()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER]:
			next_shot()
			get_viewport().set_input_as_handled()

func finish() -> void:
	if ended: return
	ended = true
	if not breach and game.get("campaign") != null:
		if not game.campaign.state.has("story_seen"): game.campaign.state["story_seen"] = {}
		game.campaign.state["story_seen"]["origin"] = true
	restore_game()
	if not breach and not replay:
		var saves: Node = game.get_node_or_null("SaveGame")
		if saves != null and saves.playing and not saves.loaded_game: saves.capture_day_start()
	finished.emit()
	queue_free()

func restore_game() -> void:
	if not owns_pause: return
	owns_pause = false
	for item: CanvasItem in world_visibility:
		if is_instance_valid(item): item.visible = world_visibility[item]
	world_visibility.clear()
	if is_instance_valid(game_ui): game_ui.visible = ui_was_visible
	var display: Node = game.get("display_settings")
	if display != null and display.menu_open: display.previously_paused = previously_paused
	else: get_tree().paused = previously_paused
	var guide: Node = game.get_node_or_null("TutorialGuide")
	if guide != null: guide.focus_objective.call_deferred()

func _exit_tree() -> void:
	if audio_tween != null: audio_tween.kill()
	for player: AudioStreamPlayer in players: player.stop()
	restore_game()
