extends RefCounted

signal transported(source: Vector2i, destination: Vector2i, kind: String)
signal changed
signal sale_completed(kind: String)

const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const MOVE_INTERVAL := 2.0
const STRAIGHT := "straight"
const CORNER := "corner"
const CORNER_RIGHT := "corner_right"
const CORNER_LEFT := "corner_left"
const JUNCTION := "junction"
const FILTER := "filter"
const FILTER_MATERIALS := ["coal", "copper", "iron", "gold"]

var grid: RefCounted
var mining: RefCounted
var launchers: RefCounted
var drills: RefCounted
var belts: Dictionary = {}
var last_junction_entry: Dictionary = {}
var accumulator: float = 0.0
var move_interval: float = MOVE_INTERVAL

func setup(grid_manager: RefCounted, mining_manager: RefCounted) -> void:
	grid = grid_manager
	mining = mining_manager

func dispose() -> void:
	grid = null
	mining = null
	launchers = null
	drills = null

func belt_data(cell: Vector2i) -> Dictionary:
	if not belts.has(cell):
		return {}
	var value: Variant = belts[cell]
	if value is Dictionary:
		return value
	return {"direction": int(value), "shape": STRAIGHT}

func belt_direction(cell: Vector2i) -> int:
	return int(belt_data(cell).get("direction", 1))

func belt_shape(cell: Vector2i) -> String:
	return str(belt_data(cell).get("shape", STRAIGHT))

func can_place(cell: Vector2i) -> bool:
	return grid.owned_tiles.has(cell) and (grid.is_valid_cell(cell) or grid.is_ammo_cell(cell)) and not grid.is_defense_position(cell) and (drills == null or not drills.drills.has(cell)) and cell != grid.sale_cell and not belts.has(cell) and (launchers == null or not launchers.launchers.has(cell)) and mining.vein_at(cell) == "" and mining.nuggets_at(cell) == 0 and not mining.occupied_by_machine(cell)

func place(cell: Vector2i, direction: int, shape: String = STRAIGHT) -> bool:
	if not grid.owned_tiles.has(cell) or not can_place(cell):
		return false
	belts[cell] = {"direction": posmod(direction, 4), "shape": shape}
	if shape == FILTER: belts[cell]["filter"] = "coal"
	changed.emit()
	return true

func move(source: Vector2i, destination: Vector2i, direction: int) -> bool:
	if not belts.has(source) or mining.nuggets_at(source) > 0:
		return false
	if source != destination and not can_place(destination):
		return false
	var data: Dictionary = belt_data(source).duplicate(true)
	var previous_entry: int = int(last_junction_entry.get(source, -1))
	belts.erase(source)
	last_junction_entry.erase(source)
	data["direction"] = posmod(direction,4)
	belts[destination] = data
	if destination == source and previous_entry >= 0:
		last_junction_entry[destination] = previous_entry
	changed.emit()
	return true

func input_index(destination: Vector2i, source: Vector2i) -> int:
	var relative: Vector2i = source - destination
	var output: int = belt_direction(destination)
	for index in range(4):
		if relative == DIRECTIONS[(output + index) % 4]:
			return index
	return -1

func accepts_from(destination: Vector2i, source: Vector2i) -> bool:
	if not belts.has(destination):
		return false
	var index: int = input_index(destination, source)
	var shape: String = belt_shape(destination)
	match shape:
		STRAIGHT, FILTER:
			return index == 2
		CORNER, CORNER_RIGHT:
			return index == 3
		CORNER_LEFT:
			return index == 1
		JUNCTION:
			return index == 1 or index == 2 or index == 3
	return false

func set_filter(cell: Vector2i, material: String) -> bool:
	if belt_shape(cell) != FILTER or material not in FILTER_MATERIALS: return false
	belts[cell]["filter"] = material
	changed.emit()
	return true

func output_direction(cell: Vector2i, kind: String) -> int:
	var direction: int = belt_direction(cell)
	if belt_shape(cell) == FILTER and kind.get_slice("_",0) != belt_data(cell).get("filter","coal"):
		return (direction + 1) % 4
	return direction

func advance(delta: float) -> void:
	accumulator += delta
	if accumulator < move_interval:
		return
	accumulator = fmod(accumulator, move_interval)
	tick()

func tick() -> void:
	var requests: Dictionary = {}
	var sales: Array[Dictionary] = []
	var construction_deliveries: Array[Dictionary] = []
	for key in belts:
		var source: Vector2i = key
		if mining.nuggets_at(source) == 0:
			continue
		var kind: String = mining.nugget_type(source)
		var destination: Vector2i = source + DIRECTIONS[output_direction(source,kind)]
		if is_instance_valid(mining.construction) and mining.construction.can_receive(destination, kind):
			construction_deliveries.append({"source": source, "destination": destination, "kind": kind})
		elif mining.occupied_by_saw(destination) and mining.saws.can_receive(destination,kind):
			if not requests.has(destination): requests[destination] = []
			requests[destination].append({"source":source,"kind":kind})
		elif mining.occupied_by_furnace(destination) and mining.furnaces.can_receive(destination, kind):
			if not requests.has(destination): requests[destination] = []
			requests[destination].append({"source": source, "kind": kind})
		elif mining.occupied_by_compactor(destination) and mining.compactors.can_receive(destination, kind):
			if not requests.has(destination): requests[destination] = []
			requests[destination].append({"source": source, "kind": kind})
		elif launchers != null and launchers.can_receive(destination, kind):
			if not requests.has(destination):
				requests[destination] = []
			requests[destination].append({"source": source, "kind": kind})
		elif destination == grid.sale_cell:
			sales.append({"source": source, "kind": kind})
		elif belts.has(destination) and mining.can_move_nugget(destination) and accepts_from(destination, source):
			if not requests.has(destination):
				requests[destination] = []
			requests[destination].append({"source": source, "kind": kind})
	var transfers: Array[Dictionary] = []
	for destination_key in requests:
		var destination: Vector2i = destination_key
		var candidates: Array = requests[destination]
		if mining.occupied_by_furnace(destination):
			for candidate: Dictionary in mining.furnaces.plan_inputs(destination, candidates):
				transfers.append({"source": candidate["source"], "destination": destination, "kind": candidate["kind"]})
			continue
		if mining.occupied_by_compactor(destination):
			for candidate: Dictionary in mining.compactors.plan_inputs(destination,candidates):
				transfers.append({"source":candidate["source"],"destination":destination,"kind":candidate["kind"]})
			continue
		var selected: Dictionary = candidates[0]
		if belt_shape(destination) == JUNCTION:
			var last_entry: int = int(last_junction_entry.get(destination, 0))
			for offset in range(1, 4):
				var wanted: int = 1 + posmod(last_entry - 1 + offset, 3)
				var found: bool = false
				for candidate in candidates:
					if input_index(destination, candidate["source"]) == wanted:
						selected = candidate
						found = true
						break
				if found:
					break
			last_junction_entry[destination] = input_index(destination, selected["source"])
		transfers.append({"source": selected["source"], "destination": destination, "kind": selected["kind"]})
	for delivery: Dictionary in construction_deliveries:
		if mining.construction.receive(delivery["destination"], delivery["kind"]):
			mining.remove_one_nugget(delivery["source"], delivery["kind"])
			transported.emit(delivery["source"], delivery["destination"], delivery["kind"])
	if transfers.is_empty() and sales.is_empty() and construction_deliveries.is_empty():
		return
	for transfer in transfers:
		mining.remove_one_nugget(transfer["source"], transfer["kind"])
		transported.emit(transfer["source"], transfer.get("destination", grid.sale_cell), transfer["kind"])
	for transfer in sales:
		mining.remove_one_nugget(transfer["source"], transfer["kind"])
		transported.emit(transfer["source"], transfer.get("destination", grid.sale_cell), transfer["kind"])
		sale_completed.emit(transfer["kind"])
	for transfer in transfers:
		if mining.occupied_by_saw(transfer["destination"]):
			mining.saws.receive(transfer["destination"],transfer["kind"])
			continue
		if mining.occupied_by_furnace(transfer["destination"]):
			mining.furnaces.receive(transfer["destination"], transfer["kind"])
			continue
		if mining.occupied_by_compactor(transfer["destination"]):
			mining.compactors.receive(transfer["destination"], transfer["kind"])
			continue
		if launchers != null and launchers.launchers.has(transfer["destination"]):
			launchers.receive(transfer["destination"], transfer["kind"])
			continue
		var items: Dictionary = mining.items_for(transfer["kind"])
		items[transfer["destination"]] = 1
	changed.emit()
