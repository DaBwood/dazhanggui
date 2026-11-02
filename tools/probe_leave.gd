extends SceneTree
# 临时探针：进背包再离开，确认 PageContainer 恢复正常显示

func _init() -> void:
	var game: Node = load("uid://ppwrhv7ag3ag").instantiate()
	root.add_child(game)
	_run(game)


func _run(game: Node) -> void:
	for i in range(10):
		await process_frame
	game._enter_game()
	for i in range(6):
		await process_frame
	game.switch_page("bag")
	for i in range(10):
		await process_frame
	var pc: Control = game.get_node_or_null("PageContainer")
	print("[bag] PageContainer.visible=", pc.visible if pc != null else "null")
	game.switch_page("mansion")
	for i in range(10):
		await process_frame
	print("[mansion] PageContainer.visible=", pc.visible if pc != null else "null")
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/_leave_check.png")
	print("[shot] saved ", img.get_width(), "x", img.get_height())
	quit()
