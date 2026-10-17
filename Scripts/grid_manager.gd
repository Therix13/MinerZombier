extends RefCounted

const TILE_SIZE := 48
const MAP_WIDTH := 30
const MAP_HEIGHT := 40
const GRID_OFFSET_Y := 220.0

var cave_width: int = 3
var cave_height: int = 3
var owned_tiles: Dictionary = {}
var sale_cell: Vector2i = Vector2i(15, -1)
var defense_tiles: Dictionary = {}
var ammo_tiles: Dictionary = {}

func _init() -> void:
	apply_cave_size()

func apply_cave_size() -> void:
	owned_tiles.clear()
	var center_x: int = floori(MAP_WIDTH / 2.0)
	var start_x: int = center_x - floori(cave_width / 2.0)
	for y in range(cave_height):
		for x in range(cave_width):
			owned_tiles[Vector2i(start_x + x, y)] = true
	for cell in defense_tiles:
		owned_tiles[cell] = true
	for cell in ammo_tiles:
		owned_tiles[cell] = true

func expand() -> void:
	cave_width = 7
	cave_height = 5
	apply_cave_size()

func get_cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell.x * TILE_SIZE, GRID_OFFSET_Y + cell.y * TILE_SIZE), Vector2.ONE * TILE_SIZE)

func world_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / TILE_SIZE), floori((point.y - GRID_OFFSET_Y) / TILE_SIZE))

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < MAP_WIDTH and cell.y >= 0 and cell.y < MAP_HEIGHT

func get_map_size() -> Vector2:
	return Vector2(MAP_WIDTH * TILE_SIZE, GRID_OFFSET_Y + MAP_HEIGHT * TILE_SIZE)

func defense_cell(side: String) -> Vector2i:
	var center_x: int = floori(MAP_WIDTH / 2.0)
	return Vector2i(center_x - 3 if side == "left" else center_x + 3, -3)

func is_defense_position(cell: Vector2i) -> bool:
	return cell == defense_cell("left") or cell == defense_cell("right")

func is_ammo_cell(cell: Vector2i) -> bool:
	return ammo_tiles.has(cell)

func purchase_defense_cell(_side: String) -> bool:
	return purchase_defense_platforms()

func purchase_defense_platforms() -> bool:
	var left_cell: Vector2i = defense_cell("left")
	var right_cell: Vector2i = defense_cell("right")
	if defense_tiles.has(left_cell) and defense_tiles.has(right_cell):
		return false
	defense_tiles[left_cell] = true
	defense_tiles[right_cell] = true
	for platform: Vector2i in [left_cell, right_cell]:
		for offset_y in [1, 2]:
			var connection: Vector2i = platform + Vector2i(0, offset_y)
			ammo_tiles[connection] = true
			owned_tiles[connection] = true
	return true
