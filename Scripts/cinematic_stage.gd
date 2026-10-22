extends Control
const Art = preload("res://Scripts/painted_assets.gd")
var scene_data: Dictionary = {}
var shot: int = 0
var time: float = 0.0
var progress: float = 0.0
var boss: String = ""
var picture: TextureRect
var grade: ShaderMaterial
var foreground: Node2D
var caption_gradient: GradientTexture2D
var spore_texture: GradientTexture2D
var ready_stage: bool = false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture = TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	grade = ShaderMaterial.new()
	grade.shader = preload("res://Shaders/cinematic_grade.gdshader")
	picture.material = grade
	add_child(picture)
	var captions := Gradient.new()
	captions.colors = PackedColorArray([Color(.015,.025,.04,0),Color(.015,.025,.04,.98)])
	caption_gradient = GradientTexture2D.new()
	caption_gradient.width = 4
	caption_gradient.height = 512
	caption_gradient.gradient = captions
	caption_gradient.fill_from = Vector2(0,0)
	caption_gradient.fill_to = Vector2(0,1)
	foreground = Foreground.new()
	foreground.stage = self
	add_child(foreground)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.55,0.9,1,0.7),Color(0.2,0.7,0.9,0)])
	spore_texture = GradientTexture2D.new()
	spore_texture.width = 32
	spore_texture.height = 32
	spore_texture.fill = GradientTexture2D.FILL_RADIAL
	spore_texture.fill_from = Vector2(.5,.5)
	spore_texture.fill_to = Vector2(.5,1)
	spore_texture.gradient = gradient
	var particles := CPUParticles2D.new()
	particles.position = Vector2(640,300)
	particles.amount = 55
	particles.lifetime = 9
	particles.preprocess = 7
	particles.texture = spore_texture
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(750,450)
	particles.direction = Vector2(-.7,-1)
	particles.spread = 45
	particles.gravity = Vector2(2,-2)
	particles.initial_velocity_min = 7
	particles.initial_velocity_max = 20
	particles.scale_amount_min = .08
	particles.scale_amount_max = .26
	particles.color = Color(.7,.9,1,.5)
	add_child(particles)
	ready_stage = true
	present()

func present() -> void:
	if not ready_stage: return
	boss = str(scene_data.get("boss",boss))
	var base_shot: int = int(scene_data.get("shot",shot))
	picture.texture = Art.scene(base_shot)
	var area: Rect2 = picture.texture.region
	var sheet_size: Vector2 = picture.texture.atlas.get_size()
	grade.set_shader_parameter("panel",Vector4(area.position.x/sheet_size.x,area.position.y/sheet_size.y,area.size.x/sheet_size.x,area.size.y/sheet_size.y))
	var zoom: float = 1.06+smoothstep(0,1,progress)*.09
	var drift := Vector2(sin(time*.08)*18,cos(time*.07)*9)
	var shake := Vector2.ZERO
	if base_shot == 1 and time > 1.0 and time < 2.2: shake = Vector2(sin(time*47),cos(time*61))*2.4
	picture.size = Vector2(1280,720)*zoom
	picture.position = (Vector2(1280,720)-picture.size)*.5+drift+shake
	grade.set_shader_parameter("clock",time)
	grade.set_shader_parameter("alarm",.5 if base_shot == 1 else 0)
	grade.set_shader_parameter("exposure",.80 if not boss.is_empty() else 1.0)
	foreground.queue_redraw()

func _process(_delta: float) -> void:
	present()

class Foreground extends Node2D:
	var stage: Control
	func _draw() -> void:
		if stage == null: return
		var time: float = stage.time
		var boss: String = stage.boss
		if not boss.is_empty():
			var fall: float = smoothstep(1.0,4.0,time)
			var at := Vector2(650,305+fall*65)
			var angle: float = fall*(.22 if boss in ["plague","broodmother"] else -.3)
			draw_set_transform(at,angle,Vector2(1.0,1.0-fall*.2))
			var tex: Texture2D = Art.enemy(boss)
			var dimensions := Vector2(355,355)
			if tex != null: dimensions.x = dimensions.y*tex.get_width()/tex.get_height()
			Art.draw(self,tex,Rect2(-dimensions*.5,dimensions),Color(1,1,1,1-fall*.65))
			draw_set_transform(Vector2.ZERO)
			for i in range(36):
				var direction := Vector2.RIGHT.rotated(i*2.3999)
				var distance: float = 25+fall*(60+i%5*15)
				var alpha: float = sin(fall*PI)*.65
				draw_circle(at+direction*distance,1+i%3,Color(.35,.83,.9,alpha),true,-1,true)
			if boss == "executor": draw_line(at+Vector2(-100,40),at+Vector2(105,85),Color(.95,.6,.25,sin(fall*PI)),2,true)
			if boss == "warden":
				for side in [-1,1]: draw_line(at+Vector2(side*(35+fall*60),-30),at+Vector2(side*(60+fall*85),80),Color(.65,.75,.8,sin(fall*PI)*.8),3,true)
			if boss in ["plague","broodmother"]:
				draw_arc(at,50+fall*160,0,TAU,96,Color(.22,.7,.75,sin(fall*PI)*.35),2,true)
		# Soft letterbox and a deep caption gradient, independent of the painted plate.
		draw_texture_rect(stage.caption_gradient,Rect2(0,360,1280,360),false)
		draw_rect(Rect2(0,0,1280,42),Color("#070c13"))
		draw_rect(Rect2(0,696,1280,24),Color("#070c13"))
