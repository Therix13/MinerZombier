extends Node2D

signal reached_base
signal base_attacked(damage: float)
signal defeated

const MAX_HEALTH: float = 3.0
const MOVEMENT_SPEED: float = 35.0
const ATTACK_INTERVAL: float = 2.0
const ATTACK_DAMAGE: float = 1.0
const DISMEMBERMENT_CHANCE: float = 0.25

const TYPES := {
	"walker": {"name":"Zombi", "health":1.0, "speed":24.0, "armor":0.0, "damage":1.0},
	"runner": {"name":"Corredor", "health":1.0, "speed":55.0, "armor":0.0, "damage":1.0},
	"armored": {"name":"Blindado", "health":2.0, "speed":19.0, "armor":1.5, "damage":1.0},
	"spitter": {"name":"Escupidor", "health":2.0, "speed":27.0, "armor":0.0, "damage":3.0},
	"brute": {"name":"DEMOLEDOR", "health":6.0, "speed":20.0, "armor":2.0, "damage":2.0},
	"plague": {"name":"REY DE LA PLAGA", "health":10.0, "speed":17.0, "armor":0.0, "damage":2.0},
	"bomber": {"name":"Explosivo", "health":2.0, "speed":35.0, "armor":0.0, "damage":6.0},
	"crawler": {"name":"Rastrero","health":0.6,"speed":44,"armor":0,"damage":0.4,"behavior":"walker"},
	"stalker": {"name":"Acechador","health":2.5,"speed":38,"armor":0,"damage":1.5,"behavior":"walker"},
	"dodger": {"name":"Esquivo","health":2,"speed":46,"armor":0,"damage":1,"behavior":"walker"},
	"shielder": {"name":"Portaescudo","health":4,"speed":18,"armor":3,"damage":1,"behavior":"walker"},
	"healer": {"name":"Contagiador","health":3,"speed":21,"armor":0,"damage":1,"behavior":"walker"},
	"swarm": {"name":"Colmena","health":3,"speed":22,"armor":0,"damage":1,"behavior":"walker"},
	"sapper": {"name":"Saboteador","health":3,"speed":33,"armor":0,"damage":2,"behavior":"spitter"},
	"berserker": {"name":"Furioso","health":5,"speed":29,"armor":1,"damage":2,"behavior":"brute"},
	"warden": {"name":"EL CARCELERO","health":24,"speed":18,"armor":6,"damage":3,"behavior":"brute"},
	"broodmother": {"name":"MADRE DE LA COLMENA","health":24,"speed":16,"armor":0,"damage":2,"behavior":"plague"},
	"executor": {"name":"EL EJECUTOR","health":40,"speed":19,"armor":5,"damage":4,"behavior":"brute"},
}
signal minions_requested(origin: Vector2, count: int)
signal sabotage
var status: Dictionary = {"slow":0.0,"support":0.0,"hits":0}

signal acid_spit(origin: Vector2, damage: float, volley: int)
var focused: bool = false
var archetype: String = "walker"
var armor: float = 0.0
var phase: String = "advance"
var ability_timer: float = 0.0
var charge_used: bool = false
var retreating: bool = false

var health: float = MAX_HEALTH
var max_health: float = MAX_HEALTH
var destination: Vector2 = Vector2.ZERO
var walking_time: float = 0.0
var attacking: bool = false
var attack_timer: float = ATTACK_INTERVAL
var hit_flash: float = 0.0
var limbs: Array[String] = ["left_arm", "right_arm", "left_leg", "right_leg"]
var random := RandomNumberGenerator.new()
var body_sprite: Sprite2D
var last_body_state := -1

func setup(start_position: Vector2, target_position: Vector2, starting_health: float = MAX_HEALTH) -> void:
	position = start_position
	destination = target_position
	max_health = maxf(0.5, starting_health)
	health = max_health
	limbs.assign(["left_arm", "right_arm", "left_leg", "right_leg"])

func configure(kind: String) -> void:
	archetype = kind if TYPES.has(kind) else "walker"
	var stats: Dictionary = TYPES[archetype]
	max_health = stats["health"]
	health = max_health
	armor = stats["armor"]
	if behavior() == "brute": scale = Vector2.ONE * 1.35
	elif behavior() == "plague": scale = Vector2.ONE * 1.55
	if archetype == "executor": scale = Vector2.ONE * 1.7

func behavior() -> String:
	return str(TYPES[archetype].get("behavior",archetype))

func apply_slow(seconds: float) -> void:
	status["slow"] = maxf(float(status.get("slow",0)),seconds)

func depart() -> void:
	remove_from_group("zombies")
	set_process(false)
	queue_free()


func _ready() -> void:
	add_to_group("zombies")
	create_body_sprite()
	update_visual()

func _process(delta: float) -> void:
	status["slow"] = maxf(0,float(status.get("slow",0)) - delta)
	advance_support(delta)
	hit_flash = maxf(0,hit_flash - delta)
	if phase == "windup":
		ability_timer = maxf(0,ability_timer - delta)
		queue_redraw()
		if ability_timer <= 0:
			if behavior() == "brute":
				phase = "charge"
			elif behavior() == "bomber":
				base_attacked.emit(float(TYPES[archetype]["damage"]))
				depart()
				return
			else:
				if archetype == "broodmother": minions_requested.emit(position,2)
				if archetype == "sapper": sabotage.emit()
				acid_spit.emit(position,float(TYPES[archetype]["damage"]),3 if behavior() == "plague" else 1)
				phase = "exposed"
				ability_timer = 5.0 if behavior() == "plague" else 1.0
		update_visual()
		return
	if phase == "exposed":
		ability_timer = maxf(0,ability_timer - delta)
		if ability_timer <= 0:
			phase = "advance"
			if archetype in ["warden","executor","berserker"]: charge_used = false
			attack_timer = 6.0 if behavior() in ["spitter","plague"] else ATTACK_INTERVAL
			queue_redraw()
		update_visual()
		return
	if behavior() == "brute" and not charge_used and position.y >= -160:
		charge_used = true
		phase = "windup"
		ability_timer = 1.5
		queue_redraw()
		return
	if behavior() == "bomber" and position.y >= -60:
		phase = "windup"
		ability_timer = 2.0
		queue_redraw()
		return
	if behavior() in ["spitter","plague"] and position.y >= (-100.0 if behavior() == "plague" else -120.0): attacking = true
	if attacking:
		attack_timer -= delta
		if attack_timer <= 0:
			if behavior() in ["spitter","plague"]:
				phase = "windup"
				ability_timer = 2.0 if behavior() == "plague" else 1.0
				queue_redraw()
			else:
				attack_timer += ATTACK_INTERVAL
				hit_flash = 0.18
				base_attacked.emit(float(TYPES[archetype]["damage"]))
		update_visual()
		return
	var remaining: Vector2 = destination - position
	var speed: float = 150.0 if phase == "charge" else float(TYPES[archetype]["speed"])
	if float(status.get("slow",0)) > 0: speed *= 0.5
	if status.get("frenzy",false): speed *= 1.2
	if archetype in ["berserker","executor"] and health < max_health * 0.5: speed *= 1.4
	var step: float = speed * delta
	if remaining.length_squared() <= step * step:
		position = destination
		attacking = true
		attack_timer = ATTACK_INTERVAL
		if phase == "charge":
			base_attacked.emit(8.0)
			phase = "exposed"
			ability_timer = 4.0
			queue_redraw()
		reached_base.emit()
	else:
		position += remaining.normalized() * step
		walking_time += delta * 8.0
	update_visual()

func advance_support(delta: float) -> void:
	if archetype not in ["healer","shielder"]: return
	status["support"] = float(status.get("support",0)) - delta
	if float(status["support"]) > 0: return
	status["support"] = 3.0
	for ally: Node2D in get_parent().living_zombies():
		if ally == self or ally.position.distance_squared_to(position) > 10000: continue
		if archetype == "healer": ally.health = minf(ally.max_health,ally.health + 0.4)
		else: ally.armor = minf(3,ally.armor + 0.3)
		ally.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed or retreating: return
	if get_global_mouse_position().distance_to(global_position) > 22.0 * scale.x: return
	var world: Node = get_parent().get_parent()
	if world.get("cycle") == null or not world.cycle.is_night: return
	world.launchers.focus(self)
	get_viewport().set_input_as_handled()

func take_damage(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	status["hits"] = int(status.get("hits",0)) + 1
	if archetype == "stalker" and position.y < -180: amount *= 0.35
	if archetype == "dodger" and int(status["hits"]) % 3 == 0 and phase != "exposed": amount *= 0.3
	if phase == "exposed": amount *= 2.0
	elif behavior() == "plague": amount *= 0.3
	if armor > 0 and phase != "exposed":
		var absorbed: float = minf(armor,amount)
		armor -= absorbed
		amount -= absorbed
		queue_redraw()
		if amount <= 0:
			hit_flash = 0.1
			update_visual()
			return
	var received: float = minf(health, amount)
	health = maxf(0.0, health - amount)
	queue_redraw()
	show_hit(received)
	if health <= 0.0:
		remove_from_group("zombies")
		set_process(false)
		if archetype == "swarm": minions_requested.emit(position,2)
		defeated.emit()
		queue_free()
	else:
		update_visual()

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
	update_visual()

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
	var image := Image.create(BODY_SIZE.x * 8, BODY_SIZE.y * 16, false, Image.FORMAT_RGBA8)
	for state in range(128):
		var origin := Vector2i(state % 8, state / 8) * BODY_SIZE + Vector2i(32, 40)
		var stride: int = [-2,0,2,0][int(state / 32)]
		var arms := Color("#a9b86c") if state % 32 >= 16 else Color("#849c66")
		paint_circle(image, origin, Vector2(1, 11), 13, Color(0, 0, 0, 0.21))
		if state & 4: paint_rect(image, origin, Rect2i(-7, 14 + stride, 5, 9), Color("#556d43"))
		if state & 8: paint_rect(image, origin, Rect2i(2, 14 - stride, 5, 9), Color("#556d43"))
		paint_rect(image, origin, Rect2i(-8, 1, 16, 16), Color("#394b35"))
		if state & 1: paint_rect(image, origin, Rect2i(-11, 6, 6, 13), arms)
		if state & 2: paint_rect(image, origin, Rect2i(5, 6, 6, 13), arms)
		paint_circle(image, origin, Vector2(0, -6), 11, Color("#202e24"))
		paint_circle(image, origin, Vector2(0, -7), 9, Color("#8aab6a"))
		paint_rect(image, origin, Rect2i(-6, -9, 4, 3), Color("#ecde83"))
		paint_rect(image, origin, Rect2i(2, -9, 4, 3), Color("#ecde83"))
		paint_rect(image, origin, Rect2i(-3, -2, 6, 2), Color("#384b36"))
		# Pixel shading, torn workwear, boots and facial asymmetry keep silhouettes readable.
		paint_rect(image,origin,Rect2i(-7,2,3,11),Color("#586551"))
		paint_rect(image,origin,Rect2i(3,3,4,10),Color("#253b35"))
		paint_rect(image,origin,Rect2i(-2,3,2,11),Color("#a99c77"))
		paint_rect(image,origin,Rect2i(-7,10,5,3),Color("#695042"))
		paint_rect(image,origin,Rect2i(-7,-15,10,3),Color("#3e4c3b"))
		paint_rect(image,origin,Rect2i(-7,-7,3,5),Color("#607f51"))
		paint_rect(image,origin,Rect2i(5,-6,3,5),Color("#698252"))
		paint_rect(image,origin,Rect2i(-4,-1,9,3),Color("#293a30"))
		paint_rect(image,origin,Rect2i(-2,-1,2,2),Color("#ddd0a4"))
		paint_rect(image,origin,Rect2i(2,-1,2,2),Color("#ddd0a4"))
		if state & 4: paint_rect(image,origin,Rect2i(-8,21 + stride,7,3),Color("#273537"))
		if state & 8: paint_rect(image,origin,Rect2i(1,21 - stride,7,3),Color("#273537"))
	body_atlas = ImageTexture.create_from_image(image)
	return body_atlas

func body_state() -> int:
	return (1 if "left_arm" in limbs else 0) | (2 if "right_arm" in limbs else 0) | (4 if "left_leg" in limbs else 0) | (8 if "right_leg" in limbs else 0) | (16 if hit_flash > 0 else 0)

func create_body_sprite() -> void:
	if body_sprite != null: return
	body_sprite = Sprite2D.new()
	body_sprite.name = "BodySprite"
	body_sprite.show_behind_parent = true
	body_sprite.texture = get_body_atlas()
	body_sprite.modulate = Color("#ffc68a") if archetype == "runner" else (Color("#b6ef85") if behavior() in ["spitter","plague"] else Color.WHITE)
	var palettes := {"crawler":"#9baf88","stalker":"#a7b5cc","dodger":"#e5c19c","healer":"#b5e4c9","swarm":"#d1b78b","sapper":"#c6abc9","berserker":"#d4a693","warden":"#b2c8d8","executor":"#d6b69c"}
	if palettes.has(archetype): body_sprite.modulate = Color(palettes[archetype])
	body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body_sprite.region_enabled = true
	body_sprite.scale = Vector2.ONE * 0.5
	add_child(body_sprite)

func update_visual() -> void:
	if body_sprite == null:
		queue_redraw()
		return
	var state: int = body_state() + (0 if attacking else posmod(int(walking_time * 2),4) * 32)
	if archetype == "stalker": modulate.a = 0.45 if position.y < -180 else 1.0
	if state != last_body_state:
		body_sprite.region_rect = Rect2(Vector2(Vector2i(state % 8, state / 8) * BODY_SIZE),Vector2(BODY_SIZE))
		last_body_state = state
	body_sprite.position = Vector2(0,4 + (0.0 if attacking else sin(walking_time) * 1.5))

func _draw() -> void:
	draw_archetype()
	if body_sprite != null: return
	var state: int = body_state()
	var bob: float = 0.0 if attacking else sin(walking_time) * 1.5
	var source := Rect2(Vector2(Vector2i(state % 8, state / 8) * BODY_SIZE), Vector2(BODY_SIZE))
	draw_texture_rect_region(get_body_atlas(), Rect2(-16, -20 + bob, 32, 48), source)

func draw_archetype() -> void:
	if focused:
		var marker_y: float = -65.0 if archetype in ["brute","plague","warden","broodmother","executor"] else -44.0
		draw_colored_polygon(PackedVector2Array([Vector2(-5,marker_y),Vector2(5,marker_y),Vector2(0,marker_y + 6)]),Color("#ffe08a"))
	if archetype in ["healer","shielder"]:
		draw_arc(Vector2(0,8),25,0,TAU,16,Color("#94d7b0") if archetype == "healer" else Color("#92b6df"),1)
	if archetype == "swarm": draw_circle(Vector2(0,7),9,Color("#b88155"))
	if archetype == "healer":
		draw_rect(Rect2(-13,4,6,13),Color("#355b4b"))
		draw_line(Vector2(-10,7),Vector2(-10,13),Color("#c5e8cc"),2)
		draw_line(Vector2(-13,10),Vector2(-7,10),Color("#c5e8cc"),2)
	if archetype == "dodger": draw_line(Vector2(-8,-15),Vector2(8,-15),Color("#cf7755"),3)
	if archetype == "sapper":
		draw_rect(Rect2(-9,12,18,4),Color("#735348"))
		draw_line(Vector2(8,7),Vector2(13,16),Color("#a7c6cc"),3)
	if archetype == "shielder":
		draw_rect(Rect2(4,4,13,18),Color("#607c90"))
		draw_rect(Rect2(6,6,9,14),Color("#b4c4cc"),false,2)
	if archetype in ["warden","executor"]:
		draw_line(Vector2(-14,4),Vector2(-14,24),Color("#82664b"),3)
		draw_colored_polygon(PackedVector2Array([Vector2(-15,3),Vector2(-24,0),Vector2(-24,11),Vector2(-15,9)]),Color("#9eaeb8"))
	if archetype == "broodmother":
		for point: Vector2 in [Vector2(-9,12),Vector2(11,6),Vector2(5,16)]:
			draw_circle(point,4,Color("#78923f"))
			draw_circle(point + Vector2(-1,-1),2,Color("#d5e477"))
	if armor > 0:
		draw_rect(Rect2(-10,1,20,14),Color("#596b7b"))
		draw_rect(Rect2(-10,1,20,14),Color("#d1d8dc"),false,1.5)
		draw_rect(Rect2(-11,-17,22,6),Color("#8597a3"))
	if archetype == "runner": draw_line(Vector2(-10,3),Vector2(10,7),Color("#e59a45"),4)
	if behavior() in ["spitter","plague"]:
		draw_circle(Vector2(8,9),6,Color("#4a7628"))
		draw_circle(Vector2(8,8),3,Color("#bde458"))
	if behavior() == "bomber":
		draw_rect(Rect2(-9,4,18,12),Color("#a64b32"))
		draw_line(Vector2(-5,7),Vector2(5,13),Color("#ffe293"),2)
	if behavior() == "plague":
		for x in [-7,0,7]: draw_rect(Rect2(x - 2,-24,4,7),Color("#d5b566"))
		if phase != "exposed" and not retreating: draw_arc(Vector2.ZERO,21,PI,TAU,16,Color("#7ac8b5"),2)
	if phase == "windup":
		var pulse: float = 0.65 + 0.35 * sin(ability_timer * 12)
		draw_circle(Vector2(0,23),20,Color(0.95,0.32,0.16,0.16 * pulse))
		draw_arc(Vector2(0,23),20,0,TAU,24,Color(1,0.55,0.22,pulse),2)
		draw_string(ThemeDB.fallback_font,Vector2(-15,-28),"¡CARGA!" if behavior() == "brute" else ("¡BOOM!" if behavior() == "bomber" else "ÁCIDO"),HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("#ffca72"))
	if phase == "exposed": draw_arc(Vector2.ZERO,20,0,TAU,24,Color("#f1df78"),2)
	if archetype in ["brute","plague","warden","broodmother","executor"] or health < max_health:
		draw_rect(Rect2(-18,-42,36,3),Color("#352d28"))
		draw_rect(Rect2(-18,-42,36 * health / max_health,3),Color("#d79b60"))
	if archetype in ["brute","plague","warden","broodmother","executor"]:
		draw_string(ThemeDB.fallback_font,Vector2(-26,-48),str(TYPES[archetype]["name"]),HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color("#f5d198"))

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
