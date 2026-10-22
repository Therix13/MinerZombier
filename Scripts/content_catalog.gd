extends RefCounted

const CAMPAIGN_NIGHTS := 900
const MATERIALS := {"nitrate":"Nitrato de potasio", "sulfur":"Azufre", "tungsten":"Wolframio"}
const VEIN_PRICES := {"nitrate":1800,"sulfur":3500,"tungsten":125000}
const AMMO := ["powder","bullet","highcaliber","grenade","rocket","battery"]
const LABELS := {"highcaliber":"Balas de alto calibre","powder":"Pólvora", "bullet":"Balas", "grenade":"Granadas", "rocket":"Cohetes", "battery":"Celdas eléctricas"}
const COLORS := {"coal":"#7f92a7","copper":"#efaa84","iron":"#b5c8db","gold":"#efcf7e","highcaliber":"#ff987d","nitrate":"#c0e5ea","sulfur":"#e9cf51","tungsten":"#8095b2","powder":"#696775","bullet":"#d6b777","grenade":"#7d9866","rocket":"#d77551","battery":"#6cd8e2"}
const WEAPONS := {
	"pistol": {"name":"Torreta de pistolas","price":1800,"capacity":24,"interval":0.65,"damage":1.5,"radius":0.0,"range":340.0,"ammo":"bullet","color":"#91a8b2"},
	"ak47":{"name":"Torreta AK-47","price":4200,"capacity":30,"interval":0.4,"damage":2.0,"radius":0.0,"range":350.0,"ammo":"highcaliber","color":"#edb478"},
	"grenadier": {"name":"Lanzagranadas","price":6000,"capacity":10,"interval":3.0,"damage":6.0,"radius":78.0,"range":360.0,"ammo":"grenade","color":"#a7b86d"},
	"minigun":{"name":"Minigun","price":12000,"capacity":80,"interval":0.16,"damage":1.4,"radius":0.0,"range":330.0,"ammo":"highcaliber","color":"#85c9b7"},
	"rocketeer": {"name":"Lanzacohetes","price":20000,"capacity":6,"interval":4.0,"damage":18.0,"radius":105.0,"range":430.0,"ammo":"rocket","color":"#d78b64"},
	"tesla": {"name":"Torreta Tesla","price":45000,"capacity":16,"interval":1.5,"damage":4.0,"radius":65.0,"range":320.0,"ammo":"battery","color":"#77d7e7"},
}
const CRAFTS := {
	"powder": {"name":"Pólvora","cost":{"nitrate_4":1,"sulfur_4":1,"coal_4":1},"yield":8,"time":4.0},
	"bullet": {"name":"Balas","cost":{"powder":1,"copper_ingot":1},"yield":12,"time":3.0},
	"highcaliber":{"name":"Balas de alto calibre","cost":{"powder":2,"iron_ingot_2":1},"yield":16,"time":4.0},
	"grenade": {"name":"Granadas","cost":{"powder":3,"iron_ingot":1},"yield":4,"time":5.0},
	"rocket": {"name":"Cohetes","cost":{"powder":6,"iron_ingot_2":1},"yield":2,"time":7.0},
	"battery": {"name":"Celdas eléctricas","cost":{"copper_ingot_3":1,"nitrate_4":1},"yield":8,"time":6.0},
}
const INDUSTRIAL_UPGRADES := [
	{"night":25,"price":25000,"cost":{"iron_ingot_4":2,"copper_ingot_4":2}},
	{"night":100,"price":100000,"cost":{"tungsten_ingot_2":2,"gold_ingot_3":2}},
	{"night":250,"price":500000,"cost":{"tungsten_ingot_4":2,"gold_ingot_4":2}},
]
const CHAPTERS := [
	{"start":1,"name":"La entrada","goal":"Domina la mina y sobrevive a la primera horda."},
	{"start":6,"name":"Pólvora y acero","goal":"Explota nitrato y azufre; fabrica balas y pistolas."},
	{"start":21,"name":"El asedio","goal":"Automatiza munición y combate con explosivos."},
	{"start":81,"name":"Mutaciones","goal":"Alterna daño de área y disparos contra enemigos de apoyo."},
	{"start":181,"name":"El corazón de la mina","goal":"Desarrolla wolframio y defensas eléctricas."},
	{"start":361,"name":"Zona de exclusión","goal":"Supera combinaciones de élites y jefes."},
	{"start":601,"name":"La última frontera","goal":"Conquista los asedios finales hasta la noche 900."},
]

static func label(kind: String) -> String:
	if LABELS.has(kind): return LABELS[kind]
	var material: String = kind.get_slice("_",0)
	if MATERIALS.has(material):
		var suffix: String = kind.get_slice("_",kind.get_slice_count("_") - 1)
		return ("Lingote de " if "_ingot" in kind else "") + MATERIALS[material] + " Nv. " + (suffix if suffix.is_valid_int() else "1")
	return kind

static func chapter(day: int) -> Dictionary:
	var found: Dictionary = CHAPTERS[0]
	for entry: Dictionary in CHAPTERS:
		if day >= entry["start"]: found = entry
	return found

# Cumulative excavation; prices track the material economy rather than calendar time.
const EXPANSIONS := [
	{"size":Vector2i(7,5),"price":500}, {"size":Vector2i(11,7),"price":7500},
	{"size":Vector2i(15,9),"price":30000}, {"size":Vector2i(19,14),"price":90000},
	{"size":Vector2i(23,21),"price":240000}, {"size":Vector2i(27,30),"price":600000},
	{"size":Vector2i(30,40),"price":1500000}]
const UNLOCKS := {
	"powder":{"requires":["nitrate_4","sulfur_4"],"hint":"Fusiona nitrato y azufre hasta Nv. 4 → Pólvora"},
	"bullet":{"requires":["copper_ingot_2"],"hint":"Fusiona lingotes de cobre hasta Nv. 2 → Balas"},
	"highcaliber":{"requires":["iron_ingot_2"],"hint":"Fusiona lingotes de hierro hasta Nv. 2 → Alto calibre"},
	"grenade":{"requires":["iron_ingot_3"],"hint":"Fusiona lingotes de hierro hasta Nv. 3 → Granadas"},
	"rocket":{"requires":["gold_ingot_3"],"hint":"Fusiona lingotes de oro hasta Nv. 3 → Cohetes"},
	"battery":{"requires":["tungsten_ingot_2"],"hint":"Fusiona lingotes de wolframio hasta Nv. 2 → Celdas"},
	"pistol":{"requires":["bullet","iron_ingot_2"],"hint":"Fabrica balas y crea hierro fundido Nv. 2 → Pistolas"},
	"ak47":{"requires":["highcaliber","iron_ingot_3"],"hint":"Fabrica alto calibre y fusiona hierro fundido Nv. 3 → AK-47"},
	"minigun":{"requires":["highcaliber","iron_ingot_4"],"hint":"Fabrica alto calibre y fusiona hierro fundido Nv. 4 → Minigun"},
	"grenadier":{"requires":["grenade","copper_ingot_3"],"hint":"Fabrica granadas y fusiona cobre fundido Nv. 3 → Lanzagranadas"},
	"rocketeer":{"requires":["rocket","iron_ingot_4"],"hint":"Fabrica cohetes y fusiona hierro fundido Nv. 4 → Lanzacohetes"},
	"tesla":{"requires":["battery","tungsten_ingot_3"],"hint":"Fabrica celdas y fusiona wolframio fundido Nv. 3 → Tesla"},
}
static func next_expansion(width: int) -> Dictionary:
	for stage: Dictionary in EXPANSIONS:
		if stage["size"].x > width: return stage
	return {}
