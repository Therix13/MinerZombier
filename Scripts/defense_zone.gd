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
	var visible: Rect2 = get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var left: float = minf(0.0, visible.position.x)
	var right: float = maxf(width, visible.end.x)
	var top: float = minf(ZONE_TOP, visible.position.y)
	# Continue the scenery to the screen edges, including behind the HUD.
	draw_rect(Rect2(left, top, right - left, -top), Color("#192c3f") if is_night else Color("#42604b"))
	draw_rect(Rect2(left, ZONE_BOTTOM, right - left, grid.GRID_OFFSET_Y), Color.WHITE)
	var center_x: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var path := PackedVector2Array([
		Vector2(center_x - 285.0, ZONE_TOP),
		Vector2(center_x + 285.0, ZONE_TOP),
		Vector2(center_x + 125.0, ZONE_BOTTOM),
		Vector2(center_x - 125.0, ZONE_BOTTOM)
	])
	draw_colored_polygon(path, Color("#353b4b") if is_night else Color("#766c50"))
	for y in range(int(ZONE_TOP) - ceili(maxf(0.0, ZONE_TOP - top) / 48.0) * 48, 0, 48):
		draw_line(Vector2(left, float(y)), Vector2(right, float(y)), Color("#31465a", 0.35) if is_night else Color("#55735b", 0.35), 1.0)
	draw_line(Vector2(left, 0.0), Vector2(right, 0.0), Color("#8b7eae") if is_night else Color("#b19055"), 3.0)
