# ============================================================
# 《大掌柜》主控制器（第3批重构版）
# 职责：场景根脚本——初始化/信号连接/页面切换导航/TopBar/弹窗工厂/共享UI工具
#       + 持有15个页面模块并转发其方法（节点路径/弹窗语义与原单文件完全一致）
# ============================================================
extends Control

var data: GameData 

#页面切换
var current_page: String = "shop"   # shop / hero / bag

var _quantity_item_id: String = ""   # 数量选择器当前操作的道具ID

#按钮信号连接
var _signals_connected: bool = false

# 当前正在查看哪个普通店铺
var current_shop_id: String = ""

# 人参待使用数量

# ========== 记录当前打开的弹窗面板 ==========
var _current_popup: Control = null

# ========== 系列兑换子页面 ==========

# ========== 徒弟页面 ==========

# 提亲弹窗

# ===== 页面逻辑模块（第3批重构；_ready 中创建，页面经 c 共享本脚本） =====
var mansion_page   # 府邸页
var shop_page   # 商铺页（含钱庄面板/店员分配）
var hero_page   # 门客页（含门客面板/珍兽装备选择）
var bag_page   # 背包页（含道具使用/人参/门客盒子选择器）
var stage_page   # 关卡页
var beast_page   # 珍兽页（含详情/技能刷新/装备）
var friend_page   # 挚友页（含谈心/赠礼/店铺技能）
var apprentice_page   # 徒弟页（含培养/结业/联姻）
var adventure_page   # 闯荡页主视图
var exchange_view   # 闯荡-兑换子视图（门客/挚友/珍兽/系列）
var lottery_view   # 闯荡-抽奖子视图
var charity_view   # 闯荡-行善子视图
var travel_view   # 闯荡-游历子视图
var mall_panel   # 商城/充值/VIP弹窗
var player_panel   # 玩家信息/身份/每日奖励弹窗
var manor_view   # 庄园视图（第4批新增）
var courtyard_view   # 宅院视图（第7批新增，作为庄园第三页签）
var war_view   # 商战视图（第5批新增）
var fishing_view   # 垂钓视图（第8批新增）
var fish_equip_view   # 门客渔获装备弹窗（第8批新增）
var costume_view   # 【服装系统】服装视图

func _ready():
	#打印场景树
	print_scene_tree_to_file()

	randomize()
	data = GameData.new()

	# 【第3批重构】创建各页面逻辑模块（注入本脚本引用；页面内节点访问经 c.xxx）
	mansion_page = MansionPage.new(self)
	shop_page = ShopPage.new(self)
	hero_page = HeroPage.new(self)
	bag_page = BagPage.new(self)
	stage_page = StagePage.new(self)
	beast_page = BeastPage.new(self)
	friend_page = FriendPage.new(self)
	apprentice_page = ApprenticePage.new(self)
	adventure_page = AdventurePage.new(self)
	exchange_view = ExchangeView.new(self)
	lottery_view = LotteryView.new(self)
	charity_view = CharityView.new(self)
	travel_view = TravelView.new(self)
	mall_panel = MallPanel.new(self)
	player_panel = PlayerPanel.new(self)
	manor_view = ManorView.new(self)
	courtyard_view = CourtyardView.new(self)   # 【第7批新增】宅院页签内容
	war_view = WarView.new(self)
	fishing_view = FishingView.new(self)   # 【第8批新增】垂钓视图
	fish_equip_view = FishEquipView.new(self)   # 【第8批新增】渔获装备弹窗
	costume_view = CostumeView.new(self)
	data.load_game()  # ← 先读档

	# 计算离线收益
	var offline_income = data.calculate_offline_income()
	if offline_income > 0:
		data.money += offline_income
		print("离线收益: +", offline_income, "铜钱")
	
	# 庄园离线产量结算（100%产量，上限24小时；必须在更新 last_login_time 之前调用）
	data.settle_manor_offline()

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

	generate_apprentice_page()   # 【新增】徒弟页面
	#挚友页面
	generate_friend_page()

	print("信号连接完成")  # ← 加这行

	# 正常退出时存档
	tree_exiting.connect(on_exit)

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
	if has_node("PageContainer/ApprenticePage"): $PageContainer/ApprenticePage.visible = false

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
	#回到闯荡页面关闭各个子页面
	if page_id == "adventure": 
		hide_exchange_view()
		hide_lottery_view()
		hide_charity_view()
		hide_travel_view()
		hide_manor_view()
		hide_war_view() 
		hide_fishing_view()   # 【第8批新增】关闭垂钓子视图    
		update_adventure_page()
	
	if page_id == "apprentice": update_apprentice_page()
	
	if page_id == "beast": update_beast_page()
	
	if page_id == "friend": update_friend_page()
	# 高亮当前导航按钮（可选）
	style_nav_buttons()

func open_popup(panel: Control):
	_current_popup = panel
	panel.show()
	$Overlay.show()

func close_popup():
	if _current_popup != null:
		_current_popup.hide()
		_current_popup = null
	$Overlay.hide()

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

func on_auto_earn():
	data.money += data.get_total_auto_income()
	data.settle_manor()   # 【第4批新增】庄园每秒懒结算产量入仓库
	# 【第6批新增】每秒检查挚友目标，达成即自动解锁并弹提示（各玩法的计数钩子在 data 层，这里统一反馈）
	var unlocked = data.check_friend_goals()
	for fname in unlocked:
		_show_stage_hint("达成挚友目标，解锁挚友【%s】！" % fname, 4.0)
	# 【新增】一键贸易节拍：勾选期间每秒自动贸易一次；挂在本函数故离开关卡页也持续跑
	if data.stage_auto_trade:
		_on_stage_auto_trade_tick(data.stage_auto_trade_tick())
	update_all_ui()

# 【新增】一键贸易节拍结果处理：
# 途中节点提示（通关/Boss出现/谈判成功）只在玩家位于关卡页时弹出，不在则静默；
# 停止事件不立即弹——原因已写入 data.stage_auto_stop_reason，等玩家点进关卡页时由 update_stage_page 消费弹出
func _on_stage_auto_trade_tick(result: Dictionary):
	var event = result.get("event", "none")
	match event:
		"next_sub":
			# 通关小关发宝箱，同步背包显示；提示仅关卡页可见时弹（文案与手动贸易一致）
			update_bag_list()
			if current_page == "stage":
				_show_stage_hint("通关！宝箱×1  阅历+%d" % result.get("exp_reward", 0))
		"boss_ready":
			if current_page == "stage":
				_show_stage_hint("贸易完成，Boss 已出现！")
		"boss_win":
			# 进新章后刷新入口按钮（与手动谈判一致）
			update_entry_buttons()
			if current_page == "stage":
				_show_stage_hint("谈判成功！声望 +10，抽奖券 +1")
		"stop_money", "stop_power":
			# 玩家正好在关卡页时刷新页面，让 update_stage_page 立刻消费停止原因并弹出
			if current_page == "stage":
				update_stage_page()
	# 有实质进展且玩家正在关卡页时，刷新关卡页显示（标题/进度/按钮状态）
	if event != "none" and current_page == "stage":
		update_stage_page()

func _show_quantity_selector(item_id: String, title_text: String, on_confirm: Callable):
	_close_quantity_selector()
	_quantity_item_id = item_id
	
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

func on_money_plus_clicked():
	var count = data.items.get("hour_card", 0)
	if count <= 0:
		_show_stage_hint("没有小时卡，请前往商城购买")
		return
	_show_quantity_selector("hour_card", "使用小时卡", _on_item_use_confirmed)

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

func on_friend_page():
	switch_page("friend")
	update_friend_page()

func on_daily_task(): print("每日任务预留")

func on_beast():
	switch_page("beast")
	update_beast_page()

# 通用顶部提示弹窗（关卡/行善/兑换/庄园等结果提示共用）
# 修复记录①：原写死 position=Vector2(376,250) 且 Label 无自动换行，长文本会把弹窗向右撑出屏幕；
# 修复记录②：锚点居中方案在根节点未铺满视口时失效（框跑左边缘），改回绝对定位，
#            按视口宽度手动算居中 x + 按文本实际宽度在 400~560 间取宽并自动换行
func _show_stage_hint(text: String, auto_hide: float = 2.5):
	var panel = get_node_or_null("StageHint")
	var vbox: VBoxContainer
	var label: Label
	
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "StageHint"
		panel.custom_minimum_size = Vector2(400, 120)
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
		# 长文本自动换行（中文按字断行）
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	# 按文本实际宽度动态限宽：短提示维持原 400 宽，长提示限宽 560 并在该宽度内换行
	var font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font   # 兜底：主题未配字体时用引擎回退字体，防止空引用
	var text_w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	label.custom_minimum_size.x = clampf(text_w, 400, 560)
	# 水平居中：弹窗宽度≈label限宽（StyleBox无内边距），按视口宽度手动算 x，y固定250（每次显示重算）
	# （不能用锚点居中：根 Control 未铺满视口，锚点 0.5 会算到左边缘）
	panel.position = Vector2((get_viewport().get_visible_rect().size.x - label.custom_minimum_size.x) / 2, 250)
	
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

func on_apprentice():
	switch_page("apprentice")
	update_apprentice_page()

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

func _create_base_popup(title_text: String, popup_size: Vector2, pos: Vector2 = Vector2.ZERO) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = popup_size
	panel.position = pos if pos != Vector2.ZERO else (get_viewport_rect().size - popup_size) / 2
	panel.z_index = 30
	
	var style = StyleBoxFlat.new()
	# 【改】底色提亮一档（原 #1e1b2e 与全屏门客面板同色，弹窗会融进背景）
	style.bg_color = Color("#2a2640")
	style.set_corner_radius_all(12)
	# 【新增】2px 淡紫描边，弹窗边界一眼可辨（想换金色描边就改成 "#a8893f"）
	style.set_border_width_all(2)
	style.border_color = Color("#6a5f9e")
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

func print_scene_tree_to_file():
	var lines = []
	_collect_node_lines(get_tree().root, 0, lines)
	var file = FileAccess.open("res://scene_tree.txt", FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()
		# 打印绝对路径，方便直接去找文件
		print("场景树已导出：", ProjectSettings.globalize_path("user://scene_tree.txt"))
	else:
		push_error("场景树导出失败")

func _collect_node_lines(node: Node, depth: int, lines: Array):
	# 每深一层加两个空格缩进，同时标出节点类型和可见性
	var indent = ""
	for i in range(depth):
		indent += "  "
	var visible_txt = ""
	if node is CanvasItem:
		visible_txt = "  visible=%s" % str(node.visible)
	lines.append("%s%s (%s)%s" % [indent, node.name, node.get_class(), visible_txt])
	for child in node.get_children():
		_collect_node_lines(child, depth + 1, lines)

# ==================== 页面方法转发区 ====================
# ==================== 【转发】府邸页 → pages/mansion_page.gd ====================

func generate_mansion_list():
	return mansion_page.generate_mansion_list()

func update_mansion_list():
	return mansion_page.update_mansion_list()

# ==================== 【转发】商铺页（含钱庄面板/店员分配） → pages/shop_page.gd ====================

func generate_shop_list():
	return shop_page.generate_shop_list()

func on_shop_entry_pressed(shop_id: String):
	return shop_page.on_shop_entry_pressed(shop_id)

func _show_hero_assign_selector(slot: int):
	return shop_page._show_hero_assign_selector(slot)

func _close_assign_selector():
	return shop_page._close_assign_selector()

func _on_hero_assigned(hero_id: String, _slot: int):
	return shop_page._on_hero_assigned(hero_id, _slot)

func _on_hero_unassign(hero_id: String):
	return shop_page._on_hero_unassign(hero_id)

func open_hq_panel():
	return shop_page.open_hq_panel()

func close_hq_panel():
	return shop_page.close_hq_panel()

func open_shop_panel(shop_id: String):
	return shop_page.open_shop_panel(shop_id)

func close_shop_panel():
	return shop_page.close_shop_panel()

func on_hq_click():
	return shop_page.on_hq_click()

func on_hq_upgrade():
	return shop_page.on_hq_upgrade()

func on_current_shop_upgrade():
	return shop_page.on_current_shop_upgrade()

func on_current_shop_hire():
	return shop_page.on_current_shop_hire()

func _on_batch_hire_toggled(_pressed: bool):
	return shop_page._on_batch_hire_toggled(_pressed)

func update_entry_buttons():
	return shop_page.update_entry_buttons()

func update_hq_panel():
	return shop_page.update_hq_panel()

func update_shop_panel():
	return shop_page.update_shop_panel()

# ==================== 【转发】门客页（含门客面板/珍兽装备选择） → pages/hero_page.gd ====================

func generate_hero_list():
	return hero_page.generate_hero_list()

func _create_hero_card(hero_id: String, locked: bool) -> Button:
	return hero_page._create_hero_card(hero_id, locked)

func _on_locked_hero_clicked(hero_id: String):
	return hero_page._on_locked_hero_clicked(hero_id)

func open_hero_panel(hero_id: String):
	return hero_page.open_hero_panel(hero_id)

func close_hero_panel():
	return hero_page.close_hero_panel()

func update_hero_panel():
	return hero_page.update_hero_panel()

func on_hero_level_upgrade():
	return hero_page.on_hero_level_upgrade()

func on_hero_breakthrough():
	return hero_page.on_hero_breakthrough()

func _on_hero_beast_btn_clicked(beast_id: String, beast_idx: int):
	return hero_page._on_hero_beast_btn_clicked(beast_id, beast_idx)

func _show_beast_selector_for_hero():
	return hero_page._show_beast_selector_for_hero()

func _on_equip_beast_to_hero(beast_id: String, index: int):
	return hero_page._on_equip_beast_to_hero(beast_id, index)

func _on_hero_unequip_beast():
	return hero_page._on_hero_unequip_beast()

func on_aptitude_skill_upgrade(skill_index: int, mode: String = "single"):
	return hero_page.on_aptitude_skill_upgrade(skill_index, mode)

func on_shop_skill_upgrade(skill_index: int, mode: String = "single"):
	return hero_page.on_shop_skill_upgrade(skill_index, mode)

func on_promotion_upgrade(mode: String = "single"):
	return hero_page.on_promotion_upgrade(mode)

func open_hero_detail(hero_id: String):
	return hero_page.open_hero_detail(hero_id)

func update_hero_list():
	return hero_page.update_hero_list()

# ==================== 【转发】背包页（含道具使用/人参/门客盒子选择器） → pages/bag_page.gd ====================

func generate_bag_list():
	return bag_page.generate_bag_list()

func _on_item_use_confirmed(spin: SpinBox):
	return bag_page._on_item_use_confirmed(spin)

func update_bag_list():
	return bag_page.update_bag_list()

func _on_ginseng_confirmed(spin: SpinBox):
	return bag_page._on_ginseng_confirmed(spin)

func _show_ginseng_selector():
	return bag_page._show_ginseng_selector()

func _on_ginseng_target_selected(hero_id: String):
	return bag_page._on_ginseng_target_selected(hero_id)

func _close_ginseng_selector():
	return bag_page._close_ginseng_selector()

func _show_hero_box_selector():
	return bag_page._show_hero_box_selector()

func _on_hero_box_selected(hero_id: String):
	return bag_page._on_hero_box_selected(hero_id)

# ==================== 【转发】关卡页 → pages/stage_page.gd ====================

func generate_stage_page():
	return stage_page.generate_stage_page()

func update_stage_page():
	return stage_page.update_stage_page()

func on_stage_trade():
	return stage_page.on_stage_trade()

func on_stage_boss():
	return stage_page.on_stage_boss()

# ==================== 【转发】珍兽页（含详情/技能刷新/装备） → pages/beast_page.gd ====================

func _create_beast_card() -> Button:
	return beast_page._create_beast_card()

func generate_beast_page():
	return beast_page.generate_beast_page()

func update_beast_page():
	return beast_page.update_beast_page()

func open_beast_detail(beast_id: String, instance_index: int):
	return beast_page.open_beast_detail(beast_id, instance_index)

func _update_beast_detail(beast_id: String, instance_index: int):
	return beast_page._update_beast_detail(beast_id, instance_index)

func _on_beast_upgrade(beast_id: String, instance_index: int):
	return beast_page._on_beast_upgrade(beast_id, instance_index)

func _on_beast_equip_toggle(beast_id: String, instance_index: int):
	return beast_page._on_beast_equip_toggle(beast_id, instance_index)

func _show_hero_equip_selector(beast_id: String, instance_index: int):
	return beast_page._show_hero_equip_selector(beast_id, instance_index)

func _on_hero_equipped_beast(hero_id: String, beast_id: String, instance_index: int):
	return beast_page._on_hero_equipped_beast(hero_id, beast_id, instance_index)

func _on_beast_skill_clicked(skill_index: int):
	return beast_page._on_beast_skill_clicked(skill_index)

func _show_beast_skill_refresh_panel():
	return beast_page._show_beast_skill_refresh_panel()

func _update_beast_skill_refresh_panel():
	return beast_page._update_beast_skill_refresh_panel()

func _on_refresh_beast_skill():
	return beast_page._on_refresh_beast_skill()

func _close_beast_skill_refresh_panel():
	return beast_page._close_beast_skill_refresh_panel()

func _close_beast_detail():
	return beast_page._close_beast_detail()

# ==================== 【转发】挚友页（含谈心/赠礼/店铺技能） → pages/friend_page.gd ====================

func generate_friend_page():
	return friend_page.generate_friend_page()

func update_friend_page():
	return friend_page.update_friend_page()

func _create_friend_card(cname: String, friendly: int, talent: int, locked: bool) -> Button:
	return friend_page._create_friend_card(cname, friendly, talent, locked)

func show_friend_detail(friend_id: String):
	return friend_page.show_friend_detail(friend_id)

func hide_friend_detail():
	return friend_page.hide_friend_detail()

func _update_friend_page_detail():
	return friend_page._update_friend_page_detail()

func _on_shop_skill_clicked(skill_index: int):
	return friend_page._on_shop_skill_clicked(skill_index)

func _get_category_color(category: String) -> Color:
	return friend_page._get_category_color(category)

func _show_shop_skill_detail(skill_index: int):
	return friend_page._show_shop_skill_detail(skill_index)

func _close_shop_skill_detail():
	return friend_page._close_shop_skill_detail()

func _on_refresh_selected_skill():
	return friend_page._on_refresh_selected_skill()

func _update_shop_skill_detail():
	return friend_page._update_shop_skill_detail()

func _on_locked_friend_clicked(friend_id: String, vip_level: int):
	return friend_page._on_locked_friend_clicked(friend_id, vip_level)

func on_chat_with_friend():
	return friend_page.on_chat_with_friend()

func _show_energy_pill_prompt():
	return friend_page._show_energy_pill_prompt()

func _on_use_energy_pill(spin: SpinBox = null):
	return friend_page._on_use_energy_pill(spin)

func _show_chat_result(results: Array):
	return friend_page._show_chat_result(results)

func _on_friend_skill_upgrade(is_fixed: bool):
	return friend_page._on_friend_skill_upgrade(is_fixed)

func _upgrade_friend_fixed_batch(friend_id: String, batch: bool) -> int:
	return friend_page._upgrade_friend_fixed_batch(friend_id, batch)

func _upgrade_friend_percent_batch(friend_id: String, batch: bool) -> int:
	return friend_page._upgrade_friend_percent_batch(friend_id, batch)

func _show_play_selector():
	return friend_page._show_play_selector()

func _on_play_scenery():
	return friend_page._on_play_scenery()

func _on_play_poetry():
	return friend_page._on_play_poetry()

func _do_play_chat():
	return friend_page._do_play_chat()

func on_gift_friend():
	return friend_page.on_gift_friend()

func _show_gift_selector():
	return friend_page._show_gift_selector()

func _close_gift_selector():
	return friend_page._close_gift_selector()

func _on_gift_item_confirmed(spin: SpinBox, item_id: String):
	return friend_page._on_gift_item_confirmed(spin, item_id)

func _refresh_gift_selector():
	return friend_page._refresh_gift_selector()

# ==================== 【转发】徒弟页（含培养/结业/联姻） → pages/apprentice_page.gd ====================

func generate_apprentice_page():
	return apprentice_page.generate_apprentice_page()

func _on_apprentice_tab(tab: String):
	return apprentice_page._on_apprentice_tab(tab)

func update_apprentice_page():
	return apprentice_page.update_apprentice_page()

func _update_apprentice_train(content: VBoxContainer):
	return apprentice_page._update_apprentice_train(content)

func _update_apprentice_list_view(content: VBoxContainer, state: String):
	return apprentice_page._update_apprentice_list_view(content, state)

func _on_train_apprentice(slot: int):
	return apprentice_page._on_train_apprentice(slot)

func _handle_train_fail(slot: int, reason: String):
	return apprentice_page._handle_train_fail(slot, reason)

func _show_graduate_selector(slot: int):
	return apprentice_page._show_graduate_selector(slot)

func _on_graduate(slot: int, path: String):
	return apprentice_page._on_graduate(slot, path)

func _show_vitality_pill_prompt(slot: int):
	return apprentice_page._show_vitality_pill_prompt(slot)

func _on_use_vitality_pill(spin: SpinBox):
	return apprentice_page._on_use_vitality_pill(spin)

func _show_marriage_proposal(slot: int):
	return apprentice_page._show_marriage_proposal(slot)

func _on_marry_apprentice():
	return apprentice_page._on_marry_apprentice()

# ==================== 【转发】闯荡页主视图 → pages/adventure_page.gd ====================

func generate_adventure_page():
	return adventure_page.generate_adventure_page()

func update_adventure_page():
	return adventure_page.update_adventure_page()

# ==================== 【转发】闯荡-兑换子视图（门客/挚友/珍兽/系列） → pages/exchange_view.gd ====================

func _on_exchange_back_pressed():
	return exchange_view._on_exchange_back_pressed()

func show_exchange_view():
	return exchange_view.show_exchange_view()

func hide_exchange_view():
	return exchange_view.hide_exchange_view()

func show_beast_exchange_view():
	return exchange_view.show_beast_exchange_view()

func hide_beast_exchange_view():
	return exchange_view.hide_beast_exchange_view()

func update_beast_exchange_view():
	return exchange_view.update_beast_exchange_view()

func _create_beast_exchange_card(beast_id: String) -> Button:
	return exchange_view._create_beast_exchange_card(beast_id)

func show_token_exchange_view():
	return exchange_view.show_token_exchange_view()

func hide_token_exchange_view():
	return exchange_view.hide_token_exchange_view()

func update_token_exchange_view():
	return exchange_view.update_token_exchange_view()

func _add_exchange_section_title(list: VBoxContainer, text: String):
	return exchange_view._add_exchange_section_title(list, text)

func _add_role_exchange_grid(list: VBoxContainer, role_type: String, entries: Array):
	return exchange_view._add_role_exchange_grid(list, role_type, entries)

func _create_role_exchange_card(role_type: String, role_id: String, cost: int) -> Button:
	return exchange_view._create_role_exchange_card(role_type, role_id, cost)

func show_series_exchange_view(series_index: int):
	return exchange_view.show_series_exchange_view(series_index)

func hide_series_exchange_view():
	return exchange_view.hide_series_exchange_view()

func update_series_exchange_view():
	return exchange_view.update_series_exchange_view()

func _create_series_exchange_card(entry: Dictionary, series: Dictionary) -> Button:
	return exchange_view._create_series_exchange_card(entry, series)

func _on_exchange_series_hero(entry: Dictionary, series: Dictionary):
	return exchange_view._on_exchange_series_hero(entry, series)

func _on_exchange_role(role_type: String, role_id: String, cost: int):
	return exchange_view._on_exchange_role(role_type, role_id, cost)

func _on_exchange_beast(beast_id: String):
	return exchange_view._on_exchange_beast(beast_id)

# ==================== 【转发】闯荡-抽奖子视图 → pages/lottery_view.gd ====================

func show_lottery_view():
	return lottery_view.show_lottery_view()

func hide_lottery_view():
	return lottery_view.hide_lottery_view()

func update_lottery_view():
	return lottery_view.update_lottery_view()

func on_lottery_draw(draw_count: int, ticket_need: int):
	return lottery_view.on_lottery_draw(draw_count, ticket_need)

func _do_lottery_draw(draw_count: int, ticket_need: int, use_yuanbao: bool):
	return lottery_view._do_lottery_draw(draw_count, ticket_need, use_yuanbao)

func _show_lottery_confirm(draw_count: int, ticket_need: int, ticket_have: int):
	return lottery_view._show_lottery_confirm(draw_count, ticket_need, ticket_have)

func _show_lottery_results(results: Array):
	return lottery_view._show_lottery_results(results)

# ==================== 【转发】闯荡-行善子视图 → pages/charity_view.gd ====================

func show_charity_view():
	return charity_view.show_charity_view()

func hide_charity_view():
	return charity_view.hide_charity_view()

func update_charity_view():
	return charity_view.update_charity_view()

func _on_charity():
	return charity_view._on_charity()

# ==================== 【转发】闯荡-游历子视图 → pages/travel_view.gd ====================

func show_travel_view():
	return travel_view.show_travel_view()

func hide_travel_view():
	return travel_view.hide_travel_view()

func update_travel_view():
	return travel_view.update_travel_view()

func _on_travel():
	return travel_view._on_travel()

func _refresh_travel_header():
	return travel_view._refresh_travel_header()

# ==================== 【转发】商城/充值/VIP弹窗 → pages/mall_panel.gd ====================

func on_mall():
	return mall_panel.on_mall()

func _on_buy_mall_pack(pack: Dictionary):
	return mall_panel._on_buy_mall_pack(pack)

func _close_mall_panel():
	return mall_panel._close_mall_panel()

func _on_buy_test_beast_pack():
	return mall_panel._on_buy_test_beast_pack()

func on_recharge():
	return mall_panel.on_recharge()

func _on_tab_normal_pressed():
	return mall_panel._on_tab_normal_pressed()

func _on_tab_daily_pressed():
	return mall_panel._on_tab_daily_pressed()

func _on_tab_special_pressed():
	return mall_panel._on_tab_special_pressed()

func _switch_recharge_tab(tab: String):
	return mall_panel._switch_recharge_tab(tab)

func _update_recharge_page():
	return mall_panel._update_recharge_page()

func _update_special_pack_page():
	return mall_panel._update_special_pack_page()

func _on_buy_special_pack(pack: Dictionary):
	return mall_panel._on_buy_special_pack(pack)

func _update_daily_gift_page():
	return mall_panel._update_daily_gift_page()

func _on_daily_gift_buy():
	return mall_panel._on_daily_gift_buy()

func _show_daily_gift_success():
	return mall_panel._show_daily_gift_success()

func _on_recharge_confirmed(amount: int):
	return mall_panel._on_recharge_confirmed(amount)

func _show_recharge_success(amount: int):
	return mall_panel._show_recharge_success(amount)

func on_vip():
	return mall_panel.on_vip()

func _update_vip_panel():
	return mall_panel._update_vip_panel()

func _on_claim_vip_reward(level: int):
	return mall_panel._on_claim_vip_reward(level)

# 打开挚友目标弹窗
func on_friend_goals():
	return mansion_page.show_friend_goals_popup()

# ==================== 【转发】玩家信息/身份/每日奖励弹窗 → pages/player_panel.gd ====================

func open_player_panel():
	return player_panel.open_player_panel()

func _update_identity_reward_list():
	return player_panel._update_identity_reward_list()

func _on_claim_identity_reward(level: int):
	return player_panel._on_claim_identity_reward(level)

func _close_player_panel():
	return player_panel._close_player_panel()

func _on_rename_confirmed(input: LineEdit):
	return player_panel._on_rename_confirmed(input)

func _on_promote_identity():
	return player_panel._on_promote_identity()

func _on_claim_daily_reward():
	return player_panel._on_claim_daily_reward()

# ==================== 【转发】庄园视图 → pages/manor_view.gd ====================

# 在闯荡页注入庄园入口按钮与子视图（由 adventure_page 构建时调用）
func build_manor_view(page, vbox):
	return manor_view.build_manor_view(page, vbox)

# 打开庄园
func show_manor_view():
	return manor_view.show_manor_view()

# 返回闯荡主页
func hide_manor_view():
	return manor_view.hide_manor_view()

# 刷新庄园界面
func update_manor_view():
	return manor_view.update_manor_view()

# 刷新宅院页签列表（由 ManorView 在切到“宅院”时调用）
func update_courtyard_view(list: VBoxContainer):
	return courtyard_view.update_courtyard_view(list)

# ==================== 【转发】商战视图 → pages/war_view.gd ====================

# 在闯荡页注入商战入口按钮与子视图（由 adventure_page 构建时调用）
func build_war_view(page, vbox):
	return war_view.build_war_view(page, vbox)

# 打开商战
func show_war_view():
	return war_view.show_war_view()

# 返回闯荡主页
func hide_war_view():
	return war_view.hide_war_view()

# 刷新商战界面
func update_war_view():
	return war_view.update_war_view()

# ==================== 【转发】垂钓视图 → pages/fishing_view.gd（第8批新增） ====================

# 在闯荡页注入垂钓入口按钮与子视图（由 adventure_page 构建时调用）
func build_fishing_view(page, vbox):
	return fishing_view.build_fishing_view(page, vbox)

# 打开垂钓
func show_fishing_view():
	return fishing_view.show_fishing_view()

# 返回闯荡主页
func hide_fishing_view():
	return fishing_view.hide_fishing_view()

# 打开门客渔获装备弹窗（由 hero_page 渔获按钮触发）
func show_fish_equip_view(hero_id: String):
	return fish_equip_view.show_fish_equip_view(hero_id)
