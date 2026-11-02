extends SceneTree
# 只验证视觉：不进游戏，直接建挚友 FGUI 列表并截图

func _init() -> void:
	var host := Control.new()
	host.size = Vector2(540, 960)
	root.add_child(host)
	var script: GDScript = load("res://ui/pages/friend_fgui_view.gd")
	var view = script.new(host)
	host.add_child(view)
	view.ensure_built(host)
	var rows: Array = []
	var ids := ["qing_ning", "xiu_niang", "ling_ye_mao_nv", "zhuo_gui_shi", "nan_gong_wan", "xun_ying_shao_nv",
		"ning_yin", "yu_ji", "miao_jiang_shengnv"]
	var names := ["青凝", "秀娘", "灵夜猫女", "捉鬼师", "南宫婉", "荀莺少女", "凝音", "虞姬", "苗疆圣女"]
	for i in ids.size():
		rows.append({"id": ids[i], "name": names[i],
			"portrait": "res://assets/portraits/friends_half/%s.png" % ids[i],
			"friendly": 24063 + i * 111, "talent": 36450 + i * 91})
	view.refresh(rows)
	for i in range(10):
		await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/_friend_fgui.png")
	print("shot ", img.get_width(), "x", img.get_height())
	quit()
