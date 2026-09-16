# ============================================================
# 药铺玩法全屏页（商铺地图 药铺「▶」入口，层级：DrugshopPage z35，弹窗 z40，同医馆/客栈惯例）
# 2026-09-16 按药铺设计方案 v1.3 定稿：
#   主页 = 勋章卡 + 收益罐(红点) + 体力行(营业/一键接待勾选/队列状态) + 三入口(打理/本草秘籍/成就)
#   营业 = 立即结算1个；一键接待勾选 = 体力自动挪入计算队列，后台批处理（结算不阻塞体力恢复）
#   打理 = 7工艺卡片（点卡片弹详情升级；顶部"全部升级"一次各升1级）
#   本草秘籍 = 29药方卡片网格（锁定卡显示解锁条件；点卡片弹详情：配方/收益/升级+一键升级/解锁）
#   成就 = 3条线 × 进度 + 4档领取
# 后台节拍：页面定时器 0.5s 调 background_tick 推进队列并刷文本（不重建保流畅）；页面关闭后由
#           game_controller 每秒节拍续推（队列进存档，离线暂停，上线续算）
# 重建刷新模式：操作后整页重建（同医馆惯例）
# ============================================================
class_name DrugshopView
extends RefCounted

var c      # game_controller 根脚本引用
var data: GameData   # 数据中枢（显式标注 GameData：让中枢字段被静态引用，消 UNUSED 提示，同 clinic_view 先例）

var _tab: String = "main"        # 当前视图 main/craft/recipe/ach
var _timer: Timer = null         # 后台节拍定时器（0.5s）
var _stamina_lbl: Label = null   # 体力文本
var _cd_lbl: Label = null        # 体力恢复倒计时文本
var _queue_lbl: Label = null     # 计算队列状态文本
var _jar_lbl: Label = null       # 收益罐文本
var _jar_dot: Label = null       # 收益罐红点
var _popup_rid: String = ""      # 当前打开的药方弹窗 id（升级后重建用）

func _init(p_c):
	c = p_c
	data = p_c.data

func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

func _sys() -> DrugshopSystem:
	return data.drugshop_system

# ---------- 页面开关 ----------
func show_drugshop_view():
	_close_node("DrugshopPage")
	_close_node("DrugshopPopup")
	var page := Panel.new()
	page.name = "DrugshopPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	page.add_theme_stylebox_override("panel", bg)
	c.add_child(page)
	_build(page)
	# 后台节拍：0.5s 一次（推进计算队列 + 刷文本，不重建页面）
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	page.add_child(_timer)

func hide_drugshop_view():
	_close_node("DrugshopPage")
	_close_node("DrugshopPopup")

func _on_tick():
	# 推进计算队列（时间盒 2ms；体力恢复与结算解耦，互不阻塞）
	_sys().background_tick(2)
	if _stamina_lbl:
		_stamina_lbl.text = "体力：%d / %d" % [_sys().get_stamina(), _sys().get_stamina_cap()]
	if _cd_lbl:
		_cd_lbl.text = _cd_text()
	if _queue_lbl:
		_queue_lbl.text = _queue_text()
	if _jar_lbl:
		_jar_lbl.text = _jar_text()
	if _jar_dot:
		_jar_dot.visible = _sys().has_pot()

func _cd_text() -> String:
	var sec := _sys().get_next_stamina_seconds()
	if sec <= 0:
		return "体力已满" if _sys().get_stamina() >= _sys().get_stamina_cap() else "体力即将恢复"
	return "下点体力：%d分%02d秒" % [int(sec / 60.0), sec % 60]

func _queue_text() -> String:
	var n := _sys().get_settle_queue()
	if n > 0:
		return "接待队列：%d（结算中…）" % n
	return "接待队列：0"

func _jar_text() -> String:
	var pot := _sys().get_pot()
	var parts := ["铜板 %s" % c.format_number(int(pot.get("coins", 0))),
		"药铺经验 %s" % c.format_number(int(pot.get("exp", 0)))]
	var prof_total := 0
	for rid in pot.get("prof", {}):
		prof_total += int(pot["prof"][rid])
	if prof_total > 0:
		parts.append("熟练度 %s" % c.format_number(prof_total))
	return "收益罐：" + "　".join(parts)

# ---------- 页面构建 ----------
func _build(page: Panel):
	var vb := VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
	# 顶栏：返回 + 标题（子页返回=回主页，主页返回=退出药铺）
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 48)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(90, 42)
	back_btn.pressed.connect(_on_back)
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "药铺" if _tab == "main" else ("药铺 · 打理" if _tab == "craft" else ("药铺 · 本草秘籍" if _tab == "recipe" else "药铺 · 成就"))
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	# 资源行：铜板 / 累计药铺经验
	var res := Label.new()
	res.text = "铜板 %s　累计药铺经验 %s" % [
		c.format_number(_sys().coins), c.format_number(_sys().exp_total)]
	res.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(res)
	# 内容体
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	match _tab:
		"craft":
			_fill_craft(body)
		"recipe":
			_fill_recipe(body)
		"ach":
			_fill_ach(body)
		_:
			_fill_main(body)

func _on_back():
	if _tab == "main":
		hide_drugshop_view()
	else:
		_switch_tab("main")

func _switch_tab(t: String):
	_tab = t
	_close_node("DrugshopPage")
	show_drugshop_view()

# 操作后统一刷新：重建页面；仅当弹窗节点真实存在（未按确定关闭）才重建弹窗
func _refresh():
	_close_node("DrugshopPage")
	show_drugshop_view()
	if _popup_rid != "" and c.get_node_or_null("DrugshopPopup") != null:
		_close_node("DrugshopPopup")
		_show_recipe_popup(_popup_rid)

# ---------- 主页：勋章卡 + 收益罐 + 体力行 + 三入口 ----------
func _fill_main(body: VBoxContainer):
	# 勋章卡
	_fill_medal_card(body)
	# 收益罐（铜板/药铺经验/熟练度，领取统一入账）
	var jar_row := HBoxContainer.new()
	jar_row.add_theme_constant_override("separation", 8)
	body.add_child(jar_row)
	_jar_lbl = Label.new()
	_jar_lbl.text = _jar_text()
	_jar_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jar_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jar_row.add_child(_jar_lbl)
	_jar_dot = Label.new()
	_jar_dot.text = "●"
	_jar_dot.add_theme_color_override("font_color", Color("#e74c3c"))
	_jar_dot.visible = _sys().has_pot()
	jar_row.add_child(_jar_dot)
	var collect_btn := Button.new()
	collect_btn.text = "领取"
	collect_btn.custom_minimum_size = Vector2(90, 36)
	collect_btn.disabled = not _sys().has_pot()
	collect_btn.pressed.connect(_on_collect)
	jar_row.add_child(collect_btn)
	# 体力行：计数 + 营业按钮
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 6)
	body.add_child(count_row)
	_stamina_lbl = Label.new()
	_stamina_lbl.text = "体力：%d / %d" % [_sys().get_stamina(), _sys().get_stamina_cap()]
	_stamina_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(_stamina_lbl)
	var serve_btn := Button.new()
	serve_btn.text = "营业"
	serve_btn.custom_minimum_size = Vector2(110, 38)
	serve_btn.disabled = _sys().get_stamina() <= 0
	serve_btn.pressed.connect(_on_serve)
	count_row.add_child(serve_btn)
	_cd_lbl = Label.new()
	_cd_lbl.text = _cd_text()
	_cd_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
	body.add_child(_cd_lbl)
	# 一键接待勾选（开启后体力自动入队后台结算；体力恢复照常，互不阻塞）
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 6)
	body.add_child(auto_row)
	var auto_check := CheckBox.new()
	auto_check.text = "一键接待"
	auto_check.button_pressed = _sys().get_auto_settle()
	auto_check.toggled.connect(func(on: bool):
		_sys().set_auto_settle(on)
		_refresh())
	auto_row.add_child(auto_check)
	_queue_lbl = Label.new()
	_queue_lbl.text = _queue_text()
	_queue_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	auto_row.add_child(_queue_lbl)
	# 三入口按钮
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for t in [["craft", "打理"], ["recipe", "本草秘籍"], ["ach", "成就"]]:
		var b := Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(170, 56)
		b.pressed.connect(func(): _switch_tab(t[0]))
		grid.add_child(b)

# 勋章卡：当前等级/加成/下一级门槛/手动升级
func _fill_medal_card(body: VBoxContainer):
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2a2640")
	style.border_color = Color("#6a5f9e")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", style)
	body.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var head := Label.new()
	head.text = "勋章：%s（%d级）" % [_sys().get_medal_name(), _sys().get_medal_lv()]
	head.add_theme_font_size_override("font_size", 18)
	vb.add_child(head)
	var effect := Label.new()
	effect.text = "全体商铺赚速 +%d%%　精进技能等级上限 +%d" % [
		int(_sys().get_medal_shop_pct() * 100), _sys().get_refine_cap_bonus()]
	effect.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(effect)
	var nxt := _sys().get_next_medal_cfg()
	if nxt.is_empty():
		var max_lbl := Label.new()
		max_lbl.text = "已达满级"
		max_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
		vb.add_child(max_lbl)
	else:
		var next_lbl := Label.new()
		next_lbl.text = "下一级【%s】需累计药铺经验 %s（当前 %s）" % [
			nxt.get("name", ""), c.format_number(int(nxt.get("need_exp", 0))), c.format_number(_sys().exp_total)]
		next_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(next_lbl)
		var btn := Button.new()
		btn.text = "升级勋章"
		btn.disabled = not _sys().can_upgrade_medal().get("ok", false)
		btn.pressed.connect(_on_medal_upgrade)
		vb.add_child(btn)

func _on_medal_upgrade():
	var r := _sys().upgrade_medal()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()   # 勋章%入账→全体商铺赚速变化→全局飘字
	_refresh()

# 一键接待勾选切换：开启=当前体力挪入计算队列，此后后台自动搬运新恢复的体力
func _on_auto_toggled(on: bool):
	_sys().set_auto_settle(on)
	_refresh()

func _on_collect():
	var r := _sys().collect_pot()
	c._show_stage_hint("领取：铜板+%s 药铺经验+%s" % [
		c.format_number(int(r["coins"])), c.format_number(int(r["exp"]))])
	_refresh()

func _on_serve():
	var r := _sys().serve_one()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("接待完成，收益已入罐")
	_refresh()

# ---------- 子页：打理（7工艺卡片 + 全部升级） ----------
func _fill_craft(body: VBoxContainer):
	# 顶部：全部升级（7项各升1级，铜板不足跳过）
	var all_btn := Button.new()
	all_btn.text = "全部升级（铜板 %s）" % c.format_number(_sys().coins)
	all_btn.custom_minimum_size = Vector2(0, 42)
	all_btn.pressed.connect(_on_craft_all)
	body.add_child(all_btn)
	var head := Label.new()
	head.text = "工艺（伙计赚速固定加成）"
	head.add_theme_color_override("font_color", Color("#9a93b8"))
	body.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for cdef in _sys().get_craft_list():
		var cid: String = str(cdef.get("id", ""))
		if cid == "":
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 64)
		b.text = "【%s】\nLv.%d" % [cdef.get("name", cid), _sys().get_craft_level(cid)]
		var cid_c: String = cid
		b.pressed.connect(func(): _show_craft_popup(cid_c))
		grid.add_child(b)

# 全部升级：一次把7项各升1级，铜板不足的项跳过
func _on_craft_all():
	var r := _sys().upgrade_all_crafts()
	if int(r.get("up", 0)) <= 0:
		c._show_stage_hint("铜板不足")
		return
	c.update_all_ui()   # 工艺固定值入账→伙计赚速变化→全局飘字
	_refresh()

func _show_craft_popup(cid: String):
	_close_node("DrugshopPopup")
	var cdef: Dictionary = {}
	for cd in _sys().get_craft_list():
		if str(cd.get("id", "")) == cid:
			cdef = cd
			break
	if cdef.is_empty():
		return
	var popup: PanelContainer = c._create_base_popup(str(cdef.get("name", cid)), Vector2(420, 260))
	popup.name = "DrugshopPopup"
	popup.z_index = 40   # 盖过 DrugshopPage(z35)，同 clinic/inn 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child（同 clinic/inn 惯例）
	var vb: VBoxContainer = popup.get_child(0)
	var lv := _sys().get_craft_level(cid)
	var target: String = str(cdef.get("target", "all"))
	# 加成对象文案（玩家可见：全体商铺或某职业店铺）
	var target_txt := "全体商铺" if target == "all" else "%s类店铺" % target
	var info := Label.new()
	info.text = "Lv.%d　%s伙计赚速 +%s/级×%d" % [lv, target_txt,
		str(cdef.get("per_level", 0)), lv]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	var cost := Label.new()
	cost.text = "下级消耗铜板：%s（拥有 %s）" % [
		c.format_number(_sys().get_craft_cost(cid)), c.format_number(_sys().coins)]
	vb.add_child(cost)
	var btn := Button.new()
	btn.text = "升级"
	btn.disabled = not _sys().can_upgrade_craft(cid).get("ok", false)
	btn.pressed.connect(func(): _on_craft_upgrade(cid))
	vb.add_child(btn)
	c._add_ok_button(vb, func(): _close_node("DrugshopPopup"))

func _on_craft_upgrade(cid: String):
	var r := _sys().upgrade_craft(cid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()   # 工艺固定值入账→伙计赚速变化→全局飘字
	_refresh()

# ---------- 子页：本草秘籍（29药方卡片网格） ----------
func _fill_recipe(body: VBoxContainer):
	var head := Label.new()
	head.text = "累计药铺经验 %s（接待得经验，领取收益罐后入账）" % c.format_number(_sys().exp_total)
	head.add_theme_color_override("font_color", Color("#9a93b8"))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for rc in _sys().get_recipe_list():
		var rid: String = str(rc.get("id", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 52)
		if _sys().is_recipe_unlocked(rid):
			b.text = "%s\nLv.%d" % [rc.get("name", rid), _sys().get_recipe_level(rid)]
		else:
			b.text = "%s\n需经验 %s" % [rc.get("name", rid), c.format_number(_sys().get_recipe_unlock_need(rid))]
			b.add_theme_color_override("font_color", Color("#666080"))
		var rid_c: String = rid
		b.pressed.connect(func(): _show_recipe_popup(rid_c))
		grid.add_child(b)

# 药方详情弹窗：配方/收益/升级+一键升级（未解锁则显示解锁条件+解锁按钮）
func _show_recipe_popup(rid: String):
	_popup_rid = rid
	_close_node("DrugshopPopup")
	var rc := _sys().get_recipe_cfg(rid)
	if rc.is_empty():
		return
	var popup: PanelContainer = c._create_base_popup(str(rc.get("name", rid)), Vector2(420, 360))
	popup.name = "DrugshopPopup"
	popup.z_index = 40   # 盖过 DrugshopPage(z35)，同 clinic/inn 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child（同 clinic/inn 惯例）
	var vb: VBoxContainer = popup.get_child(0)
	if not _sys().is_recipe_unlocked(rid):
		# 未解锁：显示累计经验门槛 + 手动解锁（不消耗经验）
		var lock := Label.new()
		lock.text = "需累计药铺经验 %s（当前 %s）" % [
			c.format_number(_sys().get_recipe_unlock_need(rid)), c.format_number(_sys().exp_total)]
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(lock)
		var unlock_btn := Button.new()
		unlock_btn.text = "解锁"
		unlock_btn.disabled = not _sys().can_unlock_recipe(rid).get("ok", false)
		unlock_btn.pressed.connect(func(): _on_recipe_unlock(rid))
		vb.add_child(unlock_btn)
		c._add_ok_button(vb, func(): _close_node("DrugshopPopup"))
		return
	# 功效主治难度 + 配方（仅展示，药材不做库存）
	var diff := Label.new()
	diff.text = "难度：%s（售价+%d%%）" % [rc.get("difficulty", ""), int(rc.get("difficulty_pct", 0))]
	vb.add_child(diff)
	var formula := Label.new()
	formula.text = "配方：%s" % rc.get("formula", "")
	formula.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(formula)
	# 接待收益（当前等级）
	var gain := Label.new()
	gain.text = "接待收益：铜板 %s　药铺经验 %d　熟练度 %d" % [
		c.format_number(_sys().get_recipe_price(rid)),
		int(rc.get("exp", 0)),
		int(data._drugshop_configs.get("settings", {}).get("prof_per_serve", 100))]
	vb.add_child(gain)
	# 当前等级/熟练度池
	var lv := _sys().get_recipe_level(rid)
	var max_lv: int = _sys().get_recipe_max_level()
	var wallet := Label.new()
	wallet.text = "Lv.%d/%d　熟练度 %s" % [lv, max_lv, c.format_number(_sys().get_recipe_prof(rid))]
	wallet.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(wallet)
	if lv < max_lv:
		var cost := Label.new()
		cost.text = "下级消耗熟练度：%s" % c.format_number(_sys().get_recipe_upgrade_cost(rid))
		vb.add_child(cost)
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)
		vb.add_child(btn_row)
		var up_btn := Button.new()
		up_btn.text = "升级"
		up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		up_btn.disabled = _sys().get_recipe_prof(rid) < _sys().get_recipe_upgrade_cost(rid)
		up_btn.pressed.connect(func(): _on_recipe_upgrade(rid, false))
		btn_row.add_child(up_btn)
		var up_all_btn := Button.new()
		up_all_btn.text = "一键升级"
		up_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		up_all_btn.disabled = _sys().get_recipe_prof(rid) < _sys().get_recipe_upgrade_cost(rid)
		up_all_btn.pressed.connect(func(): _on_recipe_upgrade(rid, true))
		btn_row.add_child(up_all_btn)
	c._add_ok_button(vb, func(): _close_node("DrugshopPopup"))

func _on_recipe_unlock(rid: String):
	var r := _sys().unlock_recipe(rid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

func _on_recipe_upgrade(rid: String, batch: bool):
	var r := _sys().upgrade_recipe(rid, batch)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

# ---------- 子页：成就（3条线 × 进度 + 4档领取） ----------
func _fill_ach(body: VBoxContainer):
	for line in _sys().get_ach_list():
		var lid: String = str(line.get("id", ""))
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#2a2640")
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", style)
		body.add_child(card)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		card.add_child(vb)
		var progress := _sys().get_ach_progress(lid)
		var head := Label.new()
		head.text = "%s（%s）　当前 %s" % [line.get("name", lid), line.get("desc", ""), c.format_number(progress)]
		head.add_theme_font_size_override("font_size", 16)
		vb.add_child(head)
		var tiers: Array = line.get("tiers", [])
		for i in range(tiers.size()):
			var tier: Dictionary = tiers[i]
			var claimed: bool = i < _sys().get_ach_claimed(lid)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			vb.add_child(row)
			# 奖励文案（道具名走 ITEM_CONFIG，不臆测）
			var parts := []
			for r in tier.get("rewards", []):
				var iid: String = str(r.get("item", ""))
				var iname: String = data.ITEM_CONFIG.get(iid, {}).get("name", iid)
				parts.append("%s×%d" % [iname, int(r.get("count", 0))])
			var info := Label.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if claimed:
				info.text = "已领取　%s" % "、".join(parts)
				info.add_theme_color_override("font_color", Color("#666080"))
			else:
				info.text = "%s　%s" % [c.format_number(int(tier.get("need", 0))), "、".join(parts)]
			row.add_child(info)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(72, 30)
			if claimed:
				btn.text = "已领取"
				btn.disabled = true
			else:
				btn.text = "领取"
				btn.disabled = not _sys().can_claim_ach(lid, i)
				var lid_c: String = lid
				var i_c: int = i
				btn.pressed.connect(func(): _on_ach_claim(lid_c, i_c))
			row.add_child(btn)

func _on_ach_claim(lid: String, tier_idx: int):
	var r := _sys().claim_ach(lid, tier_idx)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("获得 %s" % str(r.get("rewards", "")))
	_refresh()
