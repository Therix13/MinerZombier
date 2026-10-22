extends Node2D
const Art = preload("res://Scripts/painted_assets.gd")
var game: Node2D
var dust: CPUParticles2D
var modulator: CanvasModulate
var glow: GradientTexture2D
var parts: Dictionary = {}
var lamps: Dictionary = {}
var refresh: float = 0
var clock: float = 0

func _ready() -> void:
	game = get_parent()
	z_index = 3
	modulator = CanvasModulate.new()
	add_child(modulator)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE,Color(1,1,1,0)])
	glow = GradientTexture2D.new()
	glow.width = 128
	glow.height = 128
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(.5,.5)
	glow.fill_to = Vector2(.5,1)
	glow.gradient = gradient
	dust = CPUParticles2D.new()
	dust.amount = 64
	dust.lifetime = 12
	dust.preprocess = 10
	dust.texture = glow
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(400,300)
	dust.direction = Vector2(-.5,-1)
	dust.spread = 60
	dust.gravity = Vector2(.1,-.2)
	dust.initial_velocity_min = 1
	dust.initial_velocity_max = 4
	dust.scale_amount_min = .004
	dust.scale_amount_max = .014
	dust.color = Color(.8,.72,.52,.5)
	dust.local_coords = false
	add_child(dust)
	game.launchers.fired.connect(muzzle_flash)
	game.mining.struck.connect(mining_sparks)

func _process(delta: float) -> void:
	clock += delta
	var target := Color(.73,.82,.92) if game.cycle.is_night else Color(.96,.97,1)
	modulator.color = modulator.color.lerp(target,minf(1,delta*1.2))
	dust.position = game.camera.position
	dust.emission_rect_extents = get_viewport_rect().size/game.camera.zoom*.55
	dust.color = Color(.35,.75,.85,.5) if game.camera_controller.defense_view else Color(.85,.7,.43,.5)
	refresh -= delta
	if refresh <= 0:
		refresh = .2
		refresh_parts()
	for cell: Vector2i in parts:
		var entry: Dictionary = parts[cell]
		var data: Dictionary = game.get_node(entry["node"]).machines.get(cell,{})
		var active: bool = not str(data.get("input","")).is_empty() if entry["node"] == "Saws" else int(data.get("points",0)) >= 8
		entry["sprite"].visible = active and not (game.dragging_object and game.held_object_cell == cell)
		if entry["node"] == "Saws": entry["sprite"].rotation = clock*7
		else: entry["sprite"].position = game.grid.get_cell_rect(cell).get_center()+Vector2(0,-9+sin(clock*5)*2)
	for cell: Vector2i in lamps:
		var data: Dictionary = game.get_node("Furnaces").machines.get(cell,{})
		lamps[cell].modulate.a = (.36+sin(clock*17+cell.x)*.05) if data.get("burning",false) else (.08 if data.get("fuel",0)>0 else 0.0)

func refresh_parts() -> void:
	var desired: Dictionary = {}
	for path: String in ["Saws","Compactors"]:
		for cell: Vector2i in game.get_node(path).machines:
			desired[cell] = path
	for cell: Vector2i in parts.keys():
		if desired.get(cell,"") != parts[cell]["node"]:
			parts[cell]["sprite"].queue_free()
			parts.erase(cell)
	for cell: Vector2i in desired:
		if parts.has(cell): continue
		var source: AtlasTexture = Art.prop(7 if desired[cell] == "Saws" else 6)
		var area: Rect2 = source.region
		var piece := Rect2(area.position+area.size*(Vector2(.27,.055) if desired[cell] == "Saws" else Vector2(.23,.2)),area.size*(Vector2(.46,.46) if desired[cell] == "Saws" else Vector2(.54,.24)))
		var sprite := Sprite2D.new()
		sprite.texture = Art.region(Art.INDUSTRY,piece)
		sprite.scale = Vector2.ONE*(50.0/area.size.x)
		sprite.position = game.grid.get_cell_rect(cell).get_center()+Vector2(0,-10)
		if desired[cell] == "Saws":
			var material := ShaderMaterial.new()
			material.shader = preload("res://Shaders/rotor_mask.gdshader")
			var size: Vector2 = source.atlas.get_size()
			material.set_shader_parameter("frame",Vector4(piece.position.x/size.x,piece.position.y/size.y,piece.size.x/size.x,piece.size.y/size.y))
			sprite.material = material
		add_child(sprite)
		parts[cell] = {"node":desired[cell],"sprite":sprite}
	var furnaces: Dictionary = game.get_node("Furnaces").machines
	for cell: Vector2i in lamps.keys():
		if not furnaces.has(cell):
			lamps[cell].queue_free()
			lamps.erase(cell)
	for cell: Vector2i in furnaces:
		if lamps.has(cell) or lamps.size() >= 12: continue
		var light := Sprite2D.new()
		light.texture = glow
		light.modulate = Color(1,.59,.26,0)
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		light.material = material
		light.position = game.grid.get_cell_rect(cell).get_center()
		add_child(light)
		lamps[cell] = light

func muzzle_flash(cell: Vector2i) -> void:
	var data: Dictionary = game.launchers.launchers.get(cell,{})
	var angle: float = float(data.get("angle",-PI*.5))
	var flare := Sprite2D.new()
	flare.texture = glow
	flare.position = game.grid.get_cell_rect(cell).get_center()+Vector2.RIGHT.rotated(angle)*23
	flare.scale = Vector2(.24,.08)
	flare.rotation = angle
	flare.modulate = Color(.5,.85,1,.9) if data.get("weapon","") == "tesla" else Color(1,.75,.33,.95)
	add_child(flare)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flare.material = material
	var tween: Tween = flare.create_tween().set_parallel(true)
	tween.tween_property(flare,"modulate:a",0.0,.12)
	tween.tween_property(flare,"scale",Vector2(.32,.12),.12)
	tween.chain().tween_callback(flare.queue_free)

func mining_sparks(cell: Vector2i) -> void:
	var position: Vector2 = game.grid.get_cell_rect(cell).get_center()
	for i in range(3):
		var spark := Sprite2D.new()
		spark.texture = glow
		spark.position = position+Vector2(-8+i*7,-3)
		spark.scale = Vector2.ONE*.025
		spark.modulate = Color(1,.72,.3,.8)
		add_child(spark)
		var tween: Tween = spark.create_tween().set_parallel(true)
		tween.tween_property(spark,"position",spark.position+Vector2((i-1)*8,-14-i*3),.25)
		tween.tween_property(spark,"modulate:a",0.0,.25)
		tween.chain().tween_callback(spark.queue_free)
