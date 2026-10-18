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
signal furnace_requested
signal compactor_requested
signal night_requested
signal restart_requested
signal technology_requested(technology_id: String)

const DisplaySettingsScript = preload("res://Scripts/display_settings.gd")
const TutorialGuideScript = preload("res://Scripts/tutorial_guide.gd")
const IntroCinematicScript = preload("res://Scripts/intro_cinematic.gd")
const WorldInteractionsScript = preload("res://Scripts/world_interactions.gd")
const FurnaceScript = preload("res://Scripts/furnace_manager.gd")
const InspectorScript = preload("res://Scripts/tool_inspector.gd")
const CompactorScript = preload("res://Scripts/compactor_manager.gd")

const PANEL_WIDTH := 340.0
const TOGGLE_SIZE := 58.0
const MONEY_BOX_WIDTH := 148.0
const ANIMATION_TIME := 0.3
const CATEGORIES := ["EXPANSION", "VETAS", "HERRAMIENTAS", "AUTOMATIZACIÓN", "DEFENSA", "INVESTIGACIÓN"]
const ITEM_CATEGORIES := {
	"VETAS": ["coal", "brass", "iron"],
	"HERRAMIENTAS": ["drill", "compactor", "furnace"],
	"AUTOMATIZACIÓN": ["straight", "corner_right", "corner_left", "junction"],
}
const RESOURCE_LABELS := {"iron": "HIERRO · NIVEL 1", "iron_2": "HIERRO · NIVEL 2", "iron_3": "HIERRO · NIVEL 3", "iron_4": "HIERRO · NIVEL 4", "iron_ingot": "LINGOTE DE HIERRO · NIVEL 1", "iron_ingot_2": "LINGOTE DE HIERRO · NIVEL 2", "iron_ingot_3": "LINGOTE DE HIERRO · NIVEL 3", "iron_ingot_4": "LINGOTE DE HIERRO · NIVEL 4", "coal": "CARBÓN · NIVEL 1", "brass": "LATÓN · NIVEL 1", "coal_2": "CARBÓN · NIVEL 2", "brass_2": "LATÓN · NIVEL 2", "coal_3": "CARBÓN · NIVEL 3", "brass_3": "LATÓN · NIVEL 3", "coal_4": "CARBÓN · NIVEL 4", "brass_4": "LATÓN · NIVEL 4", "brass_ingot": "LINGOTE DE LATÓN · NIVEL 1", "brass_ingot_2": "LINGOTE DE LATÓN · NIVEL 2", "brass_ingot_3": "LINGOTE DE LATÓN · NIVEL 3", "brass_ingot_4": "LINGOTE DE LATÓN · NIVEL 4"}
const CATEGORY_ART := {"EXPANSION": "expansion", "VETAS": "coal", "HERRAMIENTAS": "drill", "AUTOMATIZACIÓN": "junction", "DEFENSA": "launcher", "INVESTIGACIÓN": "research", "RECURSOS": "resources"}
const RESEARCH_VIEW := {
	"iron": ["iron", "Hierro", "Nueva veta"],
	"drill": ["drill", "Taladro", "Automático"],
	"brass": ["ore", "Latón", "Nueva veta"],
	"straight_belt": ["belt", "Cinta", "Transportadora"],
	"curved_belts": ["curve", "Curvas", "Izquierda · derecha"],
	"junction_belt": ["junction", "Unión en T", "3 entradas"],
	"compactor": ["compactor", "Compactador", "2 → 1"],
	"furnace": ["furnace", "Horno", "40 combustible"],
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
var outside_click_pending: bool = false
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
var cycle_goal: RichTextLabel
var cycle_action: Button
var progression: RefCounted
var progression_panel: PanelContainer
var level_label: Label
var research_points_label: RichTextLabel
var view_icon: ViewIcon
var experience_bar: ProgressBar
var research_summary: RichTextLabel
var research_texture: Texture2D
var research_buttons: Dictionary = {}
var research_status: Dictionary = {}
var research_details: Dictionary = {}
var item_buttons: Dictionary = {}
var resource_buttons: Dictionary = {}
var item_grid: GridContainer
var category_buttons: Dictionary = {}
var purchase_buttons: Dictionary = {}
var fallback_display: CanvasLayer
var known_research_level: int = 1
var research_notice: PanelContainer
var research_notice_backdrop: ColorRect
var research_notice_label: Label
var research_notice_timer: Timer
var notice_research_ids: Array[String] = []

func setup(economy_manager: RefCounted, grid_manager: RefCounted) -> void:
	economy = economy_manager
	grid = grid_manager
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_interface()
	economy.money_changed.connect(update_money)
	update_money(economy.coins)
	furnace_requested.connect(func() -> void: get_parent().get_parent().get_node("WorldInteractions").select_item("furnace"))
	compactor_requested.connect(func() -> void: get_parent().get_parent().get_node("Compactors").buy())
	# Older scenes can have a built-in main script. Updating main.gd alone
	# does not update those scenes, so install the pause menu here as well.
	ensure_pause_menu.call_deferred()
	ensure_interactions.call_deferred()

func ensure_interactions() -> void:
	var game: Node = get_parent().get_parent()
	if not game.has_node("Furnaces"):
		var furnaces := FurnaceScript.new()
		furnaces.name = "Furnaces"
		game.add_child(furnaces)
	if not game.has_node("Compactors"):
		var compactors := CompactorScript.new()
		compactors.name = "Compactors"
		game.add_child(compactors)
	if not game.has_node("Construction"):
		var construction := preload("res://Scripts/construction_manager.gd").new()
		construction.name = "Construction"
		game.add_child(construction)
	if not game.has_node("WorldInteractions"):
		var interactions := WorldInteractionsScript.new()
		interactions.name = "WorldInteractions"
		game.add_child(interactions)
	if not game.has_node("ToolInspector"):
		var inspector := InspectorScript.new()
		inspector.name = "ToolInspector"
		game.add_child(inspector)

	if not game.has_node("WorkshopRhythm"):
		var rhythm := preload("res://Scripts/workshop_rhythm.gd").new()
		rhythm.name = "WorkshopRhythm"
		game.add_child(rhythm)

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
	get_parent().get_parent().get("camera_controller").bind_cycle(cycle)
	build_cycle_panel()
	cycle.changed.connect(update_cycle)
	cycle.launchers.changed.connect(update_cycle)
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
	progression.developer_mode = economy.developer_mode
	known_research_level = progression.level
	cycle.set_progression(progression)
	# Legacy scene scripts must also treat research solely as item unlocks.
	var game: Node = get_parent().get_parent()
	for connection in progression.technology_unlocked.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == game and callback.get_method() == &"apply_technologies":
			progression.technology_unlocked.disconnect(callback)
	build_progression_panel()
	build_research_notice()
	progression.changed.connect(update_progression)
	update_progression()

func _process(_delta: float) -> void:
	if progression == null:
		return
	update_notice_visibility()
	# Preserve research locks even with older scenes that handle purchases themselves.
	var game: Node = get_parent().get_parent()
	var item: String = ""
	if game.get("placing_coal"): item = "coal"
	elif game.get("placing_launcher"): item = "launcher"
	elif game.get("placing_brass"): item = "brass"
	elif game.get("placing_drill"): item = "drill"
	elif game.get("placing_belt"): item = str(game.get("belt_shape"))
	if not item.is_empty() and (not progression.is_item_unlocked(item) or (cycle != null and cycle.is_research_tutorial_active())):
		game.cancel_placement()

func build_progression_panel() -> void:
	progression_panel = PanelContainer.new()
	progression_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	progression_panel.offset_left = 20.0
	progression_panel.offset_right = 220.0
	progression_panel.offset_top = 20.0
	progression_panel.offset_bottom = 58.0
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
	level_label.size_flags_horizontal = Control.SIZE_FILL
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_color_override("font_outline_color", Color("#152019"))
	level_label.add_theme_constant_override("outline_size", 3)
	row.add_child(level_label)
	level_label.custom_minimum_size.y = 24
	research_points_label = create_research_label("", 14, Color("#d6edb4"))
	research_points_label.custom_minimum_size = Vector2(66, 24)
	research_points_label.add_theme_color_override("font_outline_color", Color("#152019"))
	research_points_label.add_theme_constant_override("outline_size", 3)
	row.add_child(research_points_label)
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
	set_research_text(research_points_label, "{research} %d" % progression.research_points)
	experience_bar.max_value = progression.experience_to_next_level()
	experience_bar.value = progression.experience
	experience_bar.tooltip_text = "EXP %d / %d\nZombi +%d · venta de carbón +%d · venta de latón +%d." % [progression.experience, progression.experience_to_next_level(), progression.ZOMBIE_EXPERIENCE, progression.SALE_EXPERIENCE["coal"], progression.SALE_EXPERIENCE["brass"]]
	progression_panel.visible = true
	if progression.level > known_research_level:
		var old_ids: Array[String] = progression.visible_researches(known_research_level)
		var new_ids: Array[String] = []
		for research_id: String in progression.visible_researches():
			if research_id not in old_ids and not progression.has_research(research_id): new_ids.append(research_id)
		known_research_level = progression.level
		announce_researches(new_ids)
	if shop_open and shop_title.text == "INVESTIGACIÓN" and research_buttons.keys() != progression.visible_researches():
		rebuild_catalog()
	elif shop_open and shop_title.text in ITEM_CATEGORIES and item_buttons.keys() != visible_shop_items(shop_title.text):
		rebuild_catalog()
	refresh_research_buttons()
	refresh_item_buttons()

func visible_shop_items(category: String = "") -> Array[String]:
	var result: Array[String] = []
	for item: String in ["coal", "brass", "iron", "straight", "corner_right", "corner_left", "junction", "drill", "compactor", "furnace"]:
		if not category.is_empty() and item not in ITEM_CATEGORIES.get(category, []): continue
		if progression == null or progression.is_item_unlocked(item): result.append(item)
	return result

func rebuild_catalog() -> void:
	var scroll: int = shop_scroll.scroll_vertical
	open_category(shop_title.text)
	shop_scroll.set_deferred("scroll_vertical", scroll)

func build_research_notice() -> void:
	research_notice_backdrop = ColorRect.new()
	research_notice_backdrop.name = "ResearchNoticeBackdrop"
	research_notice_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	research_notice_backdrop.color = Color(0, 0, 0, 0.65)
	research_notice_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	research_notice_backdrop.z_index = 120
	add_child(research_notice_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	research_notice_backdrop.add_child(center)
	research_notice = PanelContainer.new()
	research_notice.name = "NewResearchNotice"
	research_notice.custom_minimum_size = Vector2(420, 100)
	research_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := create_style("#192920", "#d5b078", 1, 9)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	research_notice.add_theme_stylebox_override("panel", style)
	center.add_child(research_notice)
	research_notice_label = create_label("", 15, Color("#efd5a2"))
	research_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	research_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	research_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	research_notice.add_child(research_notice_label)
	research_notice.hide()
	research_notice_backdrop.hide()
	research_notice_timer = Timer.new()
	research_notice_timer.one_shot = true
	research_notice_timer.wait_time = 3.0
	research_notice_timer.timeout.connect(func() -> void:
		research_notice.hide()
		research_notice_backdrop.hide()
		notice_research_ids.clear())
	add_child(research_notice_timer)

func announce_researches(research_ids: Array[String]) -> void:
	if research_ids.is_empty(): return
	for research_id: String in research_ids:
		if research_id not in notice_research_ids: notice_research_ids.append(research_id)
	var names: PackedStringArray = []
	for research_id: String in notice_research_ids: names.append(RESEARCH_VIEW[research_id][1])
	research_notice_label.text = "Nuevas investigaciones\n" + " · ".join(names)
	research_notice_timer.stop()
	research_notice.hide()
	research_notice_backdrop.hide()
	update_notice_visibility()

func update_notice_visibility() -> void:
	if research_notice == null or notice_research_ids.is_empty(): return
	var victory: Control = get_parent().get_parent().get("night_victory_overlay")
	if (cycle != null and (cycle.is_night or cycle.defeated)) or (victory != null and victory.visible):
		research_notice.hide()
		research_notice_backdrop.hide()
		research_notice_timer.stop()
	elif not research_notice.visible:
		research_notice.show()
		research_notice_backdrop.show()
		research_notice_timer.start()

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
	research_summary = create_research_label("", 17, Color("#d6edb4"))
	research_summary.tooltip_text = "Cada nivel y cada noche superada otorgan 1 punto de investigación.\nEXP: zombi +%d · carbón vendido +%d · latón vendido +%d." % [progression.ZOMBIE_EXPERIENCE, progression.SALE_EXPERIENCE["coal"], progression.SALE_EXPERIENCE["brass"]]
	shop_content.add_child(research_summary)
	var previous_branch: String = ""
	var row: HBoxContainer
	var section: VBoxContainer
	var branch_count: int = 0
	for technology_id in progression.visible_researches():
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
	button.custom_minimum_size = Vector2(116, 86)
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
	var icon := ItemPreview.new()
	icon.kind = {"straight_belt": "straight", "curved_belts": "corner_right", "junction_belt": "junction"}.get(technology_id, technology_id)
	icon.custom_minimum_size = Vector2(28, 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(icon)
	var rank := compact_research_label("", 13)
	rank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(rank)
	rank.hide()
	var title := create_label(view[1], 13)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var effect := compact_research_label(view[2], 11)
	column.add_child(effect)
	effect.hide()
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)
	var cost := create_research_label("%d {research}" % data["cost"], 12)
	cost.custom_minimum_size = Vector2(48, 22)
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
		set_research_text(research_summary, "Nivel %d · %d {research}" % [progression.level, progression.research_points])
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
			details[name].add_theme_color_override("default_color" if details[name] is RichTextLabel else "font_color", color)
		details["icon"].tint = Color.WHITE if researched or available else Color(1, 1, 1, 0.5)
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
		button.tooltip_text = "%s\n%s\nNivel %d · Coste: %d de investigación" % [data["name"], data["description"], data["level"], data["cost"]]
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
	cycle_goal = create_research_label("", 14, Color("#bacbb7"))
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
	if cycle_action.disabled or not cycle_action.visible:
		return
	var guide: Node = get_parent().get_parent().get_node_or_null("TutorialGuide")
	if guide != null and guide.resupply_active():
		return
	if cycle.defeated:
		restart_requested.emit()
	elif cycle.is_tutorial_active():
		if cycle.tutorial_step == cycle.TUTORIAL_LAST_STEP:
			night_requested.emit()
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
	cycle_goal.add_theme_color_override("default_color", Color("#bacbb7"))
	cycle_action.show()
	for index in range(cycle_steps.get_child_count()):
		cycle_steps.get_child(index).color = Color("#8db574") if index < cycle.tutorial_step else (Color("#e1b879") if index == cycle.tutorial_step else Color("#354b3a"))
	if tutorial:
		cycle_title.text = cycle.tutorial_title()
		cycle_goal.text = cycle.tutorial_text()
		cycle_action.disabled = false
		var game: Node = get_parent().get_parent()
		match cycle.tutorial_step:
			0:
				cycle_action.hide()
				if game.get("placing_coal"):
					cycle_goal.text = "Coloca la veta en la casilla dorada."
				else:
					cycle_goal.text = tutorial_navigation_text()
			1, 6:
				cycle_action.text = "MUNICIÓN · %d / 4" % roundi(cycle.ammo_damage() / 0.5) if cycle.tutorial_step == 6 else "CARBÓN VENDIDO · %d / %d" % [mini(cycle.coal_sold, cycle.TUTORIAL_SALES_TARGET), cycle.TUTORIAL_SALES_TARGET]
				cycle_action.disabled = true
			2:
				cycle_action.text = "2 × Nv. 1 → Nv. 2"
				cycle_action.disabled = true
			3, 4, 5:
				cycle_action.hide()
				if cycle.needs_tutorial_income():
					cycle_goal.text = cycle.tutorial_text()
				elif game.get("placing_launcher"):
					cycle_goal.text = "Coloca el Lanzapepitas en la plataforma dorada."
				else:
					cycle_goal.text = tutorial_navigation_text()
			7:
				cycle_action.text = "INICIAR PRIMERA NOCHE"
				cycle_action.disabled = not cycle.can_start_night()
	elif cycle.is_research_tutorial_active():
		cycle_heading.text = "INVESTIGACIÓN"
		cycle_title.text = "Tu primer desbloqueo"
		set_research_text(cycle_goal, "Tienes %d {research}. %s" % [progression.research_points, tutorial_navigation_text()])
		cycle_action.hide()
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
		if cycle.needs_defense_warning():
			cycle_goal.text = "Alto riesgo de perder. Coloca al menos 2 torretas."
			cycle_goal.add_theme_color_override("default_color", Color("#edbb76"))
	shop_button.disabled = (tutorial and tutorial_purchase().is_empty()) or cycle.is_night or cycle.defeated
	view_button.disabled = cycle.is_guided_tutorial_active() or cycle.defeated
	var guide: Node = get_parent().get_parent().get_node_or_null("TutorialGuide")
	if guide != null and guide.resupply_active():
		guide.apply_resupply_card(self)
	update_progression()

func tutorial_purchase() -> Dictionary:
	if cycle != null and cycle.is_research_tutorial_active():
		return {"category": "INVESTIGACIÓN", "item": "research", "instruction": "Desbloquea un objeto a tu elección."}
	if cycle == null or not cycle.is_tutorial_active() or cycle.needs_tutorial_income():
		return {}
	var game: Node = get_parent().get_parent()
	match cycle.tutorial_step:
		0:
			if not game.get("placing_coal"):
				return {"category": "VETAS", "item": "coal", "instruction": "Compra la veta de carbón."}
		3:
			return {"category": "EXPANSION", "item": "expansion", "instruction": "Compra la ampliación a 7 × 5."}
		4:
			return {"category": "DEFENSA", "item": "defense_platforms", "instruction": "Compra las plataformas."}
		5:
			if not game.get("placing_launcher"):
				return {"category": "DEFENSA", "item": "launcher", "instruction": "Compra el Lanzapepitas."}
	return {}

func tutorial_navigation_text() -> String:
	var purchase: Dictionary = tutorial_purchase()
	if purchase.is_empty(): return ""
	if not shop_open: return "Abre el menú ☰."
	if shop_title.text != purchase["category"]:
		return "Entra en %s." % ("EXPANSIÓN" if purchase["category"] == "EXPANSION" else purchase["category"])
	return purchase["instruction"]

func tutorial_ui_target() -> Control:
	var purchase: Dictionary = tutorial_purchase()
	if purchase.is_empty() or shop_animating: return null
	if not shop_open: return shop_button
	if shop_title.text != purchase["category"]:
		return category_buttons.get(purchase["category"])
	if purchase["item"] == "research":
		return research_summary
	return purchase_buttons.get(purchase["item"])

func tutorial_allows_item(item: String) -> bool:
	if cycle != null and cycle.is_research_tutorial_active(): return false
	if cycle == null or not cycle.is_tutorial_active(): return true
	var purchase: Dictionary = tutorial_purchase()
	return shop_open and not shop_animating and not purchase.is_empty() and purchase["item"] == item and shop_title.text == purchase["category"]

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

# Catalog tiles show the same models that are drawn on the playing field.
func catalog_grid() -> GridContainer:
	if item_grid == null:
		item_grid = GridContainer.new()
		item_grid.columns = 1
		item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_grid.add_theme_constant_override("h_separation", 8)
		item_grid.add_theme_constant_override("v_separation", 8)
		shop_content.add_child(item_grid)
	return item_grid

func create_art_button(kind: String, description: String, price: int = -1) -> Button:
	var button := create_button("")
	button.custom_minimum_size = Vector2(116, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = description
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var art := ItemPreview.new()
	art.kind = kind
	art.custom_minimum_size = Vector2(36, 36)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var short_names := {"ore:iron": "Hierro · Nv. 1", "ore:iron_2": "Hierro · Nv. 2", "ore:iron_3": "Hierro · Nv. 3", "ore:iron_4": "Hierro · Nv. 4", "ore:iron_ingot": "Ling. hierro · Nv. 1", "ore:iron_ingot_2": "Ling. hierro · Nv. 2", "ore:iron_ingot_3": "Ling. hierro · Nv. 3", "ore:iron_ingot_4": "Ling. hierro · Nv. 4",
		"expansion": "Ampliar base", "coal": "Carbón", "brass": "Latón", "iron": "Hierro",
		"drill": "Taladro", "compactor": "Compactador", "furnace": "Horno", "straight": "Cinta recta",
		"corner_right": "Cinta L derecha", "corner_left": "Cinta L izquierda",
		"junction": "Cinta en T", "platform": "Plataformas", "launcher": "Lanzapepitas",
		"ore:coal": "Carbón · Nv. 1", "ore:brass": "Latón · Nv. 1",
		"ore:coal_2": "Carbón · Nv. 2", "ore:brass_2": "Latón · Nv. 2",
		"ore:coal_3": "Carbón · Nv. 3", "ore:brass_3": "Latón · Nv. 3",
		"ore:coal_4": "Carbón · Nv. 4", "ore:brass_4": "Latón · Nv. 4",
		"ore:brass_ingot": "Lingote · Nv. 1", "ore:brass_ingot_2": "Lingote · Nv. 2",
		"ore:brass_ingot_3": "Lingote · Nv. 3", "ore:brass_ingot_4": "Lingote · Nv. 4",
	}
	var label := create_label(short_names.get(kind, description.capitalize()) if price >= 0 or kind.begins_with("ore:") else description.capitalize(), 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var cost := create_label("◆ %d" % price, 15, Color("#ffdf9c"))
	cost.autowrap_mode = TextServer.AUTOWRAP_OFF
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.visible = price >= 0
	row.add_child(cost)
	button.set_meta("price_label", cost)
	button.set_meta("item_art", art)
	return button

func create_item_preview(kind: String, minimum: Vector2 = Vector2(48, 48)) -> Control:
	var preview := ItemPreview.new()
	preview.kind = kind
	preview.custom_minimum_size = minimum
	return preview

func create_research_label(value: String, font_size: int = 17, color: Color = Color("#f0e0c8")) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	set_research_text(label, value)
	return label

func set_research_text(label: RichTextLabel, value: String) -> void:
	label.clear()
	var parts: PackedStringArray = value.split("{research}")
	for index in range(parts.size()):
		label.add_text(parts[index])
		if index < parts.size() - 1:
			if research_texture == null:
				var picture := Image.new()
				picture.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><path d="M12 4h8v9l7 11q2 5-4 5H9q-6 0-4-5l7-11Z" fill="#c9eff9" fill-opacity=".25" stroke="#b5e6f5" stroke-width="2" stroke-linejoin="round"/><path d="m10 19-4 7q0 2 3 2h14q3 0 3-2l-4-7Z" fill="#279ee8"/><path d="M11 19q5-3 11 0" fill="none" stroke="#67d7ff" stroke-width="2"/><path d="M12 3h8v4h-8Z" fill="#b48248" stroke="#e0b779"/><path d="M13 9v5l-5 10" fill="none" stroke="#e9faff" stroke-width="1.5" stroke-linecap="round"/><circle cx="18" cy="23" r="1.5" fill="#b1efff"/><circle cx="13" cy="25" r="1" fill="#b1efff"/></svg>')
				research_texture = ImageTexture.create_from_image(picture)
			label.add_image(research_texture, 20, 20)

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
	fixed_back_button = create_button("←")
	fixed_back_button.tooltip_text = "Volver"
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
	view_button = create_button("")
	view_button.custom_minimum_size = Vector2(44, 42)
	view_button.tooltip_text = "Ver defensas (P)"
	view_button.name = "BotonDefensiva"
	view_button.anchor_left = 0.0
	view_button.anchor_right = 0.0
	view_button.anchor_top = 0.0
	view_button.anchor_bottom = 0.0
	view_button.offset_left = 236.0
	view_button.offset_right = 280.0
	view_button.offset_top = 20.0
	view_button.offset_bottom = 62.0
	view_button.mouse_filter = Control.MOUSE_FILTER_STOP
	view_button.focus_mode = Control.FOCUS_NONE
	view_button.pressed.connect(request_view_toggle)
	add_child(view_button)
	view_icon = ViewIcon.new()
	view_button.add_child(view_icon)
	view_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

func request_view_toggle() -> void:
	if cycle != null and cycle.is_night:
		# Older built-in main scripts still lock navigation during combat.
		get_parent().get_parent().get_node("WorldInteractions").toggle_night_view()
	else:
		view_toggle_requested.emit()

func set_view_mode(defense_enabled: bool) -> void:
	view_button.tooltip_text = "Ver mina (P)" if defense_enabled else "Ver defensas (P)"
	view_icon.mine = defense_enabled
	view_icon.queue_redraw()

func update_money(amount: int) -> void:
	money_label.text = "∞ DEV" if economy.developer_mode else str(amount)
	if economy.developer_mode and cycle != null and not cycle.tutorial_skipped:
		var interactions: Node = get_parent().get_parent().get_node_or_null("WorldInteractions")
		if interactions != null: interactions.cancel_active()
		cycle.skip_tutorial()
	if progression != null:
		progression.developer_mode = economy.developer_mode
		var interactions: Node = get_parent().get_parent().get_node_or_null("WorldInteractions")
		if interactions != null and interactions.placement_active() and not interactions.selection_available():
			interactions.cancel_active()
	if shop_open:
		if shop_title.text == "RECURSOS":
			if not economy.developer_mode: show_categories()
			return
		if shop_title.text == "INVESTIGACIÓN":
			return
		if shop_title.text in ITEM_CATEGORIES:
			refresh_item_buttons()
			return
		if shop_title.text in CATEGORIES:
			open_category(shop_title.text)
		else:
			show_categories()

func clear_content() -> void:
	item_grid = null
	item_buttons.clear()
	resource_buttons.clear()
	category_buttons.clear()
	purchase_buttons.clear()
	research_buttons.clear()
	research_status.clear()
	research_details.clear()
	research_summary = null
	for child in shop_content.get_children():
		shop_content.remove_child(child)
		child.queue_free()

func show_categories() -> void:
	shop_title.text = "TIENDA"
	fixed_back_button.hide()
	shop_scroll.scroll_vertical = 0
	clear_content()
	var categories: Array = CATEGORIES.duplicate()
	if economy.developer_mode: categories.append("RECURSOS")
	for category in categories:
		var button := create_art_button(CATEGORY_ART[category], category.capitalize())
		button.disabled = cycle != null and cycle.is_guided_tutorial_active() and tutorial_purchase().get("category", "") != category
		button.pressed.connect(open_category.bind(category))
		category_buttons[category] = button
		catalog_grid().add_child(button)
	if cycle != null: update_cycle()

func open_category(category: String) -> void:
	if category == "RECURSOS" and not economy.developer_mode: return
	if shop_animating or (cycle != null and cycle.is_guided_tutorial_active() and tutorial_purchase().get("category", "") != category):
		return
	shop_title.text = category
	fixed_back_button.show()
	shop_scroll.scroll_vertical = 0
	clear_content()
	match category:
		"RECURSOS":
			var interactions: Node = get_parent().get_parent().get_node("WorldInteractions")
			for kind: String in RESOURCE_LABELS:
				var button := create_art_button("ore:" + kind, RESOURCE_LABELS[kind])
				button.pressed.connect(interactions.select_resource.bind(kind))
				resource_buttons[kind] = button
				catalog_grid().add_child(button)
		"INVESTIGACIÓN":
			build_research_content()
		"EXPANSION":
			var button := create_art_button("expansion", "Ampliar a 7 × 5", economy.EXPANSION_PRICE)
			if grid.cave_width >= 7:
				button.get_meta("price_label").text = "✓"
				button.tooltip_text = "Base ampliada a 7 × 5"
				button.disabled = true
			else:
				button.disabled = not economy.can_afford(economy.EXPANSION_PRICE)
				button.pressed.connect(request_item.bind("expansion", expansion_requested))
			purchase_buttons["expansion"] = button
			catalog_grid().add_child(button)
		"VETAS":
			add_item_button("VETA DE CARBÓN · 100", economy.COAL_VEIN_PRICE, "coal", coal_vein_requested)
			add_item_button("VETA DE LATÓN · 150", economy.BRASS_VEIN_PRICE, "brass", brass_vein_requested)
			add_item_button("VETA DE HIERRO · 200", economy.IRON_VEIN_PRICE, "iron", coal_vein_requested)
		"HERRAMIENTAS":
			add_item_button("TALADRO AUTOMÁTICO · 200", economy.DRILL_PRICE, "drill", drill_requested)
			add_item_button("COMPACTADOR · 300", CompactorScript.PRICE, "compactor", compactor_requested)
			add_item_button("HORNO · 350", FurnaceScript.PRICE, "furnace", furnace_requested)
		"AUTOMATIZACIÓN":
			add_item_button("CINTA RECTA · 50", economy.CONVEYOR_PRICE, "straight", conveyor_requested)
			add_item_button("CINTA EN L DERECHA · 50", economy.CONVEYOR_PRICE, "corner_right", corner_conveyor_requested)
			add_item_button("CINTA EN L IZQUIERDA · 50", economy.CONVEYOR_PRICE, "corner_left", left_corner_conveyor_requested)
			add_item_button("CINTA EN T · 50", economy.CONVEYOR_PRICE, "junction", junction_conveyor_requested)
		"DEFENSA":
			var left_cell: Vector2i = grid.defense_cell("left")
			var right_cell: Vector2i = grid.defense_cell("right")
			var platforms_button := create_art_button("platform", "Desbloquear plataformas de defensa", economy.DEFENSE_TILE_PRICE)
			if grid.defense_tiles.has(left_cell) and grid.defense_tiles.has(right_cell):
				platforms_button.get_meta("price_label").text = "✓"
				platforms_button.tooltip_text = "Plataformas desbloqueadas"
				platforms_button.disabled = true
			else:
				platforms_button.disabled = not economy.can_afford(economy.DEFENSE_TILE_PRICE)
				platforms_button.pressed.connect(unlock_defense_platforms)
			catalog_grid().add_child(platforms_button)
			platforms_button.disabled = platforms_button.disabled or not tutorial_allows_item("defense_platforms")
			purchase_buttons["defense_platforms"] = platforms_button
			var launcher_button := create_art_button("launcher", "Lanzapepitas · Nv. 1\nMunición: pepitas de nivel 1.", economy.LAUNCHER_PRICE)
			launcher_button.disabled = not economy.can_afford(economy.LAUNCHER_PRICE)
			launcher_button.disabled = launcher_button.disabled or not tutorial_allows_item("launcher")
			launcher_button.pressed.connect(request_item.bind("launcher", launcher_requested))
			purchase_buttons["launcher"] = launcher_button
			catalog_grid().add_child(launcher_button)
	if cycle != null: update_cycle()

func add_item_button(text: String, price: int, item: String, request: Signal) -> void:
	if progression != null and not progression.is_item_unlocked(item): return
	var button := create_art_button(item, text.get_slice(" · ", 0), price)
	button.pressed.connect(request_item.bind(item, request))
	item_buttons[item] = {"button": button, "price": price, "name": text.get_slice(" · ", 0)}
	purchase_buttons[item] = button
	catalog_grid().add_child(button)
	refresh_item_buttons()

func request_item(item: String, request: Signal) -> void:
	if progression != null and item != "expansion" and not progression.is_item_unlocked(item):
		return
	if cycle != null and (cycle.is_night or cycle.defeated or not tutorial_allows_item(item)):
		return
	var interactions: Node = get_parent().get_parent().get_node("WorldInteractions")
	if interactions.item_price(item) >= 0:
		interactions.select_item(item)
		return
	interactions.cancel_active()
	request.emit()

func refresh_item_buttons() -> void:
	for item in item_buttons:
		var button: Button = item_buttons[item]["button"]
		var unlocked: bool = progression == null or progression.is_item_unlocked(item)
		button.disabled = not unlocked or not economy.can_afford(item_buttons[item]["price"]) or not tutorial_allows_item(item) or (cycle != null and (cycle.is_night or cycle.defeated))
		button.tooltip_text = item_buttons[item].get("name", item)
		var construction: Node = get_parent().get_parent().get_node_or_null("Construction")
		if construction != null and construction.has_recipe(item): button.tooltip_text += "\n" + construction.recipe_text(item)
		if not unlocked:
			button.tooltip_text += "\nInvestigar: %s" % progression.RESEARCHES[progression.ITEM_RESEARCH[item]]["name"]

func unlock_defense_platforms() -> void:
	if not tutorial_allows_item("defense_platforms") or (cycle != null and not cycle.allows_action("unlock_defense")):
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

func _input(event: InputEvent) -> void:
	handle_outside_click(event)

func handle_outside_click(event: InputEvent) -> bool:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return false
	if not event.pressed and outside_click_pending:
		outside_click_pending = false
		get_viewport().set_input_as_handled()
		return true
	if not event.pressed or not shop_open: return false
	var local: Vector2 = shop_panel.get_global_transform_with_canvas().affine_inverse() * event.position
	if Rect2(Vector2.ZERO, shop_panel.size).has_point(local): return false
	outside_click_pending = true
	close_shop()
	get_viewport().set_input_as_handled()
	return true

func open_shop() -> void:
	if cycle != null and cycle.is_tutorial_active() and tutorial_purchase().is_empty():
		return
	if shop_open or shop_animating or (cycle != null and (cycle.is_night or cycle.defeated)):
		return
	show_categories()
	shop_open = true
	shop_animating = true
	shop_button.hide()
	money_box.show()
	animate_shop(true)
	if cycle != null:
		update_cycle()

func close_shop() -> void:
	if not shop_open:
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
	var money_right: float = -PANEL_WIDTH - 12.0 if opened else -TOGGLE_SIZE - 27.0
	tween.parallel().tween_property(money_box, "offset_right", money_right, ANIMATION_TIME)
	tween.parallel().tween_property(money_box, "offset_left", money_right - MONEY_BOX_WIDTH, ANIMATION_TIME)
	tween.finished.connect(finish_animation)

func finish_animation() -> void:
	shop_animating = false
	if not shop_open:
		shop_button.show()
		money_box.show()
	if cycle != null:
		update_cycle()

class ViewIcon extends Control:
	var mine: bool = false

	func _draw() -> void:
		var factor: float = minf(size.x, size.y) / 40.0
		draw_set_transform(size * 0.5, 0, Vector2.ONE * factor)
		if mine:
			draw_line(Vector2(-8, 10), Vector2(7, -8), Color("#d1ad66"), 4, true)
			draw_polyline(PackedVector2Array([Vector2(-10, -3), Vector2(-4, -10), Vector2(5, -11), Vector2(12, -5)]), Color("#e8d6ac"), 4, true)
		else:
			var shield := PackedVector2Array([Vector2(-10, -11), Vector2(10, -11), Vector2(9, 2), Vector2(5, 8), Vector2(0, 12), Vector2(-5, 8), Vector2(-9, 2), Vector2(-10, -11)])
			draw_colored_polygon(shield, Color("#6f895b"))
			draw_polyline(shield, Color("#f2cf86"), 2, true)
			draw_line(Vector2(0, -7), Vector2(0, 6), Color("#f2cf86"), 2, true)
			draw_line(Vector2(-5, -1), Vector2(5, -1), Color("#f2cf86"), 2, true)

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
			"compactor":
				draw_rect(Rect2(3, 3, 26, 26), tint, false, 2)
				draw_rect(Rect2(8, 7, 16, 4), tint)
				draw_rect(Rect2(8, 21, 16, 4), tint)
				for index in range(4): draw_circle(Vector2(10 + (index % 2) * 10, 14 + (index / 2) * 4), 1.5, tint)
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

# Isolated drawing nodes reuse the world artwork without joining its simulation.
class ItemPreview extends Control:
	var kind := "coal"
	var tint := Color.WHITE:
		set(value):
			tint = value
			modulate = value
	var model: Node2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		if kind == "compactor":
			model = CompactorArt.new()
		elif kind == "furnace":
			model = FurnaceArt.new()
		else:
			model = ItemArt.new()
			model.kind = kind
		add_child(model)
		resized.connect(layout_model)
		layout_model()

	func layout_model() -> void:
		model.position = size * 0.5
		model.scale = Vector2.ONE * minf(size.x, size.y) / 54.0

class FurnaceArt extends "res://Scripts/furnace_manager.gd":
	func _ready() -> void:
		set_process(false)

	func _draw() -> void:
		draw_machine(Vector2.ZERO, {"fuel": 20})

class CompactorArt extends "res://Scripts/compactor_manager.gd":
	func _ready() -> void:
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)

	func _draw() -> void:
		draw_machine(Vector2.ZERO, {"direction": 0, "kind": "", "count": 0})

class ItemArt extends "res://Scripts/world_renderer.gd":
	var kind := "coal"

	func _init() -> void:
		grid = preload("res://Scripts/grid_manager.gd").new()
		mining = preload("res://Scripts/mining_manager.gd").new()
		conveyors = preload("res://Scripts/conveyor_manager.gd").new()
		drills = preload("res://Scripts/drill_manager.gd").new()
		launchers = preload("res://Scripts/potato_launcher_manager.gd").new()

	func _draw() -> void:
		match kind:
			"coal": draw_coal_vein(Vector2.ZERO, 1, 0, false)
			"iron": draw_vein(Vector2.ZERO, "iron", {"level": 1, "direction": 1, "progress": 0})
			"brass": draw_brass_vein(Vector2.ZERO, 1, 0, false)
			"straight", "corner_right", "corner_left", "junction":
				draw_conveyor(Vector2.ZERO, 0, false, kind)
			"drill", "research":
				draw_drill(Vector2.ZERO, 0, false)
				if kind == "research":
					draw_circle(Vector2(15, 15), 9, Color("#1a2b21"))
					draw_line(Vector2(10, 15), Vector2(20, 15), Color("#ffdf9c"), 2)
					draw_line(Vector2(15, 10), Vector2(15, 20), Color("#ffdf9c"), 2)
			"launcher": draw_launcher(Vector2.ZERO, {"ammo": [], "angle": -PI * 0.5}, false)
			"platform": draw_defense_platform(Rect2(-24, -24, 48, 48))
			"resources":
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * 0.8)
				draw_nugget(Vector2(-11, -5), "coal_2", 1)
				draw_nugget(Vector2(11, 5), "brass_2", 1)
			"expansion":
				for y in range(5):
					for x in range(7):
						var owned: bool = x >= 2 and x <= 4 and y >= 1 and y <= 3
						draw_rect(Rect2(-24 + x * 7, -17 + y * 7, 6, 6), Color("#7b946f") if owned else Color("#d1ad66"))
			_:
				if kind.begins_with("ore:"):
					draw_nugget(Vector2.ZERO, kind.trim_prefix("ore:"), 1)
