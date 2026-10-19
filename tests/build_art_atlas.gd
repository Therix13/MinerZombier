# Developer utility: regenerate the embedded atlas from the original vector artwork.
extends SceneTree
var recipes: Array[String] = []
class Painter extends "res://Scripts/world_renderer.gd":
	var recipes: Array[String]
	func _init() -> void:
		rasterizing = true
		grid = preload("res://Scripts/grid_manager.gd").new()
		mining = preload("res://Scripts/mining_manager.gd").new()
		conveyors = preload("res://Scripts/conveyor_manager.gd").new()
		drills = preload("res://Scripts/drill_manager.gd").new()
		launchers = preload("res://Scripts/potato_launcher_manager.gd").new()
	func _draw() -> void:
		for index in range(recipes.size()):
			var parts: PackedStringArray = recipes[index].split(":")
			var center := Vector2(index % 8 * 64 + 32, index / 8 * 64 + 32)
			match parts[0]:
				"coal": draw_coal_vein(center, int(parts[1]), int(parts[2]), false)
				"copper": draw_copper_vein(center, int(parts[1]), int(parts[2]), false)
				"belt": draw_conveyor(center, int(parts[2]), false, parts[1])
				"drill": draw_drill(center, int(parts[1]), false)
				"ore": draw_nugget(center, parts[1], 1)
				"platform": draw_defense_platform(Rect2(center - Vector2(24,24), Vector2(48,48)))
class FurnacePainter extends "res://Scripts/furnace_manager.gd":
	var recipes: Array[String]
	func _ready() -> void:
		rasterizing = true
		set_process(false)
		set_process_input(false)
	func _draw() -> void:
		for index in range(recipes.size()):
			var parts: PackedStringArray = recipes[index].split(":")
			if parts[0] != "furnace": continue
			draw_machine(Vector2(index % 8 * 64 + 32, index / 8 * 64 + 32), {"fuel": int(parts[2]) * 20, "direction": int(parts[1])})
class CompactorPainter extends "res://Scripts/compactor_manager.gd":
	var recipes: Array[String]
	func _ready() -> void:
		rasterizing = true
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
	func _draw() -> void:
		for index in range(recipes.size()):
			var parts: PackedStringArray = recipes[index].split(":")
			if parts[0] != "compactor": continue
			draw_machine(Vector2(index % 8 * 64 + 32, index / 8 * 64 + 32), {"count": 0, "kind": "", "direction": int(parts[1])})
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for direction in range(4):
		for progress in range(5): recipes.append("coal:%d:%d" % [direction, progress])
		for progress in range(7): recipes.append("copper:%d:%d" % [direction, progress])
		for shape in ["straight", "corner_right", "corner_left", "junction"]: recipes.append("belt:%s:%d" % [shape, direction])
		recipes.append("drill:%d" % direction)
		recipes.append("compactor:%d" % direction)
		for lit in range(2): recipes.append("furnace:%d:%d" % [direction, lit])
	for kind in preload("res://Scripts/mining_manager.gd").ORE_KINDS: recipes.append("ore:" + kind)
	recipes.append("platform")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, ceili(recipes.size() / 8.0) * 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	root.add_child(viewport)
	for artist in [Painter.new(), FurnacePainter.new(), CompactorPainter.new()]:
		artist.recipes = recipes
		artist.scale = Vector2(2,2)
		viewport.add_child(artist)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image.get_used_rect().size == Vector2i.ZERO:
		push_error("Atlas render is empty")
		quit(1)
		return
	var png: PackedByteArray = image.save_png_to_buffer()
	var source := "extends RefCounted\n\n# Generated from the game's vector artwork by tests/build_art_atlas.gd.\n# Shared 2x sprites avoid rebuilding hundreds of tiny shapes every frame.\nconst KEYS := " + JSON.stringify(recipes) + "\nconst PNG := \"" + Marshalls.raw_to_base64(png) + "\"\nstatic var texture: ImageTexture\nstatic var regions: Dictionary = {}\n\nstatic func prepare() -> bool:\n\tif texture == null:\n\t\tvar image := Image.new()\n\t\tif image.load_png_from_buffer(Marshalls.base64_to_raw(PNG)) != OK: return false\n\t\ttexture = ImageTexture.create_from_image(image)\n\t\tfor index in range(KEYS.size()): regions[KEYS[index]] = Rect2(index % 8 * 128, index / 8 * 128, 128, 128)\n\treturn true\n\nstatic func paint(canvas: Node2D, key: String, center: Vector2) -> bool:\n\tif not prepare() or not regions.has(key): return false\n\tcanvas.draw_texture_rect_region(texture, Rect2(center - Vector2(32,32), Vector2(64,64)), regions[key])\n\treturn true\n"
	FileAccess.open("res://Scripts/art_atlas.gd", FileAccess.WRITE).store_string(source)
	print("ATLAS: ", recipes.size(), " sprites; ", png.size(), " PNG bytes")
	viewport.queue_free()
	await process_frame
	quit()
