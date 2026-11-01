extends Node

# 临时验证：实例化主场景→跳过登录门→切背包页→逐项验证 FGUI 背包
func _ready() -> void:
	var main_scene: PackedScene = load("res://control.tscn")
	var game = main_scene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in ["LoginGate", "LoginPopup", "OfflineHintPopup", "SyncMask"]:
		if game.has_node(n):
			game.get_node(n).visible = false
	game._enter_game()
	game.switch_page("bag")
	for i in range(12):
		await get_tree().process_frame
	await _shot("res://tests/bag_fgui_preview.png")
	print("SHOT1_SAVED mode=", game.bag_page._bag_mode)

	var fv = game.bag_page._fgui
	# 页签切换：合成
	fv._on_tab_clicked(2)
	for i in range(4):
		await get_tree().process_frame
	await _shot("res://tests/bag_fgui_tab3.png")
	print("SHOT3_SAVED tab=compose")
	fv._on_tab_clicked(0)
	# 格子点击：第一格 → 详情弹窗
	if fv._list != null and fv._list.num_items > 0:
		var cell = fv._list.get_child_at(0)
		fv._on_cell_clicked(null, cell)
		for i in range(4):
			await get_tree().process_frame
		await _shot("res://tests/bag_fgui_detail.png")
		print("SHOT4_SAVED detail popup visible=", game.has_node("ItemDetailPopup"))
		game._safe_close("ItemDetailPopup")
	else:
		print("SHOT4_SKIP no items")

	# 切到旧版功能背包再截一张
	game.bag_page._on_bag_mode_toggle()
	for i in range(8):
		await get_tree().process_frame
	await _shot("res://tests/bag_legacy_preview.png")
	print("SHOT2_SAVED mode=", game.bag_page._bag_mode)
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
