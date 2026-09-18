# ============================================================
# 酒坊玩法全屏页（商铺地图 酒坊「▶」入口，层级：WineryPage z35，弹窗 z40，同药铺/酒肆惯例）
# 2026-09-18 按酒坊设计方案 v1.0 实现（批次②：主页 + 三作坊 + 酿酒 + 采买）
# 主页（方案 §0）：顶栏返回 + 右上【勋章】+ 资源行(酒艺值/累计酒香) + 三作坊卡 + 底部五入口
#   【酒客故事】【名酒记】【品酒】【勋章】= 批次③接入，现统一提示"后续版本开放"（协作规则 10）
# 弹窗（方案 §9）：作坊（五流程行+同步升级勾选+概率详情ⓘ）/ 酿酒（三材料+滑杆批量）/ 采买（商店/背包双页签）
# 即时结算：无后台队列/无节拍定时器（区别于药铺），操作后整页重建刷新（同医馆惯例）
# 红点口径（照药铺互不穿透）：作坊卡红点=该坊任意流程可升（酒艺值够）；地图「▶」红点批次②不挂（酒坊无"满"类状态）
# ============================================================
class_name WineryView
extends RefCounted

var c      # game_controller 根脚本引用
var data: GameData   # 数据中枢（显式标注 GameData：让中枢字段被静态引用，消 UNUSED 提示，同 clinic/drugshop 先例）

var _popup_kind: String = ""     # 当前弹窗类型："" / "workshop" / "brew" / "buy"
var _popup_id: String = ""       # 作坊弹窗的作坊 id
var _buy_tab: String = "shop"    # 采买弹窗页签 shop / bag（类变量记忆，不依赖节点重建默认值，协作踩坑 35）
var _drink_tab: String = "huaguo"   # 品酒弹窗酒架页签（按材料：huaguo/gaoliang/daogu）
var _story_tab: String = "all"      # 酒客故事筛选页签（all/士/农/工/商/侠）

const QUALITY_NAMES := ["普通", "优秀", "卓越", "传奇", "无双"]
const QUALITY_COLORS := ["#f2f2f2", "#3498db", "#9b59b6", "#e67e22", "#e74c3c"]   # 品质色规范（档案三-40）

func _init(p_c):
	c = p_c
	data = p_c.data

func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

func _sys() -> WinerySystem:
	return data.winery_system

# ---------- 页面开关 ----------
func show_winery_view():
	_close_node("WineryPage")
	_close_node("WineryPopup")
	var page := Panel.new()
	page.name = "WineryPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	page.add_theme_stylebox_override("panel", bg)
	c.add_child(page)
	_build(page)

func hide_winery_view():
	_popup_kind = ""
	_popup_id = ""
	_close_node("WineryPage")
	_close_node("WineryPopup")

# ---------- 页面构建 ----------
func _build(page: Panel):
	var vb := VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
	# 顶栏：返回 + 标题 + 右上【勋章】（批次③接入勋章弹窗，现提示后续开放）
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 48)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(90, 42)
	back_btn.pressed.connect(hide_winery_view)
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "酒坊"
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	var medal_sp := Control.new()
	medal_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(medal_sp)
	var medal_btn := Button.new()
	medal_btn.text = "勋章"
	medal_btn.custom_minimum_size = Vector2(84, 42)
	medal_btn.pressed.connect(func(): _show_medal_popup())
	top.add_child(medal_btn)
	_add_btn_dot(medal_btn, _sys().can_upgrade_medal().get("ok", false))   # 内部红点：勋章可升
	# 资源行：酒艺值（升流程消耗）/ 累计酒香（勋章进度），数值已可见，操作不弹字（协作规则 28）
	var res := Label.new()
	res.text = "酒艺值 %s（升级消耗）　累计酒香 %s（勋章进度）" % [
		c.format_number(_sys().jiuyi), c.format_number(_sys().get_jiuxiang())]
	res.add_theme_color_override("font_color", Color("#9a93b8"))
	res.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(res)
	# 三作坊卡（点击弹五流程界面；红点=该坊任意流程可升）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	for w in _sys().get_workshop_list():
		var wid: String = str(w.get("id", ""))
		var card := Button.new()
		card.text = "%s　五流程合计 S=%d 级\n单次酿造 酒香+%d / 酒艺+%d（点按进入）" % [
			w.get("name", wid), _sys().get_workshop_S(wid),
			_sys().get_brew_output(wid), _sys().get_brew_output(wid)]
		card.custom_minimum_size = Vector2(0, 72)
		card.add_theme_font_size_override("font_size", 18)
		var wid_c: String = wid
		card.pressed.connect(func(): _show_workshop_popup(wid_c))
		body.add_child(card)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#e74c3c"))
		dot.add_theme_font_size_override("font_size", 15)
		dot.position = Vector2(c.get_viewport_rect().size.x - 40, 6)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 红点=本坊任一流程可升
		var upable := false
		for p in w.get("processes", []):
			if _sys().can_upgrade_process(wid, str(p.get("id", ""))).get("ok", false):
				upable = true
				break
		dot.visible = upable
		card.add_child(dot)
	# 底部入口（方案 §0：左下 酒客故事/名酒记，右下 品酒/酿酒/采买）
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, 56)
	bottom.add_theme_constant_override("separation", 8)
	vb.add_child(bottom)
	var b_story := Button.new()
	b_story.text = "酒客故事"
	b_story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_story.pressed.connect(func(): _show_story_popup())
	bottom.add_child(b_story)
	_add_btn_dot(b_story, _sys().has_claimable_bond())   # 内部红点：有可领奖门客
	var b_wines := Button.new()
	b_wines.text = "名酒记"
	b_wines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_wines.pressed.connect(func(): _show_wines_popup())
	bottom.add_child(b_wines)
	_add_btn_dot(b_wines, _has_upgradeable_wine())   # 内部红点：有可升级酒
	var b_drink := Button.new()
	b_drink.text = "品酒"
	b_drink.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_drink.pressed.connect(func(): _show_drink_popup())
	bottom.add_child(b_drink)
	_add_btn_dot(b_drink, _sys().has_satis_loop_ready())   # 内部红点：有满档满意值可换门客帖
	var b_brew := Button.new()
	b_brew.text = "酿酒"
	b_brew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_brew.pressed.connect(func(): _show_brew_popup())
	bottom.add_child(b_brew)
	var b_buy := Button.new()
	b_buy.text = "采买"
	b_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_buy.pressed.connect(func(): _show_buy_popup())
	bottom.add_child(b_buy)

# ---------- 操作后统一刷新：重建页面 + 原位重建弹窗 ----------
func _refresh():
	_close_node("WineryPage")
	show_winery_view()
	if _popup_kind == "workshop" and _popup_id != "":
		_show_workshop_popup(_popup_id)
	elif _popup_kind == "brew":
		_show_brew_popup()
	elif _popup_kind == "buy":
		_show_buy_popup()
	elif _popup_kind == "medal":
		_show_medal_popup()
	elif _popup_kind == "wines":
		_show_wines_popup()
	elif _popup_kind == "wine_info" and _popup_id != "":
		_show_wine_info(_popup_id)
	elif _popup_kind == "drink":
		_show_drink_popup()
	elif _popup_kind == "story":
		_show_story_popup()
	elif _popup_kind == "bond" and _popup_id != "":
		_show_bond_popup(_popup_id)

# ---------- 弹窗：作坊（五流程行 + 同步升级 + 概率详情ⓘ） ----------
func _show_workshop_popup(wid: String):
	_popup_kind = "workshop"
	_popup_id = wid
	_close_node("WineryPopup")
	var wcfg: Dictionary = _sys().get_workshop_cfg(wid)
	if wcfg.is_empty():
		return
	var popup: PanelContainer = c._create_base_popup(str(wcfg.get("name", wid)), Vector2(460, 520))
	popup.name = "WineryPopup"
	popup.z_index = 40   # 盖过 WineryPage(z35)，同 clinic/inn/drugshop 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child
	var vb: VBoxContainer = popup.get_child(0)
	var info := Label.new()
	info.text = "五流程合计 S=%d 级　单次酿造 酒香+%d / 酒艺+%d" % [
		_sys().get_workshop_S(wid), _sys().get_brew_output(wid), _sys().get_brew_output(wid)]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	# 同步升级勾选（一键拉平五流程，酒艺值不足自动停）
	var sync_chk := CheckBox.new()
	sync_chk.text = "同步升级（一键拉平五流程）"
	vb.add_child(sync_chk)
	# 五流程行：名称(职业) Lv.k　下级消耗酒艺 X　【升级】
	for p in wcfg.get("processes", []):
		var pid: String = str(p.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vb.add_child(row)
		var p_lv: int = _sys().get_process_lv(wid, pid)
		var p_career: String = str(p.get("career", ""))
		var lbl := Label.new()
		# 行内说人话：当前等级 + 当前给谁加多少（读取式加成实时值，2026-09-18 用户拍板：不展示后台公式）
		lbl.text = "%s　Lv.%d　%s类商铺 +%d%%" % [
			p.get("name", pid), p_lv, p_career,
			int(round(float(p_lv) * float(_sys()._st().get("career_pct_per_lv", 0.10)) * 100.0))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 40)
		if p_lv >= _sys().get_process_max_lv():
			btn.text = "满级"
			btn.disabled = true
		else:
			btn.text = "升级 %s" % c.format_number(_sys().get_process_upgrade_cost(wid, pid))   # 本次消耗直接显示在按钮上
			btn.disabled = not _sys().can_upgrade_process(wid, pid).get("ok", false)
			var pid_c: String = pid
			btn.pressed.connect(func(): _on_process_upgrade(wid, pid_c, sync_chk.button_pressed))
		row.add_child(btn)
	# 概率详情ⓘ（当前 S 五档概率，只读展示）
	var prob := Label.new()
	var parts := []
	var weights: Array = _sys().get_quality_weights(wid)
	for i in weights.size():
		parts.append("%s %.2f%%" % [QUALITY_NAMES[i], float(weights[i]) * 100.0])
	prob.text = "ⓘ 当前品质概率：" + "　".join(parts)
	prob.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(prob)
	c._add_ok_button(vb, func(): _close_popup())

func _on_process_upgrade(wid: String, pid: String, sync: bool):
	var r: Dictionary
	if sync:
		r = _sys().sync_upgrade_workshop(wid)
	else:
		r = _sys().upgrade_process(wid, pid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()   # 流程职业加成→商铺赚速变化→全局飘字
	_refresh()

# ---------- 弹窗：酿酒（三材料 + 滑杆批量 1~库存，即时结算） ----------
func _show_brew_popup():
	_popup_kind = "brew"
	_popup_id = ""
	_close_node("WineryPopup")
	var popup: PanelContainer = c._create_base_popup("酿酒（1 材料 = 1 次）", Vector2(460, 520))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	for m in _sys()._cfg().get("materials", []):
		var mid: String = str(m.get("id", ""))
		var have: int = _sys().get_material(mid)
		var head := Label.new()
		head.text = "%s　库存 %d　单次酿造 酒香+%d / 酒艺+%d" % [
			m.get("name", mid), have, _sys().get_brew_output(mid), _sys().get_brew_output(mid)]
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(head)
		# 滑杆批量（1~库存）+ 数字显示 + 酿造按钮（数量选择器用滑杆+SpinBox，同体力丹范式，不依赖手机键盘）
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vb.add_child(row)
		var slider := HSlider.new()
		slider.min_value = 1
		slider.max_value = max(1, have)
		slider.value = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var num := SpinBox.new()
		num.min_value = 1
		num.max_value = max(1, have)
		num.value = 1
		num.custom_minimum_size = Vector2(96, 40)
		row.add_child(num)
		slider.value_changed.connect(func(v): num.value = v)
		num.value_changed.connect(func(v): slider.value = v)
		var btn := Button.new()
		btn.text = "酿造"
		btn.custom_minimum_size = Vector2(96, 40)
		btn.disabled = have <= 0
		var mid_c: String = mid
		btn.pressed.connect(func(): _on_brew(mid_c, int(num.value)))
		row.add_child(btn)
	c._add_ok_button(vb, func(): _close_popup())

func _on_brew(mid: String, n: int):
	var r := _sys().brew(mid, n)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()   # 酿造入账→数值已可见，不弹成功字（协作规则 28）
	_refresh()

# ---------- 弹窗：采买（【商店】/【背包】双页签；100 元宝/个，每种每周限购 15） ----------
func _show_buy_popup():
	_popup_kind = "buy"
	_popup_id = ""
	_close_node("WineryPopup")
	var popup: PanelContainer = c._create_base_popup("采买", Vector2(460, 460))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	# 页签行
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	var t_shop := Button.new()
	t_shop.text = "商店"
	t_shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_shop.disabled = _buy_tab == "shop"
	t_shop.pressed.connect(func(): _buy_tab = "shop"; _show_buy_popup())
	tabs.add_child(t_shop)
	var t_bag := Button.new()
	t_bag.text = "背包"
	t_bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_bag.disabled = _buy_tab == "bag"
	t_bag.pressed.connect(func(): _buy_tab = "bag"; _show_buy_popup())
	tabs.add_child(t_bag)
	vb.add_child(HSeparator.new())
	if _buy_tab == "shop":
		_fill_buy_shop(vb)
	else:
		_fill_buy_bag(vb)
	c._add_ok_button(vb, func(): _close_popup())

func _fill_buy_shop(vb: VBoxContainer):
	var price: int = int(_sys()._st().get("buy_price", 100))
	for m in _sys()._cfg().get("materials", []):
		var mid: String = str(m.get("id", ""))
		var left: int = _sys().get_buy_left(mid)
		var info := Label.new()
		info.text = "%s　本周剩余 %d/%d　单价 %d 元宝" % [
			m.get("name", mid), left, int(_sys()._st().get("buy_weekly_limit", 15)), price]
		vb.add_child(info)
		# 数量选择器（滑杆+SpinBox 联动，同体力丹/酿酒范式，不依赖手机键盘；2026-09-18 用户拍板：批量道具备数量选择）
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vb.add_child(row)
		var slider := HSlider.new()
		slider.min_value = 1
		slider.max_value = max(1, left)
		slider.value = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var num := SpinBox.new()
		num.min_value = 1
		num.max_value = max(1, left)
		num.value = 1
		num.custom_minimum_size = Vector2(96, 40)
		row.add_child(num)
		slider.value_changed.connect(func(v): num.value = v)
		num.value_changed.connect(func(v): slider.value = v)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 40)
		if left <= 0:
			btn.text = "已售罄"
			btn.disabled = true
		else:
			btn.text = "购买（%d 元宝）" % price
			btn.disabled = data.yuanbao < price
			var mid_c: String = mid
			btn.pressed.connect(func(): _on_buy(mid_c, int(num.value)))
		row.add_child(btn)

func _fill_buy_bag(vb: VBoxContainer):
	for m in _sys()._cfg().get("materials", []):
		var mid: String = str(m.get("id", ""))
		var lbl := Label.new()
		lbl.text = "%s　库存 %d" % [m.get("name", mid), _sys().get_material(mid)]
		vb.add_child(lbl)
	var hint := Label.new()
	hint.text = "（材料在【酿酒】中消耗）"
	hint.add_theme_color_override("font_color", Color("#9a93b8"))
	vb.add_child(hint)

func _on_buy(mid: String, n: int = 1):
	var r := _sys().buy_material(mid, n)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()
	_refresh()

func _close_popup():
	_popup_kind = ""
	_popup_id = ""
	_close_node("WineryPopup")

# ---------- 弹窗：勋章（15 级；累计酒香只作门槛不消耗；全部商铺赚速 +100%×级） ----------
# 【统一样式】2026-09-18 用户拍板：全玩法勋章统一样式——主页右上角入口 + 药铺勋章卡样式弹窗
# （妙音坊/厢房后续照此模板；勋章名读配置 medals[i].name，未配置时显示"酒坊勋章"）
func _show_medal_popup():
	_popup_kind = "medal"
	_popup_id = ""
	_close_node("WineryPopup")
	var popup: PanelContainer = c._create_base_popup("勋章", Vector2(460, 420))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var lv: int = _sys().get_medal_lv()
	# 药铺同款勋章卡（深色紫底）
	var card := PanelContainer.new()
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color("#2a2440")
	cstyle.set_corner_radius_all(8)
	cstyle.content_margin_left = 10
	cstyle.content_margin_right = 10
	cstyle.content_margin_top = 8
	cstyle.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", cstyle)
	vb.add_child(card)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 6)
	card.add_child(cvb)
	var medals_cfg: Array = _sys()._cfg().get("medals", [])
	var medal_name: String = "酒坊勋章"
	if lv >= 1 and lv <= medals_cfg.size():
		medal_name = str(medals_cfg[lv - 1].get("name", medal_name))
	var head := Label.new()
	head.text = "勋章：%s（%d级）" % [medal_name, lv]
	head.add_theme_font_size_override("font_size", 20)
	cvb.add_child(head)
	var effect := Label.new()
	effect.text = "全部商铺赚速 +%d%%" % int(round(_sys().get_medal_shop_pct() * 100.0))
	effect.add_theme_color_override("font_color", Color("#f1c40f"))
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cvb.add_child(effect)
	var need: int = _sys().get_next_medal_need()
	var prog := Label.new()
	if need < 0:
		prog.text = "已满级"
	else:
		prog.text = "下级需求：累计酒香 %s" % c.format_number(need)
	prog.add_theme_color_override("font_color", Color("#9a93b8"))
	prog.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cvb.add_child(prog)
	var btn := Button.new()
	btn.text = "升级"
	btn.custom_minimum_size = Vector2(0, 44)
	btn.disabled = not _sys().can_upgrade_medal().get("ok", false)
	btn.pressed.connect(func(): _on_medal_upgrade())
	vb.add_child(btn)
	c._add_ok_button(vb, func(): _close_popup())

# 按钮右上角内部红点（锚定右上，不依赖节点尺寸；酒坊红点一律内部展示，不穿透地图）
func _add_btn_dot(btn: Button, cond: bool):
	var d := Label.new()
	d.text = "●"
	d.add_theme_color_override("font_color", Color("#e74c3c"))
	d.add_theme_font_size_override("font_size", 14)
	d.anchor_left = 1.0
	d.anchor_right = 1.0
	d.anchor_top = 0.0
	d.anchor_bottom = 0.0
	d.offset_left = -18
	d.offset_right = -2
	d.offset_top = 2
	d.offset_bottom = 18
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.visible = cond
	btn.add_child(d)

# 有可升级的名酒（名酒记入口红点）
func _has_upgradeable_wine() -> bool:
	for wc in _sys().get_wine_list():
		if _sys().can_upgrade_wine(str(wc.get("id", ""))).get("ok", false):
			return true
	return false

func _on_medal_upgrade():
	var r := _sys().upgrade_medal()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()   # 勋章百分比→商铺赚速
	_refresh()

# ---------- 弹窗：名酒记（15 酒 3 列网格；点卡看详情） ----------
func _show_wines_popup():
	_popup_kind = "wines"
	_popup_id = ""
	_close_node("WineryPopup")
	var popup: PanelContainer = c._create_base_popup("名酒记", Vector2(480, 560))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	# 按品质高→低排序展示
	var list: Array = _sys().get_wine_list().duplicate()
	list.sort_custom(func(a, b): return int(a.get("quality", 1)) > int(b.get("quality", 1)))
	for wc in list:
		var wid4: String = str(wc.get("id", ""))
		var card := Button.new()
		var q: int = int(wc.get("quality", 1))
		card.text = "%s\n%s Lv.%d　库存 %d" % [
			wc.get("name", wid4), wc.get("career", ""), _sys().get_wine_lv(wid4), _sys().get_wine_cnt(wid4)]
		card.add_theme_color_override("font_color", Color(QUALITY_COLORS[q - 1]))
		card.custom_minimum_size = Vector2(0, 72)
		var wid_c: String = wid4
		card.pressed.connect(func(): _show_wine_info(wid_c))
		grid.add_child(card)
	c._add_ok_button(vb, func(): _close_popup())

# ---------- 弹窗：酒详情（三属性 / 升级消耗=累计酿造瓶数） ----------
func _show_wine_info(wine_id: String):
	_popup_kind = "wine_info"
	_popup_id = wine_id
	_close_node("WineryPopup")
	var wc: Dictionary = _sys().get_wine_cfg(wine_id)
	if wc.is_empty():
		return
	var popup: PanelContainer = c._create_base_popup(str(wc.get("name", wine_id)), Vector2(460, 460))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var q: int = int(wc.get("quality", 1))
	var attr := Label.new()
	attr.text = "%s　品质 %s　绑定职业 %s" % [wc.get("name", wine_id), QUALITY_NAMES[q - 1], wc.get("career", "")]
	attr.add_theme_color_override("font_color", Color(QUALITY_COLORS[q - 1]))
	attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(attr)
	var give := Label.new()
	give.text = "点酒共饮产出：百业经验 %d / 交情 %d / 满意 %d　当前库存 %d" % [
		int(wc.get("baiye", 0)), int(wc.get("bond", 0)), int(wc.get("satis", 0)), _sys().get_wine_cnt(wine_id)]
	give.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(give)
	# 门客赚钱（2026-09-18 已按职业接入 hero_data.get_extra_income：绑定职业全部门客 +此值）
	var inc := Label.new()
	inc.text = "门客赚钱：%s 职业门客 +%s" % [wc.get("career", ""), c.format_number(_sys().get_wine_income(wine_id))]
	inc.add_theme_color_override("font_color", Color("#2ecc71"))
	vb.add_child(inc)
	var next_need: int = _sys().get_wine_next_need(wine_id)
	var up := Label.new()
	# 【修】Godot 4 的 Label 无 bbcode_enabled（Godot 3 残留 API，运行时报错）；达标用绿字，未达标灰字
	if next_need < 0:
		up.text = "Lv.%d 已满级（累计酿造 %d 瓶）" % [_sys().get_wine_lv(wine_id), _sys().get_wine_brewed(wine_id)]
	else:
		up.text = "Lv.%d → 本级还需酿造 %d/%d 瓶" % [
			_sys().get_wine_lv(wine_id), _sys().get_wine_overplus(wine_id), next_need]
		if _sys().can_upgrade_wine(wine_id).get("ok", false):
			up.add_theme_color_override("font_color", Color("#2ecc71"))
		else:
			up.add_theme_color_override("font_color", Color("#9a93b8"))
	up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(up)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	var b1 := Button.new()
	b1.text = "升级"
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b1.disabled = not _sys().can_upgrade_wine(wine_id).get("ok", false)
	b1.pressed.connect(func(): _on_wine_upgrade(wine_id, false))
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "一键升级"
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.disabled = not _sys().can_upgrade_wine(wine_id).get("ok", false)
	b2.pressed.connect(func(): _on_wine_upgrade(wine_id, true))
	row.add_child(b2)
	c._add_ok_button(vb, func(): _show_wines_popup())

func _on_wine_upgrade(wine_id: String, batch: bool):
	var r := _sys().upgrade_wine(wine_id, batch)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

# ---------- 弹窗：品酒（邀请门客 → 酒架三材料页签 → 点酒共饮 / 自动饮酒） ----------
func _show_drink_popup():
	_popup_kind = "drink"
	_popup_id = ""
	_close_node("WineryPopup")
	var popup: PanelContainer = c._create_base_popup("品酒", Vector2(480, 560))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	# 邀请行
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	var invited: String = _sys().get_invited()
	var inv_name: String = "未邀请"
	if invited != "" and data.heroes.has(invited):
		inv_name = str(data.heroes[invited].get("name", invited))
	var lbl := Label.new()
	lbl.text = "已邀门客：%s" % inv_name
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lbl)
	var pick := Button.new()
	pick.text = "邀请门客"
	pick.custom_minimum_size = Vector2(110, 40)
	pick.pressed.connect(func(): _show_hero_pick_popup())
	row.add_child(pick)
	# 已邀门客三维实时展示（2026-09-18 用户拍板：喝没喝要看得见）
	if invited != "":
		var st := Label.new()
		st.text = "交情 %s（Lv.%d）　百业经验 %s　满意 %d" % [
			c.format_number(_sys().get_bond_exp(invited)), _sys().get_bond_level(invited),
			c.format_number(data.bank_system.get_baiye(invited)), _sys().get_bond_satis(invited)]
		st.add_theme_color_override("font_color", Color("#9a93b8"))
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(st)
	# 自动饮酒开关（按品质高→低喝光库存）
	var auto_chk := CheckBox.new()
	auto_chk.text = "自动饮酒（品质高→低喝光库存）"
	auto_chk.button_pressed = _sys().get_auto_drink() and invited != ""
	auto_chk.disabled = invited == ""
	auto_chk.toggled.connect(func(on: bool):
		_sys().set_auto_drink(on)
		if on and invited != "":
			var r: Dictionary = _sys().auto_drink_all(invited)
			if r.get("ok", false):
				c._show_stage_hint("自动饮酒：共饮 %d 瓶" % int(r.get("n", 0)))
			c.update_all_ui()
			_refresh())
	vb.add_child(auto_chk)
	vb.add_child(HSeparator.new())
	# 酒架三材料页签
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	for m in _sys()._cfg().get("materials", []):
		var mid: String = str(m.get("id", ""))
		var tb := Button.new()
		tb.text = str(m.get("name", mid))
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.disabled = _drink_tab == mid
		var mid_c: String = mid
		tb.pressed.connect(func(): _drink_tab = mid_c; _show_drink_popup())
		tabs.add_child(tb)
	# 当前页签的酒列表（全部展示，库存 0 置灰）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	for wc in _sys().get_wine_list():
		if str(wc.get("material", "")) != _drink_tab:
			continue
		var wid5: String = str(wc.get("id", ""))
		var cnt: int = _sys().get_wine_cnt(wid5)
		var wrow := HBoxContainer.new()
		wrow.add_theme_constant_override("separation", 6)
		body.add_child(wrow)
		var q2: int = int(wc.get("quality", 1))
		var wl := Label.new()
		wl.text = "%s　百业%d/交情%d/满意%d　剩 %d" % [
			wc.get("name", wid5), int(wc.get("baiye", 0)), int(wc.get("bond", 0)),
			int(wc.get("satis", 0)), cnt]
		wl.add_theme_color_override("font_color", Color(QUALITY_COLORS[q2 - 1]))
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wrow.add_child(wl)
		var db := Button.new()
		db.text = "共饮×1"
		db.custom_minimum_size = Vector2(96, 40)
		db.disabled = invited == "" or cnt <= 0
		var wid_c2: String = wid5
		db.pressed.connect(func(): _on_drink(invited, wid_c2))
		wrow.add_child(db)
	c._add_ok_button(vb, func(): _close_popup())

func _on_drink(hero_id: String, wine_id: String):
	var r := _sys().drink(hero_id, wine_id, 1)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	# 共饮反馈：+多少要看得见（2026-09-18 用户拍板）
	var txt := "百业经验+%d　交情+%d　满意+%d" % [int(r.get("baiye", 0)), int(r.get("bond", 0)), int(r.get("satis", 0))]
	if int(r.get("tokens", 0)) > 0:
		txt += "　门客帖×%d" % int(r.get("tokens", 0))
	c._show_stage_hint(txt)
	c.update_all_ui()   # 百业经验入账
	_refresh()

# ---------- 弹窗：选择门客（品酒邀请用，全部已拥有门客） ----------
func _show_hero_pick_popup():
	_popup_kind = "hero_pick"
	_popup_id = ""
	_close_node("WineryPopup")
	var popup: PanelContainer = c._create_base_popup("选择门客", Vector2(460, 520))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	for hero_id in data.heroes.keys():
		var h: Dictionary = data.heroes[hero_id]
		var btn := Button.new()
		btn.text = "%s（%s）" % [h.get("name", hero_id), h.get("career", "")]
		btn.custom_minimum_size = Vector2(0, 44)
		var hid_c: String = hero_id
		btn.pressed.connect(func():
			_sys().set_invited(hid_c)
			_show_drink_popup())
		body.add_child(btn)
	c._add_ok_button(vb, func(): _show_drink_popup())

# ---------- 弹窗：酒客故事（全部已拥有门客，五职业筛选；红点=有可领交情奖励） ----------
func _show_story_popup():
	_popup_kind = "story"
	_popup_id = ""
	_close_node("WineryPopup")
	var popup: PanelContainer = c._create_base_popup("酒客故事", Vector2(480, 560))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	# 筛选页签：全部 + 五职业
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	for t in ["all", "士", "农", "工", "商", "侠"]:
		var tb := Button.new()
		tb.text = "全部" if t == "all" else t
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.disabled = _story_tab == t
		var t_c: String = t
		tb.pressed.connect(func(): _story_tab = t_c; _show_story_popup())
		tabs.add_child(tb)
	vb.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	for hero_id in data.heroes.keys():
		var h: Dictionary = data.heroes[hero_id]
		if _story_tab != "all" and str(h.get("category", "")) != _story_tab:
			continue
		var card := Button.new()
		var claimable: bool = _sys().can_claim_bond(str(hero_id)).get("ok", false)
		var tier: String = _sys().get_bond_tier_name(str(hero_id))
		card.text = "%s（%s）　%s\n交情 Lv.%d（%s）　满意 %d%s" % [
			h.get("name", hero_id), h.get("category", ""), tier,
			_sys().get_bond_level(str(hero_id)), c.format_number(_sys().get_bond_exp(str(hero_id))),
			_sys().get_bond_satis(str(hero_id)), "　●可领奖" if claimable else ""]
		card.custom_minimum_size = Vector2(0, 64)
		var hid_c: String = hero_id
		card.pressed.connect(func(): _show_bond_popup(hid_c))
		body.add_child(card)
	c._add_ok_button(vb, func(): _close_popup())

# 某档奖励的展示文案（道具名查 ITEM_CONFIG + 声望卡 + 家具币）
func _bond_reward_text(lv: int) -> String:
	var rewards: Array = _sys()._cfg().get("bond_rewards", [])
	if lv < 1 or lv > rewards.size():
		return ""
	var rc: Dictionary = rewards[lv - 1]
	var parts := []
	for it in rc.get("items", []):
		var iid: String = str(it.get("id", ""))
		if iid == "":
			continue
		parts.append("%s×%d" % [data.ITEM_CONFIG.get(iid, {}).get("name", iid), int(it.get("count", 1))])
	var rep_n: int = int(rc.get("rep", 0))
	if rep_n > 0:
		var rep_id: String = "reputation_card_adv" if bool(rc.get("rep_adv", false)) else "reputation_card"
		parts.append("%s×%d" % [data.ITEM_CONFIG.get(rep_id, {}).get("name", rep_id), rep_n])
	var fur_n: int = int(rc.get("furniture", 0))
	if fur_n > 0:
		parts.append("家具币×%d" % fur_n)
	return "、".join(parts)

# ---------- 弹窗：酒客故事·领奖（档位进度 + 未来 3 档预览 + 逐档领取） ----------
func _show_bond_popup(hero_id: String):
	_popup_kind = "bond"
	_popup_id = hero_id
	_close_node("WineryPopup")
	if not data.heroes.has(hero_id):
		return
	var h: Dictionary = data.heroes[hero_id]
	var popup: PanelContainer = c._create_base_popup("%s · 交情" % h.get("name", hero_id), Vector2(480, 560))
	popup.name = "WineryPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var claimed: int = _sys().get_bond_claimed(hero_id)
	var bond_exp: int = _sys().get_bond_exp(hero_id)   # 【修】exp 撞内置函数（SHADOWED_GLOBAL_IDENTIFIER）
	var head := Label.new()
	if claimed >= int(_sys()._st().get("bond_max_lv", 50)):
		head.text = "档位：%s　交情已满级（%s）" % [_sys().get_bond_tier_name(hero_id), c.format_number(bond_exp)]
	else:
		head.text = "档位：%s　交情 %s / 下级 %s" % [
			_sys().get_bond_tier_name(hero_id), c.format_number(bond_exp),
			c.format_number(_sys().get_bond_threshold(claimed + 1))]
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(head)
	var satis := Label.new()
	satis.text = "满意值 %d（满 1000 送门客帖）" % _sys().get_bond_satis(hero_id)
	satis.add_theme_color_override("font_color", Color("#9a93b8"))
	vb.add_child(satis)
	vb.add_child(HSeparator.new())
	# 未来 3 档预览（逐档领取，只领当前可领档）
	var max_lv: int = int(_sys()._st().get("bond_max_lv", 50))
	for lv in range(claimed + 1, min(claimed + 3, max_lv) + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vb.add_child(row)
		var lbl := Label.new()
		lbl.text = "第 %d 档　%s" % [lv, _bond_reward_text(lv)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "领取"
		btn.custom_minimum_size = Vector2(90, 40)
		var can: bool = _sys().can_claim_bond(hero_id).get("ok", false) and int(_sys().can_claim_bond(hero_id).get("lv", 0)) == lv
		btn.disabled = not can
		var lv_c: int = lv
		btn.pressed.connect(func(): _on_claim_bond(hero_id, lv_c))
		row.add_child(btn)
	if max_lv > claimed:
		var big := Label.new()
		big.text = "…（共 %d 档；第 %d 档大奖：门客帖）" % [max_lv, max_lv]
		big.add_theme_color_override("font_color", Color("#9a93b8"))
		vb.add_child(big)
	c._add_ok_button(vb, func(): _show_story_popup())

func _on_claim_bond(hero_id: String, _lv: int):
	# 只许按序领取当前档（can_claim_bond 已校验）；_lv 仅作行标识，实际领取按序推进
	var r := _sys().claim_bond(hero_id)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()
	c._show_stage_hint("领取成功：%s" % str(r.get("rewards", "")))
	_refresh()
