extends Node
# 临时截图：解锁两套门客服装后，背包里应出现服装条目 + 详情弹窗

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

	var data = game.data
	# 新档没有门客；这里直接造一位门客的状态，解锁两套服装，只为验证背包陈列
	var hid := "li_bai"
	var cfgs: Array = data.costume_system.get_hero_costume_cfgs(hid)
	var st: Dictionary = {}
	for i in range(mini(2, cfgs.size())):
		st[str(cfgs[i].get("id", ""))] = {"stock": 1, "base": 1, "extra": 0}
	data.heroes[hid] = {"costumes": st}
	print("[test] seed hero=", hid, " unlocked=", st.keys())

	game.switch_page("bag")
	for i in range(12):
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	# 滚到底：服装条目排在道具之后
	var fv0 = game.bag_page.get("_fgui")
	if fv0 != null and fv0._lists.size() > 0:
		var sp = fv0._lists[0].scroll_pane
		if sp != null:
			sp.perc_y = 1.0
	for i in range(8):
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await _shot("res://tests/_bag_cos.png")

	var fv = game.bag_page.get("_fgui")
	if fv != null:
		var ids: Array = fv._tab_data[0]
		var found := ""
		for one in ids:
			if str(one).begins_with("cos:"):
				found = str(one)
				break
		print("[test] cos cells=", ids.filter(func(x): return str(x).begins_with("cos:")).size(), " first=", found)
		for one in ids:
			if str(one).begins_with("cos:"):
				print("[test] ", one, " meta=", fv._cos_meta(str(one)), " tier=", fv._quality_for(str(one)))
		if found != "":
			game.bag_page._show_cos_detail_popup("li_bai_cos01")
			for i in range(14):
				await get_tree().process_frame
			await get_tree().create_timer(0.3).timeout
			var pop = game.get_node_or_null("ItemDetailPopup")
			print("[test] popup=", pop, " vis=", pop.visible if pop != null else "-",
				" pos=", pop.position if pop != null else "-", " size=", pop.size if pop != null else "-",
				" kids=", pop.get_child_count() if pop != null else -1)
			await _shot("res://tests/_bag_cos_detail.png")
	print("SHOTS_DONE")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
