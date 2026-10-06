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

# 页面骨架场景（编辑器可视化维护）；动态内容（标题/信息/贸易行）由 generate_stage_page 灌进 StageListVBox
const STAGE_SCENE := preload("res://ui/pages/stage_page.tscn")

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_stage_page():
	if not c.has_node("PageContainer/StagePage"): return
	var page = c.get_node("PageContainer/StagePage")

	# 清空旧内容：用 free() 立即释放而非 queue_free——延迟到帧末会让同名新实例被自动改名（StageScene2），
	# 导致 update_stage_page 按名查找路径断裂、页面看起来"只剩顶排"（2026-10-06 实测空页定案）
	for child in page.get_children():
		child.free()

	# 【改】让 StagePage 填满整个 PageContainer；PRESET_MODE_MINSIZE=偏移清零，结果与父级尺寸无关（构建期锚定反推偏移坑两轮定案）
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)

	# 骨架来自场景文件：顶排（返回/标题/？）+滚动区；先挂父级再锚定，偏移显式清零铺满
	var inst = STAGE_SCENE.instantiate()
	inst.name = "StageScene"
	page.add_child(inst)
	inst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	inst.get_node("TopRow/BackButton").pressed.connect(func(): c.switch_page("adventure"))
	inst.get_node("TopRow/HelpButton").pressed.connect(func(): c._show_success_popup("挑战关卡获得闯荡币与道具；章节通关解锁下一章，失败会给出战力提示。"))

	# 滚动区锚定与占位容器尺寸由脚本钉死：用户工程里的 tscn 锚定数值被编辑过（实测 StageScroll 高度塌成 0），
	# 布局真相归脚本，场景文件只负责皮肤与节点结构
	var scroll: ScrollContainer = inst.get_node("StageScroll")
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	scroll.offset_top = 48
	# 动态内容灌进场景占位容器（节点名保持旧契约，update_stage_page 按名查找）；
	# 容错：场景文件缺 StageListVBox 时自建补上
	var vbox: VBoxContainer
	if inst.has_node("StageScroll/StageListVBox"):
		vbox = inst.get_node("StageScroll/StageListVBox")
	else:
		vbox = VBoxContainer.new()
		vbox.name = "StageListVBox"
		inst.get_node("StageScroll").add_child(vbox)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)


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

	# 贸易按钮行：贸易按钮 + 「一键贸易」勾选框同行居中
	var trade_row = HBoxContainer.new()
	trade_row.name = "TradeRow"
	trade_row.alignment = BoxContainer.ALIGNMENT_CENTER
	trade_row.add_theme_constant_override("separation", 12)
	vbox.add_child(trade_row)

	var trade_btn = Button.new()
	trade_btn.name = "TradeBtn"
	trade_btn.custom_minimum_size = Vector2(240, 50)
	trade_row.add_child(trade_btn)

	# 一键贸易勾选：状态存数据层 data.stage_auto_trade（节点重建后恢复勾选；不进存档）
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
	if not c.has_node("PageContainer/StagePage/StageScene/StageScroll/StageListVBox"): return
	var vbox = c.get_node("PageContainer/StagePage/StageScene/StageScroll/StageListVBox")
	
	# 【新增】一键贸易停止原因：进入/刷新本页时消费并弹出（停止当下不弹，点进关卡页才弹）
	if data.stage_auto_stop_reason != "":
		c._show_success_popup("一键贸易已停止：%s" % data.stage_auto_stop_reason, 4.0, "ok")   # 【改】飘字退休→ok 弹窗
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
		c.flash_red("PageContainer/StagePage/StageScene/StageScroll/StageListVBox/TradeRow/TradeBtn")
		return
	
	update_stage_page()
	c.update_all_ui()
	c.update_bag_list()
	
	# 【改】普通贸易静默，只有关键节点才短暂提示
	if result.type == "next_sub":
		c._show_success_popup("通关！宝箱×1  阅历+%d" % result.get("exp_reward", 0), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	elif result.type == "boss_ready":
		c._show_success_popup("贸易完成，Boss 已出现！", 0.0, "ok")   # 【改】飘字退休→ok 弹窗

func on_stage_boss():
	var result = data.do_stage_boss()
	if not result.ok:
		var bb = c.find_child("BossBtn", true, false)   # 【改】RefCounted 模块无 find_child，经 c（controller 根节点）递归找
		if bb != null: c.flash_red(bb.get_path())   # 【新增】闪红审计：操作失败反馈（2026-09-19）
		return
	
	if result.win:
		# 【改】成功反馈铺开：谈判成功弹窗
		c._show_success_popup("谈判成功\n声望 +10　抽奖券 +1")
	else:
		var bb2 = c.find_child("BossBtn", true, false)   # 【改】RefCounted 模块无 find_child，经 c（controller 根节点）递归找
		if bb2 != null: c.flash_red(bb2.get_path())   # 【新增】闪红审计：操作失败反馈（2026-09-19）
		c._show_success_popup("谈判失败！Boss 赚速 %s，我方仅 %s" % [   # 【改】飘字退休→warn 弹窗
			c.format_number(result.boss_income),
			c.format_number(result.hero_power)
		], 0.0, "warn")
	
	update_stage_page()
	c.update_all_ui()
	c.update_bag_list()
	c.update_entry_buttons()

# 【新增】一键贸易勾选切换：状态写入数据层；节拍由 game_controller.on_auto_earn 每秒驱动，离开本页也继续跑
func _on_stage_auto_toggled(pressed: bool):
	data.stage_auto_trade = pressed
