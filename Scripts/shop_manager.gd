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
const IntroCinematicScript = preload("res://Scripts/intro_cinematic.gd")
const WorldInteractionsScript = preload("res://Scripts/world_interactions.gd")

const PANEL_WIDTH := 340.0
const TOGGLE_SIZE := 58.0
const MONEY_BOX_WIDTH := 148.0
const ANIMATION_TIME := 0.3
const CATEGORIES := ["EXPANSION", "BASE", "DEFENSA", "INVESTIGACIÓN"]
const RESEARCH_VIEW := {
	"drill": ["drill", "Taladro", "Automático"],
	"brass": ["ore", "Latón", "Nueva veta"],
	"straight_belt": ["belt", "Cinta", "Transportadora"],
	"curved_belts": ["curve", "Curvas", "Izquierda · derecha"],
	"junction_belt": ["junction", "Unión en T", "3 entradas"],
}

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
var research_details: Dictionary = {}
var item_buttons: Dictionary = {}
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
	ensure_interactions.call_deferred()

func ensure_interactions() -> void:
	var game: Node = get_parent().get_parent()
	if not game.has_node("WorldInteractions"):
		var interactions := WorldInteractionsScript.new()
		interactions.name = "WorldInteractions"
		game.add_child(interactions)

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
	ensure_intro.call_deferred()

func ensure_intro() -> void:
	# Install from the shop so older scenes with a built-in main script work too.
	if Engine.has_meta(IntroCinematicScript.SESSION_KEY):
		return
	var intro := IntroCinematicScript.new()
	intro.name = "IntroCinematic"
	get_parent().get_parent().add_child(intro)

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
	# Legacy scene scripts must also treat research solely as item unlocks.
	var game: Node = get_parent().get_parent()
	for connection in progression.technology_unlocked.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == game and callback.get_method() == &"apply_technologies":
			progression.technology_unlocked.disconnect(callback)
	build_progression_panel()
	progression.changed.connect(update_progression)
	update_progression()

func _process(_delta: float) -> void:
	if progression == null:
		return
	# Preserve research locks even with older scenes that handle purchases themselves.
	var game: Node = get_parent().get_parent()
	var item: String = "brass" if game.get("placing_brass") else ("drill" if game.get("placing_drill") else (str(game.get("belt_shape")) if game.get("placing_belt") else ""))
	if not item.is_empty() and not progression.is_item_unlocked(item):
		game.cancel_placement()

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
	refresh_item_buttons()

func open_research() -> void:
	if cycle != null and (cycle.is_night or cycle.defeated):
		return
	if not shop_open:
		open_shop()
	if shop_open:
		open_category("INVESTIGACIÓN")

func build_research_content() -> void:
	if progression == null:
		return
	research_summary = create_label("", 17, Color("#d6edb4"))
	research_summary.tooltip_text = "Cada nivel otorga 1 punto de investigación.\nEXP: zombis +10 · carbón vendido +2 · latón vendido +3."
	shop_content.add_child(research_summary)
	var previous_branch: String = ""
	var row: HBoxContainer
	var section: VBoxContainer
	var branch_count: int = 0
	for technology_id in progression.RESEARCHES:
		var data: Dictionary = progression.RESEARCHES[technology_id]
		var branch: String = data["branch"]
		if branch != previous_branch:
			section = VBoxContainer.new()
			section.add_theme_constant_override("separation", 6)
			shop_content.add_child(section)
			section.add_child(create_label(branch, 13, Color("#c8ad79")))
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 5)
			section.add_child(row)
			previous_branch = branch
			branch_count = 0
		elif branch_count % 2 == 0:
			var down := create_label("↓", 15, Color("#a18a61"))
			down.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			section.add_child(down)
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 5)
			section.add_child(row)
		else:
			var arrow := create_label("→", 19, Color("#a18a61"))
			arrow.custom_minimum_size.x = 18
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(arrow)
		row.add_child(build_research_card(technology_id, data))
		branch_count += 1
	refresh_research_buttons()

func build_research_card(technology_id: String, data: Dictionary) -> Button:
	var view: Array = RESEARCH_VIEW[technology_id]
	var button := Button.new()
	button.name = "Research_" + technology_id
	button.custom_minimum_size = Vector2(116, 116)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.pressed.connect(technology_requested.emit.bind(technology_id))
	research_buttons[technology_id] = button
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	var icon := ResearchIcon.new()
	icon.kind = view[0]
	icon.custom_minimum_size = Vector2(28, 28)
	header.add_child(icon)
	var rank := compact_research_label("", 13)
	rank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(rank)
	var title := compact_research_label(view[1], 14)
	column.add_child(title)
	var effect := compact_research_label(view[2], 11)
	column.add_child(effect)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)
	var cost := compact_research_label("%d PI" % data["cost"], 12)
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(cost)
	var status := compact_research_label("", 11)
	footer.add_child(status)
	research_status[technology_id] = status
	var state_icon := ResearchIcon.new()
	state_icon.custom_minimum_size = Vector2(16, 16)
	footer.add_child(state_icon)
	research_details[technology_id] = {"icon": icon, "state_icon": state_icon, "title": title, "effect": effect, "cost": cost, "rank": rank}
	return button

func compact_research_label(text: String, font_size: int) -> Label:
	var label := create_label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func refresh_research_buttons() -> void:
	if progression == null:
		return
	if research_summary != null:
		research_summary.text = "Nivel %d · %d PI" % [progression.level, progression.research_points]
	var blocked: bool = cycle != null and (cycle.is_night or cycle.defeated or cycle.is_tutorial_active())
	for technology_id in research_buttons:
		var button: Button = research_buttons[technology_id]
		var data: Dictionary = progression.RESEARCHES[technology_id]
		var details: Dictionary = research_details[technology_id]
		var researched: bool = progression.has_technology(technology_id)
		button.disabled = researched or blocked or not progression.can_research(technology_id)
		var available: bool = not button.disabled
		var color := Color("#a9ca91") if researched else (Color("#f0cd91") if available else Color("#988b75"))
		var background: String = "#263b2c" if researched else ("#443622" if available else "#2b261e")
		var border: String = "#83aa6c" if researched else ("#d5b078" if available else "#584d3b")
		button.add_theme_stylebox_override("normal", create_style(background, border, 2, 9))
		button.add_theme_stylebox_override("disabled", create_style(background, border, 2, 9))
		button.add_theme_stylebox_override("hover", create_style("#5b4729", "#f0d198", 2, 9))
		button.add_theme_stylebox_override("pressed", create_style("#302b1f", "#e4c28a", 2, 9))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW
		for name in ["title", "effect", "cost", "rank"]:
			details[name].add_theme_color_override("font_color", color)
		details["icon"].tint = color
		details["icon"].queue_redraw()
		details["state_icon"].kind = "done" if researched else ("add" if available else "lock")
		details["state_icon"].tint = color
		details["state_icon"].queue_redraw()
		var status: Label = research_status[technology_id]
		status.text = "Nv. %d" % data["level"] if not researched and progression.level < int(data["level"]) else ""
		status.add_theme_color_override("font_color", color)
		var reason: String = progression.research_block_reason(technology_id)
		if blocked and not researched:
			reason = "Completa el tutorial." if cycle.is_tutorial_active() else "Investiga durante el día."
		button.tooltip_text = "%s\n%s\nNivel %d · %d PI" % [data["name"], data["description"], data["level"], data["cost"]]
		for prerequisite in data["requires"]:
			button.tooltip_text += "\nRequiere: %s" % progression.RESEARCHES[prerequisite]["name"]
		button.tooltip_text += "\n" + ("Pulsa para investigar." if available else reason)

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
	cycle_badge = create_label("", 12, Color("#efd29b"))
	cycle_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(cycle_badge)
	cycle_steps = HBoxContainer.new()
	cycle_steps.add_theme_constant_override("separation", 5)
	column.add_child(cycle_steps)
	for index in range(cycle.TUTORIAL_LAST_STEP):
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
	var guide: Node = get_parent().get_parent().get_node_or_null("TutorialGuide")
	if guide != null and guide.resupply_active():
		guide.resupply_action()
		return
	if cycle.defeated:
		restart_requested.emit()
	elif cycle.is_tutorial_active():
		match cycle.tutorial_step:
			0: coal_vein_requested.emit()
			2: expansion_requested.emit()
			3: unlock_defense_platforms()
			4: launcher_requested.emit()
			6: night_requested.emit()
		update_cycle()
	elif cycle.can_start_night() and not shop_open and not shop_animating:
		night_requested.emit()

func update_cycle() -> void:
	if cycle == null or cycle_title == null:
		return
	var tutorial: bool = cycle.is_tutorial_active()
	cycle_heading.text = "PRIMEROS PASOS" if tutorial else "DEFENSA DE LA BASE"
	cycle_badge.text = "%02d / %02d" % [mini(cycle.tutorial_step + 1, cycle.TUTORIAL_LAST_STEP), cycle.TUTORIAL_LAST_STEP] if tutorial else "DÍA %d" % cycle.day
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
			1, 5:
				if cycle.tutorial_step == 5:
					cycle_action.text = "MUNICIÓN · %d / 4" % roundi(cycle.ammo_damage() / 0.5)
				else:
					cycle_action.text = "CARBÓN VENDIDO · %d / %d" % [mini(cycle.coal_sold, cycle.TUTORIAL_SALES_TARGET), cycle.TUTORIAL_SALES_TARGET]
				cycle_action.disabled = true
			2:
				cycle_action.text = "AMPLIAR A 7 × 5 · 500"
				cycle_action.disabled = not economy.can_afford(economy.EXPANSION_PRICE)
			3:
				cycle_action.text = "DESBLOQUEAR DEFENSAS · 100"
				cycle_action.disabled = not economy.can_afford(economy.DEFENSE_TILE_PRICE)
			4:
				cycle_action.text = "COLOCA EL LANZAPAPAS" if game.get("placing_launcher") else "OBTENER LANZAPAPAS · GRATIS"
				cycle_action.disabled = game.get("placing_launcher")
				if game.get("placing_launcher"):
					cycle_goal.text = "Coloca el lanzapapas en la plataforma izquierda resaltada en dorado."
			6:
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
	view_button.disabled = tutorial or cycle.defeated
	var guide: Node = get_parent().get_parent().get_node_or_null("TutorialGuide")
	if guide != null and guide.resupply_active():
		guide.apply_resupply_card(self)
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
	view_button.pressed.connect(request_view_toggle)
	add_child(view_button)

func request_view_toggle() -> void:
	if cycle != null and cycle.is_night:
		# Older built-in main scripts still lock navigation during combat.
		get_parent().get_parent().get_node("WorldInteractions").toggle_night_view()
	else:
		view_toggle_requested.emit()

func set_view_mode(defense_enabled: bool) -> void:
	view_button.text = "MINA" if defense_enabled else "DEFENSIVA"

func update_money(amount: int) -> void:
	money_label.text = "∞ DEV" if economy.developer_mode else str(amount)
	if shop_open:
		if shop_title.text == "INVESTIGACIÓN":
			return
		if shop_title.text == "BASE":
			refresh_item_buttons()
			return
		if shop_title.text in CATEGORIES:
			open_category(shop_title.text)
		else:
			show_categories()

func clear_content() -> void:
	item_buttons.clear()
	research_buttons.clear()
	research_status.clear()
	research_details.clear()
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
		"INVESTIGACIÓN":
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
			add_item_button("VETA DE CARBÓN · 100", economy.COAL_VEIN_PRICE, "coal", coal_vein_requested)
			add_item_button("VETA DE LATÓN · 150", economy.BRASS_VEIN_PRICE, "brass", brass_vein_requested)
			shop_content.add_child(create_label("AUTOMATIZACION", 19, Color("#f3ca85")))
			add_item_button("CINTA RECTA · 50", economy.CONVEYOR_PRICE, "straight", conveyor_requested)
			add_item_button("CINTA EN L DERECHA · 50", economy.CONVEYOR_PRICE, "corner_right", corner_conveyor_requested)
			add_item_button("CINTA EN L IZQUIERDA · 50", economy.CONVEYOR_PRICE, "corner_left", left_corner_conveyor_requested)
			add_item_button("CINTA EN T · 50", economy.CONVEYOR_PRICE, "junction", junction_conveyor_requested)
			add_item_button("TALADRO AUTOMÁTICO · 200", economy.DRILL_PRICE, "drill", drill_requested)
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

func add_item_button(text: String, price: int, item: String, request: Signal) -> void:
	var button := create_button(text)
	button.pressed.connect(request_item.bind(item, request))
	item_buttons[item] = {"button": button, "price": price}
	var icon := ResearchIcon.new()
	icon.name = "ResearchLock"
	icon.kind = "lock"
	icon.position = Vector2(9, 17)
	icon.size = Vector2(15, 15)
	button.add_child(icon)
	shop_content.add_child(button)
	refresh_item_buttons()

func request_item(item: String, request: Signal) -> void:
	if progression != null and not progression.is_item_unlocked(item):
		return
	if cycle != null and (cycle.is_night or cycle.defeated or cycle.is_tutorial_active()):
		return
	request.emit()

func refresh_item_buttons() -> void:
	for item in item_buttons:
		var button: Button = item_buttons[item]["button"]
		var unlocked: bool = progression == null or progression.is_item_unlocked(item)
		button.disabled = not unlocked or not economy.can_afford(item_buttons[item]["price"]) or (cycle != null and (cycle.is_night or cycle.defeated or cycle.is_tutorial_active()))
		button.get_node("ResearchLock").visible = not unlocked
		button.tooltip_text = ""
		if not unlocked:
			button.tooltip_text = "Investigar: %s" % progression.RESEARCHES[progression.ITEM_RESEARCH[item]]["name"]

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

class ResearchIcon extends Control:
	var kind: String = "lock"
	var tint := Color("#d5b078")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var factor: float = minf(size.x, size.y) / 32.0
		draw_set_transform((size - Vector2.ONE * 32.0 * factor) * 0.5, 0.0, Vector2.ONE * factor)
		match kind:
			"ore":
				draw_colored_polygon(PackedVector2Array([Vector2(3, 22), Vector2(8, 9), Vector2(21, 5), Vector2(29, 17), Vector2(23, 28), Vector2(9, 28)]), tint)
				draw_line(Vector2(10, 12), Vector2(18, 9), Color("#352516"), 2, true)
			"curve", "junction":
				var lines := [PackedVector2Array([Vector2(5, 27), Vector2(5, 7), Vector2(27, 7)]), PackedVector2Array([Vector2(13, 27), Vector2(13, 15), Vector2(27, 15)])]
				for points in lines:
					draw_polyline(points, tint, 2.5, true)
				if kind == "junction":
					draw_line(Vector2(9, 11), Vector2(9, 1), tint, 5, true)
			"pickaxe":
				draw_line(Vector2(9, 27), Vector2(20, 9), tint, 3.5, true)
				draw_polyline(PackedVector2Array([Vector2(5, 15), Vector2(13, 7), Vector2(23, 8), Vector2(28, 14)]), tint, 3.5, true)
			"drill":
				draw_rect(Rect2(7, 4, 18, 6), tint)
				draw_rect(Rect2(11, 12, 10, 8), tint)
				draw_colored_polygon(PackedVector2Array([Vector2(11, 22), Vector2(21, 22), Vector2(16, 30)]), tint)
			"belt", "fast_belt":
				draw_rect(Rect2(2, 9, 28, 15), tint, false, 2.0)
				draw_circle(Vector2(7, 16.5), 2, tint)
				draw_circle(Vector2(25, 16.5), 2, tint)
				for offset in ([0, 6] if kind == "fast_belt" else [3]):
					draw_polyline(PackedVector2Array([Vector2(10 + offset, 12), Vector2(15 + offset, 16.5), Vector2(10 + offset, 21)]), tint, 2, true)
			"target":
				draw_arc(Vector2(16, 16), 10, 0, TAU, 24, tint, 2, true)
				draw_circle(Vector2(16, 16), 3, tint)
				draw_line(Vector2(16, 1), Vector2(16, 8), tint, 2, true)
				draw_line(Vector2(16, 24), Vector2(16, 31), tint, 2, true)
				draw_line(Vector2(1, 16), Vector2(8, 16), tint, 2, true)
				draw_line(Vector2(24, 16), Vector2(31, 16), tint, 2, true)
			"ammo":
				for x in [5, 13, 21]:
					draw_rect(Rect2(x, 12, 5, 15), tint)
					draw_colored_polygon(PackedVector2Array([Vector2(x, 10), Vector2(x + 5, 10), Vector2(x + 2.5, 4)]), tint)
			"done":
				draw_polyline(PackedVector2Array([Vector2(6, 16), Vector2(13, 23), Vector2(27, 8)]), tint, 3.5, true)
			"add":
				draw_line(Vector2(7, 16), Vector2(25, 16), tint, 3, true)
				draw_line(Vector2(16, 7), Vector2(16, 25), tint, 3, true)
			"lock":
				draw_arc(Vector2(16, 13), 7, PI, TAU, 16, tint, 2.5, true)
				draw_rect(Rect2(6, 13, 20, 15), tint, false, 2.5)
				draw_line(Vector2(16, 18), Vector2(16, 23), tint, 2.5, true)
