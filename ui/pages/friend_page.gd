# ============================================================
# 挚友页（含谈心/赠礼/店铺技能）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name FriendPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var _selected_shop_skill_index: int = -1
var current_friend_id: String = ""

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_friend_page():
	if not c.has_node("PageContainer"): return
	var page = c.get_node("PageContainer/FriendPage") if c.has_node("PageContainer/FriendPage") else null
	if page == null:
		page = Panel.new()
		page.name = "FriendPage"
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		c.get_node("PageContainer").add_child(page)
	
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
	
	# 【新增】游玩按钮
	var play_btn = Button.new()
	play_btn.name = "PlayBtn"
	play_btn.text = "游玩"
	play_btn.pressed.connect(_show_play_selector)
	attr_box.add_child(play_btn)
	
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

func update_friend_page():
	if not c.has_node("PageContainer/FriendPage/ListView/FriendScroll/FriendGrid"): return
	var grid = c.get_node("PageContainer/FriendPage/ListView/FriendScroll/FriendGrid")
	for child in grid.get_children():
		child.queue_free()
	
	# 已解锁（【改动】按友好度从高到低排序；未解锁VIP挚友仍按原顺序排在最后）
	var unlocked_ids = data.friends.keys()
	unlocked_ids.sort_custom(func(a, b): return data.friends[a].friendly > data.friends[b].friendly)
	for fid in unlocked_ids:
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
	if not c.has_node("PageContainer/FriendPage"): return
	var page = c.get_node("PageContainer/FriendPage")
	page.get_node("ListView").visible = false
	page.get_node("FriendDetail").visible = true
	_update_friend_page_detail()

func hide_friend_detail():
	current_friend_id = ""
	if not c.has_node("PageContainer/FriendPage"): return
	var page = c.get_node("PageContainer/FriendPage")
	page.get_node("ListView").visible = true
	page.get_node("FriendDetail").visible = false

func _update_friend_page_detail():
	if not c.has_node("PageContainer/FriendPage/FriendDetail"): return
	var detail = c.get_node("PageContainer/FriendPage/FriendDetail")
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
	attr_box.get_node("FriendAttr").text = "友好：%d  |  才华：%d  |  美名：%s" % [f.friendly, f.talent, data.get_friend_title(fid)]
	attr_box.get_node("FriendBond").text = "缘分：%s" % c.format_number(f.bond)
	
	# 天生丽质
	var fixed_name = detail.find_child("FixedSkillName", true, false)
	var fixed_info = detail.find_child("FixedSkillInfo", true, false)
	var fixed_btn = detail.find_child("FixedSkillBtn", true, false)
	if fixed_name: fixed_name.text = "天生丽质"
	if fixed_info:
		var bonus = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
		fixed_info.text = "缘分门客赚钱+%s" % c.format_number(bonus)
	if fixed_btn:
		var cost = (f.fixed_skill_level + 1) * 100
		fixed_btn.text = "升级（%d/%s）" % [cost, c.format_number(f.bond)]
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
		percent_btn.text = "升级（%d/%s）" % [cost, c.format_number(f.bond)]
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

	# 【服装系统】服装按钮（挚友详情左侧、技能行下方；绝对定位，位置不合适可微调 position）
	var cos_btn = detail.get_node_or_null("FriendCostumeBtn")
	if cos_btn == null:
		cos_btn = Button.new()
		cos_btn.name = "FriendCostumeBtn"
		cos_btn.text = "服装"
		cos_btn.add_theme_font_size_override("font_size", 14)
		cos_btn.position = Vector2(30, 320)
		cos_btn.size = Vector2(120, 40)
		detail.add_child(cos_btn)
	# 信号重连（先断后连，防止切换挚友后串数据）
	for conn in cos_btn.pressed.get_connections():
		cos_btn.pressed.disconnect(conn.callable)
	cos_btn.pressed.connect(c.costume_view.show_friend_costume_popup.bind(current_friend_id))

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
	var parent = c.get_node("PageContainer/FriendPage")
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
		status_lbl.text = "刷新消耗：%s 铜钱" % c.format_number(cost)
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
	var parent = c.get_node("PageContainer/FriendPage")
	var panel = parent.get_node_or_null("ShopSkillDetailPanel")
	if panel:
		panel.queue_free()

func _on_refresh_selected_skill():
	if _selected_shop_skill_index < 0: return
	var parent = c.get_node("PageContainer/FriendPage")
	var panel = parent.get_node_or_null("ShopSkillDetailPanel")
	var use_wish = false
	if panel:
		var wish_check = panel.find_child("WishStoneCheck", true, false)
		if wish_check:
			use_wish = wish_check.button_pressed
	
	if data.refresh_friend_shop_skill(current_friend_id, _selected_shop_skill_index, use_wish):
		_update_friend_page_detail()
		c.update_all_ui()
		var f = data.friends[current_friend_id]
		var skill = f.shop_skills[_selected_shop_skill_index]
		if skill.bonus >= 0.299:
			_close_shop_skill_detail()
		else:
			_update_shop_skill_detail()
	else:
		var parent2 = c.get_node("PageContainer/FriendPage")
		var panel2 = parent2.get_node_or_null("ShopSkillDetailPanel")
		if panel2:
			var refresh_btn = panel2.find_child("DetailRefreshBtn", true, false)
			if refresh_btn:
				c.flash_red(refresh_btn.get_path())

func _update_shop_skill_detail():
	var parent = c.get_node("PageContainer/FriendPage")
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
				status_lbl.text = "刷新消耗：%s 铜钱" % c.format_number(cost)
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


func _on_locked_friend_clicked(friend_id: String, vip_level: int):
	var cfg = data.get_friend_config(friend_id)
	var friend_name = cfg.get("name", "未知挚友")
	c._show_unlock_hint(friend_name, vip_level)




func on_chat_with_friend():
	var page = c.get_node("PageContainer/FriendPage")
	if data.energy <= 0:
		if data.items.get("energy_pill", 0) > 0:
			_show_energy_pill_prompt()
		else:
			
			var chat_btn = page.find_child("ChatBtn", true, false)
			if chat_btn:
				c.flash_red(chat_btn.get_path())
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
		c.update_all_ui()
		update_friend_page()
		var chat_btn = page.find_child("ChatBtn", true, false)
		if chat_btn:
			chat_btn.text = "谈心（%d/100）" % data.energy
	else:
		var chat_btn = page.find_child("ChatBtn", true, false)
		if chat_btn:
			c.flash_red(chat_btn.get_path())

func _show_energy_pill_prompt():
	if c.has_node("EnergyPillPrompt"): return
	
	var max_pills = data.items.get("energy_pill", 0)
	if max_pills <= 0: return
	
	var panel = c._create_base_popup("精力不足", Vector2(420, 280), Vector2(366, 184))
	panel.name = "EnergyPillPrompt"
	
	var vbox = panel.get_child(0)
	
	var info = Label.new()
	info.text = "拥有精力丹：%d" % max_pills
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	var pair = c._create_slider_spin_pair(vbox, max_pills)
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
	cancel_btn.pressed.connect(func(): c._safe_close("EnergyPillPrompt"))
	btn_box.add_child(cancel_btn)
	
	c.add_child(panel)

func _on_use_energy_pill(spin: SpinBox = null):
	var count = 1
	if spin != null:
		count = int(spin.value)
	
	var max_pills = data.items.get("energy_pill", 0)
	count = clamp(count, 1, max_pills)
	
	if max_pills <= 0:
		if c.has_node("EnergyPillPrompt"): 
			c._safe_close("EnergyPillPrompt")
		return
	
	data.items.energy_pill -= count
	data.energy += 3 * count
	
	if c.has_node("EnergyPillPrompt"): c._safe_close("EnergyPillPrompt")
	var chat_btn = c.get_node("PageContainer/FriendPage/FriendDetail").find_child("ChatBtn", true, false)
	if chat_btn != null:
		chat_btn.text = "谈心（%d/100）" % data.energy
	c.update_bag_list()
	# 吃完自动继续谈心
	on_chat_with_friend()


func _show_chat_result(results: Array):
	if c.has_node("ChatResultPanel"): return
	
	var panel = c._create_base_popup("谈心结果", Vector2(400, 300), Vector2(376, 174))
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
		# 【新增】月老牵线提示
		if r.get("yuelao", false):
			lbl.text += "（月老牵线！）"
		if r.get("twin", false):
			lbl.text += "，领养了一对双胞胎徒弟！"
			# 【新增】观音送子提示
			if r.get("guanyin", false):
				lbl.text += "（观音送子！）"
		elif r.get("adopted", false):
			lbl.text += "，领养了一位徒弟！"
		list.add_child(lbl)
	
	if results.size() > 1:
		var total = 0
		for r in results: total += r.gain
		var sum_lbl = Label.new()
		sum_lbl.text = "总计谈心 %d 次，缘分 +%d" % [results.size(), total]
		sum_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sum_lbl)
	
	c._add_ok_button(vbox, func(): c._safe_close("ChatResultPanel"))
	
	c.add_child(panel)


func _on_friend_skill_upgrade(is_fixed: bool):
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	
	var btn_name = "FixedSkillBtn" if is_fixed else "PercentSkillBtn"
	var detail = c.get_node("PageContainer/FriendPage/FriendDetail")
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
		c.update_all_ui()
	else:
		var btn = detail.find_child(btn_name, true, false)
		if btn != null:
			c.flash_red(btn.get_path())

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

func _show_play_selector():
	if current_friend_id == "" or not data.friends.has(current_friend_id): return
	c._safe_close("PlaySelector")
	
	var f = data.friends[current_friend_id]
	var panel = c._create_base_popup("与【%s】游玩" % f.name, Vector2(420, 260), Vector2(366, 190))
	panel.name = "PlaySelector"
	var vbox = panel.get_child(0)
	
	var info = Label.new()
	info.text = "谈心效果与普通谈心一致\n（缘分+才华，有空位可领养徒弟，不消耗精力）"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 14)
	vbox.add_child(info)
	
	# 游山玩水：1000元宝
	var scenery_btn = Button.new()
	scenery_btn.text = "游山玩水（1000元宝，拥有%s）" % c.format_number(data.yuanbao)
	scenery_btn.custom_minimum_size = Vector2(280, 44)
	scenery_btn.disabled = data.yuanbao < 1000
	scenery_btn.pressed.connect(_on_play_scenery)
	vbox.add_child(scenery_btn)
	
	# 吟诗作对：玫瑰香水×1
	var poetry_btn = Button.new()
	poetry_btn.text = "吟诗作对（玫瑰香水×1，拥有%d）" % data.items.get("rose_perfume", 0)
	poetry_btn.custom_minimum_size = Vector2(280, 44)
	poetry_btn.disabled = data.items.get("rose_perfume", 0) < 1
	poetry_btn.pressed.connect(_on_play_poetry)
	vbox.add_child(poetry_btn)
	
	c._add_ok_button(vbox, func(): c._safe_close("PlaySelector"), "取消")
	c.add_child(panel)

func _on_play_scenery():
	if data.yuanbao < 1000:
		c._show_stage_hint("元宝不足！")
		return
	data.yuanbao -= 1000
	_do_play_chat()

func _on_play_poetry():
	if data.items.get("rose_perfume", 0) < 1:
		c._show_stage_hint("玫瑰香水不足！")
		return
	data.items.rose_perfume -= 1
	_do_play_chat()

func _do_play_chat():
	var result = data.chat_with_specific_friend(current_friend_id)
	c._safe_close("PlaySelector")
	if result.ok:
		var msg = "与【%s】谈心，缘分 +%d" % [result.name, result.gain]
		if result.get("twin", false):
			msg += "，领养了一对双胞胎徒弟！"
			# 【新增】观音送子提示
			if result.get("guanyin", false):
				msg += "（观音送子！）"
		elif result.get("adopted", false):
			msg += "，领养了一位徒弟！"
		c._show_stage_hint(msg)
		_update_friend_page_detail()
		c.update_all_ui()
		c.update_bag_list()

func on_gift_friend():
	if current_friend_id == "": return
	_show_gift_selector()

# 打开赠礼选择器：滚动列表 + 限高 + 视口手动定位，防止礼物多了之后面板偏下、被底栏遮挡
func _show_gift_selector():
	var parent = c.get_node("PageContainer/FriendPage")
	if parent.has_node("GiftSelector"): return

	# 视口尺寸：项目根节点未铺满视口，不能依赖锚点，统一用视口手动算
	# 视口尺寸：页面类不是节点，要通过控制器 c 取视口
	var vs = c.get_viewport().get_visible_rect().size
	var panel_w = 440
	# 最大高度 = 视口高 - 顶部信息栏(约120) - 底部导航(约120)，保证上下都不被压
	var panel_h = min(560, vs.y - 240)

	var panel = PanelContainer.new()
	panel.name = "GiftSelector"
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	# 水平居中；垂直居中后再上移40，视觉上更靠上，且不会碰到顶栏
	panel.position = Vector2((vs.x - panel_w) / 2, max(110, (vs.y - panel_h) / 2 - 40))
	panel.z_index = 30   # 盖在页面最上层
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")   # 深色背景，不透
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "选择礼物"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 滚动容器：礼物行全放这里，超出高度可滚动，面板本身不再被撑高
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(panel_w - 20, panel_h - 110)   # 扣掉标题和取消按钮的高度
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 10)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	var gifts = [
		{"id": "wood_comb", "name": "木梳", "effect": "友好+1"},
		{"id": "rouge", "name": "胭脂", "effect": "才华+1"},
		{"id": "tong_zan", "name": "铜簪", "effect": "友好+2"},
		{"id": "yin_erhuan", "name": "银耳环", "effect": "友好+5"},
		{"id": "xiang_nang", "name": "香囊", "effect": "才华+2"},
		{"id": "huarong_xia", "name": "花容匣", "effect": "才华+5"},
	]
	for g in gifts:
		var count = data.items.get(g.id, 0)

		# 每行：信息 + 滑块 + 输入框 + 确认（行节点名保持不变，_refresh_gift_selector 靠它刷新）
		var row = VBoxContainer.new()
		row.name = "GiftRow_" + g.id
		row.add_theme_constant_override("separation", 2)
		list_vbox.add_child(row)

		var info = Label.new()
		info.text = "%s（%s）  拥有：%s" % [g.name, g.effect, c.format_number(count)]
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
		slider.custom_minimum_size = Vector2(140, 24)
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
	var parent = c.get_node("PageContainer/FriendPage")
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
	c.update_bag_list()
	c.update_all_ui()

func _refresh_gift_selector():
	var parent = c.get_node("PageContainer/FriendPage")
	if not parent.has_node("GiftSelector"): return
	var gifts = [
		{"id": "wood_comb", "name": "木梳", "effect": "友好+1"},
		{"id": "rouge", "name": "胭脂", "effect": "才华+1"},
		{"id": "tong_zan", "name": "铜簪", "effect": "友好+2"},
		{"id": "yin_erhuan", "name": "银耳环", "effect": "友好+5"},
		{"id": "xiang_nang", "name": "香囊", "effect": "才华+2"},
		{"id": "huarong_xia", "name": "花容匣", "effect": "才华+5"}
	]
	for g in gifts:
		var row = parent.get_node("GiftSelector").find_child("GiftRow_" + g.id, true, false)
		if row == null: continue
		var count = data.items.get(g.id, 0)
		
		var info = row.get_child(0)
		if info is Label:
			info.text = "%s（%s）  拥有：%s" % [g.name, g.effect, c.format_number(count)]
		
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
