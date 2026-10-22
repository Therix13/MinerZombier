extends RefCounted

const Catalog = preload("res://Scripts/content_catalog.gd")

static var resource_cache: Dictionary = {}

static func polygon(image: Image, points: PackedVector2Array, color: Color) -> void:
	for y in range(48):
		for x in range(48):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5,y + 0.5),points): image.set_pixel(x,y,color)

static func resource_texture(kind: String) -> ImageTexture:
	if resource_cache.has(kind): return resource_cache[kind]
	var image := Image.create(48,48,false,Image.FORMAT_RGBA8)
	var material: String = kind.get_slice("_",0)
	var color := Color(Catalog.COLORS.get(material,"#c7cfdf"))
	for y in range(29,42):
		for x in range(6,43):
			if pow((x - 24) / 18.0,2) + pow((y - 36) / 5.0,2) < 1: image.set_pixel(x,y,Color(0,0,0,0.28))
	if material in Catalog.AMMO:
		image.fill_rect(Rect2i(10,9,28,28),Color("#202c32"))
		image.fill_rect(Rect2i(12,11,24,24),color.darkened(0.4))
		image.fill_rect(Rect2i(12,11,24,3),color.lightened(0.2))
		for i in range(3):
			image.fill_rect(Rect2i(15 + i * 6,18,4,13),color)
			image.fill_rect(Rect2i(15 + i * 6,16,4,3),color.lightened(0.4))
	elif "_ingot" in kind:
		polygon(image,PackedVector2Array([Vector2(8,34),Vector2(13,16),Vector2(34,16),Vector2(40,34),Vector2(31,39),Vector2(16,39)]),color.darkened(0.6))
		polygon(image,PackedVector2Array([Vector2(12,32),Vector2(16,18),Vector2(32,18),Vector2(36,32)]),color)
		image.fill_rect(Rect2i(18,20,3,10),color.lightened(0.5))
	else:
		var suffix: String = kind.get_slice("_",kind.get_slice_count("_") - 1)
		var tier: int = int(suffix) if suffix.is_valid_int() else 1
		for i in range(tier):
			var point := Vector2(18 + (i % 2) * 12,17 + (i / 2) * 11)
			var points := PackedVector2Array([point + Vector2(-8,6),point + Vector2(-5,-6),point + Vector2(3,-9),point + Vector2(9,3),point + Vector2(5,9)])
			polygon(image,points,color.darkened(0.55))
			polygon(image,PackedVector2Array([points[0] + Vector2(1,-1),points[1] + Vector2(1,1),points[2] + Vector2(0,2),point]),color.lightened(0.2))
			polygon(image,PackedVector2Array([point,points[2] + Vector2(0,2),points[3] + Vector2(-2,0),points[4] + Vector2(0,-2)]),color.darkened(0.1))
	var texture := ImageTexture.create_from_image(image)
	resource_cache[kind] = texture
	return texture

static func resource(canvas: CanvasItem, at: Vector2, kind: String, count: int = 1) -> void:
	canvas.draw_texture_rect(resource_texture(kind),Rect2(at - Vector2(24,24),Vector2(48,48)),false)
	if count > 1: canvas.draw_string(ThemeDB.fallback_font,at + Vector2(5,20),str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#fff0b9"))

static func vein(canvas: CanvasItem, at: Vector2, material: String, direction: int, tier: int) -> void:
	canvas.draw_rect(Rect2(at - Vector2(23,23),Vector2(46,46)),Color("#20272d"))
	canvas.draw_rect(Rect2(at - Vector2(21,21),Vector2(42,42)),Color("#849093"),false,2)
	resource(canvas,at,material + "_4")
	var forward := Vector2.UP.rotated(direction * PI * 0.5)
	canvas.draw_line(at,at + forward * 19,Color("#ffe4a0"),3)
	for i in range(tier): canvas.draw_rect(Rect2(at + Vector2(-9 + i * 5,-20),Vector2(3,4)),Color("#efcc8b"))

static func weapon(canvas: CanvasItem, at: Vector2, data: Dictionary) -> void:
	var id: String = data.get("weapon","pistol")
	var color := Color(Catalog.WEAPONS[id]["color"])
	var angle: float = data.get("angle",-PI * 0.5)
	var forward := Vector2.RIGHT.rotated(angle)
	var side := forward.rotated(PI * 0.5)
	var recoil: float = maxf(0,1.0 - (float(Catalog.WEAPONS[id]["interval"]) - float(data.get("cooldown",0))) / 0.18) * 3
	canvas.draw_circle(at + Vector2(1,3),23,Color(0,0,0,0.3))
	canvas.draw_rect(Rect2(at - Vector2(21,21),Vector2(42,42)),Color("#242b30"))
	canvas.draw_rect(Rect2(at - Vector2(19,19),Vector2(38,38)),color.darkened(0.45),false,3)
	for offset: Vector2 in [Vector2(-16,-16),Vector2(16,-16),Vector2(-16,16),Vector2(16,16)]:
		canvas.draw_circle(at + offset,2,Color("#e2cf9f"))
	canvas.draw_circle(at,15,color.darkened(0.5))
	canvas.draw_arc(at,13,0,TAU,16,color.lightened(0.15),2)
	var tip: Vector2 = at + forward * (25 - recoil)
	if id == "pistol":
		for offset in [-5,5]:
			canvas.draw_line(at + side * offset,tip + side * offset,Color("#202a30"),7)
			canvas.draw_line(at + side * offset,tip + side * offset,color,4)
	elif id == "tesla":
		for i in range(3): canvas.draw_arc(at,6 + i * 3,0,TAU,12,color,2)
		canvas.draw_circle(at,4,Color("#e4fcff"))
	else:
		canvas.draw_line(at - forward * 7,tip,Color("#182229"),15 if id == "rocketeer" else 12)
		canvas.draw_line(at - forward * 5,tip - forward * 2,color,10 if id == "rocketeer" else 8)
		canvas.draw_line(tip - side * 6,tip + side * 6,Color("#17242c"),4)
	var ammo: Array = data.get("ammo",[])
	canvas.draw_rect(Rect2(at + Vector2(-15,18),Vector2(30.0 * minf(1,float(ammo.size()) / Catalog.WEAPONS[id]["capacity"]),2)),color)
