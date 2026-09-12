# ============================================================
# 钱庄玩法全屏页（商铺地图 钱庄「▶」入口，层级：BankPage z35，同藏品/兽魂页惯例）
# 结构：顶栏（返回/标题）→ 资源栏（筹算/信誉/百业Σ + 一键全领）→ 信誉等级卡 → 柜台卡片网格
# 柜台/委任选择器均为卡片式（2列网格，同珍兽/挚友页惯例；用户 2026-09-12 拍板）
# 重建刷新模式（同藏品页）：操作后整页重建；1秒 Timer 只刷新计时/待领文本（不重建，保滚动位置）
# ============================================================
class_name BankView
extends RefCounted

var c      # game_controller 根脚本引用
var data: GameData   # 数据中枢（显式标注 GameData：让中枢字段被静态引用，消 UNUSED_PRIVATE_CLASS_VARIABLE 提示，同 shop_page 先例）

var _row_refs: Array = []   # 柜台卡片动态引用 [{idx, info, btn, hid}]，秒刷只改文本

func _init(p_c):
	c = p_c
	data = p_c.data

func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

# ---------- 页面开关 ----------
func show_bank_view():
	_row_refs.clear()
	_close_node("BankPage")
	_close_node("BankAssignPopup")
	# 根面板：禁用锚点预设，显式铺满（同藏品页）
	var page := Panel.new()
	page.name = "BankPage"
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
	back_btn.pressed.connect(hide_bank_view)
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "钱庄"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(90, 44)
	top.add_child(pad)
	# 内容
	_fill_body(vb)
	c.add_child(page)
	# 秒刷 Timer（随页面节点销毁，无需手动停）
	var timer := Timer.new()
	timer.name = "TickTimer"
	timer.wait_time = 1.0
	timer.timeout.connect(_refresh_rows)
	page.add_child(timer)
	timer.start()

func hide_bank_view():
	_close_node("BankPage")
	_close_node("BankAssignPopup")
	_row_refs.clear()

# ---------- 内容 ----------
func _fill_body(vb: VBoxContainer):
	var sys = data.bank_system
	sys._ensure_counters()
	# 资源栏：三资源存量 + 一键全领
	var res := HBoxContainer.new()
	res.alignment = BoxContainer.ALIGNMENT_CENTER
	res.add_theme_constant_override("separation", 12)
	vb.add_child(res)
	var res_lbl := Label.new()
	res_lbl.text = "筹算值 %d ｜ 信誉值 %d ｜ 百业经验Σ %d" % [sys.get_chousuan(), sys.get_xinyu(), sys.get_baiye_total()]
	res_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	res_lbl.add_theme_font_size_override("font_size", 14)
	res.add_child(res_lbl)
	var collect_all_btn := Button.new()
	collect_all_btn.text = "一键全领"
	collect_all_btn.pressed.connect(_on_collect_all)
	res.add_child(collect_all_btn)
	# 信誉等级卡
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#2a2640")
	cs.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", cs)
	vb.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	card.add_child(cv)
	var lv_lbl := Label.new()
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.text = "信誉等级 Lv.%d/%d" % [sys.get_xinyu_level(), sys.get_xinyu_max_level()]
	lv_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	lv_lbl.add_theme_font_size_override("font_size", 17)
	cv.add_child(lv_lbl)
	var bonus_lbl := Label.new()
	bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus_lbl.text = "当前加成：徒弟赚速 +%d、+%.0f%% ｜ 珍兽等级上限 +%d ｜ 珍兽觉醒上限 +%d" % [
		sys.get_apprentice_flat_bonus(), sys.get_apprentice_pct_bonus() * 100.0,
		sys.get_beast_level_cap_bonus(), sys.get_awaken_limit_bonus()]
	bonus_lbl.add_theme_font_size_override("font_size", 13)
	bonus_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	cv.add_child(bonus_lbl)
	# 升级按钮居中，不横拉满（同卡片内按钮惯例）
	var up_row := HBoxContainer.new()
	up_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(up_row)
	var up_btn := Button.new()
	if sys.get_xinyu_level() >= sys.get_xinyu_max_level():
		up_btn.text = "已满级"
		up_btn.disabled = true
	else:
		up_btn.text = "升级（%d 信誉值）" % sys.get_xinyu_cost()
		up_btn.disabled = sys.get_xinyu() < sys.get_xinyu_cost()
		up_btn.pressed.connect(_on_xinyu_upgrade)
	up_row.add_child(up_btn)
	# 柜台区标题 + 卡片网格（2列，同珍兽/挚友页惯例）
	var head := Label.new()
	# 解锁花费直接读中枢配置（同 shop_page 读 _shop_configs 先例；显式引用让分析器看到 _bank_configs）
	var bank_st: Dictionary = data._bank_configs.get("settings", {})
	head.text = "柜台（已解锁 %d/%d）　每20分钟产 1百业+40筹算+40信誉，单柜封顶24小时；前5个免费，之后受钱庄店铺等级限制、每个%d元宝解锁" % [sys.get_counter_count(), sys.get_counter_total(), int(bank_st.get("counter_unlock_cost", 5000))]
	head.add_theme_font_size_override("font_size", 13)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 必须换行：否则整段文字的最小宽度会把网格顶出屏幕
	vb.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3   # 按按钮尺寸实测3列正好，4列会顶出去（用户 2026-09-12 拍板）
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	# 只渲染已解锁柜台，末尾恒有一个「+」新增卡（用户拍板：不一次全显示30个）
	for i in range(sys.get_counter_count()):
		_add_counter_card(grid, i)
	_add_unlock_card(grid)

# ---------- 柜台卡片 ----------
func _add_counter_card(grid: GridContainer, idx: int):
	var sys = data.bank_system
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
	title.add_theme_font_size_override("font_size", 13)
	title.clip_text = true
	vb.add_child(title)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color("#c8c3e0"))
	info.clip_text = true
	vb.add_child(info)
	# 按钮行：居中紧凑，不横拉满
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 6)
	vb.add_child(btn_row)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(58, 24)
	btn.add_theme_font_size_override("font_size", 11)
	btn_row.add_child(btn)
	var btn2 := Button.new()
	btn2.custom_minimum_size = Vector2(58, 24)
	btn2.add_theme_font_size_override("font_size", 11)
	btn_row.add_child(btn2)
	# 两态：空闲 / 已委任（未解锁柜台不渲染，由末尾「+」卡负责新增）
	var hid: String = sys.get_counter_hero(idx)   # 显式标注（sys 为 Variant，方法返回 Variant）
	if hid == "":
		title.text = "柜台%d·空闲" % (idx + 1)
		info.text = "委任门客开始产出"
		btn.text = "委任"
		btn.pressed.connect(_show_assign_selector.bind(idx))
		btn2.visible = false
	else:
		title.text = "柜台%d·%s" % [idx + 1, str(data.heroes.get(hid, {}).get("name", hid))]
		info.text = _counter_info_text(idx, hid)
		btn.text = "领取"
		btn.pressed.connect(_on_collect.bind(idx))
		btn2.text = "撤下"
		btn2.pressed.connect(_on_unassign.bind(idx))
	# 记录动态引用，秒刷只更新文本
	_row_refs.append({"idx": idx, "info": info, "btn": btn, "hid": hid})

# 「+」新增柜台卡：末尾只渲染一个；等级不足时点+提示升级钱庄店铺（用户 2026-09-12 拍板）
func _add_unlock_card(grid: GridContainer):
	var sys = data.bank_system
	var card := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color("#2a2440")
	rs.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", rs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var title := Label.new()
	title.text = "新增柜台"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(title)
	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color("#c8c3e0"))
	vb.add_child(info)
	# 按钮行：居中紧凑，不横拉满
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)
	var btn := Button.new()
	btn.text = "＋"
	btn.custom_minimum_size = Vector2(58, 24)
	btn.add_theme_font_size_override("font_size", 13)
	btn_row.add_child(btn)
	# 三态：达上限（禁用）/ 等级不足（点击提示升级钱庄店铺）/ 可花元宝解锁
	var count: int = sys.get_counter_count()   # 显式标注（sys 为 Variant，方法返回 Variant）
	if count >= sys.get_counter_total():
		info.text = "柜台已达上限30"
		btn.disabled = true
	elif count >= sys.get_max_unlockable():
		var req_lv: int = 2 * (count + 1 - 5) + 1   # 下一柜台所需钱庄店铺等级（每2级+1个额度）
		info.text = "需钱庄店铺等级%d\n升级地图上的钱庄解锁" % req_lv
		btn.pressed.connect(func(): c._show_stage_hint("钱庄店铺等级不足，升级地图上的钱庄后可继续解锁柜台"))
	else:
		info.text = "花%d元宝解锁柜台%d" % [sys.get_counter_unlock_cost(), count + 1]
		btn.disabled = int(data.yuanbao) < sys.get_counter_unlock_cost()
		btn.pressed.connect(_on_unlock)

func _counter_info_text(idx: int, _hid: String) -> String:   # _hid 未用（名字在卡片标题显示），下划线前缀消 UNUSED_PARAMETER 提示
	var sys = data.bank_system
	var secs: int = sys.get_accrued_seconds(idx)   # 显式标注（sys 为 Variant，方法返回 Variant）
	var t: String
	if secs >= 3600:
		t = "%d小时%d分" % [floori(secs / 3600.0), floori((secs % 3600) / 60.0)]
	else:
		t = "%d分%d秒" % [floori(secs / 60.0), secs % 60]
	var p: Dictionary = sys.get_pending(idx)
	return "%s\n待领 %d百业 %d筹算 %d信誉" % [t, int(p["baiye"]), int(p["chousuan"]), int(p["xinyu"])]

# 秒刷：只更新计时/待领文本与领取按钮态（不整页重建，保住滚动位置）
func _refresh_rows():
	if not c.has_node("BankPage"): return
	for ref in _row_refs:
		if not is_instance_valid(ref["info"]): continue
		var hid: String = ref["hid"]
		if hid == "": continue
		var idx := int(ref["idx"])
		ref["info"].text = _counter_info_text(idx, hid)
		var p: Dictionary = data.bank_system.get_pending(idx)
		ref["btn"].disabled = int(p["baiye"]) + int(p["chousuan"]) + int(p["xinyu"]) <= 0

# ---------- 操作 ----------
func _on_collect(idx: int):
	var gain: Dictionary = data.bank_system.collect_counter(idx)   # 显式标注（data 无类型，方法返回 Variant）
	if gain.is_empty():
		c._show_stage_hint("还没有产出，稍后再来")
		return
	c._show_stage_hint("领取：%d百业 %d筹算 %d信誉" % [int(gain["baiye"]), int(gain["chousuan"]), int(gain["xinyu"])])
	_rebuild()

func _on_collect_all():
	var total: Dictionary = data.bank_system.collect_all()   # 显式标注（data 无类型，方法返回 Variant）
	if int(total["baiye"]) + int(total["chousuan"]) + int(total["xinyu"]) <= 0:
		c._show_stage_hint("所有柜台都还没有产出")
		return
	c._show_stage_hint("一键全领：%d百业 %d筹算 %d信誉" % [int(total["baiye"]), int(total["chousuan"]), int(total["xinyu"])])
	_rebuild()

func _on_unassign(idx: int):
	data.bank_system.unassign_hero(idx)   # 撤下前自动结算已累积产出
	_rebuild()

# 花元宝手动解锁柜台（+卡入口；5个以后每个5000元宝，受钱庄店铺等级上限约束）
func _on_unlock():
	if data.bank_system.unlock_counter():
		c.update_all_ui()   # 元宝变动刷新顶栏
		_rebuild()
	else:
		c._show_stage_hint("元宝不足")

func _on_xinyu_upgrade():
	if data.bank_system.upgrade_xinyu_level():
		c.update_all_ui()   # 徒弟赚速/珍兽上限变动 → 全局赚速飘字
		_rebuild()

func _rebuild():
	if c.has_node("BankPage"):
		show_bank_view()   # 整页重建（同藏品页惯例）

# ---------- 委任选择器（页内弹窗 z40，卡片网格 2 列） ----------
func _show_assign_selector(idx: int):
	_close_node("BankAssignPopup")
	var popup = c._create_base_popup("委任门客到柜台%d" % (idx + 1), Vector2(480, 560))
	popup.name = "BankAssignPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb = popup.get_child(0)
	var hint := Label.new()
	hint.text = "门客不锁定，与店铺派遣/商战全并行；同一门客可同时委任多柜台"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	vb.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3   # 英雄卡片内容紧凑，3列（同柜台网格拍板）
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	# 按实时赚速降序展示；卡片显示财源广进技能等级（筹算值升级的技能，用户 2026-09-12 拍板）
	var ids: Array = data.heroes.keys()
	ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "暂无门客"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(empty)
	for hero_id in ids:
		_add_hero_card(grid, idx, hero_id)
	c._add_ok_button(vb, func(): _close_node("BankAssignPopup"), "关闭")

func _add_hero_card(grid: GridContainer, counter_idx: int, hero_id: String):
	var h: Dictionary = data.heroes[hero_id]
	var card := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color("#252138")
	rs.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", rs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)
	var name_lbl := Label.new()
	name_lbl.text = "【%s】%s" % [h.get("name", hero_id), h.get("category", "")]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	name_lbl.clip_text = true
	vb.add_child(name_lbl)
	var info_lbl := Label.new()
	info_lbl.text = "%s/秒" % c.format_number(data.get_hero_income(hero_id))
	info_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(info_lbl)
	var skill_lbl := Label.new()
	var cy: Dictionary = data.bank_system.get_caiyuan_skill(hero_id)   # 显式标注（data 无类型）
	if cy.is_empty():
		skill_lbl.text = "财源广进 Lv.-"
	else:
		skill_lbl.text = "财源广进 Lv.%d/%d" % [int(cy.get("level", 1)), int(cy.get("max_level", 200))]
	skill_lbl.add_theme_font_size_override("font_size", 12)
	skill_lbl.add_theme_color_override("font_color", Color("#c8c3e0"))
	vb.add_child(skill_lbl)
	# 委任按钮居中，不横拉满
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)
	var btn := Button.new()
	btn.text = "委任"
	btn.custom_minimum_size = Vector2(58, 24)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_on_hero_picked.bind(counter_idx, hero_id))
	btn_row.add_child(btn)

func _on_hero_picked(idx: int, hero_id: String):
	data.bank_system.assign_hero(idx, hero_id)
	_close_node("BankAssignPopup")
	_rebuild()
