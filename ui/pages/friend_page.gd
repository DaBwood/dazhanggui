# ============================================================
# 挚友页（重构版：左侧标签栏 + 右侧动态内容 + 底部礼物栏）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# ============================================================
class_name FriendPage
extends RefCounted

# ============ 立绘目录约定 ============
# 按类别分子目录、按ID命名，新增立绘只需把图丢进对应目录，零配置：
#   res://assets/portraits/friends/{friend_id}.png              挚友立绘
#   res://assets/portraits/heroes/{hero_id}.png                 门客立绘（预留）
#   res://assets/portraits/friends_cos/{friend_id}_{cos_id}.png 挚友服装立绘（预留）
#   res://assets/portraits/heroes_cos/{hero_id}_{cos_id}.png    门客服装立绘（预留）
const PORTRAIT_DIR_FRIENDS := "res://assets/portraits/friends/"

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

var _selected_shop_skill_index: int = -1
var current_friend_id: String = ""

func _init(p_c):
	c = p_c
	data = p_c.data

# ============ generate_friend_page：列表页不变，详情页重构 ============
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

	# --- 立绘背景（详情页专用，整页垫底）---
	# 【新增】TextureRect 挂 FriendPage 最底层：等比裁切铺满整页；
	#  文字/标签/礼物栏都是它的兄弟节点、天然浮在上面；
	#  mouse_filter=IGNORE 不挡点击；默认隐藏，进详情页才显示
	var portrait_bg = TextureRect.new()
	portrait_bg.name = "PortraitBg"
	portrait_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_bg.visible = false
	page.add_child(portrait_bg)
	page.move_child(portrait_bg, 0)  # 移到子节点最前，保证渲染在最底层

	# --- 列表视图容器 ---
	var list_view = VBoxContainer.new()
	list_view.name = "ListView"
	list_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(list_view)

	var scroll = ScrollContainer.new()
	scroll.name = "FriendScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_view.add_child(scroll)

	var grid = GridContainer.new()
	grid.name = "FriendGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	# 谈心操作区（谈心只在列表页全局谈，单个挚友的互动走详情页「游玩」标签）
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

	# --- 详情视图（左侧竖排标签 | 右侧信息+动态内容 | 底部礼物栏）---
	var detail = VBoxContainer.new()
	detail.name = "FriendDetail"
	detail.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail.visible = false
	detail.add_theme_constant_override("separation", 6)
	page.add_child(detail)

		# ===== 顶部信息带：返回键 + 名字 + 属性行 =====
	# 【新增】外套半透明纯色底条（PanelContainer），立绘背景上保证可读性
	var top_band = PanelContainer.new()
	top_band.name = "TopBand"
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = Color(0.05, 0.04, 0.10, 0.55)  # 半透明深色底，透明度可微调
	top_band.add_theme_stylebox_override("panel", top_style)
	detail.add_child(top_band)

	var top_vbox = VBoxContainer.new()
	top_vbox.name = "TopVBox"
	top_vbox.add_theme_constant_override("separation", 4)
	top_band.add_child(top_vbox)

	var back_btn = Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "< 返回挚友列表"
	back_btn.pressed.connect(hide_friend_detail)
	top_vbox.add_child(back_btn)  # 【改】原 detail.add_child，现挂进底条

	# 挚友名字（全宽居中）
	var name_lbl = Label.new()
	name_lbl.name = "FriendName"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	top_vbox.add_child(name_lbl)  # 【改】原 detail.add_child

	# 属性行：友好 | 才华 | 美名（纯文本一行展示）
	var attr_box = HBoxContainer.new()
	attr_box.name = "AttrBox"
	attr_box.alignment = BoxContainer.ALIGNMENT_CENTER
	attr_box.add_theme_constant_override("separation", 24)
	top_vbox.add_child(attr_box)  # 【改】原 detail.add_child

	var friendly_lbl = Label.new()
	friendly_lbl.name = "FriendlyLabel"
	attr_box.add_child(friendly_lbl)

	var talent_lbl = Label.new()
	talent_lbl.name = "TalentLabel"
	attr_box.add_child(talent_lbl)

	var title_lbl = Label.new()
	title_lbl.name = "FriendTitle"
	attr_box.add_child(title_lbl)

	# 主内容区（现在只放左侧竖排标签栏；右侧留空，以后放立绘等内容再加）
	var main_hbox = HBoxContainer.new()
	main_hbox.name = "MainHBox"
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 10)
	detail.add_child(main_hbox)

	# ===== 左侧区域：竖排标签（整体贴底）=====
	var left_area = VBoxContainer.new()
	left_area.name = "LeftArea"
	left_area.custom_minimum_size = Vector2(110, 0)
	left_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(left_area)

	# 【新增】标签栏外套半透明纯色底条（立绘背景上保证可读性）
	var tab_bg = PanelContainer.new()
	tab_bg.name = "TabBg"
	var tab_style = StyleBoxFlat.new()
	tab_style.bg_color = Color(0.05, 0.04, 0.10, 0.55)
	tab_bg.add_theme_stylebox_override("panel", tab_style)
	tab_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL  # 撑起左列高度，标签才能贴底
	left_area.add_child(tab_bg)

	var tab_bar = VBoxContainer.new()
	tab_bar.name = "TabBar"
	# 【改】tab_bar 挂进底条；PanelContainer 内子节点自动撑满，原来那行 EXPAND_FILL 删掉
	tab_bar.alignment = BoxContainer.ALIGNMENT_END
	tab_bar.add_theme_constant_override("separation", 6)
	tab_bg.add_child(tab_bar)

	# 标签点击直接打开对应弹窗（详情页只保留信息展示，功能全走弹窗）
	var tab_actions = {
		"技能": _show_skill_popup,
		"美名": _show_title_popup,
		"游玩": _show_play_popup,
		"服装": _on_open_costume_popup
	}
	for tab_name in ["技能", "美名", "游玩", "服装"]:
		var tbtn = Button.new()
		tbtn.name = "Tab_" + tab_name
		tbtn.text = tab_name
		tbtn.custom_minimum_size = Vector2(100, 42)
		tbtn.pressed.connect(tab_actions[tab_name])
		tab_bar.add_child(tbtn)

	# ===== 底部礼物栏 =====
	# 【新增】外套半透明纯色底条（立绘背景上保证可读性）
	var gift_band = PanelContainer.new()
	gift_band.name = "GiftBand"
	var gift_style = StyleBoxFlat.new()
	gift_style.bg_color = Color(0.05, 0.04, 0.10, 0.55)
	gift_band.add_theme_stylebox_override("panel", gift_style)
	detail.add_child(gift_band)

	var gift_bar = HBoxContainer.new()
	gift_bar.name = "GiftBar"
	gift_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	gift_bar.add_theme_constant_override("separation", 6)
	gift_band.add_child(gift_bar)  # 【改】原 detail.add_child，现挂进底条

	var batch_gift_check = CheckBox.new()
	batch_gift_check.name = "BatchGiftCheck"
	batch_gift_check.text = "十连赠送"
	gift_bar.add_child(batch_gift_check)

	var gift_ids = ["wood_comb", "rouge", "tong_zan", "yin_erhuan", "xiang_nang", "huarong_xia"]
	for i in range(gift_ids.size()):
		var gbtn = Button.new()
		gbtn.name = "GiftBtn_" + gift_ids[i]
		gbtn.custom_minimum_size = Vector2(70, 40)
		gbtn.add_theme_font_size_override("font_size", 12)
		gbtn.pressed.connect(_on_quick_gift.bind(gift_ids[i]))
		gift_bar.add_child(gbtn)

	# 【新增】「更多」按钮：打开自选数量赠礼弹窗
	# （_show_gift_selector 原来保留了下来但没有任何入口，是死代码）
	var more_btn = Button.new()
	more_btn.name = "GiftMoreBtn"
	more_btn.text = "更多"
	more_btn.custom_minimum_size = Vector2(56, 40)
	more_btn.pressed.connect(on_gift_friend)
	gift_bar.add_child(more_btn)

# ============ 列表页（不变） ============
func update_friend_page():
	if not c.has_node("PageContainer/FriendPage/ListView/FriendScroll/FriendGrid"): return
	var grid = c.get_node("PageContainer/FriendPage/ListView/FriendScroll/FriendGrid")
	for child in grid.get_children():
		child.queue_free()

	var unlocked_ids = data.friends.keys()
	unlocked_ids.sort_custom(func(a, b): return data.friends[a].friendly > data.friends[b].friendly)
	for fid in unlocked_ids:
		var f = data.friends[fid]
		var cell = _create_friend_card(f.name, f.friendly, f.talent, false)
		cell.pressed.connect(show_friend_detail.bind(fid))
		grid.add_child(cell)

	for fid in data.get_all_friend_ids():
		if data.friends.has(fid): continue
		var cfg = data.get_friend_config(fid)
		var cell = _create_friend_card(cfg.get("name", "未知"), 0, 0, true)
		var vip_lv = data.get_friend_unlock_vip(fid)
		cell.pressed.connect(_on_locked_friend_clicked.bind(fid, vip_lv))
		grid.add_child(cell)
	
	# 【新增】进入挚友页时同步谈心按钮精力数（原只在谈心后更新，首次进页面只显示"谈心"两字）
	var chat_btn = c.get_node_or_null("PageContainer/FriendPage/ListView/ChatOpBox/ChatBtn")
	if chat_btn:
		chat_btn.text = "谈心（%d/100）" % data.energy

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
		attr_lbl.add_theme_font_size_override("font_size", 16)
		vbox.add_child(attr_lbl)
	else:
		var lock_lbl = Label.new()
		lock_lbl.text = "未解锁"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_color_override("font_color", Color("#888888"))
		lock_lbl.add_theme_font_size_override("font_size", 16)
		vbox.add_child(lock_lbl)
		cell.modulate = Color(0.5, 0.5, 0.5, 0.7)

	return cell

func show_friend_detail(friend_id: String):
	current_friend_id = friend_id
	if not c.has_node("PageContainer/FriendPage"): return
	var page = c.get_node("PageContainer/FriendPage")
	page.get_node("ListView").visible = false
	page.get_node("FriendDetail").visible = true
	# 【新增】加载并显示该挚友立绘背景（无图则保持纯色底）
	_load_friend_portrait(friend_id)
	page.get_node("PortraitBg").visible = true
	_update_friend_page_detail()

func hide_friend_detail():
	current_friend_id = ""
	if not c.has_node("PageContainer/FriendPage"): return
	var page = c.get_node("PageContainer/FriendPage")
	page.get_node("ListView").visible = true
	page.get_node("FriendDetail").visible = false
	# 【新增】返回列表时隐藏立绘背景
	page.get_node("PortraitBg").visible = false

# ============ 详情页更新（重构） ============
func _update_friend_page_detail():
	if not c.has_node("PageContainer/FriendPage/FriendDetail"): return
	var detail = c.get_node("PageContainer/FriendPage/FriendDetail")
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	var f = data.friends[fid]
	if not f.has("shop_skills"):
		data._init_friend_shop_skills(fid)

	# 名字
	detail.get_node("TopBand/TopVBox/FriendName").text = "【%s】" % f.name

	# 友好/才华/美名（【改】节点名 FriendlyBtn/TalentBtn → FriendlyLabel/TalentLabel，纯文本）
	var attr_box = detail.get_node("TopBand/TopVBox/AttrBox")
	attr_box.get_node("FriendlyLabel").text = "友好：%d" % f.friendly
	attr_box.get_node("TalentLabel").text = "才华：%d" % f.talent
	attr_box.get_node("FriendTitle").text = "美名：%s" % data.get_friend_title(fid)

	# 刷新底部礼物栏
	_refresh_gift_bar()


# ============ 打开挚友服装弹窗 ============
# 【新增】替代 _on_costume_tab_clicked（只弹"开发中"提示，把已有功能砍掉了）；
#  接回服装系统的挚友服装兑换弹窗
func _on_open_costume_popup():
	if current_friend_id == "": return
	# 防御：controller 未接 costume_view 时不崩，给提示
	if not ("costume_view" in c) or c.costume_view == null:
		c._show_stage_hint("服装系统未接线")
		return
	c.costume_view.show_friend_costume_popup(current_friend_id)

# ============ 加载挚友立绘背景 ============
# 按目录约定拼路径；文件不存在时清空纹理（保持纯色底），静默跳过不报错
func _load_friend_portrait(friend_id: String):
	if not c.has_node("PageContainer/FriendPage/PortraitBg"): return
	var bg = c.get_node("PageContainer/FriendPage/PortraitBg")
	var path = PORTRAIT_DIR_FRIENDS + friend_id + ".png"
	if ResourceLoader.exists(path):
		bg.texture = load(path)
	else:
		bg.texture = null

# ============ 技能弹窗（天生丽质 + 花开富贵 + 店铺技能） ============
func _show_skill_popup():
	# 【修复】弹窗实际挂在控制器根节点（末尾 c.add_child），守卫必须查 c 根，
	#  否则每点一次"仪容技能"就叠一个新弹窗（同时删掉不再使用的 parent 变量）
	if c.has_node("SkillPopup"): return

	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	var f = data.friends[fid]

	var panel = c._create_base_popup("技能", Vector2(520, 600), Vector2(316, 24))
	panel.name = "SkillPopup"
	var vbox = panel.get_child(0)

	# 天生丽质
	var fixed_box = VBoxContainer.new()
	fixed_box.name = "FixedBox"
	fixed_box.add_theme_constant_override("separation", 4)
	vbox.add_child(fixed_box)

	var fixed_title = Label.new()
	fixed_title.text = "【天生丽质】"
	fixed_title.add_theme_font_size_override("font_size", 18)
	fixed_title.add_theme_color_override("font_color", Color("#ffd700"))
	fixed_box.add_child(fixed_title)

	var fixed_effect = Label.new()
	fixed_effect.name = "FixedEffect"
	var fbonus = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
	fixed_effect.text = "缘分门客赚钱+%s" % c.format_number(fbonus)
	fixed_box.add_child(fixed_effect)

	var fixed_upgrade = HBoxContainer.new()
	fixed_upgrade.name = "FixedUpgradeBox"
	fixed_upgrade.add_theme_constant_override("separation", 8)
	fixed_box.add_child(fixed_upgrade)

	var fixed_btn = Button.new()
	fixed_btn.name = "FixedUpgradeBtn"
	var fcost = (f.fixed_skill_level + 1) * 100
	fixed_btn.text = "升级（%d/%s）" % [fcost, c.format_number(f.bond)]
	fixed_btn.pressed.connect(_on_skill_upgrade_in_popup.bind(true))
	fixed_upgrade.add_child(fixed_btn)

	var fixed_check = CheckBox.new()
	fixed_check.name = "FixedBatchCheck"
	fixed_check.text = "十连"
	fixed_upgrade.add_child(fixed_check)

	# 花开富贵
	var percent_box = VBoxContainer.new()
	percent_box.name = "PercentBox"
	percent_box.add_theme_constant_override("separation", 4)
	vbox.add_child(percent_box)

	var percent_title = Label.new()
	percent_title.text = "【花开富贵】"
	percent_title.add_theme_font_size_override("font_size", 18)
	percent_title.add_theme_color_override("font_color", Color("#ffd700"))
	percent_box.add_child(percent_title)

	var percent_effect = Label.new()
	percent_effect.name = "PercentEffect"
	percent_effect.text = "缘分门客赚钱+%d%%" % (f.percent_skill_level * 5)
	percent_box.add_child(percent_effect)

	var percent_upgrade = HBoxContainer.new()
	percent_upgrade.name = "PercentUpgradeBox"
	percent_upgrade.add_theme_constant_override("separation", 8)
	percent_box.add_child(percent_upgrade)

	var percent_btn = Button.new()
	percent_btn.name = "PercentUpgradeBtn"
	var pcost = (f.percent_skill_level + 1) * 100
	percent_btn.text = "升级（%d/%s）" % [pcost, c.format_number(f.bond)]
	percent_btn.pressed.connect(_on_skill_upgrade_in_popup.bind(false))
	percent_upgrade.add_child(percent_btn)

	var percent_check = CheckBox.new()
	percent_check.name = "PercentBatchCheck"
	percent_check.text = "十连"
	percent_upgrade.add_child(percent_check)

	# 店铺技能
	var shop_title = Label.new()
	shop_title.text = "【店铺技能】"
	shop_title.add_theme_font_size_override("font_size", 18)
	shop_title.add_theme_color_override("font_color", Color("#ffd700"))
	shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(shop_title)

	var shop_scroll = ScrollContainer.new()
	shop_scroll.custom_minimum_size = Vector2(0, 200)
	vbox.add_child(shop_scroll)

	var shop_grid = GridContainer.new()
	shop_grid.columns = 5
	shop_grid.add_theme_constant_override("h_separation", 8)
	shop_grid.add_theme_constant_override("v_separation", 6)
	shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_scroll.add_child(shop_grid)

	for i in range(400):
		var btn = Button.new()
		btn.name = "PopupShopSkill_%d" % i
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_shop_skill_clicked.bind(i))
		shop_grid.add_child(btn)
	
	c._add_ok_button(vbox, func(): c._safe_close("SkillPopup"), "关闭")
	c.add_child(panel)
	_refresh_skill_popup()

# ============ 游玩弹窗（游山玩水/吟诗作对）============
# 【新增】原游玩内容平铺在详情页面板里，现改为弹窗：点「游玩」标签直接打开
func _show_play_popup():
	if c.has_node("PlayPopup"): return
	if current_friend_id == "" or not data.friends.has(current_friend_id): return

	var panel = c._create_base_popup("游玩", Vector2(420, 280), Vector2(366, 160))
	panel.name = "PlayPopup"
	var vbox = panel.get_child(0)

	var info = Label.new()
	info.text = "选择游玩方式（不消耗精力）"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	var scenery_btn = Button.new()
	scenery_btn.text = "游山玩水（1000元宝，拥有%s）" % c.format_number(data.yuanbao)
	scenery_btn.custom_minimum_size = Vector2(280, 44)
	scenery_btn.disabled = data.yuanbao < 1000
	scenery_btn.pressed.connect(_on_play_scenery)
	vbox.add_child(scenery_btn)

	var poetry_btn = Button.new()
	poetry_btn.text = "吟诗作对（玫瑰香水×1，拥有%d）" % data.items.get("rose_perfume", 0)
	poetry_btn.custom_minimum_size = Vector2(280, 44)
	poetry_btn.disabled = data.items.get("rose_perfume", 0) < 1
	poetry_btn.pressed.connect(_on_play_poetry)
	vbox.add_child(poetry_btn)

	c._add_ok_button(vbox, func(): c._safe_close("PlayPopup"), "关闭")
	c.add_child(panel)

func _refresh_skill_popup():
	# 【修复】与挂载点一致：弹窗在控制器根节点下，原路径找不到导致升级后弹窗不刷新
	var popup = c.get_node_or_null("SkillPopup")
	if not popup: return
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	var f = data.friends[fid]

	var fixed_effect = popup.find_child("FixedEffect", true, false)
	if fixed_effect:
		var bonus = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
		fixed_effect.text = "缘分门客赚钱+%s" % c.format_number(bonus)
	var fixed_btn = popup.find_child("FixedUpgradeBtn", true, false)
	if fixed_btn:
		var cost = (f.fixed_skill_level + 1) * 100
		fixed_btn.text = "升级（%d/%s）" % [cost, c.format_number(f.bond)]

	var percent_effect = popup.find_child("PercentEffect", true, false)
	if percent_effect:
		percent_effect.text = "缘分门客赚钱+%d%%" % (f.percent_skill_level * 5)
	var percent_btn = popup.find_child("PercentUpgradeBtn", true, false)
	if percent_btn:
		var cost = (f.percent_skill_level + 1) * 100
		percent_btn.text = "升级（%d/%s）" % [cost, c.format_number(f.bond)]

	var max_slots = min(400, int(f.friendly / 500))
	for i in range(400):
		var btn = popup.find_child("PopupShopSkill_%d" % i, true, false)
		if not btn: continue
		if i < max_slots and i < f.shop_skills.size():
			btn.visible = true
			var skill = f.shop_skills[i]
			var btxt = "+%.0f%%" % (skill.bonus * 100)
			if skill.bonus >= 0.299:
				btxt += "[满]"
				btn.disabled = true
			else:
				btn.disabled = false
			btn.text = "%s %s" % [skill.category, btxt]
		else:
			btn.visible = false

func _on_skill_upgrade_in_popup(is_fixed: bool):
	var fid = current_friend_id  
	if fid == "" or not data.friends.has(fid): return

	# 【修复】与挂载点一致：弹窗在控制器根节点下（c.add_child），原路径找不到会导致升级后弹窗不刷新
	var popup = c.get_node_or_null("SkillPopup")
	var batch = false
	if popup:
		var check_name = "FixedBatchCheck" if is_fixed else "PercentBatchCheck"
		var check = popup.find_child(check_name, true, false)
		if check != null:
			batch = check.button_pressed

	var upgraded = 0
	if is_fixed:
		upgraded = _upgrade_friend_fixed_batch(fid, batch)
	else:
		upgraded = _upgrade_friend_percent_batch(fid, batch)

	if upgraded > 0:
		_refresh_skill_popup()
		_update_friend_page_detail()
		c.update_all_ui()
	else:
		c._show_stage_hint("缘分不足！")

# ============ 美名弹窗 ============
# 【重写】K2.6 版虚构了"晋升"按钮和不存在的字段（.name/.friendly/.talent_bonus/.aptitude_bonus），
#  打开即报错；FRIEND_TITLES 真实字段是 .title/.req/.quality/.income，
#  美名实际作用 = 决定领养徒弟的品质与赚速基础（见 GameData._create_apprentice）
func _show_title_popup():
	# 【修复】弹窗实际挂在控制器根节点（末尾 c.add_child），守卫必须查 c 根，
	#  否则重复点击会叠多个弹窗
	if c.has_node("TitlePopup"): return
	var fid = current_friend_id
	if fid == "" or not data.friends.has(fid): return
	var f = data.friends[fid]
	var titles = data.FRIEND_TITLES
	var idx = data.get_friend_title_index(fid)

	var panel = c._create_base_popup("美名一览", Vector2(420, 300), Vector2(366, 140))
	panel.name = "TitlePopup"
	var vbox = panel.get_child(0)

	# 当前美名
	var cur_lbl = Label.new()
	cur_lbl.text = "当前美名：%s" % (titles[idx].title if idx >= 0 else "无")
	cur_lbl.add_theme_font_size_override("font_size", 18)
	cur_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	cur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cur_lbl)

	# 当前效果（徒弟品质 + 赚速基础）
	if idx >= 0:
		var eff_lbl = Label.new()
		eff_lbl.text = "效果：徒弟品质【%s】，赚速基础 %s" % [titles[idx].quality, c.format_number(titles[idx].income)]
		eff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(eff_lbl)

	# 下一级条件（友好/才华需同时达标）
	if idx < titles.size() - 1:
		var next_t = titles[idx + 1]
		var next_lbl = Label.new()
		next_lbl.text = "下一级【%s】：友好 %s/%s，才华 %s/%s" % [
			next_t.title,
			c.format_number(f.friendly), c.format_number(next_t.req),
			c.format_number(f.talent), c.format_number(next_t.req)
		]
		next_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(next_lbl)
	else:
		var max_lbl = Label.new()
		max_lbl.text = "已达最高美名"
		max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(max_lbl)

	# 说明行：告知自动判定，消除"找晋升按钮"的疑惑
	var tip_lbl = Label.new()
	tip_lbl.text = "（友好、才华达标后美名自动晋升）"
	tip_lbl.add_theme_color_override("font_color", Color("#888888"))
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tip_lbl)

	c._add_ok_button(vbox, func(): c._safe_close("TitlePopup"), "关闭")
	c.add_child(panel)


# ============ 底部礼物栏 ============
func _refresh_gift_bar():
	if not c.has_node("PageContainer/FriendPage/FriendDetail"): return
	var bar = c.get_node("PageContainer/FriendPage/FriendDetail/GiftBand/GiftBar")
	var gift_ids = ["wood_comb", "rouge", "tong_zan", "yin_erhuan", "xiang_nang", "huarong_xia"]
	var gift_names = ["木梳", "胭脂", "铜簪", "银耳环", "香囊", "花容匣"]
	for i in range(gift_ids.size()):
		var btn = bar.get_node_or_null("GiftBtn_" + gift_ids[i])
		if btn == null: continue
		var count = data.items.get(gift_ids[i], 0)
		btn.text = "%s\n%d" % [gift_names[i], count]
		btn.disabled = count <= 0

func _on_quick_gift(item_id: String):
	if current_friend_id == "": return
	var bar = c.get_node("PageContainer/FriendPage/FriendDetail/GiftBand/GiftBar")
	var batch_check = bar.get_node_or_null("BatchGiftCheck")
	var batch = false
	if batch_check != null:
		batch = batch_check.button_pressed
	var count = 10 if batch else 1

	if data.items.get(item_id, 0) < count:
		c._show_stage_hint("礼物不足！")
		return

	for i in range(count):
		if not data.gift_friend(current_friend_id, item_id):
			break

	_refresh_gift_bar()
	_update_friend_page_detail()
	c.update_bag_list()
	c.update_all_ui()

# ============ 店铺技能（不变） ============
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
	_selected_shop_skill_index = skill_index
	# 【改】弹窗统一挂控制器根节点 c（项目弹窗惯例），守卫同步查 c 根；
	#  原挂在 FriendPage 下，与挂 c 根的技能弹窗不在同一条排序链上，z 拼不过被压在下面
	if c.has_node("ShopSkillDetailPanel"): return

	var f = data.friends[current_friend_id]
	if not f.has("shop_skills") or skill_index >= f.shop_skills.size(): return
	var skill = f.shop_skills[skill_index]

	var panel = PanelContainer.new()
	panel.name = "ShopSkillDetailPanel"
	panel.custom_minimum_size = Vector2(360, 280)
	# 【改】定位基准从 FriendPage.size 改为视口尺寸（挂载点变了，父节点尺寸不再适用）
	panel.position = (c.get_viewport_rect().size - panel.custom_minimum_size) / 2
	# 【改】z=40：压过所有 _create_base_popup 系弹窗（z=30，含仪容技能弹窗）
	panel.z_index = 40

	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "【%s类】店铺技能" % skill.category
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)

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

	# 【改】挂载点：parent.add_child → c.add_child（与所有弹窗一致）
	c.add_child(panel)

func _close_shop_skill_detail():
	# 【改】详情弹窗已改挂 c 根节点
	var panel = c.get_node_or_null("ShopSkillDetailPanel")
	if panel:
		panel.queue_free()

func _on_refresh_selected_skill():
	if _selected_shop_skill_index < 0: return
	# 【改】详情弹窗已改挂 c 根节点（原从 FriendPage 下找）
	var panel = c.get_node_or_null("ShopSkillDetailPanel")
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
		# 【改】详情弹窗已改挂 c 根节点
		var panel2 = c.get_node_or_null("ShopSkillDetailPanel")
		if panel2:
			var refresh_btn = panel2.find_child("DetailRefreshBtn", true, false)
			if refresh_btn:
				c.flash_red(refresh_btn.get_path())

func _update_shop_skill_detail():
	# 【改】详情弹窗已改挂 c 根节点
	var panel = c.get_node_or_null("ShopSkillDetailPanel")
	if not panel: return

	var f = data.friends[current_friend_id]
	if not f.has("shop_skills") or _selected_shop_skill_index >= f.shop_skills.size(): return
	var skill = f.shop_skills[_selected_shop_skill_index]

	var bonus_lbl = panel.find_child("DetailBonus", true, false)
	if bonus_lbl:
		bonus_lbl.text = "当前加成：+%.0f%%" % (skill.bonus * 100)

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

	if wish_check:
		wish_check.text = "使用许愿石（拥有：%d）" % data.items.get("wish_stone", 0)
		if skill.bonus >= 0.299:
			wish_check.visible = false

	var refresh_btn = panel.find_child("DetailRefreshBtn", true, false)
	if skill.bonus >= 0.299:
		if refresh_btn:
			refresh_btn.queue_free()
		if wish_check:
			wish_check.queue_free()
	else:
		if refresh_btn:
			refresh_btn.text = "刷新"

func _on_shop_skill_clicked(skill_index: int):
	_selected_shop_skill_index = skill_index
	_show_shop_skill_detail(skill_index)

# ============ 谈心（不变） ============
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
	# 【修复】谈心按钮在列表页 ListView 下，原路径从 FriendDetail 找永远为 null、文本不更新
	var chat_btn = c.get_node("PageContainer/FriendPage/ListView").find_child("ChatBtn", true, false)
	if chat_btn != null:
		chat_btn.text = "谈心（%d/100）" % data.energy
	c.update_bag_list()
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
		if r.get("yuelao", false):
			lbl.text += "（月老牵线！）"
		if r.get("twin", false):
			lbl.text += "，领养了一对双胞胎徒弟！"
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

# ============ 技能升级（弹窗内复用） ============
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

# ============ 游玩（不变） ============
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
	c._safe_close("PlayPopup")
	if result.ok:
		var msg = "与【%s】谈心，缘分 +%d" % [result.name, result.gain]
		if result.get("twin", false):
			msg += "，领养了一对双胞胎徒弟！"
			if result.get("guanyin", false):
				msg += "（观音送子！）"
		elif result.get("adopted", false):
			msg += "，领养了一位徒弟！"
		c._show_stage_hint(msg)
		_update_friend_page_detail()
		c.update_all_ui()
		c.update_bag_list()

# ============ 赠礼（完整版弹窗保留） ============
func on_gift_friend():
	if current_friend_id == "": return
	_show_gift_selector()

func _show_gift_selector():
	var parent = c.get_node("PageContainer/FriendPage")
	if parent.has_node("GiftSelector"): return

	var vs = c.get_viewport().get_visible_rect().size
	var panel_w = 440
	var panel_h = min(560, vs.y - 240)

	var panel = PanelContainer.new()
	panel.name = "GiftSelector"
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	panel.position = Vector2((vs.x - panel_w) / 2, max(110, (vs.y - panel_h) / 2 - 40))
	panel.z_index = 30
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "选择礼物"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(panel_w - 20, panel_h - 110)
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

func _on_locked_friend_clicked(friend_id: String, vip_level: int):
	var cfg = data.get_friend_config(friend_id)
	var friend_name = cfg.get("name", "未知挚友")
	c._show_unlock_hint(friend_name, vip_level)
