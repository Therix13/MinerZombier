extends Node2D

signal base_health_changed(health: float, max_health: float)
signal wave_completed
signal base_destroyed
signal zombie_defeated

const ZombieScript = preload("res://Scripts/zombie.gd")
const SPAWN_INTERVAL: float = 5.0
const MAX_ZOMBIES: int = 12
const SPAWN_DISTANCE: float = 225.0
const SPAWN_HEIGHT: float = -590.0
const ATTACK_LINE_Y: float = -28.0
const BASE_MAX_HEALTH: float = 100.0
const WAVE_END_DELAY: float = 3.0

var grid: RefCounted
var spawn_timer: float = 0.0
var spawn_from_left: bool = true
var spawn_count: int = 0
var wave_total: int = 0
var wave_day: int = 1
var active_wave: bool = false
var base_health: float = BASE_MAX_HEALTH
var cleared_time: float = 0.0

func setup(grid_manager: RefCounted) -> void:
	grid = grid_manager
	base_health = BASE_MAX_HEALTH
	queue_redraw()

func start_wave(day: int) -> void:
	if active_wave or grid == null:
		return
	wave_day = day
	wave_total = 2 if day == 1 else (3 if day == 2 else (2 if day == 3 else mini(12, day + 1)))
	spawn_count = 0
	spawn_from_left = true
	spawn_timer = SPAWN_INTERVAL
	cleared_time = 0.0
	active_wave = true
	spawn_zombie()

func _process(delta: float) -> void:
	if not active_wave:
		return
	if spawn_count < wave_total:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and get_tree().get_nodes_in_group("zombies").size() < MAX_ZOMBIES:
			spawn_timer = SPAWN_INTERVAL
			spawn_zombie()
	if spawn_count >= wave_total and get_tree().get_nodes_in_group("zombies").is_empty():
		cleared_time += delta
		if cleared_time >= WAVE_END_DELAY:
			active_wave = false
			cleared_time = 0.0
			wave_completed.emit()
	else:
		cleared_time = 0.0

func spawn_zombie() -> void:
	if not active_wave or spawn_count >= wave_total:
		return
	var center_x: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var side: float = -1.0 if spawn_from_left else 1.0
	var lane: float = float(spawn_count % 3) * 30.0
	var start_position := Vector2(center_x + side * (SPAWN_DISTANCE + lane), SPAWN_HEIGHT)
	var target_position := Vector2(center_x + side * (45.0 + lane), ATTACK_LINE_Y)
	var health: float = 1.0 if wave_day <= 2 else 3.0 + float(maxi(0, wave_day - 4))
	var zombie: Node2D = ZombieScript.new()
	zombie.z_index = 20
	zombie.call("setup", start_position, target_position, health)
	zombie.connect("base_attacked", _on_base_attacked)
	zombie.connect("defeated", zombie_defeated.emit)
	add_child(zombie)
	spawn_count += 1
	spawn_from_left = not spawn_from_left

func _on_base_attacked(damage: float) -> void:
	if not active_wave or base_health <= 0.0:
		return
	base_health = maxf(0.0, base_health - damage)
	base_health_changed.emit(base_health, BASE_MAX_HEALTH)
	queue_redraw()
	if base_health <= 0.0:
		active_wave = false
		base_destroyed.emit()

func _draw() -> void:
	if grid == null:
		return
	var center_x: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var center_y: float = grid.GRID_OFFSET_Y - 81.0
	var outer := Rect2(Vector2(center_x - 65.0, center_y), Vector2(130.0, 18.0))
	draw_rect(outer, Color("#33271e"))
	draw_rect(outer.grow(-3.0), Color("#803b36"))
	var fill_width: float = 124.0 * base_health / BASE_MAX_HEALTH
	if fill_width > 0.0:
		draw_rect(Rect2(outer.position + Vector2(3.0, 3.0), Vector2(fill_width, 12.0)), Color("#8cb46e"))
	draw_rect(outer, Color("#c49a5e"), false, 2.0)
	var label: String = str(int(base_health)) + " / " + str(int(BASE_MAX_HEALTH))
	draw_string(ThemeDB.fallback_font, Vector2(center_x - 24.0, center_y - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#553623"))
