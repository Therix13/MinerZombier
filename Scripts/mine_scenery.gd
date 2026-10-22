extends RefCounted

# Flat vector terrain is batched into retained meshes; no noise or pixel textures.
const TILE := 48
static var texture: ImageTexture
static var builds: int = 0

static func prepare() -> void:
	if texture != null: return
	var image := Image.create(1,1,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(image)
	builds += 1

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
	var brush := Brush.new()
	var colors := [Color("#121d2d"),Color("#29394d"),Color("#1c2d3b"),Color("#34465b")]
	brush.draw_rect(bounds,colors[clampi(kind,0,3)] * tint)
	return brush.flush(canvas)

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

static func entrance(canvas, center_x: float, bottom: float) -> void:
	var top: float = bottom-150
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(center_x-90,bottom),Vector2(center_x-90,top+35),Vector2(center_x-55,top),Vector2(center_x+55,top),Vector2(center_x+90,top+35),Vector2(center_x+90,bottom)]),Color("#111b2b"))
	for side in [-1,1]:
		var x: float = center_x+side*72
		canvas.draw_line(Vector2(x,top+37),Vector2(x,bottom),Color("#536b82"),8)
		canvas.draw_line(Vector2(x-side*5,top+40),Vector2(x-side*5,bottom-5),Color("#6ee7ce"),2)
	canvas.draw_line(Vector2(center_x-72,top+37),Vector2(center_x+72,top+37),Color("#536b82"),8)
	canvas.draw_string(ThemeDB.fallback_font,Vector2(center_x-35,top+24),"SECTOR 07",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#d6e5f3"))
	for side in [-1,1]: canvas.draw_line(Vector2(center_x+side*18,top+55),Vector2(center_x+side*25,bottom),Color("#40536a"),2)
