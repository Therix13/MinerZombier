extends RefCounted

signal changed

const NIGHT_REWARD: int = 0
const TUTORIAL_EXPANSION_BONUS: int = 0
const TUTORIAL_COAL_CELL := Vector2i(14, 0)
const TUTORIAL_ORE_CELL := Vector2i(15, 0)
const TUTORIAL_FUSION_CELL := Vector2i(15, 1)
const TUTORIAL_SALES_TARGET: int = 5
const TUTORIAL_ACTIONS := [
	["buy_coal", "place_coal"],
	["mine_coal", "sell_coal"],
	["mine_coal", "fuse", "sell_fused"],
	["expand"],
	["unlock_defense"],
	["buy_launcher", "place_launcher"],
	["mine_coal", "load_ammo"],
	["start_night"],
]
const TUTORIAL_TITLES := [
	"Tu primera veta", "Del carbón a las monedas", "Fusiona y vende",
	"Haz sitio para crecer", "Prepara las defensas", "Tu primer Lanzapepitas",
	"Carga la munición", "¡Todo listo!",
]
const TUTORIAL_LAST_STEP: int = 7

var day: int = 1
var is_night: bool = false
var defeated: bool = false
var tutorial_step: int = 0
var fusion_taught: bool = false
var fusion_sold: bool = false
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

func _on_fusion(kind: String) -> void:
	if is_tutorial_active() and tutorial_step == 2 and kind == "coal_2":
		fusion_taught = true
		refresh_tutorial()

func _on_sale(kind: String) -> void:
	if is_tutorial_active() and tutorial_step == 2 and fusion_taught and kind == "coal_2": fusion_sold = true
	if kind == "coal":
		coal_sold += 1
	refresh_tutorial()
	if is_tutorial_active() and tutorial_step == 1:
		changed.emit()

func is_tutorial_active() -> bool:
	return not tutorial_skipped and day == 1 and not is_night and not defeated

func is_research_tutorial_active() -> bool:
	return not tutorial_skipped and research_tutorial_pending and day == 2 and not is_night and not defeated

func skip_tutorial() -> void:
	if tutorial_skipped: return
	tutorial_skipped = true
	tutorial_step = TUTORIAL_LAST_STEP
	research_tutorial_pending = false
	changed.emit()

func is_guided_tutorial_active() -> bool:
	return is_tutorial_active() or is_research_tutorial_active()

func _on_research_unlocked(_research_id: String) -> void:
	if is_research_tutorial_active():
		research_tutorial_pending = false
		changed.emit()

func tutorial_purchase_price() -> int:
	match tutorial_step:
		3: return economy.EXPANSION_PRICE
		4: return economy.DEFENSE_TILE_PRICE
		5: return economy.LAUNCHER_PRICE
	return 0

func needs_tutorial_income() -> bool:
	return is_tutorial_active() and tutorial_step in [3, 4, 5] and not economy.can_afford(tutorial_purchase_price())

func allows_action(action: String) -> bool:
	if action == "developer": return true
	if is_research_tutorial_active():
		return action == "research"
	if not is_tutorial_active():
		return true
	if needs_tutorial_income() and action in ["mine_coal", "sell_coal", "fuse", "sell_fused"]: return true
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
	return (allows_action("mine_coal") and cell == TUTORIAL_COAL_CELL and mining.nuggets_at(TUTORIAL_ORE_CELL) == 0) or ((allows_action("sell_coal") or allows_action("load_ammo") or allows_action("fuse")) and cell == TUTORIAL_ORE_CELL) or (allows_action("sell_fused") and cell == TUTORIAL_FUSION_CELL and mining.nugget_type(cell) == "coal_2")

func allows_interaction(kind: String, source: Vector2i, destination: Vector2i, dragged: bool) -> bool:
	if is_research_tutorial_active():
		return false
	if not is_tutorial_active():
		return true
	if kind == "vein":
		return allows_action("mine_coal") and source == TUTORIAL_COAL_CELL and source == destination and not dragged
	if kind == "nugget" and source == TUTORIAL_FUSION_CELL and dragged:
		return allows_action("sell_fused") and mining.nugget_type(source) == "coal_2" and destination == grid.sale_cell
	if kind == "nugget" and source == TUTORIAL_ORE_CELL and dragged:
		return (allows_action("fuse") and destination == TUTORIAL_FUSION_CELL) or (allows_action("sell_coal") and destination == grid.sale_cell) or (allows_action("load_ammo") and destination == grid.defense_cell("left"))
	return false

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
	if tutorial_skipped or day != 1 or is_night or defeated:
		return
	var previous: int = tutorial_step
	while tutorial_step < TUTORIAL_LAST_STEP:
		var completed: bool = false
		match tutorial_step:
			0:
				completed = not mining.coal_veins.is_empty()
			1:
				completed = coal_sold >= TUTORIAL_SALES_TARGET
			2: completed = fusion_sold
			3: completed = grid.cave_width >= 7 and grid.cave_height >= 5
			4: completed = grid.defense_tiles.size() >= 2
			5: completed = not launchers.launchers.is_empty()
			6: completed = ammo_damage() >= 2.0
		if not completed:
			break
		tutorial_step += 1
	if previous != tutorial_step:
		changed.emit()

func tutorial_text() -> String:
	if needs_tutorial_income():
		var missing: int = tutorial_purchase_price() - economy.coins
		return "Vende pepitas para reunir %d monedas más. Las de Nv. 2 valen %d." % [missing, economy.sale_value("coal_2")]
	match tutorial_step:
		0: return "Compra una veta de carbón y colócala en la casilla dorada."
		1: return "Arrastra la pepita al cofre." if mining.nuggets_at(TUTORIAL_ORE_CELL) > 0 else "Extrae y vende 5 pepitas de carbón."
		2:
			if mining.nugget_type(TUTORIAL_FUSION_CELL) == "coal_2":
				return "Véndela en el cofre: vale %d monedas; una de Nv. 1 vale %d." % [economy.sale_value("coal_2"), economy.sale_value("coal")]
			if mining.nuggets_at(TUTORIAL_ORE_CELL) > 0:
				return "Arrástrala a la casilla dorada." if mining.nuggets_at(TUTORIAL_FUSION_CELL) == 0 else "Arrástrala sobre la otra: 2 de Nv. 1 crean 1 de Nv. 2."
			return "Extrae 2 pepitas y combínalas. La de Nv. 2 se vende más cara."
		3: return "Amplía la base a 7 × 5."
		4: return "Compra las dos plataformas de defensa."
		5: return "Compra el Lanzapepitas y colócalo en la plataforma dorada."
		6: return "Extrae y carga 4 pepitas de Nv. 1 en el Lanzapepitas."
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
		research_tutorial_pending = not tutorial_skipped
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
