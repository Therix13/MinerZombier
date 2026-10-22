extends RefCounted

# Original painted sheets. AtlasTexture regions keep source PNGs intact and share VRAM.
const OPENING := "res://Art/Cinematics/origin_panels.png"
const INDUSTRY := "res://Art/Sprites/industry.png"
const COMPONENTS := "res://Art/Sprites/components.png"
const INFECTED := "res://Art/Sprites/infected.png"
const WORLD := "res://Art/Environments/mine_world.png"
static var textures: Dictionary = {}
static var regions: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if textures.has(path): return textures[path]
	var result: Texture2D
	if ResourceLoader.exists(path): result = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if not image.is_empty():
			image.generate_mipmaps()
			result = ImageTexture.create_from_image(image)
	if result != null: textures[path] = result
	return result

static func region(path: String, rectangle: Rect2) -> AtlasTexture:
	var key: String = path + str(rectangle)
	if regions.has(key): return regions[key]
	var result := AtlasTexture.new()
	result.atlas = texture(path)
	result.region = rectangle
	result.filter_clip = true
	regions[key] = result
	return result

static func cell(path: String, index: int, columns: int, rows: int) -> AtlasTexture:
	var sheet: Texture2D = texture(path)
	if sheet == null: return null
	var size: Vector2 = sheet.get_size()/Vector2(columns,rows)
	return region(path,Rect2(Vector2(index%columns,index/columns)*size,size))

static func prop(index: int) -> AtlasTexture:
	return cell(INDUSTRY,index,4,3)

static func scene(index: int) -> AtlasTexture:
	return cell(OPENING,clampi(index,0,3),2,2)

static func environment(index: int) -> AtlasTexture:
	return cell(WORLD,clampi(index,0,3),2,2)

static func enemy_index(kind: String) -> int:
	if kind in ["armored","shielder","warden"]: return 1
	if kind in ["spitter","sapper","healer","bomber"]: return 2
	if kind in ["brute","berserker","executor"]: return 3
	if kind == "plague": return 4
	if kind in ["swarm","broodmother"]: return 5
	return 0

static func enemy_region(kind: String) -> Rect2:
	var index: int = enemy_index(kind)
	var sheet: Texture2D = texture(INFECTED)
	if sheet == null: return Rect2()
	# The lower, taller bosses occupy the bottom 58% of this painted sheet.
	var size: Vector2 = sheet.get_size()
	var split: float = size.y*0.422
	return Rect2(index%3*size.x/3,0 if index < 3 else split,size.x/3,split if index < 3 else size.y-split)

static func enemy(kind: String) -> AtlasTexture:
	return region(INFECTED,enemy_region(kind))

static func draw(canvas: CanvasItem, image: Texture2D, rectangle: Rect2, tint := Color.WHITE) -> void:
	if image != null: canvas.draw_texture_rect(image,rectangle,false,tint)
