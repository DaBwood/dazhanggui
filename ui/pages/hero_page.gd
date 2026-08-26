# ============================================================
# 门客页（含门客面板/珍兽装备选择）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name HeroPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var current_hero_id: String = ""

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_hero_list():
	if data._hero_configs.is_empty():
		print("警告：门客配置为空，尝试重新加载...")
		data._load_all_configs()
	
	if not c.has_node("PageContainer/HeroPage"): return
	var scroll = c.get_node("PageContainer/HeroPage/HeroScroll")
	for child in scroll.get_children():
		scroll.remove_child(child) 
		child.queue_free()
	
	# 创建网格
	var grid = GridContainer.new()
	grid.name = "HeroGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	
	# 1. 已解锁门客
	for hero_id in data.heroes.keys():
		var cell = _create_hero_card(hero_id, false)
		grid.add_child(cell)
	
	# 2. 未解锁的VIP门客
	for hero_id in data.get_all_hero_ids():
		if not data.heroes.has(hero_id):
			var cell = _create_hero_card(hero_id, true)
			grid.add_child(cell)
	
	update_hero_list()

func _create_hero_card(hero_id: String, locked: bool) -> Button:
	var cell = Button.new()
	cell.name = hero_id + ("_hero_locked" if locked else "_hero")
	cell.custom_minimum_size = Vector2(200, 240)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_lbl)
	
	var income_lbl = Label.new()
	income_lbl.name = "IncomeLabel"
	income_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	income_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(income_lbl)
	
	var status_lbl = Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_lbl)
	
	if locked:
		cell.modulate = Color(0.5, 0.5, 0.5, 0.7)
		cell.pressed.connect(_on_locked_hero_clicked.bind(hero_id))
	else:
		cell.pressed.connect(open_hero_detail.bind(hero_id))
	
	return cell

func _on_locked_hero_clicked(hero_id: String):
	var vip_level = data.get_hero_unlock_vip(hero_id)
	var cfg = data.get_hero_config(hero_id)
	var hero_name = cfg.get("name", "未知门客")
	c._show_unlock_hint("门客 " + hero_name, vip_level)

func open_hero_panel(hero_id: String):
	current_hero_id = hero_id
	if c.has_node("HeroPanel"):
		c.open_popup(c.get_node("HeroPanel"))
		update_hero_panel()

func close_hero_panel():
	c.close_popup()
	current_hero_id = ""
	update_hero_list()

func update_hero_panel():
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var h = data.heroes[current_hero_id]
	var income = data.get_hero_income(current_hero_id)
	var total_aptitude = HeroData.get_total_aptitude(data, current_hero_id)   # 【改】面板资质 = 总资质（含珍兽），与赚速同口径；适配新签名
	var quality_tag = ""
	if h.has("quality") and h.quality > 0:
		quality_tag = "[%s]" % HeroData.get_quality_name(h.quality)
	
	if c.has_node("HeroPanel/HeroName"):
		c.get_node("HeroPanel/HeroName").text = "【%s】%s %s Lv.%d" % [h.name, h.category, quality_tag, h.level]
	if c.has_node("HeroPanel/HeroIncome"):
		c.get_node("HeroPanel/HeroIncome").text = "赚速：%s/秒  资质：%d" % [c.format_number(income), total_aptitude]
	
	# 清理旧布局（如果有）
	if c.has_node("HeroPanel/BeastInfoBox"):
		c.get_node("HeroPanel/BeastInfoBox").queue_free()
	
	# ========== 缘分按钮 + 珍兽装备按钮（HeroIncome 下方，上下排列）==========
	var beast_id = data.heroes[current_hero_id].get("equipped_beast", "")
	var beast_idx = data.heroes[current_hero_id].get("equipped_beast_index", 0)
	var income_label = c.get_node("HeroPanel/HeroIncome")
	# 【修复】显式固定尺寸：新建 Button 当帧 size 为 (0,0)，不能用 size 做定位依据
	var btn_size = Vector2(120, 40)
	
	# 【新增】缘分按钮（上行）：点击弹窗显示该门客的缘分挚友
	var fate_btn = c.get_node("HeroPanel").get_node_or_null("FateBtn")
	if fate_btn == null:
		fate_btn = Button.new()
		fate_btn.name = "FateBtn"
		fate_btn.text = "缘分"
		fate_btn.add_theme_font_size_override("font_size", 14)
		c.get_node("HeroPanel").add_child(fate_btn)
	fate_btn.size = btn_size
	fate_btn.position = Vector2(income_label.position.x, income_label.position.y + income_label.size.y + 4)
	# 信号重连（先断后连，防止切换门客后串数据）
	for conn in fate_btn.pressed.get_connections():
		fate_btn.pressed.disconnect(conn.callable)
	fate_btn.pressed.connect(_on_fate_btn_clicked.bind(current_hero_id))
	
	# 珍兽按钮（下行）：原有创建逻辑，位置改为缘分按钮正下方
	var beast_btn = c.get_node("HeroPanel").get_node_or_null("BeastEquipBtn")
	if beast_btn == null:
		beast_btn = Button.new()
		beast_btn.name = "BeastEquipBtn"
		beast_btn.add_theme_font_size_override("font_size", 14)
		c.get_node("HeroPanel").add_child(beast_btn)
	beast_btn.size = btn_size
	beast_btn.position = Vector2(income_label.position.x, fate_btn.position.y + btn_size.y + 4)
	
	# 把技能列表下移到珍兽按钮下方，避免重叠（原有逻辑不变，基准仍是珍兽按钮底部）
	if c.get_node("HeroPanel").has_node("ScrollContainer"):
		var scroll = c.get_node("HeroPanel/ScrollContainer")
		var needed_y = beast_btn.position.y + beast_btn.size.y + 8
		if scroll.position.y < needed_y:
			scroll.position.y = needed_y
	
	for conn in beast_btn.pressed.get_connections():
		beast_btn.pressed.disconnect(conn.callable)
	
	if beast_id != "":
		var b_cfg = data.get_beast_config(beast_id)
		var b_inst = data.get_beast_instance(beast_id, beast_idx)
		beast_btn.text = "【%s】Lv.%d" % [b_cfg.name, b_inst.level]
		beast_btn.pressed.connect(_on_hero_beast_btn_clicked.bind(beast_id, beast_idx))
	else:
		beast_btn.text = "珍兽"
		beast_btn.pressed.connect(_show_beast_selector_for_hero)
	
	#升级
	var level_box = c.get_node("HeroPanel").get_node("LevelUpBox")
	var max_lv = 50 + h.breakthrough_count * 50
	var need_bt = h.level >= max_lv
	var bt_cost = h.breakthrough_count * 10
	
	var lv_btn = level_box.get_node("LevelUpBtnBox/LevelUpBtn")
	var batch_check = level_box.get_node("LevelUpBtnBox/BatchCheck")
	
	if need_bt:
		# 到达突破节点：显示突破按钮，隐藏勾选框
		level_box.get_node("LevelUpInfo").text = "突破需%d风雅颂" % bt_cost
		lv_btn.text = "突破"
		batch_check.visible = false
		#关闭升级
		if lv_btn.pressed.is_connected(on_hero_level_upgrade):
			lv_btn.pressed.disconnect(on_hero_level_upgrade)
		#连接突破
		if not lv_btn.pressed.is_connected(on_hero_breakthrough):
			lv_btn.pressed.connect(on_hero_breakthrough)
	else:
		# 正常升级：显示升级按钮，显示勾选框
		var next_cost = int(ceil(100 * pow(1.05, h.level - 1)))
		level_box.get_node("LevelUpInfo").text = "升级需%d阅历" % next_cost
		lv_btn.text = "升级"
		batch_check.visible = true
		#关闭突破
		if lv_btn.pressed.is_connected(on_hero_breakthrough):
			lv_btn.pressed.disconnect(on_hero_breakthrough)
			#连接升级
		if not lv_btn.pressed.is_connected(on_hero_level_upgrade):
			lv_btn.pressed.connect(on_hero_level_upgrade)
	
	if not c.has_node("HeroPanel/ScrollContainer/SkillList"): return
	var list = c.get_node("HeroPanel/ScrollContainer/SkillList")
	
	# 清空
	for child in list.get_children():
		child.queue_free()
	
	# ========== 晋升系统（通用） ==========
	if h.has("promotion"):
		var promo = h.promotion
		var cost = promo.cost_amount
		var has_item = data.items.get(promo.cost_item, 0)
		var item_name = data.ITEM_CONFIG[promo.cost_item].name
		var promo_name = promo.get("name", "晋升")
		
		var promo_row = HBoxContainer.new()
		promo_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var promo_info = Label.new()
		promo_info.text = "【%s】%d/%d" % [promo_name, promo.level, promo.max_level]
		promo_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		promo_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		promo_info.clip_text = true
		promo_info.add_theme_color_override("font_color", Color("#ffd700"))
		promo_row.add_child(promo_info)
		
		var cost_label = Label.new()
		cost_label.text = "%s:%d/%d" % [item_name, has_item, cost]
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		promo_row.add_child(cost_label)
		
		var btn_box = VBoxContainer.new()
		btn_box.custom_minimum_size = Vector2(70, 0)
		btn_box.add_theme_constant_override("separation", 3)
		
		var single_btn = Button.new()
		single_btn.text = "升级"
		single_btn.custom_minimum_size = Vector2(70, 24)
		single_btn.add_theme_font_size_override("font_size", 12)
		single_btn.pressed.connect(on_promotion_upgrade.bind("single"))
		btn_box.add_child(single_btn)
		
		var bulk_btn = Button.new()
		bulk_btn.text = "一键"
		bulk_btn.custom_minimum_size = Vector2(70, 24)
		bulk_btn.add_theme_font_size_override("font_size", 12)
		bulk_btn.pressed.connect(on_promotion_upgrade.bind("bulk"))
		btn_box.add_child(bulk_btn)
		
		promo_row.add_child(btn_box)
		list.add_child(promo_row)
	
	
	# ========== 资质技能 ==========
	for i in range(h.aptitude_skills.size()):
		var skill = h.aptitude_skills[i]
		var apt_cost = max(1, int(ceil(pow(1.05, skill.level - 1))))
		
		var apt_row = HBoxContainer.new()
		apt_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var apt_info = Label.new()
		apt_info.text = "【资质】%s  Lv.%d/%d  需%d资质丹" % [skill.name, skill.level, skill.max_level, apt_cost]
		apt_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apt_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		apt_info.clip_text = true
		apt_info.custom_minimum_size.x = 380
		apt_row.add_child(apt_info)
		
		var apt_btn_box = VBoxContainer.new()
		apt_btn_box.custom_minimum_size = Vector2(70, 0)
		apt_btn_box.add_theme_constant_override("separation", 3)
		
		var apt_btn_single = Button.new()
		apt_btn_single.text = "升级"
		apt_btn_single.custom_minimum_size = Vector2(70, 24)
		apt_btn_single.add_theme_font_size_override("font_size", 12)
		apt_btn_single.pressed.connect(on_aptitude_skill_upgrade.bind(i, "single"))
		apt_btn_box.add_child(apt_btn_single)
		
		var apt_btn_bulk = Button.new()
		apt_btn_bulk.text = "一键升级"
		apt_btn_bulk.custom_minimum_size = Vector2(70, 24)
		apt_btn_bulk.add_theme_font_size_override("font_size", 12)
		apt_btn_bulk.pressed.connect(on_aptitude_skill_upgrade.bind(i, "bulk"))
		apt_btn_box.add_child(apt_btn_bulk)
		
		apt_row.add_child(apt_btn_box)
		list.add_child(apt_row)
	
	# ========== 店铺技能 ==========
	for i in range(h.shop_skills.size()):
		var skill = h.shop_skills[i]
		var current_percent = skill.base_percent + (skill.level - 1) * skill.percent_per_level
		var shop_cost = max(1, int(ceil(pow(1.05, skill.level - 1))))
		
		var shop_row = HBoxContainer.new()
		shop_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var shop_info = Label.new()
		shop_info.text = "【店铺】%s  Lv.%d/%d  (+%.0f%%)  需%d算盘" % [skill.name, skill.level, skill.max_level, current_percent * 100, shop_cost]
		shop_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shop_info.clip_text = true
		shop_info.custom_minimum_size.x = 80
		shop_row.add_child(shop_info)
		
		var shop_btn_box = VBoxContainer.new()
		shop_btn_box.custom_minimum_size = Vector2(70, 0)
		shop_btn_box.add_theme_constant_override("separation", 3)
		
		var shop_btn_single = Button.new()
		shop_btn_single.text = "升级"
		shop_btn_single.custom_minimum_size = Vector2(70, 24)
		shop_btn_single.add_theme_font_size_override("font_size", 12)
		shop_btn_single.pressed.connect(on_shop_skill_upgrade.bind(i, "single"))
		shop_btn_box.add_child(shop_btn_single)
		
		var shop_btn_bulk = Button.new()
		shop_btn_bulk.text = "一键升级"
		shop_btn_bulk.custom_minimum_size = Vector2(70, 24)
		shop_btn_bulk.add_theme_font_size_override("font_size", 12)
		shop_btn_bulk.pressed.connect(on_shop_skill_upgrade.bind(i, "bulk"))
		shop_btn_box.add_child(shop_btn_bulk)
		
		shop_row.add_child(shop_btn_box)
		list.add_child(shop_row)

func on_hero_level_upgrade():
	var batch = false
	if c.has_node("HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck"):
		batch = c.get_node("HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck").button_pressed
	
	var upgraded = data.upgrade_hero_level(current_hero_id, batch)
	if upgraded > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func on_hero_breakthrough():
	if data.breakthrough_hero(current_hero_id):
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func _on_hero_beast_btn_clicked(beast_id: String, beast_idx: int):
	var panel = c._create_base_popup("珍兽操作", Vector2(360, 240), Vector2(396, 200))
	panel.name = "BeastActionPanel"
	
	var vbox = panel.get_child(0)
	
	var replace_btn = Button.new()
	replace_btn.text = "替换珍兽"
	replace_btn.pressed.connect(func():
		c._safe_close("BeastActionPanel")
		_show_beast_selector_for_hero()
	)
	vbox.add_child(replace_btn)
	
	var detail_btn = Button.new()
	detail_btn.text = "培养珍兽"
	detail_btn.pressed.connect(func():
		c._safe_close("BeastActionPanel")
		c.open_beast_detail(beast_id, beast_idx)
	)
	vbox.add_child(detail_btn)
	
	var unequip_btn = Button.new()
	unequip_btn.text = "卸下珍兽"
	unequip_btn.pressed.connect(func():
		data.unequip_beast(current_hero_id)
		c._safe_close("BeastActionPanel")
		update_hero_panel()
		c.update_all_ui()
	)
	vbox.add_child(unequip_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(func(): c._safe_close("BeastActionPanel"))
	vbox.add_child(cancel_btn)
	
	c.add_child(panel)

func _show_beast_selector_for_hero():
	if current_hero_id == "": return
	
	var panel = c._create_base_popup("选择珍兽装备", Vector2(460, 400), Vector2(346, 120))
	panel.name = "BeastSelectForHero"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	var has_beast = false
	for beast_id in data.beasts.keys():
		var cfg = data.get_beast_config(beast_id)
		var count = data.get_beast_instance_count(beast_id)
		for i in range(count):
			var instance = data.get_beast_instance(beast_id, i)
			if instance == null: continue
			var btn = Button.new()
			var apt = data.get_beast_aptitude(beast_id, i)
			var bonus = data.get_beast_skill_bonus(beast_id, i) + data.get_beast_aura_bonus(beast_id, i)
			
			var equipped_hero = instance.get("equipped_hero", "")
			var status = ""
			if equipped_hero == current_hero_id:
				status = " [当前装备]"
				btn.disabled = true
			elif equipped_hero != "" and data.heroes.has(equipped_hero):
				status = " [%s已装备]" % data.heroes[equipped_hero].name
			
			btn.text = "【%s】Lv.%d 资质+%d 加成+%.0f%%%s" % [cfg.name, instance.level, apt, bonus * 100, status]
			
			if not btn.disabled:
				btn.pressed.connect(_on_equip_beast_to_hero.bind(beast_id, i))
			list.add_child(btn)
			has_beast = true
	
	if not has_beast:
		var empty = Label.new()
		empty.text = "暂无可装备珍兽"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("BeastSelectForHero"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

func _on_equip_beast_to_hero(beast_id: String, index: int):
	data.equip_beast(current_hero_id, beast_id, index)
	c._safe_close("BeastSelectForHero")
	update_hero_panel()
	c.update_all_ui()

func _on_hero_unequip_beast():
	data.unequip_beast(current_hero_id)
	update_hero_panel()
	c.update_all_ui()

func on_aptitude_skill_upgrade(skill_index: int, mode: String = "single"):
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var hero = data.heroes[current_hero_id]
	var skill = hero.aptitude_skills[skill_index]
	
	# 已满级
	if skill.level >= skill.max_level:
		return
	
	var pill_count = data.items.get("aptitude_pill", 0)
	if pill_count <= 0:
		return
	
	var levels_to_upgrade: int
	if mode == "single":
		levels_to_upgrade = 1
	else:  # bulk 一键升满
		var remaining = skill.max_level - skill.level
		levels_to_upgrade = min(pill_count, remaining)
	
	if levels_to_upgrade > 0:
		data.items.aptitude_pill -= levels_to_upgrade
		skill.level += levels_to_upgrade
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func on_shop_skill_upgrade(skill_index: int, mode: String = "single"):
	if data.upgrade_hero_shop_skill(current_hero_id, skill_index, mode):
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func on_promotion_upgrade(mode: String = "single"):
	var upgraded = data.upgrade_promotion(current_hero_id, mode == "bulk")
	if upgraded > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func open_hero_detail(hero_id: String):
	open_hero_panel(hero_id)

func update_hero_list():
	if not c.has_node("PageContainer/HeroPage/HeroScroll/HeroGrid"): return
	var grid = c.get_node("PageContainer/HeroPage/HeroScroll/HeroGrid")
	
	for cell in grid.get_children():
		if not cell is Button: continue
		
		var hero_id = cell.name.replace("_hero_locked", "").replace("_hero", "")
		
		var name_lbl = cell.find_child("NameLabel", true, false)
		var income_lbl = cell.find_child("IncomeLabel", true, false)
		var status_lbl = cell.find_child("StatusLabel", true, false)
		
		var h = null
		var income = 0
		var status = ""
		
		if data.heroes.has(hero_id):
			h = data.heroes[hero_id]
			income = data.get_hero_income(hero_id)
			status = "闲置"
			if h.assigned_shop != "" and data.shops.has(h.assigned_shop):
				status = "在【" + data.shops[h.assigned_shop].name + "】"
			cell.modulate = Color.WHITE
		elif not data.heroes.has(hero_id) and data.get_hero_config(hero_id) != null:
			h = data.get_hero_config(hero_id)
			var vip_level = data.get_hero_unlock_vip(hero_id)
			status = "VIP%d解锁" % vip_level
			cell.modulate = Color(0.5, 0.5, 0.5, 0.7)
		else:
			continue
		
		if name_lbl:
			name_lbl.text = "【%s】Lv.%d | %s" % [h.name, h.level, h.category]
		if income_lbl:
			income_lbl.text = "%s/秒" % c.format_number(income)
		if status_lbl:
			status_lbl.text = status
	
	_sort_hero_grid(grid)   # 【新增】每次刷新后按实时赚速重排卡片顺序

# 【新增】门客网格按赚速降序重排：已解锁按实时赚速从高到低，未解锁VIP门客保持原相对顺序排在最后
# 赚速会随升级/今日新菜等变化，所以在 update_hero_list 每次刷新时调用，保证顺序始终最新
func _sort_hero_grid(grid):
	var unlocked = []   # 已解锁：[cell, 实时赚速]
	var locked = []     # 未解锁VIP门客：保持原相对顺序
	for cell in grid.get_children():
		if not cell is Button: continue
		# 与 update_hero_list 相同的 id 解析方式：去掉 _hero_locked / _hero 后缀
		var hero_id = cell.name.replace("_hero_locked", "").replace("_hero", "")
		if data.heroes.has(hero_id):
			unlocked.append([cell, data.get_hero_income(hero_id)])
		else:
			locked.append(cell)
	unlocked.sort_custom(func(a, b): return a[1] > b[1])   # 赚速降序
	# 用 move_child 原位重排：先排已解锁，未解锁依次排到末尾（不销毁重建，保留卡片信号连接）
	var idx = 0
	for pair in unlocked:
		grid.move_child(pair[0], idx)
		idx += 1
	for cell in locked:
		grid.move_child(cell, idx)
		idx += 1

# 【新增】获取指定门客的全部缘分挚友id（friends.json 中 bound_heroes 数组包含该门客的挚友）
func _get_fate_friends(hero_id: String) -> Array:
	var result = []
	for fid in data.get_all_friend_ids():
		var cfg = data.get_friend_config(fid)
		if cfg.get("bound_heroes", []).has(hero_id):
			result.append(fid)
	return result

# 【新增】缘分按钮点击：弹窗列出该门客全部缘分挚友
# 已拥有=金色（带友好度）；未拥有=灰色默认色，附获取途径（VIP解锁 / 游历好感进度 / 仅显示未拥有）
func _on_fate_btn_clicked(hero_id: String):
	var fate_ids = _get_fate_friends(hero_id)
	if fate_ids.is_empty():
		c._show_stage_hint("该门客没有缘分挚友")
		return
	var popup = c._create_base_popup("缘分挚友", Vector2(420, 400), Vector2(366, 120))
	popup.name = "FatePopup"
	var vb = popup.get_child(0)
	# 列表可滚动，挚友多时不超窗
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for fid in fate_ids:
		var cfg = data.get_friend_config(fid)
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if data.friends.has(fid):
			# 已拥有：金色 + 当前友好度
			lbl.text = "【%s】已拥有（友好%d）" % [cfg.get("name", fid), data.friends[fid].friendly]
			lbl.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			# 未拥有：按获取途径显示提示（VIP解锁 > 游历好感 > 仅标未拥有）
			var vip_lv = data.get_friend_unlock_vip(fid)
			if vip_lv > 0:
				lbl.text = "【%s】未拥有（VIP%d解锁）" % [cfg.get("name", fid), vip_lv]
			elif data.TRAVEL_AFFECTION.has(fid):
				lbl.text = "【%s】未拥有（游历好感%d/%d）" % [cfg.get("name", fid), data.friend_affection.get(fid, 0), data.TRAVEL_AFFECTION[fid]]
			else:
				lbl.text = "【%s】未拥有" % cfg.get("name", fid)
		list.add_child(lbl)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)
