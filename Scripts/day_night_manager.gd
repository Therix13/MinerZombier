extends RefCounted

signal changed

const NIGHT_REWARD: int = 0
const TUTORIAL_EXPANSION_BONUS: int = 0
const TUTORIAL_COAL_CELL := Vector2i(14, 0)
const TUTORIAL_NEW_VEIN_CELL := Vector2i(14, 1)
const TUTORIAL_ORE_CELL := Vector2i(15, 0)
const TUTORIAL_FUSION_CELL := Vector2i(15, 1)
const TUTORIAL_BRASS_CELL := Vector2i(14, 2)
const TUTORIAL_FURNACE_CELL := Vector2i(16, 1)
const TUTORIAL_SALES_TARGET: int = 5
const TUTORIAL_TITLES := [
	"Tu primera veta", "Pepitas hasta nivel 4", "Fusiona tus vetas",
	"Una veta de nivel 3", "Una veta de nivel 4", "El siguiente mineral",
	"Tu primera veta de latón", "Construye un horno", "Enciende el horno",
	"Tu primer lingote", "Lingotes hasta nivel 3", "Compra las defensas",
	"Construye un lanzapepitas", "Carga la munición", "Comienza la primera noche",
	"¡Tutorial completado!",
]
const TUTORIAL_LAST_STEP: int = 15
const TUTORIAL_DISPLAY_STEPS: int = 15

# A budget stays earned while the player places its batch of veins.
var funded_steps: Dictionary = {}

var coal_cell := TUTORIAL_COAL_CELL
var brass_cell := TUTORIAL_BRASS_CELL
var furnace_cell := TUTORIAL_FURNACE_CELL
var refreshing_tutorial: bool = false

var day: int = 1
var is_night: bool = false
var defeated: bool = false
var tutorial_step: int = 0
var fusion_taught: bool = false
var vein_fusion_taught: bool = false
var barrier_broken: bool = false
var fusion_sold: bool = false
var brass_ingot_sold: bool = false
var brass_ingot_created: bool = false
var brass_ingot_3_created: bool = false
var level3_sold: bool = false
var level4_sold: bool = false
var coal_sold: int = 0
var expansion_bonus_granted: bool = false
var free_launcher_available: bool = false
var tutorial_skipped: bool = false
var grid: RefCounted
var mining: RefCounted
var conveyors: RefCounted
var launchers: RefCounted
var economy: RefCounted

func setup(grid_manager: RefCounted, mining_manager: RefCounted, conveyor_manager: RefCounted, launcher_manager: RefCounted, economy_manager: RefCounted) -> void:
	grid = grid_manager
	mining = mining_manager
	conveyors = conveyor_manager
	launchers = launcher_manager
	economy = economy_manager
	economy.money_changed.connect(_on_money_changed)
	mining.resource_created.connect(_on_resource_created)
	mining.changed.connect(refresh_tutorial)
	mining.fusion_completed.connect(_on_fusion)
	mining.vein_fused.connect(_on_vein_fused)
	mining.sale_completed.connect(_on_sale)
	conveyors.sale_completed.connect(_on_sale)
	conveyors.changed.connect(refresh_tutorial)
	launchers.changed.connect(refresh_tutorial)
	refresh_tutorial()

func dispose() -> void:
	if mining != null:
		mining.resource_created.disconnect(_on_resource_created)
		mining.changed.disconnect(refresh_tutorial)
		mining.fusion_completed.disconnect(_on_fusion)
		mining.vein_fused.disconnect(_on_vein_fused)
		mining.sale_completed.disconnect(_on_sale)
	if conveyors != null:
		conveyors.changed.disconnect(refresh_tutorial)
		conveyors.sale_completed.disconnect(_on_sale)
	if launchers != null:
		launchers.changed.disconnect(refresh_tutorial)
	if economy != null:
		economy.money_changed.disconnect(_on_money_changed)
	grid = null
	mining = null
	conveyors = null
	launchers = null
	economy = null

func vein_lesson_active() -> bool:
	return is_tutorial_active() and tutorial_step == 2

func advanced_vein_lesson() -> bool:
	return is_tutorial_active() and tutorial_step in [3,4]

func target_vein_level() -> int:
	return {2:2,3:3,4:4}.get(tutorial_step,4)

func vein_fusion_targets() -> Array[Vector2i]:
	for tier in range(3,0,-1):
		var cells: Array[Vector2i] = []
		if mining.vein_level(coal_cell) == tier: cells.append(coal_cell)
		for cell: Vector2i in mining.coal_veins:
			if cell != coal_cell and mining.vein_level(cell) == tier: cells.append(cell)
		if cells.size() >= 2 and mining.can_fuse_veins(cells[1],cells[0]): return [cells[1],cells[0]]
	return []

func next_vein_cell() -> Vector2i:
	for cell: Vector2i in [Vector2i(14,1),Vector2i(16,1),Vector2i(14,2),Vector2i(16,2),Vector2i(16,0),Vector2i(15,2)]:
		if mining.can_place_vein(cell): return cell
	for cell: Vector2i in grid.owned_tiles:
		if mining.can_place_vein(cell): return cell
	return Vector2i(-999,-999)

func needs_ammo_vein() -> bool:
	return false

func tutorial_mining_cell() -> Vector2i:
	return coal_cell

func tutorial_output_cell() -> Vector2i:
	var cell: Vector2i = tutorial_mining_cell()
	var data: Dictionary = mining.veins_for(mining.vein_at(cell)).get(cell,{"direction":1})
	return cell + mining.DIRECTIONS[int(data["direction"])]

func platforms_ready() -> bool:
	return grid.defense_tiles.size() >= 2

func _on_vein_fused(cell: Vector2i) -> void:
	if mining.vein_at(cell) == "coal" and mining.vein_level(cell) >= 2: vein_fusion_taught = true
	refresh_tutorial()

func _on_fusion(kind: String) -> void:
	if kind.begins_with("coal_") and "ingot" not in kind: fusion_taught = true
	refresh_tutorial()

func _on_resource_created(kind: String) -> void:
	if not kind.begins_with("brass_ingot"): return
	brass_ingot_created = true
	if mining.ore_level(kind) >= 3: brass_ingot_3_created = true
	# Furnace output is announced before its slots finish updating.
	refresh_tutorial.call_deferred()

func furnace_ready() -> bool:
	return mining.furnaces != null and not mining.furnaces.machines.is_empty()

func furnace_fueled() -> bool:
	if brass_ingot_created: return true
	if not furnace_ready(): return false
	for data: Dictionary in mining.furnaces.machines.values():
		if int(data.get("fuel",0)) >= mining.furnaces.FUEL_COST or data.get("burning",false): return true
	return false

func _on_money_changed(_amount: int) -> void:
	# Refresh after the sale has finished updating the wallet.
	refresh_tutorial.call_deferred()

func _on_sale(kind: String) -> void:
	if kind == "coal_4": level4_sold = true
	if kind.begins_with("coal_") and "ingot" not in kind: fusion_sold = true
	if kind.begins_with("brass_ingot"): brass_ingot_sold = true
	if kind.get_slice("_",0) == "coal" and "ingot" not in kind: coal_sold += 1
	refresh_tutorial()

func is_tutorial_active() -> bool:
	return not tutorial_skipped and tutorial_step < TUTORIAL_LAST_STEP and day == 1 and not is_night and not defeated

func skip_tutorial() -> void:
	if tutorial_skipped: return
	tutorial_skipped = true
	barrier_broken = true
	tutorial_step = TUTORIAL_LAST_STEP
	changed.emit()

func is_guided_tutorial_active() -> bool:
	return is_tutorial_active()

func tutorial_purchase_price() -> int:
	if tutorial_step == 1: return 100
	if tutorial_step in [5,6]: return economy.BRASS_VEIN_PRICE
	if tutorial_step == 7:
		if furnace_ready() or furnace_blueprint_exists(): return 0
		return mining.furnaces.PRICE if mining.furnaces != null else 350
	if tutorial_step in [2,3,4]:
		if not vein_fusion_targets().is_empty(): return 0
		if not funded_steps.has(tutorial_step): return {2:100,3:200,4:400}[tutorial_step]
		return economy.COAL_VEIN_PRICE
	if tutorial_step == 11: return 0 if platforms_ready() else economy.DEFENSE_TILE_PRICE
	if tutorial_step == 12:
		return 0 if launcher_ready() or launcher_blueprint_cell() != Vector2i(-999,-999) else economy.LAUNCHER_PRICE
	if tutorial_step == 13 and ammo_vein() == Vector2i(-999,-999): return economy.COAL_VEIN_PRICE
	return 0

func needs_tutorial_income() -> bool:
	return is_tutorial_active() and tutorial_step > 0 and not economy.can_afford(tutorial_purchase_price())

func income_level() -> int:
	return 4

func advanced_income() -> bool:
	return needs_tutorial_income()

func income_targets() -> Array[Vector2i]:
	# Prefer selling the requested tier, then fusing the highest available pair.
	var level: int = income_level()
	for tier in range(level, 0, -1):
		var kind: String = "coal" if tier == 1 else "coal_" + str(tier)
		var cells: Array[Vector2i] = []
		for cell: Vector2i in mining.items_for(kind):
			if grid.is_valid_cell(cell) and grid.owned_tiles.has(cell): cells.append(cell)
		if tier == level and not cells.is_empty(): return [cells[0], grid.sale_cell]
		if cells.size() >= 2: return [cells[1], cells[0]]
	if mining.nuggets_at(coal_output()) > 0:
		var staging: Array[Vector2i] = [TUTORIAL_FUSION_CELL, Vector2i(14, 1), Vector2i(16, 2)]
		for cell: Vector2i in grid.owned_tiles:
			if grid.is_valid_cell(cell) and cell not in [furnace_cell,brass_cell] and not staging.has(cell): staging.append(cell)
		for cell: Vector2i in staging:
			if cell not in [coal_output(),furnace_cell,brass_cell] and mining.can_move_nugget(cell): return [coal_output(), cell]
		return [coal_output(),grid.sale_cell]
	return [coal_cell]

func allows_action(action: String) -> bool:
	return true

func tutorial_display_step() -> int:
	return mini(TUTORIAL_DISPLAY_STEPS,tutorial_step + 1)

func tutorial_title() -> String:
	if advanced_vein_lesson(): return "Fusiona hasta nivel %d" % target_vein_level()
	if vein_lesson_active(): return "Fusiona tus vetas"
	return TUTORIAL_TITLES[clampi(tutorial_step, 0, TUTORIAL_LAST_STEP)]

func allows_world_press(cell: Vector2i, placing: String = "") -> bool:
	return true

func allows_interaction(kind: String, source: Vector2i, destination: Vector2i, dragged: bool) -> bool:
	return true

func ammo_damage() -> float:
	var total: float = 0.0
	for launcher in launchers.launchers.values():
		var ammo: Array = launcher["ammo"]
		for kind in ammo:
			total += launchers.ammo_damage(kind)
	return total

func has_ammo() -> bool:
	for cell: Vector2i in launchers.launchers:
		var launcher: Dictionary = launchers.launchers[cell]
		if launchers.is_active_position(cell) and not (launcher["ammo"] as Array).is_empty():
			return true
	return false

func refresh_tutorial() -> void:
	if mining == null or economy == null or refreshing_tutorial or tutorial_skipped or day != 1 or is_night or defeated: return
	refreshing_tutorial = true
	sync_tutorial_cells()
	while tutorial_step < TUTORIAL_LAST_STEP:
		if tutorial_step in [2,3,4] and economy.coins >= int({2:100,3:200,4:400}[tutorial_step]):
			funded_steps[tutorial_step] = true
		var completed: bool = false
		match tutorial_step:
			0: completed = not mining.coal_veins.is_empty()
			1: completed = level4_sold and economy.coins >= 100
			2: completed = not mining.coal_veins.is_empty() and mining.vein_level(coal_cell) >= 2
			3: completed = not mining.coal_veins.is_empty() and mining.vein_level(coal_cell) >= 3
			4: completed = not mining.coal_veins.is_empty() and mining.vein_level(coal_cell) >= 4
			5: completed = economy.coins >= economy.BRASS_VEIN_PRICE or not mining.brass_veins.is_empty()
			6: completed = not mining.brass_veins.is_empty()
			7: completed = furnace_ready()
			8: completed = furnace_fueled()
			9: completed = brass_ingot_created
			10: completed = brass_ingot_3_created
			11: completed = platforms_ready()
			12: completed = launcher_ready()
			13: completed = launcher_full()
		if not completed: break
		tutorial_step += 1
	refreshing_tutorial = false
	changed.emit()

func coal_output() -> Vector2i:
	var data: Dictionary = mining.coal_veins.get(coal_cell,{"direction":1})
	return coal_cell + mining.DIRECTIONS[int(data["direction"])]

func sync_tutorial_cells() -> void:
	for material: String in ["coal","brass"]:
		var veins: Dictionary = mining.veins_for(material)
		var selected: Vector2i = coal_cell if material == "coal" else brass_cell
		for cell: Vector2i in veins:
			if not veins.has(selected) or mining.vein_level(cell) > mining.vein_level(selected): selected = cell
		if material == "coal": coal_cell = selected
		else: brass_cell = selected
	if mining.furnaces != null and not mining.furnaces.machines.is_empty():
		if not mining.furnaces.machines.has(furnace_cell): furnace_cell = mining.furnaces.machines.keys()[0]
	elif mining.construction != null:
		for cell: Vector2i in mining.construction.plans:
			if mining.construction.plans[cell]["item"] == "furnace": furnace_cell = cell

func tutorial_text() -> String:
	match tutorial_step:
		0: return "Compra una veta de carbón."
		1: return "Puedes fusionar pepitas hasta Nv. 4.\nVéndelas hasta reunir 100 de oro."
		5: return "Reúne 500 de oro para una veta de latón."
		6: return "Reúne 500 de oro." if needs_tutorial_income() else "Compra y coloca una veta de latón."
		7:
			if needs_tutorial_income(): return "Vende pepitas hasta reunir 350 de oro."
			if furnace_blueprint_exists(): return "Entrega 2 pepitas de carbón Nv. 4 al plano."
			return "Compra y coloca el plano del horno."
		8: return "Carga 20 de combustible en el horno.\nPuedes usar carbón de cualquier nivel."
		9:
			if mining.furnaces != null:
				var data: Dictionary = mining.furnaces.machines.get(furnace_cell,{})
				if not data.get("burning",false) and int(data.get("fuel",0)) < mining.furnaces.FUEL_COST: return "Carga carbón: cada lingote consume 20 de combustible."
				if not str(data.get("input","")).is_empty(): return "Espera a que se cree el lingote."
			return "Fusiona latón hasta Nv. 4.\nMételo en el horno para crear un lingote."
	if tutorial_step in [2,3,4]:
		if needs_tutorial_income():
			return "Vende carbón Nv. 4 hasta reunir %d de oro." % tutorial_purchase_price()
		var goal: int = target_vein_level()
		if not vein_fusion_targets().is_empty():
			return "Fusiona las vetas marcadas hasta Nv. %d." % goal
		if tutorial_step == 2: return "Compra otra veta de carbón.\nFusiona las dos para crear una Nv. 2."
		var count: int = 2 if tutorial_step == 3 else 4
		return "Coloca %d vetas manteniendo Shift.\nFusiónalas hasta Nv. %d." % [count,goal]
	if tutorial_step == 10:
		return "Fusiona lingotes de latón hasta Nv. 3.\nCada lingote nuevo consume 20 de combustible."
	if tutorial_step == 11:
		return "Reúne 1000 de oro para las plataformas." if needs_tutorial_income() else "Compra las plataformas de defensa."
	if tutorial_step == 12:
		if needs_tutorial_income(): return "Reúne 200 de oro para el lanzapepitas."
		if launcher_blueprint_cell() != Vector2i(-999,-999): return "Entrega un lingote de latón Nv. 3 y uno Nv. 1."
		if not launchers.launchers.is_empty(): return "Mueve el lanzapepitas a una plataforma."
		return "Coloca el plano del lanzapepitas en una plataforma."
	if tutorial_step == 13: return "Llena el lanzapepitas con 5 pepitas Nv. 1."
	if tutorial_step == 14: return "Pulsa INICIAR NOCHE."
	return "¡Tutorial completado!"

func income_instruction() -> String:
	var targets: Array[Vector2i] = income_targets()
	if targets.size() == 2:
		var kind: String = mining.nugget_type(targets[0])
		var tier: int = mining.ore_level(kind)
		if targets[1] == grid.sale_cell:
			if tier == 4: return "Vende la pepita Nv. 4 marcada: vale 50 de oro."
			return "Puedes vender la pepita marcada para liberar espacio, o seguir fusionándola hasta Nv. 4."
		if mining.can_fuse(targets[0],targets[1]): return "Fusiona las pepitas marcadas: Nv. %d → Nv. %d." % [tier,tier+1]
		return "Mueve la pepita a la casilla marcada para despejar la salida y seguir fusionando."
	return "Extrae carbón y fusiona pares hasta Nv. 4. Puedes vender pepitas sueltas para liberar espacio."

func furnace_blueprint_exists() -> bool:
	return mining.construction != null and mining.construction.plans.has(furnace_cell)

func resource_targets(material: String, tier: int, destination: Vector2i) -> Array[Vector2i]:
	for level in range(tier,0,-1):
		var kind: String = material + ("" if level == 1 else "_" + str(level))
		var cells: Array[Vector2i] = []
		for cell: Vector2i in mining.items_for(kind):
			if grid.owned_tiles.has(cell): cells.append(cell)
		if level == tier and not cells.is_empty(): return [cells[0],destination]
		if cells.size() >= 2: return [cells[1],cells[0]]
	var vein: Vector2i = brass_cell if material == "brass" else coal_cell
	var data: Dictionary = mining.veins_for(material).get(vein,{"direction":1})
	var output: Vector2i = vein + mining.DIRECTIONS[int(data["direction"])]
	if mining.nuggets_at(output) > 0:
		return park_resource(output,material)
	return [vein]

func park_resource(source: Vector2i, material: String = "brass") -> Array[Vector2i]:
	for at: Vector2i in grid.owned_tiles:
		if at != source and at != grid.sale_cell and at not in [coal_cell,brass_cell,furnace_cell] and grid.is_valid_cell(at) and mining.can_move_nugget(at): return [source,at]
	for kind: String in mining.ORE_KINDS:
		if kind.get_slice("_",0) == material or "_ingot" in kind: continue
		for at: Vector2i in mining.items_for(kind): return [at,grid.sale_cell]
	if mining.nuggets_at(source) > 0: return [source,grid.sale_cell]
	return []

func workshop_targets() -> Array[Vector2i]:
	if needs_tutorial_income(): return income_targets()
	if tutorial_step == 6:
		if mining.can_place_vein(brass_cell): return [brass_cell]
		return []
	if tutorial_step == 7:
		if furnace_blueprint_exists(): return resource_targets("coal",4,furnace_cell)
		if mining.can_move_nugget(furnace_cell): return [furnace_cell]
		return []
	if tutorial_step == 8: return resource_targets("coal",4,furnace_cell)
	if tutorial_step == 9: return smelting_targets()
	if tutorial_step == 10: return ingot_targets(3)
	if tutorial_step == 12:
		var plan: Vector2i = launcher_blueprint_cell()
		if plan != Vector2i(-999,-999):
			var delivered: Dictionary = mining.construction.plans[plan]["delivered"]
			return ingot_targets(3,plan) if int(delivered.get("brass_ingot_3",0)) < 1 else ingot_targets(1,plan)
		for cell: Vector2i in launchers.launchers:
			if not launchers.is_active_position(cell): return [cell,grid.defense_cell("left")]
		return [grid.defense_cell("left")]
	if tutorial_step == 13: return ammo_targets()
	return []

func launcher_ready() -> bool:
	for cell: Vector2i in launchers.launchers:
		if launchers.is_active_position(cell): return true
	return false

func launcher_full() -> bool:
	for cell: Vector2i in launchers.launchers:
		if launchers.is_active_position(cell) and launchers.launchers[cell]["ammo"].size() >= launchers.capacity: return true
	return false

func launcher_blueprint_cell() -> Vector2i:
	if mining.construction != null:
		for cell: Vector2i in mining.construction.plans:
			if mining.construction.plans[cell]["item"] == "launcher": return cell
	return Vector2i(-999,-999)

func ammo_vein() -> Vector2i:
	for material: String in ["coal","brass"]:
		for cell: Vector2i in mining.veins_for(material):
			if mining.vein_level(cell) == 1: return cell
	return Vector2i(-999,-999)

func ammo_targets() -> Array[Vector2i]:
	var weapon: Vector2i = grid.defense_cell("left")
	for cell: Vector2i in launchers.launchers:
		if launchers.is_active_position(cell) and launchers.can_receive(cell):
			weapon = cell
			break
	for material: String in ["coal","brass"]:
		for cell: Vector2i in mining.items_for(material): return [cell,weapon]
	var vein: Vector2i = ammo_vein()
	if vein == Vector2i(-999,-999): return [next_vein_cell()]
	var data: Dictionary = mining.veins_for(mining.vein_at(vein))[vein]
	var output: Vector2i = vein + mining.DIRECTIONS[int(data["direction"])]
	if mining.nuggets_at(output) > 0: return park_resource(output)
	return [vein]

func smelting_targets() -> Array[Vector2i]:
	if not furnace_ready(): return []
	var data: Dictionary = mining.furnaces.machines[furnace_cell]
	if not str(data.get("output","")).is_empty():
		var output: Vector2i = furnace_cell + mining.furnaces.DIRECTIONS[int(data.get("direction",0))]
		if mining.nuggets_at(output) > 0: return park_resource(output)
		return [furnace_cell]
	if not data.get("burning",false) and int(data.get("fuel",0)) < mining.furnaces.FUEL_COST:
		return resource_targets("coal",4,furnace_cell)
	if not str(data.get("input","")).is_empty(): return [furnace_cell]
	return resource_targets("brass",4,furnace_cell)

func ingot_targets(tier: int, destination := Vector2i(-999,-999)) -> Array[Vector2i]:
	for level in range(tier,0,-1):
		var kind: String = "brass_ingot" + ("" if level == 1 else "_" + str(level))
		var cells: Array[Vector2i] = []
		for cell: Vector2i in mining.items_for(kind):
			if grid.owned_tiles.has(cell): cells.append(cell)
		if level == tier and destination != Vector2i(-999,-999) and not cells.is_empty(): return [cells[0],destination]
		if cells.size() >= 2: return [cells[1],cells[0]]
	return smelting_targets()

func workshop_text() -> String:
	return tutorial_text()

func resource_instruction(targets: Array[Vector2i], tier: int) -> String:
	if targets.size() == 1: return "Pulsa la veta marcada para extraer."
	if targets.size() == 2:
		if mining.can_fuse(targets[0],targets[1]): return "Fusiona las pepitas marcadas hasta Nv. %d." % tier
		if targets[1] == grid.sale_cell: return "Puedes vender la pepita marcada para liberar espacio, o fusionarla por tu cuenta."
		if targets[1] in [furnace_cell,grid.defense_cell("left")]: return "Arrastra el material al destino marcado."
		return "Despeja la salida: mueve el material a la casilla marcada."
	return "Espera a que termine el proceso."

func needs_defense_warning() -> bool:
	return day == 4 and not is_night and not defeated and launchers.launchers.size() < 2

func can_start_night() -> bool:
	if is_tutorial_active() and (tutorial_step < 14 or not launcher_full()): return false
	return not is_night and not defeated and not launchers.launchers.is_empty() and has_ammo()

func start_night() -> bool:
	if not can_start_night() or (day == 1 and not barrier_broken):
		return false
	if is_tutorial_active(): tutorial_step = TUTORIAL_LAST_STEP
	is_night = true
	changed.emit()
	return true

func complete_night() -> void:
	if not is_night:
		return
	is_night = false
	day += 1
	changed.emit()

func lose_night() -> void:
	if not is_night:
		return
	is_night = false
	defeated = true
	changed.emit()

func use_free_launcher() -> void:
	if free_launcher_available:
		free_launcher_available = false
		changed.emit()
