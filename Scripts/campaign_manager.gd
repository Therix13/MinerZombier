extends CanvasLayer

const Catalog = preload("res://Scripts/content_catalog.gd")
var game: Node2D
const INITIAL_STATE := {"kills":0,"bosses":0,"flawless":0,"best_night":0,"crafted":{},"achievements":{},"job":{},"health_at_dusk":100.0,"elapsed_play":0.0,"repeat_recipe":""}
var state: Dictionary = INITIAL_STATE.duplicate(true)
var hud: Button
var overlay: Control
var page: VBoxContainer
var status_label: Label
var toast: Label
var toast_time: float = 0
var previous_pause: bool = false
var selected_tab: String = "Campaña"
var refresh_timer: float = 0

func _ready() -> void:
	game = get_parent()
	for kind: String in game.mining.EXTRA_KINDS: preload("res://Scripts/content_art.gd").resource_texture(kind)
	layer = 190
	process_mode = Node.PROCESS_MODE_ALWAYS
	game.zombie_manager.enemy_killed.connect(record_kill)
	game.zombie_manager.wave_started.connect(func(): state["health_at_dusk"] = game.zombie_manager.base_health)
	build_ui()
	game.progression.changed.connect(check_achievements)

func total(kind: String) -> int:
	var result: int = 0
	for value: int in game.mining.items_for(kind).values(): result += value
	return result

func available(cost: Dictionary) -> bool:
	for kind: String in cost:
		if total(kind) < int(cost[kind]): return false
	return true

func consume(cost: Dictionary) -> void:
	for kind: String in cost:
		var left: int = cost[kind]
		var store: Dictionary = game.mining.items_for(kind)
		for cell: Vector2i in store.keys():
			var used: int = mini(left,store[cell])
			store[cell] -= used
			left -= used
			if store[cell] == 0: store.erase(cell)
			if left == 0: break
	game.mining.changed.emit()

func output_cell(kind: String, count: int) -> Vector2i:
	for cell: Vector2i in game.mining.items_for(kind):
		if int(game.mining.items_for(kind)[cell]) + count <= 1000: return cell
	for cell: Vector2i in game.grid.owned_tiles:
		if game.mining.can_move_nugget(cell): return cell
	return Vector2i(-999,-999)

func can_craft(kind: String) -> bool:
	return Catalog.CRAFTS.has(kind) and game.progression.is_item_unlocked(kind) and available(Catalog.CRAFTS[kind]["cost"]) and state["job"].is_empty() and not game.cycle.defeated and output_cell(kind,Catalog.CRAFTS[kind]["yield"]).x != -999

func craft(kind: String) -> bool:
	if not can_craft(kind): return false
	consume(Catalog.CRAFTS[kind]["cost"])
	state["job"] = {"kind":kind,"elapsed":0.0}
	return true

func advance_workshop(delta: float) -> void:
	if state["job"].is_empty():
		if not str(state["repeat_recipe"]).is_empty(): craft(state["repeat_recipe"])
		return
	var job: Dictionary = state["job"]
	var recipe: Dictionary = Catalog.CRAFTS[job["kind"]]
	job["elapsed"] = minf(recipe["time"],float(job["elapsed"]) + delta)
	if float(job["elapsed"]) < float(recipe["time"]): return
	var cell: Vector2i = output_cell(job["kind"],recipe["yield"])
	if cell.x == -999: return
	var store: Dictionary = game.mining.items_for(job["kind"])
	store[cell] = int(store.get(cell,0)) + int(recipe["yield"])
	state["crafted"][job["kind"]] = int(state["crafted"].get(job["kind"],0)) + int(recipe["yield"])
	game.mining.resource_created.emit(job["kind"])
	state["job"] = {}
	game.mining.changed.emit()
	check_achievements()

func record_kill(kind: String) -> void:
	state["kills"] += 1
	if kind in ["plague","warden","broodmother","executor"]: state["bosses"] += 1
	check_achievements()

func finish_night(day: int) -> void:
	state["best_night"] = maxi(state["best_night"],day)
	if game.zombie_manager.base_health >= float(state["health_at_dusk"]): state["flawless"] += 1
	# Rewards pay for repairs and supply growth; they do not multiply with kills or loads.
	game.economy.add(mini(15000,100 + day * 40))
	check_achievements()

func achievements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for count in [10,100,1000,10000,100000]: result.append({"id":"kills_%d" % count,"name":"Elimina %d zombis" % count,"current":state["kills"],"target":count})
	for night in [1,2,5,10,25,50,100,200,400,600,900]: result.append({"id":"night_%d" % night,"name":"Supera la noche %d" % night,"current":state["best_night"],"target":night})
	for kind: String in Catalog.CRAFTS:
		for count in [1,100,1000]: result.append({"id":kind + "_%d" % count,"name":"Fabrica %d · %s" % [count,Catalog.LABELS[kind]],"current":state["crafted"].get(kind,0),"target":count})
	for metric: String in ["bosses","flawless"]:
		for count in [1,10,100]: result.append({"id":metric + "_%d" % count,"name":("Vence %d jefes" if metric == "bosses" else "Supera %d noches sin daño") % count,"current":state[metric],"target":count})
	for item: String in Catalog.UNLOCKS:
		result.append({"id":"unlock_" + item,"name":Catalog.UNLOCKS[item]["hint"],"current":1 if game.progression.is_item_unlocked(item) else 0,"target":1})
	for level in [2,3,4]:
		result.append({"id":"tool_%d" % level,"name":"Fusiona dos máquinas iguales del mismo nivel → Nv. %d" % level,"current":int(state.get("tool_tier",1)),"target":level})
	return result

func check_achievements() -> void:
	for entry: Dictionary in achievements():
		if not state["achievements"].has(entry["id"]) and entry["current"] >= entry["target"]:
			state["achievements"][entry["id"]] = true
			toast.text = "★ Logro desbloqueado · " + entry["name"]
			toast_time = 4

func repair() -> bool:
	var price: int = 80 + game.cycle.day * 15
	if game.cycle.is_night or game.cycle.defeated or game.zombie_manager.base_health >= 100 or not game.economy.spend(price): return false
	game.zombie_manager.base_health = minf(100,game.zombie_manager.base_health + 30)
	game.zombie_manager.base_health_changed.emit(game.zombie_manager.base_health,100)
	game.zombie_manager.queue_redraw()
	return true

func expand_gallery() -> bool:
	if game.cycle.defeated or not game.progression.is_item_unlocked("expansion"): return false
	var stage: Dictionary = Catalog.next_expansion(game.grid.cave_width)
	if stage.is_empty() or not game.economy.spend(stage["price"]): return false
	game.grid.cave_width = stage["size"].x
	game.grid.cave_height = stage["size"].y
	game.grid.apply_cave_size()
	game.camera_controller.update_zoom_limits()
	game.cycle.refresh_tutorial()
	game.redraw_world()
	return true

func add_platforms() -> bool:
	if game.cycle.is_night or game.cycle.defeated or game.grid.defense_tiles.size() < 2 or game.grid.defense_tiles.size() >= 6: return false
	if not game.economy.spend(5000 * game.grid.defense_tiles.size()): return false
	game.grid.purchase_defense_platforms(game.grid.defense_tiles.size() + 2)
	game.redraw_world()
	return true

func upgrade_arsenal() -> bool:
	var rank: int = state.get("arsenal_rank",0)
	if rank >= Catalog.INDUSTRIAL_UPGRADES.size() or game.cycle.is_night or game.cycle.defeated: return false
	var upgrade: Dictionary = Catalog.INDUSTRIAL_UPGRADES[rank]
	if state["best_night"] < upgrade["night"] or not available(upgrade["cost"]) or not game.economy.spend(upgrade["price"]): return false
	consume(upgrade["cost"])
	state["arsenal_rank"] = rank + 1
	return true

func _process(delta: float) -> void:
	var saves: Node = game.get_node_or_null("SaveGame")
	hud.visible = saves != null and saves.playing and not game.shop.shop_open and not game.display_settings.menu_open and not game.display_settings.auto_click_prompt.visible and game.get_node_or_null("IntroCinematic") == null
	toast.visible = toast_time > 0 and hud.visible
	if not get_tree().paused and saves != null and saves.playing and not game.cycle.defeated:
		state["elapsed_play"] += delta / maxf(0.001,Engine.time_scale)
		advance_workshop(delta)
		toast_time = maxf(0,toast_time - delta)
	refresh_timer -= delta
	if overlay.visible and refresh_timer <= 0:
		refresh_timer = 0.5
		update_status()
	var factor: float = game.display_settings.interface_scale()
	scale = Vector2.ONE * factor
	var view: Vector2 = get_viewport().get_visible_rect().size / factor
	hud.position = view - Vector2(170,60)
	overlay.size = view
	toast.position = Vector2((view.x - 580) * 0.5,view.y - 50)

func build_ui() -> void:
	hud = game.shop.create_button("ARSENAL · LOGROS")
	hud.custom_minimum_size = Vector2(150,40)
	hud.pressed.connect(open_panel)
	add_child(hud)
	overlay = Control.new()
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.04,0.05,0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780,570)
	var style: StyleBoxFlat = game.shop.create_style("#192d29","#d8b477",2,14)
	for margin: String in ["left","right","top","bottom"]: style.set("content_margin_" + margin,22)
	panel.add_theme_stylebox_override("panel",style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title: Label = game.shop.create_label("LA MINA · CENTRAL DE OPERACIONES",24,Color("#ffe2ac"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = game.shop.create_button("×")
	close.custom_minimum_size = Vector2(40,40)
	close.pressed.connect(close_panel)
	header.add_child(close)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for tab: String in ["Campaña","Taller","Logros","Bestiario","Historia"]:
		var button: Button = game.shop.create_button(tab)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(show_tab.bind(tab))
		tabs.add_child(button)
	status_label = game.shop.create_label("",14,Color("#9fb5c7"))
	column.add_child(status_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720,390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation",10)
	scroll.add_child(page)
	toast = game.shop.create_label("",16,Color("#ffe2a1"))
	toast.custom_minimum_size.x = 580
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	overlay.hide()

func open_panel() -> void:
	if get_tree().paused or game.cycle.defeated: return
	game.get_node("WorldInteractions").cancel_active()
	previous_pause = get_tree().paused
	get_tree().paused = true
	overlay.show()
	show_tab(selected_tab)

func close_panel() -> void:
	if not overlay.visible: return
	overlay.hide()
	get_tree().paused = previous_pause

func _input(event: InputEvent) -> void:
	if overlay.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()

func update_status() -> void:
	status_label.text = "Día %d · %d monedas · %d zombis eliminados · %d/%d logros" % [game.cycle.day,game.economy.coins,state["kills"],state["achievements"].size(),achievements().size()]
	if not state["job"].is_empty(): status_label.text += "\nFabricando %s · %.1f/%.0f s. Cierra esta ventana para avanzar." % [Catalog.LABELS[state["job"]["kind"]],state["job"]["elapsed"],Catalog.CRAFTS[state["job"]["kind"]]["time"]]

func text(value: String, size: int = 16, color := Color("#c9d9e7")) -> void:
	var label: Label = game.shop.create_label(value,size,color)
	label.custom_minimum_size.x = 660
	page.add_child(label)

func action(label: String, callable: Callable, enabled: bool = true) -> void:
	var button: Button = game.shop.create_button(label)
	button.custom_minimum_size.y = 38
	button.disabled = not enabled
	button.pressed.connect(func():
		callable.call()
		show_tab(selected_tab)
	)
	page.add_child(button)

func show_tab(tab: String) -> void:
	selected_tab = tab
	for child: Node in page.get_children():
		page.remove_child(child)
		child.queue_free()
	update_status()
	match tab:
		"Campaña":
			var chapter: Dictionary = Catalog.chapter(game.cycle.day)
			text(chapter["name"],26,Color("#e2edf5"))
			text(chapter["goal"])
			if state["best_night"] >= Catalog.CAMPAIGN_NIGHTS: text("Ruta completada · Puedes continuar en supervivencia infinita.",20,Color("#f2d49b"))
			text("Ruta de 900 noches · unos 105 h a velocidad normal, sin contar preparación inicial ni combates prolongados. La duración real depende de tu ritmo.",14)
			text("Cada 5 noches: jefe. Desde noche 21, cada 7: niebla (−15 % de alcance); cada 6: enemigos con blindaje adicional. Cada 9: furia (+20 % de velocidad). A partir de las noches 81 y 601 aparecen jefes adicionales. Prioriza sanadores y saboteadores.",14)
			for entry: Dictionary in Catalog.CHAPTERS: text("Día %d · %s" % [entry["start"],entry["name"]],16,Color("#e2edf5") if game.cycle.day >= entry["start"] else Color("#849589"))
			action("Reparar 30 de integridad · %d monedas" % (80 + game.cycle.day * 15),repair,not game.cycle.is_night and game.zombie_manager.base_health < 100)
			var stage: Dictionary = Catalog.next_expansion(game.grid.cave_width)
			if not stage.is_empty(): action("Ampliar a %d × %d · %d monedas" % [stage["size"].x,stage["size"].y,stage["price"]],expand_gallery,game.progression.is_item_unlocked("expansion"))
			else: text("Excavación completa · 1200 casillas")
			action("Dos plataformas adicionales · %d monedas" % (5000 * game.grid.defense_tiles.size()),add_platforms,game.grid.defense_tiles.size() in [2,4] and not game.cycle.is_night)
			var rank: int = state.get("arsenal_rank",0)
			text("Arsenal industrial · Mejora %d/3" % rank,20,Color("#e2edf5"))
			text("Cada mejora: +20 % de daño, +25 % de capacidad y −10 % de intervalo en las armas industriales.",14)
			if rank < 3:
				var upgrade: Dictionary = Catalog.INDUSTRIAL_UPGRADES[rank]
				var requirements: String = "Tras noche %d · %d monedas\n" % [upgrade["night"],upgrade["price"]]
				for ingredient: String in upgrade["cost"]: requirements += "%d × %s  " % [upgrade["cost"][ingredient],game.shop.RESOURCE_LABELS.get(ingredient,Catalog.label(ingredient))]
				text(requirements,14)
				action("Mejorar arsenal",upgrade_arsenal,state["best_night"] >= upgrade["night"] and available(upgrade["cost"]) and not game.cycle.is_night)
		"Historia":
			var director: Node = game.get_node("StoryDirector")
			for id: String in director.SCENES:
				var unlocked: bool = director.seen().has(id)
				text(director.SCENES[id]["chapter"] + (" · Recuperado" if unlocked else " · Señal perdida"),18)
				if unlocked:
					text(director.SCENES[id]["text"],15)
					action("Reproducir escena",func(): close_panel(); director.play(id))
				else: text("Descubre este archivo al avanzar o derrotar a su jefe.",14)
		"Taller":
			text("Munición industrial",24,Color("#e2edf5"))
			text("Usa materiales sueltos de la mina. El producto aparece en una casilla libre o se apila. Las cintas pueden cargar las armas; cada arma usa su propia munición.",14)
			for kind: String in Catalog.CRAFTS:
				var recipe: Dictionary = Catalog.CRAFTS[kind]
				var description: String = "%s ×%d · %.0f s · Disponibles: %d\n" % [Catalog.LABELS[kind],recipe["yield"],recipe["time"],total(kind)]
				for ingredient: String in recipe["cost"]: description += "%d × %s (%d)  " % [recipe["cost"][ingredient],game.shop.RESOURCE_LABELS.get(ingredient,Catalog.label(ingredient)),total(ingredient)]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation",12)
				page.add_child(row)
				var icon: Control = game.shop.create_item_preview("ore:" + kind,Vector2(54,54))
				icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(icon)
				var label: Label = game.shop.create_label(description,14)
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(label)
				text(Catalog.UNLOCKS[kind]["hint"],14)
				action(("Fabricar " if game.progression.is_item_unlocked(kind) else "Bloqueado · ") + Catalog.LABELS[kind],craft.bind(kind),can_craft(kind))
				action(("✓ Repetición activa · " if state["repeat_recipe"] == kind else "Repetir automáticamente · ") + Catalog.LABELS[kind],func(): state["repeat_recipe"] = "" if state["repeat_recipe"] == kind else kind,game.progression.is_item_unlocked(kind))
		"Logros":
			for entry: Dictionary in achievements():
				text(("★ " if state["achievements"].has(entry["id"]) else "○ ") + entry["name"] + " · %d/%d" % [mini(entry["current"],entry["target"]),entry["target"]],16,Color("#f2d49b") if state["achievements"].has(entry["id"]) else Color("#9ab2a7"))
		"Bestiario":
			var mechanics := {"spitter":"Anuncia ácido antes de disparar. Interrúmpelo.","brute":"Se prepara, carga y queda expuesto: daño doble.","plague":"Escudo activo; tras su triple ácido queda vulnerable.","stalker":"Resiste a distancia; pierde camuflaje al acercarse.","dodger":"Reduce cada tercer impacto. Usa explosivos.","shielder":"Restaura blindaje cercano cada tres segundos.","healer":"Cura aliados cercanos. Prioridad de eliminación.","swarm":"Al morir libera dos rastreros.","sapper":"Su ataque anunciado roba una carga de cada arma.","warden":"Blindaje pesado, cargas repetidas y ventana de contraataque.","broodmother":"Invoca rastreros al lanzar ácido; ataca mientras baja el escudo.","executor":"Cargas repetidas; se enfurece por debajo del 50 % de vida."}
			for enemy: String in game.zombie_manager.ZombieScript.TYPES:
				var stats: Dictionary = game.zombie_manager.ZombieScript.TYPES[enemy]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation",15)
				page.add_child(row)
				var preview := EnemyPreview.new()
				preview.archetype = enemy
				preview.custom_minimum_size = Vector2(85,110)
				row.add_child(preview)
				var descriptions := VBoxContainer.new()
				descriptions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(descriptions)
				descriptions.add_child(game.shop.create_label(stats["name"],20,Color("#e2edf5")))
				var detail: Label = game.shop.create_label("Vida %.1f · Blindaje %.1f · Velocidad %.0f\n%s" % [stats["health"],stats["armor"],stats["speed"],mechanics.get(enemy,"Mantén las armas cargadas y controla su avance.")],14)
				detail.custom_minimum_size.x = 570
				descriptions.add_child(detail)

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not data.get("tool_tier",1) is int or data.get("tool_tier",1) not in [1,2,3,4]: return false
	if not data.get("story_seen",{}) is Dictionary: return false
	for id: Variant in data.get("story_seen",{}):
		if not preload("res://Scripts/story_director.gd").SCENES.has(id) or not data["story_seen"][id] is bool: return false
	if not data.get("arsenal_rank",0) is int or data.get("arsenal_rank",0) not in [0,1,2,3]: return false
	for key: String in ["kills","bosses","flawless","best_night","elapsed_play","health_at_dusk"]:
		if not (data.get(key) is int or data.get(key) is float) or not is_finite(float(data[key])) or data[key] < 0 or data[key] > 1e12: return false
	if data["health_at_dusk"] > 100 or not data.get("crafted") is Dictionary or not data.get("achievements") is Dictionary or not data.get("job") is Dictionary: return false
	for kind: Variant in data["crafted"]:
		if kind not in Catalog.CRAFTS or not data["crafted"][kind] is int or data["crafted"][kind] < 0 or data["crafted"][kind] > 1e12: return false
	for key: Variant in data["achievements"]:
		if not key is String or key.length() > 64 or not data["achievements"][key] is bool: return false
	if data.get("repeat_recipe","") not in [""] + Catalog.CRAFTS.keys(): return false
	if not data["job"].is_empty():
		var job: Dictionary = data["job"]
		if not Catalog.CRAFTS.has(job.get("kind")) or not (job.get("elapsed") is float or job.get("elapsed") is int): return false
		if not is_finite(float(job["elapsed"])) or job["elapsed"] < 0 or job["elapsed"] > Catalog.CRAFTS[job["kind"]]["time"]: return false
	return true

class EnemyPreview extends Control:
	var archetype: String
	var model: Node2D
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		model = preload("res://Scripts/zombie.gd").new()
		model.configure(archetype)
		model.position = Vector2(42,58)
		add_child(model)
		model.remove_from_group("zombies")
		model.set_process(false)
		model.set_process_unhandled_input(false)
	func _process(delta: float) -> void:
		if not is_visible_in_tree(): return
		model.walking_time += delta * 8
		model.update_visual()
