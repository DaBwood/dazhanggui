# ============================================================
# 关卡页（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name StagePage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_stage_page():
	if not c.has_node("PageContainer/StagePage"): return
	var page = c.get_node("PageContainer/StagePage")
	
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
	
	# 【改】贸易按钮行：贸易按钮 + 「一键贸易」勾选框同行居中（原贸易按钮直接挂 vbox）
	var trade_row = HBoxContainer.new()
	trade_row.name = "TradeRow"
	trade_row.alignment = BoxContainer.ALIGNMENT_CENTER
	trade_row.add_theme_constant_override("separation", 12)
	vbox.add_child(trade_row)
	
	# 贸易按钮（改挂到 trade_row）
	var trade_btn = Button.new()
	trade_btn.name = "TradeBtn"
	trade_btn.custom_minimum_size = Vector2(240, 50)
	trade_row.add_child(trade_btn)
	
	# 【新增】一键贸易勾选框：勾选后每秒自动贸易（离开本页也继续），铜钱/战力不足自动停止
	# 状态存数据层 data.stage_auto_trade（节点重建后从这里恢复勾选；不进存档，重开游戏默认关）
	var auto_check = CheckBox.new()
	auto_check.name = "StageAutoCheck"
	auto_check.text = "一键贸易"
	auto_check.button_pressed = data.stage_auto_trade
	auto_check.toggled.connect(_on_stage_auto_toggled)
	trade_row.add_child(auto_check)
	
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
	if not c.has_node("PageContainer/StagePage/StageVBox"): return
	var vbox = c.get_node("PageContainer/StagePage/StageVBox")
	
	# 【新增】一键贸易停止原因：进入/刷新本页时消费并弹出（停止当下不弹，点进关卡页才弹）
	if data.stage_auto_stop_reason != "":
		c._show_stage_hint("一键贸易已停止：%s" % data.stage_auto_stop_reason, 4.0)
		data.stage_auto_stop_reason = ""
	
	# 【新增】勾选框状态与数据层同步（自动停止后取消勾选；set_pressed_no_signal 避免触发 toggled 回写）
	var auto_check = vbox.find_child("StageAutoCheck", true, false)
	if auto_check:
		auto_check.set_pressed_no_signal(data.stage_auto_trade)
	
	var title = vbox.get_node("StageTitle")
	var info = vbox.get_node("StageInfo")
	var boss_info = vbox.get_node("BossInfo")
	var trade_btn = vbox.get_node("TradeRow/TradeBtn")
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
		c.format_number(cost),
		c.format_number(actual_cost),
		discount * 100,
		count,
		data.reputation,
		10 * data.stage_main
	]
	
	trade_btn.text = "贸易（-%s）" % c.format_number(actual_cost)
	
	# 【改】Boss出现时的按钮状态
	if data.is_stage_boss_ready():
		trade_btn.disabled = true
		trade_btn.text = "Boss 已出现"
		boss_btn.visible = true
		boss_info.visible = true
		boss_info.text = "Boss 赚速：%s/秒  |  我方赚速：%s/秒" % [
			c.format_number(boss_income),
			c.format_number(hero_power)
		]
		if hero_power > boss_income:
			boss_btn.text = "Boss谈判（可战胜）"
			boss_btn.disabled = false
		else:
			boss_btn.text = "Boss谈判（实力不足）"
			boss_btn.disabled = false
	else:
		trade_btn.disabled = false
		trade_btn.text = "贸易（-%s）" % c.format_number(actual_cost)
		boss_btn.visible = false
		boss_info.visible = false

func on_stage_trade():
	var result = data.do_stage_trade()
	if not result.ok:
		c.flash_red("PageContainer/StagePage/StageVBox/TradeRow/TradeBtn")
		return
	
	update_stage_page()
	c.update_all_ui()
	c.update_bag_list()
	
	# 【改】普通贸易静默，只有关键节点才短暂提示
	if result.type == "next_sub":
		c._show_stage_hint("通关！宝箱×1  阅历+%d" % result.get("exp_reward", 0))
	elif result.type == "boss_ready":
		c._show_stage_hint("贸易完成，Boss 已出现！")

func on_stage_boss():
	var result = data.do_stage_boss()
	if not result.ok:
		return
	
	if result.win:
		c._show_stage_hint("谈判成功！声望 +10，抽奖券 +1")
	else:
		c._show_stage_hint("谈判失败！Boss 赚速 %s，我方仅 %s" % [
			c.format_number(result.boss_income),
			c.format_number(result.hero_power)
		])
	
	update_stage_page()
	c.update_all_ui()
	c.update_bag_list()
	c.update_entry_buttons()

# 【新增】一键贸易勾选切换：状态写入数据层；节拍由 game_controller.on_auto_earn 每秒驱动，离开本页也继续跑
func _on_stage_auto_toggled(pressed: bool):
	data.stage_auto_trade = pressed
