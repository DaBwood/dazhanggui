# ============================================================
# 闯荡页主视图（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name AdventurePage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_adventure_page():
	if not c.has_node("PageContainer/AdventurePage"): return
	var page = c.get_node("PageContainer/AdventurePage")
	
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
	stage_btn.pressed.connect(c.switch_page.bind("stage"))
	vbox.add_child(stage_btn)
	
	var exchange_btn = Button.new()
	exchange_btn.name = "ExchangeBtn"
	exchange_btn.text = "兑换"
	exchange_btn.custom_minimum_size = Vector2(240, 60)
	exchange_btn.pressed.connect(c.show_exchange_view)
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
	back_btn.pressed.connect(c._on_exchange_back_pressed)
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
	beast_entry_btn.pressed.connect(c.show_beast_exchange_view)
	entry_grid.add_child(beast_entry_btn)
	
	var token_entry_btn = Button.new()
	token_entry_btn.text = "门客帖兑换"
	token_entry_btn.custom_minimum_size = Vector2(240, 60)
	token_entry_btn.pressed.connect(c.show_token_exchange_view)
	entry_grid.add_child(token_entry_btn)
	
	# 系列兑换入口（配置表驱动，加系列只改 game_data 的表）
	for i in range(data.SERIES_EXCHANGE.size()):
		var s_btn = Button.new()
		s_btn.text = data.SERIES_EXCHANGE[i].series
		s_btn.custom_minimum_size = Vector2(240, 60)
		s_btn.pressed.connect(c.show_series_exchange_view.bind(i))
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
	lottery_btn.pressed.connect(c.show_lottery_view)
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
	lot_back_btn.pressed.connect(c.hide_lottery_view)
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
	single_btn.pressed.connect(c.on_lottery_draw.bind(1, 1))
	lot_btn_box.add_child(single_btn)
	
	var ten_btn = Button.new()
	ten_btn.name = "LotteryTenBtn"
	ten_btn.text = "十连抽\n9抽奖券"
	ten_btn.custom_minimum_size = Vector2(140, 80)
	ten_btn.pressed.connect(c.on_lottery_draw.bind(10, 9))
	lot_btn_box.add_child(ten_btn)
	
	var hundred_btn = Button.new()
	hundred_btn.name = "LotteryHundredBtn"
	hundred_btn.text = "百连抽\n90抽奖券"
	hundred_btn.custom_minimum_size = Vector2(140, 80)
	hundred_btn.pressed.connect(c.on_lottery_draw.bind(100, 90))
	lot_btn_box.add_child(hundred_btn)
	
	var lot_result_scroll = ScrollContainer.new()
	lot_result_scroll.custom_minimum_size = Vector2(0, 200)
	lottery_view.add_child(lot_result_scroll)
	
	var lot_result_list = VBoxContainer.new()
	lot_result_list.name = "LotteryResultList"
	lot_result_scroll.add_child(lot_result_list)
	
	# --- 行善入口 ---
	var charity_btn = Button.new()
	charity_btn.text = "行善"
	charity_btn.custom_minimum_size = Vector2(240, 60)
	charity_btn.pressed.connect(c.show_charity_view)
	vbox.add_child(charity_btn)
	
	# --- 行善子页面 ---
	var charity_view = VBoxContainer.new()
	charity_view.name = "CharityView"
	charity_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	charity_view.visible = false
	charity_view.add_theme_constant_override("separation", 12)
	page.add_child(charity_view)
	
	var c_back = Button.new()
	c_back.text = "< 返回闯荡"
	c_back.pressed.connect(c.hide_charity_view)
	charity_view.add_child(c_back)
	
	var c_info = Label.new()
	c_info.name = "CharityInfo"
	c_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charity_view.add_child(c_info)
	
	var c_op = HBoxContainer.new()
	c_op.name = "CharityOpBox"
	c_op.alignment = BoxContainer.ALIGNMENT_CENTER
	c_op.add_theme_constant_override("separation", 12)
	charity_view.add_child(c_op)
	
	var c_btn = Button.new()
	c_btn.name = "CharityBtn"
	c_btn.custom_minimum_size = Vector2(240, 60)
	c_btn.pressed.connect(c._on_charity)
	c_op.add_child(c_btn)
	
	var c_check = CheckBox.new()
	c_check.name = "CharityBatchCheck"
	c_check.text = "十连"
	c_op.add_child(c_check)
	
	# 五个地点进度列表（scroll双向填充，内容只横向填充）
	var c_scroll = ScrollContainer.new()
	c_scroll.name = "CharityScroll"
	c_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	charity_view.add_child(c_scroll)
	
	var c_list = VBoxContainer.new()
	c_list.name = "CharityList"
	c_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c_list.add_theme_constant_override("separation", 8)
	c_scroll.add_child(c_list)
	
	# --- 【新增】游历入口（与行善并列） ---
	var travel_btn = Button.new()
	travel_btn.text = "游历"
	travel_btn.custom_minimum_size = Vector2(240, 60)
	travel_btn.pressed.connect(c.show_travel_view)
	vbox.add_child(travel_btn)
	
	# --- 【新增】游历子页面 ---
	var travel_view = VBoxContainer.new()
	travel_view.name = "TravelView"
	travel_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	travel_view.visible = false
	travel_view.add_theme_constant_override("separation", 12)
	page.add_child(travel_view)
	
	var t_back = Button.new()
	t_back.text = "< 返回闯荡"
	t_back.pressed.connect(c.hide_travel_view)
	travel_view.add_child(t_back)
	
	# 体力/声望显示
	var t_info = Label.new()
	t_info.name = "TravelInfo"
	t_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	travel_view.add_child(t_info)
	
	# 月老/观音祝福层数显示
	var t_buff = Label.new()
	t_buff.name = "TravelBuffInfo"
	t_buff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_buff.add_theme_font_size_override("font_size", 14)
	travel_view.add_child(t_buff)
	
	# 游历按钮
	var t_btn = Button.new()
	t_btn.name = "TravelBtn"
	t_btn.text = "游历（-1体力，+20声望）"
	t_btn.custom_minimum_size = Vector2(240, 60)
	t_btn.pressed.connect(c._on_travel)
	travel_view.add_child(t_btn)
	
	# 本次游历结果
	var t_result = Label.new()
	t_result.name = "TravelResult"
	t_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t_result.add_theme_color_override("font_color", Color("#ffd700"))
	travel_view.add_child(t_result)
	
	# 表2挚友好感进度列表（scroll双向填充，内容只横向填充）
	var t_title = Label.new()
	t_title.text = "—— 好感解锁挚友 ——"
	t_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_title.add_theme_font_size_override("font_size", 18)
	t_title.add_theme_color_override("font_color", Color("#ffd700"))
	travel_view.add_child(t_title)
	
	var t_scroll = ScrollContainer.new()
	t_scroll.name = "TravelScroll"
	t_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	travel_view.add_child(t_scroll)
	
	var t_list = VBoxContainer.new()
	t_list.name = "TravelList"
	t_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_list.add_theme_constant_override("separation", 8)
	t_scroll.add_child(t_list)
	
	# 【第4批新增】庄园入口与子视图（构建逻辑在 pages/manor_view.gd，此处仅挂接）
	c.build_manor_view(page, vbox)

func update_adventure_page():
	# 页面静态，无需动态更新
	pass
