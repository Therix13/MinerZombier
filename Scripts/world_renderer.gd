extends Node2D

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
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
		preload("res://Scripts/painted_assets.gd").draw(self,preload("res://Scripts/painted_assets.gd").environment(2),connector_rect,Color(.8,.8,.75))
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
	for material: String in mining.VEIN_KINDS:
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
		if shot.get("weapon","") in ["grenadier","rocketeer"]:
			var radius: float = preload("res://Scripts/content_catalog.gd").WEAPONS[shot["weapon"]]["radius"]
			var age: float = 1.0 - float(shot["time"]) / 0.45
			draw_circle(shot["to"],radius * age,Color(1,0.55,0.18,0.22 * (1 - age)))
			draw_arc(shot["to"],radius * age,0,TAU,24,Color(1,0.8,0.4,1 - age),2)
		elif shot.get("weapon","") == "tesla":
			var mid: Vector2 = (shot["from"] + shot["to"]) * 0.5
			draw_polyline(PackedVector2Array([shot["from"],mid + Vector2(12,-10),mid + Vector2(-8,8),shot["to"]]),Color("#a8f0ff"),3)

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
	if is_instance_valid(interactions) and not interactions.placing_content.is_empty() and interactions.phase_allows():
		var item: String = interactions.placing_content
		var center: Vector2 = grid.get_cell_rect(hovered_cell).get_center()
		if preload("res://Scripts/content_catalog.gd").WEAPONS.has(item):
			draw_launcher(center,{"weapon":item},true)
		else: draw_vein(center,item,{"direction":placement_direction,"progress":0,"level":1},true)
		draw_rect(grid.get_cell_rect(hovered_cell).grow(-1),Color("#ffe2a1") if interactions.can_place_item(hovered_cell,item) else Color("#e96f6f"),false,2)
	if is_instance_valid(interactions) and not interactions.placing_resource.is_empty() and interactions.phase_allows():
		var valid: bool = mining.can_move_nugget(hovered_cell)
		draw_rect(grid.get_cell_rect(hovered_cell).grow(-2), Color("#ffe18a") if valid else Color("#df7770"), false, 2)
		draw_nugget(grid.get_cell_rect(hovered_cell).get_center(), interactions.placing_resource, 1)

func draw_nugget(center: Vector2, kind: String, amount: int) -> void:
	preload("res://Scripts/content_art.gd").resource(self,center,kind,amount)

func preview_allowed(kind: String) -> bool:
	return tutorial == null or tutorial.allows_world_press(hovered_cell, kind)

func draw_vein(center: Vector2, kind: String, data: Dictionary, preview: bool = false) -> void:
	preload("res://Scripts/content_art.gd").vein(self,center,kind,int(data.get("direction",1)),int(data.get("level",1)))
	if not preview and data.get("progress",0) > 0: draw_line(center+Vector2(-14,21),center+Vector2(-14+28.0*data["progress"]/mining.hardness(kind),21),Color("#6ee7ce"),2,true)

func draw_coal_vein(center: Vector2, direction_index: int, progress: int, _preview: bool) -> void:
	preload("res://Scripts/content_art.gd").vein(self,center,"coal",direction_index,1)
	if progress > 0: draw_line(center+Vector2(-14,21),center+Vector2(-14+28.0*progress/5,21),Color("#6ee7ce"),2,true)

func draw_coal_nugget(center: Vector2, amount: int) -> void:
	preload("res://Scripts/content_art.gd").resource(self,center,"coal",amount)

func draw_sale_cell() -> void:
	var center: Vector2 = grid.get_cell_rect(grid.sale_cell).get_center()
	preload("res://Scripts/content_art.gd").plate(self,center,Color("#efcf7e"))
	draw_circle(center,12,Color("#efcf7e"),false,1.5,true)
	draw_line(center+Vector2(-4,4),center+Vector2(4,-4),Color("#efcf7e"),2,true)
	if sale_hovered: draw_circle(center,20,Color("#efcf7e"),false,1.5,true)

func draw_conveyor(center: Vector2, direction_index: int, preview: bool, shape: String = "straight") -> void:
	preload("res://Scripts/content_art.gd").machine(self,center,shape,direction_index)
	if preview: draw_circle(center,22,Color("#6ee7ce33"),true,-1,true)

func draw_drill(center: Vector2, direction_index: int, preview: bool) -> void:
	preload("res://Scripts/content_art.gd").machine(self,center,"drill",direction_index)
	if preview: draw_circle(center,22,Color("#6ee7ce33"),true,-1,true)

func draw_copper_vein(center: Vector2, direction_index: int, progress: int, preview: bool) -> void:
	preload("res://Scripts/content_art.gd").vein(self,center,"copper",direction_index,1)
	if progress > 0 and not preview: draw_line(center+Vector2(-14,21),center+Vector2(-14+28.0*progress/7,21),Color("#6ee7ce"),2,true)

func draw_copper_nugget(center: Vector2, amount: int) -> void:
	preload("res://Scripts/content_art.gd").resource(self,center,"copper",amount)

func draw_launcher(center: Vector2, data: Dictionary, preview: bool) -> void:
	draw_launcher_on(self, center, data, preview)

func draw_launcher_on(canvas: Node2D, center: Vector2, data: Dictionary, preview: bool) -> void:
	preload("res://Scripts/content_art.gd").weapon(canvas,center,data)
	if preview: canvas.draw_circle(center,22,Color("#6ee7ce33"),true,-1,true)

func draw_defense_platform(rect: Rect2) -> void:
	preload("res://Scripts/content_art.gd").plate(self,rect.get_center(),Color("#8aa3bc"))
	draw_arc(rect.get_center(),14,0,TAU,48,Color("#40536a"),1,true)

class GroundCanvas extends Node2D:
	const Scenery = preload("res://Scripts/mine_scenery.gd")
	var grid: RefCounted
	var meshes: Array[ArrayMesh] = []
	func _draw() -> void:
		if grid == null: return
		meshes.clear()
		var bounds := Rect2(0,grid.GRID_OFFSET_Y,grid.MAP_WIDTH*48,grid.MAP_HEIGHT*48)
		meshes.append(Scenery.field(self,bounds,0))
		var x: float = (grid.MAP_WIDTH/2-floori(grid.cave_width/2.0))*48
		var cave := Rect2(x,grid.GRID_OFFSET_Y,grid.cave_width*48,grid.cave_height*48)
		meshes.append(Scenery.field(self,cave,1))
		draw_grid_lines(self,cave,48,cave.position)
		draw_rect(cave,Color("#4a6478"),false,2)
		for side in [-1,1]:
			var edge: float = cave.position.x if side == -1 else cave.end.x
			for y in range(int(cave.position.y)+24,int(cave.end.y),192):
				draw_line(Vector2(edge,y-10),Vector2(edge,y+10),Color("#6ee7ce"),3,true)

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
		canvas.draw_multiline(lines, Color("#3a4d61"), 0.6,true)

static func draw_grid_lines(canvas: Node2D, bounds: Rect2, tile_size: float, origin: Vector2) -> void:
	GroundCanvas.draw_grid_lines(canvas, bounds, tile_size, origin)

func draw_iron_vein(center: Vector2, direction: int, progress: int, material: String = "iron") -> void:
	preload("res://Scripts/content_art.gd").vein(self,center,material,direction,1)
	if progress > 0: draw_line(center+Vector2(-14,21),center+Vector2(-14+28.0*progress/11,21),Color("#6ee7ce"),2,true)
