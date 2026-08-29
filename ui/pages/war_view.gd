# ============================================================
# 商战视图（第5批新增：税所/战斗/兑换商店，入口在闯荡页）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# UI 全部代码生成：入口按钮与子视图跟随闯荡页重建，零场景改动
# ============================================================
class_name WarView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 本页 UI 状态变量
var _war_tab: String = "tax"   # tax=税所 / battle=战斗 / shop=兑换商店

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
	war_btn.custom_minimum_size = Vector2(240, 60)
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
	
	# 页签：税所 / 战斗 / 兑换商店
	var tab_box = HBoxContainer.new()
	tab_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_box.add_theme_constant_override("separation", 16)
	view.add_child(tab_box)
	for t in [["tax", "税所"], ["battle", "战斗"], ["shop", "兑换商店"]]:
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
		"battle": _build_battle_tab(list)
		"shop": _build_shop_tab(list)

# 切换 税所/战斗/兑换商店 页签
func _on_tab(kind: String):
	_war_tab = kind
	update_war_view()

# ============ 税所页 ============
# 税所信息 + 累积/领取 + 升级
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

# ============ 战斗页 ============
# 小队列表（编辑编队 + 出战）
func _build_battle_tab(list):
	var head = Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.text = "可编小队 %d 支（上限=门客总数÷6）｜ 每队每天可出战 1 次" % data.get_war_max_squads()
	list.add_child(head)
	for i in range(data.get_war_max_squads()):
		list.add_child(_build_squad_card(i))

# 单支小队卡片：战力 + 6个格子 + 出战按钮
func _build_squad_card(idx: int) -> PanelContainer:
	var card = PanelContainer.new()
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	
	var title = Label.new()
	title.text = "第%d小队 ｜ 战力（队内赚速之和）：%s" % [idx + 1, c.format_number(data.get_war_squad_power(idx))]
	title.add_theme_color_override("font_color", Color("#ffd700"))
	box.add_child(title)
	
	# 6 个格子（点击弹门客选择器）
	var slots = HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	box.add_child(slots)
	var squad = data.get_war_squad(idx)
	for s in range(squad.size()):
		var b = Button.new()
		b.custom_minimum_size = Vector2(150, 44)
		var hid = squad[s]
		b.text = data.get_war_hero_name(hid) if hid != "" else "（空）"
		b.pressed.connect(_on_slot.bind(idx, s))
		slots.add_child(b)
	
	# 出战（每日一次）
	var battle_btn = Button.new()
	if data.can_war_battle(idx):
		battle_btn.text = "出战"
	else:
		battle_btn.text = "今日已出战"
		battle_btn.disabled = true
	battle_btn.custom_minimum_size = Vector2(200, 46)
	battle_btn.pressed.connect(_on_battle.bind(idx))
	box.add_child(battle_btn)
	return card

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
	# 【改】门客按实时赚速降序排列（原按字典顺序；get_war_hero_list 返回新数组，排序不影响数据源）
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
	update_war_view()

# 选择器中点移出
func _on_remove_hero(popup, squad_index: int, slot: int):
	data.remove_war_hero(squad_index, slot)
	popup.queue_free()
	update_war_view()

# 出战：按小队战力对比NPC商队结算胜负与奖励
func _on_battle(idx: int):
	var r = data.war_battle(idx)
	if not r.ok:
		c._show_stage_hint(r.reason)
	else:
		var msg = "战胜商队！" if r.win else "败给商队……"
		msg += "\n我方战力 %s vs 商队 %s\n击败 %d 人 ｜ 商战积分 +%d ｜ 商战税引 +%d" % [
			c.format_number(r.power), c.format_number(r.npc_power), r.kills, r.points, r.yin]
		c._show_stage_hint(msg, 4.0)
	update_war_view()

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
