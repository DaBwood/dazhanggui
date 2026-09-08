class_name CollectionView
extends RefCounted

# ============================================================
# 藏品全屏页（府邸【藏品】入口进入）
# 层级：CollectionPage z35（同兽魂页）；页内弹窗 z40
# 三个页签：藏宝阁（已获得在上/未获得在下，按品质分开展示）/ 套装 / 淘宝
# ============================================================

var c      # game_controller 根脚本引用
var data   # GameData 中枢引用

var _view: String = "main"   # main=三按钮主页 ge=藏宝阁 ta=套装 tao=淘宝
var _ge_q: int = 0           # 藏宝阁当前品质页 0无双~4普通
var _batch: bool = false         # 十连勾选记忆
var _detail_status: String = ""  # 详情弹窗操作结果行
var _body = null   # 内容区引用（整页重建时更新，避免靠节点路径找）

const QUALITY_NAMES: Array = ["无双", "传奇", "卓越", "优秀", "普通"]
# 【改】统一品质色：无双红 / 传奇橙 / 卓越紫 / 优秀蓝 / 普通白
const QUALITY_COLORS: Array = ["#e74c3c", "#e67e22", "#9b59b6", "#3498db", "#f2f2f2"]

func _init(p_c):
	c = p_c
	data = p_c.data

# ---------- 页面开关 ----------
func show_collection_view():
	_close_node("CollectionPage")
	_close_node("CollectionDetailPopup")
	_close_node("CollectionPickPopup")
	_close_node("CollectionResultPopup")
	_detail_status = ""
	# 根面板：禁用锚点预设（坑#3），显式铺满
	var page = Panel.new()
	page.name = "CollectionPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	page.add_theme_stylebox_override("panel", bg)
	var vb = VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
	# 顶栏：返回 + 标题 + 页签
	var top = HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 52)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	# 【新增】进入藏品只显示三个按钮，不再直接铺页签内容
	var back_btn = Button.new()
	back_btn.text = "< 返回" if _view == "main" else "< 主页"
	back_btn.custom_minimum_size = Vector2(90, 44)
	back_btn.pressed.connect(_on_back)
	top.add_child(back_btn)
	var title = Label.new()
	title.text = "藏品"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var pad = Control.new()
	pad.custom_minimum_size = Vector2(90, 44)
	top.add_child(pad)
	
	# 动态内容区
	var body = VBoxContainer.new()
	body.name = "CollectionBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	_body = body   # 【新增】持有内容区引用
	c.add_child(page)
	_fill_body(body)

func hide_collection_view():
	_close_node("CollectionDetailPopup")
	_close_node("CollectionPickPopup")
	_close_node("CollectionResultPopup")
	_close_node("CollectionPage")

func _on_back():
	if _view == "main":
		hide_collection_view()
		return
	# 【新增】子页面返回三按钮主页
	_view = "main"
	_detail_status = ""
	_close_node("CollectionDetailPopup")
	_close_node("CollectionPickPopup")
	_close_node("CollectionResultPopup")
	show_collection_view()

# 【新增】从主页进入子页面
func _open_view(v: String):
	if _view == v:
		return
	_view = v
	_detail_status = ""
	_close_node("CollectionDetailPopup")
	_close_node("CollectionPickPopup")
	_close_node("CollectionResultPopup")
	show_collection_view()

# 【新增】仅刷新内容区（藏宝阁切品质用，避免整页闪烁）
func _refresh_body():
	if _body and is_instance_valid(_body):
		for child in _body.get_children():
			child.queue_free()
		_fill_body(_body)

func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

# ---------- 内容填充 ----------
func _fill_body(body: VBoxContainer):
	for child in body.get_children():
		child.queue_free()
	match _view:
		"main": _fill_main(body)
		"ge": _fill_ge(body)
		"ta": _fill_ta(body)
		"tao": _fill_tao(body)

# 主页：三个入口大按钮
func _fill_main(body: VBoxContainer):
	var sys = data.collection_system
	var all = sys.get_all_collections()
	var owned_cnt = 0
	for cid in all.keys():
		if sys.is_owned(cid):
			owned_cnt += 1
	for item in [
		["ge", "藏 宝 阁", "%d/%d 件藏品" % [owned_cnt, all.size()]],
		["ta", "套 装", ""],
		["tao", "淘 宝", ""],
	]:
		var b = Button.new()
		b.custom_minimum_size = Vector2(0, 120)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		# 【改动】套装/淘宝只显示名字，藏宝阁保留进度副标题
		b.text = item[1] if item[2] == "" else "%s\n%s" % [item[1], item[2]]
		b.pressed.connect(_open_view.bind(item[0]))
		body.add_child(b)
		# 套装有可激活档位时亮红点
		if item[0] == "ta" and sys.has_activatable_suit():
			var dot = Label.new()
			dot.text = "●"
			dot.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			dot.position = Vector2(-32, 8)
			b.add_child(dot)
	# 主页也留点底部提示
	var tip = Label.new()
	tip.text = "藏品：升级与晋升提升基础属性，晋升提升特殊效果"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	body.add_child(tip)

# ===== 藏宝阁 =====
# 藏宝阁：顶部五个品质按钮切换，下面只显示当前品质的藏品
func _fill_ge(body: VBoxContainer):
	var sys = data.collection_system
	var all = sys.get_all_collections()
	# 品质切换行
	var qrow = HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 4)
	body.add_child(qrow)
	for q in range(5):
		var ids_q = []
		for cid in all.keys():
			if int(all[cid].get("quality", 4)) == q:
				ids_q.append(cid)
		var owned_q = 0
		for cid in ids_q:
			if sys.is_owned(cid):
				owned_q += 1
		var b = Button.new()
		b.text = "%s %d/%d" % [QUALITY_NAMES[q], owned_q, ids_q.size()]
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		if q == _ge_q:
			b.add_theme_color_override("font_color", Color(QUALITY_COLORS[q]))
		b.pressed.connect(func(): _ge_q = q; _refresh_body())
		qrow.add_child(b)
	# 当前品质藏品网格（已获得在上按星/级降序，未获得在下）
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var ids = []
	for cid in all.keys():
		if int(all[cid].get("quality", 4)) == _ge_q:
			ids.append(cid)
	ids.sort_custom(func(a, b): return int(all[a].get("order", 0)) < int(all[b].get("order", 0)))
	var owned_ids = ids.filter(func(i): return sys.is_owned(i))
	owned_ids.sort_custom(func(a, b): return sys.get_star(b) * 1000 + sys.get_level(b) < sys.get_star(a) * 1000 + sys.get_level(a))
	var unowned_ids = ids.filter(func(i): return not sys.is_owned(i))
	# 【新增】可合成藏品排最前：碎片够100的未获得藏品优先展示
	var synth_ids = unowned_ids.filter(func(i): return sys.get_synthesize_info(i).ok)
	var rest_ids = unowned_ids.filter(func(i): return not sys.get_synthesize_info(i).ok)
	for cid in synth_ids + owned_ids + rest_ids:
		grid.add_child(_make_coll_card(cid))

# ---------- 藏品玩家可见效果文案 ----------
# 原则：只显示当前实际效果数值，不展示后台 desc / 公式 / 计算过程

# 【新增】格式化效果数值：去掉 10.0 这类小数尾巴，百分比显示 10 / 2.5
func _fmt_effect_number(n) -> String:
	var s = "%.2f" % float(n)
	s = s.rstrip("0").rstrip(".")
	return s

# 【改】门客显示名：固定目标优先查全量门客配置，不能查 data.heroes（只含已拥有门客）
func _hero_label(hero_id: String) -> String:
	if hero_id == "":
		return "未选择"
	# 固定目标先查全量配置表：即使当前未拥有李白，也应显示"李白"
	if data._hero_configs.has(hero_id):
		return str(data._hero_configs[hero_id].get("name", hero_id))
	# 自选门客已选择时，这里作为兜底
	if data.heroes.has(hero_id):
		return str(data.heroes[hero_id].get("name", hero_id))
	return "未知门客"

# 【新增】挚友显示名：固定目标查全量挚友配置（同 _hero_label 惯例，不查 data.friends 已拥有表）
func _friend_label(friend_id: String) -> String:
	if friend_id == "":
		return "未选择"
	if data._friend_configs.has(friend_id):
		return str(data._friend_configs[friend_id].get("name", friend_id))
	return "未知挚友"

# 【新增】基础效果作用目标显示名
func _base_target_label(base: Dictionary, cid: String) -> String:
	match base.get("target", ""):
		"hero":
			return _hero_label(str(base.get("hero", "")))
		"category":
			return "%s类门客" % str(base.get("category", ""))
		"wuyan":
			return "五艳凤魁"
		"quality_min":
			return "无双及以上门客"
		"pick":
			var pick_id = data.collection_system.get_pick(cid)
			return "自选门客（%s）" % _hero_label(pick_id) if pick_id != "" else "自选门客"
		"friend":
			return _friend_label(str(base.get("friend", "")))
		"friend_category":
			return "%s类挚友" % str(base.get("category", ""))
	return "全体"

# 【新增】基础效果玩家文案：按当前等级/星数直接算结果值
func _collection_base_effect(cid: String) -> String:
	var sys = data.collection_system
	var base: Dictionary = sys.get_collection(cid).get("base", {})
	if not base.get("wired", false):
		return "基础效果：后续版本开放"
	var lv = sys.get_level(cid) if sys.is_owned(cid) else 1
	var st = sys.get_star(cid) if sys.is_owned(cid) else 1
	var stat = str(base.get("stat", ""))
	var stat_name = "资质"
	if stat == "income":
		stat_name = "赚速"
	elif stat != "apt":
		stat_name = stat
	var val = int(base.get("per_level", 0)) * lv + int(base.get("per_star", 0)) * st
	var val_txt = c.format_number(val) if stat == "income" else str(val)
	return "基础效果：%s %s +%s" % [_base_target_label(base, cid), stat_name, val_txt]

# 【新增】特殊效果玩家文案：按当前星数直接算结果值
func _collection_special_effect(cid: String) -> String:
	var sys = data.collection_system
	var sp: Dictionary = sys.get_collection(cid).get("special", {})
	var kind = str(sp.get("kind", "display"))
	if kind == "" or kind == "display":
		return "特殊效果：后续版本开放"
	var st = sys.get_star(cid) if sys.is_owned(cid) else 1
	var per_star = float(sp.get("per_star", 0))
	var is_pct = kind.ends_with("_pct")
	var target = ""
	match kind:
		"hero_pct", "hero_apt":
			target = _hero_label(str(sp.get("hero", "")))
		"group_pct", "group_apt":
			target = "五艳凤魁"
		"category_pct", "category_apt":
			target = "%s类门客" % str(sp.get("category", ""))
		"pick_pct":
			var pick_id = sys.get_pick(cid)
			target = "自选门客（%s）" % _hero_label(pick_id) if pick_id != "" else "自选门客"
		"quality_min_pct":
			target = "无双及以上门客"
		_:
			return "特殊效果：后续版本开放"
	var stat_name = "赚速" if is_pct else "资质"
	var value_txt = ""
	if is_pct:
		value_txt = "+%s%%" % _fmt_effect_number(per_star * st)
	else:
		value_txt = "+%s" % c.format_number(int(per_star * st))
	return "特殊效果：%s %s %s" % [target, stat_name, value_txt]

# 藏品卡片：已获显示★/Lv与效果摘要；未获显示碎片进度（点击都进详情）
func _make_coll_card(cid: String) -> Button:
	var sys = data.collection_system
	var coll = sys.get_collection(cid)
	var q = int(coll.get("quality", 4))
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(270, 84)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_PASS   # 坑#10：滚动穿透
	btn.add_theme_font_size_override("font_size", 12)
	# 【新增】藏品名字按品质着色：无双红/传奇橙/卓越紫/优秀蓝/普通白
	btn.add_theme_color_override("font_color", Color(QUALITY_COLORS[q]))
	if sys.is_owned(cid):
		# 【改】卡片摘要显示当前特殊效果结果值，不再贴后台 desc
		var brief = _collection_special_effect(cid).trim_prefix("特殊效果：")
		if brief.length() > 22:
			brief = brief.substr(0, 22) + "…"
		btn.text = "%s ★%d Lv.%d\n%s" % [coll.get("name", cid), sys.get_star(cid), sys.get_level(cid), brief]
	else:
		var info = sys.get_synthesize_info(cid)
		btn.text = "%s（未获得）\n碎片 %d/%d" % [coll.get("name", cid), info.have, info.need]
		# 【新增】可合成红点：碎片足够时提示可合成
		if info.ok:
			var dot = Label.new()
			dot.text = "●"
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 装饰节点不拦截点击
			dot.add_theme_font_size_override("font_size", 16)
			dot.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			dot.position = Vector2(246, 4)
			btn.add_child(dot)
	# 【新增】打开新详情时清空上一次操作提示，避免跨藏品串文案
	btn.pressed.connect(func():
		_detail_status = ""
		_show_detail(cid))
	return btn

# 藏品详情弹窗：合成/升级/晋升/自选门客
func _show_detail(cid: String):
	_close_node("CollectionDetailPopup")
	var sys = data.collection_system
	var coll = sys.get_collection(cid)
	var panel = c._create_base_popup(coll.get("name", cid), Vector2(520, 560))
	panel.name = "CollectionDetailPopup"
	panel.z_index = 40
	var vbox = panel.get_child(0)
	# 【改】藏品详情内容整体居中
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# 【改】只显示失败提示；成功不额外加一行，避免弹窗高度跳动
	if _detail_status != "":
		var st = Label.new()
		st.text = _detail_status
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.add_theme_color_override("font_color", Color("#ff6666"))
		vbox.add_child(st)

	var q = int(coll.get("quality", 4))
	var head = Label.new()
	head.text = "%s ★%d Lv.%d" % [QUALITY_NAMES[q], sys.get_star(cid), sys.get_level(cid)]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_color_override("font_color", Color(QUALITY_COLORS[q]))
	vbox.add_child(head)

	# 【改】玩家可见效果：直接显示当前计算结果值，不展示后台 desc / 公式
	var effect_title = Label.new()
	effect_title.text = "效果预览" if not sys.is_owned(cid) else "当前效果"
	effect_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(effect_title)

	var base_desc = Label.new()
	base_desc.text = _collection_base_effect(cid)
	base_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(base_desc)

	var sp_desc = Label.new()
	sp_desc.text = _collection_special_effect(cid)
	sp_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sp_desc)

	if not sys.is_owned(cid):
		# 合成区
		var info = sys.get_synthesize_info(cid)
		var line = Label.new()
		line.text = "碎片 %d/%d" % [info.have, info.need]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(line)

		var btn = Button.new()
		btn.text = "合成"
		btn.disabled = not info.ok
		# 【改】成功不显示“已合成/Lv.X”文字，失败才显示原因
		btn.pressed.connect(func():
			var r = sys.synthesize(cid)
			if r.ok:
				_detail_status = ""
				_refresh_body()
			else:
				_detail_status = r.msg
			_show_detail(cid))
		vbox.add_child(btn)
	else:
		# 自选门客区
		if coll.get("base", {}).get("target", "") == "pick" or coll.get("special", {}).get("kind", "") == "pick_pct":
			var pick = sys.get_pick(cid)
			var pname = _hero_label(pick)
			var row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_child(row)

			var pl = Label.new()
			pl.text = "自选门客：%s" % pname
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(pl)

			var pb = Button.new()
			pb.text = "选择"
			# 【新增】确保按钮自身接收点击
			pb.mouse_filter = Control.MOUSE_FILTER_STOP
			pb.pressed.connect(_show_pick_selector.bind(cid))
			row.add_child(pb)

		# 升级区
		var item = sys.get_upgrade_item(cid)
		var cost = sys.get_upgrade_cost(cid)
		var have = int(data.items.get(item, 0))
		var iname = data.ITEM_CONFIG.get(item, {}).get("name", item)
		var ul = Label.new()
		ul.text = "升级：%s×%d（拥有 %d）" % [iname, cost, have]
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ul.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(ul)

		var urow = HBoxContainer.new()
		urow.alignment = BoxContainer.ALIGNMENT_CENTER
		urow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(urow)

		var ub = Button.new()
		ub.text = "升级"
		ub.disabled = not sys.can_upgrade(cid)
		# 【改】去掉独立“升级十次”按钮；十连勾选决定一次升十次
		# 【改】成功不显示“升级成功 Lv.X”，等级数字变化本身就是反馈
		ub.pressed.connect(func():
			var r = sys.upgrade(cid, _batch)
			if r.ok:
				_detail_status = ""
				_refresh_body()
			else:
				_detail_status = r.msg
			_show_detail(cid))
		urow.add_child(ub)

		var cb = CheckBox.new()
		cb.text = "十连"
		cb.button_pressed = _batch
		cb.toggled.connect(func(on): _batch = on)
		urow.add_child(cb)

		# 晋升区
		var scost = sys.get_star_up_cost(cid)
		var shave = sys.get_frag_have(q, cid)
		var sl = Label.new()
		sl.text = "晋升：碎片×%d（拥有 %d）" % [scost, shave]
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(sl)

		var sb = Button.new()
		sb.text = "晋升"
		sb.disabled = not sys.can_star_up(cid)
		# 【改】成功不显示“晋升成功 ★X”，星级变化本身就是反馈
		sb.pressed.connect(func():
			var r = sys.star_up(cid)
			if r.ok:
				_detail_status = ""
				_refresh_body()
			else:
				_detail_status = r.msg
			_show_detail(cid))
		vbox.add_child(sb)

	c._add_ok_button(vbox, func(): _close_node("CollectionDetailPopup"), "关闭")
	c.add_child(panel)

# 自选门客选择器（已拥有门客列表）
func _show_pick_selector(cid: String):
	_close_node("CollectionPickPopup")
	var panel = c._create_base_popup("选择门客", Vector2(480, 560))
	panel.name = "CollectionPickPopup"
	panel.z_index = 40
	var vbox = panel.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# 按实时赚速降序（项目三页排序约定）
	var ids = data.heroes.keys()
	ids.sort_custom(func(a, b): return data.get_hero_income(b) < data.get_hero_income(a))
	for hid in ids:
		var b = Button.new()
		b.text = "%s（%s · 赚速%s）" % [data.heroes[hid].get("name", hid), data.heroes[hid].get("category", ""), c.format_number(data.get_hero_income(hid))]
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(func():
			data.collection_system.set_pick(cid, hid)
			# 【改】选择成功不弹文字；详情里的“自选门客：XXX”会直接变化
			_detail_status = ""
			_close_node("CollectionPickPopup")
			_refresh_body()   # 【新增】同步刷新藏宝阁列表
			_show_detail(cid))
		list.add_child(b)
	c._add_ok_button(vbox, func(): _close_node("CollectionPickPopup"), "取消")
	c.add_child(panel)

# 【改】套装锦盒：道具id suitbox_XX ↔ 套装 s_XX，任选成员藏品碎片；数量由背包详情弹窗带入
func show_suit_frag_box_selector(item_id: String, p_qty: int = 1):
	var sys = data.collection_system
	var suit_id = "s_" + item_id.trim_prefix("suitbox_")
	var suit = sys.get_suits().get(suit_id, {})
	if suit.is_empty():
		c._show_stage_hint("锦盒配置缺失")
		return
	var owned = int(data.items.get(item_id, 0))
	if owned < 1:
		c._show_stage_hint("锦盒不足！")
		return
	var box_name = data.ITEM_CONFIG.get(item_id, {}).get("name", item_id)
	var popup = c._create_base_popup("%s（使用%d个）" % [box_name, p_qty], Vector2(480, 520))
	popup.name = "SuitFragBoxSelector"
	var vbox = popup.get_child(0)
	# 【改】数量由详情弹窗选择器带入，不再重复选择
	var hint = Label.new()
	hint.text = "选择成员，获得该碎片 ×%d" % p_qty
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(hint)
	for cid in suit.get("members", []):
		var coll = sys.get_collection(cid)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color(QUALITY_COLORS[int(coll.get("quality", 4))]))
		lbl.text = "%s（当前碎片 %d）" % [coll.get("name", cid), sys.get_frag_count(cid)]
		row.add_child(lbl)
		var btn = Button.new()
		btn.text = "选择"
		btn.custom_minimum_size = Vector2(80, 40)
		btn.pressed.connect(func():
			var n = mini(p_qty, int(data.items.get(item_id, 0)))
			if n < 1:
				return
			data.items[item_id] = int(data.items.get(item_id, 0)) - n
			sys.add_frags(cid, n)
			popup.queue_free()
			c._show_stage_hint("获得【%s】碎片×%d" % [coll.get("name", cid), n])
			c.update_bag_list())
		row.add_child(btn)
		vbox.add_child(row)
	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 【新增】套装效果玩家文案：已接入类按"已激活档数×每档值"显示当前实际加成；未接入统一"后续版本开放"
func _suit_effect_label(sid: String, suit: Dictionary) -> String:
	var act = int(data.collection_system.get_suit_info(sid).activated)
	var per = float(suit.get("per_tier", 0))
	var cur = _fmt_effect_number(per * act)   # 当前已激活的总值
	match str(suit.get("kind", "display")):
		"awaken_limit":
			return "套装效果：珍兽觉醒上限 +%d（已激活%d档）" % [int(per) * act, act]
		"beast_level_cap":
			return "套装效果：珍兽等级上限 +%d（已激活%d档）" % [int(per) * act, act]
		"guardian_pct":
			return "套装效果：守护灵提供的赚钱 +%s%%（已激活%d档）" % [cur, act]
		"quality_min_pct":
			return "套装效果：无双及以上门客赚钱 +%s%%（已激活%d档）" % [cur, act]
		"soul_cell_pct":
			return "套装效果：%s类门客每格有效魂石赚钱 +%s%%（已激活%d档）" % [suit.get("category", ""), cur, act]
		"wuyan_pct":
			return "套装效果：五艳凤魁门客赚钱 +%s%%（已激活%d档）" % [cur, act]
		"hero_pct":
			return "套装效果：%s赚钱 +%s%%（已激活%d档）" % [_hero_label(str(suit.get("hero", ""))), cur, act]
	return "套装效果：后续版本开放"

# ===== 套装 =====
func _fill_ta(body: VBoxContainer):
	var sys = data.collection_system
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for sid in sys.get_suits().keys():
		var suit = sys.get_suits()[sid]
		var info = sys.get_suit_info(sid)
		var box = PanelContainer.new()
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		box.add_child(vb)
		list.add_child(box)
		# 标题行 + 激活按钮/红点
		var row = HBoxContainer.new()
		vb.add_child(row)
		var tl = Label.new()
		tl.text = "【%s】 已激活 %d/%d 档" % [suit.get("name", sid), info.activated, info.total]
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.add_theme_font_size_override("font_size", 15)
		tl.add_theme_color_override("font_color", Color("#ffd700"))
		row.add_child(tl)
		if info.can_activate:
			var dot = Label.new()
			dot.text = "● "
			dot.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			row.add_child(dot)
		var ab = Button.new()
		ab.text = "激活"
		ab.custom_minimum_size = Vector2(80, 34)
		ab.disabled = not info.can_activate
		ab.pressed.connect(func():
			sys.activate_suit(sid)
			# 激活后重建整页（刷新页签红点）
			show_collection_view())
		row.add_child(ab)
		# 成员与进度
		var members_text = []
		for m in suit.get("members", []):
			var cname = sys.get_collection(m).get("name", m)
			members_text.append("%s ★%d" % [cname, sys.get_star(m) if sys.is_owned(m) else 0])
		var ml = Label.new()
		ml.text = "成员：" + "、".join(members_text)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(ml)
		var pl = Label.new()
		pl.text = "成员最低★%d，已达 %d 档" % [info.min_star, info.reached]
		pl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
		vb.add_child(pl)
		# 【改】按已激活档数显示当前实际效果值；未接入套装不再贴配置原文
		var el = Label.new()
		el.text = _suit_effect_label(sid, suit)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(el)

# ===== 淘宝 =====
func _fill_tao(body: VBoxContainer):
	var sys = data.collection_system
	# 券信息
	var tl = Label.new()
	tl.text = "淘宝券 ×%d（获取途径：活动）" % sys.get_ticket_count()
	tl.add_theme_font_size_override("font_size", 16)
	body.add_child(tl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	var b1 = Button.new()
	b1.text = "抽一次"
	b1.custom_minimum_size = Vector2(160, 52)
	b1.add_theme_font_size_override("font_size", 16)
	b1.disabled = not sys.can_lottery(1)
	b1.pressed.connect(func(): _do_roll(1))
	row.add_child(b1)
	var b10 = Button.new()
	b10.text = "抽十次"
	b10.custom_minimum_size = Vector2(160, 52)
	b10.add_theme_font_size_override("font_size", 16)
	b10.disabled = not sys.can_lottery(10)
	b10.pressed.connect(func(): _do_roll(10))
	row.add_child(b10)
	var bp = Button.new()
	bp.text = "概率一览"
	bp.pressed.connect(_show_probability)
	row.add_child(bp)
	# 奖池说明
	var tip = Label.new()
	tip.text = "可抽取：传奇藏品专属碎片 / 通用碎片（卓越·优秀·普通）/ 升级光（萤虫光~日轮光）"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	body.add_child(tip)

func _do_roll(n: int):
	var r = data.collection_system.roll(n)
	if not r.ok:
		return
	_show_results(r.results)

# 抽奖结果弹窗
func _show_results(results: Array):
	_close_node("CollectionResultPopup")
	var panel = c._create_base_popup("淘宝结果", Vector2(480, 560))
	panel.name = "CollectionResultPopup"
	panel.z_index = 40
	var vbox = panel.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for e in results:
		var label = Label.new()
		var txt = e.get("label", "")
		if e.get("type") == "item":
			var iname = data.ITEM_CONFIG.get(e.get("item", ""), {}).get("name", e.get("item", ""))
			txt = "%s×%d" % [iname, int(e.get("count", 0))]
		label.text = "🎁 " + txt
		list.add_child(label)
	c._add_ok_button(vbox, func():
		_close_node("CollectionResultPopup")
		_refresh_body(), "确定")
	c.add_child(panel)

# 概率一览弹窗
func _show_probability():
	_close_node("CollectionResultPopup")
	var panel = c._create_base_popup("淘宝概率", Vector2(480, 560))
	panel.name = "CollectionResultPopup"
	panel.z_index = 40
	var vbox = panel.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var total = 0
	for e in data.collection_system.get_lottery_pool():
		total += int(e.get("weight", 0))
	for e in data.collection_system.get_lottery_pool():
		var label = Label.new()
		label.text = "%s  %.2f%%" % [e.get("label", ""), float(e.get("weight", 0)) * 100.0 / maxi(total, 1)]
		list.add_child(label)
	c._add_ok_button(vbox, func(): _close_node("CollectionResultPopup"), "关闭")
	c.add_child(panel)
