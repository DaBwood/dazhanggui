extends Control

var data: GameData 
var current_hero_id: String = ""
var current_friend_id: String = ""

#页面切换
var current_page: String = "shop"   # shop / hero / bag

#按钮信号连接
var _signals_connected: bool = false

# 当前正在查看哪个普通店铺
var current_shop_id: String = ""
# 人参待使用数量
var _pending_ginseng_count: int = 0

# ========== 记录当前打开的弹窗面板 ==========
var _current_popup: Control = null

func _ready():
	randomize()
	data = GameData.new() 
	data.load_game()  # ← 先读档
	
	# 计算离线收益
	var offline_income = data.calculate_offline_income()
	if offline_income > 0:
		data.money += offline_income
		print("离线收益: +", offline_income, "铜钱")
	
	# 记录本次登录时间，并保存（这样闪退时知道"上次在线时间"）
	@warning_ignore("narrowing_conversion")
	data.last_login_time = Time.get_unix_time_from_system()
	
	#先保存一下，防止闪退
	data.save_game()
	
	#应用风格
	apply_theme()
	#连接信号
	connect_signals()
	#初始化店铺列表
	generate_shop_list()
	#初始化门客列表
	generate_hero_list()
	#初始化背包
	generate_bag_list()
	#初始化府邸
	generate_mansion_list()
	#默认主页面府邸
	switch_page("mansion")
	#更新UI
	update_all_ui()
	
	print("信号连接完成")  # ← 加这行
	
	# 正常退出时存档
	tree_exiting.connect(on_exit)

#格式化函数
func format_number(n: int) -> String:
	if n < 10000:
		return str(n)
	
	var units = ["", "万", "亿", "万亿", "亿亿"]
	var idx = 0
	var val = float(n)
	while val >= 10000 and idx < units.size() - 1:
		val /= 10000.0
		idx += 1
	
	var s = "%.2f" % val
	s = s.rstrip("0").rstrip(".")
	return s + units[idx]

# ========== 信号连接 ==========
func connect_signals():
	
	if _signals_connected:
		return
	_signals_connected = true
	
	# 钱庄入口
	if has_node("PageContainer/ShopPage/HQEntryBtn"): $PageContainer/ShopPage/HQEntryBtn.pressed.connect(open_hq_panel)
	
	# 钱庄面板内
	if has_node("HQPanel/VBoxContainer/HBoxContainer/HQClickBtn"): $HQPanel/VBoxContainer/HBoxContainer/HQClickBtn.pressed.connect(on_hq_click)
	if has_node("HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn"): $HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn.pressed.connect(on_hq_upgrade)
	if has_node("HQPanel/CloseBtn"): $HQPanel/CloseBtn.pressed.connect(close_hq_panel)
	
	# 通用店铺面板内
	if has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn"): $ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn.pressed.connect(on_current_shop_upgrade)
	if has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn"): $ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn.pressed.connect(on_current_shop_hire)
	if has_node("ShopPanel/ShopCloseBtn"): $ShopPanel/ShopCloseBtn.pressed.connect(close_shop_panel)
	
	# 底部导航
	if has_node("BottomNav/NavMansionBtn"): $BottomNav/NavMansionBtn.pressed.connect(switch_page.bind("mansion"))
	if has_node("BottomNav/NavShopBtn"): $BottomNav/NavShopBtn.pressed.connect(switch_page.bind("shop"))
	if has_node("BottomNav/NavHeroBtn"): $BottomNav/NavHeroBtn.pressed.connect(switch_page.bind("hero"))
	if has_node("BottomNav/NavBagBtn"): $BottomNav/NavBagBtn.pressed.connect(switch_page.bind("bag"))
	
	# 门客面板内
	if has_node("HeroPanel/HeroCloseBtn"): $HeroPanel/HeroCloseBtn.pressed.connect(close_hero_panel)
	#计时器
	if has_node("Timer"): $Timer.timeout.connect(on_auto_earn)
	
	# 挚友面板内
	if has_node("FriendPanel/FriendDetailView/HBoxContainer/GiftBtn"): 
		$FriendPanel/FriendDetailView/HBoxContainer/GiftBtn.pressed.connect(on_gift_friend)
	if has_node("FriendPanel/CloseBtn"): 
		$FriendPanel/CloseBtn.pressed.connect(_on_close_or_back_btn)
	# 谈心按钮
	var chat_btn = $FriendPanel/ChatOpBox.find_child("ChatBtn", true, false)
	if chat_btn != null and not chat_btn.pressed.is_connected(on_chat_with_friend):
		chat_btn.pressed.connect(on_chat_with_friend)
	
	
#底部导航栏页面切换
func switch_page(page_id: String):
	_close_ginseng_selector()  # 切换页面时关闭人参选择器
	current_page = page_id
	
	# 隐藏所有页面（加 mansion）
	if has_node("PageContainer/MansionPage"): $PageContainer/MansionPage.visible = false
	if has_node("PageContainer/ShopPage"): $PageContainer/ShopPage.visible = false
	if has_node("PageContainer/HeroPage"): $PageContainer/HeroPage.visible = false
	if has_node("PageContainer/BagPage"): $PageContainer/BagPage.visible = false

	# 显示目标页面
	var page_path = "PageContainer/" + page_id.capitalize() + "Page"
	if has_node(page_path): get_node(page_path).visible = true

	
	#进入门客页面时更新门客列表
	if page_id == "hero":update_hero_list()
	#进入背包页面时更新背包列表
	if page_id == "bag":update_bag_list()
	# 进入府邸时更新
	if page_id == "mansion":update_mansion_list()
	# 高亮当前导航按钮（可选）
	style_nav_buttons()


# ========== 动态生成店铺列表 ==========
func generate_shop_list():
	if not has_node("PageContainer/ShopPage/ShopList"): return
	
	# 先清空（防止重复）
	for child in $PageContainer/ShopPage/ShopList.get_children():
		child.queue_free()
	
	# 为每个普通店铺创建一个入口按钮
	for shop_id in data.shops.keys():
		var btn = Button.new()
		btn.name = shop_id + "_entry"
		btn.custom_minimum_size = Vector2(500, 60)  # 按钮最小尺寸
		btn.pressed.connect(open_shop_panel.bind(shop_id))
		$PageContainer/ShopPage/ShopList.add_child(btn)



# ========== 统一弹窗管理 ==========
func open_popup(panel: Control):
	_current_popup = panel
	panel.show()
	$Overlay.show()

func close_popup():
	if _current_popup != null:
		_current_popup.hide()
		_current_popup = null
	$Overlay.hide()


# ========== 全局输入检测：点击弹窗外部关闭 ==========
func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				# 礼物选择器打开时，点击其内部不触发 close_popup
			if has_node("FriendPanel/GiftSelector"):
				var gift_rect = get_node("FriendPanel/GiftSelector").get_global_rect()
				if gift_rect.has_point(get_global_mouse_position()):
					return
			# 如果有弹窗打开
			if _current_popup != null and _current_popup.visible:
				
				# 获取弹窗的全局矩形区域
				var popup_rect = _current_popup.get_global_rect()
				# 如果鼠标点击在弹窗区域之外
				if not popup_rect.has_point(get_global_mouse_position()):
					close_popup()
					# 阻止事件继续传给下面的按钮
					get_viewport().set_input_as_handled()
			# 新增：AssignSelector 外部点击关闭
			if has_node("AssignSelector"):
				var selector_rect = get_node("AssignSelector").get_global_rect()
				if not selector_rect.has_point(get_global_mouse_position()):
					_close_assign_selector()
					get_viewport().set_input_as_handled()
			#挚友礼物选择器
			if has_node("FriendPanel/GiftSelector"):
				var gift_rect = get_node("FriendPanel/GiftSelector").get_global_rect()
				if not gift_rect.has_point(get_global_mouse_position()):
					get_node("FriendPanel/GiftSelector").queue_free()
					get_viewport().set_input_as_handled()

#动态生成门客列表
func generate_hero_list():
	
	if not has_node("PageContainer/HeroPage"): return
	var list = $PageContainer/HeroPage/HeroScroll/HeroList
	
	# 清空旧按钮
	for child in list.get_children():
		if child is Button:
			child.queue_free()
	
	# 为每个门客生成入口按钮
	for hero_id in data.heroes.keys():
		var btn = Button.new()
		btn.name = hero_id + "_hero"
		btn.custom_minimum_size = Vector2(600, 70)
		btn.pressed.connect(open_hero_detail.bind(hero_id))
		list.add_child(btn)
		

#打开门客详情页
func open_hero_panel(hero_id: String):
	current_hero_id = hero_id
	if has_node("HeroPanel"):
		open_popup($HeroPanel)
		update_hero_panel()

#关闭门客详情页
func close_hero_panel():
	close_popup()
	current_hero_id = ""
	update_hero_list()

func update_hero_panel():
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var h = data.heroes[current_hero_id]
	var income = data.get_hero_income(current_hero_id)
	var total_aptitude = HeroData.get_total_aptitude(h)
	var quality_tag = ""
	if h.has("quality") and h.quality > 0:
		quality_tag = "[%s]" % HeroData.get_quality_name(h.quality)
	
	if has_node("HeroPanel/HeroName"):
		$HeroPanel/HeroName.text = "【%s】%s %s Lv.%d" % [h.name, h.category, quality_tag, h.level]
	if has_node("HeroPanel/HeroIncome"):
		$HeroPanel/HeroIncome.text = "赚速：%s/秒  资质：%d" % [format_number(income), total_aptitude]
	
	
	var level_box = $HeroPanel.get_node("LevelUpBox")
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
	
	if not has_node("HeroPanel/ScrollContainer/SkillList"): return
	var list = $HeroPanel/ScrollContainer/SkillList
	
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

#门客等级升级
func on_hero_level_upgrade():
	var batch = false
	if has_node("HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck"):
		batch = $HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck.button_pressed
	
	var upgraded = data.upgrade_hero_level(current_hero_id, batch)
	if upgraded > 0:
		update_hero_panel()
		update_all_ui()
		update_bag_list()

#门客突破
func on_hero_breakthrough():
	if data.breakthrough_hero(current_hero_id):
		update_hero_panel()
		update_all_ui()
		update_bag_list()

#门客资质技能升级
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
		update_all_ui()
		update_bag_list()

func on_shop_skill_upgrade(skill_index: int, mode: String = "single"):
	if data.upgrade_hero_shop_skill(current_hero_id, skill_index, mode):
		update_hero_panel()
		update_all_ui()
		update_bag_list()

func on_promotion_upgrade(mode: String = "single"):
	var upgraded = data.upgrade_promotion(current_hero_id, mode == "bulk")
	if upgraded > 0:
		update_hero_panel()
		update_all_ui()
		update_bag_list()

func open_hero_detail(hero_id: String):
	open_hero_panel(hero_id)

# ========== 门客派遣 ==========
func _show_hero_assign_selector(slot: int):
	if current_shop_id == "": return
	close_popup()  # 先关闭店铺面板，防止遮挡
	_current_popup = null  # 清空弹窗记录，避免全局点击误关
	
	var overlay = $Overlay
	overlay.show()
	
	var selector = PanelContainer.new()
	selector.name = "AssignSelector"
	selector.custom_minimum_size = Vector2(500, 400)
	selector.position = Vector2(326, 150)
	selector.z_index = 20
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	selector.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择门客派遣到【%s】" % data.shops[current_shop_id].name
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
		btn.text = "【%s】%s Lv.%d | %s/秒" % [h.name, h.category, h.level, format_number(income)]
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
	
	add_child(selector)
	

func _on_assign_overlay_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		_close_assign_selector()

func _close_assign_selector():
	if has_node("AssignSelector"):
		get_node("AssignSelector").queue_free()
	$Overlay.hide()
	# 重新打开店铺面板
	if current_shop_id != "":
		open_popup($ShopPanel)
		update_shop_panel()

func _on_hero_assigned(hero_id: String, _slot: int):
	data.heroes[hero_id].assigned_shop = current_shop_id
	_close_assign_selector()
	update_shop_panel()
	update_all_ui()
	update_hero_list()

func _on_hero_unassign(hero_id: String):
	data.heroes[hero_id].assigned_shop = ""
	update_shop_panel()
	update_all_ui()
	update_hero_list()

#更新门客列表
func update_hero_list():
	if not has_node("PageContainer/HeroPage"): return
	
	var list = $PageContainer/HeroPage/HeroScroll/HeroList
	
	for btn in list.get_children():
		if not btn is Button: continue
		var hero_id = btn.name.replace("_hero", "")
		if not data.heroes.has(hero_id): continue
		
		var h = data.heroes[hero_id]
		var income = data.get_hero_income(hero_id)
		var status = "闲置"
		if h.assigned_shop != "" and data.shops.has(h.assigned_shop):
			status = "在【" + data.shops[h.assigned_shop].name + "】"
		
		btn.text = "【%s】Lv.%d | %s | %s/秒 | %s" % [h.name, h.level, h.category, format_number(income), status]
		


# ========== 面板开关 ==========
func open_hq_panel():
	if has_node("HQPanel"):
		open_popup($HQPanel)
		update_hq_panel()

func close_hq_panel():
	close_popup()
	update_hero_list()

func open_shop_panel(shop_id: String):
	current_shop_id = shop_id
	if has_node("ShopPanel"):
		open_popup($ShopPanel)
		update_shop_panel()

func close_shop_panel():
	close_popup()
	current_shop_id = ""



# ========== 交互 ==========
func on_hq_click():
	data.money += data.hq.click_income
	update_all_ui()
	animate_button("HQPanel/HQClickBtn")

#实时铜钱
func on_auto_earn():
	data.money += data.get_total_auto_income()
	update_all_ui()

#钱庄升级
func on_hq_upgrade():
	if data.upgrade_hq():
		update_all_ui()
		update_bag_list()
	else:
		flash_red("HQPanel/HQUpgradeBtn")

#店铺升级
func on_current_shop_upgrade():
	if data.upgrade_shop(current_shop_id):
		update_all_ui()
		update_bag_list()
	else:
		flash_red("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn")

#店员招募
func on_current_shop_hire():
	if data.hire_staff(current_shop_id):
		update_all_ui()
	else:
		flash_red("ShopPanel/VBoxContainer/HBoxContainerl/ShopHireBtn")

# ========== 初始化背包 ==========
func generate_bag_list():
	if not has_node("PageContainer/BagPage"): return
	var bag_page = $PageContainer/BagPage
	
	# 自动创建 GridContainer（如果没有）
	var grid: GridContainer
	if bag_page.has_node("BagGrid"):
		grid = bag_page.get_node("BagGrid")
	else:
		grid = GridContainer.new()
		grid.name = "BagGrid"
		grid.columns = 4
		grid.custom_minimum_size = Vector2(1100, 500)
		bag_page.add_child(grid)
	
	# 清空旧格子
	for child in grid.get_children():
		child.queue_free()
	
	# 为每种物品生成格子
	for item_id in data.ITEM_CONFIG.keys():
		var cfg = data.ITEM_CONFIG[item_id]
		var count = data.items.get(item_id, 0)
		
		var cell = PanelContainer.new()
		cell.name = item_id + "_cell"
		cell.custom_minimum_size = Vector2(250, 120)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(vbox)
		
		var name_lbl = Label.new()
		name_lbl.text = cfg.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_lbl)
		
		var count_lbl = Label.new()
		count_lbl.name = "CountLabel"
		count_lbl.text = "x%d" % count
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(count_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = cfg.desc
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(desc_lbl)
		
		# 可使用道具添加按钮
		if item_id == "exp_box":
			var use_btn = Button.new()
			use_btn.text = "打开"
			use_btn.custom_minimum_size = Vector2(60, 28)
			use_btn.add_theme_font_size_override("font_size", 12)
			use_btn.pressed.connect(func(): _show_quantity_selector("exp_box", "打开阅历箱", _on_exp_box_confirmed))
			vbox.add_child(use_btn)
		elif item_id == "ginseng":
			var use_btn = Button.new()
			use_btn.text = "使用"
			use_btn.custom_minimum_size = Vector2(60, 28)
			use_btn.add_theme_font_size_override("font_size", 12)
			use_btn.pressed.connect(func(): _show_quantity_selector("ginseng", "使用百年人参", _on_ginseng_confirmed))
			vbox.add_child(use_btn)

		
		grid.add_child(cell)

#更新背包
func update_bag_list():
	if not has_node("PageContainer/BagPage/BagGrid"): return
	var grid = $PageContainer/BagPage/BagGrid
	for cell in grid.get_children():
		var item_id = cell.name.replace("_cell", "")
		var count_lbl = cell.find_child("CountLabel", true, false)
		if count_lbl:
			count_lbl.text = "x%d" % data.items.get(item_id, 0)

# ========== 通用数量选择器 ==========
func _show_quantity_selector(item_id: String, title_text: String, on_confirm: Callable):
	var bag_page = $PageContainer/BagPage
	_close_quantity_selector()
	
	var max_count = data.items.get(item_id, 0)
	if max_count <= 0: return
	
	var panel = PanelContainer.new()
	panel.name = "QuantitySelector"
	panel.custom_minimum_size = Vector2(420, 260)
	panel.position = Vector2(366, 200)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var own_label = Label.new()
	own_label.text = "拥有：%d" % max_count
	own_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(own_label)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)
	
	var slider = HSlider.new()
	slider.name = "QtySlider"
	slider.min_value = 1
	slider.max_value = max_count
	slider.value = 1
	slider.custom_minimum_size = Vector2(180, 30)
	hbox.add_child(slider)
	
	var spin = SpinBox.new()
	spin.name = "QtySpin"
	spin.min_value = 1
	spin.max_value = max_count
	spin.value = 1
	hbox.add_child(spin)
	
	# 滑动条与输入框双向同步
	slider.value_changed.connect(spin.set_value)
	spin.value_changed.connect(slider.set_value)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_box)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "确认"
	confirm_btn.custom_minimum_size = Vector2(70, 32)
	confirm_btn.pressed.connect(on_confirm.bind(spin))
	btn_box.add_child(confirm_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(70, 32)
	cancel_btn.pressed.connect(_close_quantity_selector)
	btn_box.add_child(cancel_btn)
	
	bag_page.add_child(panel)

func _close_quantity_selector():
	var bag_page = $PageContainer/BagPage
	if bag_page.has_node("QuantitySelector"):
		bag_page.get_node("QuantitySelector").queue_free()

func _on_exp_box_confirmed(spin: SpinBox):
	var count = int(spin.value)
	if data.items.get("exp_box", 0) < count:
		_close_quantity_selector()
		return
	data.items.exp_box -= count
	data.items.experience += 99999 * count
	_close_quantity_selector()
	update_bag_list()
	update_all_ui()

func _on_ginseng_confirmed(spin: SpinBox):
	var count = int(spin.value)
	if data.items.get("ginseng", 0) < count:
		_close_quantity_selector()
		return
	_pending_ginseng_count = count
	_close_quantity_selector()
	_show_ginseng_selector()

# ========== 背包道具使用 ==========
func _show_ginseng_selector():
	var bag_page = $PageContainer/BagPage
	if bag_page.has_node("GinsengSelector"): return
	
	var panel = PanelContainer.new()
	panel.name = "GinsengSelector"
	panel.custom_minimum_size = Vector2(500, 400)
	panel.position = Vector2(326, 150)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择门客使用百年人参"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	for hero_id in data.heroes.keys():
		var h = data.heroes[hero_id]
		var btn = Button.new()
		btn.text = "【%s】%s Lv.%d" % [h.name, h.category, h.level]
		btn.pressed.connect(_on_ginseng_target_selected.bind(hero_id))
		list.add_child(btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_close_ginseng_selector)
	vbox.add_child(cancel_btn)
	
	bag_page.add_child(panel)

func _on_ginseng_target_selected(hero_id: String):
	var count = _pending_ginseng_count
	if data.items.get("ginseng", 0) < count:
		_close_ginseng_selector()
		return
	data.items.ginseng -= count
	data.heroes[hero_id].base_income += 2000 * count
	_close_ginseng_selector()
	update_bag_list()
	update_all_ui()

func _close_ginseng_selector():
	var bag_page = $PageContainer/BagPage
	if bag_page.has_node("GinsengSelector"):
		bag_page.get_node("GinsengSelector").queue_free()
	_pending_ginseng_count = 0


# ========== UI 更新 ==========
func update_all_ui():
	update_money_label()
	update_entry_buttons()
	
	# 如果面板打开，实时更新面板内容
	if has_node("HQPanel") and $HQPanel.visible:
		update_hq_panel()
	if has_node("ShopPanel") and $ShopPanel.visible and current_shop_id != "":
		update_shop_panel()

func update_money_label():
	var text = "🥈 %s  |   🥇：%s |  赚速：%s/秒" % [
		format_number(data.money),
		format_number(data.yuanbao),
		format_number(data.get_total_auto_income())
	]
	if has_node("TopBar/Label"):
		$TopBar/Label.text = text
	elif has_node("Label"):
		$Label.text = text

func update_entry_buttons():
	# 钱庄入口
	if has_node("PageContainer/ShopPage/HQEntryBtn"):
		var income = data.get_hq_auto_income()
		$PageContainer/ShopPage/HQEntryBtn.text = "【钱庄】Lv.%d  |  挂机 %d/秒  |  点击 +%d" % [data.hq.level, income, data.hq.click_income]
	
	# 普通店铺入口（动态生成的按钮）
	if not has_node("PageContainer/ShopPage/ShopList"): return
	for btn in $PageContainer/ShopPage/ShopList.get_children():
		var shop_id = btn.name.replace("_entry", "")
		if data.shops.has(shop_id):
			var s = data.shops[shop_id]
			var income = data.get_shop_auto_income(shop_id)
			btn.text = "【%s】Lv.%d  |  赚速 %s/秒  |  店员 %d人" % [s.name, s.level, format_number(income), s.staff]

func update_hq_panel():
	if has_node("HQPanel/VBoxContainer/HQName"):
		$HQPanel/VBoxContainer/HQName.text = "【%s】Lv.%d" % [data.hq.name, data.hq.level]
	if has_node("HQPanel/VBoxContainer/HQInfo"):
		var auto = data.get_hq_auto_income()
		var bonus = data.get_global_bonus_percent() * 100
		$HQPanel/VBoxContainer/HQInfo.text = "挂机 %s/秒  |  点击 +%s  |  全局加成 +%d%%" % [format_number(auto), format_number(data.hq.click_income), bonus]
	if has_node("HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn"):
		$HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn.text = "🔨 升级（%d图纸）" % data.hq.upgrade_cost

func update_shop_panel():
	if current_shop_id == "": return
	var s = data.shops[current_shop_id]
	var cost = s.hire_cost
	
	if has_node("ShopPanel/VBoxContainer/ShopName"):
		$ShopPanel/VBoxContainer/ShopName.text = "【%s】Lv.%d" % [s.name, s.level]
	if has_node("ShopPanel/VBoxContainer/ShopInfo"):
		var income = data.get_shop_auto_income(current_shop_id)
		$ShopPanel/VBoxContainer/ShopInfo.text = "赚速 %s/秒  |  店员 %d人" % [format_number(income), s.staff]
	if has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn"):
		$ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn.text = "🔨 升级（%d道具）" % s.upgrade_cost
	if has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn"):
		$ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn.text = "👤 招募（%d铜钱）" % cost
	
	
	# 更新槽位内容
	var assign_box = $ShopPanel/VBoxContainer/AssignContainer
	
	# 收集当前店铺已派遣的门客
	var assigned_heroes: Array = []
	for hero_id in data.heroes.keys():
		if data.heroes[hero_id].assigned_shop == current_shop_id:
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
			label.text = "【%s】%s | %s/秒" % [h.name, h.category, format_number(data.get_hero_income(assigned_id))]
			btn.text = "撤下"
			btn.disabled = false
			btn.pressed.connect(_on_hero_unassign.bind(assigned_id))
		else:
			label.text = "【派遣位%d】空闲" % (slot + 1)
			btn.text = "派遣"
			btn.disabled = false
			btn.pressed.connect(_show_hero_assign_selector.bind(slot))

#初始化府邸页面
func generate_mansion_list():
	if not has_node("PageContainer/MansionPage"): return
	var page = $PageContainer/MansionPage
	
	# 自动创建 GridContainer
	var grid: GridContainer
	if page.has_node("MansionGrid"):
		grid = page.get_node("MansionGrid")
	else:
		grid = GridContainer.new()
		grid.name = "MansionGrid"
		grid.columns = 3
		grid.custom_minimum_size = Vector2(1100, 500)
		page.add_child(grid)
	
	# 清空
	for child in grid.get_children():
		child.queue_free()
	
	var modules = [
		{"name": "挚友", "func": "on_friend"},
		{"name": "商城", "func": "on_mall"},
		{"name": "每日任务", "func": "on_daily_task"},
		{"name": "VIP", "func": "on_vip"},
		{"name": "充值豪礼", "func": "on_recharge"},
	]
	
	for m in modules:
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(300, 120)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(vbox)
		
		var name_lbl = Label.new()
		name_lbl.text = m.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_lbl)
		
		var btn = Button.new()
		btn.text = "进入"
		btn.custom_minimum_size = Vector2(80, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(Callable(self, m.func))
		vbox.add_child(btn)
		
		grid.add_child(cell)

#更新府邸页面
func update_mansion_list():
	# 目前无动态数据，预留
	pass

# 5 个预留函数
func on_mall(): print("商城系统预留")
func on_daily_task(): print("每日任务预留")
func on_vip(): print("VIP系统预留")
func on_recharge(): print("充值豪礼预留")

#挚友函数
func on_friend():
	if has_node("FriendPanel"):
		open_popup($FriendPanel)
		_show_friend_list()

# ========== 挚友列表 ↔ 详情 切换 ==========

func _show_friend_list():
	current_friend_id = ""
	if has_node("FriendPanel/FriendDetailView"):
		$FriendPanel/FriendDetailView.visible = false
	if has_node("FriendPanel/FriendListView"):
		var lv = $FriendPanel/FriendListView
		lv.visible = true
		_update_friend_list()
	_update_chat_btn()
	if has_node("FriendPanel/ChatOpBox"):$FriendPanel/ChatOpBox.visible = true

func _on_close_or_back_btn():
	if current_friend_id != "":
		# 在详情页 → 返回列表
		_show_friend_list()
	else:
		# 在列表页 → 关闭面板
		close_popup()
		#print("没有current_friend")


func _update_chat_btn():
	if not has_node("FriendPanel/ChatOpBox"): return
	var chat_btn = $FriendPanel/ChatOpBox.find_child("ChatBtn", true, false)
	if chat_btn != null:
		chat_btn.text = "谈心（%d/100）" % data.energy




func _update_friend_list():
	var list_view = $FriendPanel/FriendListView
	var list = list_view.find_child("VBoxContainer", true, false)
	
	
	# 确保 VBoxContainer 能垂直扩展，按钮才会往下排
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# 清空旧按钮
	for child in list.get_children():
		child.queue_free()
	
	for fid in data.friends.keys():
		var f = data.friends[fid]
		var btn = Button.new()
		btn.text = "【%s】友好：%d | 才华：%d | 缘分：%s" % [f.name, f.friendly, f.talent, format_number(f.bond)]
		btn.custom_minimum_size = Vector2(0, 50)   # 宽度交给孩子自己扩展
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_friend_selected.bind(fid))
		list.add_child(btn)
	
	

func _on_friend_selected(friend_id: String):
	current_friend_id = friend_id
	if has_node("FriendPanel/FriendListView"):
		$FriendPanel/FriendListView.visible = false
	if has_node("FriendPanel/FriendDetailView"):
		var dv = $FriendPanel/FriendDetailView
		dv.visible = true
	update_friend_panel()
	if has_node("FriendPanel/ChatOpBox"):$FriendPanel/ChatOpBox.visible = false



func update_friend_panel():
	
	if has_node("FriendPanel/FriendDetailView"):
		$FriendPanel/FriendDetailView.custom_minimum_size.x = 560
	
	if not has_node("FriendPanel"): return
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	var f = data.friends[fid]
	
	if has_node("FriendPanel/FriendDetailView/FriendName"):
		var lbl = $FriendPanel/FriendDetailView/FriendName
		lbl.text = "【%s】" % f.name
	
	if has_node("FriendPanel/FriendDetailView/FriendAttr"):
		var lbl = $FriendPanel/FriendDetailView/FriendAttr
		lbl.text = "友好：%d  |  才华：%d" % [f.friendly, f.talent]
	
	if has_node("FriendPanel/FriendDetailView/ShopSkills"):
		var skills = data.get_friend_shop_skills(fid)
		var txt = "店铺技能："
		for sk in skills:
			txt += "%s+5%% " % sk.category
		if skills.size() == 0: txt += "无"
		var lbl = $FriendPanel/FriendDetailView/ShopSkills
		lbl.text = txt
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	if has_node("FriendPanel/FriendDetailView/FriendBond"):
		var lbl = $FriendPanel/FriendDetailView/FriendBond
		lbl.text = "缘分：%s" % format_number(f.bond)
	
	if has_node("FriendPanel/FriendDetailView/BoundHeroes"):
		var lbl = $FriendPanel/FriendDetailView/BoundHeroes
		var names = []
		for hid in f.bound_heroes:
			if data.heroes.has(hid):
				names.append(data.heroes[hid].name)
		lbl.text = "绑定门客：" + "、".join(names)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
	# ========== 更新预创建的技能行 ==========
	var detail = $FriendPanel/FriendDetailView
	
	# --- 天生丽质（固定加成）---
	var fixed_name = detail.find_child("FixedSkillName", true, false)
	var fixed_info = detail.find_child("FixedSkillInfo", true, false)
	var fixed_btn = detail.find_child("FixedSkillBtn", true, false)

	
	if fixed_name: fixed_name.text = "天生丽质"
	if fixed_info:
		var bonus = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
		fixed_info.text = str(bonus)
	if fixed_btn:
		var cost = (f.fixed_skill_level + 1) * 100
		fixed_btn.text = "升级（%d/%s）" % [cost, format_number(f.bond)]
		for conn in fixed_btn.pressed.get_connections():
			fixed_btn.pressed.disconnect(conn.callable)
		fixed_btn.pressed.connect(_on_friend_skill_upgrade.bind(true))
	
	# --- 花开富贵（百分比加成）---
	var percent_name = detail.find_child("PercentSkillName", true, false)
	var percent_info = detail.find_child("PercentSkillInfo", true, false)
	var percent_btn = detail.find_child("PercentSkillBtn", true, false)
	
	if percent_name: percent_name.text = "花开富贵"
	if percent_info:
		var percent = f.percent_skill_level * 5
		percent_info.text = "%d%%" % percent
	if percent_btn:
		var cost = (f.percent_skill_level + 1) * 100
		percent_btn.text = "升级（%d/%s）" % [cost, format_number(f.bond)]
		for conn in percent_btn.pressed.get_connections():
			percent_btn.pressed.disconnect(conn.callable)
		percent_btn.pressed.connect(_on_friend_skill_upgrade.bind(false))

#挚友谈心
func on_chat_with_friend():
	
	# 精力不足时优先提示使用精力丹
	if data.energy <= 0:
		if data.items.get("energy_pill", 0) > 0:
			_show_energy_pill_prompt()
		else:
			if has_node("FriendPanel/ChatOpBox"):
				flash_red("FriendPanel/ChatOpBox/ChatBtn")
		return
	
	var batch = false
	var chat_op = $FriendPanel/ChatOpBox
	if chat_op != null:
		var batch_check = chat_op.find_child("BatchChatCheck", true, false)
		if batch_check != null:
			batch = batch_check.button_pressed
	
	var result = data.chat_with_friend(not batch)
	if result.ok:
		if current_friend_id != "" and has_node("FriendPanel/FriendDetailView") and $FriendPanel/FriendDetailView.visible:
			update_friend_panel()
		_show_chat_result(result.results)
		update_all_ui()
		_update_friend_list()
		_update_chat_btn()
	else:
		if has_node("FriendPanel/ChatOpBox"):
			flash_red("FriendPanel/ChatOpBox")

func _show_energy_pill_prompt():
	if has_node("EnergyPillPrompt"): return
	
	var max_pills = data.items.get("energy_pill", 0)
	if max_pills <= 0: return
	
	# 计算最多能吃几个
	var max_count = max_pills
	
	var panel = PanelContainer.new()
	panel.name = "EnergyPillPrompt"
	panel.custom_minimum_size = Vector2(420, 280)
	panel.position = Vector2(366, 184)
	panel.z_index = 30
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "精力不足"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "拥有精力丹：%d" % max_pills
	vbox.add_child(info)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)
	
	var slider = HSlider.new()
	slider.name = "PillSlider"
	slider.min_value = 1
	slider.max_value = max_count
	slider.value = 1
	slider.custom_minimum_size = Vector2(180, 30)
	hbox.add_child(slider)
	
	var spin = SpinBox.new()
	spin.name = "PillSpin"
	spin.min_value = 1
	spin.max_value = max_count
	spin.value = 1
	hbox.add_child(spin)
	
	# 双向同步
	slider.value_changed.connect(spin.set_value)
	spin.value_changed.connect(slider.set_value)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	var use_btn = Button.new()
	use_btn.text = "使用"
	use_btn.custom_minimum_size = Vector2(80, 36)
	use_btn.pressed.connect(_on_use_energy_pill.bind(spin))
	btn_box.add_child(use_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 36)
	cancel_btn.pressed.connect(func(): if has_node("EnergyPillPrompt"): get_node("EnergyPillPrompt").queue_free())
	btn_box.add_child(cancel_btn)
	
	add_child(panel)

func _on_use_energy_pill(spin: SpinBox = null):
	var count = 1
	if spin != null:
		count = int(spin.value)
	
	var max_pills = data.items.get("energy_pill", 0)
	count = clamp(count, 1, max_pills)
	
	if max_pills <= 0:
		if has_node("EnergyPillPrompt"): get_node("EnergyPillPrompt").queue_free()
		return
	
	data.items.energy_pill -= count
	data.energy += 3 * count
	
	if has_node("EnergyPillPrompt"): get_node("EnergyPillPrompt").queue_free()
	_update_chat_btn()
	update_bag_list()
	# 吃完自动继续谈心
	on_chat_with_friend()


func _show_chat_result(results: Array):
	if has_node("ChatResultPanel"): return
	
	var panel = PanelContainer.new()
	panel.name = "ChatResultPanel"
	panel.custom_minimum_size = Vector2(400, 300)
	panel.position = Vector2(376, 174)
	panel.z_index = 30
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "谈心结果"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 200)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	for r in results:
		var lbl = Label.new()
		lbl.text = "与【%s】谈心，缘分 +%d" % [r.name, r.gain]
		list.add_child(lbl)
	
	if results.size() > 1:
		var total = 0
		for r in results: total += r.gain
		var sum_lbl = Label.new()
		sum_lbl.text = "总计谈心 %d 次，缘分 +%d" % [results.size(), total]
		sum_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sum_lbl)
	
	var ok_btn = Button.new()
	ok_btn.text = "确定"
	ok_btn.pressed.connect(func(): if has_node("ChatResultPanel"): get_node("ChatResultPanel").queue_free())
	vbox.add_child(ok_btn)
	
	add_child(panel)


func _on_friend_skill_upgrade(is_fixed: bool):
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	
	var btn_name = "FixedSkillBtn" if is_fixed else "PercentSkillBtn"
	var detail = $FriendPanel/FriendDetailView
	var check_name = "FixedSkillChek" if is_fixed else "PercentSkillChek"
	var check = detail.find_child(check_name, true, false)
	var batch = false
	if check != null:
		batch = check.button_pressed
	
	var upgraded = 0
	if is_fixed:
		upgraded = _upgrade_friend_fixed_batch(fid, batch)
	else:
		upgraded = _upgrade_friend_percent_batch(fid, batch)
	
	if upgraded > 0:
		update_friend_panel()
		update_all_ui()
	else:
		var btn = detail.find_child(btn_name, true, false)
		if btn != null:
			flash_red(btn.get_path())

func _upgrade_friend_fixed_batch(friend_id: String, batch: bool) -> int:
	if not data.friends.has(friend_id): return 0
	var f = data.friends[friend_id]
	var count = 0
	var max_times = 10 if batch else 1
	for i in range(max_times):
		var cost = (f.fixed_skill_level + 1) * 100
		if f.bond < cost:
			break
		f.bond -= cost
		f.fixed_skill_level += 1
		count += 1
	return count

func _upgrade_friend_percent_batch(friend_id: String, batch: bool) -> int:
	if not data.friends.has(friend_id): return 0
	var f = data.friends[friend_id]
	var count = 0
	var max_times = 10 if batch else 1
	for i in range(max_times):
		var cost = (f.percent_skill_level + 1) * 100
		if f.bond < cost:
			break
		f.bond -= cost
		f.percent_skill_level += 1
		count += 1
	return count


#挚友赠礼
func on_gift_friend():
	if current_friend_id == "": return
	_show_gift_selector()

#打开赠礼选择器
func _show_gift_selector():
	if has_node("FriendPanel/GiftSelector"): return
	
	var panel = PanelContainer.new()
	panel.name = "GiftSelector"
	panel.custom_minimum_size = Vector2(420, 260)   # 调小，确保在面板内
	panel.position = Vector2(40, 60)
	panel.z_index = 30   # 原来是 20，改大确保盖在最上
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")   # 深色背景，不透
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择礼物"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var gifts = [
		{"id": "wood_comb", "name": "木梳", "effect": "友好+1"},
		{"id": "rouge", "name": "胭脂", "effect": "才华+1"},
	]
	for g in gifts:
		var count = data.items.get(g.id, 0)
		
		# 每行：信息 + 滑块 + 输入框 + 确认
		var row = VBoxContainer.new()
		row.name = "GiftRow_" + g.id
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)
		
		var info = Label.new()
		info.text = "%s（%s）  拥有：%s" % [g.name, g.effect, format_number(count)]
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(info)
		
		var hbox = HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 8)
		row.add_child(hbox)
		
		var slider = HSlider.new()
		slider.min_value = 0
		slider.max_value = count
		slider.value = 0
		slider.custom_minimum_size = Vector2(140, 30)
		hbox.add_child(slider)
		
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = count
		spin.value = 0
		hbox.add_child(spin)
		
		slider.value_changed.connect(spin.set_value)
		spin.value_changed.connect(slider.set_value)
		
		var confirm_btn = Button.new()
		confirm_btn.text = "赠送"
		confirm_btn.custom_minimum_size = Vector2(70, 32)
		confirm_btn.pressed.connect(_on_gift_item_confirmed.bind(spin, g.id))
		hbox.add_child(confirm_btn)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_close_gift_selector)
	vbox.add_child(cancel)
	
	$FriendPanel.add_child(panel)

func _close_gift_selector():
	if has_node("FriendPanel/GiftSelector"):
		get_node("FriendPanel/GiftSelector").queue_free()

func _on_gift_item_confirmed(spin: SpinBox, item_id: String):
	var count = int(spin.value)
	if count <= 0: return
	if current_friend_id == "": return
	if data.items.get(item_id, 0) < count:
		return
	
	for i in range(count):
		if not data.gift_friend(current_friend_id, item_id):
			break
	
	# 刷新弹窗内数量，不关闭弹窗
	_refresh_gift_selector()
	
	update_friend_panel()
	update_bag_list()
	update_all_ui()

func _refresh_gift_selector():
	if not has_node("FriendPanel/GiftSelector"): return
	var gifts = [
		{"id": "wood_comb", "name": "木梳", "effect": "友好+1"},
		{"id": "rouge", "name": "胭脂", "effect": "才华+1"},
	]
	for g in gifts:
		var row = $FriendPanel/GiftSelector.find_child("GiftRow_" + g.id, true, false)
		if row == null: continue
		var count = data.items.get(g.id, 0)
		
		var info = row.get_child(0)
		if info is Label:
			info.text = "%s（%s）  拥有：%s" % [g.name, g.effect, format_number(count)]
		
		var hbox = row.get_child(1)
		if hbox is HBoxContainer and hbox.get_child_count() >= 3:
			var slider = hbox.get_child(0)
			var spin = hbox.get_child(1)
			if slider is Slider:
				slider.max_value = count
				if slider.value > count:
					slider.value = count
			if spin is SpinBox:
				spin.max_value = count
				if spin.value > count:
					spin.value = count



# ========== 美化 ==========
func apply_theme():
	if has_node("Background"):
		$Background.color = Color("#2d2a2e")
	
	# 遍历所有按钮统一美化
	for btn in find_children("*", "Button"):
		if btn.name == "CloseBtn":
			continue
		style_button(btn)
	
	# 遍历所有 Label 统一字体
	for lbl in find_children("*", "Label"):
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color("#f2e9e4"))
	# 底部导航按钮铺满
	if has_node("BottomNav"):
		for btn in $BottomNav.get_children():
			if btn is Button:
				btn.custom_minimum_size = Vector2(288, 60)  # 1152/3 = 384

#按钮美化
func style_nav_buttons():
	if not has_node("BottomNav"): return
	for btn in $BottomNav.get_children():
		if btn is Button:
			if  (current_page == "mansion" and btn.name == "NavMansionBtn") or \
				(current_page == "shop" and btn.name == "NavShopBtn") or \
				(current_page == "hero" and btn.name == "NavHeroBtn") or \
				(current_page == "bag" and btn.name == "NavBagBtn"):
				btn.modulate = Color("#e0c070")  # 高亮
			else:
				btn.modulate = Color("#c9a959")  # 普通

func style_button(btn: Button):
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color("#c9a959")
	for i in 4:
		normal.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color("#e0c070")
	for i in 4:
		hover.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color("#a08030")
	for i in 4:
		pressed.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_color_override("font_color", Color("#2d2a2e"))
	btn.add_theme_font_size_override("font_size", 16)

# ========== 动画 ==========
func animate_button(node_path: String):
	if not has_node(node_path): return
	var btn = get_node(node_path)
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.05)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.05)

func flash_red(node_path: String):
	if not has_node(node_path): return
	var btn = get_node(node_path)
	
	# 防止重复调用导致样式错乱
	if btn.has_meta("flashing"):
		return
	
	var original = btn.get_theme_stylebox("normal")
	if original == null:return
	btn.set_meta("flashing", true)
	
	var red = StyleBoxFlat.new()
	red.bg_color = Color("#ff4444")
	for i in 4:
		red.set_corner_radius(i, 8)
	
	btn.add_theme_stylebox_override("normal", red)
	var tween = create_tween()
	tween.tween_interval(0.2)
	tween.tween_callback(func():
		btn.add_theme_stylebox_override("normal", original)
		btn.remove_meta("flashing")
	)



func on_exit():
	# 正常退出：记录下线时间，然后存档
	@warning_ignore("narrowing_conversion")
	data.last_logout_time = Time.get_unix_time_from_system()
	data.save_game()
