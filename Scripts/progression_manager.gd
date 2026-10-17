extends RefCounted

signal changed
signal level_up(new_level: int)
signal technology_unlocked(technology_id: String)

const BASE_LEVEL_EXPERIENCE: int = 25
const LEVEL_EXPERIENCE_STEP: int = 15
const POINTS_PER_LEVEL: int = 1
const ZOMBIE_EXPERIENCE: int = 10
const SALE_EXPERIENCE := {"coal": 2, "brass": 3}
const TECHNOLOGIES := {
	"mining_i": {
		"name": "Extracción eficiente", "branch": "MINERÍA", "cost": 1, "level": 2,
		"requires": [], "description": "Extrae una pepita en 5 acciones en lugar de 7.",
	},
	"mining_ii": {
		"name": "Perforación avanzada", "branch": "MINERÍA", "cost": 2, "level": 4,
		"requires": ["mining_i"], "description": "Los taladros trabajan cada 0,3 s en lugar de 0,6 s.",
	},
	"logistics_i": {
		"name": "Cintas mejoradas", "branch": "LOGÍSTICA", "cost": 1, "level": 2,
		"requires": [], "description": "Las cintas avanzan cada 3 s en lugar de 4 s.",
	},
	"logistics_ii": {
		"name": "Transporte industrial", "branch": "LOGÍSTICA", "cost": 2, "level": 4,
		"requires": ["logistics_i"], "description": "Las cintas avanzan cada 2 s en lugar de 3 s.",
	},
	"defense_i": {
		"name": "Potencia de fuego", "branch": "DEFENSA", "cost": 1, "level": 2,
		"requires": [], "description": "Aumenta un 50 % el daño de los lanzapapas.",
	},
	"defense_ii": {
		"name": "Cargadores ampliados", "branch": "DEFENSA", "cost": 2, "level": 4,
		"requires": ["defense_i"], "description": "8 municiones por torreta y un disparo cada 3 s.",
	},
}

var level: int = 1
var experience: int = 0
var total_experience: int = 0
var research_points: int = 0
var unlocked: Dictionary = {}

func experience_to_next_level() -> int:
	return BASE_LEVEL_EXPERIENCE + (level - 1) * LEVEL_EXPERIENCE_STEP

func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	experience += amount
	total_experience += amount
	var gained_levels: Array[int] = []
	while experience >= experience_to_next_level():
		experience -= experience_to_next_level()
		level += 1
		research_points += POINTS_PER_LEVEL
		gained_levels.append(level)
	changed.emit()
	for gained_level in gained_levels:
		level_up.emit(gained_level)

func award_sale(kind: String) -> void:
	add_experience(int(SALE_EXPERIENCE.get(kind, 0)))

func has_technology(technology_id: String) -> bool:
	return unlocked.has(technology_id)

func research_block_reason(technology_id: String) -> String:
	if not TECHNOLOGIES.has(technology_id):
		return "Tecnología desconocida."
	if has_technology(technology_id):
		return "Investigada."
	var data: Dictionary = TECHNOLOGIES[technology_id]
	if level < int(data["level"]):
		return "Requiere nivel %d." % int(data["level"])
	for prerequisite in data["requires"]:
		if not has_technology(prerequisite):
			return "Requiere %s." % TECHNOLOGIES[prerequisite]["name"]
	if research_points < int(data["cost"]):
		return "Necesitas %d puntos de investigación." % int(data["cost"])
	return ""

func can_research(technology_id: String) -> bool:
	return research_block_reason(technology_id).is_empty()

func research(technology_id: String) -> bool:
	if not can_research(technology_id):
		return false
	research_points -= int(TECHNOLOGIES[technology_id]["cost"])
	unlocked[technology_id] = true
	technology_unlocked.emit(technology_id)
	changed.emit()
	return true
