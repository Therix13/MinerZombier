extends "res://tests/timed_hordes.gd"
const Art = preload("res://Scripts/painted_assets.gd")
const Intro = preload("res://Scripts/intro_cinematic.gd")
func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.campaign.set_process(false)
	game.cycle.skip_tutorial()
	game.camera_controller.stop_transition()
	manager = game.zombie_manager
	manager.set_process(false)
	mover = game.get_node("WorldInteractions")
	for path: String in [Art.OPENING,Art.INFECTED,Art.INDUSTRY,Art.COMPONENTS,Art.WORLD]:
		var tex: Texture2D = Art.texture(path)
		check(tex != null and tex.get_width() >= 1400,"Original painted production asset loads: " + path)
		check(Art.texture(path) == tex,"Painted sheet is shared rather than copied per sprite: " + path)
	for i in range(12):
		check(Art.prop(i) != null and Art.prop(i).atlas == Art.texture(Art.INDUSTRY),"Industrial sprite uses its shared atlas region: %d" % i)
	for i in range(6):
		var kind: String = ["walker","armored","spitter","executor","plague","broodmother"][i]
		check(Art.enemy_index(kind) == i and Art.enemy(kind).region.has_area(),"Infected role has its own painted silhouette: " + kind)
	var live: Node = enemy("walker")
	live.walking_time = 1
	live.update_visual()
	var first_position: Vector2 = live.body_sprite.position
	live.walking_time = 3
	live.update_visual()
	check(not first_position.is_equal_approx(live.body_sprite.position) and live.body_sprite.material is ShaderMaterial,"Walking drives both body motion and the sprite's limb shader")
	live.hit_flash = .15
	live.update_visual()
	check(live.body_sprite.material.get_shader_parameter("hurt") > .8,"Damage flashes the painted sprite without changing combat stats")
	clear_enemies()
	var coins: int = game.economy.coins
	var camera_position: Vector2 = game.camera.position
	var original_visibility: bool = game.renderer.visible
	var intro: Node = Intro.new()
	intro.name = "IntroCinematic"
	game.add_child(intro)
	intro.set_process(false)
	check(paused and not game.renderer.visible and not game.ui_layer.visible,"New opening pauses simulation and excludes the covered world from rendering")
	check(Intro.SHOTS.size() == 4 and Intro.DURATION == 32,"Opening is a four-shot cinematic, replacing the old fence sequence")
	for i in range(4):
		intro.elapsed = i*Intro.SHOT_DURATION+3
		intro.present_frame()
		check(intro.shot == i and intro.title.text == Intro.SHOTS[i]["title"],"Opening shot shows its own lore and plate: %d" % i)
		check(intro.film.picture.texture.region == Art.scene(i).region,"Opening camera samples the correct painted scene: %d" % i)
		if DisplayServer.get_name() != "headless":
			await settle()
			root.get_texture().get_image().save_png("/tmp/painted-opening-%d.png" % i)
	check(Intro.SHOTS[1]["text"].contains("ventilación") and Intro.SHOTS[1]["text"].contains("muertos"),"Lore explains how escaped spores caused the zombies")
	check(Intro.SHOTS[3]["text"].contains("aire independiente") and Intro.SHOTS[3]["text"].contains("generador"),"Lore explains why the mine is a viable refuge")
	intro.finish()
	await settle()
	check(not paused and game.renderer.visible == original_visibility and game.ui_layer.visible,"Skipping or finishing restores the previous world, UI and pause state")
	check(game.campaign.state["story_seen"].has("origin") and game.economy.coins == coins and game.camera.position == camera_position,"Opening records the lore once without granting resources or moving the game camera")
	var director: Node = game.get_node("StoryDirector")
	director.play("origin")
	check(director.active == "origin" and is_instance_valid(director.sequence) and director.sequence.replay,"History replays the complete new opening rather than the removed vector scene")
	director.finish()
	await settle()
	check(director.active.is_empty() and not paused,"Finishing an opening replay resumes gameplay")
	director.play("origin")
	var timed_intro: Node = director.sequence
	timed_intro.set_process(false)
	timed_intro._process(33)
	await settle()
	check(director.active.is_empty() and not paused,"Opening completes automatically after its full duration and resumes play")
	var breach: Node = Intro.new()
	breach.name = "BarrierBreach"
	breach.breach = true
	game.add_child(breach)
	breach.set_process(false)
	breach.elapsed = 3
	breach.present_frame()
	check(breach.shot == 2 and breach.title.text.contains("COMPUERTA"),"First-night transition shares the new painted continuity")
	breach.finish()
	await settle()
	for kind: String in ["plague","warden","broodmother","executor"]:
		director.play(kind)
		director._process(3.5)
		check(director.film.picture != null and director.film.scene_data["boss"] == kind,"Boss kill-scene animates the painted boss: " + kind)
		await settle()
		if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/painted-boss-%s.png" % kind)
		director.finish()
		director._process(1.1)
		await settle()
	var saves: Node = game.get_node("SaveGame")
	check(saves.valid_snapshot(saves.snapshot()) and saves.restore_snapshot(saves.snapshot()),"New presentation preserves game/save compatibility")
	game.grid.expand()
	clear_items()
	game.mining.place_vein(Vector2i(14,0),1,"coal")
	game.mining.place_vein(Vector2i(14,2),1,"copper")
	game.drills.place(Vector2i(13,2),1)
	game.get_node("Furnaces").place(Vector2i(16,2),0)
	game.get_node("Furnaces").receive(Vector2i(16,2),"coal_4")
	game.get_node("Furnaces").receive(Vector2i(16,2),"copper_4")
	game.get_node("Furnaces").process_smelting(1)
	game.get_node("Saws").place(Vector2i(16,3),0)
	game.get_node("Saws").receive(Vector2i(16,3),"copper_3")
	game.get_node("Compactors").place(Vector2i(14,3),0)
	game.get_node("Compactors").receive(Vector2i(14,3),"coal_4")
	game.mining.items_for("copper_ingot_3")[Vector2i(15,1)] = 1
	game.conveyors.place(Vector2i(15,2),1,"filter")
	game.grid.purchase_defense_platforms()
	game.launchers.place(game.grid.defense_cell("left"))
	game.get_node("WorldAtmosphere").refresh_parts()
	game.shop.notice_item_ids.clear()
	game.shop.unlock_notice_backdrop.hide()
	game.redraw_world()
	await settle()
	var atmosphere: Node = game.get_node("WorldAtmosphere")
	check(atmosphere.parts.size() == 2 and atmosphere.lamps.size() == 1,"Mechanical parts and furnace lighting are attached to live machines")
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/painted-mine.png")
	game.campaign.open_panel()
	game.campaign.show_tab("Bestiario")
	await settle()
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/tmp/painted-bestiary.png")
	game.campaign.close_panel()
	print("RESULT: %d passed, %d failed; painted presentation and new opening" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
