extends RefCounted

signal changed

const NIGHT_REWARD: int = 50
const TUTORIAL_EXPANSION_BONUS: int = 500
const TUTORIAL_COAL_CELL := Vector2i(14, 0)
const TUTORIAL_ORE_CELL := Vector2i(15, 0)
const TUTORIAL_SALES_TARGET: int = 5
const TUTORIAL_ACTIONS := [
	["buy_coal", "place_coal"],
	["mine_coal", "sell_coal"],
	["expand"],
	["unlock_defense"],
	["buy_launcher", "place_launcher"],
	["mine_coal", "load_ammo"],
	["start_night"],
]
const TUTORIAL_TITLES := [
	"Tu primera veta", "Del carbón a las monedas", "Haz sitio para crecer",
	"Prepara las defensas", "Tu primer Lanzapepitas",
	"Carga la munición", "¡Todo listo!",
]
const TUTORIAL_LAST_STEP: int = 6

var day: int = 1
var is_night: bool = false
var defeated: bool = false
var tutorial_step: int = 0
var coal_sold: int = 0
var expansion_bonus_granted: bool = false
var free_launcher_available: bool = true
var research_tutorial_pending: bool = false
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

func _on_sale(kind: String) -> void:
	if kind == "coal":
		coal_sold += 1
	refresh_tutorial()
	if is_tutorial_active() and tutorial_step == 1:
		changed.emit()

func is_tutorial_active() -> bool:
	return day == 1 and not is_night and not defeated

func is_research_tutorial_active() -> bool:
	return research_tutorial_pending and day == 2 and not is_night and not defeated

func is_guided_tutorial_active() -> bool:
	return is_tutorial_active() or is_research_tutorial_active()

func _on_research_unlocked(_research_id: String) -> void:
	if is_research_tutorial_active():
		research_tutorial_pending = false
		changed.emit()

func allows_action(action: String) -> bool:
	if is_research_tutorial_active():
		return action == "research"
	if not is_tutorial_active():
		return true
	return action in TUTORIAL_ACTIONS[clampi(tutorial_step, 0, TUTORIAL_LAST_STEP)]

func tutorial_title() -> String:
	return TUTORIAL_TITLES[clampi(tutorial_step, 0, TUTORIAL_LAST_STEP)]

func allows_world_press(cell: Vector2i, placing: String = "") -> bool:
	if is_research_tutorial_active():
		return false
	if not is_tutorial_active():
		return true
	if placing == "coal":
		return allows_action("place_coal") and cell == TUTORIAL_COAL_CELL
	if placing == "belt":
		return false
	if placing == "launcher":
		return allows_action("place_launcher") and cell == grid.defense_cell("left")
	if not placing.is_empty():
		return false
	return (allows_action("mine_coal") and cell == TUTORIAL_COAL_CELL and mining.nuggets_at(TUTORIAL_ORE_CELL) == 0) or ((allows_action("sell_coal") or allows_action("load_ammo")) and cell == TUTORIAL_ORE_CELL)

func allows_interaction(kind: String, source: Vector2i, destination: Vector2i, dragged: bool) -> bool:
	if is_research_tutorial_active():
		return false
	if not is_tutorial_active():
		return true
	if kind == "vein":
		return allows_action("mine_coal") and source == TUTORIAL_COAL_CELL and source == destination and not dragged
	if kind == "nugget" and source == TUTORIAL_ORE_CELL and dragged:
		return (allows_action("sell_coal") and destination == grid.sale_cell) or (allows_action("load_ammo") and destination == grid.defense_cell("left"))
	return false

func ammo_damage() -> float:
	var total: float = 0.0
	for launcher in launchers.launchers.values():
		var ammo: Array = launcher["ammo"]
		for kind in ammo:
			total += (2.0 if kind == "brass" else 1.0) * launchers.damage_multiplier
	return total

func has_ammo() -> bool:
	for launcher in launchers.launchers.values():
		if not (launcher["ammo"] as Array).is_empty():
			return true
	return false

func refresh_tutorial() -> void:
	if day != 1 or is_night or defeated:
		return
	var previous: int = tutorial_step
	while tutorial_step < TUTORIAL_LAST_STEP:
		var completed: bool = false
		match tutorial_step:
			0:
				completed = not mining.coal_veins.is_empty()
			1:
				completed = coal_sold >= TUTORIAL_SALES_TARGET
			2:
				completed = grid.cave_width >= 7 and grid.cave_height >= 5
			3:
				completed = grid.defense_tiles.size() >= 2
			4:
				completed = not launchers.launchers.is_empty()
			5:
				completed = ammo_damage() >= 2.0
		if not completed:
			break
		tutorial_step += 1
		if tutorial_step == 2 and not expansion_bonus_granted:
			expansion_bonus_granted = true
			if not economy.developer_mode:
				economy.add(TUTORIAL_EXPANSION_BONUS)
	if previous != tutorial_step:
		changed.emit()

func tutorial_text() -> String:
	match tutorial_step:
		0:
			return "Compra una veta de carbón y colócala en la casilla dorada."
		1:
			if mining.nuggets_at(TUTORIAL_ORE_CELL) > 0:
				return "Arrastra la pepita hasta el cofre marcado para venderla."
			return "Extrae y vende 5 pepitas de carbón en el cofre."
		2:
			return "Has ganado 500 monedas extra. Amplía la base a 7 × 5."
		3:
			return "Desbloquea las dos plataformas para defender la entrada."
		4:
			return "Obtén tu Lanzapepitas gratuito y colócalo en la plataforma dorada."
		5:
			if mining.nuggets_at(TUTORIAL_ORE_CELL) > 0:
				return "Arrastra la pepita al Lanzapepitas marcado. Necesitas cargar 4 en total."
			return "Extrae carbón de tu veta y arrástralo al Lanzapepitas: 4 pepitas preparan la primera noche."
	return "¡Preparación lista! Inicia la primera noche."

func needs_defense_warning() -> bool:
	return day == 4 and not is_night and not defeated and launchers.launchers.size() < 2

func can_start_night() -> bool:
	return not is_night and not defeated and not is_research_tutorial_active() and not launchers.launchers.is_empty() and has_ammo() and (day > 1 or tutorial_step >= TUTORIAL_LAST_STEP)

func start_night() -> bool:
	if not can_start_night():
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
		research_tutorial_pending = true
	if progression != null:
		progression.award_night()
	economy.add(NIGHT_REWARD)
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
