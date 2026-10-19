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
	meshes.clear()
	var width: float = float(grid.MAP_WIDTH * grid.TILE_SIZE)
	var visible: Rect2 = get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var left: float = minf(-512.0,visible.position.x - 256)
	var right: float = maxf(width + 512.0,visible.end.x + 256)
	var top: float = minf(-1536.0,visible.position.y - 256)
	var tint := Color("#728d9a") if is_night else Color.WHITE
	# A continuous foundation eliminates white gaps at wide aspect ratios and during pans.
	draw_rect(Rect2(-8192,-8192,18000,18000),Color("#343c39"))
	meshes.append(Scenery.field(self,Rect2(left,top,right-left,-top),2,tint))
	var center: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var brush := Scenery.Brush.new()
	var path := PackedVector2Array()
	for side in [-1,1]:
		for index in range(25):
			var y: float = top * (float(index) / 24.0 if side == -1 else 1.0 - float(index) / 24.0)
			var half_width: float = 125 - y * 0.25
			path.append(Vector2(center + side * half_width + sin(y * 0.013) * 11,y))
	brush.draw_colored_polygon(path,Color("#3f4947") if is_night else Color("#7e7256"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 29041
	# Footprints, gravel and wagon ruts stay subtle so enemies and acid remain readable.
	var dust := Color("#697469",0.4) if is_night else Color("#b09a72",0.4)
	for index in range(260):
		var y: float = rng.randf_range(top,-10)
		var half_width: float = 110 - y * 0.24
		var x: float = center + rng.randf_range(-half_width,half_width)
		brush.draw_line(Vector2(x,y),Vector2(x + rng.randf_range(2,6),y-2),dust,1)
	for side in [-1,1]:
		var rut := PackedVector2Array()
		for i in range(18):
			var y: float = top * i / 17.0
			rut.append(Vector2(center + side * (34 - y * 0.027) + sin(y * 0.013) * 11,y))
		brush.draw_polyline(rut,Color("#1d2828",0.18),4)
	for index in range(110):
		var y: float = rng.randf_range(top,-15)
		var half_width: float = 150 - y * 0.25
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var x: float = center + side * rng.randf_range(half_width,half_width+430)
		if index % 4 == 0:
			Scenery.stone(brush,Vector2(x,y),rng.randf_range(0.5,1.2),Color("#465452") if is_night else Color("#717365"))
		else:
			var grass := Color("#525e50") if is_night else Color("#858163")
			for ray in range(3): brush.draw_line(Vector2(x,y),Vector2(x-5+ray*5,y-8-rng.randf_range(0,5)),grass,1)
	# Weathered fence remnants flank the approach, with an open combat corridor.
	for side in [-1,1]:
		for index in range(7):
			var y: float = -65 - index * 145
			var x: float = center + side * (160 - y * 0.25)
			var wood := Color("#3e4841") if is_night else Color("#655e43")
			brush.draw_line(Vector2(x,y+12),Vector2(x+3,y-14),wood,7)
			brush.draw_line(Vector2(x,y-5),Vector2(x+side*35,y-15),wood,4)
			Scenery.stone(brush,Vector2(x+side*16,y+22),0.6,wood.lightened(0.05))
	meshes.append(brush.flush(self))
	meshes.append(Scenery.field(self,Rect2(left,0,right-left,grid.GRID_OFFSET_Y),3))
	brush = Scenery.Brush.new()
	# Long, offset strata make the cliff a rock face rather than a white separator.
	for row in range(5):
		var seams := PackedVector2Array()
		var y: float = 15 + row * 43
		for x in range(int(left)-96,int(right)+96,72):
			seams.append(Vector2(x,y + posmod(x * 13 + row * 31,15)))
		brush.draw_polyline(seams,Color("#303d36",0.35),3)
	brush.draw_rect(Rect2(left,0,right-left,8),Color("#2d3730"))
	brush.draw_line(Vector2(left,grid.GRID_OFFSET_Y-3),Vector2(right,grid.GRID_OFFSET_Y-3),Color("#272f2a"),6)
	Scenery.entrance(brush,center,grid.GRID_OFFSET_Y)
	meshes.append(brush.flush(self))
