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
	draw_rect(Rect2(-8192,-8192,18000,18000),Color("#142333") if is_night else Color("#203746"))
	var corridor := PackedVector2Array([Vector2(center-550,-1600),Vector2(center+550,-1600),Vector2(center+125,0),Vector2(center-125,0)])
	draw_colored_polygon(corridor,Color("#203247") if is_night else Color("#304957"))
	for side in [-1,1]:
		draw_line(Vector2(center+side*550,-1600),Vector2(center+side*125,0),Color("#40576a"),2,true)
		for y in range(-1200,0,120):
			var x: float = center+side*(125-y*.265)
			draw_circle(Vector2(x,y),2,Color("#6ee7ce"),true,-1,true)
	draw_rect(Rect2(-8192,0,18000,grid.GRID_OFFSET_Y),Color("#34465b"))
	for offset in [18,70,142]: draw_line(Vector2(-8192,offset),Vector2(9812,offset-30),Color("#3c5066"),2,true)
	var brush := Scenery.Brush.new()
	Scenery.entrance(brush,center,grid.GRID_OFFSET_Y)
	meshes.clear()
	meshes.append(brush.flush(self))
