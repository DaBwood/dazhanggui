extends Node
# 临时截图：挚友 FGUI 列表（圆形半身格）

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
	var ids: Array = []
	for fid in data.FRIEND_CONFIGS.keys():
		ids.append(fid)
	ids.sort()
	var rows: Array = []
	for fid in ids.slice(0, 9):
		var cfg: Dictionary = data.FRIEND_CONFIGS[fid]
		rows.append({
			"id": fid,
			"name": cfg.get("name", fid),
			"portrait": "res://assets/portraits/friends_half/%s.png" % fid,
			"friendly": int(cfg.get("friendly", 0)) + 1000,
			"talent": int(cfg.get("talent", 0)) + 500,
		})
	var script: GDScript = load("res://ui/pages/friend_fgui_view.gd")
	var view = script.new(game)
	game.add_child(view)
	view.ensure_built(game)
	view.refresh(rows)
	for i in range(10):
		await get_tree().process_frame
	await _shot("res://tests/_friend_fgui.png")
	print("rows=", rows.size())
	get_tree().quit()
