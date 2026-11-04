extends Node

# 临时验证：弹窗统一前基线截图（2026-11-04）
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
	for i in range(6):
		await get_tree().process_frame
	print("[shot] viewport=", game.get_viewport_rect().size, " win=", get_viewport().get_visible_rect().size)

	# A. 工厂基础弹窗
	var pa = game._create_base_popup("基础弹窗", Vector2(420, 320))
	pa.name = "ShotBasePopup"
	var va = pa.get_child(0)
	for t in ["这一行是说明文字，用来占位。", "第二行：数值 1234", "第三行：状态正常"]:
		var l := Label.new()
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		va.add_child(l)
	var row: HBoxContainer = game.popup_button_row(va)
	var b_ok := Button.new()
	b_ok.text = "确定"
	b_ok.custom_minimum_size = Vector2(120, 44)
	row.add_child(b_ok)
	game.add_child(pa)
	for i in range(6):
		await get_tree().process_frame
	_rect("A", pa)
	print("[shot] A overflow=", pa.overflow, " avail=", Vector2(pa.avail_w, pa.avail_h), " body=", pa.body.size)
	await _shot("res://tests/_unify_after_a_base.png")
	game._safe_close("ShotBasePopup")
	for i in range(6):
		await get_tree().process_frame

	# B. 规则弹窗（素面）
	game._show_rule_popup("规则说明", "一、这是一段规则文本。\n二、第二段规则文本。\n三、第三段规则文本。")
	for i in range(8):
		await get_tree().process_frame
	await _shot("res://tests/_unify_after_b_rule.png")
	for ch in game.get_children():
		if ch.has_meta("popup_mask"):   # 【改】窗根不再是 PanelContainer，按弹窗元数据清理
			ch.queue_free()
	for i in range(6):
		await get_tree().process_frame

	# C. 长列表弹窗（压力：20 张卡片）
	var pc = game._create_base_popup("长列表压力", Vector2(500, 640))
	pc.name = "ShotListPopup"
	var vc = pc.get_child(0)
	var sc: VBoxContainer = game.popup_scroll(vc)
	for i in range(20):
		var card: VBoxContainer = game.popup_card(sc, 64)
		var t := Label.new()
		t.text = "第 %d 项：门客资质 +%d" % [i + 1, i * 3]
		card.add_child(t)
	game.add_child(pc)
	for i in range(8):
		await get_tree().process_frame
	_rect("C", pc)
	print("[shot] C overflow=", pc.overflow, " avail=", Vector2(pc.avail_w, pc.avail_h), " body=", pc.body.size)
	await _shot("res://tests/_unify_after_c_list.png")
	pc._scroll_by(240)   # 滚一半，验上下遮挡带是否盖住滚动内容
	for i in range(4):
		await get_tree().process_frame
	await _shot("res://tests/_unify_after_c2_list_scrolled.png")
	game._safe_close("ShotListPopup")
	for i in range(6):
		await get_tree().process_frame

	# D. 背包道具详情
	game.switch_page("bag")
	game.switch_page("bag")
	for i in range(30):
		await get_tree().process_frame
	var fv = game.bag_page._fgui
	if fv._list != null and fv._list.num_items > 0:
		fv._on_cell_clicked(null, fv._list.get_child_at(0))
		for i in range(8):
			await get_tree().process_frame
		await _shot("res://tests/_unify_after_d_bagdetail.png")
		game._safe_close("ItemDetailPopup")
		for i in range(6):
			await get_tree().process_frame

	# E. 超宽声明（640×500）：验证固定窗对宽内容的裁剪表现
	var pe = game._create_base_popup("超宽内容", Vector2(640, 500))
	pe.name = "ShotWidePopup"
	var ve = pe.get_child(0)
	var wide := Label.new()
	wide.text = "这是一段很长的说明文字，用来验证 640 宽声明在固定窗里会不会溢出到金边外面。"
	wide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wide.custom_minimum_size = Vector2(600, 0)
	ve.add_child(wide)
	game.add_child(pe)
	for i in range(8):
		await get_tree().process_frame
	_rect("E", pe)
	await _shot("res://tests/_unify_after_e_wide.png")
	game._safe_close("ShotWidePopup")
	for i in range(6):
		await get_tree().process_frame

	# F. 声明 560×640 但内容很短：验证「不再随内容变高矮」
	var pf = game._create_base_popup("短内容", Vector2(560, 640))
	pf.name = "ShotShortPopup"
	var vf = pf.get_child(0)
	var lf := Label.new()
	lf.text = "只有一行"
	lf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vf.add_child(lf)
	game.add_child(pf)
	for i in range(8):
		await get_tree().process_frame
	await _shot("res://tests/_unify_after_f_short.png")
	game._safe_close("ShotShortPopup")
	for i in range(6):
		await get_tree().process_frame

	# G. 内容直接塞进 vbox、高度超过固定窗（验证「上下滚动 + 滚动条隐藏 + 上下遮挡带」）
	var pg = game._create_base_popup("溢出自检", Vector2(500, 640))
	pg.name = "ShotOverflowPopup"
	var vg = pg.get_child(0)
	for i in range(14):
		var lg := Label.new()
		lg.text = "第 %d 行：超出固定窗高度后应能上下滚动，且不画滚动条" % (i + 1)
		lg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vg.add_child(lg)
	game.add_child(pg)
	for i in range(8):
		await get_tree().process_frame
	print("[shot] G overflow=", pg.overflow, " avail=", Vector2(pg.avail_w, pg.avail_h), " body=", pg.body.size, " scroll_y=", pg.scroll_y, " band=", pg.band_mask.visible)
	await _shot("res://tests/_unify_after_g_overflow.png")
	pg._scroll_by(220)
	for i in range(4):
		await get_tree().process_frame
	print("[shot] G scrolled scroll_y=", pg.scroll_y, " body_pos=", pg.body.position)
	await _shot("res://tests/_unify_after_g2_overflow_scrolled.png")
	game._safe_close("ShotOverflowPopup")
	for i in range(6):
		await get_tree().process_frame

	get_tree().quit()

func _rect(tag: String, p: Control) -> void:
	print("[shot] ", tag, " pos=", p.position, " size=", p.size, " scale=", p.scale, " global=", p.get_global_rect())

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] saved ", path, " ", img.get_size())
