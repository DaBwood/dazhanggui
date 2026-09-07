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
const QUALITY_COLORS: Array = ["#ffd700", "#c77dff", "#4da6ff", "#69c96b", "#b0b0b0"]

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
	for cid in owned_ids + unowned_ids:
		grid.add_child(_make_coll_card(cid))

# 藏品卡片：已获显示★/Lv与效果摘要；未获显示碎片进度（点击都进详情）
func _make_coll_card(cid: String) -> Button:
	var sys = data.collection_system
	var coll = sys.get_collection(cid)
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(270, 84)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_PASS   # 坑#10：滚动穿透
	btn.add_theme_font_size_override("font_size", 12)
	if sys.is_owned(cid):
		var sp: Dictionary = coll.get("special", {})
		var brief = sp.get("desc", "")
		if brief.length() > 22:
			brief = brief.substr(0, 22) + "…"
		btn.text = "%s ★%d Lv.%d\n%s" % [coll.get("name", cid), sys.get_star(cid), sys.get_level(cid), brief]
	else:
		var info = sys.get_synthesize_info(cid)
		btn.text = "%s（未获得）\n碎片 %d/%d" % [coll.get("name", cid), info.have, info.need]
		btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
	btn.pressed.connect(_show_detail.bind(cid))
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
	# 状态行
	if _detail_status != "":
		var st = Label.new()
		st.text = _detail_status
		st.add_theme_color_override("font_color", Color("#ffd700"))
		vbox.add_child(st)
	var q = int(coll.get("quality", 4))
	var head = Label.new()
	head.text = "%s ★%d Lv.%d" % [QUALITY_NAMES[q], sys.get_star(cid), sys.get_level(cid)]
	head.add_theme_color_override("font_color", Color(QUALITY_COLORS[q]))
	vbox.add_child(head)
	# 效果说明
	var base_desc = Label.new()
	base_desc.text = "基础：" + coll.get("base", {}).get("desc", "")
	base_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(base_desc)
	var sp_desc = Label.new()
	sp_desc.text = "特殊：" + coll.get("special", {}).get("desc", "")
	sp_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sp_desc)
	if not coll.get("base", {}).get("wired", false) and coll.get("special", {}).get("kind", "display") == "display":
		var tip = Label.new()
		tip.text = "（该藏品效果将在后续版本接入）"
		tip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(tip)
	if not sys.is_owned(cid):
		# 合成区
		var info = sys.get_synthesize_info(cid)
		var line = Label.new()
		line.text = "碎片 %d/%d" % [info.have, info.need]
		vbox.add_child(line)
		var btn = Button.new()
		btn.text = "合成"
		btn.disabled = not info.ok
		btn.pressed.connect(func():
			var r = sys.synthesize(cid)
			_detail_status = r.msg
			_show_detail(cid))
		vbox.add_child(btn)
	else:
		# 自选门客区
		if coll.get("base", {}).get("target", "") == "pick" or coll.get("special", {}).get("kind", "") == "pick_pct":
			var pick = sys.get_pick(cid)
			var pname = data.heroes[pick].get("name", pick) if pick != "" and data.heroes.has(pick) else "未选择"
			var row = HBoxContainer.new()
			vbox.add_child(row)
			var pl = Label.new()
			pl.text = "自选门客：%s" % pname
			pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(pl)
			var pb = Button.new()
			pb.text = "选择"
			pb.pressed.connect(_show_pick_selector.bind(cid))
			row.add_child(pb)
		# 升级区
		var item = sys.get_upgrade_item(cid)
		var cost = sys.get_upgrade_cost(cid)
		var have = int(data.items.get(item, 0))
		var iname = data.ITEM_CONFIG.get(item, {}).get("name", item)
		var ul = Label.new()
		ul.text = "升级：%s×%d（拥有 %d）" % [iname, cost, have]
		vbox.add_child(ul)
		var urow = HBoxContainer.new()
		vbox.add_child(urow)
		var ub = Button.new()
		ub.text = "升级"
		ub.disabled = not sys.can_upgrade(cid)
		ub.pressed.connect(func():
			var r = sys.upgrade(cid, false)
			_detail_status = r.msg
			_show_detail(cid))
		urow.add_child(ub)
		var cb = CheckBox.new()
		cb.text = "十连"
		cb.button_pressed = _batch
		cb.toggled.connect(func(on): _batch = on)
		urow.add_child(cb)
		var ub10 = Button.new()
		ub10.text = "升级十次"
		ub10.disabled = not sys.can_upgrade(cid)
		ub10.pressed.connect(func():
			var r = sys.upgrade(cid, true)
			_detail_status = r.msg
			_show_detail(cid))
		urow.add_child(ub10)
		# 晋升区
		var scost = sys.get_star_up_cost(cid)
		var shave = sys.get_frag_have(q, cid)
		var sl = Label.new()
		sl.text = "晋升：碎片×%d（拥有 %d）" % [scost, shave]
		vbox.add_child(sl)
		var sb = Button.new()
		sb.text = "晋升"
		sb.disabled = not sys.can_star_up(cid)
		sb.pressed.connect(func():
			var r = sys.star_up(cid)
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
		if not data.is_hero_owned(hid):
			continue
		var b = Button.new()
		b.text = "%s（%s · 赚速%s）" % [data.heroes[hid].get("name", hid), data.heroes[hid].get("category", ""), data.format_number(data.get_hero_income(hid))]
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.pressed.connect(func():
			data.collection_system.set_pick(cid, hid)
			_detail_status = "已选择 " + data.heroes[hid].get("name", hid)
			_close_node("CollectionPickPopup")
			_show_detail(cid))
		list.add_child(b)
	c._add_ok_button(vbox, func(): _close_node("CollectionPickPopup"), "取消")
	c.add_child(panel)

# 套装锦盒：道具id suitbox_XX ↔ 套装 s_XX，任选成员藏品碎片，支持批量使用
func show_suit_frag_box_selector(item_id: String):
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
	var popup = c._create_base_popup("%s（拥有%d个）" % [box_name, owned], Vector2(480, 520))
	popup.name = "SuitFragBoxSelector"
	var vbox = popup.get_child(0)
	# 【新增】批量使用：先选数量（×1 / ×10 / ×全部），再选成员
	var ctx = {"n": 1}
	var count_row = HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	count_row.add_theme_constant_override("separation", 8)
	vbox.add_child(count_row)
	var count_lbl = Label.new()
	count_lbl.text = "使用数量：%d" % ctx["n"]
	count_row.add_child(count_lbl)
	for n_opt in [1, 10, -1]:   # -1=全部
		var nb = Button.new()
		nb.text = "全部" if n_opt == -1 else "×%d" % n_opt
		nb.custom_minimum_size = Vector2(70, 36)
		nb.set_meta("n", n_opt)
		nb.pressed.connect(func():
			var opt = int(nb.get_meta("n"))
			ctx["n"] = owned if opt == -1 else mini(opt, owned)
			count_lbl.text = "使用数量：%d" % ctx["n"])
		count_row.add_child(nb)
	var hint = Label.new()
	hint.text = "选择成员，按所选数量一次性获得碎片"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(hint)
	for cid in suit.get("members", []):
		var coll = sys.get_collection(cid)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s（当前碎片 %d）" % [coll.get("name", cid), sys.get_frag_count(cid)]
		row.add_child(lbl)
		var btn = Button.new()
		btn.text = "选择"
		btn.custom_minimum_size = Vector2(80, 40)
		# 【新增】批量：扣 use_n 个锦盒 + 该成员碎片×use_n（上限为拥有数）
		btn.pressed.connect(func():
			var n = mini(int(ctx["n"]), int(data.items.get(item_id, 0)))
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
		var el = Label.new()
		el.text = "套装效果：" + suit.get("effect", "")
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if suit.get("kind", "display") == "display":
			el.text += "（后续接入）"
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
