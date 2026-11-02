extends Node

# 临时验证：三个挚友盒选择器（素装盒 / 锦衣盒 / 多选锦盒）
func _ready() -> void:
	var main_scene: PackedScene = load("res://control.tscn")
	var game = main_scene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in ["LoginGate", "LoginPopup", "OfflineHintPopup", "SyncMask"]:
		if game.has_node(n):
			game.get_node(n).queue_free()
	for ch in game.get_children():
		if ch is ColorRect and (ch as ColorRect).color.a >= 0.5:
			ch.queue_free()
	game._enter_game()
	for i in range(4):
		await get_tree().process_frame
	var data = game.data
	data.items["friend_multi_box"] = 1
	data.items["friend_cos_box_miao_jiang_shengnv"] = 1
	data.items["friend_jinyi_box_qing_ning"] = 1
	game.switch_page("bag")
	game.switch_page("bag")
	for i in range(30):
		await get_tree().process_frame

	var bp = game.bag_page
	bp._show_friend_multi_box_selector("friend_multi_box")
	for i in range(6):
		await get_tree().process_frame
	await _shot("res://tests/_box_multi.png")
	print("BOX1 multi selector=", game.has_node("FriendBoxSelector"))
	game._safe_close("FriendBoxSelector")
	for i in range(4):
		await get_tree().process_frame

	bp._show_friend_cos_box_selector("friend_cos_box_miao_jiang_shengnv")
	for i in range(6):
		await get_tree().process_frame
	await _shot("res://tests/_box_cos.png")
	print("BOX2 cos selector=", game.has_node("FriendBoxSelector"))
	game._safe_close("FriendBoxSelector")
	for i in range(4):
		await get_tree().process_frame

	bp._show_friend_jinyi_box_selector("friend_jinyi_box_qing_ning")
	for i in range(6):
		await get_tree().process_frame
	await _shot("res://tests/_box_jinyi.png")
	print("BOX3 jinyi selector=", game.has_node("FriendBoxSelector"))
	game._safe_close("FriendBoxSelector")
	for i in range(4):
		await get_tree().process_frame

	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
