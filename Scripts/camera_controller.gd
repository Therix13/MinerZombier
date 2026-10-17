extends RefCounted

const VISIBLE_COLUMNS: float = 9.0
const ZOOM_STEP: float = 1.1
const DEFENSE_TOP: float = -640.0
const DEFENSE_HEADER: float = 84.0
const DEFENSE_FOOTER: float = 64.0
const DEFENSE_LEFT_MARGIN: float = 340.0
const DEFENSE_RIGHT_MARGIN: float = 20.0

var defense_view: bool = false
var mine_position: Vector2 = Vector2.ZERO
var mine_zoom: float = 1.0

var camera: Camera2D
var viewport: Viewport
var grid: RefCounted
var min_zoom: float = 1.0
var max_zoom: float = 1.0
var dragging: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO
var previous_viewport_size: Vector2 = Vector2.ZERO
var defense_mask: DefenseMask

func setup(target: Camera2D, source: Viewport, grid_manager: RefCounted) -> void:
	camera = target
	viewport = source
	grid = grid_manager
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	defense_mask = DefenseMask.new()
	defense_mask.name = "DefenseFramingMask"
	defense_mask.top_level = true
	defense_mask.z_index = 4000
	defense_mask.hide()
	camera.add_child(defense_mask)
	defense_mask.global_transform = Transform2D.IDENTITY
	var center_x: int = grid.MAP_WIDTH / 2
	camera.position = Vector2((center_x + 0.5) * grid.TILE_SIZE, grid.GRID_OFFSET_Y + grid.TILE_SIZE * 1.5)
	update_zoom_limits(true)
	viewport.size_changed.connect(update_zoom_limits)

func get_active_min_zoom() -> float:
	if not defense_view:
		return min_zoom
	return defense_zoom()

func defense_bounds() -> Rect2:
	# Include the spawn area, platforms, ammunition connections, and base.
	# The first mining row starts exactly at GRID_OFFSET_Y.
	return Rect2(0.0, DEFENSE_TOP, grid.MAP_WIDTH * grid.TILE_SIZE, grid.GRID_OFFSET_Y - DEFENSE_TOP)

func defense_frame() -> Rect2:
	var size: Vector2 = viewport.get_visible_rect().size
	var factor: float = size.x / 1280.0
	var ui: CanvasLayer = camera.get_parent().get_node_or_null("CanvasLayer") as CanvasLayer
	if ui != null:
		factor = ui.scale.x
	return Rect2(Vector2(DEFENSE_LEFT_MARGIN, DEFENSE_HEADER) * factor, Vector2(maxf(1.0, size.x - (DEFENSE_LEFT_MARGIN + DEFENSE_RIGHT_MARGIN) * factor), maxf(1.0, size.y - (DEFENSE_HEADER + DEFENSE_FOOTER) * factor)))

func defense_zoom() -> float:
	var frame: Rect2 = defense_frame()
	var bounds: Rect2 = defense_bounds()
	return maxf(0.001, minf(frame.size.x / bounds.size.x, frame.size.y / bounds.size.y))

func fit_defense_view() -> void:
	var size: Vector2 = viewport.get_visible_rect().size
	var zoom: float = defense_zoom()
	var bounds: Rect2 = defense_bounds()
	camera.zoom = Vector2.ONE * zoom
	camera.position = bounds.get_center() - (defense_frame().get_center() - size * 0.5) / zoom
	dragging = false
	defense_mask.arena = bounds
	defense_mask.view_rect = Rect2(camera.position - size / (zoom * 2.0), size / zoom).grow(1.0 / zoom)
	defense_mask.show()
	defense_mask.queue_redraw()
	camera.force_update_scroll()

func update_zoom_limits(initial: bool = false) -> void:
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	if not initial and previous_viewport_size.x > 0.0 and viewport_size.x != previous_viewport_size.x:
		var ratio: float = viewport_size.x / previous_viewport_size.x
		camera.zoom *= ratio
		mine_zoom *= ratio
	previous_viewport_size = viewport_size
	var map_size: Vector2 = grid.get_map_size()
	max_zoom = viewport_size.x / (VISIBLE_COLUMNS * grid.TILE_SIZE)
	min_zoom = maxf(viewport_size.x / map_size.x, viewport_size.y / map_size.y)
	max_zoom = maxf(max_zoom, min_zoom)
	var minimum: float = get_active_min_zoom()
	var maximum: float = maxf(max_zoom, minimum)
	var value: float = maximum if initial else clampf(camera.zoom.x, minimum, maximum)
	camera.zoom = Vector2.ONE * value
	clamp_position()

func clamp_position() -> void:
	if defense_view:
		fit_defense_view()
		return
	defense_mask.hide()
	var size: Vector2 = grid.get_map_size()
	var half: Vector2 = viewport.get_visible_rect().size / (camera.zoom * 2.0)
	camera.position.x = size.x * 0.5 if half.x * 2.0 >= size.x else clampf(camera.position.x, half.x, size.x - half.x)
	var top: float = 0.0
	var bottom: float = size.y
	if half.y * 2.0 >= bottom - top:
		camera.position.y = (top + bottom) * 0.5
	else:
		camera.position.y = clampf(camera.position.y, top + half.y, bottom - half.y)

func handle_button(event: InputEventMouseButton, blocked: bool) -> void:
	if blocked or defense_view:
		dragging = false
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
		if dragging:
			last_mouse_position = event.position
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		change_zoom(ZOOM_STEP)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		change_zoom(1.0 / ZOOM_STEP)

func update() -> void:
	if not dragging:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		dragging = false
		return
	var position: Vector2 = viewport.get_mouse_position()
	var movement: Vector2 = position - last_mouse_position
	if movement.length_squared() > 0.0:
		camera.position -= movement / camera.zoom
		clamp_position()
	last_mouse_position = position

func change_zoom(factor: float) -> void:
	if defense_view:
		return
	var minimum: float = get_active_min_zoom()
	var maximum: float = maxf(max_zoom, minimum)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, minimum, maximum)
	clamp_position()

func set_defense_view(enabled: bool) -> void:
	if enabled == defense_view:
		return
	dragging = false
	if enabled:
		mine_position = camera.position
		mine_zoom = camera.zoom.x
	defense_view = enabled
	if not defense_view:
		camera.zoom = Vector2.ONE * clampf(mine_zoom, min_zoom, max_zoom)
		camera.position = mine_position
	clamp_position()

class DefenseMask extends Node2D:
	var arena: Rect2
	var view_rect: Rect2

	func _draw() -> void:
		# Cover the mine and unused margins in world space, below the HUD.
		var color := Color("#18252c")
		var areas: Array[Rect2] = [
			Rect2(view_rect.position, Vector2(view_rect.size.x, maxf(0.0, arena.position.y - view_rect.position.y))),
			Rect2(Vector2(view_rect.position.x, arena.end.y), Vector2(view_rect.size.x, maxf(0.0, view_rect.end.y - arena.end.y))),
			Rect2(Vector2(view_rect.position.x, arena.position.y), Vector2(maxf(0.0, arena.position.x - view_rect.position.x), arena.size.y)),
			Rect2(Vector2(arena.end.x, arena.position.y), Vector2(maxf(0.0, view_rect.end.x - arena.end.x), arena.size.y)),
		]
		for area in areas:
			if area.has_area():
				draw_rect(area, color)
