# ============================================================
# 玩家信息/身份/每日奖励弹窗（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name PlayerPanel
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func open_player_panel():
	_close_player_panel()
	
	var panel = c._create_base_popup("", Vector2(480, 520), Vector2(336, 60))
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
		c.format_number(need_income),
		c.format_number(cur_income),
		c.format_number(need_rep),
		c.format_number(cur_rep)
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
		chest_btn.text = "每日宝箱\n领 %s 元宝" % c.format_number(data.identity_level * 10000)
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
	
	c.add_child(panel)
	c._current_popup = panel
	c.get_node("Overlay").show()
	_update_identity_reward_list()

func _update_identity_reward_list():
	if not c.has_node("PlayerPanel"): return
	var list = c.get_node("PlayerPanel").find_child("IdentityRewardList", true, false)
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
		c._show_stage_hint("领取成功！%s" % result.reward.name)
		_update_identity_reward_list()
		c.update_all_ui()
		c.generate_hero_list()
		if c.has_node("PageContainer/BeastPage"):
			c.update_beast_page()
	elif result.duplicate:
		c._show_stage_hint("门客【%s】已拥有，无法重复领取" % result.reward.name)
	else:
		c.flash_red("PlayerPanel")



func _close_player_panel():
	if c.has_node("PlayerPanel"):
		c._safe_close("PlayerPanel")
	c.get_node("Overlay").hide()
	c._current_popup = null

func _on_rename_confirmed(input: LineEdit):
	var new_name = input.text.strip_edges()
	if data.rename_player(new_name):
		# 更新左上角名字
		if c.has_node("TopBar/AvatarBox/PlayerNameBtn"):
			c.get_node("TopBar/AvatarBox/PlayerNameBtn").text = data.player_name
		_close_player_panel()
		c._show_stage_hint("改名成功！")
	else:
		c.flash_red("PlayerPanel")

func _on_promote_identity():
	if data.promote_identity():
		c._show_stage_hint("晋升成功！身份 Lv.%d" % data.identity_level)
		# 【新增】如果面板还开着，刷新奖励列表
		if c.has_node("PlayerPanel"):
			_update_identity_reward_list()
		_close_player_panel()
		c.update_all_ui()
	else:
		c.flash_red("PlayerPanel/PromoteBtn")

func _on_claim_daily_reward():
	var reward = data.claim_daily_reward()
	if reward > 0:
		c._show_stage_hint("领取成功！元宝 +%s" % c.format_number(reward))
		c.update_all_ui()
		# 刷新个人页面内的宝箱按钮状态，不关闭面板
		if c.has_node("PlayerPanel"):
			var chest_btn = c.get_node("PlayerPanel").find_child("DailyChestBtn", true, false)
			if chest_btn != null:
				chest_btn.text = "每日宝箱\n已领取"
				chest_btn.disabled = true
	else:
		c.flash_red("PlayerPanel/DailyChestBtn")
