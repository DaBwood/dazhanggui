# ============================================================
# 商城/充值/VIP弹窗（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name MallPanel
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func on_mall():
	_close_mall_panel()
	
	var panel = c._create_base_popup("商城", Vector2(500, 420), Vector2(326, 160))
	panel.name = "MallPanel"
	var vbox = panel.get_child(0)
	
	# 配置表驱动：新增礼包只需改 game_data 的 MALL_PACKS 表
	for pack in data.MALL_PACKS:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 16)
		vbox.add_child(row)
		
		var info = Label.new()
		info.text = "%s\n%s" % [pack.name, pack.desc]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(info)
		
		var buy_btn = Button.new()
		buy_btn.text = "%d元宝" % pack.cost
		buy_btn.custom_minimum_size = Vector2(120, 40)
		buy_btn.pressed.connect(_on_buy_mall_pack.bind(pack))
		row.add_child(buy_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_mall_panel)
	vbox.add_child(close_btn)
	
	c.add_child(panel)
	c._current_popup = panel
	c.get_node("Overlay").show()

func _on_buy_mall_pack(pack: Dictionary):
	if data.buy_mall_pack(pack):
		c.update_all_ui()
		c.update_bag_list()
		c._show_stage_hint("购买成功！%s" % pack.name)
	else:
		c.flash_red("MallPanel")


func _close_mall_panel():
	if c.has_node("MallPanel"):
		c._safe_close("MallPanel")
	c.get_node("Overlay").hide()
	c._current_popup = null

func _on_buy_test_beast_pack():
	if data.buy_test_beast_pack():
		c.update_beast_page()
		c.update_all_ui()
		c.update_bag_list()
		c._show_stage_hint("购买成功！驺虞×1 珍兽果×988 奇香果×988")
	else:
		c._show_stage_hint("元宝不足！")

func on_recharge():
	if c.has_node("RechargePage"):
		c.open_popup(c.get_node("RechargePage"))
		_switch_recharge_tab("normal")
		_update_recharge_page()
		

func _on_tab_normal_pressed():
	_switch_recharge_tab("normal")

func _on_tab_daily_pressed():
	_switch_recharge_tab("daily")

func _on_tab_special_pressed():
	_switch_recharge_tab("special")

func _switch_recharge_tab(tab: String):
	var normal_container = c.get_node("RechargePage/RechargeContainer/ContentContainer/YuanbaiContainer")
	var daily_container = c.get_node("RechargePage/RechargeContainer/ContentContainer/DailyGiftContainer")
	var special_container = c.get_node("RechargePage/RechargeContainer/ContentContainer/SpecialPackContainer")
	
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
	if not c.has_node("RechargePage/RechargeContainer/ContentContainer/YuanbaiContainer/RechargeGrid"): return
	var grid = c.get_node("RechargePage/RechargeContainer/ContentContainer/YuanbaiContainer/RechargeGrid")
	
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
	if not c.has_node("RechargePage/RechargeContainer/ContentContainer/SpecialPackContainer"): return
	var container = c.get_node("RechargePage/RechargeContainer/ContentContainer/SpecialPackContainer")
	
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

func _on_buy_special_pack(pack: Dictionary):
	data.buy_special_pack(pack)
	c._show_stage_hint("购买成功！%s" % pack.name)
	c.update_all_ui()
	c.update_bag_list()

func _update_daily_gift_page():
	if not c.has_node("RechargePage/RechargeContainer/ContentContainer/DailyGiftContainer"):
		return
	var container = c.get_node("RechargePage/RechargeContainer/ContentContainer/DailyGiftContainer")

	# 清空旧内容
	for child in container.get_children():
		child.queue_free()

	await c.get_tree().process_frame

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
		c.update_all_ui()
		c.update_bag_list()
		# 4. 弹出成功提示（复用充值成功弹窗或单独写一个）
		_show_recharge_success(amount)  # 这个函数会显示"获得XX元宝"，我们额外加一句提示
		# 由于原函数只显示元宝，我们可以在显示后追加一个标签，但简单起见，弹个额外提示
		# 或者自己写一个简单的提示框
		_show_daily_gift_success()
	else:
		# 理论上不会失败，因为 do_recharge 总是返回 true（只要 amount>0）
		pass

func _show_daily_gift_success():
	if c.has_node("DailyGiftSuccess"): return
	
	var panel = c._create_base_popup("购买成功！", Vector2(400, 180), Vector2(376, 220))
	panel.name = "DailyGiftSuccess"
	
	var vbox = panel.get_child(0)
	var info = Label.new()
	info.text = "获得元宝 ×60\n木梳 ×1000\n胭脂 ×1000"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	c._add_ok_button(vbox, func(): c._safe_close("DailyGiftSuccess"))
	
	c.add_child(panel)


func _on_recharge_confirmed(amount: int):
	if data.do_recharge(amount):
		_show_recharge_success(amount)
		c.update_all_ui()

func _show_recharge_success(amount: int):
	if c.has_node("RechargeSuccessPanel"): return
	
	var panel = c._create_base_popup("充值成功", Vector2(360, 200), Vector2(396, 224))
	panel.name = "RechargeSuccessPanel"
	
	var vbox = panel.get_child(0)
	var info = Label.new()
	info.text = "获得 %d 元宝\nVIP经验 +%d" % [amount * 10, amount * 10]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	c._add_ok_button(vbox, func(): c._safe_close("RechargeSuccessPanel"))
	
	c.add_child(panel)

func on_vip():
	if c.has_node("VIPPanel"):
		c.open_popup(c.get_node("VIPPanel"))
		_update_vip_panel()

func _update_vip_panel():
	
	if not c.has_node("VIPPanel"):
		return
	var panel = c.get_node("VIPPanel")
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
			vbox.get_node("VIPExpInfo").text = "经验：%s / %s" % [c.format_number(current_exp), c.format_number(next_exp)]

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
		lv_label.custom_minimum_size.x = 50
		if level == current_level:
			lv_label.add_theme_color_override("font_color", Color("#ffd700"))
		row.add_child(lv_label)

		var exp_label = Label.new()
		var need_exp = data.VIP_EXP_TABLE[level]
		exp_label.text = "累计 %s 元" % c.format_number(need_exp / 10)
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
		reward_label.custom_minimum_size.x = 140
		reward_label.add_theme_color_override("font_color", Color("#888888"))
		row.add_child(reward_label)

		# 领取按钮
		var claim_btn = Button.new()
		claim_btn.custom_minimum_size.x = 80
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
		c.generate_hero_list()
		c.update_friend_page()
		c.update_all_ui()
		data.save_game() 
		# 可选：弹窗提示领取成功
		#_show_claim_success(level)
	else:
		# 提示失败原因（可简化）
		pass
