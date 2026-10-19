extends "res://tests/interactions.gd"

var compactors: Node
const C := Vector2i(14,2)
const OUT := Vector2i(14,1)

func reset_machine() -> void:
	clear_items()
	compactors.place(C,0)

func run_checks() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	game.grid.expand()
	mover = game.get_node("WorldInteractions")
	compactors = game.get_node("Compactors")
	compactors.set_process(false)
	game.get_node("WorkshopRhythm").set_process(false)
	for family: String in ["coal","copper","iron","gold","copper_ingot","iron_ingot","gold_ingot"]:
		for tier in range(1,5):
			reset_machine()
			var kind: String = family + ("_" + str(tier) if tier > 1 else "")
			var points: int = 1 << (tier - 1)
			var count: int = 8 / points
			for i in range(count): check(compactors.receive(C,kind),"Accepts %s input %d" % [kind,i + 1])
			check(compactors.machines[C]["points"] == 8,"Tier %d supplies %d points per item" % [tier,points])
			check(not compactors.can_receive(C,kind),"Full batch does not swallow more input")
			var duration: float = 1.0 if tier == 4 else 4.0
			compactors.process_outputs(duration - 0.01)
			check(game.mining.nuggets_at(OUT) == 0,"Batch waits for its full processing time")
			compactors.process_outputs(0.02)
			check(game.mining.nugget_type(OUT) == family + "_4" and compactors.machines[C]["points"] == 0,"Every batch produces exactly one maximum-tier item")
	reset_machine()
	for kind: String in ["coal_3","coal_2","coal","coal_3"]: compactors.receive(C,kind)
	check(compactors.machines[C]["points"] == 11 and compactors.process_time(compactors.machines[C]) == 4.0,"Mixed lower tiers accumulate eleven points at normal speed")
	game.mining.items_for("iron")[OUT] = 1
	var before: Dictionary = compactors.stored_items(C)
	compactors.process_outputs(20)
	check(compactors.machines[C]["points"] == 11 and compactors.stored_items(C) == before,"Blocked outlet preserves all eleven points and physical inputs")
	game.mining.items_for("iron").erase(OUT)
	compactors.process_outputs()
	check(game.mining.nugget_type(OUT) == "coal_4" and compactors.machines[C]["points"] == 3,"Output consumes eight points and keeps the remainder")
	check(compactors.stored_items(C) == {"coal_2":1,"coal":1},"Surplus preserves its exact original tiers")
	check(not compactors.receive(C,"copper") and not compactors.receive(C,"coal_ingot") and not compactors.receive(C,"unknown"),"Materials and forms cannot mix or invent points")
	game.mining.items_for("coal_4").erase(OUT)
	compactors.receive(C,"coal_3")
	compactors.receive(C,"coal")
	compactors.process_outputs(4)
	check(game.mining.nugget_type(OUT) == "coal_4" and compactors.machines[C]["points"] == 0,"Saved surplus contributes to the next cycle")
	reset_machine()
	for kind: String in ["copper_3","copper_2","copper","copper_4"]: compactors.receive(C,kind)
	check(compactors.machines[C]["points"] == 15 and compactors.process_time(compactors.machines[C]) == 1.0,"Tier-four arrival uses the fast cycle even with seven saved points")
	compactors.process_outputs(1)
	check(compactors.machines[C]["points"] == 7 and compactors.stored_items(C) == {"copper_3":1,"copper_2":1,"copper":1},"Fast cycle consumes only the level-four item and preserves all surplus")
	check(compactors.remove_material(C,"copper_2") and compactors.machines[C]["points"] == 5,"Withdrawing an original input removes its exact points")
	var inspector: Node = game.get_node("ToolInspector")
	inspector.open_tool("compactor",C)
	check(inspector.status.text.contains("5 / 8") and inspector.inventory() == compactors.stored_items(C),"Inspector shows actual resources and the point total")
	check(inspector.withdraw("copper_3") and compactors.machines[C]["points"] == 1 and game.mining.items_for("copper_3").size() == 1,"Inspector withdrawal returns the real tier without duplicating points")
	inspector.close_inspector()
	var saves: Node = game.get_node("SaveGame")
	var snapshot: Dictionary = saves.snapshot()
	check(saves.valid_snapshot(snapshot) and saves.restore_snapshot(snapshot) and compactors.machines[C]["points"] == 1,"Surplus survives save and reload")
	var bad: Dictionary = snapshot.duplicate(true)
	bad["compactors"][C]["points"] = 7
	check(not saves.valid_snapshot(bad),"Save validator rejects points unsupported by inventory")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.erase("compactor_revision")
	legacy["compactors"][C] = {"kind":"iron_ingot_3","count":2,"direction":0,"elapsed":1.75}
	check(saves.restore_snapshot(legacy) and compactors.machines[C]["points"] == 8 and compactors.stored_items(C) == {"iron_ingot_3":2} and compactors.machines[C]["elapsed"] == 1.75,"Legacy two-item batch migrates without losing its materials or elapsed time")
	for items: Dictionary in game.mining.nugget_stores().values(): items.erase(OUT)
	compactors.process_outputs(2.25)
	check(game.mining.nugget_type(OUT) == "iron_ingot_4","Migrated batch completes its correct maximum-tier output")
	reset_machine()
	var left := C + Vector2i.LEFT
	var right := C + Vector2i.RIGHT
	game.conveyors.place(left,1)
	game.conveyors.place(right,3)
	game.mining.items_for("coal_4")[left] = 1
	game.mining.items_for("coal_4")[right] = 1
	game.conveyors.tick()
	check(compactors.machines[C]["points"] == 8 and game.mining.nuggets_at(left) + game.mining.nuggets_at(right) == 1,"Simultaneous belts reserve capacity and leave unaccepted input on its belt")
	reset_machine()
	game.conveyors.place(left,1)
	game.conveyors.place(right,3)
	game.conveyors.place(C + Vector2i.DOWN,0)
	game.mining.items_for("coal_3")[left] = 1
	game.mining.items_for("coal_2")[right] = 1
	game.mining.items_for("coal_3")[C + Vector2i.DOWN] = 1
	game.conveyors.tick()
	check(compactors.machines[C]["points"] == 10,"Three belts can deliver mixed tiers up to a completed batch with surplus")
	compactors.process_outputs(4)
	check(compactors.machines[C]["points"] == 2 and game.mining.nugget_type(OUT) == "coal_4","Belt-fed batch produces maximum tier and retains excess points")
	game.shop.accept_unlock_notice()
	check(mover.sell("compactor",C) and game.mining.items_for("coal_2").get(C) == 1,"Selling a compactor returns all leftover material")
	print("RESULT: %d passed, %d failed; point-based compactors" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
