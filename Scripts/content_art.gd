extends RefCounted
const Catalog = preload("res://Scripts/content_catalog.gd")
const INK := Color("#111b2b")
const EDGE := Color("#40536a")
const ACCENT := Color("#6ee7ce")
static var resource_cache: Dictionary = {}
static var models: Dictionary = {}
static func svg_texture(key: String, body: String) -> ImageTexture:
	if models.has(key): return models[key]
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 48 48">'+body+'</svg>')
	image.generate_mipmaps()
	models[key] = ImageTexture.create_from_image(image)
	return models[key]
static func resource_texture(kind: String) -> ImageTexture:
	if resource_cache.has(kind): return resource_cache[kind]
	var material: String = kind.get_slice("_",0)
	var color: String = Catalog.COLORS.get(material,"#b5c8db")
	var body := '<ellipse cx="24" cy="37" rx="16" ry="3" fill="#0d1725" opacity=".35"/>'
	if material in Catalog.AMMO:
		body += '<rect x="7" y="9" width="34" height="30" rx="7" fill="#253449" stroke="%s" stroke-width="1.5"/>' % color
		if material == "grenade": body += '<path d="M21 13h6v5h-6z" fill="#dbe7ef"/><ellipse cx="24" cy="27" rx="8" ry="9" fill="%s"/>' % color
		elif material == "rocket": body += '<path d="M24 13l6 8v12l-6-3-6 3V21z" fill="%s"/>' % color
		elif material == "powder": body += '<path d="M13 32l6-9 5 5 5-11 7 15z" fill="%s"/>' % color
		elif material == "battery": body += '<path d="M25 13l-8 14h7l-2 9 10-15h-7z" fill="%s"/>' % color
		else:
			for i in range(3): body += '<path d="M%d 31V20l3-6 3 6v11z" fill="%s"/>' % [13+i*8,color]
	elif "_ingot" in kind:
		body += '<path d="M10 32l5-17h18l5 17-7 6H17z" fill="%s"/><path d="M15 15h18l-3 17H11z" fill="#fff" opacity=".17"/><path d="M17 19l-3 11" stroke="#fff" opacity=".5" stroke-width="2" stroke-linecap="round"/>' % color
	else:
		body += '<path d="M8 29l7-15 15-5 10 14-6 14H18z" fill="%s"/><path d="M15 14l15-5-5 16-17 4z" fill="#fff" opacity=".22"/><path d="M25 25l15-2-6 14H18z" fill="#111b2b" opacity=".18"/>' % color
	var suffix: String = kind.get_slice("_",kind.get_slice_count("_")-1)
	var tier: int = int(suffix) if suffix.is_valid_int() else 1
	if material not in Catalog.AMMO:
		for i in range(tier): body += '<circle cx="%d" cy="42" r="1.4" fill="%s"/>' % [24-(tier-1)*3+i*6,color]
	resource_cache[kind] = svg_texture("resource:"+kind,body)
	return resource_cache[kind]
static func resource(canvas: CanvasItem, at: Vector2, kind: String, count: int = 1) -> void:
	canvas.draw_texture_rect(resource_texture(kind),Rect2(at-Vector2(24,24),Vector2(48,48)),false)
	if count > 1: canvas.draw_string(ThemeDB.fallback_font,at+Vector2(7,19),str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#ecf4fb"))
static func plate(canvas: CanvasItem, at: Vector2, color := ACCENT) -> void:
	var body := '<rect x="2" y="4" width="44" height="43" rx="8" fill="#0d1725" opacity=".4"/><rect x="2" y="2" width="44" height="42" rx="8" fill="#253449" stroke="#40536a" stroke-width="1"/><path d="M10 3h28" stroke="#%s" stroke-width="2" stroke-linecap="round"/>' % color.to_html(false)
	canvas.draw_texture_rect(svg_texture("plate:"+color.to_html(),body),Rect2(at-Vector2(24,24),Vector2(48,48)),false)
static func arrow(canvas: CanvasItem, at: Vector2, direction: int, color := ACCENT) -> void:
	var f := Vector2.UP.rotated(direction*PI*.5)
	var s := f.orthogonal()
	canvas.draw_line(at-f*6,at+f*8,color,2,true)
	canvas.draw_polyline(PackedVector2Array([at+f*3+s*4,at+f*8,at+f*3-s*4]),color,2,true)
static func vein(canvas: CanvasItem, at: Vector2, material: String, direction: int, tier: int) -> void:
	var color := Color(Catalog.COLORS.get(material,"#b5c8db"))
	plate(canvas,at,color)
	canvas.draw_texture_rect(resource_texture(material),Rect2(at-Vector2(18,20),Vector2(36,36)),false)
	arrow(canvas,at+Vector2(14,10),direction)
	for i in range(maxi(1,tier)): canvas.draw_circle(at+Vector2(-12+i*6,18),1.4,color,true,-1,true)
static func machine(canvas: CanvasItem, at: Vector2, id: String, direction: int = 0, phase: float = 0.0) -> void:
	plate(canvas,at)
	var f := Vector2.UP.rotated(direction*PI*.5)
	var s := f.orthogonal()
	if id in ["drill","saw"]:
		canvas.draw_circle(at,13,INK,true,-1,true)
		canvas.draw_arc(at,10,phase,TAU-.5+phase,40,ACCENT,3,true)
		canvas.draw_circle(at,4,Color("#d9e6f2"),true,-1,true)
		if id == "saw":
			for tooth in range(8):
				var v := Vector2.RIGHT.rotated(phase+tooth*TAU/8)
				canvas.draw_line(at+v*11,at+v*15,Color("#b5c8db"),2,true)
			for sign_value in [-1,1]:
				var v: Vector2 = (f+s*sign_value).normalized()
				canvas.draw_line(at+v*13,at+v*24,ACCENT,2,true)
				canvas.draw_line(at+v*24,at+v*17+v.orthogonal()*4,ACCENT,2,true)
		else: arrow(canvas,at+f*15,direction)
	elif id == "furnace":
		canvas.draw_circle(at,13,INK,true,-1,true)
		for i in range(3): canvas.draw_line(at+Vector2(-6+i*6,7),at+Vector2(-6+i*6,-7+sin(phase+i)*2),Color("#efaa84"),3,true)
		arrow(canvas,at+f*18,direction)
	elif id == "compactor":
		for sign_value in [-1,1]: canvas.draw_line(at+Vector2(-11,sign_value*(8+sin(phase)*3)),at+Vector2(11,sign_value*(8+sin(phase)*3)),ACCENT,4,true)
		for x in [-14,14]: canvas.draw_line(at+Vector2(x,-10),at+Vector2(x,10),EDGE,2,true)
		arrow(canvas,at+f*18,direction)
	else:
		for offset in [-10,0,10]:
			var a: Vector2 = at-f*offset
			canvas.draw_line(a-s*12,a+s*12,EDGE,2,true)
		arrow(canvas,at,direction)
		if id in ["corner","corner_right","corner_left"]:
			canvas.draw_line(at,at+s*(17 if id == "corner_left" else -17),ACCENT,2,true)
		if id == "junction":
			canvas.draw_line(at-s*17,at+s*17,ACCENT,2,true)
		if id in ["filter","splitter"]: arrow(canvas,at+s*13,posmod(direction+1,4),Color("#efaa84"))
		if id == "splitter": arrow(canvas,at-s*13,posmod(direction+3,4))
		if id == "ejector": canvas.draw_arc(at+f*13,7,0,PI,16,Color("#efaa84"),2,true)
static func weapon(canvas: CanvasItem, at: Vector2, data: Dictionary) -> void:
	var id: String = data.get("weapon","")
	var color := Color(Catalog.WEAPONS[id]["color"]) if Catalog.WEAPONS.has(id) else (Color("#d49b84") if data.get("level",1) == 1 else ACCENT)
	plate(canvas,at,color)
	var f := Vector2.RIGHT.rotated(float(data.get("angle",-PI*.5)))
	var side := f.orthogonal()
	canvas.draw_circle(at,13,INK,true,-1,true)
	canvas.draw_arc(at,11,0,TAU,40,color,2,true)
	var recoil: float = sin(minf(.15,float(data.get("cooldown",0)))*20)*2
	if id == "tesla":
		for i in range(3): canvas.draw_arc(at,4+i*3,0,TAU,32,color,1.5,true)
	else:
		var barrels: int = 3 if id == "minigun" else (2 if id == "pistol" else 1)
		for i in range(barrels):
			var offset: Vector2 = side*(i-(barrels-1)*.5)*5
			canvas.draw_line(at-f*3+offset,at+f*(24-recoil)+offset,INK,7,true)
			canvas.draw_line(at+offset,at+f*(23-recoil)+offset,color,3,true)
	if id == "ak47": canvas.draw_polyline(PackedVector2Array([at+side*5,at-f*6+side*9,at-f*13+side*7]),color,4,true)
	elif id == "minigun": canvas.draw_line(at-side*14,at-side*8,color,8,true)
	elif id == "grenadier": canvas.draw_circle(at+f*18,6,color,false,2,true)
	elif id == "rocketeer": canvas.draw_line(at-f*7,at+f*20,color,8,true)
	var maximum: int = Catalog.WEAPONS[id]["capacity"] if Catalog.WEAPONS.has(id) else (7 if data.get("level",1) == 2 else 5)
	canvas.draw_line(at+Vector2(-13,17),at+Vector2(13,17),INK,2,true)
	if not data.get("ammo",[]).is_empty(): canvas.draw_line(at+Vector2(-13,17),at+Vector2(-13+26.0*minf(1,float(data["ammo"].size())/maximum),17),color,2,true)
