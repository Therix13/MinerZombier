extends RefCounted

signal changed
signal level_up(new_level: int)
signal technology_unlocked(technology_id: String)
signal research_unlocked(research_id: String)

const BASE_LEVEL_EXPERIENCE: int = 50
const LEVEL_EXPERIENCE_GROWTH: float = 1.6
const POINTS_PER_LEVEL: int = 1
const POINTS_PER_NIGHT: int = 1
const ZOMBIE_EXPERIENCE: int = 25
const SALE_EXPERIENCE := {"coal": 1, "brass": 2, "coal_2": 4, "brass_2": 8}
const RESEARCHES := {
	"drill": {
		"name": "Taladro", "branch": "MINERÍA", "cost": 1, "level": 2,
		"requires": [], "description": "Desbloquea el taladro automático en la tienda.",
	},
	"brass": {
		"name": "Latón", "branch": "MINERÍA", "cost": 1, "level": 3,
		"requires": ["drill"], "description": "Desbloquea la veta de latón en la tienda.",
	},
	"straight_belt": {
		"name": "Cinta transportadora", "branch": "LOGÍSTICA", "cost": 1, "level": 2,
		"requires": [], "description": "Desbloquea la cinta recta en la tienda.",
	},
	"curved_belts": {
		"name": "Cintas curvas", "branch": "LOGÍSTICA", "cost": 1, "level": 3,
		"requires": ["straight_belt"], "description": "Desbloquea las cintas en L de ambas direcciones.",
	},
	"junction_belt": {
		"name": "Unión en T", "branch": "LOGÍSTICA", "cost": 2, "level": 4,
		"requires": ["curved_belts"], "description": "Desbloquea la cinta que reúne tres entradas.",
	},
	"compactor": {
		"name": "Compactador", "branch": "PROCESAMIENTO", "cost": 1, "level": 3,
		"requires": ["drill"], "description": "Convierte 4 pepitas iguales en una de nivel 2.",
	},
}
const BASE_ITEMS := ["coal", "launcher", "defense_platforms"]
const ITEM_RESEARCH := {"straight": "straight_belt", "drill": "drill", "brass": "brass", "corner": "curved_belts", "corner_right": "curved_belts", "corner_left": "curved_belts", "junction": "junction_belt", "compactor": "compactor"}
# Older scenes can still refer to these names. They now resolve item unlocks.
const TECHNOLOGIES := RESEARCHES

var level: int = 1
var experience: int = 0
var total_experience: int = 0
var research_points: int = 0
var unlocked: Dictionary = {}

func experience_to_next_level() -> int:
	return roundi(BASE_LEVEL_EXPERIENCE * pow(LEVEL_EXPERIENCE_GROWTH, level - 1))

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

func award_night() -> void:
	research_points += POINTS_PER_NIGHT
	changed.emit()

func has_technology(technology_id: String) -> bool:
	return has_research(technology_id)

func has_research(research_id: String) -> bool:
	return RESEARCHES.has(research_id) and unlocked.has(research_id)

func is_item_unlocked(item_id: String) -> bool:
	return item_id in BASE_ITEMS or (ITEM_RESEARCH.has(item_id) and has_research(ITEM_RESEARCH[item_id]))

func visible_researches(at_level: int = -1) -> Array[String]:
	var result: Array[String] = []
	var visible_level: int = level if at_level < 0 else at_level
	for research_id: String in RESEARCHES:
		if int(RESEARCHES[research_id]["level"]) <= visible_level: result.append(research_id)
	return result

func research_block_reason(technology_id: String) -> String:
	if not RESEARCHES.has(technology_id):
		return "Investigación desconocida."
	if has_technology(technology_id):
		return "Desbloqueado."
	var data: Dictionary = RESEARCHES[technology_id]
	if level < int(data["level"]):
		return "Requiere nivel %d." % int(data["level"])
	for prerequisite in data["requires"]:
		if not has_technology(prerequisite):
			return "Requiere %s." % RESEARCHES[prerequisite]["name"]
	if research_points < int(data["cost"]):
		return "Necesitas %d puntos de investigación." % int(data["cost"])
	return ""

func can_research(technology_id: String) -> bool:
	return research_block_reason(technology_id).is_empty()

func research(technology_id: String) -> bool:
	if not can_research(technology_id):
		return false
	research_points -= int(RESEARCHES[technology_id]["cost"])
	unlocked[technology_id] = true
	research_unlocked.emit(technology_id)
	technology_unlocked.emit(technology_id)
	changed.emit()
	return true
