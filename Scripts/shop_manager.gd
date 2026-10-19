extends Control

signal expansion_requested
signal saw_requested
signal copper_vein_requested
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
const CATEGORIES := ["EXPANSION", "VETAS", "HERRAMIENTAS", "AUTOMATIZACIÓN", "DEFENSA"]
const ITEM_CATEGORIES := {
	"VETAS": ["coal", "copper", "iron", "gold"],
	"HERRAMIENTAS": ["drill", "compactor", "furnace", "saw"],
	"AUTOMATIZACIÓN": ["straight", "corner_right", "corner_left", "junction"],
}
const RESOURCE_LABELS := {"gold": "ORO · NIVEL 1", "gold_2": "ORO · NIVEL 2", "gold_3": "ORO · NIVEL 3", "gold_4": "ORO · NIVEL 4", "gold_ingot": "LINGOTE DE ORO · NIVEL 1", "gold_ingot_2": "LINGOTE DE ORO · NIVEL 2", "gold_ingot_3": "LINGOTE DE ORO · NIVEL 3", "gold_ingot_4": "LINGOTE DE ORO · NIVEL 4","iron": "HIERRO · NIVEL 1", "iron_2": "HIERRO · NIVEL 2", "iron_3": "HIERRO · NIVEL 3", "iron_4": "HIERRO · NIVEL 4", "iron_ingot": "LINGOTE DE HIERRO · NIVEL 1", "iron_ingot_2": "LINGOTE DE HIERRO · NIVEL 2", "iron_ingot_3": "LINGOTE DE HIERRO · NIVEL 3", "iron_ingot_4": "LINGOTE DE HIERRO · NIVEL 4", "coal": "CARBÓN · NIVEL 1", "copper": "COBRE · NIVEL 1", "coal_2": "CARBÓN · NIVEL 2", "copper_2": "COBRE · NIVEL 2", "coal_3": "CARBÓN · NIVEL 3", "copper_3": "COBRE · NIVEL 3", "coal_4": "CARBÓN · NIVEL 4", "copper_4": "COBRE · NIVEL 4", "copper_ingot": "LINGOTE DE COBRE · NIVEL 1", "copper_ingot_2": "LINGOTE DE COBRE · NIVEL 2", "copper_ingot_3": "LINGOTE DE COBRE · NIVEL 3", "copper_ingot_4": "LINGOTE DE COBRE · NIVEL 4"}
const CATEGORY_ART := {"EXPANSION": "expansion", "VETAS": "coal", "HERRAMIENTAS": "drill", "AUTOMATIZACIÓN": "junction", "DEFENSA": "launcher", "RECURSOS": "resources"}
const UNLOCK_VIEW := {
	"expansion": ["expansion", "Expansión", "Amplía tu mina"],
	"copper": ["copper", "Cobre", "Nueva veta"],
	"iron": ["iron", "Hierro", "Nueva veta"],
	"gold": ["gold", "Oro", "Nueva veta"],
	"saw": ["saw", "Sierra", "Nueva herramienta"],
	"drill": ["drill", "Taladro", "Nueva herramienta"],
	"compactor": ["compactor", "Compactador", "Nueva herramienta"],
	"furnace": ["furnace", "Horno", "Nueva herramienta"],
	"straight": ["straight", "Cinta", "Automatización"],
	"corner_right": ["corner_right", "Curva derecha", "Automatización"],
	"corner_left": ["corner_left", "Curva izquierda", "Automatización"],
	"junction": ["junction", "Unión en T", "Automatización"],
	"launcher": ["launcher", "Lanzapepitas Nv. 1", "Oxidado · Sin materiales"],
	"launcher_2": ["launcher_2", "Lanzapepitas Nv. 2", "Fusiona dos de Nv. 1"],
}

var economy: RefCounted
var grid: RefCounted
var shop_open: bool = false
var breach_queued: bool = false
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
var cycle_shift_hint: HBoxContainer
var cycle_shift_key: PanelContainer
var shift_key_style: StyleBoxFlat
var progression: RefCounted
var view_icon: ViewIcon
var item_buttons: Dictionary = {}
var resource_buttons: Dictionary = {}
var item_grid: GridContainer
var category_buttons: Dictionary = {}
var purchase_buttons: Dictionary = {}
var fallback_display: CanvasLayer
var unlock_notice: PanelContainer
var unlock_notice_backdrop: ColorRect
var unlock_notice_label: Label
var unlock_notice_accept: Button
var unlock_notice_grid: GridContainer
var unlock_notice_cards: Dictionary = {}
var unlock_notice_tween: Tween
var notice_item_ids: Array[String] = []

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
	if not game.has_node("Saws"):
		var saws := preload("res://Scripts/saw_manager.gd").new()
		saws.name = "Saws"
		game.add_child(saws)
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

func queue_first_night() -> void:
	if breach_queued or cycle == null or cycle.day != 1 or cycle.barrier_broken or not cycle.can_start_night(): return
	breach_queued = true
	show_breach.call_deferred()

func show_breach() -> void:
	if cycle.day != 1 or cycle.barrier_broken or not cycle.can_start_night():
		breach_queued = false
		return
	var game: Node = get_parent().get_parent()
	close_shop()
	game.get_node("WorldInteractions").cancel_active()
	var film := IntroCinematicScript.new()
	film.breach = true
	film.name = "BarrierBreach"
	film.finished.connect(func():
		cycle.barrier_broken = true
		night_requested.emit()
	)
	game.add_child(film)

func ensure_intro() -> void:
	var saves: Node = get_parent().get_parent().get_node_or_null("SaveGame")
	if saves != null and not saves.playing: return
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
	progression.setup(get_parent().get_parent().get("mining"))
	build_unlock_notice()
	progression.changed.connect(update_progression)
	progression.items_unlocked.connect(announce_unlocks)
	update_progression()

func _process(_delta: float) -> void:
	if progression == null:
		return
	update_notice_visibility()
	update_shift_hint()
	# Keep an unavailable selection out of the placement preview.
	var game: Node = get_parent().get_parent()
	var item: String = ""
	if game.get("placing_coal"): item = "coal"
	elif game.get("placing_launcher"): item = "launcher"
	elif game.get("placing_copper"): item = "copper"
	elif game.get("placing_drill"): item = "drill"
	elif game.get("placing_belt"): item = str(game.get("belt_shape"))
	if not item.is_empty() and not progression.is_item_unlocked(item):
		game.cancel_placement()

func update_progression() -> void:
	if progression == null: return
	if shop_title.text == "TIENDA" and category_buttons.keys() != visible_categories():
		show_categories()
	elif shop_title.text in CATEGORIES and not category_has_items(shop_title.text):
		show_categories()
	elif shop_open and shop_title.text in ITEM_CATEGORIES and item_buttons.keys() != visible_shop_items(shop_title.text):
		rebuild_catalog()
	elif shop_open and shop_title.text == "DEFENSA":
		var has_launcher: bool = purchase_buttons.has("launcher")
		if has_launcher != progression.is_item_unlocked("launcher"): rebuild_catalog()
	refresh_item_buttons()

func visible_shop_items(category: String = "") -> Array[String]:
	var result: Array[String] = []
	for item: String in ["coal", "copper", "iron", "gold", "straight", "corner_right", "corner_left", "junction", "drill", "compactor", "furnace", "saw"]:
		if not category.is_empty() and item not in ITEM_CATEGORIES.get(category, []): continue
		if progression == null or progression.is_item_unlocked(item): result.append(item)
	return result

func rebuild_catalog() -> void:
	var scroll: int = shop_scroll.scroll_vertical
	open_category(shop_title.text)
	shop_scroll.set_deferred("scroll_vertical", scroll)

func build_unlock_notice() -> void:
	unlock_notice_backdrop = ColorRect.new()
	unlock_notice_backdrop.name = "UnlockNoticeBackdrop"
	unlock_notice_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	unlock_notice_backdrop.color = Color(0, 0, 0, 0.65)
	unlock_notice_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	unlock_notice_backdrop.z_index = 120
	add_child(unlock_notice_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unlock_notice_backdrop.add_child(center)
	unlock_notice = PanelContainer.new()
	unlock_notice.name = "NewUnlockNotice"
	unlock_notice.custom_minimum_size = Vector2(480, 0)
	unlock_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := create_style("#192d26", "#d5b078", 2, 16)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 22
	style.content_margin_bottom = 18
	style.shadow_color = Color(0,0,0,0.4)
	style.shadow_size = 14
	unlock_notice.add_theme_stylebox_override("panel", style)
	center.add_child(unlock_notice)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 16)
	unlock_notice.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	var emblem := PanelContainer.new()
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.add_theme_stylebox_override("panel",create_style("#24443c","#547d6a",1,12))
	header.add_child(emblem)
	var emblem_icon := create_label("✦", 30, Color("#ffe1a2"))
	emblem_icon.custom_minimum_size = Vector2(40,40)
	emblem_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.add_child(emblem_icon)
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation",3)
	header.add_child(titles)
	unlock_notice_label = create_label("Nuevos desbloqueos",22,Color("#ffe1a2"))
	unlock_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(unlock_notice_label)
	var subtitle := create_label("Nuevas opciones para tu mina",13,Color("#a8c4b2"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(subtitle)
	unlock_notice_grid = GridContainer.new()
	unlock_notice_grid.columns = 2
	unlock_notice_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unlock_notice_grid.add_theme_constant_override("h_separation",10)
	unlock_notice_grid.add_theme_constant_override("v_separation",10)
	column.add_child(unlock_notice_grid)
	var footer := create_label("Disponibles en la tienda",12,Color("#a8b8a5"))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)
	unlock_notice_accept = Button.new()
	unlock_notice_accept.name = "AcceptUnlockNotice"
	unlock_notice_accept.text = "Aceptar"
	unlock_notice_accept.custom_minimum_size.y = 44
	unlock_notice_accept.add_theme_stylebox_override("normal",create_style("#684721","#d6b374",2,8))
	unlock_notice_accept.add_theme_stylebox_override("hover",create_style("#805c30","#ffe1a2",2,8))
	unlock_notice_accept.pressed.connect(accept_unlock_notice)
	column.add_child(unlock_notice_accept)
	unlock_notice.hide()
	unlock_notice_backdrop.hide()

func accept_unlock_notice() -> void:
	notice_item_ids.clear()
	unlock_notice.hide()
	unlock_notice_backdrop.hide()


func announce_unlocks(item_ids: Array[String]) -> void:
	if item_ids.is_empty(): return
	for item_id: String in item_ids:
		if item_id not in notice_item_ids: notice_item_ids.append(item_id)
	rebuild_notice_cards()
	unlock_notice.hide()
	unlock_notice_backdrop.hide()
	update_notice_visibility()

func rebuild_notice_cards() -> void:
	unlock_notice_cards.clear()
	for child in unlock_notice_grid.get_children():
		unlock_notice_grid.remove_child(child)
		child.queue_free()
	for item_id: String in notice_item_ids:
		var card := PanelContainer.new()
		card.name = "Notice_" + item_id
		card.custom_minimum_size = Vector2(210,76)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := create_style("#263d30","#486448",1,10)
		for side in ["left","right","top","bottom"]: style.set("content_margin_"+side,10)
		card.add_theme_stylebox_override("panel",style)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		var item: String = item_id
		var art: Control = create_item_preview(item,Vector2(48,48))
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(art)
		var labels := VBoxContainer.new()
		labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		labels.add_theme_constant_override("separation",4)
		row.add_child(labels)
		var name_label := create_label(UNLOCK_VIEW[item_id][1],16,Color("#f4e6c9"))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(name_label)
		var detail := create_label(UNLOCK_VIEW[item_id][2],11,Color("#9eb69b"))
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(detail)
		unlock_notice_grid.add_child(card)
		unlock_notice_cards[item_id] = card

func update_notice_visibility() -> void:
	if unlock_notice == null or notice_item_ids.is_empty(): return
	var victory: Control = get_parent().get_parent().get("night_victory_overlay")
	if (cycle != null and (cycle.is_night or cycle.defeated)) or (victory != null and victory.visible):
		unlock_notice.hide()
		unlock_notice_backdrop.hide()
	elif not unlock_notice.visible:
		unlock_notice.show()
		unlock_notice_backdrop.show()
		if unlock_notice_tween != null: unlock_notice_tween.kill()
		unlock_notice_backdrop.modulate.a = 0
		unlock_notice_tween = create_tween()
		unlock_notice_tween.tween_property(unlock_notice_backdrop,"modulate:a",1.0,0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		unlock_notice_accept.grab_focus()

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
	for index in range(cycle.TUTORIAL_DISPLAY_STEPS):
		var segment := ColorRect.new()
		segment.custom_minimum_size.y = 3
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cycle_steps.add_child(segment)
	cycle_title = create_label("", 21, Color("#f1e6c9"))
	column.add_child(cycle_title)
	cycle_goal = create_goal_label("", 14, Color("#bacbb7"))
	cycle_goal.custom_minimum_size.y = 58
	column.add_child(cycle_goal)
	cycle_shift_hint = HBoxContainer.new()
	cycle_shift_hint.name = "ShiftPlacementHint"
	cycle_shift_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cycle_shift_hint.add_theme_constant_override("separation", 10)
	column.add_child(cycle_shift_hint)
	cycle_shift_key = PanelContainer.new()
	cycle_shift_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cycle_shift_key.custom_minimum_size = Vector2(84, 38)
	shift_key_style = create_style("#344535", "#d5b078", 2, 7)
	shift_key_style.border_width_bottom = 4
	cycle_shift_key.add_theme_stylebox_override("panel", shift_key_style)
	cycle_shift_hint.add_child(cycle_shift_key)
	var key_label := create_label("⇧ SHIFT", 16, Color("#ffe1a2"))
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cycle_shift_key.add_child(key_label)
	var hint_label := create_label("Mantén para colocar varias", 12, Color("#bacbb7"))
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cycle_shift_hint.add_child(hint_label)
	cycle_shift_hint.hide()
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

func update_shift_hint() -> void:
	if cycle_shift_hint == null or cycle == null: return
	cycle_shift_hint.visible = cycle.is_tutorial_active() and cycle.tutorial_step in [3,4] and not cycle.needs_tutorial_income() and cycle.vein_fusion_targets().is_empty()
	if not cycle_shift_hint.visible: return
	var held: bool = Input.is_key_pressed(KEY_SHIFT)
	shift_key_style.bg_color = Color("#617648") if held else Color("#344535")
	shift_key_style.border_width_bottom = 2 if held else 4

func _on_cycle_action() -> void:
	if cycle_action.disabled or not cycle_action.visible:
		return
	var guide: Node = get_parent().get_parent().get_node_or_null("TutorialGuide")
	if guide != null and guide.resupply_active():
		return
	if cycle.defeated:
		restart_requested.emit()
	elif cycle.day == 1 and not cycle.barrier_broken:
		if cycle.can_start_night():
			queue_first_night()
		update_cycle()
	elif cycle.can_start_night() and not shop_open and not shop_animating:
		night_requested.emit()

func update_cycle() -> void:
	if cycle == null or cycle_title == null:
		return
	update_shift_hint()
	get_node("CyclePanel").visible = cycle.day == 1 and not (cycle.is_night and cycle.tutorial_step >= cycle.TUTORIAL_LAST_STEP)
	var tutorial: bool = cycle.is_tutorial_active()
	cycle_heading.text = "PRIMEROS PASOS" if tutorial else "DEFENSA DE LA BASE"
	cycle_badge.text = "%02d / %02d" % [cycle.tutorial_display_step(), cycle.TUTORIAL_DISPLAY_STEPS] if tutorial else "DÍA %d" % cycle.day
	cycle_steps.visible = tutorial
	cycle_goal.add_theme_color_override("default_color", Color("#bacbb7"))
	cycle_action.show()
	for index in range(cycle_steps.get_child_count()):
		cycle_steps.get_child(index).color = Color("#8db574") if index < cycle.tutorial_display_step() - 1 else (Color("#e1b879") if index == cycle.tutorial_display_step() - 1 else Color("#354b3a"))
	if tutorial:
		cycle_title.text = cycle.tutorial_title()
		cycle_goal.text = cycle.tutorial_text()
		cycle_action.disabled = false
		var game: Node = get_parent().get_parent()
		cycle_action.hide()
		if cycle.can_start_night() and cycle.tutorial_step != cycle.TUTORIAL_LAST_STEP:
			cycle_action.show()
			cycle_action.disabled = false
			cycle_action.text = "INICIAR NOCHE"
		if not tutorial_purchase().is_empty():
			cycle_goal.text += "\n" + tutorial_navigation_text()
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
	shop_button.disabled = cycle.is_night or cycle.defeated
	view_button.disabled = cycle.defeated
	var guide: Node = get_parent().get_parent().get_node_or_null("TutorialGuide")
	if guide != null and guide.resupply_active():
		guide.apply_resupply_card(self)
	update_progression()

func tutorial_purchase() -> Dictionary:
	if cycle == null or not cycle.is_tutorial_active(): return {}
	if cycle.needs_tutorial_income(): return {}
	var game: Node = get_parent().get_parent()
	if cycle.tutorial_step == 11 and grid.cave_width < 7:
		return {"category":"EXPANSION","item":"expansion","instruction":"Compra la expansión."}
	if cycle.tutorial_step == 12 and not cycle.platforms_ready():
		return {"category":"DEFENSA","item":"defense_platforms","instruction":"Compra las plataformas."}
	if cycle.tutorial_step == 13 and not cycle.launcher_ready() and cycle.launcher_blueprint_cell() == Vector2i(-999,-999) and cycle.launchers.launchers.is_empty() and not game.get("placing_launcher"):
		return {"category":"DEFENSA","item":"launcher","instruction":"Elige el lanzapepitas."}
	if cycle.tutorial_step == 13 and cycle.needs_ammo_vein() and not game.get("placing_coal"):
		return {"category":"VETAS","item":"coal","instruction":"Compra una veta de carbón Nv. 1 para munición."}
	if cycle.tutorial_step == 6 and not game.get("placing_copper"):
		return {"category":"VETAS","item":"copper","instruction":"Elige la veta de cobre."}
	if cycle.tutorial_step == 7 and not cycle.furnace_ready() and not cycle.furnace_blueprint_exists() and not game.get_node("WorldInteractions").placing_furnace:
		return {"category":"HERRAMIENTAS","item":"furnace","instruction":"Elige el horno."}
	if cycle.tutorial_step in [0,2,3,4] and cycle.vein_fusion_targets().is_empty() and not game.get("placing_coal"):
		return {"category":"VETAS","item":"coal","instruction":"Elige la veta de carbón."}
	return {}

func tutorial_navigation_text() -> String:
	var purchase: Dictionary = tutorial_purchase()
	if purchase.is_empty(): return ""
	if not shop_open: return "Abre el menú ☰."
	if shop_title.text != purchase["category"]:
		return "Entra en %s." % ("EXPANSIÓN" if purchase["category"] == "EXPANSION" else purchase["category"])
	return purchase["instruction"]

func tutorial_ui_target() -> Control:
	if cycle != null and cycle.is_tutorial_active() and cycle.tutorial_step == 14: return cycle_action
	var purchase: Dictionary = tutorial_purchase()
	if purchase.is_empty() or shop_animating: return null
	if not shop_open: return shop_button
	if shop_title.text != purchase["category"]:
		return category_buttons.get(purchase["category"])
	return purchase_buttons.get(purchase["item"])

func tutorial_allows_item(_item: String) -> bool:
	return true

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
	var short_names := {"ore:gold": "Oro · Nv. 1", "ore:gold_2": "Oro · Nv. 2", "ore:gold_3": "Oro · Nv. 3", "ore:gold_4": "Oro · Nv. 4", "ore:gold_ingot": "Ling. oro · Nv. 1", "ore:gold_ingot_2": "Ling. oro · Nv. 2", "ore:gold_ingot_3": "Ling. oro · Nv. 3", "ore:gold_ingot_4": "Ling. oro · Nv. 4","ore:iron": "Hierro · Nv. 1", "ore:iron_2": "Hierro · Nv. 2", "ore:iron_3": "Hierro · Nv. 3", "ore:iron_4": "Hierro · Nv. 4", "ore:iron_ingot": "Ling. hierro · Nv. 1", "ore:iron_ingot_2": "Ling. hierro · Nv. 2", "ore:iron_ingot_3": "Ling. hierro · Nv. 3", "ore:iron_ingot_4": "Ling. hierro · Nv. 4",
		"expansion": "Ampliar base", "coal": "Carbón", "copper": "Cobre", "iron": "Hierro", "gold": "Oro",
		"saw": "Sierra", "drill": "Taladro", "compactor": "Compactador", "furnace": "Horno", "straight": "Cinta recta",
		"corner_right": "Cinta L derecha", "corner_left": "Cinta L izquierda",
		"junction": "Cinta en T", "platform": "Plataformas", "launcher": "Lanzapepitas Nv. 1", "launcher_2": "Lanzapepitas Nv. 2",
		"ore:coal": "Carbón · Nv. 1", "ore:copper": "Cobre · Nv. 1",
		"ore:coal_2": "Carbón · Nv. 2", "ore:copper_2": "Cobre · Nv. 2",
		"ore:coal_3": "Carbón · Nv. 3", "ore:copper_3": "Cobre · Nv. 3",
		"ore:coal_4": "Carbón · Nv. 4", "ore:copper_4": "Cobre · Nv. 4",
		"ore:copper_ingot": "Lingote · Nv. 1", "ore:copper_ingot_2": "Lingote · Nv. 2",
		"ore:copper_ingot_3": "Lingote · Nv. 3", "ore:copper_ingot_4": "Lingote · Nv. 4",
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

func create_goal_label(value: String, font_size: int = 17, color: Color = Color("#f0e0c8")) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	label.text = value
	return label

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
	view_button.offset_left = 20.0
	view_button.offset_right = 64.0
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
	for child in shop_content.get_children():
		shop_content.remove_child(child)
		child.queue_free()

func category_has_items(category: String) -> bool:
	if category == "RECURSOS": return economy.developer_mode
	if progression == null: return category in ["VETAS","DEFENSA"]
	if category == "EXPANSION": return progression.is_item_unlocked("expansion")
	if category == "DEFENSA": return progression.is_item_unlocked("defense_platforms") or progression.is_item_unlocked("launcher")
	return not visible_shop_items(category).is_empty()

func visible_categories() -> Array[String]:
	var result: Array[String] = []
	for category: String in CATEGORIES:
		if category_has_items(category): result.append(category)
	if economy.developer_mode: result.append("RECURSOS")
	return result

func show_categories() -> void:
	shop_title.text = "TIENDA"
	fixed_back_button.hide()
	shop_scroll.scroll_vertical = 0
	clear_content()
	var categories: Array[String] = visible_categories()
	for category in categories:
		var button := create_art_button(CATEGORY_ART[category], category.capitalize())
		button.disabled = false
		button.pressed.connect(open_category.bind(category))
		category_buttons[category] = button
		catalog_grid().add_child(button)
	if cycle != null: update_cycle()

func open_category(category: String) -> void:
	if category not in CATEGORIES and category != "RECURSOS": return
	if not category_has_items(category): return
	if category == "RECURSOS" and not economy.developer_mode: return
	if shop_animating:
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
			add_item_button("VETA DE CARBÓN", economy.COAL_VEIN_PRICE, "coal", coal_vein_requested)
			add_item_button("VETA DE COBRE", economy.COPPER_VEIN_PRICE, "copper", copper_vein_requested)
			add_item_button("VETA DE HIERRO", economy.IRON_VEIN_PRICE, "iron", coal_vein_requested)
			add_item_button("VETA DE ORO", economy.GOLD_VEIN_PRICE, "gold", coal_vein_requested)
		"HERRAMIENTAS":
			add_item_button("TALADRO AUTOMÁTICO · 200", economy.DRILL_PRICE, "drill", drill_requested)
			add_item_button("COMPACTADOR · 300", CompactorScript.PRICE, "compactor", compactor_requested)
			add_item_button("HORNO · 350", FurnaceScript.PRICE, "furnace", furnace_requested)
			add_item_button("SIERRA · 250", preload("res://Scripts/saw_manager.gd").PRICE, "saw", saw_requested)
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
			add_item_button("LANZAPEPITAS NV. 1 · 500", economy.LAUNCHER_PRICE, "launcher", launcher_requested)
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
	if progression != null and not progression.is_item_unlocked(item):
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
		if item == "compactor": button.tooltip_text += "\nAcumula 8 puntos para producir Nv. 4. Nv. 1/2/3/4: 1/2/4/8 puntos. Conserva el sobrante. Nv. 4: 1 s; otros: 4 s."
		if item == "furnace": button.tooltip_text += "\nCarbón Nv. 1 / 2 / 3 / 4: aporta 1 / 3 / 8 / 20 de combustible. Capacidad: 40."
		if item == "launcher": button.tooltip_text += "\nDispara solo en las plataformas de defensa. Munición: cualquier pepita. Nv. 1/2/3/4 carga 1/2/3/4 disparos. Debe caber la carga completa. Alcance: 300.\nFusiona dos Nv. 1 para crear el plano de Nv. 2. Sin materiales para Nv. 1."

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
	if unlock_notice_backdrop != null and unlock_notice_backdrop.visible: return false
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
		draw_machine(Vector2.ZERO, {"direction": 0, "kind": "", "points": 0, "inventory": {}})

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
			"saw": preload("res://Scripts/saw_manager.gd").draw_machine(self,Vector2.ZERO,{"direction":1})
			"coal": draw_coal_vein(Vector2.ZERO, 1, 0, false)
			"gold": draw_vein(Vector2.ZERO, "gold", {"level": 1, "direction": 1, "progress": 0})
			"iron": draw_vein(Vector2.ZERO, "iron", {"level": 1, "direction": 1, "progress": 0})
			"copper": draw_copper_vein(Vector2.ZERO, 1, 0, false)
			"straight", "corner_right", "corner_left", "junction":
				draw_conveyor(Vector2.ZERO, 0, false, kind)
			"drill": draw_drill(Vector2.ZERO, 0, false)
			"launcher": draw_launcher(Vector2.ZERO, {"ammo": [], "level": 1, "angle": -PI * 0.5}, false)
			"launcher_2": draw_launcher(Vector2.ZERO, {"ammo": [], "level": 2, "angle": -PI * 0.5}, false)
			"platform": draw_defense_platform(Rect2(-24, -24, 48, 48))
			"resources":
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * 0.8)
				draw_nugget(Vector2(-11, -5), "coal_2", 1)
				draw_nugget(Vector2(11, 5), "copper_2", 1)
			"expansion":
				for y in range(5):
					for x in range(7):
						var owned: bool = x >= 2 and x <= 4 and y >= 1 and y <= 3
						draw_rect(Rect2(-24 + x * 7, -17 + y * 7, 6, 6), Color("#7b946f") if owned else Color("#d1ad66"))
			_:
				if kind.begins_with("ore:"):
					draw_nugget(Vector2.ZERO, kind.trim_prefix("ore:"), 1)
