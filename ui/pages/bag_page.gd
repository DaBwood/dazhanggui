# ============================================================
# 背包页（含道具使用/人参/门客盒子选择器）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name BagPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var _pending_ginseng_count: int = 0
var _pending_ginseng_type: String = ""

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_bag_list():
	if not c.has_node("PageContainer/BagPage"): return
	var bag_page = c.get_node("PageContainer/BagPage")
	
	# 【改】BagScroll 填满 BagPage，BagGrid 必须放在 BagScroll 内部
	var scroll: ScrollContainer
	if bag_page.has_node("BagScroll"):
		scroll = bag_page.get_node("BagScroll")
	else:
		scroll = ScrollContainer.new()
		scroll.name = "BagScroll"
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		bag_page.add_child(scroll)
	
	# 自动创建 GridContainer（如果没有），作为 ScrollContainer 的子节点
	var grid: GridContainer
	if scroll.has_node("BagGrid"):
		grid = scroll.get_node("BagGrid")
	else:
		grid = GridContainer.new()
		grid.name = "BagGrid"
		grid.columns = 5
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
	
	# 清空旧格子
	for child in grid.get_children():
		child.queue_free()
	
	# 【改】为每种物品生成简洁按钮，只显示名称
	for item_id in data.ITEM_CONFIG.keys():
		var cfg = data.ITEM_CONFIG[item_id]
		
		# 跳过隐藏道具（如鱼食）
		if cfg.get("hide_in_bag", false):
			continue
		
		var count = data.items.get(item_id, 0)
		if item_id == "lottery_ticket":
			count = data.lottery_ticket

		var btn = Button.new()
		btn.name = item_id + "_btn"
		btn.text = "%s\nx%d" % [cfg.name, count]   # 名称第一行，数量第二行
		btn.custom_minimum_size = Vector2(0, 50)    # 不限制宽度，高度44容纳两行
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 【修】手机端：按钮默认 STOP 会拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		# 文字样式
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.8))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		# 按钮样式：深色底+淡边框
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.14, 0.18)
		btn_style.border_color = Color(0.35, 0.32, 0.40)
		btn_style.border_width_bottom = 2
		btn_style.corner_radius_top_left = 3
		btn_style.corner_radius_top_right = 3
		btn_style.corner_radius_bottom_left = 3
		btn_style.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", btn_style)
		var hover_style = btn_style.duplicate()
		hover_style.bg_color = Color(0.22, 0.20, 0.28)
		hover_style.border_color = Color(0.50, 0.45, 0.60)
		btn.add_theme_stylebox_override("hover", hover_style)
		var press_style = btn_style.duplicate()
		press_style.bg_color = Color(0.10, 0.09, 0.13)
		btn.add_theme_stylebox_override("pressed", press_style)
		# 点击打开详情弹窗
		btn.pressed.connect(_show_item_detail_popup.bind(item_id))
		grid.add_child(btn)

# 【新增】物品详情弹窗：显示名称、数量、描述，可用道具附带使用按钮
func _show_item_detail_popup(item_id: String):
	var cfg = data.ITEM_CONFIG.get(item_id, {})
	var count = data.items.get(item_id, 0)
	if item_id == "lottery_ticket":
		count = data.lottery_ticket
	
	var popup = c._create_base_popup(cfg.get("name", "物品详情"), Vector2(360, 260))
	popup.name = "ItemDetailPopup"
	var vbox = popup.get_child(0)
	
	# 数量
	var count_lbl = Label.new()
	count_lbl.text = "数量：x%d" % count
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(count_lbl)
	
	# 描述
	var desc_lbl = Label.new()
	desc_lbl.text = cfg.get("desc", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)
	
	# 可使用道具：在弹窗内附加使用按钮
	var use_cfg = cfg.get("use", {})
	if not use_cfg.is_empty() and count > 0:
		var use_btn = Button.new()
		use_btn.text = use_cfg.get("btn", "使用")
		use_btn.custom_minimum_size = Vector2(100, 36)
		var title = use_cfg.get("title", "使用" + cfg.get("name", ""))
		match use_cfg.get("type", ""):
			"quantity", "stage_box":
				use_btn.pressed.connect(func():
					popup.queue_free()
					c._show_quantity_selector(item_id, title, _on_item_use_confirmed)
				)
			"ginseng":
				use_btn.pressed.connect(func():
					popup.queue_free()
					c._show_quantity_selector(item_id, title, _on_ginseng_confirmed)
				)
			"hero_box":
				use_btn.pressed.connect(func():
					popup.queue_free()
					_show_hero_box_selector()
				)
			"friend_box":
				use_btn.pressed.connect(func():
					popup.queue_free()
					if has_method("_show_friend_box_selector"):
						_show_friend_box_selector()
					else:
						c._show_stage_hint("挚友盒子功能开发中")
				)
			"item_box":
				use_btn.pressed.connect(func():
					popup.queue_free()
					if has_method("_show_item_box_selector"):
						_show_item_box_selector()
					else:
						c._show_stage_hint("物品盒子功能开发中")
				)
			"manhuang_box":
				use_btn.pressed.connect(func():
					popup.queue_free()
					_show_manhuang_box_selector()   # 【新增】蛮荒礼盒：自选一种道具×100
				)
			"soul_stone_box":   # 【新增】魂石宝箱：直接开出随机优秀魂石
					use_btn.pressed.connect(func(): _on_soul_box_open(item_id, "normal"))
			"soul_wushuang_box":   # 【新增】无双魂石箱：开出四格同色无双魂石
					use_btn.pressed.connect(func(): _on_soul_box_open(item_id, "wushuang"))
		vbox.add_child(use_btn)
	
	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")
	c.add_child(popup)


func _on_item_use_confirmed(spin: SpinBox):
	var count = int(spin.value)
	var item_id = c._quantity_item_id
	c._quantity_item_id = ""
	if item_id == "": return
	var result = data.use_item(item_id, count)
	c._close_quantity_selector()
	if result.get("ok", false):
		update_bag_list()
		c.update_all_ui()
		# 【改动】带 gains 明细的道具（关卡宝箱）弹窗展示明细，其余维持飘字提示
		if result.has("gains"):
			_show_item_gains_popup("打开关卡宝箱", result.gains)
		else:
			c._show_stage_hint(result.get("msg", "使用成功"))
	else:
		c._show_stage_hint(result.get("msg", "使用失败"))

func update_bag_list():
	generate_bag_list()

func _on_ginseng_confirmed(spin: SpinBox):
	var count = int(spin.value)
	var item_id = c._quantity_item_id
	c._quantity_item_id = ""
	if item_id == "": return
	if data.items.get(item_id, 0) < count:
		c._close_quantity_selector()
		return
	_pending_ginseng_count = count
	_pending_ginseng_type = item_id
	c._close_quantity_selector()
	_show_ginseng_selector()



func _show_ginseng_selector():
	var bag_page = c.get_node("PageContainer/BagPage")
	if bag_page.has_node("GinsengSelector"): return
	
	var panel = PanelContainer.new()
	panel.name = "GinsengSelector"
	panel.custom_minimum_size = Vector2(500, 400)
	var vs = c.get_viewport_rect().size
	panel.position = Vector2((vs.x - 500) / 2, (vs.y - 400) / 2)
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	 # 【修】补弹窗背景样式，解决默认背景过淡与底层混淆
	var sel_style = StyleBoxFlat.new()
	sel_style.bg_color = Color("#1e1b2e")   # 弹窗统一底色；觉得不够深可改 #15121e
	sel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", sel_style)
	
	var title = Label.new()
	title.text = "选择门客使用%s" % data.ITEM_CONFIG.get(_pending_ginseng_type, {}).get("name", "人参")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	# 【改】门客按实时赚速降序排列（原按字典顺序）
	var hero_ids = data.heroes.keys()
	hero_ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hero_id in hero_ids:
		var h = data.heroes[hero_id]
		var btn = Button.new()
		# 【改】按钮文本补上赚速（排序依据可见，否则顺序看起来是乱的；与其他选择器样式一致）
		btn.text = "【%s】%s Lv.%d | %s/秒" % [h.name, h.category, h.level, c.format_number(data.get_hero_income(hero_id))]
		btn.pressed.connect(_on_ginseng_target_selected.bind(hero_id))
		list.add_child(btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_close_ginseng_selector)
	vbox.add_child(cancel_btn)
	
	bag_page.add_child(panel)

func _on_ginseng_target_selected(hero_id: String):
	var count = _pending_ginseng_count
	var item_id = _pending_ginseng_type
	if item_id == "":
		_close_ginseng_selector()
		return
	if data.items.get(item_id, 0) < count:
		_close_ginseng_selector()
		return
	
	data.items[item_id] -= count
	if item_id == "ginseng":
		data.heroes[hero_id].extra_income += 2000 * count
	else:
		data.heroes[hero_id].extra_income += 20000 * count
	
	_pending_ginseng_count = 0
	_pending_ginseng_type = ""
	_close_ginseng_selector()
	update_bag_list()
	c.update_all_ui()

func _close_ginseng_selector():
	var bag_page = c.get_node("PageContainer/BagPage")
	if bag_page.has_node("GinsengSelector"):
		bag_page.get_node("GinsengSelector").queue_free()
	_pending_ginseng_count = 0
	_pending_ginseng_type = ""

func _show_hero_box_selector():
	if c.has_node("HeroBoxSelector"): return
	
	var panel = c._create_base_popup("选择门客", Vector2(460, 500), Vector2(346, 120))
	panel.name = "HeroBoxSelector"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 380)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	var has_unlockable = false
	for hero_id in data.get_all_hero_ids():
		if data.heroes.has(hero_id): continue  # 已拥有的跳过
		
		var cfg = data.get_hero_config(hero_id)
		var btn = Button.new()
		var vip_lv = data.get_hero_unlock_vip(hero_id)
		btn.text = "【%s】%s  |  VIP%d解锁" % [cfg.name, cfg.category, vip_lv]
		btn.pressed.connect(_on_hero_box_selected.bind(hero_id))
		list.add_child(btn)
		has_unlockable = true
	
	if not has_unlockable:
		var empty = Label.new()
		empty.text = "所有门客已拥有"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("HeroBoxSelector"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

# 【新增】挚友盒子选择弹窗：列出所有未拥有的挚友，点击即获得（不可重复）
func _show_friend_box_selector():
	if c.has_node("FriendBoxSelector"): return
	
	var panel = c._create_base_popup("选择挚友", Vector2(460, 500), Vector2(346, 120))
	panel.name = "FriendBoxSelector"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 380)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	var has_unlockable = false
	for friend_id in data.get_all_friend_ids():
		if data.friends.has(friend_id): continue  # 已拥有的跳过
		
		var cfg = data.get_friend_config(friend_id)
		var btn = Button.new()
		var vip_lv = data.get_friend_unlock_vip(friend_id)
		btn.text = "【%s】%s  |  VIP%d解锁" % [cfg.name, "挚友", vip_lv]
		btn.pressed.connect(_on_friend_box_selected.bind(friend_id))
		list.add_child(btn)
		has_unlockable = true
	
	if not has_unlockable:
		var empty = Label.new()
		empty.text = "所有挚友已拥有"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("FriendBoxSelector"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

# 【新增】开启魂石宝箱：扣1个箱子→soul_system.open_box→提示获得的魂石（品质/各格颜色词条）
func _on_soul_box_open(item_id: String, kind: String):
	if int(data.items.get(item_id, 0)) < 1:
		c._show_stage_hint("没有可开启的" + data.ITEM_CONFIG.get(item_id, {}).get("name", "宝箱"))
		return
	data.items[item_id] = int(data.items.get(item_id, 0)) - 1
	var res: Dictionary = data.soul_system.open_box(kind)
	var st: Dictionary = res.get("stone", {})
	var parts = []
	for cell in st.get("cells", []):
		parts.append("%s+%d" % [cell.get("color", "?"), int(cell.get("apt", 0))])
	c._show_stage_hint("获得【%s】魂石（%d格）：%s" % [st.get("quality", "?"), st.get("cells", []).size(), "  ".join(parts)])
	update_bag_list()   # 若你本地按钮化后刷新函数名不同，换成本地同一个刷新调用
	c.update_all_ui()

# 【新增】挚友盒子选择回调
func _on_friend_box_selected(friend_id: String):
	if data.items.get("friend_box", 0) < 1:
		c._safe_close("FriendBoxSelector")
		return
	
	data.items.friend_box -= 1
	data.unlock_friend(friend_id)
	
	var cfg = data.get_friend_config(friend_id)
	c._safe_close("FriendBoxSelector")
	c._show_stage_hint("获得挚友【%s】" % cfg.name)
	c.update_all_ui()
	update_bag_list()

# 【新增】物品盒子选择弹窗（支持批量）：顶部选使用数量，下面选道具，点击即结算
func _show_item_box_selector():
	if c.has_node("ItemBoxSelector"): return
	
	var have = data.items.get("item_box", 0)
	if have <= 0: return
	
	var panel = c._create_base_popup("物品盒子（拥有%d个）" % have, Vector2(460, 520), Vector2(346, 100))
	panel.name = "ItemBoxSelector"
	var vbox = panel.get_child(0)
	
	# 数量选择行
	var qty_row = HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 8)
	vbox.add_child(qty_row)
	var qty_lbl = Label.new()
	qty_lbl.text = "使用数量："
	qty_row.add_child(qty_lbl)
	var qty_spin = SpinBox.new()
	qty_spin.name = "ItemBoxQtySpin"
	qty_spin.min_value = 1
	qty_spin.max_value = have
	qty_spin.value = 1
	qty_spin.custom_minimum_size = Vector2(120, 32)
	qty_row.add_child(qty_spin)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 360)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	# 排除盒子类道具，防止递归
	var exclude_ids = ["hero_box", "friend_box", "item_box"]
	for item_id in data.ITEM_CONFIG.keys():
		if item_id in exclude_ids: continue
		
		var cfg = data.ITEM_CONFIG[item_id]
		var btn = Button.new()
		btn.text = "【%s】%s" % [cfg.name, cfg.desc]
		# 点击时读取当前 SpinBox 的值作为使用数量
		btn.pressed.connect(_on_item_box_selected.bind(item_id, qty_spin))
		list.add_child(btn)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("ItemBoxSelector"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

# 【新增】物品盒子选择回调（批量）：扣除N个盒子，获得N个选定道具
func _on_item_box_selected(item_id: String, qty_spin: SpinBox):
	var count = int(qty_spin.value)
	if data.items.get("item_box", 0) < count:
		c._safe_close("ItemBoxSelector")
		return
	
	data.items.item_box -= count
	data.items[item_id] = data.items.get(item_id, 0) + count
	
	var cfg = data.ITEM_CONFIG.get(item_id, {})
	c._safe_close("ItemBoxSelector")
	c._show_stage_hint("使用%d个物品盒子，获得【%s】×%d" % [count, cfg.get("name", item_id), count])
	c.update_all_ui()
	update_bag_list()

func _on_hero_box_selected(hero_id: String):
	if data.items.get("hero_box", 0) < 1:
		c._safe_close("HeroBoxSelector")
		return
	
	data.items.hero_box -= 1
	data.unlock_hero(hero_id)
	
	var cfg = data.get_hero_config(hero_id)
	c._safe_close("HeroBoxSelector")
	c._show_stage_hint("获得门客【%s】" % cfg.name)
	c.update_all_ui()
	update_bag_list()
	c.generate_hero_list() 

# 【新增】道具获得明细弹窗（关卡宝箱等批量开启道具用）：按配置表顺序逐项列出获得物，点确定关闭
func _show_item_gains_popup(title: String, gains: Dictionary):
	var popup = c._create_base_popup(title, Vector2(420, 480), Vector2(366, 100))
	popup.name = "ItemGainsPopup"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# 按 ITEM_CONFIG 配置顺序展示（未在配置里的 id 排最后，防御性处理）
	var ordered = []
	for iid in data.ITEM_CONFIG.keys():
		if gains.has(iid):
			ordered.append(iid)
	for iid in gains.keys():
		if not ordered.has(iid):
			ordered.append(iid)
	for iid in ordered:
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = "【%s】×%d" % [data.ITEM_CONFIG.get(iid, {}).get("name", iid), gains[iid]]
		list.add_child(lbl)
	c._add_ok_button(vb, func(): popup.queue_free(), "确定")
	c.add_child(popup)

# 【新增】蛮荒礼盒选择器：列出4种蛮荒兑换道具（显示现有数量+对应珍兽），点"选择"扣1礼盒得该道具×100
func _show_manhuang_box_selector():
	var popup = c._create_base_popup("蛮荒礼盒", Vector2(420, 420))
	var vbox = popup.get_child(0)
	var hint = Label.new()
	hint.text = "选择一种道具，获得 ×100"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	# 礼盒可兑的5种道具（道具id, 对应珍兽名）
	var options = [["jiu_yuan_shui", "相柳"],["yu_ling_zhi", "乘黄"], ["hu_po_yao_shi", "陆吾"], ["long_hun_jing_yuan", "应龙"], ["fu_sang_zhi", "金乌"]]
	for opt in options:
		var iid: String = opt[0]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s（%s）拥有：%d" % [data.ITEM_CONFIG.get(iid, {}).get("name", iid), opt[1], int(data.items.get(iid, 0))]
		row.add_child(lbl)
		var btn = Button.new()
		btn.text = "选择"
		btn.custom_minimum_size = Vector2(80, 40)
		btn.pressed.connect(_on_manhuang_box_pick.bind(popup, iid))
		row.add_child(btn)
		vbox.add_child(row)
	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 【新增】蛮荒礼盒确认：扣1个礼盒、发100个所选道具，刷新背包
func _on_manhuang_box_pick(popup, item_id: String):
	if int(data.items.get("manhuang_box", 0)) < 1:
		c._show_stage_hint("蛮荒礼盒不足！")
		return
	data.items["manhuang_box"] -= 1
	data.items[item_id] = int(data.items.get(item_id, 0)) + 100
	popup.queue_free()
	c._show_stage_hint("获得【%s】×100" % data.ITEM_CONFIG.get(item_id, {}).get("name", item_id))
	c.update_bag_list()
