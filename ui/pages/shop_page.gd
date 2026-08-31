# ============================================================
# 商铺页（含钱庄面板/店员分配）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name ShopPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_shop_list():
	if not c.has_node("PageContainer/ShopPage/ShopScroll/ShopList"): return
	
	var list = c.get_node("PageContainer/ShopPage/ShopScroll/ShopList")
	
	for child in list.get_children():
		child.queue_free()
	
	list.columns = 2
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 8)
	
	for shop_id in data.SHOP_ORDER:
		var btn = Button.new()
		btn.name = shop_id + "_entry"
		btn.custom_minimum_size = Vector2(0, 64)  # 【改】60→64，容纳两行文字
		btn.clip_text = true                      # 【新增】防长文本把按钮最小宽度撑出视口（横滚条根因）
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(on_shop_entry_pressed.bind(shop_id))
		list.add_child(btn)

func on_shop_entry_pressed(shop_id: String):
	if data.shops.has(shop_id):
		open_shop_panel(shop_id)
	elif data.can_unlock_shop(shop_id):
		if data.unlock_shop(shop_id):
			c.update_all_ui()
			c._show_stage_hint("解锁【%s】成功！" % data.get_shop_config(shop_id).name)
			open_shop_panel(shop_id)
	else:
		var need = data.get_shop_unlock_chapter(shop_id)
		c._show_stage_hint("【%s】通关第%d章解锁" % [data.get_shop_config(shop_id).name, need])

func _show_hero_assign_selector(slot: int):
	if c.current_shop_id == "": return
	c.close_popup()  # 先关闭店铺面板，防止遮挡
	c._current_popup = null  # 清空弹窗记录，避免全局点击误关
	
	var overlay = c.get_node("Overlay")
	overlay.show()
	
	var selector = PanelContainer.new()
	selector.name = "AssignSelector"
	selector.custom_minimum_size = Vector2(500, 400)
	 # 【修】原硬编码 Vector2(326,150) 在 600 宽基准分辨率下导致弹窗偏右出界，
	#       改按当前视口尺寸动态居中（与 _create_base_popup 居中逻辑一致）
	var vs = c.get_viewport_rect().size
	selector.position = Vector2((vs.x - 500) / 2, (vs.y - 400) / 2)
	selector.z_index = 20
	
	 # 【修】补弹窗背景样式，解决默认背景过淡与底层混淆
	var sel_style = StyleBoxFlat.new()
	sel_style.bg_color = Color("#1e1b2e")   # 弹窗统一底色；觉得不够深可改 #15121e
	sel_style.set_corner_radius_all(12)
	selector.add_theme_stylebox_override("panel", sel_style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	selector.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择门客派遣到【%s】" % data.shops[c.current_shop_id].name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	# 显示所有"闲置"门客
	var has_idle = false
	for hero_id in data.heroes.keys():
		var h = data.heroes[hero_id]
		if h.assigned_shop != "": continue  # 已派遣的跳过
		
		has_idle = true
		var btn = Button.new()
		var income = data.get_hero_income(hero_id)
		btn.text = "【%s】%s Lv.%d | %s/秒" % [h.name, h.category, h.level, c.format_number(income)]
		# 【修】手机端：按钮默认 STOP 拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.pressed.connect(_on_hero_assigned.bind(hero_id, slot))
		list.add_child(btn)
	
	if not has_idle:
		var empty = Label.new()
		empty.text = "暂无可派遣门客"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_close_assign_selector)
	vbox.add_child(cancel_btn)
	
	c.add_child(selector)


func _close_assign_selector():
	if c.has_node("AssignSelector"):
		c._safe_close("AssignSelector")
	c.get_node("Overlay").hide()
	# 重新打开店铺面板
	if c.current_shop_id != "":
		c.open_popup(c.get_node("ShopPanel"))
		update_shop_panel()

func _on_hero_assigned(hero_id: String, _slot: int):
	data.heroes[hero_id].assigned_shop = c.current_shop_id
	_close_assign_selector()
	update_shop_panel()
	c.update_all_ui()
	c.update_hero_list()

func _on_hero_unassign(hero_id: String):
	data.heroes[hero_id].assigned_shop = ""
	update_shop_panel()
	c.update_all_ui()
	c.update_hero_list()

func open_hq_panel():
	if c.has_node("HQPanel"):
		c.open_popup(c.get_node("HQPanel"))
		update_hq_panel()

func close_hq_panel():
	c.close_popup()
	c.update_hero_list()

func open_shop_panel(shop_id: String):
	c.current_shop_id = shop_id
	if c.has_node("ShopPanel"):
		c.open_popup(c.get_node("ShopPanel"))
		update_shop_panel()

func close_shop_panel():
	c.close_popup()
	c.current_shop_id = ""



func on_hq_click():
	data.money += data.hq.click_income
	c.update_all_ui()
	c.animate_button("HQPanel/HQClickBtn")

func on_hq_upgrade():
	if data.upgrade_hq():
		c.update_all_ui()
		c.update_bag_list()
	else:
		c.flash_red("HQPanel/HQUpgradeBtn")

func on_current_shop_upgrade():
	if data.upgrade_shop(c.current_shop_id):
		c.update_all_ui()
		c.update_bag_list()
	else:
		c.flash_red("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn")

func on_current_shop_hire():
	var batch = false
	if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck"):
		batch = c.get_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck").button_pressed
	
	var count = 10 if batch else 1
	var success = 0
	for i in range(count):
		if data.hire_staff(c.current_shop_id):
			success += 1
		else:
			break
	
	if success > 0:
		c.update_all_ui()
	else:
		c.flash_red("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn")

func _on_batch_hire_toggled(_pressed: bool):
	if c.current_shop_id != "" and c.has_node("ShopPanel") and c.get_node("ShopPanel").visible:
		update_shop_panel()

func update_entry_buttons():
	if c.has_node("PageContainer/ShopPage/HQEntryBtn"):
		var income = data.get_hq_auto_income()
		c.get_node("PageContainer/ShopPage/HQEntryBtn").text = "【钱庄】Lv.%d  |  挂机 %d/秒  |  点击 +%d" % [data.hq.level, income, data.hq.click_income]
	
	if not c.has_node("PageContainer/ShopPage/ShopScroll/ShopList"): return
	for btn in c.get_node("PageContainer/ShopPage/ShopScroll/ShopList").get_children():
		var shop_id = btn.name.replace("_entry", "")
		var cfg = data.get_shop_config(shop_id)
		if cfg.is_empty(): continue
		
		# 【改】文字拆两行，单行太长会撑宽网格列（600视口2列装不下）
		if data.shops.has(shop_id):
			var s = data.shops[shop_id]
			var income = data.get_shop_auto_income(shop_id)
			btn.text = "【%s】Lv.%d\n赚速 %s/秒  |  店员 %d人" % [s.name, s.level, c.format_number(income), s.staff]
			btn.modulate = Color.WHITE
			btn.disabled = false
		elif data.can_unlock_shop(shop_id):
			btn.text = "【%s】\n点击解锁（第%d章）" % [cfg.name, data.get_shop_unlock_chapter(shop_id)]
			btn.modulate = Color("#e0c070")
			btn.disabled = false
		else:
			btn.text = "【%s】\n未解锁（第%d章）" % [cfg.name, data.get_shop_unlock_chapter(shop_id)]
			btn.modulate = Color(0.4, 0.4, 0.4, 0.6)
			btn.disabled = true

func update_hq_panel():
	if c.has_node("HQPanel/VBoxContainer/HQName"):
		c.get_node("HQPanel/VBoxContainer/HQName").text = "【%s】Lv.%d" % [data.hq.name, data.hq.level]
	if c.has_node("HQPanel/VBoxContainer/HQInfo"):
		var auto = data.get_hq_auto_income()
		var bonus = data.get_global_bonus_percent() * 100
		c.get_node("HQPanel/VBoxContainer/HQInfo").text = "挂机 %s/秒  |  点击 +%s  |  全局加成 +%d%%" % [c.format_number(auto), c.format_number(data.hq.click_income), bonus]
	if c.has_node("HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn"):
		c.get_node("HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn").text = "🔨 升级（%d图纸）" % data.hq.upgrade_cost

func update_shop_panel():
	if c.current_shop_id == "": return
	var s = data.shops[c.current_shop_id]
	var cost = s.hire_cost
	
	if c.has_node("ShopPanel/VBoxContainer/ShopName"):
		c.get_node("ShopPanel/VBoxContainer/ShopName").text = "【%s】Lv.%d" % [s.name, s.level]
	if c.has_node("ShopPanel/VBoxContainer/ShopInfo"):
		var income = data.get_shop_auto_income(c.current_shop_id)
		c.get_node("ShopPanel/VBoxContainer/ShopInfo").text = "赚速 %s/秒  |  店员 %d人" % [c.format_number(income), s.staff]
	if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn"):
		c.get_node("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn").text = "🔨 升级（%d道具）" % s.upgrade_cost
	if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn"):
		var batch = false
		if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck"):
			batch = c.get_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck").button_pressed
		
		if batch:
			var total_cost = 0
			var temp_cost = cost
			for i in range(10):
				total_cost += temp_cost
				temp_cost = int(ceil(temp_cost * 1.01))
			c.get_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn").text = "👤 招募（%s铜钱）" % c.format_number(total_cost)
		else:
			c.get_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn").text = "👤 招募（%s铜钱）" % c.format_number(cost)
	
	
	# 更新槽位内容
	var assign_box = c.get_node("ShopPanel/VBoxContainer/AssignContainer")
	
	# 收集当前店铺已派遣的门客
	var assigned_heroes: Array = []
	for hero_id in data.heroes.keys():
		if data.heroes[hero_id].assigned_shop == c.current_shop_id:
			assigned_heroes.append(hero_id)
	
	for slot in range(5):
		var row = assign_box.get_node("AssignSlot_" + str(slot))
		var label = row.get_node("AssignLabel")
		var btn = row.get_node("AssignBtn")
		
		# 断开旧信号
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)
		
		if slot == 4:
			label.text = "【派遣位5】任务解锁"
			btn.text = "封禁"
			btn.disabled = true
			continue
		
		var assigned_id = assigned_heroes[slot] if slot < assigned_heroes.size() else ""
		
		if assigned_id != "":
			var h = data.heroes[assigned_id]
			label.text = "【%s】%s | %s/秒" % [h.name, h.category, c.format_number(data.get_hero_income(assigned_id))]
			btn.text = "撤下"
			btn.disabled = false
			btn.pressed.connect(_on_hero_unassign.bind(assigned_id))
		else:
			label.text = "【派遣位%d】空闲" % (slot + 1)
			btn.text = "派遣"
			btn.disabled = false
			btn.pressed.connect(_show_hero_assign_selector.bind(slot))
