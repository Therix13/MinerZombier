extends Node2D

signal base_health_changed(health: float, max_health: float)
signal wave_completed
signal base_destroyed
signal zombie_defeated

const ZombieScript = preload("res://Scripts/zombie.gd")
const SPAWN_INTERVAL: float = 5.0
const MAX_ZOMBIES: int = 64
const FIRST_WAVE_ZOMBIES: int = 24
const EXTRA_ZOMBIES_PER_DAY: int = 8
const MAX_WAVE_ZOMBIES: int = 160
const HORDE_DURATION: float = 120.0
const SPAWN_WINDOW: float = 90.0
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

var wave_elapsed: float = 0.0
var retreat_started: bool = false
var acid_shots: Array[Dictionary] = []
var acid_pools: Array[Dictionary] = []

func living_zombies() -> Array[Node]:
	var result: Array[Node] = []
	for enemy: Node in get_tree().get_nodes_in_group("zombies"):
		if is_ancestor_of(enemy) and not enemy.is_queued_for_deletion(): result.append(enemy)
	return result

func spawn_interval() -> float:
	return SPAWN_WINDOW / float(maxi(1,wave_total - 1))

func wave_size(day: int) -> int:
	return mini(MAX_WAVE_ZOMBIES,FIRST_WAVE_ZOMBIES + maxi(0,day - 1) * EXTRA_ZOMBIES_PER_DAY)

func archetype_for(day: int, index: int, total: int) -> String:
	if day >= 5 and day % 5 == 0 and (index == 0 or (day >= 10 and index % 12 == 0)): return "plague"
	if day >= 3 and day % 3 == 0 and index == total / 2: return "brute"
	if day >= 8 and index % 8 == 6: return "brute"
	if day >= 6 and index % 7 == 4: return "bomber"
	if day >= 4 and index % 4 == 3: return "spitter"
	if day >= 3 and index % 3 == 2: return "armored"
	if day >= 2 and index % 3 == 1: return "runner"
	return "walker"

func remaining_time() -> float:
	return maxf(0,HORDE_DURATION - wave_elapsed)

func announcement() -> String:
	if wave_elapsed >= HORDE_DURATION: return "Elimina los zombis restantes para terminar la noche"
	if wave_day >= 5 and wave_day % 5 == 0: return "Jefe: Rey de la Plaga · Ataca cuando baje el escudo"
	if wave_day >= 3 and wave_day % 3 == 0: return "Minijefe: Demoledor · Vulnerable tras cargar"
	if wave_day >= 6: return "Explosivos · Elimínalos antes de que detonen"
	if wave_day >= 4: return "Escupidores · Interrumpe su ataque de ácido"
	if wave_day >= 3: return "Blindados · Rompe su armadura"
	if wave_day >= 2: return "Corredores · Mantén las armas cargadas"
	return "Sobrevive hasta el amanecer"

func setup(grid_manager: RefCounted) -> void:
	# Warm the shared artwork during loading, before the first wave.
	ZombieScript.get_body_atlas()
	grid = grid_manager
	base_health = BASE_MAX_HEALTH
	queue_redraw()

func start_wave(day: int) -> void:
	if active_wave or grid == null: return
	wave_day = day
	wave_total = wave_size(day)
	spawn_count = 0
	spawn_from_left = true
	wave_elapsed = 0.0
	retreat_started = false
	spawn_timer = spawn_interval()
	cleared_time = 0.0
	acid_shots.clear()
	acid_pools.clear()
	active_wave = true
	spawn_zombie()

func _process(delta: float) -> void:
	if not active_wave: return
	wave_elapsed = minf(HORDE_DURATION,wave_elapsed + maxf(0,delta))
	advance_acid(delta)
	if not active_wave: return
	if spawn_count < wave_total:
		spawn_timer -= maxf(0,delta)
		if spawn_timer <= 0 and living_zombies().size() < MAX_ZOMBIES:
			spawn_timer += spawn_interval()
			spawn_zombie()
	if living_zombies().is_empty(): cleared_time = minf(WAVE_END_DELAY,cleared_time + delta)
	else: cleared_time = 0.0
	# Sunrise never removes living enemies. Finish only after the complete horde dies.
	if wave_elapsed >= HORDE_DURATION and spawn_count >= wave_total and living_zombies().is_empty():
		active_wave = false
		acid_shots.clear()
		acid_pools.clear()
		cleared_time = 0.0
		wave_completed.emit()

func connect_zombie(zombie: Node) -> void:
	zombie.base_attacked.connect(_on_base_attacked)
	zombie.defeated.connect(zombie_defeated.emit)
	zombie.acid_spit.connect(launch_acid)

func spawn_zombie() -> void:
	if not active_wave or spawn_count >= wave_total: return
	if living_zombies().size() >= MAX_ZOMBIES: return
	var center_x: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var side: float = -1.0 if spawn_from_left else 1.0
	var lane: float = float(spawn_count % 3) * 30.0
	var zombie: Node2D = ZombieScript.new()
	zombie.z_index = 20
	zombie.setup(Vector2(center_x + side * (SPAWN_DISTANCE + lane),SPAWN_HEIGHT),Vector2(center_x + side * (45.0 + lane),ATTACK_LINE_Y))
	zombie.configure(archetype_for(wave_day,spawn_count,wave_total))
	connect_zombie(zombie)
	add_child(zombie)
	spawn_count += 1
	spawn_from_left = not spawn_from_left

func launch_acid(origin: Vector2, damage: float, volley: int) -> void:
	if not active_wave: return
	var target: Vector2 = grid.get_cell_rect(grid.sale_cell).get_center()
	for i in range(volley):
		if acid_shots.size() >= 32: break
		acid_shots.append({"from":origin,"to":target + Vector2((i - (volley - 1) * 0.5) * 16,0),"age":0.0,"duration":1.2 + i * 0.2,"damage":damage})
	queue_redraw()

func advance_acid(delta: float) -> void:
	var visual: bool = not acid_shots.is_empty() or not acid_pools.is_empty()
	for i in range(acid_pools.size() - 1,-1,-1):
		var pool: Dictionary = acid_pools[i]
		var active_delta: float = minf(delta,float(pool["remaining"]))
		pool["remaining"] -= active_delta
		pool["tick"] -= active_delta
		while pool["tick"] <= 0:
			pool["tick"] += 1.0
			_on_base_attacked(0.5)
			if not active_wave: return
		if pool["remaining"] <= 0: acid_pools.remove_at(i)
	for i in range(acid_shots.size() - 1,-1,-1):
		var shot: Dictionary = acid_shots[i]
		shot["age"] += delta
		if shot["age"] < shot["duration"]: continue
		acid_shots.remove_at(i)
		_on_base_attacked(float(shot["damage"]))
		if not active_wave: return
		if acid_pools.size() < 8: acid_pools.append({"position":shot["to"],"remaining":4.0,"tick":1.0})
	if visual: queue_redraw()

func _on_base_attacked(damage: float) -> void:
	if not active_wave or base_health <= 0.0:
		return
	base_health = maxf(0.0, base_health - damage)
	base_health_changed.emit(base_health, BASE_MAX_HEALTH)
	queue_redraw()
	if base_health <= 0.0:
		active_wave = false
		acid_shots.clear()
		acid_pools.clear()
		for enemy: Node in living_zombies(): enemy.set_process(false)
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
	draw_string(ThemeDB.fallback_font, Vector2(center_x - 24.0, center_y - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e8d6b1"))

	for shot: Dictionary in acid_shots:
		var t: float = clampf(float(shot["age"]) / float(shot["duration"]),0,1)
		var at: Vector2 = (shot["from"] as Vector2).lerp(shot["to"],t) + Vector2(0,-sin(t * PI) * 75)
		draw_circle(shot["to"],14,Color(0.6,0.85,0.2,0.16))
		draw_arc(shot["to"],14,0,TAU,16,Color("#c1df65"),1.0)
		draw_circle(at,5,Color("#a8d74c"))
		draw_circle(at + Vector2(-1,-1),2,Color("#e6f599"))
	for pool: Dictionary in acid_pools:
		draw_circle(pool["position"],17,Color(0.4,0.65,0.1,0.4 * float(pool["remaining"]) / 4.0))
