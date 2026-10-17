extends Node2D

const ZONE_TOP: float = -640.0
const ZONE_BOTTOM: float = 0.0

var grid: RefCounted
var is_night: bool = false

func setup(grid_manager: RefCounted) -> void:
	grid = grid_manager
	queue_redraw()

func set_night(enabled: bool) -> void:
	if is_night != enabled:
		is_night = enabled
		queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	var width: float = float(grid.MAP_WIDTH * grid.TILE_SIZE)
	draw_rect(Rect2(0.0, ZONE_TOP, width, -ZONE_TOP), Color("#192c3f") if is_night else Color("#42604b"))
	var center_x: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var path := PackedVector2Array([
		Vector2(center_x - 285.0, ZONE_TOP),
		Vector2(center_x + 285.0, ZONE_TOP),
		Vector2(center_x + 125.0, ZONE_BOTTOM),
		Vector2(center_x - 125.0, ZONE_BOTTOM)
	])
	draw_colored_polygon(path, Color("#353b4b") if is_night else Color("#766c50"))
	for y in range(int(ZONE_TOP), 0, 48):
		draw_line(Vector2(0.0, float(y)), Vector2(width, float(y)), Color("#31465a", 0.35) if is_night else Color("#55735b", 0.35), 1.0)
	draw_line(Vector2(0.0, 0.0), Vector2(width, 0.0), Color("#8b7eae") if is_night else Color("#b19055"), 3.0)
