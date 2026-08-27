# ============================================================
# 宅院视图（庄园第三页签：技艺按钮 + 弹窗升级卷轴）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，data = GameData 数据中枢）
# UI 由 ManorView 的“宅院”页签触发，复用庄园滚动列表与“等级十连”勾选框
# ============================================================
class_name CourtyardView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用
var _batch_checked: bool = false   # 十连「卷一卷二通用」状态（勾选框在弹窗内，这里记住上次选择）

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 主列表 ============
# 重绘宅院主界面：只显示技艺按钮，点击按钮再打开升级弹窗
func update_courtyard_view(list: VBoxContainer):
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	list.add_child(grid)

	for cfg in data.get_courtyard_technique_list():
		grid.add_child(_build_technique_button(cfg))

# 构建技艺入口按钮：按钮只显示技艺名和产物名，避免主列表被卷轴详情撑长
func _build_technique_button(cfg: Dictionary) -> Button:
	var btn = Button.new()
	btn.text = "%s\n产物：%s" % [cfg.get("name", cfg.get("id", "")), cfg.get("product", "")]
	btn.custom_minimum_size = Vector2(160, 58)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_on_technique_button.bind(String(cfg.get("id", ""))))
	return btn

# ============ 技艺弹窗 ============
# 打开某个技艺的升级弹窗；重复打开时先关闭旧弹窗，避免叠加
func _on_technique_button(tech_id: String):
	c._safe_close("CourtyardTechPopup")
	var panel = c._create_base_popup("", Vector2(360, 500))
	panel.name = "CourtyardTechPopup"
	panel.set_meta("tech_id", tech_id)
	_fill_technique_popup(panel)
	c.add_child(panel)

# 填充/刷新技艺弹窗内容（升级后不关弹窗，只重建内部节点）
func _fill_technique_popup(panel: PanelContainer):
	var tech_id = String(panel.get_meta("tech_id", ""))
	var cfg = _get_technique_cfg(tech_id)
	if cfg.is_empty(): return

	var vbox: VBoxContainer = panel.get_child(0)
	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "【%s】" % cfg.get("name", tech_id)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)

	var product = String(cfg.get("product", ""))
	var stock = Label.new()
	stock.text = "产物：%s ｜ 库存：%d" % [product, data.get_manor_goods_count(product)]
	stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stock)
	
	# 【新增】十连「卷一卷二通用」勾选放在弹窗内：升级按钮在哪，开关就在哪；勾选状态记在 _batch_checked
	var batch_check = CheckBox.new()
	batch_check.text = "十连升级"
	batch_check.button_pressed = _batch_checked
	batch_check.toggled.connect(_on_batch_toggled)
	vbox.add_child(batch_check)

	# 弹窗内部使用滚动区，两个项目各两卷都能在小屏手机内查看
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 350)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var detail_list = VBoxContainer.new()
	detail_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_list.add_theme_constant_override("separation", 8)
	scroll.add_child(detail_list)

	detail_list.add_child(_build_project_block(cfg, "project1"))
	detail_list.add_child(_build_project_block(cfg, "project2"))

	c._add_ok_button(vbox, func(): c._safe_close("CourtyardTechPopup"), "关闭")

# 按 id 从宅院配置取技艺，避免弹窗刷新时继续持有旧配置字典
func _get_technique_cfg(tech_id: String) -> Dictionary:
	for cfg in data.get_courtyard_technique_list():
		if cfg.get("id", "") == tech_id:
			return cfg
	return {}

# ============ 弹窗内容构建 ============
# 构建一个项目区：项目标题、成员说明、卷一/卷二两行
func _build_project_block(tech: Dictionary, project_key: String) -> VBoxContainer:
	var project: Dictionary = tech.get(project_key, {})
	var block = VBoxContainer.new()
	block.add_theme_constant_override("separation", 3)

	var title = Label.new()
	title.text = _get_project_title(project)
	title.add_theme_color_override("font_color", Color("#4a90d9"))
	block.add_child(title)

	# 门客卷/挚友卷显示固定分配成员，便于玩家核对本卷影响谁
	var members_text = _get_members_text(project)
	if members_text != "":
		var members = Label.new()
		members.text = "成员：%s" % members_text
		members.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		members.add_theme_font_size_override("font_size", 12)
		members.add_theme_color_override("font_color", Color("#aaaaaa"))
		block.add_child(members)

	block.add_child(_build_scroll_row(tech, project_key, project, "vol1"))
	block.add_child(_build_scroll_row(tech, project_key, project, "vol2"))
	return block

# 项目标题按类型生成：商铺卷显示店铺名，挚友卷/门客卷显示成员数
func _get_project_title(project: Dictionary) -> String:
	match project.get("type", ""):
		"shop":
			return "商铺卷：%s" % project.get("target_name", project.get("target", ""))
		"friend":
			return "挚友卷（%d人）" % project.get("friends", []).size()
		"hero":
			return "门客卷（%d人）" % project.get("heroes", []).size()
	return "未知卷"

# 取门客/挚友卷的成员名列表；商铺卷没有成员列表，返回空串
func _get_members_text(project: Dictionary) -> String:
	var names = []
	if project.get("type", "") == "hero":
		for hero_id in project.get("heroes", []):
			names.append(data.get_hero_config(hero_id).get("name", hero_id))
	elif project.get("type", "") == "friend":
		for friend_id in project.get("friends", []):
			names.append(data.get_friend_config(friend_id).get("name", friend_id))
	return "、".join(names)

# 构建卷一/卷二升级行：等级、当前效果、产物消耗、升级按钮
func _build_scroll_row(tech: Dictionary, project_key: String, project: Dictionary, volume: String) -> HBoxContainer:
	var tech_id = String(tech.get("id", ""))
	var level = data.get_courtyard_scroll_level(tech_id, project_key, volume)
	var is_vol1 = volume == "vol1"

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# 【改】卷二解锁限制已作废，两卷都直接显示等级/效果/消耗
	var info = Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cost = data.get_courtyard_scroll_cost(tech_id, project_key, volume)
	var product = String(tech.get("product", ""))
	var vol_name = "卷一" if is_vol1 else "卷二"
	info.text = "%s：Lv%d ｜ %s ｜ 消耗%s×%s（有%s）" % [
		vol_name, level, _get_scroll_effect_text(project, volume, level),
		product, c.format_number(cost), c.format_number(data.get_manor_goods_count(product))]
	row.add_child(info)

	var btn = Button.new()
	btn.custom_minimum_size = Vector2(82, 34)
	btn.text = "升级"
	btn.pressed.connect(_on_upgrade_scroll.bind(tech_id, project_key, volume))
	row.add_child(btn)
	return row

# 当前卷轴效果文本：只负责显示，实际计算在 CourtyardSystem / HeroData / ShopSystem
func _get_scroll_effect_text(project: Dictionary, volume: String, level: int) -> String:
	# 效果系数统一读 courtyard.json，避免配置调参后界面文本和实际效果不一致
	var settings = data.get_courtyard_settings()
	match project.get("type", ""):
		"shop":
			if volume == "vol1":
				return "店员赚速+%.1f" % (level * float(settings.get("shop_staff_income_per_level", 0.1)))
			return "店铺总赚速+%d%%" % int(level * float(settings.get("shop_percent_per_level", 0.25)) * 100)
		"hero":
			if volume == "vol1":
				return "每名成员赚钱+%s" % c.format_number(level * int(settings.get("hero_income_per_level", 5000)))
			return "每名成员资质+%d" % (level * int(settings.get("hero_aptitude_per_level", 1)))
		"friend":
			if volume == "vol1":
				return "每名成员友好+%d" % (level * int(settings.get("friend_friendly_per_level", 1)))
			return "每名成员才华+%d" % (level * int(settings.get("friend_talent_per_level", 1)))
	return "无效果"

# ============ 交互回调 ============
# 【新增】弹窗内“卷一十连”勾选变化时记录状态，重开弹窗保持上次选择
func _on_batch_toggled(pressed: bool):
	_batch_checked = pressed

# 升级卷轴：卷一跟随弹窗内的“卷一十连”勾选；卷二固定只升1级
func _on_upgrade_scroll(tech_id: String, project_key: String, volume: String):
	var result: Dictionary
	# 十连状态读模块变量（勾选框在弹窗内）
	if _batch_checked:
		result = data.upgrade_courtyard_scroll_batch(tech_id, project_key, volume)
	else:
		result = data.upgrade_courtyard_scroll(tech_id, project_key, volume)

	if not result.ok:
		c._show_stage_hint(result.get("reason", "升级失败"))
	else:
		c.update_all_ui()
	c.update_manor_view()

	# 升级后刷新当前弹窗，让玩家可以连续升级而不必重新打开
	var popup = c.get_node_or_null("CourtyardTechPopup")
	if popup != null:
		_fill_technique_popup(popup)
