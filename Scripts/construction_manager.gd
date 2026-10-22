extends Node2D

signal changed
signal completed(cell: Vector2i)

const ArtAtlas = preload("res://Scripts/art_atlas.gd")
const RECIPES := {
	"pistol":{"iron_ingot_2":1,"copper_ingot_3":1},
	"grenadier":{"iron_ingot_3":1,"copper_ingot_3":2},
	"rocketeer":{"gold_ingot_3":1,"iron_ingot_4":1},
	"tesla":{"tungsten_ingot_3":1,"copper_ingot_4":1},
	"launcher_2": {"copper_ingot_3": 1, "copper_ingot": 1},
	"saw": {"iron_3": 1, "iron": 1},
	"furnace": {"coal_4": 2},
	"straight": {"copper_ingot_3": 1},
	"corner_right": {"copper_ingot_3": 1},
	"corner_left": {"copper_ingot_3": 1},
	"junction": {"copper_ingot_3": 1},
	"filter": {"copper_ingot_3": 1},
	"compactor": {"iron_ingot_4": 1, "iron_ingot": 2},
	"drill": {"copper_ingot_3": 2, "copper_ingot": 2},
}
var plans: Dictionary = {}
var game: Node2D
var mining: RefCounted

func _ready() -> void:
	game = get_parent()
	mining = game.get("mining")
	mining.construction = self
	changed.connect(queue_redraw)
	changed.connect(game.redraw_world)

func _exit_tree() -> void:
	if mining != null and mining.construction == self: mining.construction = null

func has_recipe(item: String) -> bool:
	return RECIPES.has(item)

func place(cell: Vector2i, item: String, direction: int, price: int) -> bool:
	if not has_recipe(item) or not game.get_node("WorldInteractions").can_place_item(cell, item): return false
	plans[cell] = {"item": item, "direction": posmod(direction, 4), "paid": maxi(price, 0), "delivered": {}}
	changed.emit()
	return true

func can_move(source: Vector2i, destination: Vector2i) -> bool:
	if not plans.has(source) or game.get("cycle").is_night or not game.get_node("WorldInteractions").phase_allows(): return false
	return source == destination or game.get_node("WorldInteractions").can_place_item(destination,str(plans[source]["item"]))

func move_plan(source: Vector2i, destination: Vector2i, direction: int = -1) -> bool:
	if not can_move(source,destination): return false
	var data: Dictionary = plans[source]
	plans.erase(source)
	if direction >= 0: data["direction"] = posmod(direction,4)
	plans[destination] = data
	var inspector: Node = game.get_node_or_null("ToolInspector")
	if inspector != null and inspector.kind == "blueprint" and inspector.cell == source:
		inspector.cell = destination
	changed.emit()
	return true

func can_receive(cell: Vector2i, kind: String) -> bool:
	if not plans.has(cell): return false
	var data: Dictionary = plans[cell]
	return int(data["delivered"].get(kind, 0)) < int(RECIPES[data["item"]].get(kind, 0))

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell, kind): return false
	var data: Dictionary = plans[cell]
	data["delivered"][kind] = int(data["delivered"].get(kind, 0)) + 1
	for material: String in RECIPES[data["item"]]:
		if int(data["delivered"].get(material, 0)) < int(RECIPES[data["item"]][material]):
			changed.emit()
			return true
	plans.erase(cell)
	game.get_node("WorldInteractions").build_selected(cell, data["item"], int(data["direction"]))
	if data["item"] == "launcher_2":
		game.get("launchers").launchers[cell]["ammo"] = data.get("ammo",[]).duplicate()
		game.get("launchers").changed.emit()
	completed.emit(cell)
	changed.emit()
	return true

func recipe_text(item: String) -> String:
	if not has_recipe(item): return ""
	var text: String = "Plano: entrega materiales para construir."
	for material: String in RECIPES[item]:
		text += "\n%d × %s" % [RECIPES[item][material], game.get("shop").RESOURCE_LABELS.get(material,preload("res://Scripts/content_catalog.gd").label(material))]
	return text

func cancel(cell: Vector2i) -> bool:
	if not plans.has(cell) or game.get("cycle").is_night: return false
	var data: Dictionary = plans[cell]
	var free: Array[Vector2i] = []
	# Defense platforms cannot hold the raw ingredients of a canceled blueprint.
	if game.get("grid").is_valid_cell(cell) or game.get("grid").is_ammo_cell(cell): free.append(cell)
	for at: Vector2i in game.get("grid").owned_tiles:
		if at != cell and at != game.get("grid").sale_cell and mining.can_move_nugget(at): free.append(at)
	var count: int = 0
	for amount: int in data["delivered"].values(): count += amount
	count += data.get("ammo",[]).size()
	if count > free.size(): return false
	plans.erase(cell)
	for material: String in data["delivered"]:
		for index in range(int(data["delivered"][material])):
			mining.items_for(material)[free.pop_front()] = 1
	for material: String in data.get("ammo",[]):
		mining.items_for(material)[free.pop_front()] = 1
	game.get("economy").add(int(data["paid"]))
	mining.changed.emit()
	changed.emit()
	return true

func _process(_delta: float) -> void:
	if game != null and game.get("dragging_object") and game.get("held_object_type") == "blueprint": queue_redraw()

func _draw() -> void:
	if game == null: return
	var grid: RefCounted = game.get("grid")
	var dragging: bool = game.get("dragging_object") and game.get("held_object_type") == "blueprint"
	var held: Vector2i = game.get("held_object_cell")
	for cell: Vector2i in plans:
		if dragging and cell == held: continue
		draw_plan(grid.get_cell_rect(cell).get_center(),plans[cell])
	if dragging and plans.has(held): draw_plan(game.get("drag_world_position"),plans[held])

func draw_plan(center: Vector2, data: Dictionary) -> void:
	var rect := Rect2(center - Vector2(22,22),Vector2(44,44))
	draw_rect(rect, Color("#224b7099"))
	draw_rect(rect, Color("#8ed7fa"), false, 1.5)
	for offset in [-10, 0, 10]:
		draw_line(center + Vector2(-20, offset), center + Vector2(20, offset), Color("#84cbf33a"), 1)
		draw_line(center + Vector2(offset, -20), center + Vector2(offset, 20), Color("#84cbf33a"), 1)
	var item: String = data["item"]
	var direction: int = int(data["direction"])
	var key: String = "%s:%d" % [item, direction]
	if item == "furnace": key = "furnace:%d:0" % direction
	elif item in ["straight", "corner_right", "corner_left", "junction"]: key = "belt:%s:%d" % [item,direction]
	if preload("res://Scripts/content_catalog.gd").WEAPONS.has(item):
		preload("res://Scripts/content_art.gd").weapon(self,center,{"weapon":item,"ammo":[]})
		draw_rect(rect,Color("#4d9bde88"))
	elif item == "filter":
		preload("res://Scripts/filter_belt_art.gd").draw(self,center,direction)
		draw_rect(rect,Color("#4d9bde88"))
	elif item == "launcher_2":
		game.get("renderer").draw_launcher_on(self, center, {"ammo": [], "level": 2}, true)
		draw_rect(rect,Color("#4d9bde88"))
	elif item == "saw":
		preload("res://Scripts/saw_manager.gd").draw_machine(self,center,{"direction":direction})
		draw_rect(rect,Color("#4d9bde88"))
	elif ArtAtlas.prepare() and ArtAtlas.regions.has(key):
		draw_texture_rect_region(ArtAtlas.texture, Rect2(center - Vector2(28,28), Vector2(56,56)), ArtAtlas.regions[key], Color(0.55,0.8,1,0.65))
	var total: int = 0
	var delivered: int = 0
	for material: String in RECIPES[item]:
		total += int(RECIPES[item][material])
		delivered += int(data["delivered"].get(material, 0))
	draw_string(ThemeDB.fallback_font, center + Vector2(-12, 19), "%d/%d" % [delivered, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c4edff"))
