extends CanvasLayer

const SCENES := {
	"origin":{"shot":3,"title":"SECTOR 07 / ÚLTIMA TRANSMISIÓN","speaker":"MARA · Operadora de la mina","text":"Mara e Ivo escapan del campamento cuando el Protocolo Lázaro libera las esporas de una colonia subterránea. El Sector 07, aislado de la ventilación contaminada, conserva agua, energía y minerales para defender a los supervivientes.","chapter":"01 · LA SEÑAL","boss":""},
	"industry":{"shot":1,"title":"EL ARCHIVO DE COBRE","speaker":"IVO · Ingeniero desaparecido","text":"Las criaturas siguen las vibraciones de la veta. El nitrato no era nuestro descubrimiento: era su alimento. Dejé los planos de munición en el taller. No vuelvas a abrir el pozo central.","chapter":"02 · ECOS BAJO TIERRA","boss":""},
	"plague":{"shot":0,"title":"SILENCIO EN LA COLONIA","speaker":"MARA · Registro recuperado","text":"El Rey de la Plaga cae y la nube se dispersa. En su arnés encontramos una placa de la expedición original. No vinieron de fuera. La infección empezó aquí.","chapter":"ARCHIVO 03 / REY DE LA PLAGA","boss":"plague"},
	"warden":{"shot":3,"title":"LA ÚLTIMA GUARDIA","speaker":"IVO · Mensaje cifrado","text":"El blindaje del Carcelero se rompe. Durante años custodió una puerta que nadie debía cruzar. Su llave aún funciona. Al fondo del túnel, alguien responde a nuestra señal.","chapter":"ARCHIVO 04 / EL CARCELERO","boss":"warden"},
	"broodmother":{"shot":0,"title":"EL CORAZÓN CALLA","speaker":"MARA · Canal de emergencia","text":"Los filamentos de la Madre se apagan uno tras otro. Los enjambres pierden su enlace. El mapa grabado bajo su caparazón señala una cámara anterior a la mina.","chapter":"ARCHIVO 05 / MADRE DE LA COLMENA","boss":"broodmother"},
	"executor":{"shot":2,"title":"NO ERA EL FINAL","speaker":"IVO · Transmisión en directo","text":"El Ejecutor cae de rodillas. Su núcleo revela el origen de la señal: supervivientes al otro lado del yacimiento. La mina ya no es sólo nuestro refugio. Es el camino hacia ellos.","chapter":"ARCHIVO 06 / EL EJECUTOR","boss":"executor"},
	"frontier":{"shot":3,"title":"UN CAMINO A LA SUPERFICIE","speaker":"MARA · Diario del refugio","text":"La galería está abierta y nuestra señal cruza la montaña. Cada noche ganada trae otra respuesta. Mantendremos las luces encendidas hasta que todos encuentren el camino.","chapter":"EPÍLOGO / LA ÚLTIMA FRONTERA","boss":""},
}
var game: Node
var pending: Array[String] = []
var active: String = ""
var backdrop: ColorRect
var overlay: Control
var film: Control
var sequence: CanvasLayer
var elapsed: float = 0
var closing: bool = false
var previous_pause: bool = false
var continue_button: Button

func _ready() -> void:
	game = get_parent()
	layer = 210
	process_mode = Node.PROCESS_MODE_ALWAYS
	game.zombie_manager.enemy_killed.connect(on_kill)
	get_viewport().size_changed.connect(layout)

func seen() -> Dictionary:
	if not game.campaign.state.has("story_seen"): game.campaign.state["story_seen"] = {}
	return game.campaign.state["story_seen"]

func enqueue(id: String) -> void:
	if SCENES.has(id) and not seen().has(id) and id not in pending and active != id: pending.append(id)

func on_kill(kind: String) -> void:
	if kind in ["plague","warden","broodmother","executor"]: enqueue(kind)

func play(id: String) -> void:
	if not active.is_empty() or not SCENES.has(id): return
	active = id
	seen()[id] = true
	if id == "origin":
		previous_pause = get_tree().paused
		sequence = preload("res://Scripts/intro_cinematic.gd").new()
		sequence.replay = true
		sequence.name = "OriginReplay"
		sequence.finished.connect(func(): sequence = null; active = "")
		game.add_child(sequence)
		return
	previous_pause = get_tree().paused
	get_tree().paused = true
	elapsed = 0
	closing = false
	backdrop = ColorRect.new()
	backdrop.color = Color("#0c1522")
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	film = preload("res://Scripts/cinematic_stage.gd").new()
	film.scene_data = SCENES[id]
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(film)
	var panel := VBoxContainer.new()
	panel.position = Vector2(76,450)
	panel.size = Vector2(1128,195)
	panel.add_theme_constant_override("separation",13)
	overlay.add_child(panel)
	panel.add_child(game.shop.create_label(SCENES[id]["chapter"],14,Color("#6ee7ce")))
	panel.add_child(game.shop.create_label(SCENES[id]["title"],30,Color("#e2edf5")))
	panel.add_child(game.shop.create_label(SCENES[id]["speaker"],15,Color("#91a9bf")))
	var body: Label = game.shop.create_label(SCENES[id]["text"],19,Color("#cad8e7"))
	body.custom_minimum_size.x = 1128
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(body)
	continue_button = game.shop.create_button("Continuar  →")
	continue_button.position = Vector2(950,655)
	continue_button.size = Vector2(230,44)
	continue_button.pressed.connect(finish)
	overlay.add_child(continue_button)
	layout()
	backdrop.modulate.a = 0
	overlay.modulate.a = 0

func layout() -> void:
	if overlay == null: return
	var area: Vector2 = get_viewport().get_visible_rect().size
	backdrop.size = area
	var factor: float = minf(area.x/1280,area.y/720)
	overlay.size = Vector2(1280,720)
	overlay.scale = Vector2.ONE*factor
	overlay.position = (area-overlay.size*factor)*.5
	film.size = Vector2(1280,720)

func finish() -> void:
	if is_instance_valid(sequence):
		sequence.finish()
		return
	if active.is_empty() or closing or elapsed < 1: return
	closing = true
	elapsed = 0
	continue_button.disabled = true

func _process(delta: float) -> void:
	if is_instance_valid(sequence): return
	var dt: float = delta/maxf(.001,Engine.time_scale)
	if not active.is_empty():
		elapsed += dt
		film.time += dt
		film.progress = clampf(film.time/9,0,1)
		film.queue_redraw()
		backdrop.modulate.a = clampf(1-elapsed if closing else elapsed,0,1)
		overlay.modulate.a = clampf(1-elapsed if closing else elapsed,0,1)
		if closing and elapsed >= 1:
			backdrop.queue_free()
			overlay.queue_free()
			overlay = null
			active = ""
			get_tree().paused = previous_pause
		return
	var saves: Node = game.get_node_or_null("SaveGame")
	if saves == null or saves.test_mode or not saves.playing or get_tree().paused or game.cycle.defeated or game.get_node_or_null("IntroCinematic") != null or (game.night_victory_overlay.visible and pending.is_empty()) or game.shop.unlock_notice_backdrop.visible or game.display_settings.auto_click_prompt.visible: return
	if not game.economy.developer_mode:
		if game.progression.is_item_unlocked("nitrate"): enqueue("industry")
		if game.campaign.state["best_night"] >= 600: enqueue("frontier")
	if not pending.is_empty(): play(pending.pop_front())

func _input(event: InputEvent) -> void:
	if not active.is_empty() and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE,KEY_ENTER,KEY_ESCAPE]:
			finish()
			get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if not active.is_empty(): get_tree().paused = previous_pause
