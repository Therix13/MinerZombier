extends RefCounted

static func draw(canvas: CanvasItem, center: Vector2, direction: int) -> void:
	preload("res://Scripts/content_art.gd").machine(canvas,center,"filter",direction)
