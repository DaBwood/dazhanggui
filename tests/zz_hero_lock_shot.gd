extends Node
# 临时截图：门客页 —— 建卡时锁定的门客在解锁后点击，应能打开详情（回归验证）

func _ready() -> void:
	var game: Node = load("res://control.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	for nm in ["LoginGate", "LoginPopup", "SyncMask"]:
		var n := game.get_node_or_null(nm)
		if n != null:
			n.queue_free()
	for ch in game.get_children():
		if ch is ColorRect and (ch as ColorRect).color.a >= 0.5:
			ch.queue_free()
	await get_tree().create_timer(0.2).timeout
	game._enter_game()
	for i in range(8):
		await get_tree().process_frame

	game.switch_page("hero")
	for i in range(20):
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	var grid: GridContainer = game.get_node_or_null("PageContainer/HeroPage/HeroScene/HeroScroll/HeroGrid")
	print("[test] grid=", grid, " cards=", grid.get_child_count() if grid != null else -1)

	# 找一个当前锁定的门客（不在 data.heroes 里），先确认点它弹 VIP 提示
	var locked_id := ""
	if grid != null:
		for cell in grid.get_children():
			var hid := str(cell.get_meta("hero_id", ""))
			if hid != "" and not game.data.heroes.has(hid):
				locked_id = hid
				break
	print("[test] locked_id=", locked_id)

	if locked_id != "":
		game.data.unlock_hero(locked_id)
		print("[test] unlocked now=", game.data.heroes.has(locked_id))
		for i in range(6):
			await get_tree().process_frame
		# 直接触发该卡的 pressed（模拟点击），应进详情而不是弹 VIP 提示
		if grid != null:
			for cell in grid.get_children():
				if str(cell.get_meta("hero_id", "")) == locked_id:
					cell.emit_signal("pressed")
					break
		for i in range(12):
			await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		print("[test] hero_panel=", game.has_node("HeroPanel"), " unlock_hint=", game.has_node("UnlockHint"))
		await _shot("res://tests/_hero_after_unlock.png")
	print("SHOTS_DONE")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
