extends Node2D

const FENCE_Y := -120.0
const HORDE_SIZE := 24
var grid: RefCounted
var live_game: Node
var time := 0.0
var destruction := 0.0
var actors: Array[Node2D] = []
var last_destruction := -1.0
var last_center := INF

func _ready() -> void:
	for index in range(HORDE_SIZE):
		var actor := WaitingZombie.new()
		add_child(actor)
		actors.append(actor)
	present()

func _process(delta: float) -> void:
	if live_game == null: return
	visible = live_game.get("cycle").day == 1 and not live_game.get("cycle").barrier_broken
	if not visible: return
	time += delta
	present()

func present() -> void:
	var center: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	var geometry_changed: bool = destruction != last_destruction or center != last_center
	if not geometry_changed and destruction < 0.7: return
	for index in range(actors.size()):
		var row: int = index / 8
		var advance: float = smoothstep(0.5,1.0,destruction) * (190 - row * 25)
		if geometry_changed: actors[index].position = Vector2(center + (index % 8 - 3.5) * 48, FENCE_Y - 20 - row * 42 + advance)
		actors[index].walking_time = time * 5 + index
		actors[index].attacking = destruction < 0.7
		actors[index].update_visual()
	if geometry_changed:
		last_destruction = destruction
		last_center = center
		queue_redraw()

func _draw() -> void:
	if grid == null: return
	var center: float = grid.get_cell_rect(grid.sale_cell).get_center().x
	for index in range(21):
		var phase: float = clampf((destruction-float(index%5)*.07)*1.5,0,1)
		var at := Vector2(center-280+index*28,FENCE_Y+phase*(50+index%3*12))
		draw_set_transform(at,phase*(-1.1 if index%2 else 1.2))
		draw_rect(Rect2(-11,-23,22,38),Color("#30475b"))
		draw_line(Vector2(-8,-20),Vector2(-8,12),Color("#6ee7ce"),1,true)
		if destruction > .15: draw_line(Vector2(-4,-16),Vector2(5,4),Color("#111b2b"),2,true)
		draw_set_transform(Vector2.ZERO)
	if destruction < .65:
		for y in [-13,5]: draw_line(Vector2(center-293,FENCE_Y+y),Vector2(center+293,FENCE_Y+y),Color("#536b82"),3,true)

class WaitingZombie extends "res://Scripts/zombie.gd":
	func _ready() -> void:
		set_process(false)
		create_body_sprite()
		update_visual()
