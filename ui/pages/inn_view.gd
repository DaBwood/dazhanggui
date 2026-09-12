# ============================================================
# 客栈玩法全屏页（商铺地图 客栈「▶」入口，层级：InnPage z35，同钱庄/藏品页惯例）
# 结构：顶栏（返回/标题）→ 资源栏（厨艺值/交子）→ 三页签【营业/菜谱/兑换商店】→ 内容体
# 重建刷新模式：切页签/操作后整页重建；1秒 Timer 只刷营业状态与收益罐文本（不重建保滚动）
# 营业流程（用户 2026-09-12 二调拍板）：【开始营业】→ 门客选择弹窗（五职业页签，默认今日加成职业）
#   → 选门客 → 食材包选择弹窗（选包+数量）→【烹饪】开做；完成收益进「收益罐」，点【领取】入账
# 菜谱页签内再分五职业二级页签（每页签 10 道菜）
# ============================================================
class_name InnView
extends RefCounted

var c      # game_controller 根脚本引用
var data: GameData   # 数据中枢（显式标注 GameData：让中枢字段被静态引用，消 UNUSED 提示，同 bank_view 先例）

var _tab: String = "cook"        # 当前页签 cook/recipe/exchange
var _recipe_career: String = ""  # 菜谱二级页签当前职业
var _status_lbl: Label = null    # 营业状态行（秒刷只改文本）
var _jar_lbl: Label = null       # 收益罐文本（秒刷只改文本）
var _jar_btn: Button = null      # 领取按钮（秒刷改禁用态）

func _init(p_c):
	c = p_c
	data = p_c.data

func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

# ---------- 页面开关 ----------
func show_inn_view():
	_close_node("InnPage")
	_close_node("InnHeroPopup")
	_close_node("InnPackPopup")
	var page := Panel.new()
	page.name = "InnPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	page.add_theme_stylebox_override("panel", bg)
	var vb := VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
	# 顶栏：返回 + 标题
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 52)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(90, 44)
	back_btn.pressed.connect(hide_inn_view)
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "客栈"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(90, 44)
	top.add_child(pad)
	# 资源栏（秒刷改文本）
	var res := Label.new()
	res.name = "InnResBar"
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.add_theme_color_override("font_color", Color("#e6c07b"))
	res.add_theme_font_size_override("font_size", 14)
	vb.add_child(res)
	# 页签栏
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	for t in [["cook", "营业"], ["recipe", "菜谱"], ["exchange", "兑换商店"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.custom_minimum_size = Vector2(104, 34)
		tb.add_theme_font_size_override("font_size", 13)
		if _tab == t[0]:
			tb.add_theme_color_override("font_color", Color("#ffd700"))
		tb.pressed.connect(_on_tab.bind(str(t[0])))
		tabs.add_child(tb)
	# 内容体
	var body := VBoxContainer.new()
	body.name = "InnBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	vb.add_child(body)
	_fill_body(body)
	c.add_child(page)
	_refresh_res()
	# 秒刷 Timer（随页面节点销毁，无需手动停）
	var timer := Timer.new()
	timer.name = "TickTimer"
	timer.wait_time = 1.0
	timer.timeout.connect(_on_tick)
	page.add_child(timer)
	timer.start()

func hide_inn_view():
	_close_node("InnPage")
	_close_node("InnHeroPopup")
	_close_node("InnPackPopup")
	_status_lbl = null
	_jar_lbl = null
	_jar_btn = null

func _on_tab(tab: String):
	_tab = tab
	show_inn_view()   # 重建刷新（同钱庄页惯例）

# ---------- 秒刷 ----------
func _on_tick():
	var sys = data.inn_system
	var st: Dictionary = sys.get_status()   # 查询即懒结算，收益进罐（不入账）
	if _status_lbl:
		_status_lbl.text = _status_text(st)
	if _jar_lbl:
		_jar_lbl.text = _jar_text()
	if _jar_btn:
		_jar_btn.disabled = not sys.has_pending()

func _refresh_res():
	var page = c.get_node_or_null("InnPage")
	if page == null: return
	var bar = page.get_child(0).get_node_or_null("InnResBar")
	if bar:
		bar.text = "厨艺值 %d ｜ 交子 %d" % [data.inn_system.get_cuisine(), data.inn_system.get_jiaozi()]

func _fmt_secs(sec: int) -> String:
	if sec >= 3600:
		return "%d时%02d分" % [int(sec / 3600.0), int((sec % 3600) / 60.0)]
	return "%d分%02d秒" % [int(sec / 60.0), sec % 60]

# ---------- 内容分派 ----------
func _fill_body(body: VBoxContainer):
	match _tab:
		"cook": _fill_cook(body)
		"recipe": _fill_recipe(body)
		"exchange": _fill_exchange(body)

# ==================== 页签一：营业 ====================
func _fill_cook(body: VBoxContainer):
	var sys = data.inn_system
	var st: Dictionary = sys.get_status()
	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	_status_lbl.text = _status_text(st)
	body.add_child(_status_lbl)
	# 收益罐（待领取收益）
	var jar_card := PanelContainer.new()
	var js := StyleBoxFlat.new()
	js.bg_color = Color("#2a2640")
	js.set_corner_radius_all(8)
	jar_card.add_theme_stylebox_override("panel", js)
	body.add_child(jar_card)
	var jar_row := HBoxContainer.new()
	jar_row.add_theme_constant_override("separation", 6)
	jar_card.add_child(jar_row)
	_jar_lbl = Label.new()
	_jar_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jar_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_jar_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_jar_lbl.add_theme_font_size_override("font_size", 13)
	_jar_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	_jar_lbl.text = _jar_text()
	jar_row.add_child(_jar_lbl)
	_jar_btn = Button.new()
	_jar_btn.text = "领取"
	_jar_btn.custom_minimum_size = Vector2(70, 30)
	_jar_btn.disabled = not sys.has_pending()
	_jar_btn.pressed.connect(_on_claim)
	jar_row.add_child(_jar_btn)
	# 开始营业按钮（营业中禁用）
	var start_row := HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(start_row)
	var start_btn := Button.new()
	start_btn.text = "开始营业"
	start_btn.custom_minimum_size = Vector2(150, 36)
	start_btn.add_theme_font_size_override("font_size", 14)
	start_btn.disabled = bool(st.get("active", false))
	start_btn.pressed.connect(_on_start_cook)
	start_row.add_child(start_btn)

func _status_text(st: Dictionary) -> String:
	if not bool(st.get("active", false)):
		var careers: Array = data.inn_system.get_today_bonus_careers()
		return "灶位空闲　今日轮班加成：%s（该职业做菜收益×2）" % "、".join(careers)
	var bonus_txt := "（轮班×2）" if bool(st.get("bonus", false)) else ""
	var hero_name := str(st.get("hero_id", ""))
	if data.heroes.has(hero_name):
		hero_name = str(data.heroes[hero_name].get("name", hero_name))
	return "%s×%d（%s）　%s 掌勺%s　本次 %d/%d 秒，全部完成还需 %s" % [
		str(st.get("dish", "")), int(st.get("count_left", 0)), str(st.get("pack_name", "")),
		hero_name, bonus_txt,
		int(st.get("into", 0)), int(st.get("secs", 0)), _fmt_secs(int(st.get("remain_total", 0)))]

func _jar_text() -> String:
	var p: Dictionary = data.inn_system.get_pending()
	var cu := int(p.get("cuisine", 0))
	var jiao := int(p.get("jiao", 0))
	var times := 0
	var cooks: Dictionary = p.get("cooks", {})
	for k in cooks.keys():
		times += int(cooks[k])
	if cu <= 0 and jiao <= 0:
		return "收益罐：空空如也（营业完成后收益存入这里）"
	return "收益罐：厨艺+%d ｜ 交子+%d（%d 次烹饪）" % [cu, jiao, times]

func _on_claim():
	var got: Dictionary = data.inn_system.claim()
	if int(got.get("cuisine", 0)) > 0 or int(got.get("jiao", 0)) > 0:
		c.update_all_ui()   # 入账→赚速/资质变化→全局飘字
		show_inn_view()

func _on_start_cook():
	if data.inn_system.is_cooking(): return
	_show_hero_popup()

# ---------- 门客选择弹窗（五职业页签，默认今日加成职业） ----------
func _show_hero_popup():
	_close_node("InnHeroPopup")
	var sys = data.inn_system
	var popup := PanelContainer.new()
	popup.name = "InnHeroPopup"
	popup.z_index = 40
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#2a2640")
	ps.set_corner_radius_all(10)
	popup.add_theme_stylebox_override("panel", ps)
	var vs: Vector2 = c.get_viewport_rect().size
	popup.size = Vector2(maxi(300, int(vs.x) - 24), maxi(420, int(vs.y) - 140))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	popup.add_child(vb)
	var title_row := HBoxContainer.new()
	vb.add_child(title_row)
	var title := Label.new()
	title.text = "选择掌勺门客"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.pressed.connect(func(): _close_node("InnHeroPopup"))
	title_row.add_child(close_btn)
	var sub := Label.new()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.text = "门客职业决定菜品；今日轮班加成职业做菜收益×2"
	vb.add_child(sub)
	# 状态容器（职业页签切换、门客网格重刷共用）
	var bonus: Array = sys.get_today_bonus_careers()
	var ctx := {"career": str(bonus[0]) if bonus.size() >= 1 else "士"}
	var grid := GridContainer.new()
	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 4)
	vb.add_child(tab_row)
	for career in sys.get_careers():
		var cb := Button.new()
		cb.text = str(career)
		cb.custom_minimum_size = Vector2(64, 26)
		cb.add_theme_font_size_override("font_size", 12)
		cb.set_meta("career", str(career))
		cb.pressed.connect(func():
			ctx["career"] = str(cb.get_meta("career"))
			_refresh_hero_popup_grid(ctx, grid))
		if str(ctx["career"]) == str(career):
			cb.add_theme_color_override("font_color", Color("#ffd700"))
		tab_row.add_child(cb)
	# 门客网格（2列，按实时赚速降序）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	vb.add_child(scroll)
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	ctx["grid"] = grid
	c.add_child(popup)
	popup.position = Vector2(floori((vs.x - popup.size.x) * 0.5), floori((vs.y - popup.size.y) * 0.5))
	_refresh_hero_popup_grid(ctx, grid)

func _refresh_hero_popup_grid(ctx: Dictionary, grid: GridContainer):
	for ch in grid.get_children():
		grid.remove_child(ch)
		ch.queue_free()
	var career := str(ctx["career"])
	var ids: Array = data.heroes.keys()
	ids.sort_custom(func(a, b): return HeroData.get_income(data, str(a)) > HeroData.get_income(data, str(b)))
	for hid in ids:
		var h: Dictionary = data.heroes[hid]
		if career != "" and str(h.get("category", "")) != career: continue
		var hb := Button.new()
		hb.text = "%s Lv.%d" % [str(h.get("name", hid)), int(h.get("level", 1))]
		hb.add_theme_font_size_override("font_size", 12)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.pressed.connect(_on_pick_hero.bind(str(hid)))   # bind 复制值，避开 for 循环闭包同引用坑
		grid.add_child(hb)

func _on_pick_hero(hero_id: String):
	_close_node("InnHeroPopup")
	_show_pack_popup(hero_id)

# ---------- 食材包选择弹窗（选包+数量 → 烹饪） ----------
func _show_pack_popup(hero_id: String):
	_close_node("InnPackPopup")
	var sys = data.inn_system
	if not data.heroes.has(hero_id): return
	var h: Dictionary = data.heroes[hero_id]
	var career := str(h.get("category", ""))
	var bonus: bool = sys.is_bonus_career(career)
	var ctx := {"pack": "", "n": 1, "hero": hero_id, "career": career, "bonus": bonus, "cards": []}
	var popup := PanelContainer.new()
	popup.name = "InnPackPopup"
	popup.z_index = 40
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#2a2640")
	ps.set_corner_radius_all(10)
	popup.add_theme_stylebox_override("panel", ps)
	var vs: Vector2 = c.get_viewport_rect().size
	popup.size = Vector2(maxi(300, int(vs.x) - 24), maxi(440, int(vs.y) - 140))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	popup.add_child(vb)
	var title_row := HBoxContainer.new()
	vb.add_child(title_row)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title.text = "选择食材包"
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.pressed.connect(func(): _close_node("InnPackPopup"))
	title_row.add_child(close_btn)
	# 食材包卡片网格（2列；点卡片选中高亮）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 330)
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	# ScrollContainer 不把宽度分给子控件：构建时直接按弹窗宽度定网格最小宽（顺带反向撑住弹窗不缩水）
	grid.custom_minimum_size.x = maxf(popup.size.x - 40.0, 200.0)
	for pack in sys.get_packs():
		# 卡片本体=PanelContainer：Button 不是容器，子控件不会自动排布（曾致文字叠在一起）
		var card := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color("#252138")
		cs.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", cs)
		# 最小宽钉死为弹窗内宽：ScrollContainer 宽度继承不可靠（多层 min-size 钳制），列宽由列内最大子控件最小宽决定
		card.custom_minimum_size = Vector2(maxf(200.0, popup.size.x - 56.0), 56)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到卡片
		card.add_child(cv)
		var name_lbl := Label.new()
		name_lbl.text = str(pack.get("name", ""))
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(name_lbl)
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color("#c8c3e0"))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = "拥有 %d ｜ 每次 %s ｜ 单次 厨艺+%d 交子+%d" % [
			int(data.items.get(str(pack.get("item", "")), 0)),
			_fmt_secs(int(pack.get("seconds", 300))),
			int(pack.get("cuisine", 0)), int(pack.get("jiao", 0))]
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(info)
		var pick_id := str(pack.get("id", ""))
		card.gui_input.connect(_on_pack_card_input.bind(ctx, pick_id))   # bind 复制值，避开 for 循环闭包同引用坑
		grid.add_child(card)
		ctx["cards"].append({"id": pick_id, "btn": card})
	# 数量行（Web 键盘坑：纯按钮步进，不用输入框）
	var qty_row := HBoxContainer.new()
	qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	qty_row.add_theme_constant_override("separation", 4)
	vb.add_child(qty_row)
	var qty_lbl := Label.new()   # 只显示 食材包名 ×N（拖动/输入改数量）
	qty_lbl.add_theme_font_size_override("font_size", 14)
	qty_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	qty_lbl.custom_minimum_size = Vector2(140, 0)
	qty_row.add_child(qty_lbl)
	# 物品同款：拖动条 + 数量输入（Web 端 SpinBox 输入不弹键盘的问题后续再处理）
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = 1
	slider.step = 1
	slider.custom_minimum_size = Vector2(100, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v):
		ctx["n"] = int(v)
		ctx["spin"].set_value_no_signal(v)
		_refresh_pack_popup(ctx))
	qty_row.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 1
	spin.step = 1
	spin.custom_minimum_size = Vector2(76, 0)
	spin.value_changed.connect(func(v):
		ctx["n"] = int(v)
		ctx["slider"].set_value_no_signal(v)
		_refresh_pack_popup(ctx))
	qty_row.add_child(spin)
	ctx["slider"] = slider
	ctx["spin"] = spin
	# 烹饪按钮行
	var cook_row := HBoxContainer.new()
	cook_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(cook_row)
	var cook_btn := Button.new()
	cook_btn.text = "烹饪"
	cook_btn.custom_minimum_size = Vector2(140, 34)
	cook_btn.add_theme_font_size_override("font_size", 14)
	cook_btn.pressed.connect(func(): _on_cook(ctx))
	cook_row.add_child(cook_btn)
	ctx["qty_lbl"] = qty_lbl
	ctx["cook_btn"] = cook_btn
	c.add_child(popup)
	popup.position = Vector2(floori((vs.x - popup.size.x) * 0.5), floori((vs.y - popup.size.y) * 0.5))
	_refresh_pack_popup(ctx)

func _on_pack_card_input(ev: InputEvent, ctx: Dictionary, pack_id: String):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_on_pack_pick(ctx, pack_id)

func _on_pack_pick(ctx: Dictionary, pack_id: String):
	ctx["pack"] = pack_id
	ctx["n"] = 1
	for card in ctx["cards"]:
		card["btn"].modulate = Color("#ffe9a8") if str(card["id"]) == pack_id else Color(1, 1, 1)
	_refresh_pack_popup(ctx)

func _refresh_pack_popup(ctx: Dictionary):
	var qty_lbl: Label = ctx["qty_lbl"]
	var cook_btn: Button = ctx["cook_btn"]
	var sys = data.inn_system
	var slider: HSlider = ctx["slider"]
	var spin: SpinBox = ctx["spin"]
	var pack: Dictionary = sys.get_pack(str(ctx["pack"]))
	if pack.is_empty():
		qty_lbl.text = "先选一个食材包"
		cook_btn.disabled = true
		return
	var own := int(data.items.get(str(pack.get("item", "")), 0))
	slider.max_value = maxi(1, own)
	spin.max_value = maxi(1, own)
	ctx["n"] = clampi(int(ctx["n"]), 1, maxi(1, own))
	slider.set_value_no_signal(int(ctx["n"]))
	spin.set_value_no_signal(int(ctx["n"]))
	qty_lbl.text = "%s ×%d" % [str(pack.get("name", "")), int(ctx["n"])]
	cook_btn.disabled = own <= 0

func _on_cook(ctx: Dictionary):
	if data.inn_system.start_cooking(str(ctx["pack"]), str(ctx["hero"]), int(ctx["n"])):
		_close_node("InnPackPopup")
		c.update_all_ui()   # 消耗食材包→背包刷新
		show_inn_view()

# ==================== 页签二：菜谱（五职业二级页签） ====================
func _fill_recipe(body: VBoxContainer):
	var sys = data.inn_system
	var careers: Array = sys.get_careers()
	if _recipe_career == "" or not (str(_recipe_career) in careers):
		_recipe_career = str(careers[0])
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	head.text = "做菜累计该菜烹饪次数自动升级（1~10级每级1次，每10级+1次需求）；每级给同职业门客 赚钱+500×所需次数"
	body.add_child(head)
	# 五职业二级页签
	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 4)
	body.add_child(tab_row)
	for career in careers:
		var cb := Button.new()
		cb.text = str(career)
		cb.custom_minimum_size = Vector2(64, 28)
		cb.add_theme_font_size_override("font_size", 12)
		cb.set_meta("career", str(career))
		cb.pressed.connect(func():
			_recipe_career = str(cb.get_meta("career"))
			show_inn_view())
		if str(_recipe_career) == str(career):
			cb.add_theme_color_override("font_color", Color("#ffd700"))
		tab_row.add_child(cb)
	# 当前职业 10 道菜
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for pack in sys.get_packs():
		list.add_child(_make_recipe_row(str(pack.get("id", "")), str(_recipe_career), pack))

func _make_recipe_row(pack_id: String, career: String, pack: Dictionary) -> PanelContainer:
	var sys = data.inn_system
	var card := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color("#252138")
	rs.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", rs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)
	var prog: Dictionary = sys.get_dish_progress(pack_id, career)
	var line1 := Label.new()
	line1.add_theme_font_size_override("font_size", 13)
	line1.text = "【%s】%s　Lv.%d（%d/%d 次升级）" % [
		career, sys.get_dish_name(pack, career), int(prog.get("level", 1)), int(prog.get("done", 0)), int(prog.get("need", 1))]
	vb.add_child(line1)
	var line2 := Label.new()
	line2.add_theme_font_size_override("font_size", 12)
	line2.add_theme_color_override("font_color", Color("#c8c3e0"))
	line2.text = "%s类门客 赚钱 +%s" % [career, c.format_number(sys.get_dish_income(pack_id, career))]
	vb.add_child(line2)
	return card

# ==================== 页签三：兑换商店 ====================
func _fill_exchange(body: VBoxContainer):
	var sys = data.inn_system
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	head.text = "交子 %d（客栈做菜产出）　无限购；碎片类可合成" % sys.get_jiaozi()
	body.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var idx := 0
	for e in sys.get_exchange_list():
		list.add_child(_make_exchange_row(idx, e))
		idx += 1

func _item_display_name(item_id: String) -> String:
	# 道具名读中枢中心配置（ITEM_CONFIG 惯例；缺失时退回 id）
	if data.ITEM_CONFIG.has(item_id):
		return str(data.ITEM_CONFIG[item_id].get("name", item_id))
	return item_id

func _make_exchange_row(index: int, e: Dictionary) -> PanelContainer:
	var sys = data.inn_system
	var card := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color("#252138")
	rs.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", rs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)
	var item_id := str(e.get("item", ""))
	var name_lbl := Label.new()
	name_lbl.text = "%s　拥有 %d" % [_item_display_name(item_id), int(data.items.get(item_id, 0))]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(name_lbl)
	var buy_btn := Button.new()
	buy_btn.text = "购买（%d 交子）" % int(e.get("cost", 0))
	buy_btn.custom_minimum_size = Vector2(120, 28)
	buy_btn.add_theme_font_size_override("font_size", 11)
	buy_btn.disabled = sys.get_jiaozi() < int(e.get("cost", 0))
	buy_btn.pressed.connect(_on_exchange_buy.bind(index))
	row.add_child(buy_btn)
	var comp: Dictionary = e.get("compose", {})
	if not comp.is_empty():
		var comp_btn := Button.new()
		comp_btn.text = "%d 合 1 %s" % [int(comp.get("need", 1)), _item_display_name(str(comp.get("to", "")))]
		comp_btn.custom_minimum_size = Vector2(120, 28)
		comp_btn.add_theme_font_size_override("font_size", 11)
		comp_btn.disabled = int(data.items.get(item_id, 0)) < int(comp.get("need", 1))
		comp_btn.pressed.connect(_on_exchange_compose.bind(index))
		row.add_child(comp_btn)
	return card

func _on_exchange_buy(index: int):
	if data.inn_system.buy_exchange(index):
		c.update_all_ui()
		show_inn_view()

func _on_exchange_compose(index: int):
	if data.inn_system.compose_exchange(index):
		c.update_all_ui()
		show_inn_view()
