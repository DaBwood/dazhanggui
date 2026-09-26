# ============================================================
# 《大掌柜》主控制器（第3批重构版）
# 职责：场景根脚本——初始化/信号连接/页面切换导航/TopBar/弹窗工厂/共享UI工具
#       + 持有15个页面模块并转发其方法（节点路径/弹窗语义与原单文件完全一致）
# ============================================================
extends Control

const AUTOSAVE_INTERVAL = 30   # 【新增】自动存档间隔（秒）：on_auto_earn 每秒计数，满即写盘

var data: GameData 

#页面切换
var current_page: String = "shop"   # shop / hero / bag

@warning_ignore("unused_private_class_variable")
var _quantity_item_id: String = ""   # 数量选择器当前操作的道具ID

# 【新增】自动存档计数（秒）
var _autosave_sec: int = 0
# 【新增】Web 端页面隐藏回调引用（JavaScriptBridge 回调是 RefCounted，必须持有引用否则被释放后回调失效）
var _web_hide_cb = null
#按钮信号连接
var _signals_connected: bool = false

# 当前正在查看哪个普通店铺
var current_shop_id: String = ""

# 人参待使用数量

# ========== 记录当前打开的弹窗面板 ==========
var _current_popup: Control = null

var net: NetSystem   # 【新增】网络层（云存档）
var net_ui: NetUi   # 【新增】网络/登录/云存档 UI 块（2026-09-19 重构批次A迁出至 ui/net_ui.gd；net 相关信号直连 net_ui）
var ui_helpers: UiHelpers   # 【新增】UI 助手设施（2026-09-19 重构批次B迁出至 ui/ui_helpers.gd；controller 留同名委托，150+ 处调用零改动）
var _game_entered := false   # 【新增】是否已进入游戏（过登录门才初始化，只进一次）
# ========== 徒弟页面 ==========

var _bars_visible = true  # 【新增】顶栏/底栏显隐状态位：二级页（挚友详情）全屏时=false，_apply_portrait_layout 重排时尊重它

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
var soul_view   # 【新增】兽魂视图（珍兽魂盘+魂石镶嵌）
var soulpower_view   # 【新增】魂力培养视图（珍兽魂体+魂骨装配）
var cuzhi_view   # 【促织园】闯荡子视图
var collection_view   # 【新增】藏品视图（府邸入口全屏页）
var bank_view   # 【新增】钱庄玩法视图（商铺地图钱庄「▶」入口全屏页）
var mail_view   # 【新增】邮件视图（府邸入口全屏页）
var inn_view   # 【新增】客栈玩法视图（商铺地图客栈「▶」入口全屏页）
var clinic_view   # 【新增】医馆玩法视图（商铺地图医馆「▶」入口全屏页）
var drugshop_view   # 【新增】药铺玩法视图（商铺地图药铺「▶」入口全屏页）
var tavern_view   # 【新增】酒肆玩法视图（商铺地图酒肆店铺「▶」入口全屏页，按名字挂不按位置）
var winery_view   # 【新增】酒坊玩法视图（商铺地图酒坊「▶」入口全屏页）
var miaoyin_view   # 【新增】妙音坊玩法视图（商铺地图妙音坊「▶」入口全屏页）
var xiangfang_view   # 【新增】厢房视图（府邸「厢房」入口全屏页，Page z35/弹窗 z40 照 BaseView 新模式）

# ==================== 【新增】视图注册清单（2026-09-18 架构重构批次②） ====================
# 一条 = var 成员名 + 脚本路径 + 通用入口 key；_ready 由本清单循环实例化。
# 新视图接入 = var 声明一行 + 本清单一条，不再手写 XxxView.new(self)。
# key 约定 = 视图内 show_<key>_view / hide_<key>_view 的方法名中段，
#  show_view(key)/hide_view(key) 通用入口按此约定分发；带参视图用 show_view(key, [参数])。
# ⚠️ 仅登记实例化、不走通用入口：courtyard（庄园页签内容，无独立 show/hide）、
#    costume（页面直调 c.costume_view.show_xxx_popup）、
#    soul/soulpower（beast_page 直调 c.soul_view.show_soul_view / c.soulpower_view.show_hunli_view）
# ⚠️ mall_panel/player_panel 是弹窗面板非视图，不进清单，仍手写实例化
const VIEW_LIST: Array = [
	{"var": "exchange_view", "script": "res://ui/pages/exchange_view.gd", "key": "exchange"},
	{"var": "lottery_view", "script": "res://ui/pages/lottery_view.gd", "key": "lottery"},
	{"var": "charity_view", "script": "res://ui/pages/charity_view.gd", "key": "charity"},
	{"var": "travel_view", "script": "res://ui/pages/travel_view.gd", "key": "travel"},
	{"var": "manor_view", "script": "res://ui/pages/manor_view.gd", "key": "manor"},
	{"var": "courtyard_view", "script": "res://ui/pages/courtyard_view.gd", "key": "courtyard"},
	{"var": "war_view", "script": "res://ui/pages/war_view.gd", "key": "war"},
	{"var": "fishing_view", "script": "res://ui/pages/fishing_view.gd", "key": "fishing"},
	{"var": "fish_equip_view", "script": "res://ui/pages/fish_equip_view.gd", "key": "fish_equip"},
	{"var": "costume_view", "script": "res://ui/pages/costume_view.gd", "key": "costume"},
	{"var": "soul_view", "script": "res://ui/pages/soul_view.gd", "key": "soul"},
	{"var": "soulpower_view", "script": "res://ui/pages/soulpower_view.gd", "key": "soulpower"},
	{"var": "cuzhi_view", "script": "res://ui/pages/cuzhi_view.gd", "key": "cuzhi"},
	{"var": "collection_view", "script": "res://ui/pages/collection_view.gd", "key": "collection"},
	{"var": "bank_view", "script": "res://ui/pages/bank_view.gd", "key": "bank"},
	{"var": "mail_view", "script": "res://ui/pages/mail_view.gd", "key": "mail"},
	{"var": "inn_view", "script": "res://ui/pages/inn_view.gd", "key": "inn"},
	{"var": "clinic_view", "script": "res://ui/pages/clinic_view.gd", "key": "clinic"},
	{"var": "drugshop_view", "script": "res://ui/pages/drugshop_view.gd", "key": "drugshop"},
	{"var": "tavern_view", "script": "res://ui/pages/tavern_view.gd", "key": "tavern"},
	{"var": "winery_view", "script": "res://ui/pages/winery_view.gd", "key": "winery"},
	{"var": "miaoyin_view", "script": "res://ui/pages/miaoyin_view.gd", "key": "miaoyin"},
	{"var": "xiangfang_view", "script": "res://ui/pages/xiangfang_view.gd", "key": "xiangfang"},
]

# 【新增】切回闯荡页需关闭的视图 key 清单（= 原 switch_page 里 16 个手写 hide_xxx_view() 调用清单化，
# 新可关闭视图在此追加一行即可；顺序无要求）
const PAGE_CLOSE_LIST: Array = ["exchange", "lottery", "charity", "travel", "manor", "war", "fishing", "cuzhi", "collection", "bank", "mail", "inn", "clinic", "drugshop", "tavern", "winery", "miaoyin"]

func _ready():
	
	# Web 端访问不到系统字体，中文会变豆腐块；显式指定全局回退字体
	# （走 fallback 通道，桌面端拉丁字符仍是原字体，显示不变）
	ThemeDB.fallback_font = load("res://fonts/msyh.ttc")
	
	_build_scene_shell()          # 【新增】代码建壳，必须是第一行

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
	# 【改】视图实例化由 VIEW_LIST 循环驱动（原 21 行手写，2026-09-18 架构重构批次②）
	# set() 动态赋值到同名 var 声明；新视图接入 = var 声明一行 + VIEW_LIST 一条
	for e in VIEW_LIST:
		set(e.get("var", ""), load(e.get("script", "")).new(self))
	mall_panel = MallPanel.new(self)
	player_panel = PlayerPanel.new(self)
	
	# 正常退出时存档
	tree_exiting.connect(on_exit)
	
	# 【新增】Web 端页面被划走/切后台瞬间补一次存档（pagehide + visibilitychange 双保险）
	_setup_web_save_hook()

	
	_apply_portrait_layout()      # 【新增】壳层布局
	get_tree().root.size_changed.connect(_apply_portrait_layout)   # 【新增】窗口变化重排
	
	
	# 【新增】网络层（云存档）：save_game 后自动上传；有令牌→启动静默比对云端；首次→引导登录（可跳过）
	net = NetSystem.new()
	net.name = "NetSystem"
	add_child(net)
	net_ui = NetUi.new(self)   # 【新增】网络 UI 块（2026-09-19 重构批次A）：登录门/登录弹窗/云存档仲裁/账号面板
	ui_helpers = UiHelpers.new(self)   # 【新增】UI 助手设施（重构批次B）：弹窗工厂/样式/飘字/数量选择器
	data.game_saved.connect(net_ui._on_game_saved_upload)
	net.login_result.connect(net_ui._on_net_login_result)
	net.download_result.connect(net_ui._on_net_download_result)
	net.auth_expired.connect(net_ui._on_net_auth_expired)   # 【新增】令牌被服务端判失效：提示重新登录（防静默失联）

	
	# 【新增】2026-09-08 丢档事故后写死：无论有无令牌一律先过登录门。
	# 令牌只作"免密快捷进入"凭证，绝不再静默直通；下载仲裁统一在玩家点了"进入游戏"之后才发生
	net_ui._show_login_gate()   # 【改】登录门迁 ui/net_ui.gd（2026-09-19 重构批次A）

# 【新增】进入游戏：登录门通过后才执行（原 _ready 中 data.load_game() 起的初始化段原样移入，只进一次）
func _enter_game():
	if _game_entered: return
	_game_entered = true
	net_ui._hide_sync_mask()   # 【改】云端仲裁完成进游戏（含离线/仲裁失败兜底），摘掉同步遮罩（遮罩迁 ui/net_ui.gd，重构批次A）
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
	
	_apply_portrait_layout()
	
	data.mail_system.add_mail("test2", "测试", "合成材料", {"small_aptitude_pill": 40, "canpo_zhuiyu": 60, "treasure_box": 3})

# 登录门/离线进入/同步遮罩/令牌失效处理 → ui/net_ui.gd（2026-09-19 重构批次A迁出，经 net_ui 调用）

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
	
	# 【改】UI统一批A：总部/商铺/充值/VIP 四面板迁弹窗工厂（随建随连），此处的启动期 connect 全删
	
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
	
	
func switch_page(page_id: String):
	_close_ginseng_selector()  # 切换页面时关闭人参选择器
	bag_page._close_baiye_selector()   # 【新增】批A：百业选择器迁工厂后挂 c 根不随页面隐藏，切页主动关（对齐上行人参口径）
	friend_page._close_gift_selector()   # 【新增】批A：赠礼选择器同理（原挂 FriendPage 随页隐藏，迁工厂后需主动关）
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
		# 【改】隐藏链改 PAGE_CLOSE_LIST 循环驱动（原 16 个手写 hide_xxx_view()，2026-09-18 架构重构批次②）
		for _close_key in PAGE_CLOSE_LIST:
			hide_view(_close_key)
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
			# 【改】UI统一批A：GiftSelector/AssignSelector 已迁弹窗工厂（遮罩点击关闭接管），三处特判全删
			# 如果有弹窗打开（open_popup 系：HeroPanel 及 mall/lottery/player 自管弹窗）
			if _current_popup != null and _current_popup.visible:

				# 获取弹窗的全局矩形区域
				var popup_rect = _current_popup.get_global_rect()
				# 如果鼠标点击在弹窗区域之外
				if not popup_rect.has_point(get_global_mouse_position()):
					close_popup()
					# 阻止事件继续传给下面的按钮
					get_viewport().set_input_as_handled()

func _show_unlock_hint(role_name: String, vip_level: int):
	ui_helpers._show_unlock_hint(role_name, vip_level)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func on_auto_earn():
	if not _game_entered: return   # 【新增】丢档根修（2026-09-26）：过登录门进游戏之前节拍整体不跑——
	# 旧病根：计时器 autostart 随场景即跑，门期间满30秒就用空白新档自动存档覆盖真实存档
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
	# 【新增】定期自动存档：每 AUTOSAVE_INTERVAL 秒写一次盘（手机 Web 端收不到退出通知，靠它兜底进度）
	_autosave_sec += 1
	
	# 【促织培育】每秒检查罐倒计时
	if data.cuzhi_jars.size() > 0:
		data.cuzhi_system.tick_jars()
	# 【新增】药铺计算队列后台节拍：每秒推一次（时间盒2ms）；页面关闭也持续结算，
	# 队列进存档、离线暂停，上线后由本节拍续算（体力恢复与收益结算解耦）
	data.drugshop_system.background_tick(2)
	
	if _autosave_sec >= AUTOSAVE_INTERVAL:
		_autosave_sec = 0
		data.save_game()

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
	ui_helpers._show_quantity_selector(item_id, title_text, on_confirm)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _close_quantity_selector():
	ui_helpers._close_quantity_selector()   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func on_money_plus_clicked():
	var count = data.items.get("hour_card", 0)
	if count <= 0:
		_show_stage_hint("没有小时卡，请前往商城购买")
		return
	_show_quantity_selector("hour_card", "使用小时卡", _on_item_use_confirmed)

func update_all_ui():
	# 【新增】收入缓存表置脏（2026-09-25 用户拍板"赚速写入式表格"）：所有养成操作都汇流本函数，
	# 在此统一置脏，各系统无需各自接线；每秒 on_auto_earn 也经过这里，缓存至多 1 秒即刷新
	HeroData.invalidate_income_cache()
	update_money_label()
	update_entry_buttons()
	
	# 如果面板打开，实时更新面板内容
	if has_node("HQPanel") and $HQPanel.visible:
		update_hq_panel()
	if has_node("ShopPanel") and $ShopPanel.visible and current_shop_id != "":
		update_shop_panel()
	_check_income_float()   # 【新增】全局赚速飘字：任何操作后汇流到此，diff≠0 即弹

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

# 【新增】全局赚速提升飘字（2026-09-11 定稿，2026-09-16 重新接入——曾被后交付的整文件覆盖丢失）：
# 中央对比方案——中枢快照 + update_all_ui 汇流。所有养成系统操作后都汇流 update_all_ui
# （含每秒 on_auto_earn），diff≠0 即弹、更新快照；批量/十连天然合并为一次总增量；新系统零成本继承
func _check_income_float():
	ui_helpers._check_income_float()   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _show_float_badge(cfg: Dictionary, node_name: String, y: int, delta: int, make_text: Callable):
	ui_helpers._show_float_badge(cfg, node_name, y, delta, make_text)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _show_income_float(total: int, delta: int):
	ui_helpers._show_income_float(total, delta)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _show_hero_power_float(delta: int):
	ui_helpers._show_hero_power_float(delta)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _check_hero_income_float():
	ui_helpers._check_hero_income_float()   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

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
	ui_helpers._show_stage_hint(text, auto_hide)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

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
	ui_helpers.apply_theme()   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func style_nav_buttons():
	ui_helpers.style_nav_buttons()   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func style_button(btn: Button):
	ui_helpers.style_button(btn)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func animate_button(node_path: String):
	ui_helpers.animate_button(node_path)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func flash_red(node_path: String):
	ui_helpers.flash_red(node_path)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

# 【改】批次②③④-B11：保留消耗着色公共委托（页面统一走 c.xxx）
func _cost_color(have: int, need: int) -> Color:
	return ui_helpers._cost_color(have, need)

# 【新增】批次②③④-B6：消耗类统一范式委托（名称默认色，（拥有/消耗）红绿）
func _add_cost_row(parent: Node, prefix: String, have: int, need: int) -> HBoxContainer:
	return ui_helpers._add_cost_row(parent, prefix, have, need)

func _add_centered_panel(parent: Control, min_size: Vector2) -> VBoxContainer:
	return ui_helpers._add_centered_panel(parent, min_size)

func _create_base_popup(title_text: String, popup_size: Vector2, _pos: Vector2 = Vector2.ZERO, with_close: bool = true) -> PanelContainer:   # 【改】UI统一批次①：透传 with_close（确认弹窗传false不带右上✕）
	return ui_helpers._create_base_popup(title_text, popup_size, _pos, with_close)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _recenter_popup(panel: Control):
	ui_helpers._recenter_popup(panel)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _add_ok_button(parent: Node, callback: Callable, text: String = "确定") -> Button:
	return ui_helpers._add_ok_button(parent, callback, text)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _create_slider_spin_pair(parent: Node, max_val: int, min_val: int = 1) -> Dictionary:
	return ui_helpers._create_slider_spin_pair(parent, max_val, min_val)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _safe_close(node_name: String):
	ui_helpers._safe_close(node_name)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func _on_popup_tree_exiting(mask):
	ui_helpers._on_popup_tree_exiting(mask)   # 【改】主体迁 ui/ui_helpers.gd（2026-09-19 重构批次B）

func on_exit():
	# 正常退出：记录下线时间，然后存档
	@warning_ignore("narrowing_conversion")
	data.last_logout_time = Time.get_unix_time_from_system()
	data.save_game()

# ============ 存档三保险（2026-08-31 新增）：定期存档 + Web切后台补存 + 退出按钮 ============
# 背景：手机 Web 端划掉标签页不会触发 tree_exiting，旧版"只在退出时存档"导致怎么玩都不落盘

# 【新增】Web 端切后台补存档：监听 pagehide/visibilitychange，页面隐藏瞬间写盘
func _setup_web_save_hook():
	if not OS.has_feature("web"): return   # 仅 Web 平台需要
	_web_hide_cb = JavaScriptBridge.create_callback(_on_web_page_hide)
	var win = JavaScriptBridge.get_interface("window")
	win.__dzg_on_hide = _web_hide_cb
	JavaScriptBridge.eval("""
		window.addEventListener('pagehide', function(){ if (window.__dzg_on_hide) window.__dzg_on_hide(); });
		document.addEventListener('visibilitychange', function(){ if (document.hidden && window.__dzg_on_hide) window.__dzg_on_hide(); });
	""", true)

# 【新增】页面隐藏回调（JS → GDScript）：补一次存档
func _on_web_page_hide(_args):
	if data != null:
		data.save_game()

# 【新增】点退出：二次确认弹窗（说明会自动存档）
func _on_exit_btn_pressed():
	_safe_close("ExitConfirmPopup")
	var popup = _create_base_popup("退出游戏", Vector2(420, 220), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
	popup.name = "ExitConfirmPopup"
	popup.z_index = 30   # 弹窗层
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "退出前会自动存档\n确定退出游戏吗？"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右，动作含义写进标题/正文
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(func(): _safe_close("ExitConfirmPopup"))
	row.add_child(cancel)
	var ok = Button.new()
	ok.text = "确定"
	ok.custom_minimum_size = Vector2(140, 40)
	ok.pressed.connect(_on_exit_confirmed)
	row.add_child(ok)
	add_child(popup)

# 【改】确认退出：先存档。离线模式（无令牌）退出=返回登录门——重载场景后 token 为空必走 net_ui._show_login_gate()，
# 玩家在登录页登录（Web 端 window.close 被浏览器拦截基本关不掉，返回登录门才是可靠的"退出到登录页"）；
# 登录态退出保持原样：存档已自动上传云端，直接关程序/关页面
func _on_exit_confirmed():
	data.save_game()
	_safe_close("ExitConfirmPopup")
	if net != null and net.token == "":
		get_tree().reload_current_scene()   # 按钮回调里重载：与退出登录同一已验证安全路径
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.close();", true)
		_show_stage_hint("已存档，可安全关闭页面", 5.0)
	else:
		get_tree().quit()

# 云存档仲裁/对账失败/冲突恢复弹窗/账号面板/登录弹窗（含 Web HTML 表单）→ ui/net_ui.gd（2026-09-19 重构批次A迁出，经 net_ui 调用）

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


func _on_hero_assigned(hero_id: String, _slot: int):
	return shop_page._on_hero_assigned(hero_id, _slot)

func _on_hero_unassign(hero_id: String):
	return shop_page._on_hero_unassign(hero_id)

func open_hq_panel():
	return shop_page.open_hq_panel()


func open_shop_panel(shop_id: String):
	return shop_page.open_shop_panel(shop_id)







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

# 【新增】套装锦盒选择器 → pages/collection_view.gd
func show_suit_frag_box_selector(item_id: String, qty: int = 1):
	return collection_view.show_suit_frag_box_selector(item_id, qty)

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

# ==================== 【新增】视图通用入口（2026-09-18 架构重构批次②） ====================
# show_view/hide_view 按 VIEW_LIST 的 key 分发到视图同名方法 show_<key>_view / hide_<key>_view；
# key 与视图方法名的对应关系在 VIEW_LIST 登记时保证；未登记/方法缺失 push_error 报错定位（不静默 nil）
func _get_view_by_key(key: String):
	for e in VIEW_LIST:
		if e.get("key", "") == key:
			return get(e.get("var", ""))
	push_error("[视图] 未登记的 key: " + key + "（VIEW_LIST 缺条目或 key 写错）")
	return null

func show_view(key: String, args: Array = []):
	var v = _get_view_by_key(key)
	if v == null:
		return
	if not v.has_method("show_" + key + "_view"):
		push_error("[视图] 方法缺失: show_" + key + "_view（key 与视图方法名中段不一致）")
		return
	return v.callv("show_" + key + "_view", args)

func hide_view(key: String):
	var v = _get_view_by_key(key)
	if v == null:
		return
	if not v.has_method("hide_" + key + "_view"):
		push_error("[视图] 方法缺失: hide_" + key + "_view（key 与视图方法名中段不一致）")
		return
	return v.call("hide_" + key + "_view")

# ==================== 【转发】闯荡-兑换子视图（门客/挚友/珍兽/系列） → pages/exchange_view.gd ====================

func _on_exchange_back_pressed():
	return exchange_view._on_exchange_back_pressed()

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

func update_charity_view():
	return charity_view.update_charity_view()

func _on_charity():
	return charity_view._on_charity()

# ==================== 【转发】闯荡-游历子视图 → pages/travel_view.gd ====================

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


func _show_recharge_success(amount: int):
	return mall_panel._show_recharge_success(amount)

func on_vip():
	return mall_panel.on_vip()


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

# 【新增】个人面板里的账号/退出按钮入口（原顶栏按钮，竖屏被截断后移入个人面板）
func show_account_popup():
	return net_ui._on_account_btn_pressed()   # 【改】账号面板迁 ui/net_ui.gd（2026-09-19 重构批次A）

func show_exit_confirm():
	return _on_exit_btn_pressed()
# ==================== 【转发】庄园视图 → pages/manor_view.gd ====================

# 在闯荡页注入庄园入口按钮与子视图（由 adventure_page 构建时调用）
func build_manor_view(page, vbox):
	return manor_view.build_manor_view(page, vbox)

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

# 刷新商战界面
func update_war_view():
	return war_view.update_war_view()

# ==================== 【转发】垂钓视图 → pages/fishing_view.gd（第8批新增） ====================

# 在闯荡页注入垂钓入口按钮与子视图（由 adventure_page 构建时调用）
func build_fishing_view(page, vbox):
	return fishing_view.build_fishing_view(page, vbox)

# ==================== 【转发】促织园视图 → pages/cuzhi_view.gd ====================
func build_cuzhi_view(page, vbox):
	return cuzhi_view.build_cuzhi_view(page, vbox)

# ==================== 【转发】藏品视图 → pages/collection_view.gd ====================
# ==================== 【转发】钱庄玩法视图 → pages/bank_view.gd ====================

# ==================== 【转发】客栈玩法视图 → pages/inn_view.gd ====================

# ==================== 【转发】医馆玩法视图 → pages/clinic_view.gd ====================
# ==================== 【转发】药铺玩法视图 → pages/drugshop_view.gd ====================
# 府邸【藏品】入口
func on_collection():
	collection_view.show_collection_view()

# 府邸【厢房】入口（2026-09-20 批次①）
func on_xiangfang():
	xiangfang_view.show_xiangfang_view()

# ==================== 【转发】酒肆玩法视图 → pages/tavern_view.gd ====================
# ==================== 【转发】酒坊玩法视图 → pages/winery_view.gd ====================

# ==================== 【转发】邮件视图 → pages/mail_view.gd ====================
func on_mail():
	mail_view.show_mail_view()

# ============================================================
# 【场景收编】壳层结构 + 壳层布局（2026-08-29）
# 原则：control.tscn 只保留根 Control + 挂脚本，全部节点代码创建
#   _build_scene_shell()    建结构（_ready 第一行调用，只跑一次）
#   _apply_portrait_layout() 摆位置（_ready 末尾 + 窗口尺寸变化时调用）
# ============================================================

# ── 静态文字集中在这里，按你游戏内实际显示核对 ──
const NAV_LABELS = ["府邸", "商铺", "门客", "闯荡", "背包"]   # 底栏5键（门客/闯荡/背包已和截图核对，前两个按页面注释推断）
const RECHARGE_TAB_LABELS = ["元宝", "每日礼包", "特惠礼包"]    # 充值页3个页签
const TXT_VIP_TITLE = "VIP 特权"
const TXT_HQ_CLICK = "💰 点击赚钱"
const TXT_BATCH_HIRE = "十连招募"

# ============ 建结构 ============
func _build_scene_shell():
	# 场景里还留着旧节点时不重复建（先去编辑器精简 control.tscn 再运行）
	if has_node("Background"):
		push_warning("场景旧节点未清空，跳过代码建壳；请把 control.tscn 精简到只剩根节点")
		return

	# ── 背景 ──
	var bg = ColorRect.new()
	bg.name = "Background"
	add_child(bg)

	# ── 顶栏（AvatarBox/加号按钮由后续代码自己加）──
	var top_bar = HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_constant_override("separation", 12)
	add_child(top_bar)
	var top_label = Label.new()
	top_label.name = "Label"
	top_bar.add_child(top_label)
	var item_label = Label.new()   # 场景遗留节点，代码未引用，保留兼容
	item_label.name = "ItemLabel"
	top_bar.add_child(item_label)

	# ── 页面容器 + 各页面 ──
	var pc = Control.new()
	pc.name = "PageContainer"
	add_child(pc)

	# 商铺页（三十六节批次1：列表→长地图）：纵 ScrollContainer + 超高 Control 内容节点，
	# 建筑=坐标显式摆放的 Panel（代码布局老套路，命盘同法）；钱庄(总部)从顶部横幅迁入地图 C 位
	# （generate_shop_list 要求 ShopScroll/ShopList 必须存在，不能省）
	var shop_pg = Control.new()
	shop_pg.name = "ShopPage"
	pc.add_child(shop_pg)
	var shop_scroll = ScrollContainer.new()
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO   # 【改】横版地图：横向可滚（触屏拖动浏览）
	shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # 【新增】纵向锁死，建筑单行排布
	shop_scroll.name = "ShopScroll"
	shop_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_scroll.offset_top = 8   # 【改】72→8：钱庄横幅已迁入地图，只留小边距
	shop_pg.add_child(shop_scroll)
	var shop_list = Control.new()   # 【改】GridContainer→Control：地图内容节点，子建筑按坐标显式摆放
	shop_list.name = "ShopList"
	shop_scroll.add_child(shop_list)

	# 门客页：滚动容器（网格由 hero_page 代码填充）
	# （generate_hero_list 直接 get_node("HeroScroll")，不能省）
	var hero_pg = Control.new()
	hero_pg.name = "HeroPage"
	pc.add_child(hero_pg)
	var hero_scroll = ScrollContainer.new()
	hero_scroll.name = "HeroScroll"
	hero_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero_pg.add_child(hero_scroll)

	# 背包/府邸/珍兽/闯荡：空容器，内容由各页面模块代码生成
	for page_name in ["BagPage", "MansionPage", "BeastPage", "AdventurePage"]:
		var pg = Control.new()
		pg.name = page_name
		pc.add_child(pg)
	# 关卡页：场景里就是 VBoxContainer，保持原类型（stage_page 依赖容器排版）
	var stage_pg = VBoxContainer.new()
	stage_pg.name = "StagePage"
	pc.add_child(stage_pg)
	# （FriendPage / ApprenticePage 由各自模块代码创建，此处不建）

	# ── 底部导航（5键等分；文字见顶部常量）──
	var nav = HBoxContainer.new()
	nav.name = "BottomNav"
	nav.add_theme_constant_override("separation", 4)
	add_child(nav)
	var nav_names = ["NavMansionBtn", "NavShopBtn", "NavHeroBtn", "NavAdventureBtn", "NavBagBtn"]
	for i in nav_names.size():
		var btn = Button.new()
		btn.name = nav_names[i]
		btn.text = NAV_LABELS[i]
		btn.custom_minimum_size = Vector2(0, 60)   # 只定高度不定宽度
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 宽度等分
		nav.add_child(btn)

	# ── 遮罩（弹窗弹出时挡住背景点击）──
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.visible = false
	add_child(overlay)

	# 【改】UI统一批A：4个场景弹窗（充值/VIP/总部/商铺）已迁弹窗工厂，不再启动期预建；
	#  HeroPanel 仍由 hero_page 代码重建自管，不在此列

	# ── 每秒收益计时器（on_auto_earn 按"每秒"结算，wait_time 必须是 1.0）──
	var timer = Timer.new()
	timer.name = "Timer"
	timer.wait_time = 1.0
	timer.autostart = true
	add_child(timer)

# 【新增】顶栏/底栏显隐开关：进入二级页隐藏（全屏），返回时恢复
# 只改状态位再触发重排，实际矩形计算全在 _apply_portrait_layout 里（单一事实来源）
func _set_bars_visible(p_visible: bool):      # 【改】参数 visible→p_visible，遮蔽基类 CanvasItem.visible 属性报警告
	_bars_visible = p_visible                 # 【改】跟随参数改名
	_apply_portrait_layout()

# ============ 摆位置（启动 + 窗口尺寸变化时调用）============
# 原则：一律显式 position+size，不用锚点预设。
# （锚点预设会"保持节点当前矩形"，把 0 尺寸焊死——商铺/门客/背包页面空白的根因）
func _apply_portrait_layout():
	var vs = get_viewport_rect().size   # 逻辑像素（720×1280，stretch 后不受窗口物理大小影响）

	# 根节点、背景、遮罩铺满视口
	set_anchors_preset(Control.PRESET_TOP_LEFT)   # 【新增】先归零根节点锚点，否则 size 设置被锚点顶回（编辑器警告来源）
	position = Vector2.ZERO
	size = vs
	for path in ["Background", "Overlay"]:
		if has_node(path):
			var n = get_node(path)
			n.set_anchors_preset(Control.PRESET_TOP_LEFT)
			n.position = Vector2.ZERO
			n.size = vs

	# 顶栏：顶部通栏，高 50
	if has_node("TopBar"):
		$TopBar.custom_minimum_size = Vector2.ZERO
		$TopBar.set_anchors_preset(Control.PRESET_TOP_LEFT)
		$TopBar.position = Vector2.ZERO
		$TopBar.size = Vector2(vs.x, 50)
		$TopBar.visible = _bars_visible  # 【新增】二级页全屏时隐藏顶栏

	# 底栏：底部通栏，高 60，按钮等分
	if has_node("BottomNav"):
		$BottomNav.custom_minimum_size = Vector2.ZERO
		$BottomNav.set_anchors_preset(Control.PRESET_TOP_LEFT)
		$BottomNav.position = Vector2(0, vs.y - 60)
		$BottomNav.size = Vector2(vs.x, 60)
		for btn in $BottomNav.get_children():
			if btn is Button:
				btn.custom_minimum_size = Vector2(0, 60)
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		$BottomNav.visible = _bars_visible  # 【新增】二级页全屏时隐藏底栏

	# 页面容器：顶栏与底栏之间；各页面显式铺满
	if has_node("PageContainer"):
		$PageContainer.set_anchors_preset(Control.PRESET_TOP_LEFT)
		# 【改】尊重 _bars_visible：二级页全屏时扩满整个视口，窗口重排不会打回夹心布局
		if _bars_visible:
			$PageContainer.position = Vector2(0, 50)
			$PageContainer.size = Vector2(vs.x, vs.y - 110)
		else:
			$PageContainer.position = Vector2.ZERO
			$PageContainer.size = vs
	
	# 页面容器：顶栏与底栏之间；各页面显式铺满
	if has_node("PageContainer"):
		$PageContainer.set_anchors_preset(Control.PRESET_TOP_LEFT)
		# 【改】尊重 _bars_visible：二级页全屏时扩满整个视口，窗口重排不会打回夹心布局
		if _bars_visible:
			$PageContainer.position = Vector2(0, 50)
			$PageContainer.size = Vector2(vs.x, vs.y - 110)
		else:
			$PageContainer.position = Vector2.ZERO
			$PageContainer.size = vs
		# 【新增】各页面显式铺满容器：页面里的 FULL_RECT 滚动区（BagScroll/HeroScroll…）创建瞬间
		# 就能从父页面拿到正确尺寸，不再依赖"布局恰好在页面生成后重跑"的巧合时序
		for pg in $PageContainer.get_children():
			pg.set_anchors_preset(Control.PRESET_TOP_LEFT)
			pg.position = Vector2.ZERO
			pg.size = $PageContainer.size
	
	
	# 商铺页内部：钱庄入口顶部通栏(高64) + 店铺列表铺满剩余
	if has_node("PageContainer/ShopPage/ShopScroll"):
		var shop_scroll = $PageContainer/ShopPage/ShopScroll
		shop_scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
		shop_scroll.position = Vector2(0, 8)   # 【改】72→8：钱庄横幅已迁入地图
		shop_scroll.size = Vector2(vs.x, vs.y - 118)   # 【改】118 = 顶栏50 + 留白8 + 底栏60（原182=50+72+60）
		generate_shop_list()   # 【新增】窗口尺寸变化时重建地图：地图尺寸随可视高度自适应（2026-09-11 拍板），只生成一次会在改窗口后错位

	# 门客页 / 背包页的滚动区铺满整页
	# 【改】门客页滚动区左右留 12px 边距，卡片品质边框不再贴屏边被截断
	for path in ["PageContainer/HeroPage/HeroScroll", "PageContainer/BagPage/BagScroll"]:
		if has_node(path):
			var sc = get_node(path)
			sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
			if path.ends_with("HeroScroll"):
				sc.position = Vector2(12, 0)
				sc.size = Vector2(vs.x - 24, vs.y - 110)
			else:
				sc.position = Vector2.ZERO
				sc.size = Vector2(vs.x, vs.y - 110)

# 【新增】无双促织盒子使用入口（由 bag_page 调用）
func show_wushuang_box_selector():
	return cuzhi_view.show_wushuang_box_selector()
