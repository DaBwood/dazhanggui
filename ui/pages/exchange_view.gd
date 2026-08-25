# ============================================================
# 闯荡-兑换子视图（门客/挚友/珍兽/系列）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name ExchangeView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var _current_series_index: int = -1

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func _on_exchange_back_pressed():
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	if ev.get_node("SeriesExchangeView").visible:
		hide_series_exchange_view()     # 在系列兑换 → 退回目录
	elif ev.get_node("BeastExchangeView").visible:
		hide_beast_exchange_view()
	elif ev.get_node("TokenExchangeView").visible:
		hide_token_exchange_view()
	else:
		hide_exchange_view()

func show_exchange_view():
	if not c.has_node("PageContainer/AdventurePage"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("AdventureVBox").visible = false
	var ev = page.get_node("ExchangeView")
	ev.visible = true
	# 每次进入都重置回目录层
	if ev.has_node("ExchangeEntryBox"): ev.get_node("ExchangeEntryBox").visible = true
	if ev.has_node("BeastExchangeView"): ev.get_node("BeastExchangeView").visible = false
	if ev.has_node("TokenExchangeView"): ev.get_node("TokenExchangeView").visible = false

func hide_exchange_view():
	if not c.has_node("PageContainer/AdventurePage"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("AdventureVBox").visible = true
	page.get_node("ExchangeView").visible = false
	if page.has_node("LotteryView"):
		page.get_node("LotteryView").visible = false

func show_beast_exchange_view():
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("ExchangeEntryBox").visible = false
	ev.get_node("TokenExchangeView").visible = false
	ev.get_node("BeastExchangeView").visible = true
	update_beast_exchange_view()

func hide_beast_exchange_view():
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("BeastExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

func update_beast_exchange_view():
	if not c.has_node("PageContainer/AdventurePage/ExchangeView/BeastExchangeView"): return
	var list = c.get_node("PageContainer/AdventurePage/ExchangeView/BeastExchangeView/BeastExchangeScroll/BeastExchangeList")
	for child in list.get_children():
		child.queue_free()
	
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(grid)
	
	for beast_id in data.get_all_beast_ids():
		if data.beasts.has(beast_id): continue
		var cfg = data.get_beast_config(beast_id)
		if cfg.get("max_count", 1) != 1: continue
		if cfg.get("exchange_item", "") == "": continue
		grid.add_child(_create_beast_exchange_card(beast_id))

func _create_beast_exchange_card(beast_id: String) -> Button:
	var cfg = data.get_beast_config(beast_id)
	var ex = cfg.get("exchange_item", "")
	var ex_count = data.items.get(ex, 0)
	
	var cell = Button.new()
	cell.custom_minimum_size = Vector2(0, 140)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.disabled = ex_count < 100
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = "【%s】" % cfg.name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lbl)
	
	var quality_lbl = Label.new()
	quality_lbl.text = cfg.quality
	quality_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quality_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(quality_lbl)
	
	var cost_lbl = Label.new()
	cost_lbl.text = "兑换（%d/100）" % ex_count
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(cost_lbl)
	
	cell.pressed.connect(_on_exchange_beast.bind(beast_id))
	return cell

func show_token_exchange_view():
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("ExchangeEntryBox").visible = false
	ev.get_node("BeastExchangeView").visible = false
	ev.get_node("TokenExchangeView").visible = true
	update_token_exchange_view()

func hide_token_exchange_view():
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("TokenExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

func update_token_exchange_view():
	if not c.has_node("PageContainer/AdventurePage/ExchangeView/TokenExchangeView"): return
	var view = c.get_node("PageContainer/AdventurePage/ExchangeView/TokenExchangeView")
	view.get_node("TokenRes").text = "门客帖：%d" % data.items.get("hero_token", 0)
	
	var list = view.get_node("TokenExchangeScroll/TokenExchangeList")
	for child in list.get_children():
		child.queue_free()
	
	# 门客分区
	_add_exchange_section_title(list, "门客")
	_add_role_exchange_grid(list, "hero", data.TOKEN_EXCHANGE_HEROES)
	
	# 挚友分区
	_add_exchange_section_title(list, "挚友")
	_add_role_exchange_grid(list, "friend", data.TOKEN_EXCHANGE_FRIENDS)

func _add_exchange_section_title(list: VBoxContainer, text: String):
	var title = Label.new()
	title.text = "—— %s ——" % text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	list.add_child(title)

func _add_role_exchange_grid(list: VBoxContainer, role_type: String, entries: Array):
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(grid)
	
	for entry in entries:
		grid.add_child(_create_role_exchange_card(role_type, entry.id, entry.cost))

func _create_role_exchange_card(role_type: String, role_id: String, cost: int) -> Button:
	var cfg = data.get_hero_config(role_id) if role_type == "hero" else data.get_friend_config(role_id)
	var owned = data.heroes.has(role_id) if role_type == "hero" else data.friends.has(role_id)
	var have = data.items.get("hero_token", 0)
	
	var cell = Button.new()
	cell.custom_minimum_size = Vector2(0, 140)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	if role_type == "hero":
		name_lbl.text = "【%s】%s" % [cfg.name, cfg.category]
	else:
		name_lbl.text = "【%s】" % cfg.name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lbl)
	
	var status_lbl = Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_lbl)
	
	if owned:
		status_lbl.text = "已拥有"
		cell.disabled = true
		cell.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		status_lbl.text = "兑换（%d/%d）" % [have, cost]
		cell.disabled = have < cost
		cell.pressed.connect(_on_exchange_role.bind(role_type, role_id, cost))
	
	return cell

func show_series_exchange_view(series_index: int):
	_current_series_index = series_index
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("ExchangeEntryBox").visible = false
	ev.get_node("BeastExchangeView").visible = false
	ev.get_node("TokenExchangeView").visible = false
	ev.get_node("SeriesExchangeView").visible = true
	update_series_exchange_view()

func hide_series_exchange_view():
	_current_series_index = -1
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("SeriesExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

func update_series_exchange_view():
	if _current_series_index < 0: return
	var view = c.get_node("PageContainer/AdventurePage/ExchangeView/SeriesExchangeView")
	var series = data.SERIES_EXCHANGE[_current_series_index]
	view.get_node("SeriesTitle").text = "—— %s ——" % series.series
	
	var list = view.get_node("SeriesExchangeScroll/SeriesExchangeList")
	for child in list.get_children():
		child.queue_free()
	
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(grid)
	
	for entry in series.heroes:
		grid.add_child(_create_series_exchange_card(entry, series))

func _create_series_exchange_card(entry: Dictionary, series: Dictionary) -> Button:
	var hero_id = entry.hero
	var cfg = data.get_hero_config(hero_id)
	var item_name = data.ITEM_CONFIG.get(entry.item, {}).get("name", entry.item)
	var have = data.items.get(entry.item, 0)
	var owned = data.heroes.has(hero_id)
	var grant_friend = series.get("grant_friend", false)
	
	var cell = Button.new()
	cell.custom_minimum_size = Vector2(0, 160)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = "【%s】%s" % [cfg.name, cfg.category]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lbl)
	
	var item_lbl = Label.new()
	item_lbl.text = "%s ×%d" % [item_name, entry.cost]
	if grant_friend:
		item_lbl.text += "\n（赠同名挚友）"
	item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(item_lbl)
	
	var status_lbl = Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_lbl)
	
	if owned:
		status_lbl.text = "已拥有"
		cell.disabled = true
		cell.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		status_lbl.text = "兑换（%d/%d）" % [have, entry.cost]
		cell.disabled = have < entry.cost
		cell.pressed.connect(_on_exchange_series_hero.bind(entry, series))
	
	return cell

func _on_exchange_series_hero(entry: Dictionary, series: Dictionary):
	var friend_id = ""
	if series.get("grant_friend", false):
		friend_id = entry.get("friend", "")
	
	var result = data.exchange_series_hero(entry.hero, entry.item, entry.cost, friend_id)
	if result.ok:
		var cfg = data.get_hero_config(entry.hero)
		if friend_id != "":
			var fcfg = data.get_friend_config(friend_id)
			c._show_stage_hint("兑换成功！获得门客【%s】和挚友【%s】" % [cfg.name, fcfg.name])
		else:
			c._show_stage_hint("兑换成功！获得门客【%s】" % cfg.name)
		update_series_exchange_view()
		c.update_all_ui()
		c.update_bag_list()
		c.generate_hero_list()
		c.update_friend_page()
	else:
		c._show_stage_hint(result.reason)

func _on_exchange_role(role_type: String, role_id: String, cost: int):
	var result = data.exchange_role_with_token(role_type, role_id, cost)
	if result.ok:
		var cfg = data.get_hero_config(role_id) if role_type == "hero" else data.get_friend_config(role_id)
		c._show_stage_hint("兑换成功！获得【%s】" % cfg.name)
		update_token_exchange_view()
		c.update_all_ui()
		c.update_bag_list()
		if role_type == "hero":
			c.generate_hero_list()
		c.update_friend_page()
	else:
		c._show_stage_hint(result.reason)


func _on_exchange_beast(beast_id: String):
	var cfg = data.get_beast_config(beast_id)
	var ex = cfg.get("exchange_item", "")
	if data.items.get(ex, 0) < 100:
		c._show_stage_hint("【%s】兑换道具不足！" % cfg.name)
		return
	data.items[ex] -= 100
	if data.add_beast(beast_id):
		c.update_beast_page()
		c.update_all_ui()
		c.update_bag_list()
		c._show_stage_hint("兑换成功！获得【%s】" % cfg.name)
		# 如果兑换视图打开，也刷新
		if c.has_node("PageContainer/AdventurePage/ExchangeView/BeastExchangeView") and c.get_node("PageContainer/AdventurePage/ExchangeView/BeastExchangeView").visible:
			update_beast_exchange_view()
	else:
		c._show_stage_hint("兑换失败")
