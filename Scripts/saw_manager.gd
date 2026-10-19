extends Node2D

signal changed
signal cut(cell: Vector2i)

const PRICE := 250
const PROCESS_TIME := 4.0
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
static var blade_texture: ImageTexture
var game: Node2D
var grid: RefCounted
var mining: RefCounted
var machines: Dictionary = {}

func _ready() -> void:
	game = get_parent()
	grid = game.get("grid")
	mining = game.get("mining")
	mining.saws = self
	changed.connect(queue_redraw)
	changed.connect(game.redraw_world)

func _exit_tree() -> void:
	if mining != null and mining.saws == self: mining.saws = null

func can_place(cell: Vector2i) -> bool:
	return mining.can_move_nugget(cell) and grid.is_valid_cell(cell) and cell != grid.sale_cell and not game.get("conveyors").belts.has(cell) and not game.get("launchers").launchers.has(cell)

func place(cell: Vector2i, direction: int = 1) -> bool:
	if not can_place(cell): return false
	machines[cell] = {"direction": posmod(direction,4), "input": "", "output": "", "count": 0, "pending": [false,false], "elapsed": 0.0}
	changed.emit()
	return true

static func lower_tier(kind: String) -> String:
	# Keep the material and form: ingots split into ingots, nuggets into nuggets.
	for level in [2,3,4]:
		for material in ["coal","copper","iron","gold","copper_ingot","iron_ingot","gold_ingot"]:
			if kind == material + "_" + str(level): return material if level == 2 else material + "_" + str(level - 1)
	return ""

func can_receive(cell: Vector2i, kind: String) -> bool:
	return machines.has(cell) and not lower_tier(kind).is_empty() and str(machines[cell]["input"]).is_empty() and int(machines[cell]["count"]) == 0

func receive(cell: Vector2i, kind: String) -> bool:
	if not can_receive(cell,kind): return false
	machines[cell]["input"] = kind
	machines[cell]["elapsed"] = 0.0
	changed.emit()
	return true

func stored_items(cell: Vector2i) -> Dictionary:
	if not machines.has(cell): return {}
	var data: Dictionary = machines[cell]
	if not str(data["input"]).is_empty(): return {data["input"]: 1}
	if int(data["count"]) > 0: return {data["output"]: int(data["count"])}
	return {}

func remove_material(cell: Vector2i, kind: String) -> bool:
	if not machines.has(cell): return false
	var data: Dictionary = machines[cell]
	if data["input"] == kind:
		data["input"] = ""
		data["elapsed"] = 0.0
	elif data["output"] == kind and int(data["count"]) > 0:
		ensure_pending(data)
		for index in range(2):
			if data["pending"][index]:
				data["pending"][index] = false
				break
		data["count"] = int(data["count"]) - 1
		if int(data["count"]) == 0: data["output"] = ""
	else: return false
	changed.emit()
	return true

func process_cutting(delta: float) -> void:
	for cell: Vector2i in machines:
		var data: Dictionary = machines[cell]
		if not str(data["input"]).is_empty():
			data["elapsed"] = minf(PROCESS_TIME,float(data["elapsed"]) + maxf(delta,0))
			queue_redraw()
			if float(data["elapsed"]) < PROCESS_TIME: continue
			data["output"] = lower_tier(data["input"])
			data["input"] = ""
			data["count"] = 2
			data["pending"] = [true,true]
			data["elapsed"] = 0.0
			mining.resource_created.emit(str(data["output"]))
			cut.emit(cell)
			changed.emit()
		if int(data["count"]) > 0: try_output(cell)

static func outlet_cells(cell: Vector2i, direction: int) -> Array[Vector2i]:
	var forward: Vector2i = DIRECTIONS[posmod(direction,4)]
	var side := Vector2i(-forward.y,forward.x)
	return [cell + forward - side,cell + forward + side]

func ensure_pending(data: Dictionary) -> void:
	# Preserve outputs in machines created before the two-outlet update.
	if not data.has("pending"): data["pending"] = [int(data["count"]) == 2,int(data["count"]) > 0]

func try_output(cell: Vector2i) -> void:
	var data: Dictionary = machines[cell]
	if int(data["count"]) <= 0: return
	ensure_pending(data)
	var destinations: Array[Vector2i] = outlet_cells(cell,int(data["direction"]))
	var belts: RefCounted = game.get("conveyors")
	var forward: Vector2i = DIRECTIONS[int(data["direction"])]
	var emitted: bool = false
	for index in range(2):
		if not data["pending"][index]: continue
		var destination: Vector2i = destinations[index]
		if destination == grid.sale_cell or not mining.can_move_nugget(destination): continue
		# Diagonal outlets enter belts along the machine's forward axis.
		if belts.belts.has(destination) and not belts.accepts_from(destination,destination - forward): continue
		mining.items_for(data["output"])[destination] = 1
		data["pending"][index] = false
		data["count"] = int(data["count"]) - 1
		emitted = true
	if int(data["count"]) == 0: data["output"] = ""
	if emitted:
		mining.changed.emit()
		changed.emit()

func _process(delta: float) -> void:
	if not game.get("cycle").defeated: process_cutting(delta)
	var mover: Node = game.get_node_or_null("WorldInteractions")
	if mover != null and (mover.placing_saw or game.get("held_object_type") == "saw"): queue_redraw()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_R: return
	var mover: Node = game.get_node_or_null("WorldInteractions")
	if mover == null or not mover.phase_allows() or (game.get("cycle").is_night and not mover.placing_saw): return
	if not mover.placing_saw and not (game.get("holding_object") and game.get("held_object_type") == "saw"): return
	game.set("placement_direction",posmod(int(game.get("placement_direction")) + 1,4))
	if game.get("holding_object"): game.set("dragging_object",true)
	queue_redraw()
	get_viewport().set_input_as_handled()

func _draw() -> void:
	if game == null: return
	for cell: Vector2i in machines:
		if game.get("dragging_object") and game.get("held_object_type") == "saw" and game.get("held_object_cell") == cell: continue
		draw_machine(self,grid.get_cell_rect(cell).get_center(),machines[cell])
	var mover: Node = game.get_node_or_null("WorldInteractions")
	if mover == null: return
	if mover.placing_saw and mover.phase_allows():
		var cell: Vector2i = grid.world_to_cell(game.get_local_mouse_position())
		draw_machine(self,grid.get_cell_rect(cell).get_center(),{"direction":game.get("placement_direction")})
		draw_rect(grid.get_cell_rect(cell).grow(-1),Color("#f0c777") if can_place(cell) else Color("#df7770"),false,2)
	if game.get("dragging_object") and game.get("held_object_type") == "saw" and machines.has(game.get("held_object_cell")):
		var data: Dictionary = machines[game.get("held_object_cell")].duplicate()
		data["direction"] = game.get("placement_direction")
		draw_machine(self,game.get("drag_world_position"),data)

static func draw_machine(canvas: Node2D, center: Vector2, data: Dictionary) -> void:
	if blade_texture == null:
		var image := Image.new()
		var points: String = ""
		for i in range(48):
			var angle: float = i * TAU / 48
			var radius: float = 29 if i % 3 == 0 else 24
			points += "%f,%f " % [32 + cos(angle)*radius,32 + sin(angle)*radius]
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64"><polygon points="%s" fill="#a9bbc3" stroke="#344650" stroke-width="2"/><circle cx="32" cy="32" r="17" fill="#718792"/><circle cx="32" cy="32" r="5" fill="#e0bd73"/></svg>' % points)
		blade_texture = ImageTexture.create_from_image(image)
	canvas.draw_rect(Rect2(center - Vector2(21,21),Vector2(42,42)),Color("#263139"))
	canvas.draw_rect(Rect2(center - Vector2(21,21),Vector2(42,42)),Color("#bd965f"),false,2)
	var active: bool = not str(data.get("input","")).is_empty()
	var angle: float = float(data.get("elapsed",0)) * 8 if active else 0
	canvas.draw_set_transform(center,angle)
	canvas.draw_texture_rect(blade_texture,Rect2(-17,-17,34,34),false)
	canvas.draw_set_transform(Vector2.ZERO)
	var outward: Vector2 = Vector2(DIRECTIONS[posmod(int(data.get("direction",1)),4)])
	var side := Vector2(-outward.y,outward.x)
	for sign_value in [-1,1]:
		var arrow: Vector2 = (outward + side * sign_value).normalized()
		var flank := Vector2(-arrow.y,arrow.x)
		var tip: Vector2 = center + arrow * 27
		canvas.draw_line(center + arrow * 13,tip - arrow * 5,Color("#ffe084"),3)
		canvas.draw_colored_polygon(PackedVector2Array([tip,tip-arrow*9+flank*5,tip-arrow*9-flank*5]),Color("#ffe084"))
	if active:
		canvas.draw_rect(Rect2(center+Vector2(-16,17),Vector2(32,3)),Color("#273239"))
		canvas.draw_rect(Rect2(center+Vector2(-16,17),Vector2(32*float(data.get("elapsed",0))/PROCESS_TIME,3)),Color("#eed083"))
