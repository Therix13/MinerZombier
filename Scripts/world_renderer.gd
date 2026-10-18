extends Node2D

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
var placing_brass := false
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
	grid = grid_manager
	mining = mining_manager
	conveyors = conveyor_manager
	drills = drill_manager

func _draw() -> void:
	var swap_bundle: bool = dragging_object and is_instance_valid(interactions) and interactions.swaps_contents(held_object_type, held_object_cell, grid.world_to_cell(drag_world_position))
	draw_rect(Rect2(Vector2.ZERO, Vector2(grid.MAP_WIDTH * grid.TILE_SIZE, grid.GRID_OFFSET_Y)), Color.WHITE)
	for y in range(grid.MAP_HEIGHT):
		for x in range(grid.MAP_WIDTH):
			var cell := Vector2i(x, y)
			var rect: Rect2 = grid.get_cell_rect(cell)
			var color := Color("#383838")
			if grid.owned_tiles.has(cell):
				color = Color("#7b946f")
			draw_rect(rect, color)
			draw_rect(rect, Color("#222222"), false, 1.0)
	for cell in grid.ammo_tiles:
		var connector_rect: Rect2 = grid.get_cell_rect(cell)
		draw_rect(connector_rect, Color("#687f72"))
		draw_rect(connector_rect.grow(-1.0), Color("#d1ad66"), false, 2.0)
		var connector_center: Vector2 = connector_rect.get_center()
		draw_circle(connector_center, 3.0, Color("#d1ad66"))
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
			if amount > 0: draw_nugget(grid.get_cell_rect(cell).get_center(), kind, amount)
	for cell in mining.brass_veins:
		if holding_object and dragging_object and held_object_type == "vein" and cell == held_object_cell:
			continue
		var vein: Dictionary = mining.brass_veins[cell]
		draw_brass_vein(grid.get_cell_rect(cell).get_center(), int(vein["direction"]), int(vein["progress"]), false)
	for cell in mining.coal_veins:
		if holding_object and dragging_object and held_object_type == "vein" and cell == held_object_cell:
			continue
		var vein: Dictionary = mining.coal_veins[cell]
		draw_coal_vein(grid.get_cell_rect(cell).get_center(), int(vein["direction"]), int(vein["progress"]), false)
	for cell in grid.defense_tiles:
		var platform_rect: Rect2 = grid.get_cell_rect(cell)
		draw_defense_platform(platform_rect)
		draw_rect(platform_rect.grow(-1.0), Color("#ffe095"), false, 3.0)
	for cell in launchers.launchers:
		if holding_object and dragging_object and held_object_type == "launcher" and cell == held_object_cell:
			continue
		draw_launcher(grid.get_cell_rect(cell).get_center(), launchers.launchers[cell], false)
	for cell in grid.defense_tiles:
		var defense_outline: Rect2 = grid.get_cell_rect(cell)
		draw_rect(defense_outline.grow(-1.0), Color("#eab958"), false, 3.0)
	for shot in launchers.shots:
		draw_line(shot["from"], shot["to"], Color("#d9b46a") if str(shot["kind"]).begins_with("brass") else Color("#444444"), 5.0 if str(shot["kind"]).ends_with("_2") else 3.0)
	draw_sale_cell()
	if placing_coal and preview_allowed("coal") and grid.owned_tiles.has(hovered_cell) and mining.can_place_vein(hovered_cell) and not conveyors.belts.has(hovered_cell) and not drills.drills.has(hovered_cell) and not launchers.launchers.has(hovered_cell):
		draw_coal_vein(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, 0, true)
	if placing_brass and grid.owned_tiles.has(hovered_cell) and mining.can_place_vein(hovered_cell) and not conveyors.belts.has(hovered_cell) and not drills.drills.has(hovered_cell) and not launchers.launchers.has(hovered_cell):
		draw_brass_vein(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, 0, true)
	if placing_belt and preview_allowed("belt") and grid.owned_tiles.has(hovered_cell) and conveyors.can_place(hovered_cell):
		draw_conveyor(grid.get_cell_rect(hovered_cell).get_center(), placement_direction, true, placement_belt_shape)
	if placing_launcher and (grid.is_valid_cell(hovered_cell) or grid.is_defense_position(hovered_cell)):
		var launcher_valid: bool = preview_allowed("launcher") and grid.defense_tiles.has(hovered_cell) and launchers.can_place(hovered_cell)
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
			valid = destination == held_object_cell or (grid.defense_tiles.has(destination) and launchers.can_place(destination))
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
			var vein: Dictionary = mining.brass_veins[held_object_cell] if kind == "brass" else mining.coal_veins[held_object_cell]
			if kind == "brass":
				draw_brass_vein(drag_world_position, placement_direction, int(vein["progress"]), true)
			else:
				draw_coal_vein(drag_world_position, placement_direction, int(vein["progress"]), true)
		elif held_object_type == "drill":
			draw_drill(drag_world_position, placement_direction, true)
		elif held_object_type == "belt":
			draw_conveyor(drag_world_position, placement_direction, true, held_belt_shape)
			if mining.nugget_type(held_object_cell) == "coal":
				draw_coal_nugget(drag_world_position, mining.nuggets_at(held_object_cell))
			elif mining.nugget_type(held_object_cell) == "brass":
				draw_brass_nugget(drag_world_position, mining.nuggets_at(held_object_cell))
		elif held_object_type == "launcher":
			draw_launcher(drag_world_position, launchers.launchers[held_object_cell], true)
		elif held_object_type == "nugget":
			if swap_bundle and conveyors.belts.has(held_object_cell):
				draw_conveyor(drag_world_position, conveyors.belt_direction(held_object_cell), true, conveyors.belt_shape(held_object_cell))
			draw_nugget(drag_world_position, mining.nugget_type(held_object_cell), 1)

func draw_nugget(center: Vector2, kind: String, amount: int) -> void:
	if kind.begins_with("brass"): draw_brass_nugget(center, amount)
	else: draw_coal_nugget(center, amount)
	if kind.ends_with("_2"):
		draw_rect(Rect2(center + Vector2(5, -16), Vector2(12, 13)), Color("#e4bd71"))
		draw_string(ThemeDB.fallback_font, center + Vector2(8, -5), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#302719"))

func preview_allowed(kind: String) -> bool:
	return tutorial == null or tutorial.allows_world_press(hovered_cell, kind)

func draw_coal_vein(
	center: Vector2,
	direction_index: int,
	progress: int,
	preview: bool
) -> void:
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
						38.0 * minf(float(progress) / float(mining.mining_clicks), 1.0),
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
		and held_object_type == "nugget"
		and hovered_cell == grid.sale_cell
	)

	if dragging_to_sale:
		draw_rect(rect, Color("#ffe18a"), false, 4.0)
	elif sale_hovered:
		draw_rect(rect, Color("#ffe6a2"), false, 2.0)

func draw_conveyor(center: Vector2, direction_index: int, preview: bool, shape: String = "straight") -> void:
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

func draw_brass_vein(center: Vector2, direction_index: int, progress: int, preview: bool) -> void:
	var rect := Rect2(center - Vector2.ONE * grid.TILE_SIZE * 0.5, Vector2.ONE * grid.TILE_SIZE).grow(-3.0)
	var base := Color("#634525")
	if preview:
		base.a = 0.7
	draw_rect(rect, base)
	draw_rect(rect, Color("#e1b65f"), false, 2.0)
	for offset in [Vector2(-10, -9), Vector2(9, -8), Vector2(-1, 8), Vector2(12, 11)]:
		draw_circle(center + offset + Vector2(2, 2), 9.0, Color("#43301c"))
		draw_circle(center + offset, 7.0, Color("#b68a4b"))
		draw_circle(center + offset + Vector2(-2, -2), 3.0, Color("#e4ca7e"))
	draw_direction_arrow(center, direction_index)
	if not preview:
		draw_rect(Rect2(rect.position + Vector2(3, 36), Vector2(36, 4)), Color("#302117"))
		draw_rect(Rect2(rect.position + Vector2(3, 36), Vector2(36.0 * minf(float(progress) / float(mining.mining_clicks), 1.0), 4)), Color("#f5d283"))

func draw_brass_nugget(center: Vector2, amount: int) -> void:
	var points := PackedVector2Array([center + Vector2(-13, -4), center + Vector2(-6, -12), center + Vector2(7, -10), center + Vector2(13, 1), center + Vector2(6, 12), center + Vector2(-9, 9)])
	draw_colored_polygon(points, Color("#a3753e"))
	draw_circle(center + Vector2(-3, -4), 5.0, Color("#e0b76b"))
	if amount > 1:
		draw_string(ThemeDB.fallback_font, center + Vector2(9, 17), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffdb85"))

func draw_launcher(center: Vector2, data: Dictionary, preview: bool) -> void:
	var rect := Rect2(center - Vector2.ONE * grid.TILE_SIZE * 0.5, Vector2.ONE * grid.TILE_SIZE).grow(-3.0)
	var color := Color("#6f7b52")
	if preview:
		color.a = 0.65
	draw_rect(rect, Color("#282c21"))
	draw_rect(rect.grow(-3.0), color)
	draw_rect(rect, Color("#d0ab69"), false, 2.0)
	var angle: float = float(data.get("angle", -PI * 0.5))
	var direction := Vector2.RIGHT.rotated(angle)
	draw_circle(center, 14.0, Color("#33412b"))
	draw_circle(center, 10.0, Color("#b0bd7b"))
	draw_line(center, center + direction * 19.0, Color("#44301d"), 11.0)
	draw_line(center, center + direction * 19.0, Color("#c6a066"), 7.0)
	draw_circle(center + direction * 18.0, 5.0, Color("#3b2d20"))
	var ammo: Array = data.get("ammo", [])
	var slots: int = launchers.capacity
	for i in range(slots):
		var offset_x: float = 5.0 + float(i) * (rect.size.x - 10.0) / float(maxi(slots - 1, 1))
		draw_circle(rect.position + Vector2(offset_x, rect.size.y - 5.0), 1.8, Color("#f5d17b") if i < ammo.size() else Color("#2f2b25"))
		if i < ammo.size() and str(ammo[i]).ends_with("_2"):
			draw_arc(rect.position + Vector2(offset_x, rect.size.y - 5.0), 3.0, 0, TAU, 10, Color("#ffe8aa"), 1)

func draw_defense_platform(rect: Rect2) -> void:
	var body: Rect2 = rect.grow(-3.0)
	draw_rect(body, Color("#4c3b25"))
	draw_rect(body.grow(-4.0), Color("#79838d"))
	draw_rect(body.grow(-7.0), Color("#a7b1b9"), false, 2.0)
	for offset: Vector2 in [Vector2(7, 7), Vector2(rect.size.x - 7, 7), Vector2(7, rect.size.y - 7), Vector2(rect.size.x - 7, rect.size.y - 7)]:
		draw_circle(rect.position + offset, 2.6, Color("#e2ba74"))
