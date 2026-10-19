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
const TUTORIAL_ACTIONS := [
	["buy_coal", "place_coal"], ["mine_coal", "sell_coal"],
	["mine_coal", "fuse", "sell_fused"], ["buy_coal", "place_coal", "fuse_veins"],
	["buy_coal", "place_coal", "fuse_veins"], ["buy_brass", "place_brass"],
	["buy_furnace", "place_furnace", "deliver"], ["smelt", "deliver", "fuse", "sell_fused"],
	["unlock_defense"], ["buy_launcher", "place_launcher"], ["mine_brass", "load_ammo"], ["start_night"],
]
const TUTORIAL_TITLES := [
	"Tu primera veta", "Del carbón a las monedas", "Fusiona y vende",
	"Fusiona tus vetas", "Vetas hasta nivel 4", "Tu primera veta de latón",
	"Construye tu horno", "Del latón al lingote", "Plataformas de defensa",
	"Tu primer Lanzapepitas", "Carga la munición", "¡Todo listo!",
]
const TUTORIAL_LAST_STEP: int = 11
const TUTORIAL_DISPLAY_STEPS: int = 11

var coal_cell := TUTORIAL_COAL_CELL
var brass_cell := TUTORIAL_BRASS_CELL
var furnace_cell := TUTORIAL_FURNACE_CELL
var research_boosts: Dictionary = {}
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
var level3_sold: bool = false
var level4_sold: bool = false
var coal_sold: int = 0
var expansion_bonus_granted: bool = false
var free_launcher_available: bool = false
var research_tutorial_pending: bool = false
var tutorial_skipped: bool = false
var progression: RefCounted
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
	mining.changed.connect(refresh_tutorial)
	mining.fusion_completed.connect(_on_fusion)
	mining.vein_fused.connect(_on_vein_fused)
	mining.sale_completed.connect(_on_sale)
	conveyors.sale_completed.connect(_on_sale)
	conveyors.changed.connect(refresh_tutorial)
	launchers.changed.connect(refresh_tutorial)
	refresh_tutorial()

func set_progression(player_progression: RefCounted) -> void:
	if progression != null:
		progression.research_unlocked.disconnect(_on_research_unlocked)
	progression = player_progression
	progression.research_unlocked.connect(_on_research_unlocked)

func dispose() -> void:
	if progression != null:
		progression.research_unlocked.disconnect(_on_research_unlocked)
	progression = null
	if mining != null:
		mining.changed.disconnect(refresh_tutorial)
		mining.fusion_completed.disconnect(_on_fusion)
		mining.vein_fused.disconnect(_on_vein_fused)
		mining.sale_completed.disconnect(_on_sale)
	if conveyors != null:
		conveyors.changed.disconnect(refresh_tutorial)
		conveyors.sale_completed.disconnect(_on_sale)
	if launchers != null:
		launchers.changed.disconnect(refresh_tutorial)
	grid = null
	mining = null
	conveyors = null
	launchers = null
	economy = null

func vein_lesson_active() -> bool:
	return is_tutorial_active() and tutorial_step == 3 and not vein_fusion_taught

func advanced_vein_lesson() -> bool:
	return is_tutorial_active() and tutorial_step == 4

func target_vein_level() -> int:
	return mini(4, mining.vein_level(coal_cell) + 1)

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
	return Vector2i(-999,-999)

func needs_ammo_vein() -> bool:
	return false

func tutorial_mining_cell() -> Vector2i:
	return brass_cell if tutorial_step == 10 else coal_cell

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

func _on_sale(kind: String) -> void:
	if kind.begins_with("coal_") and "ingot" not in kind: fusion_sold = true
	if kind.begins_with("brass_ingot"): brass_ingot_sold = true
	if kind.get_slice("_",0) == "coal" and "ingot" not in kind: coal_sold += 1
	refresh_tutorial()

func is_tutorial_active() -> bool:
	return not tutorial_skipped and day == 1 and not is_night and not defeated

func is_research_tutorial_active() -> bool:
	return false

func skip_tutorial() -> void:
	if tutorial_skipped: return
	tutorial_skipped = true
	barrier_broken = true
	tutorial_step = TUTORIAL_LAST_STEP
	research_tutorial_pending = false
	changed.emit()

func is_guided_tutorial_active() -> bool:
	return is_tutorial_active() or is_research_tutorial_active()

func _on_research_unlocked(_research_id: String) -> void:
	refresh_tutorial()

func tutorial_purchase_price() -> int:
	if vein_lesson_active(): return 0 if mining.coal_veins.has(TUTORIAL_NEW_VEIN_CELL) else economy.COAL_VEIN_PRICE
	if advanced_vein_lesson(): return 0 if not vein_fusion_targets().is_empty() else economy.COAL_VEIN_PRICE
	match tutorial_step:
		3: return economy.COAL_VEIN_PRICE
		5: return economy.BRASS_VEIN_PRICE
		6: return 0 if furnace_blueprint_exists() else 350
		8: return economy.DEFENSE_TILE_PRICE
		9: return economy.LAUNCHER_PRICE
	return 0

func needs_tutorial_income() -> bool:
	return is_tutorial_active() and tutorial_step in [3,4,5,6,8,9] and not economy.can_afford(tutorial_purchase_price())

func income_level() -> int:
	return mini(4, mining.vein_level(coal_cell)) if tutorial_step >= 4 else 2

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
	for launcher in launchers.launchers.values():
		if not (launcher["ammo"] as Array).is_empty():
			return true
	return false

func refresh_tutorial() -> void:
	if refreshing_tutorial or tutorial_skipped or day != 1 or is_night or defeated: return
	refreshing_tutorial = true
	sync_tutorial_cells()
	while tutorial_step < TUTORIAL_LAST_STEP:
		if tutorial_step >= 5: grant_research_experience("brass")
		if tutorial_step >= 6: grant_research_experience("furnace")
		var completed: bool = false
		match tutorial_step:
			0: completed = not mining.coal_veins.is_empty()
			1: completed = coal_sold >= TUTORIAL_SALES_TARGET
			2: completed = fusion_sold
			3: completed = vein_fusion_taught or (not mining.coal_veins.is_empty() and mining.vein_level(coal_cell) >= 2)
			4: completed = not mining.coal_veins.is_empty() and mining.vein_level(coal_cell) >= 4
			5: completed = not mining.brass_veins.is_empty()
			6: completed = mining.furnaces != null and not mining.furnaces.machines.is_empty()
			7: completed = brass_ingot_sold
			8: completed = platforms_ready()
			9: completed = not launchers.launchers.is_empty()
			10: completed = ammo_damage() >= 2.0
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

func missing_researches(id: String, result: Array[String]) -> void:
	if progression == null or progression.has_research(id) or result.has(id): return
	for prerequisite: String in progression.RESEARCHES[id]["requires"]: missing_researches(prerequisite,result)
	result.append(id)

func research_to_learn() -> String:
	var id: String = "brass" if tutorial_step == 5 else ("furnace" if tutorial_step == 6 else "")
	if id.is_empty(): return ""
	var chain: Array[String] = []
	missing_researches(id,chain)
	return "" if chain.is_empty() else chain[0]

func grant_research_experience(id: String) -> void:
	if progression == null or research_boosts.has(id): return
	research_boosts[id] = true
	var chain: Array[String] = []
	missing_researches(id,chain)
	var required_level: int = progression.level
	var required_points: int = 0
	for research_id: String in chain:
		var data: Dictionary = progression.RESEARCHES[research_id]
		required_level = maxi(required_level,int(data["level"]))
		required_points += int(data["cost"])
	while progression.level < required_level or progression.research_points < required_points:
		progression.add_experience(progression.experience_to_next_level() - progression.experience)

func tutorial_text() -> String:
	if tutorial_step >= 5: return workshop_text()
	if advanced_vein_lesson():
		var goal: int = target_vein_level()
		if needs_tutorial_income(): return "Objetivo: veta Nv. %d. %s" % [goal, income_instruction()]
		var pair: Array[Vector2i] = vein_fusion_targets()
		if not pair.is_empty():
			var tier: int = mining.vein_level(pair[0])
			var next_goal: String = "Así crearás la veta Nv. %d." % goal if tier+1 == goal else "Prepara otro par hasta tener 2 vetas Nv. %d para crear la de Nv. %d." % [goal-1,goal]
			return "Arrastra la veta marcada sobre la otra: 2 vetas Nv. %d → 1 Nv. %d. %s" % [tier,tier+1,next_goal]
		return "Para crear una veta Nv. %d necesitas 2 vetas Nv. %d. Compra vetas Nv. 1 y fusiona pares iguales; coloca la siguiente en la casilla dorada." % [goal,goal-1]
	if needs_ammo_vein(): return "Compra una veta de Nv. 1 para producir munición básica." if not needs_tutorial_income() else "Vende pepitas para comprar una veta de Nv. 1: el arma solo acepta munición de Nv. 1."
	if vein_lesson_active() and not needs_tutorial_income():
		if mining.coal_veins.has(TUTORIAL_NEW_VEIN_CELL): return "Arrastra la segunda veta sobre la primera: 2 vetas del mismo material y nivel crean una superior. Puedes llegar hasta Nv. 4."
		return "Compra otra veta de carbón y colócala en la casilla dorada para fusionar las minas."
	if needs_tutorial_income(): return income_instruction()
	match tutorial_step:
		0: return "Compra y coloca una veta de carbón. Fusionando 2 pepitas del mismo material y nivel puedes llegar hasta Nv. 4."
		1: return "Arrastra la pepita al cofre. Después aprenderás a fusionarlas hasta Nv. 4." if mining.nuggets_at(coal_output()) > 0 else "Primero extrae y vende 5 pepitas de carbón Nv. 1. Luego aprenderás a fusionarlas hasta Nv. 4."
		2:
			if mining.nugget_type(TUTORIAL_FUSION_CELL) == "coal_2":
				return "Véndela en el cofre: vale %d monedas; una de Nv. 1 vale %d. Fusionando pares iguales puedes seguir hasta Nv. 4." % [economy.sale_value("coal_2"), economy.sale_value("coal")]
			if mining.nuggets_at(coal_output()) > 0:
				return "Arrástrala a la casilla dorada. Siempre se fusionan 2 pepitas del mismo material y nivel, hasta Nv. 4." if mining.nuggets_at(TUTORIAL_FUSION_CELL) == 0 else "Arrástrala sobre la otra: 2 de Nv. 1 crean 1 de Nv. 2. La misma regla se repite hasta Nv. 4."
			return "2 pepitas del mismo material y nivel crean una del siguiente nivel, hasta Nv. 4. Ahora combina 2 de Nv. 1 para crear tu primera Nv. 2."
		3: return "Compra una segunda veta de carbón y fusiónala con la primera."
		4: return "Fusiona vetas del mismo nivel hasta obtener una veta de Nv. 4."
		5: return "Compra las plataformas de defensa." if not platforms_ready() else "Compra el Lanzapepitas y colócalo en la plataforma dorada."
		6:
			if mining.nugget_type(tutorial_output_cell()) in ["coal_2", "coal_3", "coal_4"]: return "Vende la pepita de nivel alto en el cofre: el Lanzapepitas solo acepta Nv. 1."
			return "Extrae y carga 4 pepitas de Nv. 1 en el Lanzapepitas."
	return "¡Preparación lista! Inicia la primera noche."

func income_instruction() -> String:
	var level: int = income_level()
	var targets: Array[Vector2i] = income_targets()
	var purchase: String = {3:"otra veta (100 monedas)",4:"otra veta (100 monedas)",5:"la veta de latón (500 monedas)",6:"el horno (350 monedas)",8:"las plataformas (1000 monedas)",9:"el Lanzapepitas (200 monedas)"}.get(tutorial_step,"la siguiente compra")
	if targets.size() == 2:
		var kind: String = mining.nugget_type(targets[0])
		var from_level: int = mining.ore_level(kind)
		if targets[1] == grid.sale_cell: return "Vende la pepita Nv. %d en el cofre: vale %d monedas. Ahorra para %s." % [from_level,economy.sale_value(kind),purchase]
		if mining.can_fuse(targets[0],targets[1]): return "Fusiona las pepitas marcadas: 2 de Nv. %d → 1 de Nv. %d. Vende desde Nv. %d para comprar %s." % [from_level,from_level+1,level,purchase]
		return "Mueve la pepita a la casilla dorada. Fusiona hasta Nv. %d y vende para comprar %s." % [level,purchase]
	return "Recomendación: fusiona carbón hasta Nv. %d y vende para comprar %s. También puedes vender pepitas sueltas para liberar espacio." % [level,purchase]

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
		return park_resource(output)
	return [vein]

func park_resource(source: Vector2i) -> Array[Vector2i]:
	for at: Vector2i in grid.owned_tiles:
		if at != source and at != grid.sale_cell and at not in [coal_cell,brass_cell,furnace_cell] and grid.is_valid_cell(at) and mining.can_move_nugget(at): return [source,at]
	var material: String = "brass" if tutorial_step == 7 and mining.furnaces != null and int(mining.furnaces.machines.get(furnace_cell,{}).get("fuel",0)) > 0 else "coal"
	for kind: String in mining.ORE_KINDS:
		if kind.get_slice("_",0) == material or "_ingot" in kind: continue
		for at: Vector2i in mining.items_for(kind): return [at,grid.sale_cell]
	if mining.nuggets_at(source) > 0: return [source,grid.sale_cell]
	return []

func workshop_targets() -> Array[Vector2i]:
	if needs_tutorial_income(): return income_targets()
	match tutorial_step:
		5:
			if mining.nuggets_at(brass_cell) > 0: return park_resource(brass_cell)
		6:
			if furnace_blueprint_exists(): return resource_targets("coal",4,furnace_cell)
			if mining.nuggets_at(furnace_cell) > 0: return park_resource(furnace_cell)
		7:
			if mining.furnaces == null or not mining.furnaces.machines.has(furnace_cell):
				return resource_targets("coal",4,furnace_cell) if furnace_blueprint_exists() else []
			if not mining.items_for("brass_ingot").is_empty(): return [mining.items_for("brass_ingot").keys()[0],grid.sale_cell]
			var data: Dictionary = mining.furnaces.machines[furnace_cell]
			var out: Vector2i = furnace_cell + mining.DIRECTIONS[int(data["direction"])]
			if not str(data["input"]).is_empty() or not str(data["output"]).is_empty():
				if mining.nuggets_at(out) > 0: return park_resource(out)
				return []
			if int(data["fuel"]) == 0: return resource_targets("coal",4,furnace_cell)
			return resource_targets("brass",4,furnace_cell)
		10: return resource_targets("brass",1,grid.defense_cell("left"))
	return []

func workshop_text() -> String:
	var research_id: String = research_to_learn()
	if not research_id.is_empty(): return "Ya tienes la EXP para esta lección. En Investigación, desbloquea %s antes de comprar. Puedes vender o fusionar pepitas libremente." % progression.RESEARCHES[research_id]["name"]
	if needs_tutorial_income(): return income_instruction()
	match tutorial_step:
		5: return "Compra la veta de latón por 500 monedas y colócala en la casilla dorada."
		6:
			if not furnace_blueprint_exists(): return "Compra el plano del horno y colócalo en la casilla dorada. Necesita 2 pepitas de carbón Nv. 4 para construirse."
			var delivered: int = int(mining.construction.plans[furnace_cell]["delivered"].get("coal_4",0))
			return "Entrega carbón Nv. 4 al plano: %d / 2. %s" % [delivered,resource_instruction(workshop_targets(),4)]
		7:
			if mining.furnaces == null or not mining.furnaces.machines.has(furnace_cell): return "Necesitas un horno para fundir el latón. Puedes reconstruirlo y reorganizar la mina libremente."
			var data: Dictionary = mining.furnaces.machines[furnace_cell]
			if not mining.items_for("brass_ingot").is_empty(): return "¡Tu primer lingote de latón! Véndelo en el cofre por 150 monedas."
			if not str(data["input"]).is_empty() or not str(data["output"]).is_empty(): return "El horno tarda 4 segundos en fundir el latón. Deja libre su salida para que salga el lingote."
			if int(data["fuel"]) == 0: return "Añade carbón Nv. 4 al horno: se consume y aporta 20 de combustible. " + resource_instruction(workshop_targets(),4)
			return "Fusiona latón hasta Nv. 4 y entrégalo al horno. Puedes vender pepitas sueltas para liberar espacio o seguir fusionándolas. " + resource_instruction(workshop_targets(),4)
		8: return "Compra las plataformas de defensa por 1000 monedas para colocar el Lanzapepitas."
		9: return "Compra el Lanzapepitas por 200 monedas y colócalo en la plataforma dorada."
		10: return "Extrae 2 pepitas de latón Nv. 1 y cárgalas en el Lanzapepitas. " + resource_instruction(workshop_targets(),1)
	return "¡Todo listo! La cerca cede: comienza la noche 1."

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
	return not is_night and not defeated and not is_research_tutorial_active() and not launchers.launchers.is_empty() and has_ammo()

func start_night() -> bool:
	if not can_start_night() or (is_tutorial_active() and not barrier_broken):
		return false
	is_night = true
	changed.emit()
	return true

func complete_night() -> void:
	if not is_night:
		return
	is_night = false
	day += 1
	if day == 2:
		research_tutorial_pending = false
	if progression != null:
		progression.award_night()
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
