extends Control

var data: GameData 
var current_hero_id: String = ""
var current_friend_id: String = ""
var _selected_shop_skill_index: int = -1
var _current_beast_id: String = ""
var _current_beast_index: int = 0
var _selected_beast_skill_index: int = -1
#页面切换
var current_page: String = "shop"   # shop / hero / bag

#按钮信号连接
var _signals_connected: bool = false

# 当前正在查看哪个普通店铺
var current_shop_id: String = ""
# 人参待使用数量
var _pending_ginseng_count: int = 0
var _pending_ginseng_type: String = ""

# ========== 记录当前打开的弹窗面板 ==========
var _current_popup: Control = null

func _ready():
	#打印场景树
	#print_tree_pretty()
	
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
	
	# 初始化左上角头像+名字
	_init_avatar_box()
	
	# 【新增】铜钱旁加号按钮
	if has_node("TopBar") and not $TopBar.has_node("MoneyPlusBtn"):
		var plus_btn = Button.new()
		plus_btn.name = "MoneyPlusBtn"
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(28, 28)
		plus_btn.add_theme_font_size_override("font_size", 16)
		plus_btn.pressed.connect(on_money_plus_clicked)
		$TopBar.add_child(plus_btn)
		if $TopBar is Container and $TopBar.has_node("Label"):
			$TopBar.move_child(plus_btn, $TopBar.get_node("Label").get_index() + 1)
	
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
	#初始化关卡页面
	generate_stage_page()
	#初始化珍兽页面
	generate_beast_page()
	#初始化闯荡页面
	generate_adventure_page()
	
	generate_friend_page()
	
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
	if has_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck"):
		$ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck.toggled.connect(_on_batch_hire_toggled)
	
	# 底部导航
	if has_node("BottomNav/NavMansionBtn"): $BottomNav/NavMansionBtn.pressed.connect(switch_page.bind("mansion"))
	if has_node("BottomNav/NavShopBtn"): $BottomNav/NavShopBtn.pressed.connect(switch_page.bind("shop"))
	if has_node("BottomNav/NavHeroBtn"): $BottomNav/NavHeroBtn.pressed.connect(switch_page.bind("hero"))
	if has_node("BottomNav/NavBagBtn"): $BottomNav/NavBagBtn.pressed.connect(switch_page.bind("bag"))
	if has_node("BottomNav/NavAdventureBtn"): $BottomNav/NavAdventureBtn.pressed.connect(switch_page.bind("adventure"))
	
	# 门客面板内
	if has_node("HeroPanel/HeroCloseBtn"): $HeroPanel/HeroCloseBtn.pressed.connect(close_hero_panel)
	#计时器
	if has_node("Timer"): $Timer.timeout.connect(on_auto_earn)
	
	
	#充值面板
	if has_node("RechargePage/RechargeContainer/CloseBtn"): $RechargePage/RechargeContainer/CloseBtn.pressed.connect(close_popup)
	if has_node("RechargePage/RechargeContainer/TabBar/TapYuanbao"):$RechargePage/RechargeContainer/TabBar/TapYuanbao.pressed.connect(_on_tab_normal_pressed)
	if has_node("RechargePage/RechargeContainer/TabBar/TapDaily"):$RechargePage/RechargeContainer/TabBar/TapDaily.pressed.connect(_on_tab_daily_pressed)
	if has_node("RechargePage/RechargeContainer/TabBar/TapSpecial"):
		$RechargePage/RechargeContainer/TabBar/TapSpecial.pressed.connect(_on_tab_special_pressed)
	
	#vip面板
	if has_node("VIPPanel/VBoxContainer/CloseBtn"): $VIPPanel/VBoxContainer/CloseBtn.pressed.connect(close_popup)
	
	
	
#底部导航栏页面切换
func switch_page(page_id: String):
	_close_ginseng_selector()  # 切换页面时关闭人参选择器
	current_page = page_id
	
	# 隐藏所有页面（加 mansion）
	if has_node("PageContainer/MansionPage"): $PageContainer/MansionPage.visible = false
	if has_node("PageContainer/ShopPage"): $PageContainer/ShopPage.visible = false
	if has_node("PageContainer/HeroPage"): $PageContainer/HeroPage.visible = false
	if has_node("PageContainer/BagPage"): $PageContainer/BagPage.visible = false
	if has_node("PageContainer/StagePage"): $PageContainer/StagePage.visible = false
	if has_node("PageContainer/BeastPage"): $PageContainer/BeastPage.visible = false
	if has_node("PageContainer/AdventurePage"): $PageContainer/AdventurePage.visible = false
	if has_node("PageContainer/FriendPage"): $PageContainer/FriendPage.visible = false

	# 显示目标页面
	var page_path = "PageContainer/" + page_id.capitalize() + "Page"
	if has_node(page_path): get_node(page_path).visible = true

	
	#进入门客页面时更新门客列表
	if page_id == "hero":update_hero_list()
	#进入背包页面时更新背包列表
	if page_id == "bag":update_bag_list()
	# 进入府邸时更新
	if page_id == "mansion":update_mansion_list()
	#进入关卡页面更新
	if page_id == "stage": update_stage_page()
	if page_id == "adventure": 
		hide_exchange_view()
		hide_lottery_view()
		update_adventure_page()
	
	if page_id == "beast": update_beast_page()
	
	if page_id == "friend": update_friend_page()
	# 高亮当前导航按钮（可选）
	style_nav_buttons()

func generate_friend_page():
	if not has_node("PageContainer"): return
	var page = $PageContainer/FriendPage if has_node("PageContainer/FriendPage") else null
	if page == null:
		page = Panel.new()
		page.name = "FriendPage"
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		$PageContainer.add_child(page)
	
	for child in page.get_children():
		child.queue_free()
	
	# --- 列表视图容器 ---
	var list_view = VBoxContainer.new()
	list_view.name = "ListView"
	list_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(list_view)
	
	# --- 滚动容器 ---
	var scroll = ScrollContainer.new()
	scroll.name = "FriendScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_view.add_child(scroll)
	
	# --- 网格列表 ---
	var grid = GridContainer.new()
	grid.name = "FriendGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	
	# --- 谈心操作区（放到列表页底部）---
	var chat_op = HBoxContainer.new()
	chat_op.name = "ChatOpBox"
	chat_op.alignment = BoxContainer.ALIGNMENT_CENTER
	chat_op.add_theme_constant_override("separation", 12)
	list_view.add_child(chat_op)
	
	var chat_btn = Button.new()
	chat_btn.name = "ChatBtn"
	chat_btn.text = "谈心"
	chat_btn.pressed.connect(on_chat_with_friend)
	chat_op.add_child(chat_btn)
	
	var batch_check = CheckBox.new()
	batch_check.name = "BatchChatCheck"
	batch_check.text = "一键"
	chat_op.add_child(batch_check)
	
	# --- 详情视图 ---
	var detail = VBoxContainer.new()
	detail.name = "FriendDetail"
	detail.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail.visible = false
	detail.add_theme_constant_override("separation", 12)
	page.add_child(detail)
	
	var back_btn = Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "< 返回挚友列表"
	back_btn.pressed.connect(hide_friend_detail)
	detail.add_child(back_btn)
	
	var name_lbl = Label.new()
	name_lbl.name = "FriendName"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	detail.add_child(name_lbl)
	
	# 绑定门客放最上
	var bound_lbl = Label.new()
	bound_lbl.name = "BoundHeroes"
	bound_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bound_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(bound_lbl)
	
	# 才华/友好/缘分/赠礼 放一起
	var attr_box = HBoxContainer.new()
	attr_box.name = "AttrBox"
	attr_box.alignment = BoxContainer.ALIGNMENT_CENTER
	attr_box.add_theme_constant_override("separation", 12)
	detail.add_child(attr_box)
	
	var attr_lbl = Label.new()
	attr_lbl.name = "FriendAttr"
	attr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attr_box.add_child(attr_lbl)
	
	var bond_lbl = Label.new()
	bond_lbl.name = "FriendBond"
	bond_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attr_box.add_child(bond_lbl)
	
	var gift_btn = Button.new()
	gift_btn.name = "GiftBtn"
	gift_btn.text = "赠礼"
	gift_btn.pressed.connect(on_gift_friend)
	attr_box.add_child(gift_btn)
	
	# 技能区（天生丽质/花开富贵）
	var skill_list = VBoxContainer.new()
	skill_list.name = "FriendSkillList"
	skill_list.add_theme_constant_override("separation", 8)
	detail.add_child(skill_list)
	# 天生丽质行
	var fixed_box = HBoxContainer.new()
	fixed_box.name = "FixedSkillBox"
	fixed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var fixed_name = Label.new(); fixed_name.name = "FixedSkillName"; fixed_box.add_child(fixed_name)
	var fixed_info = Label.new(); fixed_info.name = "FixedSkillInfo"; fixed_box.add_child(fixed_info)
	var fixed_btn = Button.new(); fixed_btn.name = "FixedSkillBtn"; fixed_box.add_child(fixed_btn)
	var fixed_check = CheckBox.new(); fixed_check.name = "FixedSkillChek"; fixed_box.add_child(fixed_check)
	fixed_check.text = "十连" 
	skill_list.add_child(fixed_box)
	# 花开富贵行
	var percent_box = HBoxContainer.new()
	percent_box.name = "PercentSkillBox"
	percent_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var percent_name = Label.new(); percent_name.name = "PercentSkillName"; percent_box.add_child(percent_name)
	var percent_info = Label.new(); percent_info.name = "PercentSkillInfo"; percent_box.add_child(percent_info)
	var percent_btn = Button.new(); percent_btn.name = "PercentSkillBtn"; percent_box.add_child(percent_btn)
	var percent_check = CheckBox.new(); percent_check.name = "PercentSkillChek"; percent_box.add_child(percent_check)
	percent_check.text = "十连" 
	skill_list.add_child(percent_box)
	
	# 店铺技能标题
	var shop_title = Label.new()
	shop_title.name = "ShopSkillsTitle"
	shop_title.text = "店铺技能"
	shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_title.add_theme_font_size_override("font_size", 18)
	shop_title.add_theme_color_override("font_color", Color("#ffd700"))
	detail.add_child(shop_title)
	
	# 店铺技能列表（可刷新，400槽位）
	var shop_scroll = ScrollContainer.new()
	shop_scroll.name = "ShopSkillsScroll"
	shop_scroll.custom_minimum_size = Vector2(0, 200)
	detail.add_child(shop_scroll)
	
	var shop_list = GridContainer.new()
	shop_list.name = "ShopSkillsList"
	shop_list.columns = 5
	shop_list.add_theme_constant_override("h_separation", 12)
	shop_list.add_theme_constant_override("v_separation", 8)
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_scroll.add_child(shop_list)
	
	for i in range(400):
		var btn = Button.new()
		btn.name = "ShopSkillBtn_%d" % i
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_shop_skill_clicked.bind(i))
		shop_list.add_child(btn)

# ========== 动态生成店铺列表 ==========
func generate_shop_list():
	if not has_node("PageContainer/ShopPage/ShopScroll/ShopList"): return
	
	var list = $PageContainer/ShopPage/ShopScroll/ShopList
	
	for child in list.get_children():
		child.queue_free()
	
	list.columns = 2
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 8)
	
	for shop_id in data.SHOP_ORDER:
		var btn = Button.new()
		btn.name = shop_id + "_entry"
		btn.custom_minimum_size = Vector2(0, 60)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(on_shop_entry_pressed.bind(shop_id))
		list.add_child(btn)

func update_friend_page():
	if not has_node("PageContainer/FriendPage/ListView/FriendScroll/FriendGrid"): return
	var grid = $PageContainer/FriendPage/ListView/FriendScroll/FriendGrid
	for child in grid.get_children():
		child.queue_free()
	
	# 已解锁
	for fid in data.friends.keys():
		var f = data.friends[fid]
		var cell = _create_friend_card(f.name, f.friendly, f.talent, false)
		cell.pressed.connect(show_friend_detail.bind(fid))
		grid.add_child(cell)
	
	# 未解锁
	for fid in data.get_all_friend_ids():
		if data.friends.has(fid): continue
		var cfg = data.get_friend_config(fid)
		var cell = _create_friend_card(cfg.get("name", "未知"), 0, 0, true)
		var vip_lv = data.get_friend_unlock_vip(fid)
		cell.pressed.connect(_on_locked_friend_clicked.bind(fid, vip_lv))
		grid.add_child(cell)

func _create_friend_card(cname: String, friendly: int, talent: int, locked: bool) -> Button:
	var cell = Button.new()
	cell.custom_minimum_size = Vector2(200, 240)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = "【%s】" % cname
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lbl)
	
	if not locked:
		var attr_lbl = Label.new()
		attr_lbl.text = "友好：%d  |  才华：%d" % [friendly, talent]
		attr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		attr_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(attr_lbl)
	else:
		var lock_lbl = Label.new()
		lock_lbl.text = "未解锁"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_color_override("font_color", Color("#888888"))
		lock_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(lock_lbl)
		cell.modulate = Color(0.5, 0.5, 0.5, 0.7)
	
	return cell

func show_friend_detail(friend_id: String):
	current_friend_id = friend_id
	if not has_node("PageContainer/FriendPage"): return
	var page = $PageContainer/FriendPage
	page.get_node("ListView").visible = false
	page.get_node("FriendDetail").visible = true
	_update_friend_page_detail()

func hide_friend_detail():
	current_friend_id = ""
	if not has_node("PageContainer/FriendPage"): return
	var page = $PageContainer/FriendPage
	page.get_node("ListView").visible = true
	page.get_node("FriendDetail").visible = false

func _update_friend_page_detail():
	if not has_node("PageContainer/FriendPage/FriendDetail"): return
	var detail = $PageContainer/FriendPage/FriendDetail
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	var f = data.friends[fid]
	if not f.has("shop_skills"):
		data._init_friend_shop_skills(fid)
	detail.get_node("FriendName").text = "【%s】" % f.name
	
	# 绑定门客
	var names = []
	for hid in f.bound_heroes:
		if data.heroes.has(hid):
			names.append(data.heroes[hid].name)
	detail.get_node("BoundHeroes").text = "绑定门客：" + "、".join(names)
	
	# 才华/友好/缘分/赠礼（放一起）
	var attr_box = detail.get_node("AttrBox")
	attr_box.get_node("FriendAttr").text = "友好：%d  |  才华：%d" % [f.friendly, f.talent]
	attr_box.get_node("FriendBond").text = "缘分：%s" % format_number(f.bond)
	
	# 天生丽质
	var fixed_name = detail.find_child("FixedSkillName", true, false)
	var fixed_info = detail.find_child("FixedSkillInfo", true, false)
	var fixed_btn = detail.find_child("FixedSkillBtn", true, false)
	if fixed_name: fixed_name.text = "天生丽质"
	if fixed_info:
		var bonus = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
		fixed_info.text = "缘分门客赚钱+%s" % format_number(bonus)
	if fixed_btn:
		var cost = (f.fixed_skill_level + 1) * 100
		fixed_btn.text = "升级（%d/%s）" % [cost, format_number(f.bond)]
		for conn in fixed_btn.pressed.get_connections():
			fixed_btn.pressed.disconnect(conn.callable)
		fixed_btn.pressed.connect(_on_friend_skill_upgrade.bind(true))
	
	# 花开富贵
	var percent_name = detail.find_child("PercentSkillName", true, false)
	var percent_info = detail.find_child("PercentSkillInfo", true, false)
	var percent_btn = detail.find_child("PercentSkillBtn", true, false)
	if percent_name: percent_name.text = "花开富贵"
	if percent_info:
		var percent = f.percent_skill_level * 5
		percent_info.text = "缘分门客赚钱+%d%%" % percent
	if percent_btn:
		var cost = (f.percent_skill_level + 1) * 100
		percent_btn.text = "升级（%d/%s）" % [cost, format_number(f.bond)]
		for conn in percent_btn.pressed.get_connections():
			percent_btn.pressed.disconnect(conn.callable)
		percent_btn.pressed.connect(_on_friend_skill_upgrade.bind(false))
	
	# 更新店铺技能列表
	var max_slots = min(400, int(f.friendly / 500))
	var shop_list = detail.get_node("ShopSkillsScroll/ShopSkillsList")
	for i in range(400):
		var btn = shop_list.get_node("ShopSkillBtn_%d" % i)
		if i < max_slots and i < f.shop_skills.size():
			btn.visible = true
			var skill = f.shop_skills[i]
			var bonus_txt = "+%.0f%%" % (skill.bonus * 100)
			if skill.bonus >= 0.299:
				bonus_txt += " [满]"
				btn.disabled = true
			else:
				btn.disabled = false
			btn.text = "%s %s" % [skill.category, bonus_txt]
		else:
			btn.visible = false

func _on_shop_skill_clicked(skill_index: int):
	_selected_shop_skill_index = skill_index
	_show_shop_skill_detail(skill_index)

func _get_category_color(category: String) -> Color:
	var colors = {
		"士": Color("#4a90d9"),
		"农": Color("#5cb85c"),
		"工": Color("#d9534f"),
		"商": Color("#f0ad4e"),
		"侠": Color("#9b59b6")
	}
	return colors.get(category, Color("#888888"))

func _show_shop_skill_detail(skill_index: int):
	var parent = $PageContainer/FriendPage
	if parent.has_node("ShopSkillDetailPanel"): return
	
	var f = data.friends[current_friend_id]
	if not f.has("shop_skills") or skill_index >= f.shop_skills.size(): return
	var skill = f.shop_skills[skill_index]
	
	var panel = PanelContainer.new()
	panel.name = "ShopSkillDetailPanel"
	panel.custom_minimum_size = Vector2(360, 280)
	panel.position = (parent.size - panel.custom_minimum_size) / 2
	panel.z_index = 40
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "【%s类】店铺技能" % skill.category
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	# 图标 + 信息
	var info_box = HBoxContainer.new()
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	info_box.add_theme_constant_override("separation", 16)
	vbox.add_child(info_box)
	
	var icon = ColorRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.color = _get_category_color(skill.category)
	info_box.add_child(icon)
	
	var info_vbox = VBoxContainer.new()
	info_box.add_child(info_vbox)
	
	var bonus_lbl = Label.new()
	bonus_lbl.name = "DetailBonus"
	bonus_lbl.text = "当前加成：+%.0f%%" % (skill.bonus * 100)
	bonus_lbl.add_theme_font_size_override("font_size", 18)
	info_vbox.add_child(bonus_lbl)
	
	var status_lbl = Label.new()
	status_lbl.name = "DetailStatus"
	if skill.bonus >= 0.299:
		status_lbl.text = "已满级"
		status_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	else:
		var cost = 100 * int(pow(2, skill.refresh_count))
		status_lbl.text = "刷新消耗：%s 铜钱" % format_number(cost)
	info_vbox.add_child(status_lbl)
	
	# 按钮区
	if skill.bonus < 0.299:
		var wish_check = CheckBox.new()
		wish_check.name = "WishStoneCheck"
		wish_check.text = "使用许愿石（拥有：%d）" % data.items.get("wish_stone", 0)
		vbox.add_child(wish_check)
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	if skill.bonus < 0.299:
		var refresh_btn = Button.new()
		refresh_btn.name = "DetailRefreshBtn"
		refresh_btn.text = "刷新"
		refresh_btn.custom_minimum_size = Vector2(100, 40)
		refresh_btn.pressed.connect(_on_refresh_selected_skill)
		btn_box.add_child(refresh_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.pressed.connect(_close_shop_skill_detail)
	btn_box.add_child(close_btn)
	
	parent.add_child(panel)

func _close_shop_skill_detail():
	var parent = $PageContainer/FriendPage
	var panel = parent.get_node_or_null("ShopSkillDetailPanel")
	if panel:
		panel.queue_free()

func _on_refresh_selected_skill():
	if _selected_shop_skill_index < 0: return
	var parent = $PageContainer/FriendPage
	var panel = parent.get_node_or_null("ShopSkillDetailPanel")
	var use_wish = false
	if panel:
		var wish_check = panel.find_child("WishStoneCheck", true, false)
		if wish_check:
			use_wish = wish_check.button_pressed
	
	if data.refresh_friend_shop_skill(current_friend_id, _selected_shop_skill_index, use_wish):
		_update_friend_page_detail()
		update_all_ui()
		var f = data.friends[current_friend_id]
		var skill = f.shop_skills[_selected_shop_skill_index]
		if skill.bonus >= 0.299:
			_close_shop_skill_detail()
		else:
			_update_shop_skill_detail()
	else:
		var parent2 = $PageContainer/FriendPage
		var panel2 = parent2.get_node_or_null("ShopSkillDetailPanel")
		if panel2:
			var refresh_btn = panel2.find_child("DetailRefreshBtn", true, false)
			if refresh_btn:
				flash_red(refresh_btn.get_path())

func _update_shop_skill_detail():
	var parent = $PageContainer/FriendPage
	var panel = parent.get_node_or_null("ShopSkillDetailPanel")
	if not panel: return
	
	var f = data.friends[current_friend_id]
	if not f.has("shop_skills") or _selected_shop_skill_index >= f.shop_skills.size(): return
	var skill = f.shop_skills[_selected_shop_skill_index]
	
	# 更新加成文本
	var bonus_lbl = panel.find_child("DetailBonus", true, false)
	if bonus_lbl:
		bonus_lbl.text = "当前加成：+%.0f%%" % (skill.bonus * 100)
	
	# 更新状态文本
	var status_lbl = panel.find_child("DetailStatus", true, false)
	var wish_check = panel.find_child("WishStoneCheck", true, false)
	if status_lbl:
		if skill.bonus >= 0.299:
			status_lbl.text = "已满级"
			status_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			var use_wish = wish_check != null and wish_check.button_pressed
			if use_wish:
				var wish_count = data.items.get("wish_stone", 0)
				status_lbl.text = "许愿石：%d/1" % wish_count
			else:
				var cost = 100 * int(pow(2, skill.refresh_count))
				status_lbl.text = "刷新消耗：%s 铜钱" % format_number(cost)
			status_lbl.remove_theme_color_override("font_color")
	
	# 更新勾选框文字
	if wish_check:
		wish_check.text = "使用许愿石（拥有：%d）" % data.items.get("wish_stone", 0)
		if skill.bonus >= 0.299:
			wish_check.visible = false
	
	# 刷新按钮
	var refresh_btn = panel.find_child("DetailRefreshBtn", true, false)
	if skill.bonus >= 0.299:
		if refresh_btn:
			refresh_btn.queue_free()
		if wish_check:
			wish_check.queue_free()
	else:
		if refresh_btn:
			refresh_btn.text = "刷新"


func generate_adventure_page():
	if not has_node("PageContainer/AdventurePage"): return
	var page = $PageContainer/AdventurePage
	
	for child in page.get_children():
		child.queue_free()
	
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.name = "AdventureVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	page.add_child(vbox)
	
	var title = Label.new()
	title.text = "闯荡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	var stage_btn = Button.new()
	stage_btn.text = "关卡"
	stage_btn.custom_minimum_size = Vector2(240, 60)
	stage_btn.pressed.connect(switch_page.bind("stage"))
	vbox.add_child(stage_btn)
	
	var exchange_btn = Button.new()
	exchange_btn.name = "ExchangeBtn"
	exchange_btn.text = "兑换"
	exchange_btn.custom_minimum_size = Vector2(240, 60)
	exchange_btn.pressed.connect(show_exchange_view)
	vbox.add_child(exchange_btn)
	
	# 兑换子页面（目录：珍兽兑换 / 门客帖兑换）
	var exchange_view = VBoxContainer.new()
	exchange_view.name = "ExchangeView"
	exchange_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	exchange_view.visible = false
	exchange_view.add_theme_constant_override("separation", 12)
	page.add_child(exchange_view)
	
	var back_btn = Button.new()
	back_btn.text = "< 返回"
	back_btn.pressed.connect(_on_exchange_back_pressed)
	exchange_view.add_child(back_btn)
	
	# 入口按钮区
	var entry_box = VBoxContainer.new()
	entry_box.name = "ExchangeEntryBox"
	entry_box.alignment = BoxContainer.ALIGNMENT_CENTER
	entry_box.add_theme_constant_override("separation", 20)
	entry_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	exchange_view.add_child(entry_box)
	
	# 3列网格放所有入口，防止按钮太多溢出
	var entry_grid = GridContainer.new()
	entry_grid.columns = 3
	entry_grid.add_theme_constant_override("h_separation", 16)
	entry_grid.add_theme_constant_override("v_separation", 16)
	entry_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	entry_box.add_child(entry_grid)
	
	var beast_entry_btn = Button.new()
	beast_entry_btn.text = "珍兽兑换"
	beast_entry_btn.custom_minimum_size = Vector2(240, 60)
	beast_entry_btn.pressed.connect(show_beast_exchange_view)
	entry_grid.add_child(beast_entry_btn)
	
	var token_entry_btn = Button.new()
	token_entry_btn.text = "门客帖兑换"
	token_entry_btn.custom_minimum_size = Vector2(240, 60)
	token_entry_btn.pressed.connect(show_token_exchange_view)
	entry_grid.add_child(token_entry_btn)
	
	# 系列兑换入口（配置表驱动，加系列只改 game_data 的表）
	for i in range(data.SERIES_EXCHANGE.size()):
		var s_btn = Button.new()
		s_btn.text = data.SERIES_EXCHANGE[i].series
		s_btn.custom_minimum_size = Vector2(240, 60)
		s_btn.pressed.connect(show_series_exchange_view.bind(i))
		entry_grid.add_child(s_btn)
	
	# --- 珍兽兑换子页面 ---
	var beast_view = VBoxContainer.new()
	beast_view.name = "BeastExchangeView"
	beast_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	beast_view.visible = false
	beast_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	beast_view.add_theme_constant_override("separation", 12)
	exchange_view.add_child(beast_view)
	
	var beast_scroll = ScrollContainer.new()
	beast_scroll.name = "BeastExchangeScroll"
	beast_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	beast_view.add_child(beast_scroll)
	
	var beast_list = VBoxContainer.new()
	beast_list.name = "BeastExchangeList"
	beast_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	beast_scroll.add_child(beast_list)
	
	# --- 门客帖兑换子页面 ---
	var token_view = VBoxContainer.new()
	token_view.name = "TokenExchangeView"
	token_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	token_view.visible = false
	token_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	token_view.add_theme_constant_override("separation", 12)
	exchange_view.add_child(token_view)
	
	var token_res = Label.new()
	token_res.name = "TokenRes"
	token_res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	token_res.add_theme_color_override("font_color", Color("#ffd700"))
	token_view.add_child(token_res)
	
	var token_scroll = ScrollContainer.new()
	token_scroll.name = "TokenExchangeScroll"
	token_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	token_view.add_child(token_scroll)
	
	var token_list = VBoxContainer.new()
	token_list.name = "TokenExchangeList"
	token_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	token_scroll.add_child(token_list)
	
	# --- 系列兑换子页面（所有系列共用） ---
	var series_view = VBoxContainer.new()
	series_view.name = "SeriesExchangeView"
	series_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	series_view.visible = false
	series_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	series_view.add_theme_constant_override("separation", 12)
	exchange_view.add_child(series_view)
	
	var series_title = Label.new()
	series_title.name = "SeriesTitle"
	series_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	series_title.add_theme_font_size_override("font_size", 20)
	series_title.add_theme_color_override("font_color", Color("#ffd700"))
	series_view.add_child(series_title)
	
	var series_scroll = ScrollContainer.new()
	series_scroll.name = "SeriesExchangeScroll"
	series_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	series_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	series_view.add_child(series_scroll)
	
	var series_list = VBoxContainer.new()
	series_list.name = "SeriesExchangeList"
	series_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	series_scroll.add_child(series_list)
	
	# --- 抽奖入口 ---
	var lottery_btn = Button.new()
	lottery_btn.name = "LotteryBtn"
	lottery_btn.text = "抽奖"
	lottery_btn.custom_minimum_size = Vector2(240, 60)
	lottery_btn.pressed.connect(show_lottery_view)
	vbox.add_child(lottery_btn)
	
	# --- 抽奖子页面 ---
	var lottery_view = VBoxContainer.new()
	lottery_view.name = "LotteryView"
	lottery_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	lottery_view.visible = false
	lottery_view.add_theme_constant_override("separation", 16)
	page.add_child(lottery_view)
	
	var lot_back_btn = Button.new()
	lot_back_btn.text = "< 返回闯荡"
	lot_back_btn.pressed.connect(hide_lottery_view)
	lottery_view.add_child(lot_back_btn)
	
	var lot_res = Label.new()
	lot_res.name = "LotteryRes"
	lot_res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lottery_view.add_child(lot_res)
	
	var lot_btn_box = HBoxContainer.new()
	lot_btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lot_btn_box.add_theme_constant_override("separation", 20)
	lottery_view.add_child(lot_btn_box)
	
	var single_btn = Button.new()
	single_btn.name = "LotterySingleBtn"
	single_btn.text = "单抽\n1抽奖券"
	single_btn.custom_minimum_size = Vector2(140, 80)
	single_btn.pressed.connect(on_lottery_draw.bind(1, 1))
	lot_btn_box.add_child(single_btn)
	
	var ten_btn = Button.new()
	ten_btn.name = "LotteryTenBtn"
	ten_btn.text = "十连抽\n9抽奖券"
	ten_btn.custom_minimum_size = Vector2(140, 80)
	ten_btn.pressed.connect(on_lottery_draw.bind(10, 9))
	lot_btn_box.add_child(ten_btn)
	
	var hundred_btn = Button.new()
	hundred_btn.name = "LotteryHundredBtn"
	hundred_btn.text = "百连抽\n90抽奖券"
	hundred_btn.custom_minimum_size = Vector2(140, 80)
	hundred_btn.pressed.connect(on_lottery_draw.bind(100, 90))
	lot_btn_box.add_child(hundred_btn)
	
	var lot_result_scroll = ScrollContainer.new()
	lot_result_scroll.custom_minimum_size = Vector2(0, 200)
	lottery_view.add_child(lot_result_scroll)
	
	var lot_result_list = VBoxContainer.new()
	lot_result_list.name = "LotteryResultList"
	lot_result_scroll.add_child(lot_result_list)

# 兑换页返回键：逐层后退（子页面 → 兑换目录 → 闯荡）
func _on_exchange_back_pressed():
	var ev = $PageContainer/AdventurePage/ExchangeView
	if ev.get_node("SeriesExchangeView").visible:
		hide_series_exchange_view()     # 在系列兑换 → 退回目录
	elif ev.get_node("BeastExchangeView").visible:
		hide_beast_exchange_view()
	elif ev.get_node("TokenExchangeView").visible:
		hide_token_exchange_view()
	else:
		hide_exchange_view()

func show_exchange_view():
	if not has_node("PageContainer/AdventurePage"): return
	var page = $PageContainer/AdventurePage
	page.get_node("AdventureVBox").visible = false
	var ev = page.get_node("ExchangeView")
	ev.visible = true
	# 每次进入都重置回目录层
	if ev.has_node("ExchangeEntryBox"): ev.get_node("ExchangeEntryBox").visible = true
	if ev.has_node("BeastExchangeView"): ev.get_node("BeastExchangeView").visible = false
	if ev.has_node("TokenExchangeView"): ev.get_node("TokenExchangeView").visible = false

func hide_exchange_view():
	if not has_node("PageContainer/AdventurePage"): return
	var page = $PageContainer/AdventurePage
	page.get_node("AdventureVBox").visible = true
	page.get_node("ExchangeView").visible = false
	if page.has_node("LotteryView"):
		page.get_node("LotteryView").visible = false

# ========== 珍兽兑换子页面 ==========
func show_beast_exchange_view():
	var ev = $PageContainer/AdventurePage/ExchangeView
	ev.get_node("ExchangeEntryBox").visible = false
	ev.get_node("TokenExchangeView").visible = false
	ev.get_node("BeastExchangeView").visible = true
	update_beast_exchange_view()

func hide_beast_exchange_view():
	var ev = $PageContainer/AdventurePage/ExchangeView
	ev.get_node("BeastExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

func update_beast_exchange_view():
	if not has_node("PageContainer/AdventurePage/ExchangeView/BeastExchangeView"): return
	var list = $PageContainer/AdventurePage/ExchangeView/BeastExchangeView/BeastExchangeScroll/BeastExchangeList
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

# 珍兽兑换卡片：整张卡就是按钮
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

# ========== 门客帖兑换子页面 ==========
func show_token_exchange_view():
	var ev = $PageContainer/AdventurePage/ExchangeView
	ev.get_node("ExchangeEntryBox").visible = false
	ev.get_node("BeastExchangeView").visible = false
	ev.get_node("TokenExchangeView").visible = true
	update_token_exchange_view()

func hide_token_exchange_view():
	var ev = $PageContainer/AdventurePage/ExchangeView
	ev.get_node("TokenExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

func update_token_exchange_view():
	if not has_node("PageContainer/AdventurePage/ExchangeView/TokenExchangeView"): return
	var view = $PageContainer/AdventurePage/ExchangeView/TokenExchangeView
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

# 一个分区的网格
func _add_role_exchange_grid(list: VBoxContainer, role_type: String, entries: Array):
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(grid)
	
	for entry in entries:
		grid.add_child(_create_role_exchange_card(role_type, entry.id, entry.cost))

# 门客/挚友兑换卡片：整张卡就是按钮
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

# ========== 系列兑换子页面 ==========
var _current_series_index: int = -1

func show_series_exchange_view(series_index: int):
	_current_series_index = series_index
	var ev = $PageContainer/AdventurePage/ExchangeView
	ev.get_node("ExchangeEntryBox").visible = false
	ev.get_node("BeastExchangeView").visible = false
	ev.get_node("TokenExchangeView").visible = false
	ev.get_node("SeriesExchangeView").visible = true
	update_series_exchange_view()

func hide_series_exchange_view():
	_current_series_index = -1
	var ev = $PageContainer/AdventurePage/ExchangeView
	ev.get_node("SeriesExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

func update_series_exchange_view():
	if _current_series_index < 0: return
	var view = $PageContainer/AdventurePage/ExchangeView/SeriesExchangeView
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
			_show_stage_hint("兑换成功！获得门客【%s】和挚友【%s】" % [cfg.name, fcfg.name])
		else:
			_show_stage_hint("兑换成功！获得门客【%s】" % cfg.name)
		update_series_exchange_view()
		update_all_ui()
		update_bag_list()
		generate_hero_list()
		update_friend_page()
	else:
		_show_stage_hint(result.reason)

func _on_exchange_role(role_type: String, role_id: String, cost: int):
	var result = data.exchange_role_with_token(role_type, role_id, cost)
	if result.ok:
		var cfg = data.get_hero_config(role_id) if role_type == "hero" else data.get_friend_config(role_id)
		_show_stage_hint("兑换成功！获得【%s】" % cfg.name)
		update_token_exchange_view()
		update_all_ui()
		update_bag_list()
		if role_type == "hero":
			generate_hero_list()
		update_friend_page()
	else:
		_show_stage_hint(result.reason)


func show_lottery_view():
	if not has_node("PageContainer/AdventurePage"): return
	var page = $PageContainer/AdventurePage
	if page.has_node("AdventureVBox"):
		page.get_node("AdventureVBox").visible = false
	if page.has_node("ExchangeView"):
		page.get_node("ExchangeView").visible = false
	if page.has_node("LotteryView"):
		page.get_node("LotteryView").visible = true
		update_lottery_view()

func hide_lottery_view():
	if not has_node("PageContainer/AdventurePage"): return
	var page = $PageContainer/AdventurePage
	if page.has_node("LotteryView"):
		page.get_node("LotteryView").visible = false
	if page.has_node("AdventureVBox"):
		page.get_node("AdventureVBox").visible = true

func update_lottery_view():
	if not has_node("PageContainer/AdventurePage/LotteryView"): return
	var view = $PageContainer/AdventurePage/LotteryView
	view.get_node("LotteryRes").text = "抽奖券：%d  |  元宝：%s  |  累计：%d/500" % [
		data.lottery_ticket, format_number(data.yuanbao), data.lottery_draw_count
	]
	
	var single = view.find_child("LotterySingleBtn", true, false)
	var ten = view.find_child("LotteryTenBtn", true, false)
	var hundred = view.find_child("LotteryHundredBtn", true, false)
	
	if single:
		single.disabled = data.lottery_ticket < 1 and data.yuanbao < 50
	if ten:
		ten.disabled = data.lottery_ticket < 9 and data.yuanbao < 450
	if hundred:
		hundred.disabled = data.lottery_ticket < 90 and data.yuanbao < 4500

func on_lottery_draw(draw_count: int, ticket_need: int):
	var ticket_have = data.lottery_ticket
	if ticket_have >= ticket_need:
		_do_lottery_draw(draw_count, ticket_need, false)
	else:
		var short = ticket_need - ticket_have
		var need_yuanbao = short * 50
		if data.yuanbao < need_yuanbao:
			_show_stage_hint("抽奖券和元宝均不足！")
			return
		_show_lottery_confirm(draw_count, ticket_need, ticket_have)

func _do_lottery_draw(draw_count: int, ticket_need: int, use_yuanbao: bool):
	var result = data.do_lottery_draw(draw_count, ticket_need, use_yuanbao)
	if result.ok:
		_show_lottery_results(result.results)
		update_all_ui()
		update_bag_list()
		if has_node("PageContainer/AdventurePage/LotteryView"):
			update_lottery_view()
	else:
		_show_stage_hint(result.reason)

func _show_lottery_confirm(draw_count: int, ticket_need: int, ticket_have: int):
	var short = ticket_need - ticket_have
	var need_yuanbao = short * 50
	
	var panel = _create_base_popup("抽奖券不足", Vector2(420, 240), Vector2(366, 204))
	panel.name = "LotteryConfirmPanel"
	
	var vbox = panel.get_child(0)
	var info = Label.new()
	info.text = "抽奖券不足，是否消耗 %d 元宝补足 %d 张抽奖券？\n（拥有元宝：%s）" % [
		need_yuanbao, short, format_number(data.yuanbao)
	]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	var confirm = Button.new()
	confirm.text = "确认"
	confirm.pressed.connect(func():
		_safe_close("LotteryConfirmPanel")
		_do_lottery_draw(draw_count, ticket_need, true)
	)
	btn_box.add_child(confirm)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func():
		_safe_close("LotteryConfirmPanel")
		$Overlay.hide()
		_current_popup = null
	)
	btn_box.add_child(cancel)
	
	add_child(panel)
	_current_popup = panel
	$Overlay.show()

func _show_lottery_results(results: Array):
	if has_node("LotteryResultPanel"): return
	
	var panel = _create_base_popup("抽奖结果", Vector2(480, 520), Vector2(336, 64))
	panel.name = "LotteryResultPanel"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 380)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	
	for r in results:
		var lbl = Label.new()
		var item_name = ""
		if r.get("is_beast", false):
			item_name = data.get_beast_config(r.item).name
		elif r.item == "money":
			item_name = "铜钱"
		else:
			item_name = data.ITEM_CONFIG.get(r.item, {}).get("name", r.item)
		lbl.text = "【%s】x%d" % [item_name, r.count]
		list.add_child(lbl)
	
	_add_ok_button(vbox, func():
		_safe_close("LotteryResultPanel")
		$Overlay.hide()
		_current_popup = null
	)
	
	add_child(panel)
	_current_popup = panel
	$Overlay.show()

func update_adventure_page():
	# 页面静态，无需动态更新
	pass

func on_shop_entry_pressed(shop_id: String):
	if data.shops.has(shop_id):
		open_shop_panel(shop_id)
	elif data.can_unlock_shop(shop_id):
		if data.unlock_shop(shop_id):
			update_all_ui()
			_show_stage_hint("解锁【%s】成功！" % data.get_shop_config(shop_id).name)
			open_shop_panel(shop_id)
	else:
		var need = data.get_shop_unlock_chapter(shop_id)
		_show_stage_hint("【%s】通关第%d章解锁" % [data.get_shop_config(shop_id).name, need])

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
			if has_node("PageContainer/FriendPage/GiftSelector"):
				var gift_rect = get_node("PageContainer/FriendPage/GiftSelector").get_global_rect()
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
			#挚友礼物选择器,点击外部关闭
			if has_node("PageContainer/FriendPage/GiftSelector"):
				var gift_rect = get_node("PageContainer/FriendPage/GiftSelector").get_global_rect()
				if not gift_rect.has_point(get_global_mouse_position()):
					_safe_close("PageContainer/FriendPage/FriendDetail/GiftSelector")
					get_viewport().set_input_as_handled()

#动态生成门客列表
func generate_hero_list():
	if data._hero_configs.is_empty():
		print("警告：门客配置为空，尝试重新加载...")
		data._load_all_configs()
	
	if not has_node("PageContainer/HeroPage"): return
	var scroll = $PageContainer/HeroPage/HeroScroll
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

func _create_beast_card() -> Button:
	var cell = Button.new()
	cell.custom_minimum_size = Vector2(200, 240)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.name = "BeastNameLabel"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_lbl)
	
	var info_lbl = Label.new()
	info_lbl.name = "BeastInfoLabel"
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(info_lbl)
	
	var apt_lbl = Label.new()
	apt_lbl.name = "BeastAptLabel"
	apt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apt_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(apt_lbl)
	
	var bonus_lbl = Label.new()
	bonus_lbl.name = "BeastBonusLabel"
	bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(bonus_lbl)
	
	var hero_lbl = Label.new()
	hero_lbl.name = "BeastHeroLabel"
	hero_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hero_lbl)
	
	return cell

func _on_locked_hero_clicked(hero_id: String):
	var vip_level = data.get_hero_unlock_vip(hero_id)
	var cfg = data.get_hero_config(hero_id)
	var hero_name = cfg.get("name", "未知门客")
	_show_unlock_hint("门客 " + hero_name, vip_level)

func _show_unlock_hint(role_name: String, vip_level: int):
	_safe_close("UnlockHint")
	
	var panel = _create_base_popup("", Vector2(400, 150), Vector2(376, 220))
	panel.name = "UnlockHint"
	
	var vbox = panel.get_child(0)
	var label = Label.new()
	label.text = "【%s】需要 VIP%d 解锁" % [role_name, vip_level]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	_add_ok_button(vbox, func(): panel.queue_free())
	
	add_child(panel)


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
	
	# 清理旧布局（如果有）
	if has_node("HeroPanel/BeastInfoBox"):
		$HeroPanel/BeastInfoBox.queue_free()
	
	# ========== 珍兽装备按钮（放在赚速和技能列表之间）==========
	var beast_id = data.heroes[current_hero_id].get("equipped_beast", "")
	var beast_idx = data.heroes[current_hero_id].get("equipped_beast_index", 0)
	
	var beast_btn = $HeroPanel.get_node_or_null("BeastEquipBtn")
	if beast_btn == null:
		beast_btn = Button.new()
		beast_btn.name = "BeastEquipBtn"
		beast_btn.custom_minimum_size = Vector2(120, 40)
		beast_btn.add_theme_font_size_override("font_size", 14)
		$HeroPanel.add_child(beast_btn)
	
	var income_label = $HeroPanel/HeroIncome
	beast_btn.position = Vector2(income_label.position.x, income_label.position.y + income_label.size.y + 4)
	
	# 把技能列表下移到按钮下方，避免重叠
	if $HeroPanel.has_node("ScrollContainer"):
		var scroll = $HeroPanel/ScrollContainer
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

func _on_hero_beast_btn_clicked(beast_id: String, beast_idx: int):
	var panel = _create_base_popup("珍兽操作", Vector2(360, 240), Vector2(396, 200))
	panel.name = "BeastActionPanel"
	
	var vbox = panel.get_child(0)
	
	var replace_btn = Button.new()
	replace_btn.text = "替换珍兽"
	replace_btn.pressed.connect(func():
		_safe_close("BeastActionPanel")
		_show_beast_selector_for_hero()
	)
	vbox.add_child(replace_btn)
	
	var detail_btn = Button.new()
	detail_btn.text = "培养珍兽"
	detail_btn.pressed.connect(func():
		_safe_close("BeastActionPanel")
		open_beast_detail(beast_id, beast_idx)
	)
	vbox.add_child(detail_btn)
	
	var unequip_btn = Button.new()
	unequip_btn.text = "卸下珍兽"
	unequip_btn.pressed.connect(func():
		data.unequip_beast(current_hero_id)
		_safe_close("BeastActionPanel")
		update_hero_panel()
		update_all_ui()
	)
	vbox.add_child(unequip_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(func(): _safe_close("BeastActionPanel"))
	vbox.add_child(cancel_btn)
	
	add_child(panel)

func _show_beast_selector_for_hero():
	if current_hero_id == "": return
	
	var panel = _create_base_popup("选择珍兽装备", Vector2(460, 400), Vector2(346, 120))
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
	cancel.pressed.connect(func(): _safe_close("BeastSelectForHero"))
	vbox.add_child(cancel)
	
	add_child(panel)

func _on_equip_beast_to_hero(beast_id: String, index: int):
	data.equip_beast(current_hero_id, beast_id, index)
	_safe_close("BeastSelectForHero")
	update_hero_panel()
	update_all_ui()

func _on_hero_unequip_beast():
	data.unequip_beast(current_hero_id)
	update_hero_panel()
	update_all_ui()

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


func _close_assign_selector():
	if has_node("AssignSelector"):
		_safe_close("AssignSelector")
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
	if not has_node("PageContainer/HeroPage/HeroScroll/HeroGrid"): return
	var grid = $PageContainer/HeroPage/HeroScroll/HeroGrid
	
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
			income_lbl.text = "%s/秒" % format_number(income)
		if status_lbl:
			status_lbl.text = status


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
	var batch = false
	if has_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck"):
		batch = $ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck.button_pressed
	
	var count = 10 if batch else 1
	var success = 0
	for i in range(count):
		if data.hire_staff(current_shop_id):
			success += 1
		else:
			break
	
	if success > 0:
		update_all_ui()
	else:
		flash_red("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn")

func _on_batch_hire_toggled(_pressed: bool):
	if current_shop_id != "" and has_node("ShopPanel") and $ShopPanel.visible:
		update_shop_panel()

# ========== 初始化背包 ==========
func generate_bag_list():
	if not has_node("PageContainer/BagPage"): return
	var bag_page = $PageContainer/BagPage
	
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
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
	
	# 清空旧格子
	for child in grid.get_children():
		child.queue_free()
	
	# 为每种物品生成格子
	for item_id in data.ITEM_CONFIG.keys():
		var cfg = data.ITEM_CONFIG[item_id]
		var count = data.items.get(item_id, 0)
		if item_id == "lottery_ticket":
			count = data.lottery_ticket
		
		var cell = PanelContainer.new()
		cell.name = item_id + "_cell"
		cell.custom_minimum_size = Vector2(250, 120)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
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
		elif item_id == "ginseng_1000":
			var use_btn = Button.new()
			use_btn.text = "使用"
			use_btn.custom_minimum_size = Vector2(60, 28)
			use_btn.add_theme_font_size_override("font_size", 12)
			use_btn.pressed.connect(func(): _show_quantity_selector("ginseng_1000", "使用千年人参", _on_ginseng_1000_confirmed))
			vbox.add_child(use_btn)
		elif item_id == "hour_card":
			var use_btn = Button.new()
			use_btn.text = "使用"
			use_btn.custom_minimum_size = Vector2(60, 28)
			use_btn.add_theme_font_size_override("font_size", 12)
			use_btn.pressed.connect(func(): _show_quantity_selector("hour_card", "使用小时卡", _on_hour_card_confirmed))
			vbox.add_child(use_btn)
		elif item_id == "hero_box":
			var use_btn = Button.new()
			use_btn.text = "打开"
			use_btn.custom_minimum_size = Vector2(60, 28)
			use_btn.add_theme_font_size_override("font_size", 12)
			use_btn.pressed.connect(_show_hero_box_selector)
			vbox.add_child(use_btn)

		
		grid.add_child(cell)

#更新背包
func update_bag_list():
	if not has_node("PageContainer/BagPage/BagScroll/BagGrid"): return
	var grid = $PageContainer/BagPage/BagScroll/BagGrid
	for cell in grid.get_children():
		var item_id = cell.name.replace("_cell", "")
		var count_lbl = cell.find_child("CountLabel", true, false)
		if count_lbl:
			var count = data.lottery_ticket if item_id == "lottery_ticket" else data.items.get(item_id, 0)
			count_lbl.text = "x%d" % count

# ========== 通用数量选择器 ==========
func _show_quantity_selector(item_id: String, title_text: String, on_confirm: Callable):
	_close_quantity_selector()
	
	var max_count = data.items.get(item_id, 0)
	if max_count <= 0: return
	
	var panel = _create_base_popup(title_text, Vector2(420, 260), Vector2(366, 200))
	panel.name = "QuantitySelector"
	
	var vbox = panel.get_child(0)
	
	var own_label = Label.new()
	own_label.text = "拥有：%d" % max_count
	own_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(own_label)
	
	var pair = _create_slider_spin_pair(vbox, max_count)
	var spin = pair.spin
	
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
	
	add_child(panel)

func _close_quantity_selector():
	if has_node("QuantitySelector"):
		_safe_close("QuantitySelector")

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
	_pending_ginseng_type = "ginseng"
	_close_quantity_selector()
	_show_ginseng_selector()

func _on_ginseng_1000_confirmed(spin: SpinBox):
	var count = int(spin.value)
	if data.items.get("ginseng_1000", 0) < count:
		_close_quantity_selector()
		return
	_pending_ginseng_count = count
	_pending_ginseng_type = "ginseng_1000"
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
	title.text = "选择门客使用%s" % data.ITEM_CONFIG.get(_pending_ginseng_type, {}).get("name", "人参")
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

func on_money_plus_clicked():
	var count = data.items.get("hour_card", 0)
	if count <= 0:
		_show_stage_hint("没有小时卡，请前往商城购买")
		return
	_show_quantity_selector("hour_card", "使用小时卡", _on_hour_card_confirmed)

func _on_hour_card_confirmed(spin: SpinBox):
	var count = int(spin.value)
	var gain = data.use_hour_card(count)
	if gain > 0:
		_close_quantity_selector()
		update_all_ui()
		update_bag_list()
		_show_stage_hint("获得铜钱 %s" % format_number(gain))
	else:
		_close_quantity_selector()

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
		data.heroes[hero_id].base_income += 2000 * count
	else:
		data.heroes[hero_id].base_income += 20000 * count
	
	_pending_ginseng_count = 0
	_pending_ginseng_type = ""
	_close_ginseng_selector()
	update_bag_list()
	update_all_ui()

func _close_ginseng_selector():
	var bag_page = $PageContainer/BagPage
	if bag_page.has_node("GinsengSelector"):
		bag_page.get_node("GinsengSelector").queue_free()
	_pending_ginseng_count = 0
	_pending_ginseng_type = ""

func _show_hero_box_selector():
	if has_node("HeroBoxSelector"): return
	
	var panel = _create_base_popup("选择门客", Vector2(460, 500), Vector2(346, 120))
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
	cancel.pressed.connect(func(): _safe_close("HeroBoxSelector"))
	vbox.add_child(cancel)
	
	add_child(panel)

func _on_hero_box_selected(hero_id: String):
	if data.items.get("hero_box", 0) < 1:
		_safe_close("HeroBoxSelector")
		return
	
	data.items.hero_box -= 1
	data.unlock_hero(hero_id)
	
	var cfg = data.get_hero_config(hero_id)
	_safe_close("HeroBoxSelector")
	_show_stage_hint("获得门客【%s】" % cfg.name)
	update_all_ui()
	update_bag_list()
	generate_hero_list() 


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
	var text = "🥈 %s  |  🥇：%s  |  VIP%d  |  赚速：%s/秒" % [
		format_number(data.money),
		format_number(data.yuanbao),
		data.get_vip_level(),  # ← 使用函数获取实时等级
		format_number(data.get_total_auto_income())
	]
	if has_node("TopBar/Label"):
		$TopBar/Label.text = text
	elif has_node("Label"):
		$Label.text = text

func update_entry_buttons():
	if has_node("PageContainer/ShopPage/HQEntryBtn"):
		var income = data.get_hq_auto_income()
		$PageContainer/ShopPage/HQEntryBtn.text = "【钱庄】Lv.%d  |  挂机 %d/秒  |  点击 +%d" % [data.hq.level, income, data.hq.click_income]
	
	if not has_node("PageContainer/ShopPage/ShopScroll/ShopList"): return
	for btn in $PageContainer/ShopPage/ShopScroll/ShopList.get_children():
		var shop_id = btn.name.replace("_entry", "")
		var cfg = data.get_shop_config(shop_id)
		if cfg.is_empty(): continue
		
		if data.shops.has(shop_id):
			var s = data.shops[shop_id]
			var income = data.get_shop_auto_income(shop_id)
			btn.text = "【%s】Lv.%d  |  赚速 %s/秒  |  店员 %d人" % [s.name, s.level, format_number(income), s.staff]
			btn.modulate = Color.WHITE
			btn.disabled = false
		elif data.can_unlock_shop(shop_id):
			btn.text = "【%s】点击解锁（第%d章）" % [cfg.name, data.get_shop_unlock_chapter(shop_id)]
			btn.modulate = Color("#e0c070")
			btn.disabled = false
		else:
			btn.text = "【%s】未解锁（第%d章）" % [cfg.name, data.get_shop_unlock_chapter(shop_id)]
			btn.modulate = Color(0.4, 0.4, 0.4, 0.6)
			btn.disabled = true

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
		var batch = false
		if has_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck"):
			batch = $ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck.button_pressed
		
		if batch:
			var total_cost = 0
			var temp_cost = cost
			for i in range(10):
				total_cost += temp_cost
				temp_cost = int(ceil(temp_cost * 1.01))
			$ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn.text = "👤 招募（%s铜钱）" % format_number(total_cost)
		else:
			$ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn.text = "👤 招募（%s铜钱）" % format_number(cost)
	
	
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
	page.set_anchors_preset(Control.PRESET_FULL_RECT)  # 【新增】让 page 先铺满
	
	# 自动创建 GridContainer
	var grid: GridContainer
	if page.has_node("MansionGrid"):
		grid = page.get_node("MansionGrid")
	else:
		grid = GridContainer.new()
		grid.name = "MansionGrid"
		grid.columns = 5
		# 【删】grid.custom_minimum_size = Vector2(1100, 500)
		# 【新增】让 grid 铺满 page
		grid.set_anchors_preset(Control.PRESET_FULL_RECT)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		page.add_child(grid)
	
	# 清空
	for child in grid.get_children():
		child.queue_free()
	
	var modules = [
		{"name": "挚友", "func": "on_friend_page"},
		{"name": "商城", "func": "on_mall"},
		{"name": "每日任务", "func": "on_daily_task"},
		{"name": "VIP", "func": "on_vip"},
		{"name": "充值豪礼", "func": "on_recharge"},
		{"name": "珍兽", "func": "on_beast"},
	]
	
	for m in modules:
		var cell = PanelContainer.new()
		# 【改】允许 cell 扩展填满
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(200, 140)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		# 【新增】让内部也跟随扩展
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

func on_friend_page():
	switch_page("friend")
	update_friend_page()

# 预留函数
func on_daily_task(): print("每日任务预留")

func on_mall():
	_close_mall_panel()
	
	var panel = _create_base_popup("商城", Vector2(500, 320), Vector2(326, 160))
	panel.name = "MallPanel"
	
	var vbox = panel.get_child(0)
	
	# 驺虞礼包
	var row1 = HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_theme_constant_override("separation", 16)
	vbox.add_child(row1)
	
	var info1 = Label.new()
	info1.text = "驺虞礼包\n驺虞×1 + 珍兽果×988 + 奇香果×988"
	info1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(info1)
	
	var buy1 = Button.new()
	buy1.text = "19888元宝"
	buy1.custom_minimum_size = Vector2(120, 40)
	buy1.pressed.connect(_on_buy_zou_yu_pack)
	row1.add_child(buy1)
	
	# 小时卡礼包
	var row2 = HBoxContainer.new()
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_theme_constant_override("separation", 16)
	vbox.add_child(row2)
	
	var info2 = Label.new()
	info2.text = "小时卡礼包\n小时卡×999"
	info2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row2.add_child(info2)
	
	var buy2 = Button.new()
	buy2.text = "998元宝"
	buy2.custom_minimum_size = Vector2(120, 40)
	buy2.pressed.connect(_on_buy_hour_card_pack)
	row2.add_child(buy2)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_mall_panel)
	vbox.add_child(close_btn)
	
	add_child(panel)
	_current_popup = panel
	$Overlay.show()

func _on_buy_zou_yu_pack():
	if data.buy_test_beast_pack():
		update_all_ui()
		update_bag_list()
		_show_stage_hint("购买成功！驺虞×1 珍兽果×988 奇香果×988")
	else:
		flash_red("MallPanel")

func _on_buy_hour_card_pack():
	if data.yuanbao < 998:
		flash_red("MallPanel")
		return
	data.yuanbao -= 998
	data.items.hour_card += 999
	update_all_ui()
	update_bag_list()
	_show_stage_hint("购买成功！获得小时卡 ×999")

func _close_mall_panel():
	if has_node("MallPanel"):
		_safe_close("MallPanel")
	$Overlay.hide()
	_current_popup = null

func on_beast():
	switch_page("beast")
	update_beast_page()

func generate_beast_page():
	if not has_node("PageContainer/BeastPage"): return
	var page = $PageContainer/BeastPage
	for child in page.get_children():
		child.queue_free()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.name = "BeastVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	page.add_child(vbox)
	
	var title = Label.new()
	title.text = "珍兽"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	var res = Label.new()
	res.name = "BeastRes"
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(res)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var grid = GridContainer.new()
	grid.name = "BeastGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)


func update_beast_page():
	if not has_node("PageContainer/BeastPage/BeastVBox"): return
	var vbox = $PageContainer/BeastPage/BeastVBox
	vbox.get_node("BeastRes").text = "珍兽果：%d  |  奇香果：%d" % [data.beast_fruit, data.aroma_fruit]
	
	var grid = vbox.find_child("BeastGrid", true, false)
	if grid == null: return
	for child in grid.get_children():
		child.queue_free()
	
	for beast_id in data.beasts.keys():
		var cfg = data.get_beast_config(beast_id)
		var raw = data.beasts[beast_id]
		var count = raw.size() if raw is Array else 1
		for i in range(count):
			var instance = data.get_beast_instance(beast_id, i)
			if instance == null: continue
			
			var cell = _create_beast_card()
			cell.name = beast_id + "_" + str(i)
			cell.pressed.connect(open_beast_detail.bind(beast_id, i))
			
			var apt = data.get_beast_aptitude(beast_id, i)
			var bonus = data.get_beast_skill_bonus(beast_id, i) + data.get_beast_aura_bonus(beast_id, i)
			var hero_name = ""
			var hid = instance.get("equipped_hero", "")
			if hid != "" and data.heroes.has(hid):
				hero_name = data.heroes[hid].name
			
			var name_lbl = cell.find_child("BeastNameLabel", true, false)
			if name_lbl: name_lbl.text = "【%s】" % cfg.name
			
			var info_lbl = cell.find_child("BeastInfoLabel", true, false)
			if info_lbl: info_lbl.text = "Lv.%d  |  %s" % [instance.level, cfg.quality]
			
			var apt_lbl = cell.find_child("BeastAptLabel", true, false)
			if apt_lbl: apt_lbl.text = "资质：%d" % apt
			
			var bonus_lbl = cell.find_child("BeastBonusLabel", true, false)
			if bonus_lbl: bonus_lbl.text = "加成：%.0f%%" % (bonus * 100)
			
			var hero_lbl = cell.find_child("BeastHeroLabel", true, false)
			if hero_lbl: hero_lbl.text = "装备：%s" % (hero_name if hero_name != "" else "未装备")
			
			grid.add_child(cell)


func _on_exchange_beast(beast_id: String):
	var cfg = data.get_beast_config(beast_id)
	var ex = cfg.get("exchange_item", "")
	if data.items.get(ex, 0) < 100:
		_show_stage_hint("【%s】兑换道具不足！" % cfg.name)
		return
	data.items[ex] -= 100
	if data.add_beast(beast_id):
		update_beast_page()
		update_all_ui()
		update_bag_list()
		_show_stage_hint("兑换成功！获得【%s】" % cfg.name)
		# 如果兑换视图打开，也刷新
		if has_node("PageContainer/AdventurePage/ExchangeView/BeastExchangeView") and $PageContainer/AdventurePage/ExchangeView/BeastExchangeView.visible:
			update_beast_exchange_view()
	else:
		_show_stage_hint("兑换失败")

func open_beast_detail(beast_id: String, instance_index: int):
	_close_beast_detail()
	_current_beast_id = beast_id
	_current_beast_index = instance_index
	
	var cfg = data.get_beast_config(beast_id)
	var instance = data.get_beast_instance(beast_id, instance_index)
	if instance == null: return
	
	var panel = _create_base_popup("【%s】" % cfg.name, Vector2(520, 620), Vector2(316, 30))
	panel.name = "BeastDetailPanel"
	var vbox = panel.get_child(0)
	
	# 品质
	var quality_lbl = Label.new()
	quality_lbl.name = "BeastQualityLbl"
	quality_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(quality_lbl)
	
	# 资质行（文字 + 升级按钮）
	var apt_row = HBoxContainer.new()
	apt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	apt_row.add_theme_constant_override("separation", 12)
	vbox.add_child(apt_row)
	
	var apt_lbl = Label.new()
	apt_lbl.name = "BeastAptLbl"
	apt_row.add_child(apt_lbl)
	
	var up_btn = Button.new()
	up_btn.name = "BeastUpBtn"
	up_btn.custom_minimum_size = Vector2(120, 32)
	up_btn.pressed.connect(_on_beast_upgrade.bind(beast_id, instance_index))
	apt_row.add_child(up_btn)
	
	# 光环
	var aura_lbl = Label.new()
	aura_lbl.name = "BeastAuraLbl"
	aura_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aura_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(aura_lbl)
	
	# 技能列表标题行
	var skill_title_row = HBoxContainer.new()
	skill_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_title_row.add_theme_constant_override("separation", 16)
	vbox.add_child(skill_title_row)
	
	var skill_title = Label.new()
	skill_title.text = "技能列表"
	skill_title.add_theme_font_size_override("font_size", 18)
	skill_title.add_theme_color_override("font_color", Color("#ffd700"))
	skill_title_row.add_child(skill_title)
	
	var skill_bonus_lbl = Label.new()
	skill_bonus_lbl.name = "BeastSkillBonusLbl"
	skill_title_row.add_child(skill_bonus_lbl)
	
	# 技能网格滚动区
	var skill_scroll = ScrollContainer.new()
	skill_scroll.name = "BeastSkillScroll"
	skill_scroll.custom_minimum_size = Vector2(0, 220)
	skill_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(skill_scroll)
	
	var skill_grid = GridContainer.new()
	skill_grid.name = "BeastSkillGrid"
	skill_grid.columns = 4
	skill_grid.add_theme_constant_override("h_separation", 8)
	skill_grid.add_theme_constant_override("v_separation", 8)
	skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(skill_grid)
	
	# 创建技能按钮
	var skill_count = cfg.get("skill_count", 0)
	for i in range(skill_count):
		var btn = Button.new()
		btn.name = "BeastSkillBtn_%d" % i
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_beast_skill_clicked.bind(i))
		skill_grid.add_child(btn)
	
	# 装备/卸下按钮
	var equip_btn = Button.new()
	equip_btn.name = "BeastEquipBtn"
	equip_btn.custom_minimum_size = Vector2(200, 40)
	equip_btn.pressed.connect(_on_beast_equip_toggle.bind(beast_id, instance_index))
	vbox.add_child(equip_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_beast_detail)
	vbox.add_child(close_btn)
	
	add_child(panel)
	_current_popup = panel
	$Overlay.show()
	_update_beast_detail(beast_id, instance_index)

func _update_beast_detail(beast_id: String, instance_index: int):
	if not has_node("BeastDetailPanel"): return
	var cfg = data.get_beast_config(beast_id)
	var instance = data.get_beast_instance(beast_id, instance_index)
	if instance == null: return
	
	var vbox = $BeastDetailPanel.get_child(0)
	var quality_lbl = vbox.get_node("BeastQualityLbl")
	var apt_lbl = vbox.find_child("BeastAptLbl", true, false)
	var up_btn = vbox.find_child("BeastUpBtn", true, false)
	var aura_lbl = vbox.get_node("BeastAuraLbl")
	var skill_bonus_lbl = vbox.find_child("BeastSkillBonusLbl", true, false)
	var equip_btn = vbox.get_node("BeastEquipBtn")
	
	var apt = data.get_beast_aptitude(beast_id, instance_index)
	var skill_bonus = data.get_beast_skill_bonus(beast_id, instance_index)
	
	quality_lbl.text = "品质：%s" % cfg.quality
	apt_lbl.text = "资质：%d（基础%d + 等级%d×8）" % [apt, cfg.aptitude, instance.level - 1]
	
	up_btn.text = "升级" if instance.level < 200 else "已满级"
	up_btn.disabled = instance.level >= 200 or data.beast_fruit < 80
	
	# 光环显示具体列表
	var auras = cfg.get("auras", [])
	if auras.is_empty():
		aura_lbl.text = "光环：无"
	else:
		var aura_texts = []
		for a in auras:
			aura_texts.append(a)
		aura_lbl.text = "光环：%s" % " | ".join(aura_texts)
	
	skill_bonus_lbl.text = "技能加成：%.0f%%" % (skill_bonus * 100)
	
	# 更新技能网格按钮
	var skills = instance.get("skills", [])
	var skill_grid = vbox.find_child("BeastSkillGrid", true, false)
	if skill_grid:
		for i in range(skill_grid.get_child_count()):
			var btn = skill_grid.get_child(i)
			if i < skills.size():
				btn.visible = true
				var sk = skills[i]
				var txt = "+%.0f%%" % (sk.percent * 100)
				if sk.percent >= 0.249:
					txt += " [满]"
					btn.disabled = true
				else:
					btn.disabled = false
				btn.text = txt
			else:
				btn.visible = false
	
	# 装备状态
	var hid = instance.get("equipped_hero", "")
	if hid != "":
		equip_btn.text = "卸下"
	else:
		equip_btn.text = "装备"

func _on_beast_upgrade(beast_id: String, instance_index: int):
	if data.upgrade_beast(beast_id, instance_index):
		_update_beast_detail(beast_id, instance_index)
		update_beast_page()
		update_all_ui()


func _on_beast_equip_toggle(beast_id: String, instance_index: int):
	var instance = data.get_beast_instance(beast_id, instance_index)
	if instance == null: return
	var hid = instance.get("equipped_hero", "")
	if hid != "":
		data.unequip_beast(hid)
		_update_beast_detail(beast_id, instance_index)
		update_beast_page()
		update_hero_panel()
		update_all_ui()
	else:
		_show_hero_equip_selector(beast_id, instance_index)

func _show_hero_equip_selector(beast_id: String, instance_index: int):
	
	# 关闭技能刷新面板，避免层级冲突
	_close_beast_skill_refresh_panel()
	var panel = _create_base_popup("选择门客装备", Vector2(460, 400), Vector2(346, 120))
	panel.name = "HeroEquipSelector"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	for hero_id in data.heroes.keys():
		var h = data.heroes[hero_id]
		var btn = Button.new()
		var income = data.get_hero_income(hero_id)
		
		# 【新增】装备状态
		var status = ""
		var equipped_beast = h.get("equipped_beast", "")
		if equipped_beast == beast_id and h.get("equipped_beast_index", 0) == instance_index:
			status = " [已装备]"
			btn.disabled = true
		elif equipped_beast != "":
			var b_cfg = data.get_beast_config(equipped_beast)
			status = " [%s]" % b_cfg.name
		
		btn.text = "【%s】%s Lv.%d | %s/秒%s" % [h.name, h.category, h.level, format_number(income), status]
		
		if not btn.disabled:
			btn.pressed.connect(_on_hero_equipped_beast.bind(hero_id, beast_id, instance_index))
		list.add_child(btn)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): _safe_close("HeroEquipSelector"))
	vbox.add_child(cancel)
	
	add_child(panel)

func _on_hero_equipped_beast(hero_id: String, beast_id: String, instance_index: int):
	data.equip_beast(hero_id, beast_id, instance_index)
	_safe_close("HeroEquipSelector")
	update_beast_page()
	update_all_ui()

func _on_beast_skill_clicked(skill_index: int):
	_selected_beast_skill_index = skill_index
	_show_beast_skill_refresh_panel()

func _show_beast_skill_refresh_panel():
	var parent = $BeastDetailPanel
	if parent == null: return
	if parent.has_node("BeastSkillRefreshPanel"): return
	
	var instance = data.get_beast_instance(_current_beast_id, _current_beast_index)
	if instance == null: return
	var skills = instance.get("skills", [])
	if _selected_beast_skill_index < 0 or _selected_beast_skill_index >= skills.size(): return
	var skill = skills[_selected_beast_skill_index]
	
	var panel = PanelContainer.new()
	panel.name = "BeastSkillRefreshPanel"
	panel.custom_minimum_size = Vector2(360, 260)
	panel.position = (parent.size - panel.custom_minimum_size) / 2
	panel.z_index = 50
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "技能槽位 #%d" % (_selected_beast_skill_index + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	# 当前加成
	var bonus_lbl = Label.new()
	bonus_lbl.name = "BeastSkillBonus"
	bonus_lbl.text = "当前加成：+%.0f%%" % (skill.percent * 100)
	bonus_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(bonus_lbl)
	
	# 状态/消耗
	var status_lbl = Label.new()
	status_lbl.name = "BeastSkillStatus"
	vbox.add_child(status_lbl)
	
	# 勾选框
	if skill.percent < 0.249:
		var aroma_check = CheckBox.new()
		aroma_check.name = "AromaCheck"
		aroma_check.text = "使用奇香果（拥有：%d）" % data.aroma_fruit
		vbox.add_child(aroma_check)
	
	# 按钮区
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	if skill.percent < 0.249:
		var refresh_btn = Button.new()
		refresh_btn.name = "BeastSkillRefreshBtn"
		refresh_btn.text = "刷新"
		refresh_btn.custom_minimum_size = Vector2(100, 40)
		refresh_btn.pressed.connect(_on_refresh_beast_skill)
		btn_box.add_child(refresh_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.pressed.connect(_close_beast_skill_refresh_panel)
	btn_box.add_child(close_btn)
	
	parent.add_child(panel)
	_update_beast_skill_refresh_panel()

func _update_beast_skill_refresh_panel():
	var parent = $BeastDetailPanel
	var panel = parent.get_node_or_null("BeastSkillRefreshPanel")
	if not panel: return
	
	var instance = data.get_beast_instance(_current_beast_id, _current_beast_index)
	if instance == null: return
	var skills = instance.get("skills", [])
	if _selected_beast_skill_index < 0 or _selected_beast_skill_index >= skills.size(): return
	var skill = skills[_selected_beast_skill_index]
	
	var bonus_lbl = panel.find_child("BeastSkillBonus", true, false)
	if bonus_lbl:
		bonus_lbl.text = "当前加成：+%.0f%%" % (skill.percent * 100)
	
	var status_lbl = panel.find_child("BeastSkillStatus", true, false)
	var aroma_check = panel.find_child("AromaCheck", true, false)
	if status_lbl:
		if skill.percent >= 0.249:
			status_lbl.text = "已满级"
			status_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			var use_aroma = aroma_check != null and aroma_check.button_pressed
			if use_aroma:
				status_lbl.text = "奇香果：%d/1" % data.aroma_fruit
			else:
				var cost = 100 * int(pow(2, skill.refresh_count))
				status_lbl.text = "刷新消耗：%s 铜钱" % format_number(cost)
			status_lbl.remove_theme_color_override("font_color")
	
	if aroma_check:
		aroma_check.text = "使用奇香果（拥有：%d）" % data.aroma_fruit
		if skill.percent >= 0.249:
			aroma_check.visible = false
	
	var refresh_btn = panel.find_child("BeastSkillRefreshBtn", true, false)
	if skill.percent >= 0.249:
		if refresh_btn:
			refresh_btn.queue_free()
		if aroma_check:
			aroma_check.queue_free()
	else:
		if refresh_btn:
			refresh_btn.text = "刷新"

func _on_refresh_beast_skill():
	if _selected_beast_skill_index < 0: return
	var parent = $BeastDetailPanel
	var panel = parent.get_node_or_null("BeastSkillRefreshPanel")
	var use_aroma = false
	if panel:
		var aroma_check = panel.find_child("AromaCheck", true, false)
		if aroma_check:
			use_aroma = aroma_check.button_pressed
	
	if data.refresh_beast_skill(_current_beast_id, _current_beast_index, _selected_beast_skill_index, use_aroma):
		_update_beast_detail(_current_beast_id, _current_beast_index)
		update_beast_page()
		update_all_ui()
		update_bag_list()
		var instance = data.get_beast_instance(_current_beast_id, _current_beast_index)
		var skills = instance.get("skills", [])
		var skill = skills[_selected_beast_skill_index]
		if skill.percent >= 0.249:
			_close_beast_skill_refresh_panel()
		else:
			_update_beast_skill_refresh_panel()
	else:
		var panel2 = $BeastDetailPanel.get_node_or_null("BeastSkillRefreshPanel")
		if panel2:
			var refresh_btn = panel2.find_child("BeastSkillRefreshBtn", true, false)
			if refresh_btn:
				flash_red(refresh_btn.get_path())

func _close_beast_skill_refresh_panel():
	var parent = get_node_or_null("BeastDetailPanel")
	if parent == null: return
	var panel = parent.get_node_or_null("BeastSkillRefreshPanel")
	if panel:
		panel.queue_free()

func _close_beast_detail():
	# 先关闭内层面板
	if has_node("BeastDetailPanel/BeastSkillRefreshPanel"):
		var inner = $BeastDetailPanel/BeastSkillRefreshPanel
		inner.get_parent().remove_child(inner)
		inner.queue_free()
	# 立即从场景树移除旧面板，避免同名冲突
	if has_node("BeastDetailPanel"):
		var old = $BeastDetailPanel
		old.get_parent().remove_child(old)
		old.queue_free()
	# 如果下层 HeroPanel 还开着...
	if has_node("HeroPanel") and $HeroPanel.visible:
		_current_popup = $HeroPanel
		$Overlay.show()
		update_hero_panel()
	else:
		$Overlay.hide()
		_current_popup = null

func _on_buy_test_beast_pack():
	if data.buy_test_beast_pack():
		update_beast_page()
		update_all_ui()
		update_bag_list()
		_show_stage_hint("购买成功！驺虞×1 珍兽果×988 奇香果×988")
	else:
		_show_stage_hint("元宝不足！")

func generate_stage_page():
	if not has_node("PageContainer/StagePage"): return
	var page = $PageContainer/StagePage
	
	# 清空旧内容
	for child in page.get_children():
		child.queue_free()
	
	# 【改】让 StagePage 填满整个 PageContainer
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.name = "StageVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)  # 【改】让 vbox 填满 StagePage
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 50)
	page.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.name = "StageTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	# 信息区
	var info = Label.new()
	info.name = "StageInfo"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	# Boss信息
	var boss_info = Label.new()
	boss_info.name = "BossInfo"
	boss_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_info.add_theme_color_override("font_color", Color("#ff8888"))
	vbox.add_child(boss_info)
	
	# 贸易按钮
	var trade_btn = Button.new()
	trade_btn.name = "TradeBtn"
	trade_btn.custom_minimum_size = Vector2(240, 50)
	vbox.add_child(trade_btn)
	
	# Boss谈判按钮
	var boss_btn = Button.new()
	boss_btn.name = "BossBtn"
	boss_btn.text = "Boss谈判"
	boss_btn.custom_minimum_size = Vector2(240, 50)
	boss_btn.visible = false
	vbox.add_child(boss_btn)
	

	# 连接信号
	trade_btn.pressed.connect(on_stage_trade)
	boss_btn.pressed.connect(on_stage_boss)

func update_stage_page():
	if not has_node("PageContainer/StagePage/StageVBox"): return
	var vbox = $PageContainer/StagePage/StageVBox
	
	var title = vbox.get_node("StageTitle")
	var info = vbox.get_node("StageInfo")
	var boss_info = vbox.get_node("BossInfo")
	var trade_btn = vbox.get_node("TradeBtn")
	var boss_btn = vbox.get_node("BossBtn")
	
	var main = data.stage_main
	var sub = data.stage_sub
	var count = data.stage_trade_count
	
	title.text = "第 %d 章 - 第 %d 关" % [main, sub]
	
	var cost = data.get_stage_trade_cost()
	var boss_income = data.get_stage_boss_income()
	var hero_power = data.get_heroes_total_income()
	var discount = clamp(float(boss_income) / float(max(hero_power, 1)), 0.1, 1.0)
	var actual_cost = int(cost * discount)
	
	info.text = "基础花费：%s  |  实际花费：%s（%.0f%%）\n已贸易：%d/3  |  声望：%d  |  阅历+%d/次" % [
		format_number(cost),
		format_number(actual_cost),
		discount * 100,
		count,
		data.reputation,
		10 * data.stage_main
	]
	
	trade_btn.text = "贸易（-%s）" % format_number(actual_cost)
	
	# 【改】Boss出现时的按钮状态
	if data.is_stage_boss_ready():
		trade_btn.disabled = true
		trade_btn.text = "Boss 已出现"
		boss_btn.visible = true
		boss_info.visible = true
		boss_info.text = "Boss 赚速：%s/秒  |  我方赚速：%s/秒" % [
			format_number(boss_income),
			format_number(hero_power)
		]
		if hero_power > boss_income:
			boss_btn.text = "Boss谈判（可战胜）"
			boss_btn.disabled = false
		else:
			boss_btn.text = "Boss谈判（实力不足）"
			boss_btn.disabled = false
	else:
		trade_btn.disabled = false
		trade_btn.text = "贸易（-%s）" % format_number(actual_cost)
		boss_btn.visible = false
		boss_info.visible = false

func on_stage_trade():
	var result = data.do_stage_trade()
	if not result.ok:
		flash_red("PageContainer/StagePage/StageVBox/TradeBtn")
		return
	
	update_stage_page()
	update_all_ui()
	update_bag_list()
	
	# 【改】普通贸易静默，只有关键节点才短暂提示
	if result.type == "next_sub":
		_show_stage_hint("通关！宝箱×1  阅历+%d" % result.get("exp_reward", 0))
	elif result.type == "boss_ready":
		_show_stage_hint("贸易完成，Boss 已出现！")

func on_stage_boss():
	var result = data.do_stage_boss()
	if not result.ok:
		return
	
	if result.win:
		_show_stage_hint("谈判成功！声望 +10，抽奖券 +1")
	else:
		_show_stage_hint("谈判失败！Boss 赚速 %s，我方仅 %s" % [
			format_number(result.boss_income),
			format_number(result.hero_power)
		])
	
	update_stage_page()
	update_all_ui()
	update_bag_list()
	update_entry_buttons()

func _show_stage_hint(text: String, auto_hide: float = 2.5):
	var panel = get_node_or_null("StageHint")
	var vbox: VBoxContainer
	var label: Label
	
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "StageHint"
		panel.custom_minimum_size = Vector2(400, 120)
		panel.position = Vector2(376, 250)
		panel.z_index = 50
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#1e1b2e")
		style.set_corner_radius_all(12)
		panel.add_theme_stylebox_override("panel", style)
		
		vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 12)
		panel.add_child(vbox)
		
		label = Label.new()
		label.name = "HintLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color("#ffd700"))
		vbox.add_child(label)
		
		add_child(panel)
	else:
		# 杀掉旧 tween，防止堆叠
		var old_tween = panel.get_meta("hint_tween", null)
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
		vbox = panel.get_child(0)
		label = vbox.get_node("HintLabel")
	
	label.text = text
	
	var tween = create_tween()
	panel.set_meta("hint_tween", tween)
	tween.tween_interval(auto_hide)
	tween.tween_callback(func():
		if has_node("StageHint"):
			_safe_close("StageHint")
	)

func _init_avatar_box():
	if not has_node("TopBar"): return
	if $TopBar.has_node("AvatarBox"): return
	
	var box = HBoxContainer.new()
	box.name = "AvatarBox"
	box.add_theme_constant_override("separation", 12)
	
	var avatar = PanelContainer.new()
	avatar.name = "Avatar"
	avatar.custom_minimum_size = Vector2(32, 32)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#c9a959")
	style.set_corner_radius_all(16)
	avatar.add_theme_stylebox_override("panel", style)
	box.add_child(avatar)
	
	var name_btn = Button.new()
	name_btn.name = "PlayerNameBtn"
	name_btn.text = data.player_name
	name_btn.flat = true
	name_btn.add_theme_color_override("font_color", Color("#f2e9e4"))
	name_btn.add_theme_font_size_override("font_size", 16)
	name_btn.pressed.connect(open_player_panel)
	box.add_child(name_btn)
	
	$TopBar.add_child(box)
	$TopBar.move_child(box, 0)

func open_player_panel():
	_close_player_panel()
	
	var panel = _create_base_popup("", Vector2(480, 520), Vector2(336, 60))
	panel.name = "PlayerPanel"
	
	var vbox = panel.get_child(0)
	
	# 标题
	var title = Label.new()
	title.text = "【%s】身份 Lv.%d" % [data.player_name, data.identity_level]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	# 改名区
	var rename_row = HBoxContainer.new()
	rename_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rename_row.add_theme_constant_override("separation", 8)
	vbox.add_child(rename_row)
	
	var name_input = LineEdit.new()
	name_input.name = "NameInput"
	name_input.text = data.player_name
	name_input.custom_minimum_size = Vector2(180, 36)
	name_input.placeholder_text = "输入新名字"
	rename_row.add_child(name_input)
	
	var rename_btn = Button.new()
	rename_btn.text = "改名"
	rename_btn.custom_minimum_size = Vector2(70, 36)
	rename_btn.pressed.connect(_on_rename_confirmed.bind(name_input))
	rename_row.add_child(rename_btn)
	
	# 晋升信息
	var next_lv = data.identity_level + 1
	var need_income = data.get_identity_income_req(next_lv)
	var need_rep = data.get_identity_reputation_req(next_lv)
	var cur_income = data.get_total_auto_income()
	var cur_rep = data.reputation
	
	var info = Label.new()
	info.text = "下一级 Lv.%d 需求：\n赚速 %s/秒（当前 %s/秒）\n声望 %s（当前 %s）" % [
		next_lv,
		format_number(need_income),
		format_number(cur_income),
		format_number(need_rep),
		format_number(cur_rep)
	]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	# 晋升按钮
	var promote_btn = Button.new()
	promote_btn.name = "PromoteBtn"
	promote_btn.custom_minimum_size = Vector2(200, 44)
	if data.can_promote_identity():
		promote_btn.text = "晋升身份"
	else:
		promote_btn.text = "条件不足"
		promote_btn.disabled = true
	promote_btn.pressed.connect(_on_promote_identity)
	vbox.add_child(promote_btn)
	
	# 身份奖励
	var reward_title = Label.new()
	reward_title.text = "身份等级奖励"
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(reward_title)
	
	var reward_scroll = ScrollContainer.new()
	reward_scroll.custom_minimum_size = Vector2(0, 200)
	vbox.add_child(reward_scroll)
	
	var reward_list = VBoxContainer.new()
	reward_list.name = "IdentityRewardList"
	reward_scroll.add_child(reward_list)
	
	
	
	# 每日宝箱（右下角风格，放在 vbox 底部）
	var chest_box = HBoxContainer.new()
	chest_box.alignment = BoxContainer.ALIGNMENT_CENTER
	chest_box.add_theme_constant_override("separation", 12)
	vbox.add_child(chest_box)
	
	var chest_btn = Button.new()
	chest_btn.name = "DailyChestBtn"
	chest_btn.custom_minimum_size = Vector2(160, 50)
	if data.can_claim_daily_reward():
		chest_btn.text = "每日宝箱\n领 %s 元宝" % format_number(data.identity_level * 10000)
	else:
		chest_btn.text = "每日宝箱\n已领取"
		chest_btn.disabled = true
	chest_btn.pressed.connect(_on_claim_daily_reward)
	chest_box.add_child(chest_btn)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_player_panel)
	vbox.add_child(close_btn)
	
	add_child(panel)
	_current_popup = panel
	$Overlay.show()
	_update_identity_reward_list()

func _update_identity_reward_list():
	if not has_node("PlayerPanel"): return
	var list = $PlayerPanel.find_child("IdentityRewardList", true, false)
	if list == null: return
	for child in list.get_children():
		child.queue_free()
	
	var has_reward = false
	for level in range(2, data.identity_level + 1):
		if data.identity_rewards_claimed.get(str(level), false): continue
		var reward = data.get_identity_reward(level)
		if reward.is_empty(): continue
		
		has_reward = true
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var info = Label.new()
		info.text = "Lv.%d %s" % [level, reward.name]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(info)
		
		var btn = Button.new()
		btn.text = "领取"
		btn.custom_minimum_size = Vector2(80, 32)
		btn.pressed.connect(_on_claim_identity_reward.bind(level))
		row.add_child(btn)
		
		list.add_child(row)
	
	if not has_reward:
		var empty = Label.new()
		empty.text = "暂无可领取奖励"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)

func _on_claim_identity_reward(level: int):
	var result = data.claim_identity_reward(level)
	if result.ok:
		_show_stage_hint("领取成功！%s" % result.reward.name)
		_update_identity_reward_list()
		update_all_ui()
		generate_hero_list()
		if has_node("PageContainer/BeastPage"):
			update_beast_page()
	elif result.duplicate:
		_show_stage_hint("门客【%s】已拥有，无法重复领取" % result.reward.name)
	else:
		flash_red("PlayerPanel")



func _close_player_panel():
	if has_node("PlayerPanel"):
		_safe_close("PlayerPanel")
	$Overlay.hide()
	_current_popup = null

func _on_rename_confirmed(input: LineEdit):
	var new_name = input.text.strip_edges()
	if data.rename_player(new_name):
		# 更新左上角名字
		if has_node("TopBar/AvatarBox/PlayerNameBtn"):
			$TopBar/AvatarBox/PlayerNameBtn.text = data.player_name
		_close_player_panel()
		_show_stage_hint("改名成功！")
	else:
		flash_red("PlayerPanel")

func _on_promote_identity():
	if data.promote_identity():
		_show_stage_hint("晋升成功！身份 Lv.%d" % data.identity_level)
		# 【新增】如果面板还开着，刷新奖励列表
		if has_node("PlayerPanel"):
			_update_identity_reward_list()
		_close_player_panel()
		update_all_ui()
	else:
		flash_red("PlayerPanel/PromoteBtn")

func _on_claim_daily_reward():
	var reward = data.claim_daily_reward()
	if reward > 0:
		_show_stage_hint("领取成功！元宝 +%s" % format_number(reward))
		update_all_ui()
		# 刷新个人页面内的宝箱按钮状态，不关闭面板
		if has_node("PlayerPanel"):
			var chest_btn = $PlayerPanel.find_child("DailyChestBtn", true, false)
			if chest_btn != null:
				chest_btn.text = "每日宝箱\n已领取"
				chest_btn.disabled = true
	else:
		flash_red("PlayerPanel/DailyChestBtn")

#充值好礼入口
func on_recharge():
	if has_node("RechargePage"):
		open_popup($RechargePage)
		_switch_recharge_tab("normal")
		_update_recharge_page()
		

func _on_tab_normal_pressed():
	_switch_recharge_tab("normal")

func _on_tab_daily_pressed():
	_switch_recharge_tab("daily")

func _on_tab_special_pressed():
	_switch_recharge_tab("special")

func _switch_recharge_tab(tab: String):
	var normal_container = $RechargePage/RechargeContainer/ContentContainer/YuanbaiContainer
	var daily_container = $RechargePage/RechargeContainer/ContentContainer/DailyGiftContainer
	var special_container = $RechargePage/RechargeContainer/ContentContainer/SpecialPackContainer
	
	normal_container.visible = false
	daily_container.visible = false
	special_container.visible = false
	
	if tab == "normal":
		normal_container.visible = true
		_update_recharge_page()
	elif tab == "daily":
		daily_container.visible = true
		_update_daily_gift_page()
	else:
		special_container.visible = true
		_update_special_pack_page()

func _update_recharge_page():
	if not has_node("RechargePage/RechargeContainer/ContentContainer/YuanbaiContainer/RechargeGrid"): return
	var grid = get_node("RechargePage/RechargeContainer/ContentContainer/YuanbaiContainer/RechargeGrid")
	
	for child in grid.get_children():
		child.queue_free()
	
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var tiers = [6, 30, 68, 128, 328, 648, 1000, 2000, 5000]
	for amount in tiers:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 80)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		btn.text = "¥%d\n%d元宝" % [amount, amount * 10]
		btn.pressed.connect(_on_recharge_confirmed.bind(amount))
		grid.add_child(btn)

func _update_special_pack_page():
	if not has_node("RechargePage/RechargeContainer/ContentContainer/SpecialPackContainer"): return
	var container = $RechargePage/RechargeContainer/ContentContainer/SpecialPackContainer
	
	for child in container.get_children():
		child.queue_free()
	
	# 确保 container 在父容器中获得垂直空间
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var scroll = ScrollContainer.new()
	scroll.name = "SpecialPackScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "SpecialPackVBox"
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 关键：不设置 size_flags_vertical！让 VBoxContainer 根据内容自然扩展高度
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(main_vbox)
	
	# 配置表驱动：所有礼包统一生成
	for pack in data.SPECIAL_PACKS:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		main_vbox.add_child(row)
		
		var info = Label.new()
		info.text = "%s\n%s" % [pack.name, pack.desc]
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_theme_font_size_override("font_size", 18)
		row.add_child(info)
		
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		
		var btn = Button.new()
		btn.text = "购买（¥%d）" % pack.cost
		btn.custom_minimum_size = Vector2(160, 60)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_buy_special_pack.bind(pack))
		row.add_child(btn)

# 通用购买处理：一个函数搞定所有礼包
func _on_buy_special_pack(pack: Dictionary):
	data.buy_special_pack(pack)
	_show_stage_hint("购买成功！%s" % pack.name)
	update_all_ui()
	update_bag_list()

func _update_daily_gift_page():
	if not has_node("RechargePage/RechargeContainer/ContentContainer/DailyGiftContainer"):
		return
	var container = get_node("RechargePage/RechargeContainer/ContentContainer/DailyGiftContainer")

	# 清空旧内容
	for child in container.get_children():
		child.queue_free()

	await get_tree().process_frame

	# 整体垂直居中
	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 20)
	container.add_child(main_vbox)

	# 标题
	var title = Label.new()
	title.text = "🎁 每日礼包"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	# 水平行：详情 + 弹性空间 + 购买按钮
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)   # 间距由弹性空间控制
	main_vbox.add_child(row)

	# 左侧：礼包详情（多行文本）
	var info = Label.new()
	info.text = "六元特惠礼包\n赠送：木梳 ×1000\n　　　胭脂 ×1000"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_theme_font_size_override("font_size", 18)
	row.add_child(info)

	# 弹性空间（把按钮推到最右边）
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# 右侧：购买按钮
	var buy_btn = Button.new()
	buy_btn.text = "购买（¥6）"
	buy_btn.custom_minimum_size = Vector2(160, 60)
	buy_btn.add_theme_font_size_override("font_size", 20)
	buy_btn.pressed.connect(_on_daily_gift_buy)
	row.add_child(buy_btn)


func _on_daily_gift_buy():
	# 1. 充值（自娱自乐，直接成功）
	var amount = 6
	if data.do_recharge(amount):
		# 2. 发放道具
		data.items.wood_comb += 1000
		data.items.rouge += 1000
		# 3. 刷新UI
		update_all_ui()
		update_bag_list()
		# 4. 弹出成功提示（复用充值成功弹窗或单独写一个）
		_show_recharge_success(amount)  # 这个函数会显示"获得XX元宝"，我们额外加一句提示
		# 由于原函数只显示元宝，我们可以在显示后追加一个标签，但简单起见，弹个额外提示
		# 或者自己写一个简单的提示框
		_show_daily_gift_success()
	else:
		# 理论上不会失败，因为 do_recharge 总是返回 true（只要 amount>0）
		pass

func _show_daily_gift_success():
	if has_node("DailyGiftSuccess"): return
	
	var panel = _create_base_popup("购买成功！", Vector2(400, 180), Vector2(376, 220))
	panel.name = "DailyGiftSuccess"
	
	var vbox = panel.get_child(0)
	var info = Label.new()
	info.text = "获得元宝 ×60\n木梳 ×1000\n胭脂 ×1000"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	_add_ok_button(vbox, func(): _safe_close("DailyGiftSuccess"))
	
	add_child(panel)


func _on_recharge_confirmed(amount: int):
	if data.do_recharge(amount):
		_show_recharge_success(amount)
		update_all_ui()

func _show_recharge_success(amount: int):
	if has_node("RechargeSuccessPanel"): return
	
	var panel = _create_base_popup("充值成功", Vector2(360, 200), Vector2(396, 224))
	panel.name = "RechargeSuccessPanel"
	
	var vbox = panel.get_child(0)
	var info = Label.new()
	info.text = "获得 %d 元宝\nVIP经验 +%d" % [amount * 10, amount * 10]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	_add_ok_button(vbox, func(): _safe_close("RechargeSuccessPanel"))
	
	add_child(panel)

func on_vip():
	if has_node("VIPPanel"):
		open_popup($VIPPanel)
		_update_vip_panel()

func _update_vip_panel():
	
	if not has_node("VIPPanel"):
		return
	var panel = $VIPPanel
	var current_level = data.get_vip_level()
	var current_exp = data.vip_exp
	var next_exp = data.get_vip_next_level_exp()
	var progress = data.get_vip_exp_progress()

	# 所有节点都在 VBoxContainer 下面，加前缀
	var vbox = panel.get_node("VBoxContainer")

	# 更新当前等级信息
	if vbox.has_node("VIPLevel"):
		vbox.get_node("VIPLevel").text = "当前 VIP：%d" % current_level

	if vbox.has_node("VIPExpInfo"):
		if current_level >= 16:
			vbox.get_node("VIPExpInfo").text = "已满级 🎉"
		else:
			vbox.get_node("VIPExpInfo").text = "经验：%s / %s" % [format_number(current_exp), format_number(next_exp)]

	if vbox.has_node("VIPProgress"):
		vbox.get_node("VIPProgress").value = progress * 100

	# 更新等级列表（V1~V15）
	var list_container = vbox.get_node("VIPList")
	if not list_container: return

	# 清空旧列表
	for child in list_container.get_children():
		child.queue_free()

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_container.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	for level in range(1, 17):  # 改为 1 到 16
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size.y = 40

		var lv_label = Label.new()
		lv_label.text = "VIP%d" % level
		lv_label.custom_minimum_size.x = 70
		if level == current_level:
			lv_label.add_theme_color_override("font_color", Color("#ffd700"))
		row.add_child(lv_label)

		var exp_label = Label.new()
		var need_exp = data.VIP_EXP_TABLE[level]
		exp_label.text = "累计 %s 元" % format_number(need_exp / 10)
		exp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(exp_label)

		# 奖励信息
		var reward_label = Label.new()
		var reward_text = ""
		if data.get_vip_rewards().has(str(level)):
			for reward in data.get_vip_rewards()[str(level)]:
				if reward.type == "hero":
					reward_text += "门客·%s " % reward.name
				else:
					reward_text += "挚友·%s " % reward.name
		else:
			reward_text = "无特殊奖励"
		reward_label.text = reward_text
		reward_label.custom_minimum_size.x = 200
		reward_label.add_theme_color_override("font_color", Color("#888888"))
		row.add_child(reward_label)

		# 领取按钮
		var claim_btn = Button.new()
		claim_btn.custom_minimum_size.x = 100
		if data.get_vip_level() < level:
			claim_btn.text = "未达成"
			claim_btn.disabled = true
		elif data.is_vip_reward_claimed(level):
			claim_btn.text = "已领取"
			claim_btn.disabled = true
		else:
			claim_btn.text = "领取"
			claim_btn.pressed.connect(_on_claim_vip_reward.bind(level))
		row.add_child(claim_btn)

		list_vbox.add_child(row)

func _on_claim_vip_reward(level: int):
	if data.claim_vip_reward(level):
		# 刷新 VIP 面板
		_update_vip_panel()
		# 刷新门客/挚友列表
		generate_hero_list()
		update_friend_page()
		update_all_ui()
		data.save_game() 
		# 可选：弹窗提示领取成功
		#_show_claim_success(level)
	else:
		# 提示失败原因（可简化）
		pass


# ========== 挚友列表 ↔ 详情 切换 ==========




func _on_locked_friend_clicked(friend_id: String, vip_level: int):
	var cfg = data.get_friend_config(friend_id)
	var friend_name = cfg.get("name", "未知挚友")
	_show_unlock_hint(friend_name, vip_level)




#挚友谈心
func on_chat_with_friend():
	var page = $PageContainer/FriendPage
	if data.energy <= 0:
		if data.items.get("energy_pill", 0) > 0:
			_show_energy_pill_prompt()
		else:
			
			var chat_btn = page.find_child("ChatBtn", true, false)
			if chat_btn:
				flash_red(chat_btn.get_path())
		return
	var batch = false
	var batch_check = page.find_child("BatchChatCheck", true, false)
	if batch_check != null:
		batch = batch_check.button_pressed
	
	var result = data.chat_with_friend(not batch)
	if result.ok:
		if current_friend_id != "" and page.get_node("FriendDetail").visible:
			_update_friend_page_detail()
		_show_chat_result(result.results)
		update_all_ui()
		update_friend_page()
		var chat_btn = page.find_child("ChatBtn", true, false)
		if chat_btn:
			chat_btn.text = "谈心（%d/100）" % data.energy
	else:
		var chat_btn = page.find_child("ChatBtn", true, false)
		if chat_btn:
			flash_red(chat_btn.get_path())

func _show_energy_pill_prompt():
	if has_node("EnergyPillPrompt"): return
	
	var max_pills = data.items.get("energy_pill", 0)
	if max_pills <= 0: return
	
	var panel = _create_base_popup("精力不足", Vector2(420, 280), Vector2(366, 184))
	panel.name = "EnergyPillPrompt"
	
	var vbox = panel.get_child(0)
	
	var info = Label.new()
	info.text = "拥有精力丹：%d" % max_pills
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	var pair = _create_slider_spin_pair(vbox, max_pills)
	var spin = pair.spin
	
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
	cancel_btn.pressed.connect(func(): _safe_close("EnergyPillPrompt"))
	btn_box.add_child(cancel_btn)
	
	add_child(panel)

func _on_use_energy_pill(spin: SpinBox = null):
	var count = 1
	if spin != null:
		count = int(spin.value)
	
	var max_pills = data.items.get("energy_pill", 0)
	count = clamp(count, 1, max_pills)
	
	if max_pills <= 0:
		if has_node("EnergyPillPrompt"): 
			_safe_close("EnergyPillPrompt")
		return
	
	data.items.energy_pill -= count
	data.energy += 3 * count
	
	if has_node("EnergyPillPrompt"): _safe_close("EnergyPillPrompt")
	var chat_btn = $PageContainer/FriendPage/FriendDetail.find_child("ChatBtn", true, false)
	if chat_btn != null:
		chat_btn.text = "谈心（%d/100）" % data.energy
	update_bag_list()
	# 吃完自动继续谈心
	on_chat_with_friend()


func _show_chat_result(results: Array):
	if has_node("ChatResultPanel"): return
	
	var panel = _create_base_popup("谈心结果", Vector2(400, 300), Vector2(376, 174))
	panel.name = "ChatResultPanel"
	
	var vbox = panel.get_child(0)
	
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
	
	_add_ok_button(vbox, func(): _safe_close("ChatResultPanel"))
	
	add_child(panel)


func _on_friend_skill_upgrade(is_fixed: bool):
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	
	var btn_name = "FixedSkillBtn" if is_fixed else "PercentSkillBtn"
	var detail = $PageContainer/FriendPage/FriendDetail
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
		_update_friend_page_detail()
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
	var parent = $PageContainer/FriendPage
	if parent.has_node("GiftSelector"): return
	
	var panel = PanelContainer.new()
	panel.name = "GiftSelector"
	panel.custom_minimum_size = Vector2(420, 260)   # 调小，确保在面板内
	panel.position = (parent.size - panel.custom_minimum_size) / 2
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
	
	parent.add_child(panel)

func _close_gift_selector():
	var parent = $PageContainer/FriendPage
	var gift = parent.get_node_or_null("GiftSelector")
	if gift != null:
		gift.queue_free()

func _on_gift_item_confirmed(spin: SpinBox, item_id: String):
	var count = int(spin.value)
	if count <= 0: return
	if current_friend_id == "": return
	if data.items.get(item_id, 0) < count:
		return
	
	for i in range(count):
		if not data.gift_friend(current_friend_id, item_id):
			break
	
	_close_gift_selector()
	_update_friend_page_detail()
	update_bag_list()
	update_all_ui()

func _refresh_gift_selector():
	var parent = $PageContainer/FriendPage
	if not parent.has_node("GiftSelector"): return
	var gifts = [
		{"id": "wood_comb", "name": "木梳", "effect": "友好+1"},
		{"id": "rouge", "name": "胭脂", "effect": "才华+1"},
	]
	for g in gifts:
		var row = parent.get_node("GiftSelector").find_child("GiftRow_" + g.id, true, false)
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
				btn.custom_minimum_size = Vector2(230, 60)  # 1152/3 = 384

#按钮美化
func style_nav_buttons():
	if not has_node("BottomNav"): return
	for btn in $BottomNav.get_children():
		if btn is Button:
			if  (current_page == "mansion" and btn.name == "NavMansionBtn") or \
				(current_page == "shop" and btn.name == "NavShopBtn") or \
				(current_page == "hero" and btn.name == "NavHeroBtn") or \
				(current_page == "stage" and btn.name == "NavStageBtn") or \
				(current_page == "adventure" and btn.name == "NavAdventureBtn") or \
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

# ========== 通用弹窗工厂 ==========

func _create_base_popup(title_text: String, popup_size: Vector2, pos: Vector2 = Vector2.ZERO) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = popup_size
	panel.position = pos if pos != Vector2.ZERO else (get_viewport_rect().size - popup_size) / 2
	panel.z_index = 30
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	if title_text != "":
		var title = Label.new()
		title.text = title_text
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color("#ffd700"))
		vbox.add_child(title)
	
	return panel

func _add_ok_button(parent: Node, callback: Callable, text: String = "确定") -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 36)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _create_slider_spin_pair(parent: Node, max_val: int, min_val: int = 1) -> Dictionary:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)
	
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = min_val
	slider.custom_minimum_size = Vector2(180, 30)
	hbox.add_child(slider)
	
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = min_val
	hbox.add_child(spin)
	
	slider.value_changed.connect(spin.set_value)
	spin.value_changed.connect(slider.set_value)
	
	return {"slider": slider, "spin": spin, "hbox": hbox}

func _safe_close(node_name: String):
	if has_node(node_name):
		get_node(node_name).queue_free()


func on_exit():
	# 正常退出：记录下线时间，然后存档
	@warning_ignore("narrowing_conversion")
	data.last_logout_time = Time.get_unix_time_from_system()
	data.save_game()
