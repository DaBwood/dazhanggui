extends Node
# 临时截图：素装盒选择器（挚友头像 + 服装图标 + 已拥有禁用）

const SAVE_PATH := "user://save.json"


func _ready() -> void:
	await _run()


func _find_all(n: Node, nm: String, out: Array) -> void:
	if n.name == nm:
		out.append(n)
	for ch in n.get_children():
		_find_all(ch, nm, out)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)


func _run() -> void:
	var game: Node = load("res://control.tscn").instantiate()
	add_child(game)
	for i in range(6):
		await get_tree().process_frame
	for nm in ["LoginGate", "LoginPopup", "SyncMask"]:
		var n: Node = game.get_node_or_null(nm)
		if n != null:
			n.queue_free()
	for ch in game.get_children():
		if ch is ColorRect and (ch as ColorRect).color.a >= 0.5:
			ch.queue_free()
	game._enter_game()
	for i in range(8):
		await get_tree().process_frame

	var data = game.data
	# 挚友本体：已拥有（应禁用）
	data.friends["miao_jiang_shengnv"] = {"level": 1}
	# 背包里放一个素装盒
	data.items["friend_cos_box_miao_jiang_shengnv"] = 3
	game.switch_page("bag")
	for i in range(10):
		await get_tree().process_frame
	game.bag_page._show_friend_cos_box_selector("friend_cos_box_miao_jiang_shengnv", 2)
	for i in range(8):
		await get_tree().process_frame
	var sel: Node = game.get_node_or_null("OrigChoosePopup")
	print("[sel] exist=", sel != null)
	if sel != null:
		print("[sel] children=", sel.get_child_count())
	# 点两下 +，验证步进与「使用」解禁
	var panel_node: Node = game.get_node_or_null("FriendBoxSelector")
	if panel_node != null:
		var pluses := []
		_find_all(panel_node, "QtyPlus", pluses)
		if pluses.size() >= 1:
			for k in range(2):
				(pluses[1] as Button).emit_signal("pressed")
				await get_tree().process_frame
	await _shot("res://tests/_box_sel_qty.png")
	await _shot("res://tests/_box_sel.png")
	# 多选锦盒（每行是一个盒子道具，走道具图标）
	game._safe_close("FriendBoxSelector")
	for i in range(5):
		await get_tree().process_frame
	game.bag_page._show_friend_multi_box_selector("friend_multi_box")
	for i in range(8):
		await get_tree().process_frame
	await _shot("res://tests/_box_sel_multi.png")
	# 服装盒子（门客服装 + 图标）
	game._safe_close("FriendBoxSelector")
	for i in range(5):
		await get_tree().process_frame
	data.items["cos_box"] = 2
	game.bag_page._show_cos_box_selector()
	for i in range(8):
		await get_tree().process_frame
	await _shot("res://tests/_box_sel_cos.png")
	print("DONE")
	get_tree().quit()
