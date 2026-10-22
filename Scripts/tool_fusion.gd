extends Node2D

# Separate metadata also supports legacy drills represented by integer directions.
var levels: Dictionary = {}
var game: Node
const SUPPORTED := ["drill","belt","furnace","compactor","saw"]
func _ready() -> void:
	game = get_parent()
func level_at(cell: Vector2i) -> int:
	return int(levels.get(cell,1))
func speed(cell: Vector2i) -> float:
	return [1.0,1.5,2.25,3.375][level_at(cell)-1]
func can_fuse(kind: String, a: Vector2i, b: Vector2i) -> bool:
	if kind not in SUPPORTED or a == b or game.cycle.is_night: return false
	var mover: Node = game.get_node("WorldInteractions")
	var maps: Dictionary = mover.stores()
	if not maps[kind].has(a) or not maps[kind].has(b) or level_at(a) != level_at(b) or level_at(a) >= 4: return false
	if kind == "belt":
		return game.conveyors.belt_shape(a) == game.conveyors.belt_shape(b) and game.mining.nuggets_at(a) == 0 and game.mining.nuggets_at(b) == 0
	# Never discard fuel, progress, ingredients or pending outputs. Empty machines only.
	if kind != "drill":
		for at: Vector2i in [a,b]:
			var data: Dictionary = maps[kind][at]
			if data.get("fuel",0) != 0 or data.get("points",0) != 0 or data.get("input","") != "" or data.get("output","") != "" or data.get("count",0) != 0: return false
	return true
func fuse(kind: String, a: Vector2i, b: Vector2i) -> bool:
	if not can_fuse(kind,a,b): return false
	var tier: int = level_at(b) + 1
	game.get_node("WorldInteractions").stores()[kind].erase(a)
	if kind == "belt": game.conveyors.last_junction_entry.erase(a)
	levels.erase(a)
	levels[b] = tier
	game.campaign.state["tool_tier"] = maxi(tier,game.campaign.state.get("tool_tier",1))
	game.campaign.check_achievements()
	game.redraw_world()
	for path: String in ["Furnaces","Compactors","Saws"]: game.get_node(path).queue_redraw()
	queue_redraw()
	return true
func _process(_delta: float) -> void:
	set_process(false)

func _draw() -> void:
	if game == null: return
	for cell: Vector2i in levels:
		if game.dragging_object and game.held_object_cell == cell: continue
		var at: Vector2 = game.grid.get_cell_rect(cell).position + Vector2(5,8)
		for i in range(level_at(cell)):
			draw_circle(at + Vector2(i * 5,0),1.5,Color("#6ee7ce"),true,-1,true)
