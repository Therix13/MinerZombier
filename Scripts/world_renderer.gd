extends Node2D

const ArtAtlas = preload("res://Scripts/art_atlas.gd")
var rasterizing: bool = false

var ground: GroundCanvas
var ground_signature: int = 0
var ground_rebuilds: int = 0
var grid: RefCounted
var mining: RefCounted
var conveyors: RefCounted
var drills: RefCounted
var launchers: RefCounted
var tutorial: RefCounted
var interactions: Node
var placing_launcher: bool = false
var hovered_cell := Vector2i(-999, -999)
var sale_hovered := false
var placing_coal := false
var placing_copper := false
var placing_belt := false
var placement_belt_shape: String = "straight"
var held_belt_shape: String = "straight"
var placing_drill := false
var placement_direction := 1
var holding_object := false
var dragging_object := false
var held_object_type := ""
var held_object_cell := Vector2i.ZERO
var drag_world_position := Vector2.ZERO

func setup(grid_manager: RefCounted, mining_manager: RefCounted, conveyor_manager: RefCounted, drill_manager: RefCounted) -> void:
	ArtAtlas.prepare()
	grid = grid_manager
	mining = mining_manager
	conveyors = conveyor_manager
	drills = drill_manager
	if ground == null:
		ground = GroundCanvas.new()
		ground.name = "CachedGround"
		ground.show_behind_parent = true
		add_child(ground)
	ground.grid = grid
	ground_signature = grid.owned_tiles.hash()
	ground.queue_redraw()
	ground_rebuilds += 1

func _draw() -> void:
	var swap_bundle: bool = dragging_object and is_instance_valid(interactions) and interactions.swaps_contents(held_object_type, held_object_cell, grid.world_to_cell(drag_world_position))
	if ground != null and ground_signature != grid.owned_tiles.hash():
		ground_signature = grid.owned_tiles.hash()
		ground.queue_redraw()
		ground_rebuilds += 1
	for cell in grid.ammo_tiles:
		var connector_rect: Rect2 = grid.get_cell_rect(cell)
		draw_rect(connector_rect, Color("#6d6a54"))
		draw_rect(connector_rect.grow(-1.0), Color("#d1ad66"), false, 2.0)
		var connector_center: Vector2 = connector_rect.get_center()
		draw_circle(connector_center, 3.0, Color("#d1ad66"))
	for cell in grid.defense_tiles:
		var platform_rect: Rect2 = grid.get_cell_rect(cell)
		draw_defense_platform(platform_rect)
		draw_rect(platform_rect.grow(-1.0), Color("#ffe095"), false, 3.0)
	for cell in conveyors.belts:
		if holding_object and dragging_object and (held_object_type == "belt" or swap_bundle) and cell == held_object_cell:
			continue
		draw_conveyor(grid.get_cell_rect(cell).get_center(), conveyors.belt_direction(cell), false, conveyors.belt_shape(cell))
	for cell in drills.drills:
		if holding_object and dragging_object and held_object_type == "drill" and cell == held_object_cell:
			continue
		draw_drill(grid.get_cell_rect(cell).get_center(), int(drills.drills[cell]), false)
	for kind: String in mining.ORE_KINDS:
		var items: Dictionary = mining.items_for(kind)
		for cell: Vector2i in items:
			if holding_object and dragging_object and (held_object_type == "belt" or swap_bundle) and cell == held_object_cell: continue
			var amount: int = int(items[cell])
			if holding_object and dragging_object and held_object_type == "nugget" and cell == held_object_cell and kind == mining.nugget_type(cell): amount -= 1
			if amount > 0:
				var center: Vector2 = grid.get_cell_rect(cell).get_center()
				var rhythm: Node = get_parent().get_node_or_null("WorkshopRhythm")
				if rhythm != null: center = rhythm.nugget_position(cell, kind, center)
				draw_nugget(center, kind, amount)
	for material: String in ["coal", "copper", "iron", "gold"]:
		for cell: Vector2i in mining.veins_for(material):
			if holding_object and dragging_object and held_object_type == "vein" and cell == held_object_cell: continue
			draw_vein(grid.get_cell_rect(cell).get_center(), material, mining.veins_for(material)[cell])
	for cell in launchers.launchers:
		if holding_object and dragging_object and held_object_type == "launcher" and cell == held_object_cell:
			continue
		draw_launcher(grid.get_cell_rect(cell).get_center(), launchers.launchers[cell], false)
	for cell in grid.defense_tiles:
		var defense_outline: Rect2 = grid.get_cell_rect(cell)
		draw_rect(defense_outline.grow(-1.0), Color("#eab958"), false, 3.0)
	for shot in launchers.shots:
		draw_line(shot["from"], shot["to"], Color("#d9b46a") if str(shot["kind"]).begins_with("copper") else Color("#444444"), 5.0 if str(shot["kind"]).ends_with("_2") else 3.0)
	draw_sale_cell()
	if placing_coal and preview_allowed("coal") and grid.owned_tiles.has(hovered_cell) and mining.can_place_vein(hovered_cell) and not conveyors.belts.has(hovered_cell) and not drills.drills.has(hovered_cell) and not launchers.launchers.has(hovered_cell):
		draw_coal_vein(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, 0, true)
	if placing_copper and grid.owned_tiles.has(hovered_cell) and mining.can_place_vein(hovered_cell) and not conveyors.belts.has(hovered_cell) and not drills.drills.has(hovered_cell) and not launchers.launchers.has(hovered_cell):
		draw_copper_vein(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, 0, true)
	if placing_belt and preview_allowed("belt") and grid.owned_tiles.has(hovered_cell) and conveyors.can_place(hovered_cell):
		draw_conveyor(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, true, placement_belt_shape)
	if placing_launcher and (grid.is_valid_cell(hovered_cell) or grid.is_defense_position(hovered_cell)):
		var launcher_valid: bool = preview_allowed("launcher") and launchers.can_place(hovered_cell)
		if launcher_valid:
			draw_rect(grid.get_cell_rect(hovered_cell).grow(-1.0), Color("#ffe084"), false, 3.0)
		else:
			draw_rect(grid.get_cell_rect(hovered_cell).grow(-1.0), Color("#ec6969"), false, 3.0)
		draw_launcher(grid.get_cell_rect(hovered_cell).get_center(), {"ammo": [], "angle": -PI * 0.5}, true)
	if placing_drill and grid.owned_tiles.has(hovered_cell) and drills.can_place(hovered_cell) and not launchers.launchers.has(hovered_cell):
		draw_drill(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, true)
	if dragging_object:
		var destination: Vector2i = grid.world_to_cell(drag_world_position)
		var valid: bool = false
		if held_object_type == "vein":
			valid = destination == held_object_cell or (mining.can_place_vein(destination) and not conveyors.belts.has(destination) and not drills.drills.has(destination) and not launchers.launchers.has(destination))
		elif held_object_type == "drill":
			valid = destination == held_object_cell or (drills.can_place(destination) and not launchers.launchers.has(destination))
		elif held_object_type == "belt":
			valid = destination == held_object_cell or conveyors.can_place(destination)
		elif held_object_type == "launcher":
			valid = destination == held_object_cell or launchers.can_place(destination) or launchers.can_fuse(held_object_cell,destination)
		elif held_object_type == "nugget":
			valid = mining.can_move_nugget(destination) or destination == grid.sale_cell or launchers.can_receive(destination)
		if is_instance_valid(interactions):
			valid = interactions.can_drop(held_object_type, held_object_cell, destination)
		if tutorial != null:
			valid = valid and tutorial.allows_interaction(held_object_type, held_object_cell, destination, true)
		if destination != grid.sale_cell or not valid:
			draw_rect(grid.get_cell_rect(destination).grow(-2.0), Color("#ffe18a") if valid else Color("#df7770"), false, 3.0)
		if held_object_type == "vein" and mining.vein_at(held_object_cell) != "":
			var kind: String = mining.vein_at(held_object_cell)
			var vein: Dictionary = mining.veins_for(kind)[held_object_cell]
			var preview_data: Dictionary = vein.duplicate()
			preview_data["direction"] = placement_direction
			draw_vein(drag_world_position, kind, preview_data, true)
		elif held_object_type == "drill":
			draw_drill(drag_world_position, placement_direction, true)
		elif held_object_type == "belt":
			draw_conveyor(drag_world_position, placement_direction, true, held_belt_shape)
			if mining.nugget_type(held_object_cell) == "coal":
				draw_coal_nugget(drag_world_position, mining.nuggets_at(held_object_cell))
			elif mining.nugget_type(held_object_cell) == "copper":
				draw_copper_nugget(drag_world_position, mining.nuggets_at(held_object_cell))
		elif held_object_type == "launcher":
			draw_launcher(drag_world_position, launchers.launchers[held_object_cell], true)
		elif held_object_type == "nugget":
			if swap_bundle and conveyors.belts.has(held_object_cell):
				draw_conveyor(drag_world_position, conveyors.belt_direction(held_object_cell), true, conveyors.belt_shape(held_object_cell))
			draw_nugget(drag_world_position, mining.nugget_type(held_object_cell), 1)
	if is_instance_valid(interactions) and (interactions.placing_iron or interactions.placing_gold) and interactions.phase_allows():
		draw_iron_vein(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, 0, "gold" if interactions.placing_gold else "iron")
		draw_rect(grid.get_cell_rect(hovered_cell).grow(-1), Color("#f0c777") if mining.can_place_vein(hovered_cell) else Color("#df7770"), false, 2)
	if is_instance_valid(interactions) and not interactions.placing_resource.is_empty() and interactions.phase_allows():
		var valid: bool = mining.can_move_nugget(hovered_cell)
		draw_rect(grid.get_cell_rect(hovered_cell).grow(-2), Color("#ffe18a") if valid else Color("#df7770"), false, 2)
		draw_nugget(grid.get_cell_rect(hovered_cell).get_center(), interactions.placing_resource, 1)

func draw_nugget(center: Vector2, kind: String, amount: int) -> void:
	if not rasterizing and amount == 1 and ArtAtlas.paint(self, "ore:" + kind, center): return
	if kind.begins_with("iron") or kind.begins_with("gold"):
		if "_ingot" in kind: draw_ingot(center, kind, amount)
		else: draw_iron_nugget(center, kind, amount)
	elif "_ingot" in kind: draw_ingot(center, kind, amount)
	elif mining.ore_level(kind) >= 3: draw_cluster_nugget(center, kind, amount)
	elif mining.ore_level(kind) == 2: draw_refined_nugget(center, kind, amount)
	elif kind.begins_with("copper"): draw_copper_nugget(center, amount)
	else: draw_coal_nugget(center, amount)

func draw_iron_nugget(center: Vector2, kind: String, amount: int) -> void:
	var level: int = mining.ore_level(kind)
	var offsets: Array[Vector2] = [Vector2.ZERO]
	if level == 2: offsets = [Vector2(-4, 2), Vector2(5, -3)]
	elif level == 3: offsets = [Vector2(-8, 4), Vector2(8, 4), Vector2(0, -6)]
	elif level == 4: offsets = [Vector2(-8, 6), Vector2(9, 5), Vector2(-6, -7), Vector2(8, -8)]
	var radius: float = 12 if level == 1 else 10
	for offset: Vector2 in offsets:
		var at: Vector2 = center + offset
		var points := PackedVector2Array([at + Vector2(-radius, 0), at + Vector2(-radius * 0.6, -radius), at + Vector2(radius * 0.6, -radius * 0.8), at + Vector2(radius, 0), at + Vector2(radius * 0.5, radius), at + Vector2(-radius * 0.6, radius * 0.8)])
		draw_colored_polygon(points, Color("#e6b52c") if kind.begins_with("gold") else Color("#73858e"))
		draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], at]), Color("#fff29a") if kind.begins_with("gold") else Color("#b4c2ca"))
		points.append(points[0])
		draw_polyline(points, Color("#85591a") if kind.begins_with("gold") else Color("#35454f"), 1.5)
	if amount > 1: draw_string(ThemeDB.fallback_font, center + Vector2(12, 20), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffdb85"))

func draw_ingot(center: Vector2, kind: String, amount: int) -> void:
	var level: int = mining.ore_level(kind)
	var w: float = [10.0, 13.0, 16.0, 20.0][level - 1]
	var h: float = [7.0, 9.0, 12.0, 16.0][level - 1]
	var outline: PackedVector2Array
	if level == 4:
		outline = PackedVector2Array([center + Vector2(-w, -h + 3), center + Vector2(-2, -h), center + Vector2(w, -h + 3), center + Vector2(w, h - 2), center + Vector2(1, h + 2), center + Vector2(-w, h - 2)])
	else:
		outline = PackedVector2Array([center + Vector2(-w + 4, -h), center + Vector2(w - 4, -h), center + Vector2(w, h - 2), center + Vector2(w - 2, h), center + Vector2(-w + 2, h), center + Vector2(-w, h - 2)])
	draw_colored_polygon(outline, (Color("#e3ad2c") if kind.begins_with("gold") else Color("#8196a0") if kind.begins_with("iron") else Color("#c47739")))
	draw_colored_polygon(PackedVector2Array([center + Vector2(-w + 4, -h), center + Vector2(w - 4, -h), center + Vector2(w - 1, -h + 4), center + Vector2(-w + 1, -h + 4)]), (Color("#fff09a") if kind.begins_with("gold") else Color("#d2e2e8") if kind.begins_with("iron") else Color("#f4b67a")))
	draw_colored_polygon(PackedVector2Array([center + Vector2(w - 5, -h + 4), center + Vector2(w - 1, -h + 2), center + Vector2(w - 1, h - 2), center + Vector2(w - 5, h)]), (Color("#af751b") if kind.begins_with("gold") else Color("#506571") if kind.begins_with("iron") else Color("#985526")))
	if level == 4:
		draw_colored_polygon(PackedVector2Array([center + Vector2(-w, -h + 3), center + Vector2(-2, -h), center + Vector2(w, -h + 3), center + Vector2(1, -h + 8)]), (Color("#ffe780") if kind.begins_with("gold") else Color("#c6d8e1") if kind.begins_with("iron") else Color("#f3b178")))
		draw_colored_polygon(PackedVector2Array([center + Vector2(1, -h + 8), center + Vector2(w, -h + 3), center + Vector2(w, h - 2), center + Vector2(1, h + 2)]), (Color("#ca901e") if kind.begins_with("gold") else Color("#607a89") if kind.begins_with("iron") else Color("#ab622f")))
		draw_circle(center + Vector2(8, 1), 1, (Color("#f5cd61") if kind.begins_with("gold") else Color("#8da7b4") if kind.begins_with("iron") else Color("#bd7538")))
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, (Color("#79501b") if kind.begins_with("gold") else Color("#273944") if kind.begins_with("iron") else Color("#2e2014")), 2.5, true)
	draw_line(center + Vector2(-w + 7, -h + 5), center + Vector2(-w + 4, h - 3), (Color("#ffffc9") if kind.begins_with("gold") else Color("#e4f3fa") if kind.begins_with("iron") else Color("#ffd9a1")), 2, true)
	draw_line(center + Vector2(-w + 10, -h + 5), center + Vector2(-w + 7, h - 3), (Color("#fff0a0") if kind.begins_with("gold") else Color("#afc6d1") if kind.begins_with("iron") else Color("#e99b59")), 1, true)
	if amount > 1: draw_string(ThemeDB.fallback_font, center + Vector2(12, 20), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffdb85"))

func draw_cluster_nugget(center: Vector2, kind: String, amount: int) -> void:
	var copper: bool = kind.begins_with("copper")
	var level: int = mining.ore_level(kind)
	var offsets: Array[Vector2] = [Vector2(-8, 3), Vector2(8, 3), Vector2(0, -7)]
	if level == 4: offsets = [Vector2(-9, 6), Vector2(9, 6), Vector2(-6, -8), Vector2(7, -8)]
	for offset: Vector2 in offsets:
		var at: Vector2 = center + offset
		var points := PackedVector2Array([at + Vector2(-11, 1), at + Vector2(-7, -8), at + Vector2(3, -10), at + Vector2(11, -3), at + Vector2(8, 8), at + Vector2(-4, 10)])
		draw_colored_polygon(points, Color("#ad6439") if copper else Color("#222427"))
		points.append(points[0])
		draw_polyline(points, Color("#62462a") if copper else Color("#101113"), 1.5)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-7, -6), at + Vector2(2, -8), at + Vector2(6, -3), at + Vector2(-3, 1)]), Color("#f0b17d") if copper else Color("#51555a"))
	if amount > 1: draw_string(ThemeDB.fallback_font, center + Vector2(12, 20), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffdb85"))

func draw_refined_nugget(center: Vector2, kind: String, amount: int) -> void:
	var copper: bool = kind.begins_with("copper")
	# A modest step up from raw ore; larger tiers can grow into fuller clusters.
	var outline := PackedVector2Array([
		center + Vector2(-15, -3), center + Vector2(-11, -10),
		center + Vector2(-4, -15), center + Vector2(5, -14),
		center + Vector2(9, -9), center + Vector2(14, -6),
		center + Vector2(16, 2), center + Vector2(12, 10),
		center + Vector2(4, 14), center + Vector2(-5, 15),
		center + Vector2(-13, 10), center + Vector2(-16, 3),
	])
	draw_colored_polygon(outline, Color("#ab6238") if copper else Color("#171719"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-13, -3), center + Vector2(-9, -9),
		center + Vector2(-3, -13), center + Vector2(4, -12),
		center + Vector2(6, -7), center + Vector2(1, -1),
		center + Vector2(-5, 3), center + Vector2(-11, 3),
	]), Color("#edaf78") if copper else Color("#444649"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(3, -5), center + Vector2(9, -7),
		center + Vector2(13, -3), center + Vector2(13, 3),
		center + Vector2(8, 8), center + Vector2(1, 7), center + Vector2(-1, 2),
	]), Color("#cb7e48") if copper else Color("#2d2f32"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-9, 7), center + Vector2(-4, 3),
		center + Vector2(2, 4), center + Vector2(5, 10),
		center + Vector2(0, 12), center + Vector2(-6, 12),
	]), Color("#87573b") if copper else Color("#222326"))
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, Color("#5c4026") if copper else Color("#0c0d0e"), 1.5)
	if amount > 1:
		draw_string(ThemeDB.fallback_font, center + Vector2(12, 20), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffdb85"))

func preview_allowed(kind: String) -> bool:
	return tutorial == null or tutorial.allows_world_press(hovered_cell, kind)

func draw_vein(center: Vector2, kind: String, data: Dictionary, preview: bool = false) -> void:
	if kind in ["iron", "gold"]: draw_iron_vein(center, int(data["direction"]), int(data["progress"]), kind)
	elif kind == "copper": draw_copper_vein(center, int(data["direction"]), int(data["progress"]), preview)
	else: draw_coal_vein(center, int(data["direction"]), int(data["progress"]), preview)
	var level: int = clampi(int(data.get("level", 1)), 1, 4)
	if level == 1: return
	var tint: Color = [Color("#c29a6b"), Color("#c9d8df"), Color("#ffe08a")][level - 2]
	if preview: tint.a = 0.75
	draw_rect(Rect2(center - Vector2(22,22), Vector2(44,44)), tint, false, 1.5)
	var marks := PackedVector2Array()
	for index in range(level):
		var x: float = (index - (level - 1) * 0.5) * 5
		marks.append(center + Vector2(x,-19))
		marks.append(center + Vector2(x,-15))
	draw_multiline(marks, tint, 2)

func draw_coal_vein(
	center: Vector2,
	direction_index: int,
	progress: int,
	preview: bool
) -> void:
	if not rasterizing and not preview and ArtAtlas.paint(self, "coal:%d:%d" % [direction_index, progress], center): return
	var rect := Rect2(
		center - Vector2.ONE * grid.TILE_SIZE * 0.5,
		Vector2.ONE * grid.TILE_SIZE
	)

	var color := Color("#44382c")

	if preview:
		color.a = 0.75

	draw_rect(rect.grow(-3.0), color)
	draw_rect(
		rect.grow(-3.0),
		Color("#d6a85c") if preview else Color("#241c16"),
		false,
		2.0
	)

	var rock_positions: Array[Vector2] = [
		Vector2(-10, -6),
		Vector2(7, -10),
		Vector2(0, 7),
		Vector2(12, 9)
	]

	for offset: Vector2 in rock_positions:
		var rock_center: Vector2 = center + offset
		draw_circle(rock_center + Vector2(2, 2), 10.0, Color("#171717"))
		draw_circle(rock_center, 8.0, Color("#303033"))
		draw_circle(rock_center + Vector2(-2, -3), 3.0, Color("#535357"))

	draw_direction_arrow(center, direction_index)

	if not preview:
		draw_rect(
			Rect2(
				rect.position + Vector2(5, 41),
				Vector2(38, 4)
			),
			Color("#201a16")
		)

		if progress > 0:
			draw_rect(
				Rect2(
					rect.position + Vector2(5, 41),
					Vector2(
						38.0 * minf(float(progress) / float(mining.hardness("coal")), 1.0),
						4.0
					)
				),
				Color("#e2b252")
			)

func draw_direction_arrow(center: Vector2, direction_index: int) -> void:
	var direction: Vector2 = Vector2(mining.DIRECTIONS[direction_index])
	var side := Vector2(-direction.y, direction.x)
	var tip: Vector2 = center + direction * 23.0

	var points := PackedVector2Array([
		tip,
		tip - direction * 12.0 + side * 6.0,
		tip - direction * 12.0 - side * 6.0
	])

	draw_colored_polygon(points, Color("#ffe084"))
	draw_line(
		center + direction * 3.0,
		center + direction * 15.0,
		Color("#f4c761"),
		3.0
	)

func draw_coal_nugget(center: Vector2, amount: int) -> void:
	var points := PackedVector2Array([
		center + Vector2(-13, -5),
		center + Vector2(-5, -13),
		center + Vector2(8, -11),
		center + Vector2(14, 0),
		center + Vector2(7, 12),
		center + Vector2(-8, 10)
	])

	draw_colored_polygon(points, Color("#171719"))

	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(-10, -5),
			center + Vector2(-4, -11),
			center + Vector2(6, -9),
			center + Vector2(0, -2),
			center + Vector2(-7, 1)
		]),
		Color("#55565a")
	)

	if amount > 1:
		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(9, 17),
			str(amount),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color("#ffdb85")
		)

func draw_sale_cell() -> void:
	var rect: Rect2 = grid.get_cell_rect(grid.sale_cell)
	var p: Vector2 = rect.position

	draw_rect(rect, Color("#322315"))
	draw_rect(rect, Color("#c08b4e"), false, 2.0)

	draw_rect(Rect2(p + Vector2(4, 5), Vector2(40, 39)), Color("#56391f"))
	draw_rect(Rect2(p + Vector2(8, 19), Vector2(32, 20)), Color("#251a12"))
	draw_rect(Rect2(p + Vector2(5, 30), Vector2(38, 12)), Color("#a36b35"))
	draw_rect(Rect2(p + Vector2(5, 30), Vector2(38, 3)), Color("#e0ab60"))
	draw_rect(Rect2(p + Vector2(6, 9), Vector2(36, 12)), Color("#b4773e"))
	draw_rect(Rect2(p + Vector2(4, 7), Vector2(40, 5)), Color("#4a2917"))

	for i in range(5):
		draw_rect(
			Rect2(
				p + Vector2(7 + i * 7, 11),
				Vector2(7, 10)
			),
			Color("#d6a25b") if i % 2 == 0 else Color("#8c482b")
		)

	draw_circle(p + Vector2(24, 25), 9.0, Color("#5d3615"))
	draw_circle(p + Vector2(24, 25), 7.5, Color("#e0a63f"))
	draw_circle(p + Vector2(24, 25), 5.5, Color("#ffe18a"))
	draw_rect(Rect2(p + Vector2(22, 21), Vector2(4, 8)), Color("#c8882d"))

	var dragging_to_sale: bool = (
		dragging_object
		and hovered_cell == grid.sale_cell
		and (held_object_type == "nugget" or (is_instance_valid(interactions) and interactions.can_sell(held_object_type, held_object_cell)))
	)

	if dragging_to_sale:
		draw_rect(rect, Color("#ffe18a"), false, 4.0)
		if held_object_type != "nugget":
			draw_string(ThemeDB.fallback_font, rect.end + Vector2(-38, 17), "+%d" % interactions.resale_value(held_object_type, held_object_cell), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#d5a351"))
	elif sale_hovered:
		draw_rect(rect, Color("#ffe6a2"), false, 2.0)

func draw_conveyor(center: Vector2, direction_index: int, preview: bool, shape: String = "straight") -> void:
	if not rasterizing and not preview and ArtAtlas.paint(self, "belt:%s:%d" % ["corner_right" if shape == "corner" else shape, direction_index], center): return
	var rect := Rect2(center - Vector2.ONE * grid.TILE_SIZE * 0.5, Vector2.ONE * grid.TILE_SIZE).grow(-3.0)
	var base := Color("#59432c")
	if preview:
		base.a = 0.75
	draw_rect(rect, Color("#221a14"))
	draw_rect(rect.grow(-3.0), base)
	for i in range(3):
		var p := rect.position + Vector2(8.0 + i * 11.0, 6.0)
		draw_rect(Rect2(p, Vector2(5, rect.size.y - 12.0)), Color("#886848"))
	draw_rect(rect, Color("#c09352") if preview else Color("#9c7445"), false, 2.0)
	var output: Vector2 = Vector2(conveyors.DIRECTIONS[direction_index])
	var left: Vector2 = Vector2(conveyors.DIRECTIONS[(direction_index + 3) % 4])
	var right: Vector2 = Vector2(conveyors.DIRECTIONS[(direction_index + 1) % 4])
	var origin: Vector2 = center - output * 11.0
	if shape == "corner" or shape == "corner_right" or shape == "corner_left":
		var inlet: Vector2 = center + (right if shape == "corner_left" else left) * 17.0
		draw_line(inlet, center, Color("#f0c478"), 6.0)
		origin = center
	elif shape == "junction":
		draw_line(center + left * 17.0, center, Color("#f0c478"), 5.0)
		draw_line(center + right * 17.0, center, Color("#f0c478"), 5.0)
		origin = center
	else:
		draw_line(center - output * 17.0, center, Color("#f0c478"), 5.0)
	draw_line(origin, center + output * 8.0, Color("#f7d478"), 5.0)
	var side: Vector2 = Vector2(-output.y, output.x)
	var tip: Vector2 = center + output * 17.0
	var arrow := PackedVector2Array([tip, tip - output * 12.0 + side * 7.0, tip - output * 12.0 - side * 7.0])
	draw_colored_polygon(arrow, Color("#f7d478"))

func draw_drill(center: Vector2, direction_index: int, preview: bool) -> void:
	if not rasterizing and not preview and ArtAtlas.paint(self, "drill:%d" % direction_index, center): return
	var rect := Rect2(center - Vector2.ONE * grid.TILE_SIZE * 0.5, Vector2.ONE * grid.TILE_SIZE).grow(-3.0)
	var metal := Color("#81888d")
	if preview:
		metal.a = 0.65
	draw_rect(rect, Color("#201c19"))
	draw_rect(rect.grow(-3.0), metal)
	draw_rect(rect.grow(-5.0), Color("#3c4044"), false, 2.0)
	for offset in [Vector2(-15, -15), Vector2(15, -15), Vector2(-15, 15), Vector2(15, 15)]:
		draw_circle(center + offset, 2.5, Color("#d8b067"))
	draw_circle(center, 13.0, Color("#22272c"))
	draw_circle(center, 9.0, Color("#b5bdc3"))
	draw_circle(center, 4.0, Color("#5d666c"))
	var direction: Vector2 = Vector2(drills.DIRECTIONS[direction_index])
	var side: Vector2 = Vector2(-direction.y, direction.x)
	var tip: Vector2 = center + direction * 21.0
	var arrow := PackedVector2Array([tip, tip - direction * 11.0 + side * 5.0, tip - direction * 11.0 - side * 5.0])
	draw_colored_polygon(arrow, Color("#ffe084"))

func draw_copper_vein(center: Vector2, direction_index: int, progress: int, preview: bool) -> void:
	if not rasterizing and not preview and ArtAtlas.paint(self, "copper:%d:%d" % [direction_index, progress], center): return
	var rect := Rect2(center - Vector2.ONE * grid.TILE_SIZE * 0.5, Vector2.ONE * grid.TILE_SIZE).grow(-3.0)
	var base := Color("#634525")
	if preview:
		base.a = 0.7
	draw_rect(rect, base)
	draw_rect(rect, Color("#e1b65f"), false, 2.0)
	for offset in [Vector2(-10, -9), Vector2(9, -8), Vector2(-1, 8), Vector2(12, 11)]:
		draw_circle(center + offset + Vector2(2, 2), 9.0, Color("#43301c"))
		draw_circle(center + offset, 7.0, Color("#c77c48"))
		draw_circle(center + offset + Vector2(-2, -2), 3.0, Color("#f4bc88"))
	draw_direction_arrow(center, direction_index)
	if not preview:
		draw_rect(Rect2(rect.position + Vector2(3, 36), Vector2(36, 4)), Color("#302117"))
		draw_rect(Rect2(rect.position + Vector2(3, 36), Vector2(36.0 * minf(float(progress) / float(mining.hardness("copper")), 1.0), 4)), Color("#f5d283"))

func draw_copper_nugget(center: Vector2, amount: int) -> void:
	var points := PackedVector2Array([center + Vector2(-13, -4), center + Vector2(-6, -12), center + Vector2(7, -10), center + Vector2(13, 1), center + Vector2(6, 12), center + Vector2(-9, 9)])
	draw_colored_polygon(points, Color("#ab6238"))
	draw_circle(center + Vector2(-3, -4), 5.0, Color("#e0b76b"))
	if amount > 1:
		draw_string(ThemeDB.fallback_font, center + Vector2(9, 17), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffdb85"))

func draw_launcher(center: Vector2, data: Dictionary, preview: bool) -> void:
	draw_launcher_on(self, center, data, preview)

func draw_launcher_on(canvas: Node2D, center: Vector2, data: Dictionary, preview: bool) -> void:
	var level: int = int(data.get("level",1))
	var rusty: bool = level == 1
	var rect := Rect2(center - Vector2(21,21), Vector2(42,42))
	var metal := Color("#806954") if rusty else Color("#cb783e")
	if preview: metal.a = 0.65
	var edge := Color("#493f35") if rusty else Color("#63351f")
	var light := Color("#b39b78") if rusty else Color("#ffc68a")
	canvas.draw_rect(rect,edge)
	canvas.draw_rect(rect.grow(-3),metal)
	canvas.draw_rect(rect,light,false,2)
	canvas.draw_line(rect.position + Vector2(3,3),rect.position + Vector2(38,3),light,2)
	for bolt: Vector2 in [Vector2(-16,-16),Vector2(16,-16)]:
		canvas.draw_circle(center + bolt,2,light)
	if rusty:
		for patch: Vector2 in [Vector2(-12,-8),Vector2(10,9),Vector2(-14,12),Vector2(13,-13)]:
			canvas.draw_circle(center + patch,3.5,Color("#a14f2d"))
			canvas.draw_circle(center + patch + Vector2(1,1),1.5,Color("#633d2c"))
	canvas.draw_circle(center,14,edge)
	canvas.draw_circle(center,11,metal)
	canvas.draw_arc(center,9,PI,TAU,12,light,2)
	var direction := Vector2.RIGHT.rotated(float(data.get("angle",-PI * 0.5)))
	var muzzle: Vector2 = center + direction * 18
	canvas.draw_line(center,muzzle,edge,12)
	canvas.draw_line(center,muzzle,metal,8)
	canvas.draw_line(center + direction.orthogonal()*2,muzzle + direction.orthogonal()*2,light,2)
	canvas.draw_circle(muzzle,5,metal)
	canvas.draw_circle(muzzle,3,edge)
	var ammo: Array = data.get("ammo",[])
	var slots: int = 5 if rusty else 7
	for i in range(slots):
		canvas.draw_circle(center + Vector2(-14 + i * (28.0 / (slots - 1)),16),1.8,light if i < ammo.size() else edge)
	if level == 2:
		for x in [-3,3]: canvas.draw_line(center + Vector2(x,-19),center + Vector2(x,-14),light,2)

func draw_defense_platform(rect: Rect2) -> void:
	if not rasterizing and rect.size == Vector2.ONE * 48 and ArtAtlas.paint(self, "platform", rect.get_center()): return
	var body: Rect2 = rect.grow(-3.0)
	draw_rect(body, Color("#4c3b25"))
	draw_rect(body.grow(-4.0), Color("#79838d"))
	draw_rect(body.grow(-7.0), Color("#a7b1b9"), false, 2.0)
	for offset: Vector2 in [Vector2(7, 7), Vector2(rect.size.x - 7, 7), Vector2(7, rect.size.y - 7), Vector2(rect.size.x - 7, rect.size.y - 7)]:
		draw_circle(rect.position + offset, 2.6, Color("#e2ba74"))

# One retained canvas for the terrain; moving ore never rebuilds its geometry.
class GroundCanvas extends Node2D:
	const Scenery = preload("res://Scripts/mine_scenery.gd")
	var grid: RefCounted
	var meshes: Array[ArrayMesh] = []
	func _draw() -> void:
		if grid == null: return
		meshes.clear()
		var bounds := Rect2(0,grid.GRID_OFFSET_Y,grid.MAP_WIDTH * grid.TILE_SIZE,grid.MAP_HEIGHT * grid.TILE_SIZE)
		meshes.append(Scenery.field(self,bounds,0))
		var start_x: float = floori(grid.MAP_WIDTH / 2.0) - floori(grid.cave_width / 2.0)
		var cave := Rect2(start_x * grid.TILE_SIZE,grid.GRID_OFFSET_Y,grid.cave_width * grid.TILE_SIZE,grid.cave_height * grid.TILE_SIZE)
		var brush := Scenery.Brush.new()
		brush.draw_rect(cave.grow(12),Color("#242e2a"))
		brush.draw_rect(cave.grow(5),Color("#676657"))
		meshes.append(brush.flush(self))
		meshes.append(Scenery.field(self,cave,1))
		brush = Scenery.Brush.new()
		# Only excavated cells get a quiet placement grid; solid rock stays organic.
		var lines := PackedVector2Array()
		for x in range(grid.cave_width+1):
			lines.append(Vector2(cave.position.x+x*48,cave.position.y))
			lines.append(Vector2(cave.position.x+x*48,cave.end.y))
		for y in range(grid.cave_height+1):
			lines.append(Vector2(cave.position.x,cave.position.y+y*48))
			lines.append(Vector2(cave.end.x,cave.position.y+y*48))
		brush.draw_multiline(lines,Color("#645d4c",0.6),1)
		for side in [-1,1]:
			var x: float = cave.get_center().x + side * (cave.size.x * 0.5 + 10)
			for y in range(int(cave.position.y)+22,int(cave.end.y),96):
				brush.draw_rect(Rect2(x-4,y-16,8,57),Color("#503d2d"))
				brush.draw_line(Vector2(x-1,y-16),Vector2(x-1,y+41),Color("#9a784d"),2)
				Scenery.lamp(brush,Vector2(x,y+4))
		var rng := RandomNumberGenerator.new()
		rng.seed = 66382
		for i in range(150):
			var at := Vector2(rng.randf_range(10,bounds.end.x-10),rng.randf_range(bounds.position.y+10,bounds.end.y-10))
			if cave.grow(27).has_point(at): continue
			Scenery.stone(brush,at,rng.randf_range(0.9,1.5) if i % 12 == 0 else rng.randf_range(0.15,0.4),Color("#5d655a"))
			if i % 2 == 0:
				var crack := PackedVector2Array([at+Vector2(-24,8),at,at+Vector2(18,-17),at+Vector2(38,-14)])
				brush.draw_polyline(crack,Color("#26352f",0.4),2)
		meshes.append(brush.flush(self))

	static func draw_grid_lines(canvas: Node2D, bounds: Rect2, tile_size: float, origin: Vector2) -> void:
		var lines := PackedVector2Array()
		for column in range(floori((bounds.position.x - origin.x) / tile_size), ceili((bounds.end.x - origin.x) / tile_size) + 1):
			var x: float = origin.x + column * tile_size
			lines.append(Vector2(x, bounds.position.y))
			lines.append(Vector2(x, bounds.end.y))
		for row in range(floori((bounds.position.y - origin.y) / tile_size), ceili((bounds.end.y - origin.y) / tile_size) + 1):
			var y: float = origin.y + row * tile_size
			lines.append(Vector2(bounds.position.x, y))
			lines.append(Vector2(bounds.end.x, y))
		canvas.draw_multiline(lines, Color("#222222"), 1.0)

static func draw_grid_lines(canvas: Node2D, bounds: Rect2, tile_size: float, origin: Vector2) -> void:
	GroundCanvas.draw_grid_lines(canvas, bounds, tile_size, origin)

func draw_iron_vein(center: Vector2, direction: int, progress: int, material: String = "iron") -> void:
	draw_rect(Rect2(center - Vector2(21,21), Vector2(42,42)), Color("#59441d") if material == "gold" else Color("#29353c"))
	draw_rect(Rect2(center - Vector2(21,21), Vector2(42,42)), Color("#f2d366") if material == "gold" else Color("#95a7ae"), false, 2)
	for offset: Vector2 in [Vector2(-8,-7), Vector2(8,-7), Vector2(-7,8), Vector2(9,8)]:
		draw_iron_nugget(center + offset, material, 1)
	var outward: Vector2 = Vector2(mining.DIRECTIONS[posmod(direction,4)])
	var side := Vector2(-outward.y,outward.x)
	var tip: Vector2 = center + outward * 23
	draw_line(center, tip - outward * 4, Color("#f7d57b"), 3)
	draw_colored_polygon(PackedVector2Array([tip,tip - outward * 10 + side * 6,tip - outward * 10 - side * 6]),Color("#f7d57b"))
	if progress > 0:
		draw_rect(Rect2(center + Vector2(-18,18),Vector2(36.0 * progress / mining.hardness(material),2)),Color("#edc16c"))
