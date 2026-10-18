extends Node2D

signal reached_base
signal base_attacked(damage: float)
signal defeated

const MAX_HEALTH: float = 3.0
const MOVEMENT_SPEED: float = 35.0
const ATTACK_INTERVAL: float = 2.0
const ATTACK_DAMAGE: float = 1.0
const DISMEMBERMENT_CHANCE: float = 0.25

var health: float = MAX_HEALTH
var max_health: float = MAX_HEALTH
var destination: Vector2 = Vector2.ZERO
var walking_time: float = 0.0
var attacking: bool = false
var attack_timer: float = ATTACK_INTERVAL
var hit_flash: float = 0.0
var limbs: Array[String] = ["left_arm", "right_arm", "left_leg", "right_leg"]
var random := RandomNumberGenerator.new()

func setup(start_position: Vector2, target_position: Vector2, starting_health: float = MAX_HEALTH) -> void:
	position = start_position
	destination = target_position
	max_health = maxf(0.5, starting_health)
	health = max_health
	limbs.assign(["left_arm", "right_arm", "left_leg", "right_leg"])

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
	if health <= 0.0 or amount <= 0.0:
		return
	var received: float = minf(health, amount)
	health = maxf(0.0, health - amount)
	show_hit(received)
	if health <= 0.0:
		remove_from_group("zombies")
		set_process(false)
		defeated.emit()
		queue_free()
	else:
		queue_redraw()

func apply_damage(amount: float) -> void:
	take_damage(amount)

func show_hit(amount: float) -> void:
	if not is_inside_tree(): return
	var effect := HitEffect.new()
	effect.amount = amount
	if not limbs.is_empty() and random.randf() < DISMEMBERMENT_CHANCE:
		effect.limb = limbs.pop_at(random.randi_range(0, limbs.size() - 1))
		effect.limb_position = Vector2(-8 if effect.limb.begins_with("left") else 8, 12 if effect.limb.ends_with("arm") else 18)
		effect.velocity = Vector2(random.randf_range(-45, 45), -65)
		effect.spin = random.randf_range(-5, 5)
	# The effect belongs to the battlefield so fatal hits remain visible.
	get_parent().add_child(effect)
	effect.global_transform = global_transform
	effect.z_index = z_index + 1
	queue_redraw()

# All enemies share one small atlas, including every dismemberment/flash state.
# Bobbing changes the sprite transform, rather than tessellating circles each frame.
static var body_atlas: ImageTexture
const BODY_SIZE := Vector2i(64, 96)

static func paint_rect(image: Image, origin: Vector2i, rect: Rect2i, color: Color) -> void:
	image.fill_rect(Rect2i(origin + rect.position * 2, rect.size * 2), color)

static func paint_circle(image: Image, origin: Vector2i, center: Vector2, radius: float, color: Color) -> void:
	var at: Vector2 = Vector2(origin) + center * 2
	var r: float = radius * 2
	for y in range(floori(at.y - r), ceili(at.y + r)):
		for x in range(floori(at.x - r), ceili(at.x + r)):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(at) <= r * r:
				image.set_pixel(x, y, color)

static func get_body_atlas() -> ImageTexture:
	if body_atlas != null: return body_atlas
	var image := Image.create(BODY_SIZE.x * 8, BODY_SIZE.y * 4, false, Image.FORMAT_RGBA8)
	for state in range(32):
		var origin := Vector2i(state % 8, state / 8) * BODY_SIZE + Vector2i(32, 40)
		var arms := Color("#a9b86c") if state >= 16 else Color("#849c66")
		paint_circle(image, origin, Vector2(1, 11), 13, Color(0, 0, 0, 0.21))
		if state & 4: paint_rect(image, origin, Rect2i(-7, 14, 5, 9), Color("#556d43"))
		if state & 8: paint_rect(image, origin, Rect2i(2, 14, 5, 9), Color("#556d43"))
		paint_rect(image, origin, Rect2i(-8, 1, 16, 16), Color("#394b35"))
		if state & 1: paint_rect(image, origin, Rect2i(-11, 6, 6, 13), arms)
		if state & 2: paint_rect(image, origin, Rect2i(5, 6, 6, 13), arms)
		paint_circle(image, origin, Vector2(0, -6), 11, Color("#202e24"))
		paint_circle(image, origin, Vector2(0, -7), 9, Color("#8aab6a"))
		paint_rect(image, origin, Rect2i(-6, -9, 4, 3), Color("#ecde83"))
		paint_rect(image, origin, Rect2i(2, -9, 4, 3), Color("#ecde83"))
		paint_rect(image, origin, Rect2i(-3, -2, 6, 2), Color("#384b36"))
	body_atlas = ImageTexture.create_from_image(image)
	return body_atlas

func body_state() -> int:
	return (1 if "left_arm" in limbs else 0) | (2 if "right_arm" in limbs else 0) | (4 if "left_leg" in limbs else 0) | (8 if "right_leg" in limbs else 0) | (16 if hit_flash > 0 else 0)

func _draw() -> void:
	var state: int = body_state()
	var bob: float = 0.0 if attacking else sin(walking_time) * 1.5
	var source := Rect2(Vector2(Vector2i(state % 8, state / 8) * BODY_SIZE), Vector2(BODY_SIZE))
	draw_texture_rect_region(get_body_atlas(), Rect2(-16, -20 + bob, 32, 48), source)

class HitEffect extends Node2D:
	var amount: float
	var limb: String = ""
	var age: float = 0.0
	var velocity := Vector2.ZERO
	var limb_position := Vector2.ZERO
	var spin: float = 0.0
	var angle: float = 0.0

	func _process(delta: float) -> void:
		age += delta
		if age >= (1.0 if limb.is_empty() else 2.5):
			queue_free()
			return
		if not limb.is_empty():
			velocity.y += 180 * delta
			limb_position += velocity * delta
			angle += spin * delta
			if limb_position.y > 18:
				limb_position.y = 18
				velocity = Vector2.ZERO
				spin = 0.0
		queue_redraw()

	func _draw() -> void:
		if age < 1.0:
			var label: String = String.num(amount, 2).rstrip("0").rstrip(".")
			var font: Font = ThemeDB.fallback_font
			var at := Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.5, -27 - age * 30)
			var opacity: float = clampf((1.0 - age) * 3, 0, 1)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0.1, 0.08, 0.06, opacity))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.85, 0.55, opacity))
		if not limb.is_empty():
			draw_set_transform(limb_position, angle)
			var color := Color("#849c66") if limb.ends_with("arm") else Color("#556d43")
			color.a = clampf((2.5 - age) * 2, 0, 1)
			draw_rect(Rect2(Vector2(-3, -6), Vector2(6, 12)), color)
