extends RefCounted

const VISIBLE_COLUMNS: float = 9.0
const ZOOM_STEP: float = 1.1
const DEFENSE_TOP: float = -640.0
const DEFENSE_HALF_WIDTH: float = 330.0
const DEFENSE_FOOTER: float = 64.0
const DEFENSE_LEFT_MARGIN: float = 340.0
const VIEW_CHANGE_DURATION: float = 0.65
const MINE_COMBAT_TOP: float = -144.0

var defense_view: bool = false
var mine_position: Vector2 = Vector2.ZERO
var mine_zoom: float = 1.0
var combat_mine_active: bool = false
var combat_mine_position: Vector2
var combat_mine_zoom: float = 1.0

var camera: Camera2D
var viewport: Viewport
var grid: RefCounted
var min_zoom: float = 1.0
var max_zoom: float = 1.0
var dragging: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO
var previous_viewport_size: Vector2 = Vector2.ZERO
var defense_mask: DefenseMask
var motion: ViewMotion
var transitioning: bool = false
var transition_time: float = 0.0
var from_position: Vector2
var to_position: Vector2
var from_zoom: float
var to_zoom: float
var from_cover: float = 0.0

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
	motion = ViewMotion.new()
	motion.name = "ViewMotion"
	motion.controller = self
	camera.add_child(motion)
	motion.set_process(false)
	var center_x: int = grid.MAP_WIDTH / 2
	camera.position = Vector2((center_x + 0.5) * grid.TILE_SIZE, grid.GRID_OFFSET_Y + grid.TILE_SIZE * 1.5)
	update_zoom_limits(true)
	viewport.size_changed.connect(update_zoom_limits)

func get_active_min_zoom() -> float:
	if not defense_view:
		return min_zoom
	return defense_zoom()

func bind_cycle(cycle: RefCounted) -> void:
	cycle.changed.connect(motion.on_cycle_changed)

func horde_active() -> bool:
	var cycle: RefCounted = camera.get_parent().get("cycle")
	return cycle != null and cycle.is_night and not cycle.defeated

func fit_combat_mine() -> void:
	var size: Vector2 = viewport.get_visible_rect().size
	var factor: float = camera.get_parent().get_node("CanvasLayer").scale.x
	var frame := Rect2(Vector2(DEFENSE_LEFT_MARGIN * factor, 100.0 * factor), Vector2(maxf(1, size.x - 2 * DEFENSE_LEFT_MARGIN * factor), maxf(1, size.y - 164.0 * factor)))
	var bottom: float = grid.GRID_OFFSET_Y + grid.cave_height * grid.TILE_SIZE
	var center_x: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var bounds := Rect2(center_x - grid.cave_width * grid.TILE_SIZE * 0.5, MINE_COMBAT_TOP, grid.cave_width * grid.TILE_SIZE, bottom - MINE_COMBAT_TOP)
	var zoom: float = clampf(minf(frame.size.x / bounds.size.x, frame.size.y / bounds.size.y), min_zoom, max_zoom)
	camera.zoom = Vector2.ONE * zoom
	camera.position = bounds.get_center() - (frame.get_center() - size * 0.5) / zoom

func on_cycle_changed() -> void:
	if horde_active() or not combat_mine_active: return
	combat_mine_active = false
	if not defense_view:
		stop_transition()
		camera.position = mine_position
		camera.zoom = Vector2.ONE * clampf(mine_zoom, min_zoom, max_zoom)
		clamp_position()

func defense_bounds() -> Rect2:
	# Fit the combat lanes, platforms, and entrance, rather than empty map edges.
	var center_x: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	return Rect2(center_x - DEFENSE_HALF_WIDTH, DEFENSE_TOP, DEFENSE_HALF_WIDTH * 2.0, grid.GRID_OFFSET_Y - DEFENSE_TOP)

func defense_frame() -> Rect2:
	var size: Vector2 = viewport.get_visible_rect().size
	var factor: float = size.x / 1280.0
	var ui: CanvasLayer = camera.get_parent().get_node_or_null("CanvasLayer") as CanvasLayer
	if ui != null:
		factor = ui.scale.x
	# Reserve the same width on both sides so combat stays centered on screen.
	var width: float = maxf(1.0, size.x - 2.0 * DEFENSE_LEFT_MARGIN * factor)
	return Rect2(Vector2((size.x - width) * 0.5, 0.0), Vector2(width, maxf(1.0, size.y - DEFENSE_FOOTER * factor)))

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
	defense_mask.modulate.a = 1.0
	defense_mask.show()
	refresh_framing()

func refresh_framing() -> void:
	var size: Vector2 = viewport.get_visible_rect().size
	var zoom: float = camera.zoom.x
	var bounds: Rect2 = defense_bounds()
	defense_mask.arena = bounds
	defense_mask.view_rect = Rect2(camera.position - size / (zoom * 2.0), size / zoom).grow(1.0 / zoom)
	defense_mask.queue_redraw()
	camera.force_update_scroll()
	var zone: Node2D = camera.get_parent().get("defense_zone") as Node2D
	if zone != null:
		zone.queue_redraw()

func update_zoom_limits(initial: bool = false) -> void:
	var was_transitioning: bool = transitioning
	stop_transition()
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	if not initial and previous_viewport_size.x > 0.0 and viewport_size.x != previous_viewport_size.x:
		var ratio: float = viewport_size.x / previous_viewport_size.x
		camera.zoom *= ratio
		mine_zoom *= ratio
		combat_mine_zoom *= ratio
	previous_viewport_size = viewport_size
	var map_size: Vector2 = grid.get_map_size()
	max_zoom = viewport_size.x / (VISIBLE_COLUMNS * grid.TILE_SIZE)
	min_zoom = maxf(viewport_size.x / map_size.x, viewport_size.y / map_size.y)
	max_zoom = maxf(max_zoom, min_zoom)
	var minimum: float = get_active_min_zoom()
	var maximum: float = maxf(max_zoom, minimum)
	var value: float = maximum if initial else clampf(camera.zoom.x, minimum, maximum)
	camera.zoom = Vector2.ONE * value
	if was_transitioning and not defense_view:
		camera.zoom = Vector2.ONE * clampf(combat_mine_zoom if combat_mine_active else mine_zoom, min_zoom, max_zoom)
		camera.position = combat_mine_position if combat_mine_active else mine_position
	if combat_mine_active and not defense_view and horde_active(): fit_combat_mine()
	clamp_position()

func clamp_position() -> void:
	if transitioning:
		return
	if defense_view:
		fit_defense_view()
		return
	defense_mask.hide()
	defense_mask.modulate.a = 0.0
	var size: Vector2 = grid.get_map_size()
	var half: Vector2 = viewport.get_visible_rect().size / (camera.zoom * 2.0)
	camera.position.x = size.x * 0.5 if half.x * 2.0 >= size.x else clampf(camera.position.x, half.x, size.x - half.x)
	var top: float = MINE_COMBAT_TOP - 160.0 if horde_active() else 0.0
	var bottom: float = size.y
	if half.y * 2.0 >= bottom - top:
		camera.position.y = (top + bottom) * 0.5
	else:
		camera.position.y = clampf(camera.position.y, top + half.y, bottom - half.y)
	refresh_framing()

func handle_button(event: InputEventMouseButton, blocked: bool) -> void:
	if blocked or defense_view or transitioning:
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
	if not dragging or transitioning:
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
	if defense_view or transitioning:
		return
	var minimum: float = get_active_min_zoom()
	var maximum: float = maxf(max_zoom, minimum)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, minimum, maximum)
	clamp_position()

func set_defense_view(enabled: bool) -> void:
	if enabled == defense_view:
		return
	dragging = false
	if enabled and not transitioning:
		if combat_mine_active:
			combat_mine_position = camera.position
			combat_mine_zoom = camera.zoom.x
		else:
			mine_position = camera.position
			mine_zoom = camera.zoom.x
	var start_position: Vector2 = camera.position
	var start_zoom: float = camera.zoom.x
	var start_cover: float = defense_mask.modulate.a if defense_mask.visible else 0.0
	stop_transition()
	defense_view = enabled
	if not defense_view:
		if horde_active():
			if not combat_mine_active:
				fit_combat_mine()
				combat_mine_active = true
			else:
				camera.zoom = Vector2.ONE * clampf(combat_mine_zoom, min_zoom, max_zoom)
				camera.position = combat_mine_position
			combat_mine_position = camera.position
			combat_mine_zoom = camera.zoom.x
		else:
			camera.zoom = Vector2.ONE * clampf(mine_zoom, min_zoom, max_zoom)
			camera.position = mine_position
	clamp_position()
	to_position = camera.position
	to_zoom = camera.zoom.x
	from_position = start_position
	from_zoom = start_zoom
	from_cover = start_cover
	camera.position = from_position
	camera.zoom = Vector2.ONE * from_zoom
	defense_mask.modulate.a = from_cover
	defense_mask.show()
	transition_time = 0.0
	transitioning = true
	var interactions: Node = camera.get_parent().get_node_or_null("WorldInteractions")
	if interactions != null:
		interactions.clear_drag()
	motion.set_process(true)
	refresh_framing()

func stop_transition() -> void:
	transitioning = false
	if is_instance_valid(motion):
		motion.set_process(false)

func advance_transition(delta: float) -> void:
	transition_time = minf(transition_time + delta, VIEW_CHANGE_DURATION)
	var progress: float = transition_time / VIEW_CHANGE_DURATION
	var eased: float = smoothstep(0.0, 1.0, progress)
	camera.position = from_position.lerp(to_position, eased)
	camera.zoom = Vector2.ONE * lerpf(from_zoom, to_zoom, eased)
	defense_mask.modulate.a = lerpf(from_cover, 1.0, smoothstep(0.75, 1.0, progress)) if defense_view else lerpf(from_cover, 0.0, smoothstep(0.0, 0.25, progress))
	refresh_framing()
	if progress >= 1.0:
		stop_transition()
		clamp_position()

class ViewMotion extends Node:
	var controller: RefCounted

	func on_cycle_changed() -> void:
		controller.on_cycle_changed()

	func _process(delta: float) -> void:
		controller.advance_transition(delta)

class DefenseMask extends Node2D:
	var arena: Rect2
	var view_rect: Rect2

	func _draw() -> void:
		# Hide only the mine; the battlefield continues behind the HUD.
		var mine := Rect2(Vector2(view_rect.position.x, arena.end.y), Vector2(view_rect.size.x, maxf(0.0, view_rect.end.y - arena.end.y)))
		if mine.has_area():
			draw_rect(mine, Color("#18252c"))
