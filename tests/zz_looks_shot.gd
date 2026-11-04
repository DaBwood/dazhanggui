extends Node
# 验证：挚友详情 → 仪容技能页（BeautyLooks.Main）
func _run() -> void:
	var game: Node = load("res://control.tscn").instantiate()
	add_child(game)
	for i in range(8):
		await get_tree().process_frame
	for nm in ["LoginGate", "LoginPopup", "SyncMask"]:
		var n: Node = game.get_node_or_null(nm)
		if n != null:
			n.queue_free()
	game._enter_game()
	for i in range(10):
		await get_tree().process_frame
	var fid := "qing_ning"
	game.data.unlock_friend(fid)
	game.switch_page("friend")
	for i in range(12):
		await get_tree().process_frame
	game.friend_page.show_friend_detail(fid)
	for i in range(10):
		await get_tree().process_frame
	game.friend_page._on_detail_tab("looks")
	for i in range(14):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_friend_looks.png")
	print("SHOT looks")
	get_tree().quit()

func _ready() -> void:
	await _run()
