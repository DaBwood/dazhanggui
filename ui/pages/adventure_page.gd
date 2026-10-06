# ============================================================
# 闯荡页主视图（第3批重构：从 game_controller.gd 拆分而来；最近批次见档案 §十一）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name AdventurePage
extends RefCounted
# 场景化骨架契约（规范 11.1/11.2）：布局唯一真相源=adventure_page.tscn，本脚本只实例化+灌内容
const ADVENTURE_SCENE := preload("res://ui/pages/adventure_page.tscn")
# 素材契约：横版地图放 res://assets/adventure/bg.png（2048×1152 原图直接用，按 1067 高铺宽≈1897≈3.16 屏，零裁切）
const ADVENTURE_BG_PATH := "res://assets/adventure/bg.png"
# 地图入口钮摆位：归一化坐标对照带字版招牌标注（2026-10-06），x/y 相对 MapContent 1897×1067；随时可调
const MAP_ENTRY_POS := {
	"关卡": Vector2(0.458, 0.80), "兑换": Vector2(0.730, 0.42), "抽奖": Vector2(0.155, 0.50),
	"行善": Vector2(0.590, 0.41), "游历": Vector2(0.460, 0.26), "招商": Vector2(0.315, 0.82),
	"商战": Vector2(0.305, 0.66), "垂钓": Vector2(0.210, 0.47), "庄园": Vector2(0.160, 0.24),
	"促织园": Vector2(0.430, 0.64), "商会": Vector2(0.305, 0.41),
}
# 地图钮统一尺寸（内容节点=脚本资产，允许定布局；建筑热点牌匾口径 150×52/16 号字）
const MAP_ENTRY_SIZE := Vector2(150, 52)
# 按钮文字→锚点英文名：节点名保持 ASCII（中文节点名在部分工程链路触发 Latin-1 编码报错，2026-10-06 实测）
const ENTRY_ANCHOR := {
	"关卡": "PosStage", "兑换": "PosExchange", "抽奖": "PosLottery", "行善": "PosCharity",
	"游历": "PosTravel", "招商": "PosZhaoshang", "商战": "PosWar", "垂钓": "PosFishing",
	"庄园": "PosManor", "促织园": "PosCuzhi", "商会": "PosGuild",
}


var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用
var guild_view # 【新增】商会视图

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

# 子视图顶排统一规范（用户拍板 2026-10-06）：< 返回(左)+玩法标题(中,金)+？(右,弹玩法说明)
func _adv_top_row(view: Control, back_callable: Callable, title_text: String, help_text: String) -> Label:
	var row := HBoxContainer.new()
	row.name = "TopRow"
	row.add_theme_constant_override("separation", 8)
	view.add_child(row)
	var back := Button.new()
	back.text = "< 返回"
	back.pressed.connect(back_callable)
	row.add_child(back)
	var title := _adv_title_row(row, "TopTitle", help_text)
	title.text = title_text
	return title

# 系列页等无独立返回的视图用：标题(中)+？(右)，标题名可定制（SeriesTitle 为外部动态改文案的约定节点名）
func _adv_title_row(row: Control, title_name: String, help_text: String) -> Label:
	var title := Label.new()
	title.name = title_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title.add_theme_font_size_override("font_size", 20)
	row.add_child(title)
	var help := Button.new()
	help.text = "?"
	help.custom_minimum_size = Vector2(40, 36)
	help.add_theme_font_size_override("font_size", 16)
	help.pressed.connect(func(): _show_adventure_help(help_text))
	row.add_child(help)
	return title

func _show_adventure_help(help_text: String):
	var popup = c._create_base_popup("玩法说明", Vector2(440, 0), Vector2.ZERO, false)
	var vb = popup.get_child(0)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = help_text
	vb.add_child(lbl)
	c.add_child(popup)

func generate_adventure_page():
	if not c.has_node("PageContainer/AdventurePage"): return
	var page = c.get_node("PageContainer/AdventurePage")
	
	for child in page.get_children():
		child.free()

	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)

	var inst: Control = ADVENTURE_SCENE.instantiate()
	page.add_child(inst)

	# 结构硬校验：缺件即报错中断（用户拍板 2026-10-06 废兜底自愈——结构正确时冗余、错误时掩盖真因；
	# fail-loud 优于静默恢复，报错信息直接给出缺失路径）
	var vbox := inst.get_node("AdventureVBox") as VBoxContainer
	var map_scroll := vbox.get_node("MapScroll") as ScrollContainer
	var map_content := map_scroll.get_node("MapContent") as Control
	var entry_grid := map_content.get_node("AdventureEntryGrid") as Control
	_map_scroll = map_scroll

	# 主页面玩法说明"？"钮在 tscn 右上角锚定（用户拍板 2026-10-06），脚本只接管信号
	var main_help := inst.get_node("MainHelpButton") as Button
	main_help.pressed.connect(func(): _show_adventure_help("闯荡是各玩法的入口：关卡产出闯荡币；兑换/系列/抽奖/行善/游历玩法各异，每个子页右上角都有？说明。左右滑动地图切换城区。"))

	# 底图契约见 ADVENTURE_BG_PATH 注释：缺图不渲染、布局不塌
	var bg := map_content.get_node("BgImage") as TextureRect
	if ResourceLoader.exists(ADVENTURE_BG_PATH):
		bg.texture = load(ADVENTURE_BG_PATH)

	# 滑动吸附：scroll_ended 只在用户滚动停时发（补间改值不重入，_map_snapping 双保险）
	map_scroll.scroll_ended.connect(_on_map_scroll_ended)

	var stage_btn = Button.new()
	stage_btn.text = "关卡"
	stage_btn.custom_minimum_size = Vector2(180, 60)
	stage_btn.pressed.connect(c.switch_page.bind("stage"))
	entry_grid.add_child(stage_btn)
	
	var exchange_btn = Button.new()
	exchange_btn.name = "ExchangeBtn"
	exchange_btn.text = "兑换"
	exchange_btn.custom_minimum_size = Vector2(180, 60)
	exchange_btn.pressed.connect(c.show_view.bind("exchange"))
	entry_grid.add_child(exchange_btn)
	
	# 兑换子页面（目录：珍兽兑换 / 门客帖兑换）
	var exchange_view = VBoxContainer.new()
	exchange_view.name = "ExchangeView"
	exchange_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	exchange_view.visible = false
	exchange_view.add_theme_constant_override("separation", 12)
	page.add_child(exchange_view)
	
	_adv_top_row(exchange_view, c._on_exchange_back_pressed, "兑换", "用闯荡币兑换珍兽、令牌与系列奖励；各系列累计的兑换进度通用。")
	
	# 入口按钮区
	var entry_box = VBoxContainer.new()
	entry_box.name = "ExchangeEntryBox"
	entry_box.alignment = BoxContainer.ALIGNMENT_CENTER
	entry_box.add_theme_constant_override("separation", 20)
	entry_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	exchange_view.add_child(entry_box)
	
	# 3列网格放所有入口，防止按钮太多溢出
	var excg_entry_grid = GridContainer.new()
	excg_entry_grid.columns = 3
	excg_entry_grid.add_theme_constant_override("h_separation", 16)
	excg_entry_grid.add_theme_constant_override("v_separation", 16)
	excg_entry_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	entry_box.add_child(excg_entry_grid)
	
	var beast_entry_btn = Button.new()
	beast_entry_btn.text = "珍兽兑换"
	beast_entry_btn.custom_minimum_size = Vector2(180, 60)
	beast_entry_btn.pressed.connect(c.show_beast_exchange_view)
	excg_entry_grid.add_child(beast_entry_btn)
	
	var token_entry_btn = Button.new()
	token_entry_btn.text = "门客帖兑换"
	token_entry_btn.custom_minimum_size = Vector2(180, 60)
	token_entry_btn.pressed.connect(c.show_token_exchange_view)
	excg_entry_grid.add_child(token_entry_btn)
	
	# 系列兑换入口（配置表驱动，加系列只改 game_data 的表）
	for i in range(data.SERIES_EXCHANGE.size()):
		var s_btn = Button.new()
		s_btn.text = data.SERIES_EXCHANGE[i].series
		s_btn.custom_minimum_size = Vector2(180, 60)
		s_btn.pressed.connect(c.show_series_exchange_view.bind(i))
		excg_entry_grid.add_child(s_btn)
	
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
	
	var series_top := HBoxContainer.new()
	series_top.name = "TopRow"
	series_top.add_theme_constant_override("separation", 8)
	series_view.add_child(series_top)
	_adv_title_row(series_top, "SeriesTitle", "完成系列关卡任务领取系列点；系列点跨系列通用，在兑换页消费。")
	
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
	lottery_btn.custom_minimum_size = Vector2(180, 60)
	lottery_btn.pressed.connect(c.show_view.bind("lottery"))
	entry_grid.add_child(lottery_btn)
	
	# --- 抽奖子页面 ---
	var lottery_view = VBoxContainer.new()
	lottery_view.name = "LotteryView"
	lottery_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	lottery_view.visible = false
	lottery_view.add_theme_constant_override("separation", 16)
	page.add_child(lottery_view)
	
	_adv_top_row(lottery_view, c.hide_view.bind("lottery"), "抽奖", "消耗抽奖券抽取奖励：单抽、十连、百连依档九折。")
	
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
	charity_btn.custom_minimum_size = Vector2(180, 60)
	charity_btn.pressed.connect(c.show_view.bind("charity"))
	entry_grid.add_child(charity_btn)
	
	# --- 行善子页面 ---
	var charity_view = VBoxContainer.new()
	charity_view.name = "CharityView"
	charity_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	charity_view.visible = false
	charity_view.add_theme_constant_override("separation", 12)
	page.add_child(charity_view)
	
	_adv_top_row(charity_view, c.hide_view.bind("charity"), "行善", "在各地点行善积累进度，进度达标领奖；勾选十连批量行善。")
	
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
	travel_btn.custom_minimum_size = Vector2(180, 60)
	travel_btn.pressed.connect(c.show_view.bind("travel"))
	entry_grid.add_child(travel_btn)

	# 招商入口（闯荡页第 6 钮；全屏页 z35 走 VIEW_LIST 分发）
	var zhaoshang_btn = Button.new()
	zhaoshang_btn.text = "招商"
	zhaoshang_btn.custom_minimum_size = Vector2(180, 60)
	zhaoshang_btn.pressed.connect(c.show_view.bind("zhaoshang"))
	entry_grid.add_child(zhaoshang_btn)
	
	# --- 【新增】游历子页面 ---
	var travel_view = VBoxContainer.new()
	travel_view.name = "TravelView"
	travel_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	travel_view.visible = false
	travel_view.add_theme_constant_override("separation", 12)
	page.add_child(travel_view)
	
	_adv_top_row(travel_view, c.hide_view.bind("travel"), "游历", "游历消耗体力，获得声望与随机奖励。")
	
	# 体力/声望显示
	var t_info = Label.new()
	t_info.name = "TravelInfo"
	t_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	travel_view.add_child(t_info)
	
	# 月老/观音祝福层数显示
	var t_buff = Label.new()
	t_buff.name = "TravelBuffInfo"
	t_buff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_buff.add_theme_font_size_override("font_size", 16)
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
	
	# 【第5批新增】商战入口与子视图（构建逻辑在 pages/war_view.gd，此处仅挂接）
	c.build_war_view(page, vbox)
	
	# 【第8批新增】垂钓入口与子视图（构建逻辑在 pages/fishing_view.gd，此处仅挂接）
	c.build_fishing_view(page, vbox)
	
	#促织入口
	c.build_cuzhi_view(page,vbox)
	
	# 【新增】商会入口（覆盖层挂在闯荡页上，GuildView 自管理开闭，controller 零改动）
	guild_view = GuildView.new(c)
	guild_view.build_entry(page, vbox)

	# 全部入口（含 5 个 builder 挂的）就绪后统一按地图坐标摆位
	_layout_map_entries(map_content, entry_grid)

	# 结构自检：输出面板打印一次关键事实（布局争议先看这里，定位是结构问题还是坐标问题）
	print("[AdventureMap] 入口钮=%d 横向滚动余量=%d MapContent=%s" % [
		entry_grid.get_child_count(),
		int(map_scroll.get_h_scroll_bar().max_value - map_scroll.get_h_scroll_bar().page),
		str(map_content.size)])

# 入口摆位：优先读 tscn 里的 Marker2D 锚点（"Pos"+按钮文字，编辑器里可拖着摆）；
# 锚点缺失时退化到 MAP_ENTRY_POS 归一化表；都未收录的新入口退图下备用排，不丢功能只丢精修
func _layout_map_entries(map_content: Control, entry_grid: Control) -> void:
	var map_w := map_content.custom_minimum_size.x
	var map_h := map_content.custom_minimum_size.y
	var reserve_i := 0
	for node in entry_grid.get_children():
		if not (node is Button):
			continue
		node.custom_minimum_size = MAP_ENTRY_SIZE
		node.size = MAP_ENTRY_SIZE
		var center := Vector2(-1, -1)
		var anchor: Node2D = null
		if ENTRY_ANCHOR.has(node.text):
			anchor = entry_grid.get_node_or_null(ENTRY_ANCHOR[node.text]) as Node2D
		if anchor:
			center = anchor.position
		elif MAP_ENTRY_POS.has(node.text):
			var pos: Vector2 = MAP_ENTRY_POS[node.text]
			center = Vector2(pos.x * map_w, pos.y * map_h)
		else:
			center = Vector2((0.10 + reserve_i * 0.09) * map_w, 0.90 * map_h)
			reserve_i += 1
		node.position = center - MAP_ENTRY_SIZE / 2.0

var _map_snapping := false
var _map_scroll: ScrollContainer = null

# 横向地图按屏吸附：页宽=滚动视口宽（运行时实际像素，不吃设计尺寸）；滚动器引用由 generate 注入
func _on_map_scroll_ended() -> void:
	if _map_snapping or _map_scroll == null:
		return
	var page_w := _map_scroll.size.x
	if page_w <= 0:
		return
	var target := int(roundf(_map_scroll.scroll_horizontal / page_w) * page_w)
	if abs(target - _map_scroll.scroll_horizontal) < 2:
		return
	_map_snapping = true
	var tw := _map_scroll.create_tween()
	tw.tween_property(_map_scroll, "scroll_horizontal", target, 0.25)
	tw.finished.connect(func(): _map_snapping = false)

func update_adventure_page():
	# 页面静态，无需动态更新
	pass
