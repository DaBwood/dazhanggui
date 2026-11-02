extends Node

# 临时验证：BagItem1 的 bgItem 控制器 c1 的 7 个页各自是什么品质色
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
	game.switch_page("bag")
	game.switch_page("bag")
	for i in range(24):
		await get_tree().process_frame
	var fv = game.bag_page._fgui
	var list = fv._list
	var cells = []
	for idx in range(7):
		if idx < list.num_items:
			cells.append(list.get_child_at(idx))
	print("cells=", cells.size())
	for i in range(cells.size()):
		var bg = cells[i].get_child("bgItem")
		var ctl = bg.get_controller("c1")
		print("cell", i, " pages=", ctl.page_names if ctl != null else "no ctrl")
		ctl.selected_index = i
		# 用一个确定的图标，避免看不出底图
		var icon = cells[i].get_child("icon")
		if icon != null:
			icon.url = "res://assets/items/icons/101000.png"
		var cnt = cells[i].get_child("txtCount")
		if cnt != null:
			cnt.text = "P%d" % i
	for i in range(6):
		await get_tree().process_frame
	await _shot("res://tests/_quality_pages.png")
	print("QSHOT ok")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
