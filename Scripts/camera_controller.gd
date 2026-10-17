extends RefCounted

const VISIBLE_COLUMNS: float = 9.0
const ZOOM_STEP: float = 1.1
const DEFENSE_TOP: float = -640.0
const DEFENSE_CENTER_Y: float = -225.0

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

func setup(target: Camera2D, source: Viewport, grid_manager: RefCounted) -> void:
	camera = target
	viewport = source
	grid = grid_manager
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	var center_x: int = grid.MAP_WIDTH / 2
	camera.position = Vector2((center_x + 0.5) * grid.TILE_SIZE, grid.GRID_OFFSET_Y + grid.TILE_SIZE * 1.5)
	update_zoom_limits(true)
	viewport.size_changed.connect(update_zoom_limits)

func get_active_min_zoom() -> float:
	if not defense_view:
		return min_zoom
	var available_height: float = grid.GRID_OFFSET_Y - DEFENSE_TOP
	var viewport_height: float = viewport.get_visible_rect().size.y
	return maxf(min_zoom, viewport_height / available_height)

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
	var size: Vector2 = grid.get_map_size()
	var half: Vector2 = viewport.get_visible_rect().size / (camera.zoom * 2.0)
	camera.position.x = size.x * 0.5 if half.x * 2.0 >= size.x else clampf(camera.position.x, half.x, size.x - half.x)
	var top: float = DEFENSE_TOP if defense_view else 0.0
	var bottom: float = grid.GRID_OFFSET_Y if defense_view else size.y
	if half.y * 2.0 >= bottom - top:
		camera.position.y = (top + bottom) * 0.5
	else:
		camera.position.y = clampf(camera.position.y, top + half.y, bottom - half.y)

func handle_button(event: InputEventMouseButton, blocked: bool) -> void:
	if blocked:
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
	if defense_view:
		var minimum: float = get_active_min_zoom()
		var maximum: float = maxf(max_zoom, minimum)
		var desired_zoom: float = viewport.get_visible_rect().size.y / (grid.GRID_OFFSET_Y - DEFENSE_TOP)
		camera.zoom = Vector2.ONE * clampf(desired_zoom, minimum, maximum)
		camera.position = Vector2(grid.MAP_WIDTH * grid.TILE_SIZE * 0.5, DEFENSE_CENTER_Y)
	else:
		camera.zoom = Vector2.ONE * clampf(mine_zoom, min_zoom, max_zoom)
		camera.position = mine_position
	clamp_position()
