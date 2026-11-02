extends Node
# 临时截图：门客服装弹窗 / 挚友服装弹窗（验证服装图标 + 解锁区小图标）

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
	await get_tree().create_timer(0.4).timeout

	game.costume_view.show_hero_costume_popup("li_bai")
	for i in range(8):
		await get_tree().process_frame
	# 点第二张服装卡（第一张是初始形象），看解锁区的图标+数量
	var pop = game.get_node_or_null("HeroCostumePopup")
	if pop != null:
		var cards = pop.find_child("CosCards", true, false)
		if cards != null and cards.get_child_count() > 1:
			var card = cards.get_child(1)
			for ch in card.get_children():
				if ch is Button:
					(ch as Button).emit_signal("pressed")
					break
			for i in range(6):
				await get_tree().process_frame
	await _shot("res://tests/_cos_hero.png")

	game._safe_close("HeroCostumePopup")
	for i in range(4):
		await get_tree().process_frame
	game.costume_view.show_friend_costume_popup("miao_jiang_shengnv")
	for i in range(8):
		await get_tree().process_frame
	await _shot("res://tests/_cos_friend.png")
	print("SHOTS_DONE")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
