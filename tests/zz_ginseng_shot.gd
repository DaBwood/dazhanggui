extends Node

# 临时验证：人参/百年人参 在背包里的图标与品质框
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
	data.items["ginseng"] = 3
	data.items["ginseng_1000"] = 2
	game.switch_page("bag")
	game.switch_page("bag")
	for i in range(30):
		await get_tree().process_frame
	var fv = game.bag_page._fgui
	var found := []
	for i in range(fv._list.num_items):
		var cell = fv._list.get_child_at(i)
		var idx: int = cell.get_meta("item_index", -1) if cell.has_meta("item_index") else -1
		found.append(i)
	print("cells=", fv._list.num_items)
	await _shot("res://tests/_ginseng.png")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
