extends CanvasLayer

const SCENES := {
	"origin":{"title":"SECTOR 07 / ÚLTIMA TRANSMISIÓN","speaker":"MARA · Operadora de la mina","text":"La superficie dejó de responder hace nueve días. Bajo nosotros queda energía para mantener el refugio. Extrae, fabrica y conserva la entrada: aún hay gente ahí fuera.","chapter":"01 · LA SEÑAL","boss":""},
	"industry":{"title":"EL ARCHIVO DE COBRE","speaker":"IVO · Ingeniero desaparecido","text":"Las criaturas siguen las vibraciones de la veta. El nitrato no era nuestro descubrimiento: era su alimento. Dejé los planos de munición en el taller. No vuelvas a abrir el pozo central.","chapter":"02 · ECOS BAJO TIERRA","boss":""},
	"plague":{"title":"SILENCIO EN LA COLONIA","speaker":"MARA · Registro recuperado","text":"El Rey de la Plaga cae y la nube se dispersa. En su arnés encontramos una placa de la expedición original. No vinieron de fuera. La infección empezó aquí.","chapter":"ARCHIVO 03 / REY DE LA PLAGA","boss":"plague"},
	"warden":{"title":"LA ÚLTIMA GUARDIA","speaker":"IVO · Mensaje cifrado","text":"El blindaje del Carcelero se rompe. Durante años custodió una puerta que nadie debía cruzar. Su llave aún funciona. Al fondo del túnel, alguien responde a nuestra señal.","chapter":"ARCHIVO 04 / EL CARCELERO","boss":"warden"},
	"broodmother":{"title":"EL CORAZÓN CALLA","speaker":"MARA · Canal de emergencia","text":"Los filamentos de la Madre se apagan uno tras otro. Los enjambres pierden su enlace. El mapa grabado bajo su caparazón señala una cámara anterior a la mina.","chapter":"ARCHIVO 05 / MADRE DE LA COLMENA","boss":"broodmother"},
	"executor":{"title":"NO ERA EL FINAL","speaker":"IVO · Transmisión en directo","text":"El Ejecutor cae de rodillas. Su núcleo revela el origen de la señal: supervivientes al otro lado del yacimiento. La mina ya no es sólo nuestro refugio. Es el camino hacia ellos.","chapter":"ARCHIVO 06 / EL EJECUTOR","boss":"executor"},
	"frontier":{"title":"UN CAMINO A LA SUPERFICIE","speaker":"MARA · Diario del refugio","text":"La galería está abierta y nuestra señal cruza la montaña. Cada noche ganada trae otra respuesta. Mantendremos las luces encendidas hasta que todos encuentren el camino.","chapter":"EPÍLOGO / LA ÚLTIMA FRONTERA","boss":""},
}
var game: Node
var pending: Array[String] = []
var active: String = ""
var backdrop: ColorRect
var overlay: Control
var film: Film
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
	film = Film.new()
	film.scene_data = SCENES[id]
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(film)
	var panel := VBoxContainer.new()
	panel.position = Vector2(100,430)
	panel.size = Vector2(1080,220)
	panel.add_theme_constant_override("separation",13)
	overlay.add_child(panel)
	panel.add_child(game.shop.create_label(SCENES[id]["chapter"],14,Color("#6ee7ce")))
	panel.add_child(game.shop.create_label(SCENES[id]["title"],30,Color("#e2edf5")))
	panel.add_child(game.shop.create_label(SCENES[id]["speaker"],15,Color("#91a9bf")))
	var body: Label = game.shop.create_label(SCENES[id]["text"],19,Color("#cad8e7"))
	body.custom_minimum_size.x = 1080
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
	if active.is_empty() or closing or elapsed < 1: return
	closing = true
	elapsed = 0
	continue_button.disabled = true

func _process(delta: float) -> void:
	var dt: float = delta/maxf(.001,Engine.time_scale)
	if not active.is_empty():
		elapsed += dt
		film.time += dt
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
		enqueue("origin")
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

class Film extends Control:
	var scene_data: Dictionary
	var time: float = 0
	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,720),Color("#0c1522"))
		for index in range(6):
			var offset: float = fmod(time*5+index*85,520)
			draw_arc(Vector2(640,205),offset,PI*.1,PI*.9,80,Color("#273c50"),1,true)
		var art = preload("res://Scripts/content_art.gd")
		var boss: String = scene_data["boss"]
		if boss.is_empty():
			for side in [-1,1]:
				draw_line(Vector2(640+side*150,340),Vector2(640+side*80,100),Color("#405b71"),4,true)
				draw_line(Vector2(640+side*142,340),Vector2(640+side*74,100),Color("#6ee7ce"),1.5,true)
			art.vein(self,Vector2(640,245),"copper",0,4)
			draw_arc(Vector2(640,200),65,0,minf(TAU,time*.8),80,Color("#6ee7ce"),2,true)
		else:
			var fall: float = smoothstep(.8,3.2,time)
			var color := Color("#efaa84") if boss in ["warden","executor"] else Color("#9bdac4")
			var at := Vector2(640,205+fall*55)
			draw_set_transform(at,fall*.4,Vector2.ONE*(3-fall*.7))
			draw_circle(Vector2.ZERO,24,Color("#24384d"),true,-1,true)
			draw_arc(Vector2.ZERO,24,0,TAU,60,color,2,true)
			draw_circle(Vector2(0,-22),13,color,true,-1,true)
			for side in [-1,1]: draw_line(Vector2(side*17,0),Vector2(side*(22+fall*10),25),color,7,true)
			if boss in ["warden","executor"]:
				draw_rect(Rect2(-19,-5,38,20),Color("#7a91a8"))
				draw_line(Vector2(-13,0),Vector2(13,15),Color("#efaa84"),2,true)
			else:
				for i in range(4): draw_circle(Vector2(-15+i*10,12),4,Color("#6ee7ce"),true,-1,true)
			if boss == "warden":
				for sign_value in [-1,1]:
					draw_line(Vector2(sign_value*(8+fall*20),-10),Vector2(sign_value*(15+fall*30),15+fall*10),Color("#a3c7de"),7,true)
			elif boss == "executor":
				for sign_value in [-1,1]:
					draw_line(Vector2(sign_value*23,-2),Vector2(sign_value*33,25+fall*16),Color("#efaa84"),4,true)
					draw_rect(Rect2(sign_value*33-8,18+fall*16,16,10),Color("#a3c7de"))
			elif boss == "plague":
				for i in range(5):
					draw_line(Vector2(-12+i*6,-33),Vector2(-12+i*6,-40+fall*15),Color("#a3dac4"),3,true)
					draw_circle(Vector2(-16+i*8,-5-fall*15),3,Color(0.43,0.9,0.81,1-fall*.8),true,-1,true)
			elif boss == "broodmother":
				for i in range(6):
					var ray := Vector2.RIGHT.rotated(i*TAU/6)
					draw_line(ray*20,ray*(36+fall*20),Color("#a3dac4"),2,true)
					draw_circle(ray*(36+fall*20),4,Color("#76b7a6"),true,-1,true)
			draw_set_transform(Vector2.ZERO)
			for i in range(16):
				var direction := Vector2.RIGHT.rotated(i*TAU/16)
				draw_circle(at+direction*(25+fall*110),2,Color(color,1-fall*.8),true,-1,true)
			draw_line(Vector2(500,340),Vector2(780,340),Color("#405b71"),1,true)
		draw_line(Vector2(100,400),Vector2(1180,400),Color("#2e455b"),1,true)
