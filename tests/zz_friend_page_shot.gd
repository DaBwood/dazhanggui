extends Node
# 截挚友页（真实页面流程），验证 FGUI 圆形列表已接进 friend_page

func _ready() -> void:
	await _run()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)


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
	print("[page] FriendFguiView=", game.has_node("PageContainer/FriendPage/ListView/FriendFguiView"))
	game.switch_page("friend")
	for i in range(14):
		await get_tree().process_frame
	await _shot("res://tests/_friend_page.png")
	print("DONE")
	get_tree().quit()
