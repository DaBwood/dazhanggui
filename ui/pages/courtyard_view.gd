# ============================================================
# 宅院视图（庄园第三页签：技艺按钮 + 弹窗升级卷轴）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，data = GameData 数据中枢）
# UI 由 ManorView 的"宅院"页签触发，复用庄园滚动列表
# 最近批次见档案 §十一
# ============================================================
class_name CourtyardView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用
var _scroll_batch: Dictionary = {}   # 十连状态按卷独立（键 "tech|project|volume"，互不干扰）
var _tech_scroll: Dictionary = {}   # 弹窗滚动位置记忆（tech_id → 像素）

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
	btn.add_theme_font_size_override("font_size", 16)
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
	title.text = "%s" % cfg.get("name", tech_id)   # 标题去【】居中（与庄园弹窗同惯例）
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)

	var product = String(cfg.get("product", ""))
	var stock = Label.new()
	stock.text = "产物：%s ｜ 库存：%d" % [product, data.get_manor_goods_count(product)]
	stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stock)
	
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
	# 滚动记忆双保险：value_changed 连续记录（restored 闸门——恢复完成前不存档，防重建瞬态 0 覆盖存档）；
	#   位置两帧后恢复（单帧延迟赋值时机不可靠：布局 sort 可能晚于赋值，被钳回 0）
	scroll.get_v_scroll_bar().value_changed.connect(func(v):
		if bool(scroll.get_meta("restored", false)):
			_tech_scroll[tech_id] = int(v))
	_restore_scroll_later(scroll, int(_tech_scroll.get(tech_id, 0)))



# 两帧后恢复滚动位置：等容器布局算出最大滚动值再赋值；恢复完成置 restored 闸门，之后滚动才存档
func _restore_scroll_later(sc: ScrollContainer, v: int) -> void:
	if not is_instance_valid(sc):
		return
	await c.get_tree().process_frame
	await c.get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = v
		sc.set_meta("restored", true)

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

# 卷一/卷二升级卡（对齐庄园弹窗惯例）：左=卷名等级+效果 当前→下级 预览；右=升级钮+产物（拥有/需要 红绿）在钮下
func _build_scroll_row(tech: Dictionary, project_key: String, project: Dictionary, volume: String) -> PanelContainer:
	var tech_id = String(tech.get("id", ""))
	var level = data.get_courtyard_scroll_level(tech_id, project_key, volume)
	var is_vol1 = volume == "vol1"
	var cost = data.get_courtyard_scroll_cost(tech_id, project_key, volume)
	var product = String(tech.get("product", ""))
	var vol_name = "卷一" if is_vol1 else "卷二"

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	card.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	var title_lbl = Label.new()
	title_lbl.text = "%s Lv%d" % [vol_name, level]
	title_lbl.add_theme_font_size_override("font_size", 15)
	left.add_child(title_lbl)
	# 效果文本拆两行（当前一行/下级一行），禁自动换行——窄列折行难看（用户拍板）
	var info = Label.new()
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color("#bbbbbb"))
	info.text = _get_scroll_effect_text(project, volume, level)
	left.add_child(info)
	var next_lbl = Label.new()
	next_lbl.add_theme_font_size_override("font_size", 13)
	next_lbl.add_theme_color_override("font_color", Color("#bbbbbb"))
	next_lbl.text = "→ %s" % _get_scroll_effect_text(project, volume, level + 1)
	left.add_child(next_lbl)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	body.add_child(right)
	var btn = Button.new()
	btn.text = "升级"
	btn.custom_minimum_size = Vector2(90, 44)
	right.add_child(btn)
	btn.pressed.connect(_on_upgrade_scroll.bind(tech_id, project_key, volume))
	# 只显示升级所需数量（库存：xxx 在弹窗顶部已有，不重复拥有/需要）
	var have_n = int(data.get_manor_goods_count(product))
	var cost_lbl = Label.new()
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.text = "%s %s" % [product, c.format_number(int(cost))]
	cost_lbl.add_theme_color_override("font_color", c._cost_color(have_n, int(cost)))
	right.add_child(cost_lbl)
	# 该卷独立的"十连升级"勾选（放产物数量下面），状态按 "tech|project|volume" 记忆
	var batch_key = "%s|%s|%s" % [tech_id, project_key, volume]
	var batch_chk = CheckBox.new()
	batch_chk.text = "十连升级"
	batch_chk.button_pressed = bool(_scroll_batch.get(batch_key, false))
	batch_chk.add_theme_font_size_override("font_size", 12)
	batch_chk.toggled.connect(_on_scroll_batch_toggled.bind(batch_key))
	right.add_child(batch_chk)
	return card

# 卡片样式：与庄园弹窗升级卡同款（深底#221d33+淡紫描边）
func _make_card_style() -> StyleBoxFlat:
	var card_sty := StyleBoxFlat.new()
	card_sty.bg_color = Color("#221d33")
	card_sty.border_color = Color("#6a5f9e")
	card_sty.set_border_width_all(1)
	card_sty.set_corner_radius_all(6)
	card_sty.set_content_margin_all(8)
	return card_sty

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
# 每卷独立十连勾选变化：按 "tech|project|volume" 键记录，互不干扰
func _on_scroll_batch_toggled(key: String, pressed: bool):
	_scroll_batch[key] = pressed

# 升级卷轴：按该卷自己的十连勾选决定升 1 级还是 10 级
func _on_upgrade_scroll(tech_id: String, project_key: String, volume: String):
	var batch_key = "%s|%s|%s" % [tech_id, project_key, volume]
	var result: Dictionary
	# 十连状态按卷独立（勾选框在该卷卡片内）
	if bool(_scroll_batch.get(batch_key, false)):
		result = data.upgrade_courtyard_scroll_batch(tech_id, project_key, volume)
	else:
		result = data.upgrade_courtyard_scroll(tech_id, project_key, volume)

	if not result.ok:
		var pop2 = c.get_node_or_null("CourtyardTechPopup")
		if pop2 != null: c.flash_red(pop2.get_path())   # 操作失败反馈闪红
		c._show_success_popup(result.get("reason", "升级失败"), 0.0, "warn")   # 失败弹窗 warn 红（成功才 ok 金，口径见范式规范四.6）
	else:
		c.update_all_ui()
	c.update_manor_view()

	# 升级后刷新当前弹窗，让玩家可以连续升级而不必重新打开
	var popup = c.get_node_or_null("CourtyardTechPopup")
	if popup != null:
		_fill_technique_popup(popup)
