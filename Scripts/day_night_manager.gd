extends RefCounted

signal changed

const NIGHT_REWARD: int = 50
const TUTORIAL_EXPANSION_BONUS: int = 500

var day: int = 1
var is_night: bool = false
var defeated: bool = false
var tutorial_step: int = 0
var coal_sold: int = 0
var expansion_bonus_granted: bool = false
var free_launcher_available: bool = true
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

func dispose() -> void:
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
	while tutorial_step < 7:
		var completed: bool = false
		match tutorial_step:
			0:
				completed = not mining.coal_veins.is_empty()
			1:
				completed = coal_sold > 0
			2:
				completed = grid.cave_width >= 7 and grid.cave_height >= 5
			3:
				completed = not conveyors.belts.is_empty()
			4:
				completed = grid.defense_tiles.size() >= 2
			5:
				completed = not launchers.launchers.is_empty()
			6:
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
			return "Compra y coloca una veta de carbón."
		1:
			return "Extrae una pepita de carbón y véndela."
		2:
			return "Amplía la base a 7x5 en EXPANSION."
		3:
			return "Coloca tu primera cinta transportadora."
		4:
			return "Compra DESBLOQUEAR DEFENSAS."
		5:
			return "Coloca tu primer Lanzapapas gratuito."
		6:
			return "Carga munición para causar al menos 2 de daño."
	return "¡Preparación lista! Inicia la primera noche."

func can_start_night() -> bool:
	return not is_night and not defeated and not launchers.launchers.is_empty() and has_ammo() and (day > 1 or tutorial_step >= 7)

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
