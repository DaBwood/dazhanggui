# ============================================================
# 客栈玩法全屏页（商铺地图 客栈「▶」入口，层级：InnPage z35，同钱庄/藏品页惯例）
# 结构：顶栏（返回/标题）→ 资源栏（厨艺值/交子）→ 四页签【营业/菜谱/庖丁解牛/兑换商店】→ 内容体
# 重建刷新模式（同钱庄页）：切页签/操作后整页重建；1秒 Timer 只刷营业倒计时与资源数（不重建保滚动）
# ============================================================
class_name InnView
extends RefCounted

var c      # game_controller 根脚本引用
var data: GameData   # 数据中枢（显式标注 GameData：让中枢字段被静态引用，消 UNUSED 提示，同 bank_view 先例）

var _tab: String = "cook"      # 当前页签 cook/recipe/paoding/exchange
var _pack_cards: Array = []    # 营业页食材卡引用 [{pack, info, btn}]
var _status_lbl: Label = null  # 营业状态行（秒刷只改文本）

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
	_close_node("InnCookPopup")
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
	_close_node("InnCookPopup")
	_pack_cards.clear()
	_status_lbl = null

func _on_tab(tab: String):
	_tab = tab
	show_inn_view()   # 重建刷新（同钱庄页惯例）

# ---------- 秒刷 ----------
func _on_tick():
	var sys = data.inn_system
	var st: Dictionary = sys.get_status()   # 查询即懒结算，完成自动发奖
	if int(st.get("settled", 0)) > 0:
		c.update_all_ui()   # 菜谱成长→门客赚速变化→触发全局赚速飘字
	_refresh_res()
	if _status_lbl:
		_status_lbl.text = _status_text(st)

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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	_pack_cards.clear()
	for pack in sys.get_packs():
		_add_pack_card(grid, pack)

func _status_text(st: Dictionary) -> String:
	if not bool(st.get("active", false)):
		var careers: Array = data.inn_system.get_today_bonus_careers()
		return "灶位空闲　今日轮班加成：%s（该职业做菜收益×2）　点下方食材包开始营业" % "、".join(careers)
	var bonus_txt := "（轮班×2）" if bool(st.get("bonus", false)) else ""
	var hero_name := str(st.get("hero_id", ""))
	if data.heroes.has(hero_name):
		hero_name = str(data.heroes[hero_name].get("name", hero_name))
	return "%s×%d（%s）　%s 掌勺%s　本次 %d/%d 秒，全部完成还需 %s" % [
		str(st.get("dish", "")), int(st.get("count_left", 0)), str(st.get("pack_name", "")),
		hero_name, bonus_txt,
		int(st.get("into", 0)), int(st.get("secs", 0)), _fmt_secs(int(st.get("remain_total", 0)))]

func _add_pack_card(grid: GridContainer, pack: Dictionary):
	var card := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color("#252138")
	rs.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", rs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var title := Label.new()
	title.text = str(pack.get("name", ""))
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(title)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color("#c8c3e0"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	var btn := Button.new()
	btn.text = "营业"
	btn.custom_minimum_size = Vector2(0, 28)
	vb.add_child(btn)
	var entry := {"pack": pack, "info": info, "btn": btn}
	_pack_cards.append(entry)
	btn.pressed.connect(_show_cook_popup.bind(str(pack.get("id", ""))))
	_refresh_pack_card(entry)

func _refresh_pack_card(entry: Dictionary):
	var pack: Dictionary = entry["pack"]
	var own := int(data.items.get(str(pack.get("item", "")), 0))
	entry["info"].text = "拥有 %d ｜ 每次 %s ｜ 单次 厨艺+%d 交子+%d" % [
		own, _fmt_secs(int(pack.get("seconds", 300))), int(pack.get("cuisine", 0)), int(pack.get("jiao", 0))]
	entry["btn"].disabled = data.inn_system.is_cooking() or own <= 0

# ---------- 营业弹窗（选门客+数量） ----------
func _show_cook_popup(pack_id: String):
	_close_node("InnCookPopup")
	var sys = data.inn_system
	var pack: Dictionary = sys.get_pack(pack_id)   # sys 未标类型→显式标注，避免 := 推断 Variant 报错
	if pack.is_empty(): return
	var own := int(data.items.get(str(pack.get("item", "")), 0))
	if own <= 0: return
	# 状态容器：闭包捕获坑——lambda 改外层局部变量无效，跨回调状态一律 Dictionary（同锦盒批量套路）
	var ctx := {"n": 1, "hero": "", "career": "", "filter": "", "pack_id": pack_id}
	var bonus: Array = sys.get_today_bonus_careers()
	if bonus.size() == 1:
		ctx["filter"] = str(bonus[0])   # 默认筛当日加成职业
	var popup := PanelContainer.new()
	popup.name = "InnCookPopup"
	popup.z_index = 40
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#2a2640")
	ps.set_corner_radius_all(10)
	popup.add_theme_stylebox_override("panel", ps)
	var vs: Vector2 = c.get_viewport_rect().size
	popup.size = Vector2(mini(560, int(vs.x) - 40), mini(640, int(vs.y) - 80))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	popup.add_child(vb)
	var title := Label.new()
	title.text = "营业 · %s" % str(pack.get("name", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(title)
	var sub := Label.new()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.text = "选择掌勺门客（门客职业决定菜品）与数量；每次消耗1个食材包（拥有 %d），单次 %s" % [own, _fmt_secs(int(pack.get("seconds", 300)))]
	vb.add_child(sub)
	# 职业筛选行（点击重刷门客列表；默认选中当日加成职业）
	var filter_row := HBoxContainer.new()
	filter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	filter_row.add_theme_constant_override("separation", 4)
	vb.add_child(filter_row)
	var hero_grid := GridContainer.new()
	for f in ["全部"] + sys.get_careers():
		var fb := Button.new()
		fb.text = str(f)
		fb.custom_minimum_size = Vector2(58, 26)
		fb.add_theme_font_size_override("font_size", 11)
		fb.set_meta("career", str(f))
		fb.pressed.connect(func():
			ctx["filter"] = fb.get_meta("career")
			_refresh_cook_heroes(ctx, ctx["hero_grid"]))
		if str(ctx["filter"]) == str(f) or (str(ctx["filter"]) == "" and str(f) == "全部"):
			fb.add_theme_color_override("font_color", Color("#ffd700"))
		filter_row.add_child(fb)
	# 门客滚动网格（2列，按实时赚速降序）
	var hero_scroll := ScrollContainer.new()
	hero_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_scroll.custom_minimum_size = Vector2(0, 220)
	vb.add_child(hero_scroll)
	hero_grid.columns = 2
	hero_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_grid.add_theme_constant_override("h_separation", 6)
	hero_grid.add_theme_constant_override("v_separation", 4)
	hero_scroll.add_child(hero_grid)
	# 数量行（Web 键盘坑：纯按钮步进，不用输入框）
	var qty_row := HBoxContainer.new()
	qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	qty_row.add_theme_constant_override("separation", 4)
	vb.add_child(qty_row)
	var qty_lbl := Label.new()
	qty_lbl.add_theme_font_size_override("font_size", 13)
	qty_row.add_child(qty_lbl)
	for step in [1, 10, 100]:
		var pb := Button.new()
		pb.text = "+%d" % step
		pb.custom_minimum_size = Vector2(54, 26)
		pb.add_theme_font_size_override("font_size", 11)
		pb.set_meta("step", step)
		pb.pressed.connect(func():
			ctx["n"] = mini(own, int(ctx["n"]) + int(pb.get_meta("step")))
			_refresh_cook_popup(ctx))
		qty_row.add_child(pb)
	var max_btn := Button.new()
	max_btn.text = "最大"
	max_btn.custom_minimum_size = Vector2(54, 26)
	max_btn.add_theme_font_size_override("font_size", 11)
	max_btn.pressed.connect(func():
		ctx["n"] = own
		_refresh_cook_popup(ctx))
	qty_row.add_child(max_btn)
	# 开始按钮行（居中）
	var start_row := HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(start_row)
	var start_btn := Button.new()
	start_btn.text = "开始营业"
	start_btn.custom_minimum_size = Vector2(140, 34)
	start_btn.pressed.connect(func(): _on_cook_start(ctx))
	start_row.add_child(start_btn)
	# 控件引用存容器（跨刷新用）
	ctx["qty_lbl"] = qty_lbl
	ctx["start_btn"] = start_btn
	ctx["hero_grid"] = hero_grid
	c.add_child(popup)
	popup.position = Vector2(floori((vs.x - popup.size.x) * 0.5), floori((vs.y - popup.size.y) * 0.5))
	_refresh_cook_heroes(ctx, hero_grid)
	_refresh_cook_popup(ctx)

func _refresh_cook_heroes(ctx: Dictionary, grid: GridContainer):
	for ch in grid.get_children():
		grid.remove_child(ch)
		ch.queue_free()
	var flt := str(ctx["filter"])
	var ids: Array = data.heroes.keys()
	ids.sort_custom(func(a, b): return HeroData.get_income(data, str(a)) > HeroData.get_income(data, str(b)))
	for hid in ids:
		var h: Dictionary = data.heroes[hid]
		var career := str(h.get("category", ""))
		if flt != "" and flt != "全部" and career != flt: continue
		var hb := Button.new()
		var mark := "✓ " if str(ctx["hero"]) == str(hid) else ""
		hb.text = "%s%s Lv.%d" % [mark, str(h.get("name", hid)), int(h.get("level", 1))]
		hb.add_theme_font_size_override("font_size", 12)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if str(ctx["hero"]) == str(hid):
			hb.add_theme_color_override("font_color", Color("#ffd700"))
		hb.pressed.connect(_on_pick_hero.bind(ctx, str(hid), career))   # bind 复制值，避开 for 循环闭包同引用坑
		grid.add_child(hb)

func _on_pick_hero(ctx: Dictionary, hid: String, career: String):
	ctx["hero"] = hid
	ctx["career"] = career
	_refresh_cook_heroes(ctx, ctx["hero_grid"])
	_refresh_cook_popup(ctx)

func _refresh_cook_popup(ctx: Dictionary):
	var qty_lbl: Label = ctx["qty_lbl"]
	var start_btn: Button = ctx["start_btn"]
	var sys = data.inn_system
	var pack: Dictionary = sys.get_pack(str(ctx["pack_id"]))   # 显式标注 Dictionary，避免 := 推断 Variant 报错
	var own := int(data.items.get(str(pack.get("item", "")), 0))
	ctx["n"] = clampi(int(ctx["n"]), 1, maxi(1, own))
	var career := str(ctx["career"])
	var mult := 2 if (career != "" and sys.is_bonus_career(career)) else 1
	var dish := "（先选门客）"
	if career != "":
		dish = sys.get_dish_name(pack, career)
	var bonus_txt := "（轮班×2）" if mult == 2 else ""
	qty_lbl.text = "×%d（共 %s）　菜品：%s%s　预计 厨艺+%d 交子+%d" % [
		int(ctx["n"]), _fmt_secs(int(ctx["n"]) * int(pack.get("seconds", 300))), dish, bonus_txt,
		int(ctx["n"]) * int(pack.get("cuisine", 0)) * mult,
		int(ctx["n"]) * int(pack.get("jiao", 0)) * mult]
	start_btn.disabled = career == ""

func _on_cook_start(ctx: Dictionary):
	if data.inn_system.start_cooking(str(ctx["pack_id"]), str(ctx["hero"]), int(ctx["n"])):
		_close_node("InnCookPopup")
		c.update_all_ui()
		show_inn_view()

# ==================== 页签二：菜谱 ====================
func _fill_recipe(body: VBoxContainer):
	var sys = data.inn_system
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	head.text = "菜谱共 50 道：做菜即累计该菜烹饪次数，自动升级（1~10级每级1次，每10级+1次需求）；每级给同职业门客 赚钱+500×所需次数"
	body.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for pack in sys.get_packs():
		var sec := Label.new()
		sec.text = str(pack.get("name", ""))
		sec.add_theme_font_size_override("font_size", 14)
		sec.add_theme_color_override("font_color", Color("#ffd700"))
		list.add_child(sec)
		for career in sys.get_careers():
			list.add_child(_make_recipe_row(str(pack.get("id", "")), str(career), pack))

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
