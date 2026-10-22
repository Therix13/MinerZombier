extends RefCounted

const CAMPAIGN_NIGHTS := 900
const MATERIALS := {"nitrate":"Nitrato de potasio", "sulfur":"Azufre", "tungsten":"Wolframio"}
const VEIN_PRICES := {"nitrate":1800,"sulfur":3500,"tungsten":125000}
const AMMO := ["powder","bullet","grenade","rocket","battery"]
const LABELS := {"powder":"Pólvora", "bullet":"Balas", "grenade":"Granadas", "rocket":"Cohetes", "battery":"Celdas eléctricas"}
const COLORS := {"nitrate":"#c0e5ea","sulfur":"#e9cf51","tungsten":"#8095b2","powder":"#696775","bullet":"#d6b777","grenade":"#7d9866","rocket":"#d77551","battery":"#6cd8e2"}
const WEAPONS := {
	"pistol": {"name":"Torreta de pistolas","price":1800,"capacity":24,"interval":0.65,"damage":1.5,"radius":0.0,"range":340.0,"ammo":"bullet","color":"#91a8b2"},
	"grenadier": {"name":"Lanzagranadas","price":6000,"capacity":10,"interval":3.0,"damage":6.0,"radius":78.0,"range":360.0,"ammo":"grenade","color":"#a7b86d"},
	"rocketeer": {"name":"Lanzacohetes","price":20000,"capacity":6,"interval":4.0,"damage":18.0,"radius":105.0,"range":430.0,"ammo":"rocket","color":"#d78b64"},
	"tesla": {"name":"Torreta Tesla","price":45000,"capacity":16,"interval":1.5,"damage":4.0,"radius":65.0,"range":320.0,"ammo":"battery","color":"#77d7e7"},
}
const CRAFTS := {
	"powder": {"name":"Pólvora","cost":{"nitrate_4":1,"sulfur_4":1,"coal_4":1},"yield":8,"time":4.0},
	"bullet": {"name":"Balas","cost":{"powder":1,"copper_ingot":1},"yield":12,"time":3.0},
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
