extends RefCounted

# Shared pixel terrain: built once, then batched from one texture by every canvas.
const TILE := 48
static var texture: ImageTexture
static var builds: int = 0
static var fields: Dictionary = {}

static func prepare() -> void:
	if texture != null: return
	var image := Image.create(TILE * 8,TILE * 4,false,Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 41723
	noise.frequency = 0.09
	var bases: Array[Color] = [Color("#444946"),Color("#96856b"),Color("#56604a"),Color("#62675e")]
	for kind in range(4):
		for variant in range(8):
			for y in range(0,TILE,2):
				for x in range(0,TILE,2):
					var grain: float = float(posmod(x * 17 + y * 31 + variant * 43,19)) / 19.0 - 0.5
					var shade: float = noise.get_noise_2d(x + variant * TILE,y + kind * 109) * 0.1 + grain * 0.025
					if kind == 1 and posmod(x * 7 + y * 3 + variant,53) < 2: shade -= 0.1
					var color: Color = bases[kind].lightened(shade) if shade >= 0 else bases[kind].darkened(-shade)
					image.fill_rect(Rect2i(variant * TILE + x,kind * TILE + y,2,2),color)
	texture = ImageTexture.create_from_image(image)
	builds += 1

static func tile(canvas: Node2D, rect: Rect2, kind: int, variant: int, tint := Color.WHITE) -> void:
	prepare()
	canvas.draw_texture_rect_region(texture,rect,Rect2(posmod(variant,8) * TILE,kind * TILE,TILE,TILE),tint)

static func mesh_from(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, uvs := PackedVector2Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if not uvs.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func field(canvas: Node2D, bounds: Rect2, kind: int, tint := Color.WHITE) -> ArrayMesh:
	prepare()
	var key: String = str(bounds) + ":" + str(kind)
	if not fields.has(key):
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for y in range(floori(bounds.position.y / TILE),ceili(bounds.end.y / TILE)):
			for x in range(floori(bounds.position.x / TILE),ceili(bounds.end.x / TILE)):
				var cell := Rect2(x * TILE,y * TILE,TILE,TILE).intersection(bounds)
				var variant: int = posmod(x * 31 + y * 17 + x * y,8)
				var source := Rect2(variant * TILE + cell.position.x - x * TILE,kind * TILE + cell.position.y - y * TILE,cell.size.x,cell.size.y)
				var first: int = vertices.size()
				for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
					var point: Vector2 = cell.position + cell.size * corner
					vertices.append(Vector3(point.x,point.y,0))
					colors.append(Color.WHITE)
					uvs.append((source.position + Vector2.ONE * 0.5 + (source.size - Vector2.ONE) * corner) / texture.get_size())
				indices.append_array(PackedInt32Array([first,first+1,first+2,first,first+2,first+3]))
		if fields.size() >= 8: fields.erase(fields.keys()[0])
		fields[key] = mesh_from(vertices,colors,indices,uvs)
	canvas.draw_mesh(fields[key],texture,Transform2D.IDENTITY,tint)
	return fields[key]

class Brush extends RefCounted:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var strings: Array = []
	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(points)
		if triangles.is_empty(): return
		var first: int = vertices.size()
		for point: Vector2 in points:
			vertices.append(Vector3(point.x,point.y,0))
			colors.append(color)
		for index: int in triangles: indices.append(first+index)
	func draw_line(a: Vector2, b: Vector2, color: Color, width: float = 1.0, _antialias: bool = false) -> void:
		var side: Vector2 = (b-a).normalized().orthogonal() * width * 0.5
		draw_colored_polygon(PackedVector2Array([a+side,b+side,b-side,a-side]),color)
	func draw_polyline(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
		for i in range(points.size()-1): draw_line(points[i],points[i+1],color,width)
	func draw_circle(at: Vector2, radius: float, color: Color) -> void:
		var points := PackedVector2Array()
		for i in range(20): points.append(at + Vector2.RIGHT.rotated(i * TAU / 20) * radius)
		draw_colored_polygon(points,color)
	func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = 1.0) -> void:
		var points := PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
		if filled: draw_colored_polygon(points,color)
		else:
			points.append(points[0])
			draw_polyline(points,color,width)
	func draw_multiline(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
		for i in range(0,points.size(),2): draw_line(points[i],points[i+1],color,width)
	func draw_string(font: Font, at: Vector2, text: String, alignment: int, width: float, font_size: int, color: Color) -> void:
		strings.append([font,at,text,alignment,width,font_size,color])
	func flush(canvas: Node2D) -> ArrayMesh:
		var mesh: ArrayMesh = load("res://Scripts/mine_scenery.gd").mesh_from(vertices,colors,indices)
		canvas.draw_mesh(mesh,null)
		for text: Array in strings: canvas.draw_string(text[0],text[1],text[2],text[3],text[4],text[5],text[6])
		return mesh

static func stone(canvas, at: Vector2, scale: float, tint: Color) -> void:
	var shape := PackedVector2Array([Vector2(-13,3),Vector2(-9,-8),Vector2(4,-12),Vector2(13,-4),Vector2(15,5),Vector2(5,10),Vector2(-8,9)])
	var polygon := PackedVector2Array()
	for point: Vector2 in shape: polygon.append(at + point * scale)
	canvas.draw_colored_polygon(polygon,tint.darkened(0.15))
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-9,-7) * scale,at + Vector2(4,-10) * scale,at + Vector2(10,-3) * scale,at + Vector2(-2,2) * scale]),tint.lightened(0.12))
	canvas.draw_line(at + Vector2(-10,6) * scale,at + Vector2(4,8) * scale,tint.darkened(0.32),2 * scale)

static func lamp(canvas, at: Vector2) -> void:
	canvas.draw_circle(at,22,Color(1.0,0.67,0.22,0.035))
	canvas.draw_circle(at,14,Color(1.0,0.67,0.22,0.065))
	canvas.draw_rect(Rect2(at - Vector2(5,7),Vector2(10,14)),Color("#302b22"))
	canvas.draw_rect(Rect2(at - Vector2(3,5),Vector2(6,10)),Color("#ffcb70"))
	canvas.draw_line(at + Vector2(-5,-7),at + Vector2(5,-7),Color("#b79a64"),2)
	canvas.draw_line(at + Vector2(-5,7),at + Vector2(5,7),Color("#b79a64"),2)

static func entrance(canvas, center_x: float, bottom: float) -> void:
	var top: float = bottom - 158
	# The sales counter remains exactly in its original interactive cell, inside the portal.
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(center_x-89,bottom),Vector2(center_x-85,top+42),Vector2(center_x-52,top+4),Vector2(center_x+44,top),Vector2(center_x+87,top+40),Vector2(center_x+92,bottom)]),Color("#363b36"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(center_x-66,bottom),Vector2(center_x-66,top+50),Vector2(center_x-43,top+29),Vector2(center_x+44,top+29),Vector2(center_x+65,top+50),Vector2(center_x+65,bottom)]),Color("#151f20"))
	canvas.draw_rect(Rect2(center_x-49,top+48,98,bottom-top-48),Color("#202a28"))
	for y in range(int(top + 77),int(bottom),17):
		canvas.draw_line(Vector2(center_x-35,y),Vector2(center_x+35,y),Color("#534432"),5)
	for side in [-1,1]:
		var x: float = center_x + side * 64
		canvas.draw_rect(Rect2(x-7,top+38,14,bottom-top-38),Color("#59412b"))
		canvas.draw_line(Vector2(x-3,top+40),Vector2(x-3,bottom),Color("#9b7547"),3)
		for y in [top+49,bottom-12]: canvas.draw_circle(Vector2(x,y),2,Color("#cab486"))
		canvas.draw_line(Vector2(center_x + side * 22,top+75),Vector2(center_x + side * 29,bottom),Color("#7e8580"),3)
		lamp(canvas,Vector2(center_x + side * 96,top+73))
	canvas.draw_rect(Rect2(center_x-78,top+25,156,17),Color("#4b3526"))
	canvas.draw_line(Vector2(center_x-78,top+27),Vector2(center_x+78,top+27),Color("#b48a55"),3)
	canvas.draw_line(Vector2(center_x-55,top+35),Vector2(center_x-64,top+60),Color("#84613c"),7)
	canvas.draw_line(Vector2(center_x+55,top+35),Vector2(center_x+64,top+60),Color("#84613c"),7)
	canvas.draw_rect(Rect2(center_x-31,top+3,62,20),Color("#392f24"))
	canvas.draw_rect(Rect2(center_x-31,top+3,62,20),Color("#a18654"),false,1)
	canvas.draw_string(ThemeDB.fallback_font,Vector2(center_x-20,top+18),"MINA",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#efd49b"))
