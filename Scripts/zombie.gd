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
		spawn_death_pose()
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
static var body_atlas: Texture2D
const BODY_SIZE := Vector2i(128, 192)

static func get_body_atlas() -> Texture2D:
	if body_atlas == null: body_atlas = preload("res://Scripts/painted_assets.gd").texture(preload("res://Scripts/painted_assets.gd").INFECTED)
	return body_atlas

func body_state() -> int:
	return (1 if "left_arm" in limbs else 0) | (2 if "right_arm" in limbs else 0) | (4 if "left_leg" in limbs else 0) | (8 if "right_leg" in limbs else 0) | (16 if hit_flash > 0 else 0)

func create_body_sprite() -> void:
	if body_sprite != null: return
	body_sprite = Sprite2D.new()
	body_sprite.name = "BodySprite"
	body_sprite.show_behind_parent = true
	body_sprite.texture = get_body_atlas()
	body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body_sprite.region_enabled = true
	body_sprite.region_rect = preload("res://Scripts/painted_assets.gd").enemy_region(archetype)
	body_sprite.scale = Vector2.ONE*(48.0/body_sprite.region_rect.size.y)
	var material := ShaderMaterial.new()
	material.shader = preload("res://Shaders/infected_motion.gdshader")
	var bounds: Rect2 = body_sprite.region_rect
	var sheet_size: Vector2 = get_body_atlas().get_size()
	material.set_shader_parameter("frame",Vector4(bounds.position.x/sheet_size.x,bounds.position.y/sheet_size.y,bounds.size.x/sheet_size.x,bounds.size.y/sheet_size.y))
	body_sprite.material = material
	add_child(body_sprite)

func update_visual() -> void:
	if body_sprite == null:
		queue_redraw()
		return
	var material: ShaderMaterial = body_sprite.material
	material.set_shader_parameter("gait",walking_time)
	material.set_shader_parameter("walking",0.15 if attacking or phase in ["windup","exposed"] else 1.0)
	material.set_shader_parameter("hurt",minf(1.0,hit_flash*6))
	material.set_shader_parameter("limb_mask",Vector4(1 if "left_arm" in limbs else 0,1 if "right_arm" in limbs else 0,1 if "left_leg" in limbs else 0,1 if "right_leg" in limbs else 0))
	if archetype == "stalker": modulate.a = 0.45 if position.y < -180 else 1.0
	var breathing: float = sin(float(Time.get_ticks_msec())*.002+get_instance_id()%17)*.007
	var size: float = 48.0/body_sprite.region_rect.size.y
	body_sprite.scale = Vector2(size*(1-breathing),size*(1+breathing))
	body_sprite.position = Vector2(sin(walking_time)*.7 if not attacking else 0,3+(sin(walking_time*2)*.7 if not attacking else sin(hit_flash*18)*1.6))
	body_sprite.rotation = sin(walking_time)*.018 if not attacking else sin(hit_flash*14)*.04
	last_body_state = body_state()
	queue_redraw()

func _draw() -> void:
	draw_archetype()
	if body_sprite == null: preload("res://Scripts/painted_assets.gd").draw(self,preload("res://Scripts/painted_assets.gd").enemy(archetype),Rect2(-24,-24,48,48))

func draw_archetype() -> void:
	if focused:
		draw_arc(Vector2(0,20),19,0,TAU,48,Color("#f1c98c"),1.3,true)
	if archetype in ["healer","shielder"]:
		draw_arc(Vector2(0,20),24,0,TAU,48,Color(.3,.75,.8,.35),1,true)
	if phase == "windup":
		var pulse: float = .5+.5*sin(ability_timer*12)
		draw_circle(Vector2(0,20),21,Color(1,.35,.1,.08+.08*pulse),true,-1,true)
		draw_arc(Vector2(0,20),21,0,TAU,48,Color(1,.65,.3,.6+.4*pulse),1.5,true)
		draw_string(ThemeDB.fallback_font,Vector2(-17,-29),"¡CARGA!" if behavior() == "brute" else ("¡BOOM!" if behavior() == "bomber" else "ÁCIDO"),HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color("#f3cf98"))
	if phase == "exposed": draw_arc(Vector2(0,20),21,0,TAU,48,Color("#e6d5a1"),1.5,true)
	if health < max_health or archetype in ["plague","warden","broodmother","executor"]:
		draw_line(Vector2(-17,-29),Vector2(17,-29),Color("#172027"),3,true)
		draw_line(Vector2(-17,-29),Vector2(-17+34*health/max_health,-29),Color("#da9f6c"),2,true)
	if archetype in ["plague","warden","broodmother","executor"]:
		draw_string(ThemeDB.fallback_font,Vector2(-27,-36),str(TYPES[archetype]["name"]),HORIZONTAL_ALIGNMENT_LEFT,-1,7,Color("#f1c98c"))

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

func spawn_death_pose() -> void:
	if body_sprite == null or not is_inside_tree(): return
	var corpse := Sprite2D.new()
	corpse.texture = body_sprite.texture
	corpse.region_enabled = true
	corpse.region_rect = body_sprite.region_rect
	corpse.material = body_sprite.material.duplicate()
	corpse.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	get_parent().add_child(corpse)
	corpse.global_position = global_position+Vector2(0,4)
	corpse.scale = body_sprite.scale*scale
	var tween: Tween = corpse.create_tween().set_parallel(true)
	tween.tween_property(corpse,"rotation",-.8,.65).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(corpse,"scale:y",corpse.scale.y*.45,.7)
	tween.tween_method(func(value: float): corpse.material.set_shader_parameter("dissolve",value),0.0,1.0,1.1)
	tween.chain().tween_callback(corpse.queue_free)
