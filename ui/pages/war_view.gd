# ============================================================
# 商战视图（第5批新增：税所/战斗/兑换商店，入口在闯荡页）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# UI 全部代码生成：入口按钮与子视图跟随闯荡页重建，零场景改动
# 【改】2026-09-10 商战竖屏适配重构：
#       1) 页签只留 税所/兑换商店；"战斗"改为税所页内的按钮，点击弹出队伍列表弹窗
#       2) 小队卡片竖屏化：6 个格子分 2 排（每排 3 个），出战固定第 2 排最右，删除在标题行最右
#       3) 小队无上限：弹窗列表末尾"＋ 新增小队"手动增队；删除走二次确认弹窗
#       4) 弹窗底部固定"快速战斗"（不随列表滚动），一键结算所有可出战小队
#       5) 出战限制按门客：已出战门客格子名带"·已战"标记，整队不可出战时出战按钮置灰
# ============================================================
class_name WarView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 本页 UI 状态变量
var _war_tab: String = "tax"   # tax=税所 / shop=兑换商店（【改】战斗不再是页签，是税所页内的弹窗入口）

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 构建（由 adventure_page.generate_adventure_page 经中枢转发调用） ============
# 在闯荡页注入"商战"入口按钮和商战子视图（模式同行善/游历/庄园）
func build_war_view(page, vbox):
	# --- 商战入口 ---
	var war_btn = Button.new()
	war_btn.text = "商战"
	war_btn.custom_minimum_size = Vector2(180, 60)
	war_btn.pressed.connect(c.show_war_view)
	vbox.get_node("AdventureEntryGrid").add_child(war_btn)
	
	# --- 商战子页面 ---
	var view = VBoxContainer.new()
	view.name = "WarView"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.add_theme_constant_override("separation", 10)
	page.add_child(view)
	
	var back_btn = Button.new()
	back_btn.text = "< 返回闯荡"
	back_btn.pressed.connect(c.hide_war_view)
	view.add_child(back_btn)
	
	# 货币栏：商战积分 / 商战税引
	var res_lbl = Label.new()
	res_lbl.name = "WarRes"
	res_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_lbl.add_theme_font_size_override("font_size", 16)
	res_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	view.add_child(res_lbl)
	
	# 页签：税所 / 兑换商店（【改】去掉"战斗"页签，战斗入口在税所页内）
	var tab_box = HBoxContainer.new()
	tab_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_box.add_theme_constant_override("separation", 16)
	view.add_child(tab_box)
	for t in [["tax", "税所"], ["shop", "兑换商店"]]:
		var b = Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(140, 44)
		b.pressed.connect(_on_tab.bind(t[0]))
		tab_box.add_child(b)
	
	# 内容区（scroll双向填充，内容只横向填充）
	var scroll = ScrollContainer.new()
	scroll.name = "WarScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "WarList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

# ============ 显示/隐藏 ============
# 打开商战：隐藏闯荡主入口区和其他子视图，只留商战视图
func show_war_view():
	if not c.has_node("PageContainer/AdventurePage/WarView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	for child in page.get_children():
		child.visible = (child.name == "WarView")
	update_war_view()

# 返回闯荡主页
func hide_war_view():
	if not c.has_node("PageContainer/AdventurePage/WarView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("WarView").visible = false
	page.get_node("AdventureVBox").visible = true

# ============ 刷新 ============
# 重绘货币栏 + 当前页签内容
func update_war_view():
	if not c.has_node("PageContainer/AdventurePage/WarView"): return
	var view = c.get_node("PageContainer/AdventurePage/WarView")
	view.get_node("WarRes").text = "商战积分：%d ｜ 商战税引：%d" % [int(data.war_points), int(data.war_tax_yin)]
	var list = view.get_node("WarScroll/WarList")
	for child in list.get_children():
		child.queue_free()
	match _war_tab:
		"tax": _build_tax_tab(list)
		"shop": _build_shop_tab(list)

# 切换 税所/兑换商店 页签
func _on_tab(kind: String):
	_war_tab = kind
	update_war_view()

# ============ 税所页 ============
# 税所信息 + 累积/领取 + 升级 + 战斗入口
func _build_tax_tab(list):
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "税所 Lv%d ｜ 收益加成 %.2f 倍" % [data.war_tax_level, data.get_war_tax_multiplier()]
	list.add_child(info)
	
	var accum = Label.new()
	accum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	accum.text = "已累积 %.1f / %d 分钟 ｜ 可领取 %s 铜钱" % [
		data.get_war_tax_accum_minutes(), data.get_war_tax_cap_minutes(),
		c.format_number(data.get_war_tax_pending_income())]
	list.add_child(accum)
	
	var op = HBoxContainer.new()
	op.alignment = BoxContainer.ALIGNMENT_CENTER
	op.add_theme_constant_override("separation", 16)
	list.add_child(op)
	var claim_btn = Button.new()
	claim_btn.text = "领取"
	claim_btn.custom_minimum_size = Vector2(160, 50)
	claim_btn.pressed.connect(_on_claim_tax)
	op.add_child(claim_btn)
	var up_btn = Button.new()
	up_btn.text = "升级（%s 税引）" % c.format_number(data.get_war_tax_up_cost())
	up_btn.custom_minimum_size = Vector2(240, 50)
	up_btn.pressed.connect(_on_upgrade_tax)
	op.add_child(up_btn)
	
	# 【改】战斗入口：打开队伍列表弹窗（编小队/出战/快速战斗都在弹窗内）
	var op2 = HBoxContainer.new()
	op2.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_child(op2)
	var battle_btn = Button.new()
	battle_btn.text = "战斗"
	battle_btn.custom_minimum_size = Vector2(400, 56)
	battle_btn.pressed.connect(_show_battle_popup)
	op2.add_child(battle_btn)
	
	var tip = Label.new()
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color("#888888"))
	tip.text = "收益 = 当前总赚速 × 加成 × 累积时间（在线+离线都累积，到上限后不再增长）"
	list.add_child(tip)

# 领取税所收益
func _on_claim_tax():
	var r = data.claim_war_tax()
	if not r.ok:
		c._show_stage_hint(r.reason)
	else:
		c._show_stage_hint("领取税所收益 +%s 铜钱" % c.format_number(r.amount))
	update_war_view()

# 升级税所（耗商战税引）
func _on_upgrade_tax():
	var r = data.upgrade_war_tax()
	if not r.ok:
		c._show_stage_hint(r.reason)
	update_war_view()

# ============ 战斗弹窗（队伍列表） ============
# 打开快速战斗弹窗：滚动区放全部小队卡片 + 末尾"新增小队"；底部固定"快速战斗"
func _show_battle_popup():
	# 防重入：同名旧弹窗先关（按名关闭，与全项目惯例一致）
	var old = c.get_node_or_null("WarBattlePopup")
	if old != null:
		old.queue_free()
	var popup = c._create_base_popup("快速战斗", Vector2(560, 640))
	popup.name = "WarBattlePopup"
	var vb = popup.get_child(0)
	# 滚动区：固定最小高度，内容超高可滚（小队多了往下滚）
	var scroll = ScrollContainer.new()
	scroll.name = "WarBattleScroll"
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "WarBattleList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	_fill_battle_list(list)
	# 底部固定按钮：快速战斗 + 关闭（不随列表滚动）
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	vb.add_child(bottom)
	var qb = Button.new()
	qb.text = "快速战斗"
	qb.custom_minimum_size = Vector2(220, 52)
	qb.pressed.connect(_on_quick_battle)
	bottom.add_child(qb)
	# 【新增】关闭按钮：弹窗无自带关闭，固定在底部
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(120, 52)
	close_btn.pressed.connect(func(): popup.queue_free())
	bottom.add_child(close_btn)
	c.add_child(popup)

# 重填弹窗小队列表（新增/删除/编队/出战后刷新）
func _fill_battle_list(list):
	for i in range(data.war_system.get_squad_count()):
		list.add_child(_build_squad_card(i))
	# 末尾"新增小队"（无上限，手动增队；要滚动才看得到属预期）
	var add_btn = Button.new()
	add_btn.text = "＋ 新增小队"
	add_btn.custom_minimum_size = Vector2(0, 44)
	add_btn.pressed.connect(_on_add_squad)
	list.add_child(add_btn)

# 刷新战斗弹窗 + 背后税所页（货币栏/可领数值）
func _refresh_battle_popup():
	update_war_view()
	var popup = c.get_node_or_null("WarBattlePopup")
	if popup == null:
		return
	# 【修】路径补 VBox 层：弹窗结构为 PanelContainer → VBox(child 0) → WarBattleScroll → WarBattleList
	var list = popup.get_child(0).get_node("WarBattleScroll/WarBattleList")
	for child in list.get_children():
		child.queue_free()
	_fill_battle_list(list)

# 单支小队卡片：标题行（战力+可出战战力｜右侧删除）+ 格子 2 排 + 第 2 排最右出战
func _build_squad_card(idx: int) -> PanelContainer:
	var card = PanelContainer.new()
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	
	# 标题行：队名 战力 ｜ 最右"删除"（二次确认，见 _on_del_squad）
	var title_row = HBoxContainer.new()
	box.add_child(title_row)
	var total = data.get_war_squad_power(idx)
	var ready_heroes = data.war_system.get_ready_heroes(idx)
	var ready_power = 0
	for hid in ready_heroes:
		ready_power += data.get_hero_income(hid)
	var title = Label.new()
	title.text = "第%d小队 ｜ 战力 %s（可出战 %s）" % [idx + 1, c.format_number(total), c.format_number(ready_power)]
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var del_btn = Button.new()
	del_btn.text = "删除"
	del_btn.custom_minimum_size = Vector2(72, 30)
	del_btn.pressed.connect(_on_del_squad.bind(idx))
	title_row.add_child(del_btn)
	
	# 6 个格子分 2 排（每排 3 个，竖屏 600 宽放不下横排 6 个；点击弹门客选择器）
	var squad = data.get_war_squad(idx)
	for row in range(2):
		var row_box = HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 6)
		box.add_child(row_box)
		for col in range(3):
			var s = row * 3 + col
			var b = Button.new()
			b.custom_minimum_size = Vector2(120, 44)
			var hid = squad[s]
			if hid != "":
				b.text = data.get_war_hero_name(hid)
				# 今日已出战的门客做标记（出战按门客计次，方便看出剩余战力构成）
				if data.war_system.is_hero_battled(hid):
					b.text += "·已战"
			else:
				b.text = "（空）"
			b.pressed.connect(_on_slot.bind(idx, s))
			row_box.add_child(b)
		# 第 2 排最右固定"出战"（出战限制按门客：队内全部已出战则置灰）
		if row == 1:
			var battle_btn = Button.new()
			if data.can_war_battle(idx):
				battle_btn.text = "出战"
			else:
				battle_btn.text = "今日已出战"
				battle_btn.disabled = true
			battle_btn.custom_minimum_size = Vector2(120, 44)
			battle_btn.pressed.connect(_on_battle.bind(idx))
			row_box.add_child(battle_btn)
	return card

# 新增小队（无上限）
func _on_add_squad():
	data.war_system.add_squad()
	_refresh_battle_popup()

# 删除小队：二次确认弹窗（队内门客移出，门客今日出战记录保留）
func _on_del_squad(idx: int):
	var popup = c._create_base_popup("删除小队", Vector2(420, 240))
	popup.name = "WarDelPopup"
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "确定删除第%d小队？\n队内门客将移出编队（门客的今日出战记录保留）。" % (idx + 1)
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var ok = Button.new()
	ok.text = "确认删除"
	ok.custom_minimum_size = Vector2(140, 44)
	ok.pressed.connect(func():
		var r = data.war_system.remove_squad(idx)
		if not r.ok:
			c._show_stage_hint(r.reason)
		popup.queue_free()
		_refresh_battle_popup())
	row.add_child(ok)
	c._add_ok_button(vb, func(): popup.queue_free(), "取消")
	c.add_child(popup)

# 点格子：弹门客选择器（别队门客不可选；本队门客可换格）
func _on_slot(squad_index: int, slot: int):
	var squad = data.get_war_squad(squad_index)
	var cur = squad[slot]
	var popup = c._create_base_popup("选择门客", Vector2(520, 560), Vector2(316, 80))
	popup.name = "WarHeroPicker"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# 门客按实时赚速降序排列（get_war_hero_list 返回新数组，排序不影响数据源）
	var hero_list = data.get_war_hero_list()
	hero_list.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hid in hero_list:
		var owner = data.get_war_hero_squad(hid)
		if owner >= 0 and hid != cur: continue    # 已入队，跳过
		var b = Button.new()
		b.text = "%s（赚速 %s）%s" % [
			data.get_war_hero_name(hid), c.format_number(data.get_hero_income(hid)),
			" ✓" if hid == cur else ""]
		b.pressed.connect(_on_pick_hero.bind(popup, squad_index, slot, hid))
		list.add_child(b)
	# 当前格有人时提供"移出"
	if cur != "":
		var rm = Button.new()
		rm.text = "移出该位置"
		rm.pressed.connect(_on_remove_hero.bind(popup, squad_index, slot))
		vb.add_child(rm)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 选择器中选中队客（编入本格）
func _on_pick_hero(popup, squad_index: int, slot: int, hero_id: String):
	var r = data.assign_war_hero(squad_index, slot, hero_id)
	if not r.ok:
		c._show_stage_hint(r.reason)
	popup.queue_free()
	_refresh_battle_popup()

# 选择器中点移出
func _on_remove_hero(popup, squad_index: int, slot: int):
	data.remove_war_hero(squad_index, slot)
	popup.queue_free()
	_refresh_battle_popup()

# 出战：以队内"今日未出战门客"的赚速和为战力，对比 NPC 商队结算
func _on_battle(idx: int):
	var r = data.war_battle(idx)
	if not r.ok:
		c._show_stage_hint(r.reason)
	else:
		var msg = "战胜商队！" if r.win else "败给商队……"
		msg += "\n我方战力 %s vs 商队 %s\n击败 %d 人 ｜ 商战积分 +%d ｜ 商战税引 +%d" % [
			c.format_number(r.power), c.format_number(r.npc_power), r.kills, r.points, r.yin]
		c._show_stage_hint(msg, 4.0)
	_refresh_battle_popup()

# 快速战斗：所有可出战小队各结算一场，弹汇总
func _on_quick_battle():
	var r = data.war_system.quick_battle()
	if not r.ok:
		c._show_stage_hint(r.reason)
		return
	if r.battles == 0:
		c._show_stage_hint("没有可出战的小队（门客今日均已出战或队伍为空）")
		return
	_show_quick_result(r)
	_refresh_battle_popup()

# 快速战斗汇总弹窗：逐队一行 + 合计
func _show_quick_result(r):
	var popup = c._create_base_popup("战斗结果", Vector2(520, 480))
	popup.name = "WarQuickResult"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for item in r.results:
		var lbl = Label.new()
		lbl.text = "第%d小队 %s ｜ 战力 %s vs %s ｜ 积分+%d 税引+%d" % [
			item.idx + 1, "胜" if item.win else "负",
			c.format_number(item.power), c.format_number(item.npc_power),
			item.points, item.yin]
		list.add_child(lbl)
	var total = Label.new()
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total.add_theme_color_override("font_color", Color("#ffd700"))
	total.text = "合计：%d胜%d负 ｜ 积分 +%d ｜ 税引 +%d" % [r.wins, r.battles - r.wins, r.points, r.yin]
	vb.add_child(total)
	c._add_ok_button(vb, func(): popup.queue_free(), "确定")
	c.add_child(popup)

# ============ 兑换商店页 ============
# 兑换列表（war.json exchange 段驱动；商战积分，不限购）
func _build_shop_tab(list):
	for e in data.get_war_exchange_list():
		var item_id = e.get("item", "")
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var info = Label.new()
		var item_name = data.ITEM_CONFIG.get(item_id, {}).get("name", item_id)
		info.text = "%s ｜ %d 积分" % [item_name, int(e.get("cost", 0))]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b = Button.new()
		b.text = "兑换"
		b.pressed.connect(_on_exchange.bind(item_id))
		row.add_child(b)

# 兑换单个道具
func _on_exchange(item_id: String):
	var r = data.war_exchange(item_id)
	if not r.ok:
		c._show_stage_hint(r.reason)
	update_war_view()
