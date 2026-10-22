extends RefCounted
const Painted = preload("res://Scripts/painted_assets.gd")
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
static func resource_texture(kind: String) -> Texture2D:
	if resource_cache.has(kind): return resource_cache[kind]
	var material: String = kind.get_slice("_",0)
	var index: int = -1
	if "_ingot" in kind: index = {"copper":0,"iron":1,"gold":2,"tungsten":3}.get(material,1)
	else: index = {"nitrate":4,"sulfur":5,"powder":6,"bullet":7,"highcaliber":8,"grenade":9,"rocket":10,"battery":11}.get(material,-1)
	var result: Texture2D = Painted.cell(Painted.COMPONENTS,index,4,3) if index >= 0 else Painted.prop({"coal":0,"copper":1,"iron":2,"gold":3,"tungsten":2}.get(material,2))
	resource_cache[kind] = result
	return result

static func resource(canvas: CanvasItem, at: Vector2, kind: String, count: int = 1) -> void:
	var material: String = kind.get_slice("_",0)
	var tint: Color = {"nitrate":Color(.7,1,1),"sulfur":Color(1,.88,.3),"tungsten":Color(.65,.8,1)}.get(material,Color.WHITE)
	var suffix: String = kind.get_slice("_",kind.get_slice_count("_")-1)
	var tier: int = int(suffix) if suffix.is_valid_int() else 1
	if "_ingot" in kind:
		var size: float = 31+tier*3
		Painted.draw(canvas,resource_texture(kind),Rect2(at-Vector2.ONE*size*.5,Vector2.ONE*size),tint)
	else:
		var size: float = 30+tier*3.5
		Painted.draw(canvas,resource_texture(kind),Rect2(at-Vector2.ONE*size*.5,Vector2.ONE*size),tint)
	if material not in Catalog.AMMO:
		var marks := ""
		for i in range(tier): marks += '<circle cx="%d" cy="43" r="1.2" fill="#eac48e"/>' % (15+i*5)
		canvas.draw_texture_rect(svg_texture("tier_"+str(tier),marks),Rect2(at-Vector2(24,24),Vector2(48,48)),false)
	if count > 1: canvas.draw_string(ThemeDB.fallback_font,at+Vector2(8,19),str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("#f7e6c6"))

static func plate(canvas: CanvasItem, at: Vector2, color := ACCENT) -> void:
	var body := '<rect x="2" y="3" width="44" height="43" rx="4" fill="#111719" opacity=".7"/><rect x="3" y="2" width="42" height="42" rx="3" fill="#333b3e" stroke="#7e7769" stroke-width="1"/><path d="M7 6h34M7 9h34" stroke="#a09174" stroke-width=".7" opacity=".45"/><path d="M6 39h36" stroke="#11191d" stroke-width="2"/>'
	for offset: Vector2 in [Vector2(6,6),Vector2(42,6),Vector2(6,42),Vector2(42,42)]: body += '<circle cx="%d" cy="%d" r="1.4" fill="#%s"/>' % [offset.x,offset.y,color.darkened(.25).to_html(false)]
	canvas.draw_texture_rect(svg_texture("industrial_base_"+color.to_html(),body),Rect2(at-Vector2(24,24),Vector2(48,48)),false)

static func arrow(canvas: CanvasItem, at: Vector2, direction: int, color := ACCENT) -> void:
	var f := Vector2.UP.rotated(direction*PI*.5)
	var s := f.orthogonal()
	canvas.draw_line(at-f*6,at+f*8,color,2,true)
	canvas.draw_polyline(PackedVector2Array([at+f*3+s*4,at+f*8,at+f*3-s*4]),color,2,true)
static func vein(canvas: CanvasItem, at: Vector2, material: String, direction: int, tier: int) -> void:
	plate(canvas,at,Color("#af9a74"))
	resource(canvas,at+Vector2(-1,-2),material+"_4")
	arrow(canvas,at+Vector2(15,11),direction,Color("#efc77d"))
	for i in range(maxi(1,tier)): canvas.draw_circle(at+Vector2(-12+i*6,-17),1.3,Color("#e7c888"),true,-1,true)

static func machine(canvas: CanvasItem, at: Vector2, id: String, direction: int = 0, phase: float = 0.0) -> void:
	if id in ["drill","furnace","compactor","saw"]:
		var index: int = {"drill":4,"furnace":5,"compactor":6,"saw":7}[id]
		var position: Vector2 = at
		var scale := Vector2.ONE
		if id == "drill": position += Vector2.UP.rotated(direction*PI*.5)*sin(phase)*.6
		if id == "compactor": scale.y = 1-.035*absf(sin(phase))
		canvas.draw_set_transform(position,(PI+direction*PI*.5) if id == "drill" else 0.0,scale)
		Painted.draw(canvas,Painted.prop(index),Rect2(-25,-25,50,50))
		canvas.draw_set_transform(Vector2.ZERO)
		if id == "saw":
			var f := Vector2.UP.rotated(direction*PI*.5)
			for side in [-1,1]:
				var v: Vector2 = (f+f.orthogonal()*side).normalized()
				var end: Vector2 = at+v*26
				canvas.draw_line(at+v*14,end,Color("#efc77d"),2,true)
				canvas.draw_polyline(PackedVector2Array([end-v*7+v.orthogonal()*4,end,end-v*7-v.orthogonal()*4]),Color("#efc77d"),2,true)
		else: arrow(canvas,at+Vector2.UP.rotated(direction*PI*.5)*19,direction,Color("#efc77d"))
		return
	# Cache the steel rollers and routing marks as one smooth icon per belt shape.
	var body := '<rect x="2" y="2" width="44" height="44" rx="4" fill="#333b3e" stroke="#8c8575"/><rect x="6" y="6" width="36" height="36" fill="#202b2e"/>'
	for i in range(5):
		var y: int = 11+i*6
		body += '<path d="M10 %dH38" stroke="#697272" stroke-width="3"/><path d="M11 %dH37" stroke="#a4a28d" stroke-width=".8"/>' % [y,y-1]
	body += '<path d="M24 32V17M20 21L24 16L28 21" fill="none" stroke="#efc77d" stroke-width="2"/>'
	if id in ["corner","corner_right","corner_left"]:
		body += '<path d="M24 24H%s" stroke="#efc77d" stroke-width="2"/>' % ("7" if id == "corner_left" else "41")
	if id == "junction": body += '<path d="M7 24H41" stroke="#efc77d" stroke-width="2"/>'
	if id in ["filter","splitter"]: body += '<path d="M24 24H39L35 20M39 24L35 28" fill="none" stroke="#78bfc8" stroke-width="2"/>'
	if id == "splitter": body += '<path d="M24 24H9L13 20M9 24L13 28" fill="none" stroke="#efc77d" stroke-width="2"/>'
	if id == "ejector": body += '<path d="M17 12Q24 4 31 12" fill="none" stroke="#efc77d" stroke-width="2"/>'
	canvas.draw_set_transform(at,direction*PI*.5)
	canvas.draw_texture_rect(svg_texture("painted_belt_"+id,body),Rect2(-24,-24,48,48),false)
	canvas.draw_set_transform(Vector2.ZERO)

static func weapon(canvas: CanvasItem, at: Vector2, data: Dictionary) -> void:
	var id: String = data.get("weapon","")
	var index: int = 8 if int(data.get("level",1)) == 1 else 9
	if id == "ak47": index = 10
	elif id == "minigun": index = 11
	elif id in ["grenadier","rocketeer"]: index = 8
	var angle: float = float(data.get("angle",-PI*.5))
	var direction := Vector2.RIGHT.rotated(angle)
	var recoil: float = 0.0
	if Catalog.WEAPONS.has(id): recoil = maxf(0,1-(float(Catalog.WEAPONS[id]["interval"])-float(data.get("cooldown",0)))/.15)*2
	else: recoil = maxf(0,1-((2.0 if data.get("level",1) == 2 else 4.0)-float(data.get("cooldown",0)))/.15)*2
	canvas.draw_set_transform(at-direction*recoil,angle-PI*.5)
	Painted.draw(canvas,Painted.prop(index),Rect2(-25,-25,50,50),Color(.8,.9,1) if id == "tesla" else Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO)
	if id == "tesla":
		for i in range(3): canvas.draw_arc(at,5+i*3,0,TAU,32,Color(.25,.8,1,.65),1.2,true)
	var maximum: int = Catalog.WEAPONS[id]["capacity"] if Catalog.WEAPONS.has(id) else (7 if data.get("level",1) == 2 else 5)
	canvas.draw_line(at+Vector2(-14,21),at+Vector2(14,21),Color("#1d2428"),2,true)
	if not data.get("ammo",[]).is_empty(): canvas.draw_line(at+Vector2(-14,21),at+Vector2(-14+28.0*minf(1,float(data["ammo"].size())/maximum),21),Color("#e9c17d"),2,true)
