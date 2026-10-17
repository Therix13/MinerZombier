extends Node2D

signal reached_base
signal base_attacked(damage: float)
signal defeated

const MAX_HEALTH: float = 3.0
const MOVEMENT_SPEED: float = 35.0
const ATTACK_INTERVAL: float = 2.0
const ATTACK_DAMAGE: float = 1.0

var health: float = MAX_HEALTH
var max_health: float = MAX_HEALTH
var destination: Vector2 = Vector2.ZERO
var walking_time: float = 0.0
var attacking: bool = false
var attack_timer: float = ATTACK_INTERVAL
var hit_flash: float = 0.0

func setup(start_position: Vector2, target_position: Vector2, starting_health: float = MAX_HEALTH) -> void:
	position = start_position
	destination = target_position
	max_health = maxf(0.5, starting_health)
	health = max_health

func _ready() -> void:
	add_to_group("zombies")
	queue_redraw()

func _process(delta: float) -> void:
	if attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_timer += ATTACK_INTERVAL
			hit_flash = 0.18
			base_attacked.emit(ATTACK_DAMAGE)
		if hit_flash > 0.0:
			hit_flash = maxf(0.0, hit_flash - delta)
			queue_redraw()
		return
	var remaining: Vector2 = destination - position
	var step: float = MOVEMENT_SPEED * delta
	if remaining.length_squared() <= step * step:
		position = destination
		attacking = true
		attack_timer = ATTACK_INTERVAL
		reached_base.emit()
	else:
		position += remaining.normalized() * step
		walking_time += delta * 8.0
	queue_redraw()

func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		remove_from_group("zombies")
		set_process(false)
		defeated.emit()
		queue_free()
	else:
		queue_redraw()

func apply_damage(amount: float) -> void:
	take_damage(amount)

func _draw() -> void:
	var bob: float = 0.0 if attacking else sin(walking_time) * 1.5
	var body_center := Vector2(0.0, bob)
	var arm_color := Color("#a9b86c") if hit_flash > 0.0 else Color("#849c66")
	draw_circle(body_center + Vector2(1.0, 11.0), 13.0, Color(0.0, 0.0, 0.0, 0.21))
	draw_rect(Rect2(Vector2(-8.0, 1.0 + bob), Vector2(16.0, 16.0)), Color("#394b35"))
	draw_rect(Rect2(Vector2(-11.0, 6.0 + bob), Vector2(6.0, 13.0)), arm_color)
	draw_rect(Rect2(Vector2(5.0, 6.0 + bob), Vector2(6.0, 13.0)), arm_color)
	draw_circle(body_center + Vector2(0.0, -6.0), 11.0, Color("#202e24"))
	draw_circle(body_center + Vector2(0.0, -7.0), 9.0, Color("#8aab6a"))
	draw_rect(Rect2(Vector2(-6.0, -9.0 + bob), Vector2(4.0, 3.0)), Color("#ecde83"))
	draw_rect(Rect2(Vector2(2.0, -9.0 + bob), Vector2(4.0, 3.0)), Color("#ecde83"))
	draw_line(Vector2(-3.0, -1.0 + bob), Vector2(3.0, -1.0 + bob), Color("#384b36"), 2.0)
	draw_rect(Rect2(Vector2(-15.0, -23.0), Vector2(30.0, 4.0)), Color("#351d1d"))
	draw_rect(Rect2(Vector2(-15.0, -23.0), Vector2(30.0 * health / max_health, 4.0)), Color("#c45143"))
