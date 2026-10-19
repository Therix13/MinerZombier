extends "res://tests/interactions.gd"

func wait_real(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout
	await settle()

func press_accept(shop: Control) -> void:
	var button: Button = shop.unlock_notice_accept
	var at: Vector2 = root.get_screen_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	await mouse_move(at)
	await mouse_button(at,true)
	await mouse_button(at,false)

func announce(shop: Control, item: String) -> void:
	var items: Array[String] = [item]
	shop.announce_unlocks(items)

func run_checks() -> void:
	root.show()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.set_process(false)
	game.cycle.skip_tutorial()
	var shop: Control = game.shop
	shop.accept_unlock_notice()
	announce(shop,"copper")
	check(shop.unlock_notice_backdrop.visible and shop.unlock_notice_backdrop.modulate.a == 0,"Unlock modal starts visible with zero opacity")
	await wait_real(0.25)
	check(shop.unlock_notice_backdrop.modulate.a > 0.02 and shop.unlock_notice_backdrop.modulate.a < 0.95,"Entrance is still fading after a quarter second")
	await wait_real(0.25)
	check(shop.unlock_notice_backdrop.modulate.a > 0.3 and shop.unlock_notice_backdrop.modulate.a < 0.85,"Entrance passes through intermediate opacity after half a second")
	var alpha: float = shop.unlock_notice_backdrop.modulate.a
	announce(shop,"iron")
	check(shop.unlock_notice_backdrop.modulate.a == alpha and shop.unlock_notice_cards.size() == 2,"A second unlock joins without restarting or flashing the entrance")
	await wait_real(0.55)
	check(shop.unlock_notice_backdrop.modulate.a > 0.99 and shop.unlock_notice.visible,"Entrance completes after one real second")
	await wait_real(1.1)
	check(shop.unlock_notice.visible,"The fully visible alert still waits for acceptance")
	await press_accept(shop)
	check(shop.unlock_notice_closing and shop.unlock_notice_backdrop.visible and shop.unlock_notice_accept.disabled,"Actual Aceptar click starts dismissal and prevents duplicate presses")
	check(not game.phase_clock.can_tick(),"The modal keeps gameplay blocked throughout dismissal")
	await wait_real(0.3)
	check(shop.unlock_notice_backdrop.modulate.a > 0.1 and shop.unlock_notice_backdrop.modulate.a < 0.95,"Dismissal passes through intermediate opacity")
	announce(shop,"gold")
	check(shop.unlock_notice_closing and shop.notice_item_ids == ["gold"] and not shop.unlock_notice_cards.has("gold"),"Unlocks arriving during dismissal queue without replacing fading cards")
	await wait_real(0.75)
	check(not shop.unlock_notice_closing and shop.unlock_notice_cards.has("gold") and shop.unlock_notice_tween.is_running(),"A queued alert begins its own fade after the previous one exits")
	await wait_real(1.05)
	await press_accept(shop)
	await wait_real(0.35)
	check(shop.unlock_notice_backdrop.visible,"Alert is not hidden abruptly after Aceptar")
	await wait_real(0.7)
	check(not shop.unlock_notice.visible and not shop.unlock_notice_backdrop.visible and game.phase_clock.can_tick(),"One-second dismissal releases the modal and gameplay together")
	# UI transitions use real time even when the game runs accelerated.
	game.phase_clock.set_process(false)
	Engine.time_scale = 4.0
	announce(shop,"furnace")
	await wait_real(0.25)
	check(shop.unlock_notice_backdrop.modulate.a < 0.4,"Game speed does not shorten the one-second interface transition")
	Engine.time_scale = 1.0
	game.phase_clock.set_process(true)
	shop.accept_unlock_notice()
	check(not shop.unlock_notice_backdrop.visible and not shop.unlock_notice_closing,"Scene restoration can clear an in-progress transition immediately")
	game.cycle.is_night = true
	announce(shop,"drill")
	check(not shop.unlock_notice.visible,"Night unlocks remain queued rather than opening during combat")
	game.cycle.is_night = false
	shop.update_notice_visibility()
	check(shop.unlock_notice_backdrop.visible and shop.unlock_notice_backdrop.modulate.a == 0,"A deferred unlock also starts with the full entrance transition")
	shop.accept_unlock_notice()
	print("RESULT: %d passed, %d failed; unlock transitions" % [passed,failed])
	game.queue_free()
	await settle()
	quit(1 if failed else 0)
