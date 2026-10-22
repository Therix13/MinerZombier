extends Node2D

const Scenery = preload("res://Scripts/mine_scenery.gd")
const ZONE_TOP: float = -640.0
const ZONE_BOTTOM: float = 0.0

var grid: RefCounted
var is_night: bool = false
var meshes: Array[ArrayMesh] = []

func setup(grid_manager: RefCounted) -> void:
	grid = grid_manager
	Scenery.prepare()
	queue_redraw()

func set_night(enabled: bool) -> void:
	if is_night != enabled:
		is_night = enabled
		queue_redraw()

func _draw() -> void:
	if grid == null: return
	var center: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	draw_rect(Rect2(-8192,-8192,18000,18000),Color("#151d24"))
	meshes.clear()
	meshes.append(Scenery.field(self,Rect2(-1024,-1792,3488,1792),2,Color(.6,.75,.87) if is_night else Color(.9,.93,.96)))
	var path := PackedVector2Array([Vector2(center-550,-1600),Vector2(center+550,-1600),Vector2(center+125,0),Vector2(center-125,0)])
	draw_colored_polygon(path,Color(.04,.07,.09,.18) if is_night else Color(.18,.14,.08,.12))
	meshes.append(Scenery.field(self,Rect2(-1024,0,3488,grid.GRID_OFFSET_Y),3))
	var art = preload("res://Scripts/painted_assets.gd")
	var portal := Rect2(center-174,-12,348,232)
	art.draw(self,art.environment(0),portal)
	for side in [-1,1]:
		for i in range(22):
			var x: float = center+side*(174-i*1.7)
			draw_line(Vector2(x,-12),Vector2(x,220),Color(.08,.11,.14,.55*(1-float(i)/22)),2)
		var at := Vector2(center+side*80,126)
		for r in range(6,45,5): draw_circle(at,r,Color(1,.62,.25,.018),true,-1,true)
