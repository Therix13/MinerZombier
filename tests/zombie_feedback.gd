extends SceneTree

const Zombie = preload("res://Scripts/zombie.gd")
var passed: int = 0
var failed: int = 0
var kills: int = 0
var field: Node2D

func _initialize() -> void:
	Engine.set_meta(&"mine_defense_skip_start_screen", true)
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition: passed += 1; print("PASS: ", description)
	else: failed += 1; print("FAIL: ", description)

func make_zombie(at: Vector2, hp: float) -> Node2D:
	var zombie := Zombie.new()
	zombie.setup(at, at + Vector2(0, 100), hp)
	field.add_child(zombie)
	zombie.set_process(false)
	zombie.random.seed = 42
	return zombie

func effects() -> Array[Node]:
	return field.get_children().filter(func(node: Node) -> bool: return node is Zombie.HitEffect)

func run_checks() -> void:
	root.show()
	root.size = Vector2i(1280, 720)
	var background := ColorRect.new()
	background.color = Color("#182f42")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	field = Node2D.new()
	field.scale = Vector2.ONE * 4
	root.add_child(field)
	var zombie := make_zombie(Vector2(90, 85), 100)
	zombie.take_damage(0)
	zombie.apply_damage(-2)
	check(zombie.health == 100 and effects().is_empty() and zombie.limbs.size() == 4, "Zero and negative damage neither heal nor create feedback")
	zombie.take_damage(0.5)
	check(zombie.health == 99.5 and effects().size() == 1 and effects()[0].amount == 0.5, "Fractional hits create their exact damage number")
	check(effects()[0].get_parent() == field and effects()[0].global_position.is_equal_approx(zombie.global_position), "Damage feedback starts at the impact position in battlefield coordinates")
	for index in range(30): zombie.take_damage(0.5)
	var detached: Array[String] = []
	for effect in effects():
		if not effect.limb.is_empty(): detached.append(effect.limb)
	check(detached.size() > 0 and detached.size() <= 4 and detached.size() < effects().size(), "Only some hits randomly detach one of the four available limbs")
	check(detached.size() + zombie.limbs.size() == 4, "Already detached limbs cannot be detached twice")
	check(zombie.health == 84.5 and zombie.is_in_group("zombies"), "Cosmetic dismemberment preserves damage accounting and enemy lifetime")
	var before: Vector2 = zombie.position
	zombie._process(0.2)
	check(zombie.position != before, "A wounded zombie can keep advancing")
	for effect in effects(): effect.queue_free()
	await process_frame
	await process_frame
	var dying := make_zombie(Vector2(160, 85), 0.5)
	dying.defeated.connect(func() -> void: kills += 1)
	dying.take_damage(10)
	dying.take_damage(10)
	check(kills == 1 and not dying.is_in_group("zombies"), "A fatal hit removes the combat target and grants defeat exactly once")
	check(effects().size() == 1 and effects()[0].amount == 0.5, "Overkill reports actual health lost and ignores repeated damage after death")
	await process_frame
	check(not is_instance_valid(dying) and not effects().is_empty(), "Fatal damage numbers survive the defeated zombie")
	for effect in effects(): effect._process(3)
	await process_frame
	await process_frame
	check(effects().is_empty(), "Expired numbers and detached limbs clean themselves up")
	# A clean visual sample: decimal damage, two missing limbs, and a lethal hit.
	zombie.queue_free()
	await process_frame
	var sample := make_zombie(Vector2(90, 85), 10)
	sample.limbs.erase("left_arm")
	sample.limbs.erase("right_leg")
	sample.take_damage(0.5)
	var lethal := make_zombie(Vector2(200, 85), 2)
	lethal.take_damage(2)
	var effect := Zombie.HitEffect.new()
	effect.limb = "left_arm"
	effect.amount = 1
	effect.position = Vector2(100, 100)
	field.add_child(effect)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/workspace/.onboarding/display-test/zombie-feedback.png")
	field.free()
	background.free()
	print("RESULT: ", passed, " passed; ", failed, " failed; zombie feedback")
	quit(1 if failed else 0)
