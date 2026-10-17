extends Control

signal expansion_requested
signal brass_vein_requested
signal coal_vein_requested
signal left_corner_conveyor_requested
signal corner_conveyor_requested
signal junction_conveyor_requested
signal conveyor_requested
signal left_defense_tile_requested
signal right_defense_tile_requested
signal defense_platforms_unlocked
signal view_toggle_requested
signal launcher_requested
signal drill_requested
signal night_requested
signal restart_requested
signal technology_requested(technology_id: String)

const DisplaySettingsScript = preload("res://Scripts/display_settings.gd")
const TutorialGuideScript = preload("res://Scripts/tutorial_guide.gd")

const PANEL_WIDTH := 340.0
const TOGGLE_SIZE := 58.0
const MONEY_BOX_WIDTH := 148.0
const ANIMATION_TIME := 0.3
const CATEGORIES := ["EXPANSION", "BASE", "DEFENSA", "TECNOLOGÍAS"]

var economy: RefCounted
var grid: RefCounted
var shop_open: bool = false
var shop_animating: bool = false
var tween: Tween
var money_box: PanelContainer
var money_label: Label
var shop_button: Button
var view_button: Button
var shop_panel: PanelContainer
var shop_content: VBoxContainer
var shop_title: Label
var fixed_back_button: Button
var shop_scroll: ScrollContainer
var cycle: RefCounted
var cycle_title: Label
var cycle_heading: Label
var cycle_badge: Label
var cycle_steps: HBoxContainer
var cycle_goal: Label
var cycle_action: Button
var progression: RefCounted
var progression_panel: PanelContainer
var level_label: Label
var experience_bar: ProgressBar
var research_summary: Label
var research_buttons: Dictionary = {}
var research_status: Dictionary = {}
var fallback_display: CanvasLayer

func setup(economy_manager: RefCounted, grid_manager: RefCounted) -> void:
	economy = economy_manager
	grid = grid_manager
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_interface()
	economy.money_changed.connect(update_money)
	update_money(economy.coins)
	# Older scenes can have a built-in main script. Updating main.gd alone
	# does not update those scenes, so install the pause menu here as well.
	ensure_pause_menu.call_deferred()

func ensure_pause_menu() -> void:
	var ui_layer: CanvasLayer = get_parent() as CanvasLayer
	if ui_layer == null or ui_layer.get_parent() == null:
		return
	var game: Node = ui_layer.get_parent()
	for child in game.get_children():
		if child.get_script() == DisplaySettingsScript:
			return
	fallback_display = DisplaySettingsScript.new()
	fallback_display.name = "PauseMenu"
	game.add_child(fallback_display)
	fallback_display.changed.connect(update_pause_layout)
	get_viewport().size_changed.connect(update_pause_layout)
	update_pause_layout()

func update_pause_layout() -> void:
	if not is_instance_valid(fallback_display):
		return
	var factor: float = fallback_display.interface_scale()
	(get_parent() as CanvasLayer).scale = Vector2.ONE * factor
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = get_viewport().get_visible_rect().size / factor

func set_cycle(game_cycle: RefCounted) -> void:
	cycle = game_cycle
	build_cycle_panel()
	cycle.changed.connect(update_cycle)
	update_cycle()
	ensure_tutorial_guide.call_deferred()

func ensure_tutorial_guide() -> void:
	var game: Node = get_parent().get_parent()
	for child in game.get_children():
		if child.get_script() == TutorialGuideScript:
			return
	var guide := TutorialGuideScript.new()
	guide.name = "TutorialGuide"
	game.add_child(guide)

func set_progression(player_progression: RefCounted) -> void:
	progression = player_progression
	build_progression_panel()
	progression.changed.connect(update_progression)
	update_progression()

func build_progression_panel() -> void:
	progression_panel = PanelContainer.new()
	progression_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	progression_panel.offset_left = -180.0
	progression_panel.offset_right = 180.0
	progression_panel.offset_top = -58.0
	progression_panel.offset_bottom = -20.0
	progression_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progression_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(progression_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	progression_panel.add_child(column)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	level_label = create_label("", 14, Color("#d6edb4"))
	level_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_color_override("font_outline_color", Color("#152019"))
	level_label.add_theme_constant_override("outline_size", 3)
	row.add_child(level_label)
	level_label.custom_minimum_size.y = 24
	experience_bar = ProgressBar.new()
	experience_bar.custom_minimum_size.y = 6
	experience_bar.show_percentage = false
	experience_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	experience_bar.add_theme_stylebox_override("background", create_style("#18241d", "#18241d", 0, 3))
	experience_bar.add_theme_stylebox_override("fill", create_style("#8db574", "#8db574", 0, 3))
	column.add_child(experience_bar)

func update_progression() -> void:
	if progression == null:
		return
	level_label.text = "NIVEL %d" % progression.level
	experience_bar.max_value = progression.experience_to_next_level()
	experience_bar.value = progression.experience
	experience_bar.tooltip_text = "EXP %d / %d\nGana EXP vendiendo minerales y derrotando zombis." % [progression.experience, progression.experience_to_next_level()]
	progression_panel.visible = not shop_open and not shop_animating
	refresh_research_buttons()

func open_research() -> void:
	if cycle != null and (cycle.is_night or cycle.defeated):
		return
	if not shop_open:
		open_shop()
	if shop_open:
		open_category("TECNOLOGÍAS")

func build_research_content() -> void:
	if progression == null:
		return
	research_summary = create_label("", 18, Color("#d6edb4"))
	shop_content.add_child(research_summary)
	shop_content.add_child(create_label("Cada nivel otorga 1 punto. Las mejoras se aplican a todas tus máquinas y torretas.", 14))
	shop_content.add_child(create_label("EXP: zombi derrotado +10 · carbón vendido +2 · latón vendido +3.", 13))
	var previous_branch: String = ""
	for technology_id in progression.TECHNOLOGIES:
		var data: Dictionary = progression.TECHNOLOGIES[technology_id]
		var branch: String = data["branch"]
		if branch != previous_branch:
			shop_content.add_child(HSeparator.new())
			shop_content.add_child(create_label(branch, 19, Color("#f3ca85")))
			previous_branch = branch
		shop_content.add_child(create_label(data["name"], 17, Color("#d6edb4")))
		shop_content.add_child(create_label(data["description"], 14))
		var requirements: String = "Nivel %d · Coste: %d PI" % [data["level"], data["cost"]]
		for prerequisite in data["requires"]:
			requirements += "\nRequiere: %s" % progression.TECHNOLOGIES[prerequisite]["name"]
		shop_content.add_child(create_label(requirements, 13))
		var status := create_label("", 13)
		research_status[technology_id] = status
		shop_content.add_child(status)
		var button := create_button("")
		button.name = "Research_" + str(technology_id)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(technology_requested.emit.bind(technology_id))
		research_buttons[technology_id] = button
		shop_content.add_child(button)
	refresh_research_buttons()

func refresh_research_buttons() -> void:
	if progression == null:
		return
	if research_summary != null:
		research_summary.text = "Nivel %d · %d PI disponibles" % [progression.level, progression.research_points]
	var blocked: bool = cycle != null and (cycle.is_night or cycle.defeated or cycle.is_tutorial_active())
	for technology_id in research_buttons:
		var button: Button = research_buttons[technology_id]
		var status: Label = research_status[technology_id]
		var researched: bool = progression.has_technology(technology_id)
		button.disabled = blocked or not progression.can_research(technology_id)
		button.text = "INVESTIGADA" if researched else "INVESTIGAR · %d PI" % progression.TECHNOLOGIES[technology_id]["cost"]
		var reason: String = progression.research_block_reason(technology_id)
		status.text = ("Completa el tutorial para investigar." if cycle != null and cycle.is_tutorial_active() else "Investiga durante el día.") if blocked and not researched else ("Disponible" if reason.is_empty() else reason)
		status.add_theme_color_override("font_color", Color("#b8dc98") if researched or not button.disabled else Color("#c6b5a0"))

func build_cycle_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "CyclePanel"
	panel.position = Vector2(20, 91)
	panel.size = Vector2(302, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := create_style("#192920", "#435744", 1, 12)
	style.border_width_left = 3
	style.border_color = Color("#c9a469")
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 11)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	cycle_heading = create_label("PRIMEROS PASOS", 12, Color("#aabb9e"))
	cycle_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	cycle_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(cycle_heading)
	cycle_badge = create_label("01 / 07", 12, Color("#efd29b"))
	cycle_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(cycle_badge)
	cycle_steps = HBoxContainer.new()
	cycle_steps.add_theme_constant_override("separation", 5)
	column.add_child(cycle_steps)
	for index in range(7):
		var segment := ColorRect.new()
		segment.custom_minimum_size.y = 3
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cycle_steps.add_child(segment)
	cycle_title = create_label("", 21, Color("#f1e6c9"))
	column.add_child(cycle_title)
	cycle_goal = create_label("", 14, Color("#bacbb7"))
	cycle_goal.custom_minimum_size.y = 58
	column.add_child(cycle_goal)
	cycle_action = create_button("")
	cycle_action.custom_minimum_size.y = 39
	cycle_action.add_theme_font_size_override("font_size", 14)
	cycle_action.add_theme_color_override("font_color", Color("#222c20"))
	cycle_action.add_theme_color_override("font_hover_color", Color("#222c20"))
	cycle_action.add_theme_stylebox_override("normal", create_style("#d5b078", "#e6ca98", 1, 7))
	cycle_action.add_theme_stylebox_override("hover", create_style("#ebc991", "#f6dfb5", 1, 7))
	cycle_action.add_theme_stylebox_override("disabled", create_style("#263a2d", "#3b5240", 1, 7))
	cycle_action.pressed.connect(_on_cycle_action)
	column.add_child(cycle_action)

func _on_cycle_action() -> void:
	if cycle_action.disabled:
		return
	if cycle.defeated:
		restart_requested.emit()
	elif cycle.is_tutorial_active():
		match cycle.tutorial_step:
			0: coal_vein_requested.emit()
			2: expansion_requested.emit()
			3: conveyor_requested.emit()
			4: unlock_defense_platforms()
			5: launcher_requested.emit()
			7: night_requested.emit()
		update_cycle()
	elif cycle.can_start_night() and not shop_open and not shop_animating:
		night_requested.emit()

func update_cycle() -> void:
	if cycle == null or cycle_title == null:
		return
	var tutorial: bool = cycle.is_tutorial_active()
	cycle_heading.text = "PRIMEROS PASOS" if tutorial else "DEFENSA DE LA BASE"
	cycle_badge.text = "%02d / 07" % mini(cycle.tutorial_step + 1, 7) if tutorial else "DÍA %d" % cycle.day
	cycle_steps.visible = tutorial
	for index in range(cycle_steps.get_child_count()):
		cycle_steps.get_child(index).color = Color("#8db574") if index < cycle.tutorial_step else (Color("#e1b879") if index == cycle.tutorial_step else Color("#354b3a"))
	if tutorial:
		cycle_title.text = cycle.tutorial_title()
		cycle_goal.text = cycle.tutorial_text()
		cycle_action.disabled = false
		var game: Node = get_parent().get_parent()
		match cycle.tutorial_step:
			0:
				cycle_action.text = "COLOCA LA VETA MARCADA" if game.get("placing_coal") else "COMPRAR VETA · 100"
				cycle_action.disabled = game.get("placing_coal") or not economy.can_afford(economy.COAL_VEIN_PRICE)
				if game.get("placing_coal"):
					cycle_goal.text = "Coloca la veta en la casilla dorada. Su salida quedará orientada hacia la derecha."
			1, 6:
				if cycle.tutorial_step == 6:
					cycle_action.text = "MUNICIÓN · %d / 4" % roundi(cycle.ammo_damage() / 0.5)
				elif cycle.mining.nuggets_at(cycle.TUTORIAL_ORE_CELL) > 0:
					cycle_action.text = "ARRASTRA LA PEPITA AL COFRE"
				else:
					var vein: Dictionary = cycle.mining.coal_veins.get(cycle.TUTORIAL_COAL_CELL, {})
					cycle_action.text = "EXTRAE CARBÓN · %d / %d" % [vein.get("progress", 0), cycle.mining.mining_clicks]
				cycle_action.disabled = true
			2:
				cycle_action.text = "AMPLIAR A 7 × 5 · 500"
				cycle_action.disabled = not economy.can_afford(economy.EXPANSION_PRICE)
			3:
				cycle_action.text = "COLOCA LA CINTA MARCADA" if game.get("placing_belt") else "COMPRAR CINTA · 50"
				cycle_action.disabled = game.get("placing_belt") or not economy.can_afford(economy.CONVEYOR_PRICE)
				if game.get("placing_belt"):
					cycle_goal.text = "Coloca la cinta en la casilla dorada, justo debajo de tu veta."
			4:
				cycle_action.text = "DESBLOQUEAR DEFENSAS · 100"
				cycle_action.disabled = not economy.can_afford(economy.DEFENSE_TILE_PRICE)
			5:
				cycle_action.text = "COLOCA EL LANZAPAPAS" if game.get("placing_launcher") else "OBTENER LANZAPAPAS · GRATIS"
				cycle_action.disabled = game.get("placing_launcher")
				if game.get("placing_launcher"):
					cycle_goal.text = "Coloca el lanzapapas en la plataforma izquierda resaltada en dorado."
			7:
				cycle_action.text = "INICIAR PRIMERA NOCHE"
				cycle_action.disabled = not cycle.can_start_night()
	elif cycle.defeated:
		cycle_title.text = "Base destruida"
		cycle_goal.text = "La entrada ha caído. Vuelve a empezar."
		cycle_action.text = "REINICIAR PARTIDA"
		cycle_action.disabled = false
	elif cycle.is_night:
		cycle_title.text = "Noche %d · Defensa" % cycle.day
		cycle_goal.text = "Resiste la oleada y protege la entrada."
		cycle_action.text = "NOCHE EN CURSO"
		cycle_action.disabled = true
	else:
		cycle_title.text = "Día %d · Preparación" % cycle.day
		cycle_goal.text = "Construye, fabrica munición y prepara la próxima noche."
		cycle_action.text = "INICIAR NOCHE"
		cycle_action.disabled = not cycle.can_start_night() or shop_open or shop_animating
	shop_button.disabled = tutorial or cycle.is_night or cycle.defeated
	view_button.disabled = tutorial or cycle.is_night or cycle.defeated
	update_progression()

func create_style(background: String, border: String, border_size: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(border_size)
	style.set_corner_radius_all(radius)
	return style

func create_button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("#fff0d0"))
	button.add_theme_color_override("font_hover_color", Color("#ffdf9c"))
	button.add_theme_stylebox_override("normal", create_style("#60401f", "#a87843", 3, 8))
	button.add_theme_stylebox_override("hover", create_style("#80562a", "#e0ad66", 3, 8))
	button.add_theme_stylebox_override("pressed", create_style("#352516", "#a87843", 3, 8))
	button.add_theme_stylebox_override("disabled", create_style("#352719", "#59442f", 2, 8))
	return button

func create_label(value: String, font_size: int = 17, color: Color = Color("#f0e0c8")) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func build_interface() -> void:
	shop_button = create_button("☰")
	shop_button.anchor_left = 1.0
	shop_button.anchor_right = 1.0
	shop_button.offset_left = -TOGGLE_SIZE - 15.0
	shop_button.offset_right = -15.0
	shop_button.offset_top = 20.0
	shop_button.offset_bottom = 20.0 + TOGGLE_SIZE
	shop_button.add_theme_font_size_override("font_size", 28)
	shop_button.pressed.connect(open_shop)
	add_child(shop_button)

	money_box = PanelContainer.new()
	money_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_box.anchor_left = 1.0
	money_box.anchor_right = 1.0
	money_box.offset_right = -TOGGLE_SIZE - 27.0
	money_box.offset_left = money_box.offset_right - MONEY_BOX_WIDTH
	money_box.offset_top = 20.0
	money_box.offset_bottom = 20.0 + TOGGLE_SIZE
	money_box.add_theme_stylebox_override("panel", create_style("#654321", "#b8864b", 4, 12))
	add_child(money_box)

	var money_margin := MarginContainer.new()
	money_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		money_margin.add_theme_constant_override("margin_" + side, 8)
	money_box.add_child(money_margin)
	var money_row := HBoxContainer.new()
	money_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_row.add_theme_constant_override("separation", 8)
	money_margin.add_child(money_row)
	var coin_icon := PanelContainer.new()
	coin_icon.custom_minimum_size = Vector2(34, 34)
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_icon.add_theme_stylebox_override("panel", create_style("#d69a32", "#ffdb72", 3, 17))
	money_row.add_child(coin_icon)
	var coin_symbol := create_label("◆", 18, Color("#fff0a1"))
	coin_symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_icon.add_child(coin_symbol)
	coin_symbol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	money_label = create_label("", 23, Color("#f3ca85"))
	money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_row.add_child(money_label)

	shop_panel = PanelContainer.new()
	shop_panel.anchor_left = 1.0
	shop_panel.anchor_right = 1.0
	shop_panel.anchor_top = 0.0
	shop_panel.anchor_bottom = 1.0
	shop_panel.offset_left = 0.0
	shop_panel.offset_right = PANEL_WIDTH
	shop_panel.offset_top = 0.0
	shop_panel.offset_bottom = 0.0
	shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_panel.add_theme_stylebox_override("panel", create_style("#352516", "#a87843", 5, 0))
	add_child(shop_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	shop_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	shop_title = create_label("TIENDA", 27, Color("#f3ca85"))
	shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(shop_title)
	var close_button := create_button("X")
	close_button.custom_minimum_size = Vector2(45, 45)
	close_button.add_theme_stylebox_override("normal", create_style("#8f302b", "#d16b60", 3, 8))
	close_button.add_theme_stylebox_override("hover", create_style("#b84238", "#f19a83", 3, 8))
	close_button.pressed.connect(close_shop)
	header.add_child(close_button)
	content.add_child(HSeparator.new())
	fixed_back_button = create_button("← VOLVER")
	fixed_back_button.pressed.connect(show_categories)
	fixed_back_button.hide()
	content.add_child(fixed_back_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	shop_scroll = scroll
	content.add_child(scroll)
	shop_content = VBoxContainer.new()
	shop_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_content.add_theme_constant_override("separation", 12)
	scroll.add_child(shop_content)
	show_categories()
	view_button = create_button("DEFENSIVA")
	view_button.name = "BotonDefensiva"
	view_button.anchor_left = 0.0
	view_button.anchor_right = 0.0
	view_button.anchor_top = 0.0
	view_button.anchor_bottom = 0.0
	view_button.offset_left = 20.0
	view_button.offset_right = 200.0
	view_button.offset_top = 20.0
	view_button.offset_bottom = 78.0
	view_button.mouse_filter = Control.MOUSE_FILTER_STOP
	view_button.focus_mode = Control.FOCUS_NONE
	view_button.pressed.connect(view_toggle_requested.emit)
	add_child(view_button)

func set_view_mode(defense_enabled: bool) -> void:
	view_button.text = "MINA" if defense_enabled else "DEFENSIVA"

func update_money(amount: int) -> void:
	money_label.text = "∞ DEV" if economy.developer_mode else str(amount)
	if shop_open:
		if shop_title.text == "TECNOLOGÍAS":
			return
		if shop_title.text in CATEGORIES:
			open_category(shop_title.text)
		else:
			show_categories()

func clear_content() -> void:
	research_buttons.clear()
	research_status.clear()
	research_summary = null
	for child in shop_content.get_children():
		shop_content.remove_child(child)
		child.queue_free()

func show_categories() -> void:
	if cycle != null and cycle.is_tutorial_active():
		return
	shop_title.text = "TIENDA"
	fixed_back_button.hide()
	shop_scroll.scroll_vertical = 0
	clear_content()
	shop_content.add_child(create_label("CATEGORIAS", 20, Color("#f3ca85")))
	for category in CATEGORIES:
		var button := create_button(category + "  >")
		button.pressed.connect(open_category.bind(category))
		shop_content.add_child(button)

func open_category(category: String) -> void:
	if cycle != null and cycle.is_tutorial_active():
		return
	shop_title.text = category
	fixed_back_button.show()
	shop_scroll.scroll_vertical = 0
	clear_content()
	match category:
		"TECNOLOGÍAS":
			build_research_content()
		"EXPANSION":
			shop_content.add_child(create_label("AMPLIACION DE LA BASE", 18, Color("#f3ca85")))
			shop_content.add_child(create_label("Tamaño actual: %dx%d" % [grid.cave_width, grid.cave_height]))
			var button := create_button("")
			if grid.cave_width >= 7:
				button.text = "EXPANSION MAXIMA: 7x5"
				button.disabled = true
			else:
				button.text = "AMPLIAR A 7x5 - 500"
				button.disabled = not economy.can_afford(economy.EXPANSION_PRICE)
				button.pressed.connect(expansion_requested.emit)
			shop_content.add_child(button)
		"BASE":
			shop_content.add_child(create_label("MINERIA", 19, Color("#f3ca85")))
			var button := create_button("VETA DE CARBON - 100")
			button.disabled = not economy.can_afford(economy.COAL_VEIN_PRICE)
			button.pressed.connect(coal_vein_requested.emit)
			shop_content.add_child(button)
			var brass_button := create_button("VETA DE LATON - 150")
			brass_button.disabled = not economy.can_afford(economy.BRASS_VEIN_PRICE)
			brass_button.pressed.connect(brass_vein_requested.emit)
			shop_content.add_child(brass_button)
			shop_content.add_child(create_label("AUTOMATIZACION", 19, Color("#f3ca85")))
			var conveyor_button := create_button("CINTA TRANSPORTADORA - 50")
			conveyor_button.disabled = not economy.can_afford(economy.CONVEYOR_PRICE)
			conveyor_button.pressed.connect(conveyor_requested.emit)
			shop_content.add_child(conveyor_button)
			var corner_button := create_button("CINTA EN L DERECHA - 50")
			corner_button.disabled = not economy.can_afford(economy.CONVEYOR_PRICE)
			corner_button.pressed.connect(corner_conveyor_requested.emit)
			shop_content.add_child(corner_button)
			var left_corner_button := create_button("CINTA EN L IZQUIERDA - 50")
			left_corner_button.disabled = not economy.can_afford(economy.CONVEYOR_PRICE)
			left_corner_button.pressed.connect(left_corner_conveyor_requested.emit)
			shop_content.add_child(left_corner_button)
			var junction_button := create_button("CINTA EN T - 50")
			junction_button.disabled = not economy.can_afford(economy.CONVEYOR_PRICE)
			junction_button.pressed.connect(junction_conveyor_requested.emit)
			shop_content.add_child(junction_button)
			var drill_button := create_button("TALADRO AUTOMATICO - 200")
			drill_button.disabled = not economy.can_afford(economy.DRILL_PRICE)
			drill_button.pressed.connect(drill_requested.emit)
			shop_content.add_child(drill_button)
		"DEFENSA":
			var left_cell: Vector2i = grid.defense_cell("left")
			var right_cell: Vector2i = grid.defense_cell("right")
			var platforms_button := create_button("DESBLOQUEAR DEFENSAS - 100")
			if grid.defense_tiles.has(left_cell) and grid.defense_tiles.has(right_cell):
				platforms_button.text = "DEFENSAS - COMPRADAS"
				platforms_button.disabled = true
			else:
				platforms_button.disabled = not economy.can_afford(economy.DEFENSE_TILE_PRICE)
				platforms_button.pressed.connect(unlock_defense_platforms)
			shop_content.add_child(platforms_button)
			var launcher_button := create_button("LANZAPAPAS - GRATIS" if cycle != null and cycle.free_launcher_available else "LANZAPAPAS - 200")
			launcher_button.disabled = not (cycle != null and cycle.free_launcher_available) and not economy.can_afford(economy.LAUNCHER_PRICE)
			launcher_button.pressed.connect(launcher_requested.emit)
			shop_content.add_child(launcher_button)

func unlock_defense_platforms() -> void:
	if cycle != null and not cycle.allows_action("unlock_defense"):
		return
	var left_cell: Vector2i = grid.defense_cell("left")
	var right_cell: Vector2i = grid.defense_cell("right")
	if grid.defense_tiles.has(left_cell) and grid.defense_tiles.has(right_cell):
		open_category("DEFENSA")
		return
	if not economy.spend(economy.DEFENSE_TILE_PRICE):
		return
	if not grid.purchase_defense_platforms():
		if not economy.developer_mode:
			economy.add(economy.DEFENSE_TILE_PRICE)
		return
	defense_platforms_unlocked.emit()
	open_category("DEFENSA")

func open_shop() -> void:
	if cycle != null and cycle.is_tutorial_active():
		return
	if shop_open or shop_animating or (cycle != null and (cycle.is_night or cycle.defeated)):
		return
	show_categories()
	shop_open = true
	shop_animating = true
	shop_button.hide()
	money_box.hide()
	animate_shop(true)
	if cycle != null:
		update_cycle()

func close_shop() -> void:
	if not shop_open or shop_animating:
		return
	shop_open = false
	shop_animating = true
	animate_shop(false)
	if cycle != null:
		update_cycle()

func animate_shop(opened: bool) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT if opened else Tween.EASE_IN)
	var left: float = -PANEL_WIDTH if opened else 0.0
	var right: float = 0.0 if opened else PANEL_WIDTH
	tween.parallel().tween_property(shop_panel, "offset_left", left, ANIMATION_TIME)
	tween.parallel().tween_property(shop_panel, "offset_right", right, ANIMATION_TIME)
	tween.finished.connect(finish_animation)

func finish_animation() -> void:
	shop_animating = false
	if not shop_open:
		shop_button.show()
		money_box.show()
	if cycle != null:
		update_cycle()
