# ============================================================
# 珍兽页（含详情/技能刷新/装备）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name BeastPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var _current_beast_id: String = ""
var _current_beast_index: int = 0
var _selected_beast_skill_index: int = -1

# 【改】2026-09-18 回收弹窗选中态：卡片多选（key=beast_id:index）+ 底部确认，回收成功不关闭只刷新
var _recycle_selected_keys: Array = []
var _recycle_confirm_btn: Button = null

var _detail_tab: String = "skill"   # 【新增】珍兽详情页签：skill=技能 aura=光环

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func _create_beast_card() -> Button:
	var cell = Button.new()
	cell.custom_minimum_size = Vector2(180, 240)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 【修】手机端：按钮默认 STOP 拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.name = "BeastNameLabel"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_lbl)
	
	var info_lbl = Label.new()
	info_lbl.name = "BeastInfoLabel"
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(info_lbl)
	
	var apt_lbl = Label.new()
	apt_lbl.name = "BeastAptLabel"
	apt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apt_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(apt_lbl)
	
	var bonus_lbl = Label.new()
	bonus_lbl.name = "BeastBonusLabel"
	bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(bonus_lbl)
	
	var hero_lbl = Label.new()
	hero_lbl.name = "BeastHeroLabel"
	hero_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(hero_lbl)
	
	return cell

func generate_beast_page():
	if not c.has_node("PageContainer/BeastPage"): return
	var page = c.get_node("PageContainer/BeastPage")
	for child in page.get_children():
		child.queue_free()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.name = "BeastVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	page.add_child(vbox)
	
	var title = Label.new()
	title.text = "珍兽"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	var res = Label.new()
	res.name = "BeastRes"
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(res)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var grid = GridContainer.new()
	grid.name = "BeastGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	
	# 【新增】珍兽回收入口：页面底部
	var recycle_btn = Button.new()
	recycle_btn.text = "回收珍兽"
	recycle_btn.custom_minimum_size = Vector2(200, 40)
	recycle_btn.pressed.connect(_show_beast_recycle_panel)
	vbox.add_child(recycle_btn)


func update_beast_page():
	if not c.has_node("PageContainer/BeastPage/BeastVBox"): return
	var vbox = c.get_node("PageContainer/BeastPage/BeastVBox")
	# 【改】顶部资源补觉醒果
	vbox.get_node("BeastRes").text = "珍兽果：%d  |  奇香果：%d  |  觉醒果：%d" % [int(data.items.get("beast_fruit", 0)), int(data.items.get("aroma_fruit", 0)), int(data.items.get("awaken_fruit", 0))]
	
	var grid = vbox.find_child("BeastGrid", true, false)
	if grid == null: return
	for child in grid.get_children():
		child.queue_free()
	
	# 【改动】珍兽排序：已装备的排前面（按所装备门客的实时赚速降序），
	# 未装备的排最后面（按等级降序）——未装备无论等级多高都排在已装备之后
	var equipped_list = []     # 已装备实例：[beast_id, 实例下标, 门客赚速]
	var unequipped_list = []   # 未装备实例：[beast_id, 实例下标, 等级]
	for beast_id in data.beasts.keys():
		var raw = data.beasts[beast_id]
		var count = raw.size() if raw is Array else 1
		for i in range(count):
			var inst = data.get_beast_instance(beast_id, i)
			if inst == null: continue
			var eq_hid = inst.get("equipped_hero", "")
			if eq_hid != "" and data.heroes.has(eq_hid):
				equipped_list.append([beast_id, i, data.get_hero_income(eq_hid)])
			else:
				unequipped_list.append([beast_id, i, inst.level])
	equipped_list.sort_custom(func(a, b): return a[2] > b[2])     # 按门客赚速降序
	unequipped_list.sort_custom(func(a, b): return a[2] > b[2])   # 按等级降序

	for entry in equipped_list + unequipped_list:
		var beast_id = entry[0]   # 从排序结果取出 id 和实例下标
		var i = entry[1]
		if true:   # 保持原循环体缩进不变的最小改动写法
			var cfg = data.get_beast_config(beast_id)
			var instance = data.get_beast_instance(beast_id, i)
			if instance == null: continue
			
			var cell = _create_beast_card()
			cell.name = beast_id + "_" + str(i)
			cell.pressed.connect(open_beast_detail.bind(beast_id, i))
			
			var apt = data.get_beast_aptitude(beast_id, i)
			var bonus = data.get_beast_skill_bonus(beast_id, i) + data.get_beast_aura_bonus(beast_id, i)
			var hero_name = ""
			var hid = instance.get("equipped_hero", "")
			if hid != "" and data.heroes.has(hid):
				hero_name = data.heroes[hid].name
			
			var name_lbl = cell.find_child("BeastNameLabel", true, false)
			# 【改】2026-09-24 绑定兽（魅影兔）显示形态名（万年/十万年/百万年·魅影兔）
			if name_lbl: name_lbl.text = "【%s】" % data.beast_system.get_beast_display_name(beast_id)
			
			var info_lbl = cell.find_child("BeastInfoLabel", true, false)
			# 【改】2026-09-24 等级改读有效等级（自动满级兽=当前珍兽上限，随上限自动涨）
			if info_lbl: info_lbl.text = "Lv.%d  |  %s" % [data.beast_system.get_beast_level(beast_id, i), cfg.quality]
			
			var apt_lbl = cell.find_child("BeastAptLabel", true, false)
			if apt_lbl: apt_lbl.text = "资质：%d" % apt
			
			var bonus_lbl = cell.find_child("BeastBonusLabel", true, false)
			if bonus_lbl: bonus_lbl.text = "加成：%.0f%%" % (bonus * 100)
			
			var hero_lbl = cell.find_child("BeastHeroLabel", true, false)
			if hero_lbl: hero_lbl.text = "装备：%s" % (hero_name if hero_name != "" else "未装备")
			
			grid.add_child(cell)


# 【改】珍兽详情：弹窗改全屏页（z_index=20，盖门客面板z10；兽魂页z35再盖它）
# 节点名保持 BeastDetailPanel、仍挂 c 根节点、child(0)=VBoxContainer——_update_beast_detail 等引用全部不用动
func open_beast_detail(beast_id: String, instance_index: int):
	_close_beast_detail()
	_current_beast_id = beast_id
	_current_beast_index = instance_index
	
	var cfg = data.get_beast_config(beast_id)
	var instance = data.get_beast_instance(beast_id, instance_index)
	if instance == null: return
	
	# 全屏根面板：禁用锚点预设（项目坑#3），显式 position+size 铺满窗口；不透明底色直接盖住下层页面
	var panel = Panel.new()
	panel.name = "BeastDetailPanel"
	panel.z_index = 20
	panel.position = Vector2.ZERO
	panel.size = c.get_viewport_rect().size
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	panel.add_theme_stylebox_override("panel", bg)
	
	# 内容根容器：必须是 child(0)（_update_beast_detail 按 get_child(0) 取）；显式尺寸铺满
	var vbox = VBoxContainer.new()
	vbox.position = Vector2.ZERO
	vbox.size = panel.size
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# 顶栏：返回 + 标题（标题原由 _create_base_popup 生成，全屏化后自建）
	var top = HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 56)
	top.add_theme_constant_override("separation", 12)
	vbox.add_child(top)
	var back_btn = Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(120, 44)
	back_btn.pressed.connect(_close_beast_detail)
	top.add_child(back_btn)
	var title = Label.new()
	title.text = "【%s】" % cfg.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var pad = Control.new()   # 右侧占位，让标题视觉居中
	pad.custom_minimum_size = Vector2(120, 44)
	top.add_child(pad)
	
	# 品质
	var quality_lbl = Label.new()
	quality_lbl.name = "BeastQualityLbl"
	quality_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(quality_lbl)
	
	# 【新增】顶部留白：名字/品质独占干净顶栏，信息区整体下移（高度可调）
	var head_spacer = Control.new()
	head_spacer.custom_minimum_size = Vector2(0, 110)
	vbox.add_child(head_spacer)

	# 【改】信息行：左=等级/资质长框，右=魂力/兽魂/升级竖排三按钮
	var info_row = HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 20)
	vbox.add_child(info_row)
	
	# 【改】装备/卸下按钮：上移进信息行最左，与升级按钮同尺寸
	var equip_btn = Button.new()
	equip_btn.name = "BeastEquipBtn"
	equip_btn.custom_minimum_size = Vector2(110, 44)
	equip_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 【新增】不随行高拉伸，保持44高居中
	equip_btn.pressed.connect(_on_beast_equip_toggle.bind(beast_id, instance_index))
	info_row.add_child(equip_btn)
	
	# 长框：等级+资质（只显示当前值，不显示算式）
	var left_col = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(left_col)
	
	var top_pad = Control.new()
	top_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(top_pad)
	
	var apt_lbl = Label.new()
	apt_lbl.name = "BeastAptLbl"
	apt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_col.add_child(apt_lbl)

	# 右侧三按钮（顺序：魂力/兽魂/升级）
	var btn_col = VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 8)
	info_row.add_child(btn_col)

	var hunli_btn = Button.new()
	hunli_btn.text = "魂力"
	hunli_btn.custom_minimum_size = Vector2(110, 44)
	hunli_btn.pressed.connect(c.soulpower_view.show_hunli_view.bind(beast_id, instance_index))
	btn_col.add_child(hunli_btn)

	var soul_btn = Button.new()
	soul_btn.text = "兽魂"
	soul_btn.custom_minimum_size = Vector2(110, 44)
	soul_btn.pressed.connect(c.soul_view.show_soul_view.bind(beast_id, instance_index))
	btn_col.add_child(soul_btn)

	var up_btn = Button.new()
	up_btn.name = "BeastUpBtn"
	up_btn.custom_minimum_size = Vector2(110, 44)
	up_btn.pressed.connect(_on_beast_upgrade.bind(beast_id, instance_index))
	btn_col.add_child(up_btn)

	# 【改】技能/光环页签：技能在左（默认页），当前页签金色高亮
	var tab_row = HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 12)
	vbox.add_child(tab_row)

	var skill_tab = Button.new()
	skill_tab.name = "BeastSkillTab"
	skill_tab.text = "技能"
	skill_tab.custom_minimum_size = Vector2(110, 36)
	skill_tab.pressed.connect(func():
		_detail_tab = "skill"
		_update_beast_detail(_current_beast_id, _current_beast_index))
	tab_row.add_child(skill_tab)

	var aura_tab = Button.new()
	aura_tab.name = "BeastAuraTab"
	aura_tab.text = "光环"
	aura_tab.custom_minimum_size = Vector2(110, 36)
	aura_tab.pressed.connect(func():
		_detail_tab = "aura"
		_update_beast_detail(_current_beast_id, _current_beast_index))
	tab_row.add_child(aura_tab)

	# 光环区：多行容器（每只光环一行），内容在 _update_beast_detail 重填
	var aura_box = VBoxContainer.new()
	aura_box.name = "BeastAuraBox"
	aura_box.add_theme_constant_override("separation", 4)
	vbox.add_child(aura_box)

	# 技能区（标题 + 滚动网格），整体显隐随页签
	var skill_box = VBoxContainer.new()
	skill_box.name = "BeastSkillBox"
	skill_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_box.add_theme_constant_override("separation", 6)
	vbox.add_child(skill_box)

	var skill_title_row = HBoxContainer.new()
	skill_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_title_row.add_theme_constant_override("separation", 16)
	skill_box.add_child(skill_title_row)

	var skill_title = Label.new()
	skill_title.text = "技能列表"
	skill_title.add_theme_font_size_override("font_size", 18)
	skill_title.add_theme_color_override("font_color", Color("#ffd700"))
	skill_title_row.add_child(skill_title)

	var skill_bonus_lbl = Label.new()
	skill_bonus_lbl.name = "BeastSkillBonusLbl"
	skill_title_row.add_child(skill_bonus_lbl)

	# 技能网格滚动区
	var skill_scroll = ScrollContainer.new()
	skill_scroll.name = "BeastSkillScroll"
	skill_scroll.custom_minimum_size = Vector2(0, 320)
	skill_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_box.add_child(skill_scroll)

	var skill_grid = GridContainer.new()
	skill_grid.name = "BeastSkillGrid"
	skill_grid.columns = 4
	skill_grid.add_theme_constant_override("h_separation", 8)
	skill_grid.add_theme_constant_override("v_separation", 8)
	skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(skill_grid)

	# 创建初始技能按钮
	var skill_count = cfg.get("skill_count", 0)
	for i in range(skill_count):
		var btn = Button.new()
		btn.name = "BeastSkillBtn_%d" % i
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_beast_skill_clicked.bind(i))
		skill_grid.add_child(btn)

	# 技能列表最后的“+”觉醒按钮
	var awaken_btn = Button.new()
	awaken_btn.name = "BeastAwakenBtn"
	awaken_btn.text = "+"
	awaken_btn.custom_minimum_size = Vector2(0, 40)
	awaken_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	awaken_btn.pressed.connect(_show_awaken_confirm.bind(beast_id, instance_index))
	skill_grid.add_child(awaken_btn)
	
	
	c.add_child(panel)
	_update_beast_detail(beast_id, instance_index)


func _update_beast_detail(beast_id: String, instance_index: int):
	if not c.has_node("BeastDetailPanel"): return
	var cfg = data.get_beast_config(beast_id)
	var instance = data.get_beast_instance(beast_id, instance_index)
	if instance == null: return
	
	var vbox = c.get_node("BeastDetailPanel").get_child(0)
	var quality_lbl = vbox.get_node("BeastQualityLbl")
	var apt_lbl = vbox.find_child("BeastAptLbl", true, false)
	var up_btn = vbox.find_child("BeastUpBtn", true, false)
	var skill_bonus_lbl = vbox.find_child("BeastSkillBonusLbl", true, false)
	var equip_btn = vbox.find_child("BeastEquipBtn", true, false)   # 【改】按钮已移进信息行，递归找
	
	var apt = data.get_beast_aptitude(beast_id, instance_index)
	var skill_bonus = data.get_beast_skill_bonus(beast_id, instance_index)
	
	quality_lbl.text = "品质：%s" % cfg.quality
	var b_lv: int = data.beast_system.get_beast_level(beast_id, instance_index)   # 【改】2026-09-24 有效等级（自动满级兽=当前上限）
	apt_lbl.text = "等级：%d  资质：%d" % [b_lv, apt]   # 【改】等级资质一行；资质只显示当前值（去算式）
	
	var max_lv = data.beast_system.get_beast_max_level(beast_id, instance_index)   # 【改】上限含光环三加成（原写死200）
	var auto_full: bool = cfg.get("auto_max_level", false)   # 【新增】2026-09-24 自动满级兽（魅影兔）不可手动升级
	up_btn.text = "已满级（自动）" if auto_full else (("升级\n珍兽果%d/80" % int(data.items.get("beast_fruit", 0))) if b_lv < max_lv else "已满级")   # 【改】读道具轨+显示消耗
	up_btn.disabled = auto_full or b_lv >= max_lv or int(data.items.get("beast_fruit", 0)) < 80   # 【改】
	
	# 【改】光环区重填（一光环一行，带数值与升级按钮；原"光环：a|b|c"单标签逻辑删除）
	_fill_aura_box(vbox.get_node("BeastAuraBox"), beast_id, instance_index)
	
	skill_bonus_lbl.text = "技能加成：%.0f%%" % (skill_bonus * 100)
	
	# 【改】更新技能网格按钮；觉醒新增技能不足时自动补按钮，并保持“+”在最后
	var bs = data.beast_system
	var skills = instance.get("skills", [])
	var skill_grid = vbox.find_child("BeastSkillGrid", true, false)
	if skill_grid:
		var awaken_btn = skill_grid.find_child("BeastAwakenBtn", true, false)

		# 觉醒后技能数量可能超过初始按钮数，先补按钮
		while skill_grid.get_child_count() - 1 < skills.size():
			var new_index = skill_grid.get_child_count() - 1
			var new_btn = Button.new()
			new_btn.name = "BeastSkillBtn_%d" % new_index
			new_btn.custom_minimum_size = Vector2(0, 40)
			new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			new_btn.pressed.connect(_on_beast_skill_clicked.bind(new_index))
			skill_grid.add_child(new_btn)
			if awaken_btn:
				skill_grid.move_child(new_btn, max(0, skill_grid.get_child_count() - 2))

		for child in skill_grid.get_children():
			if not child.name.begins_with("BeastSkillBtn_"):
				continue
			var i = int(child.name.trim_prefix("BeastSkillBtn_"))
			if i < skills.size():
				child.visible = true
				var sk = skills[i]
				var txt = "+%.0f%%" % (sk.percent * 100)
				if sk.percent >= 0.249:
					txt += " [满]"
					child.disabled = true
				else:
					child.disabled = false
				child.text = txt
			else:
				child.visible = false

		# 【改】更新“+”按钮状态（次数/消耗不再显示在面上，点+弹确认窗查看）
		var acount = bs.get_awaken_count(beast_id, instance_index)
		var alimit = bs.get_awaken_limit(beast_id, instance_index)
		var acost = bs.get_awaken_cost(beast_id, instance_index)
		if awaken_btn:
			awaken_btn.disabled = acount >= alimit or int(data.items.get("awaken_fruit", 0)) < acost
	
	# 【新增】页签显隐 + 高亮同步：当前页金色，未选中灰
	var aura_box = vbox.get_node("BeastAuraBox")
	var skill_box = vbox.find_child("BeastSkillBox", true, false)
	if aura_box and skill_box:
		aura_box.visible = _detail_tab == "aura"
		skill_box.visible = _detail_tab == "skill"
	var skill_tab = vbox.find_child("BeastSkillTab", true, false)
	var aura_tab = vbox.find_child("BeastAuraTab", true, false)
	if skill_tab:
		skill_tab.add_theme_color_override("font_color", Color("#ffd700") if _detail_tab == "skill" else Color(0.55, 0.55, 0.6))
	if aura_tab:
		aura_tab.add_theme_color_override("font_color", Color("#ffd700") if _detail_tab == "aura" else Color(0.55, 0.55, 0.6))
	
	# 装备状态
	var hid = instance.get("equipped_hero", "")
	if hid != "":
		equip_btn.text = "卸下"
	else:
		equip_btn.text = "装备"
	# 【改】2026-09-24 绑定兽（魅影兔）不可卸下：直接隐藏卸下/装备钮（用户拍板不显示）；
	# 系统层 unequip_beast 守卫仍在，双保险
	if cfg.get("locked", false):
		equip_btn.visible = false

func _on_beast_upgrade(beast_id: String, instance_index: int):
	if data.upgrade_beast(beast_id, instance_index):
		_update_beast_detail(beast_id, instance_index)
		update_beast_page()
		c.update_all_ui()

# 【新增】珍兽觉醒：成功只刷新界面，不额外弹成功文字
func _on_beast_awaken(beast_id: String, instance_index: int):
	var res: Dictionary = data.beast_system.awaken_beast(beast_id, instance_index)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "觉醒失败"))
		return
	_update_beast_detail(beast_id, instance_index)
	update_beast_page()
	c.update_bag_list()
	c.update_all_ui()

# 【新增】觉醒确认弹窗：+号点击先显示本次消耗与拥有，确认后才执行觉醒
func _show_awaken_confirm(beast_id: String, instance_index: int):
	var bs = data.beast_system
	var acost = bs.get_awaken_cost(beast_id, instance_index)
	var have = int(data.items.get("awaken_fruit", 0))
	var popup = c._create_base_popup("珍兽觉醒", Vector2(400, 240), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
	popup.name = "BeastAwakenConfirmPopup"
	var vbox = popup.get_child(0)
	var info = Label.new()
	info.text = "本次觉醒消耗：觉醒果×%d\n当前拥有：觉醒果×%d" % [acost, have]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右，动作含义写进标题/正文
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("BeastAwakenConfirmPopup"))
	btn_row.add_child(cancel)
	var ok = Button.new()
	ok.text = "确定"
	ok.disabled = have < acost
	ok.pressed.connect(func():
		c._safe_close("BeastAwakenConfirmPopup")
		_on_beast_awaken(beast_id, instance_index))
	btn_row.add_child(ok)
	c.add_child(popup)

func _on_beast_equip_toggle(beast_id: String, instance_index: int):
	var instance = data.get_beast_instance(beast_id, instance_index)
	if instance == null: return
	var hid = instance.get("equipped_hero", "")
	if hid != "":
		data.unequip_beast(hid)
		_update_beast_detail(beast_id, instance_index)
		update_beast_page()
		c.update_hero_panel()
		c.update_all_ui()
	else:
		_show_hero_equip_selector(beast_id, instance_index)

func _show_hero_equip_selector(beast_id: String, instance_index: int):
	
	# 关闭技能刷新面板，避免层级冲突
	_close_beast_skill_refresh_panel()
	var panel = c._create_base_popup("选择门客装备", Vector2(460, 400), Vector2(346, 120))
	panel.name = "HeroEquipSelector"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	# 【改】门客按实时赚速降序排列（原按字典顺序）
	var hero_ids = data.heroes.keys()
	hero_ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hero_id in hero_ids:
		var h = data.heroes[hero_id]
		var btn = Button.new()
		
		var income = data.get_hero_income(hero_id)
		
		# 【新增】装备状态
		var status = ""
		var equipped_beast = h.get("equipped_beast", "")
		if equipped_beast == beast_id and h.get("equipped_beast_index", 0) == instance_index:
			status = " [已装备]"
			btn.disabled = true
		elif equipped_beast != "":
			# 【改】2026-09-24 绑定兽（魅影兔）显示形态名
			status = " [%s]" % data.beast_system.get_beast_display_name(equipped_beast)
		# 【新增】2026-09-24 绑定兽双向锁死：非其专属门客不可选；专属门客（小舞）已带绑定兽不可再装此兽
		if data.get_beast_config(beast_id).get("locked", false) and str(data.get_beast_config(beast_id).get("bound_hero", "")) != hero_id:
			status = " [小舞专属]"
			btn.disabled = true
		elif equipped_beast != "" and data.get_beast_config(equipped_beast).get("locked", false):
			status = " [专属绑定]"
			btn.disabled = true
		
		btn.text = "【%s】%s Lv.%d | %s/秒%s" % [h.name, h.category, h.level, c.format_number(income), status]
		
		if not btn.disabled:
			btn.pressed.connect(_on_hero_equipped_beast.bind(hero_id, beast_id, instance_index))
		list.add_child(btn)
	
	
	c.add_child(panel)

# 【改】2026-09-18 珍兽回收面板：驺虞/白泽卡片多选（3列网格），回收成功不关闭只刷新
func _show_beast_recycle_panel():
	if c.has_node("BeastRecyclePanel"): return
	_recycle_selected_keys.clear()

	var panel = c._create_base_popup("回收珍兽", Vector2(520, 420))
	# 【改】UI统一批次①：回收勾选状态清理挂 tree_exiting——右上✕/任意关闭路径都会清（原只在底部【关闭】钮回调里）
	panel.tree_exiting.connect(func():
		_recycle_selected_keys.clear()
		_recycle_confirm_btn = null
	)
	panel.name = "BeastRecyclePanel"
	var vbox = panel.get_child(0)

	# 【改】2026-09-18 回收区改 3 列卡片多选：驺虞/白泽同规则（未装备才可回收，返觉醒果×15 / 珍兽果×400）
	var scroll = ScrollContainer.new()
	scroll.name = "RecycleScroll"
	scroll.custom_minimum_size = Vector2(480, 300)
	vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.name = "RecycleGrid"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	_fill_beast_recycle_cards(grid)

	# 底部操作：回收 / 关闭 并列（回收成功不关闭，见 _on_recycle_selected）
	var bottom = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 12)
	vbox.add_child(bottom)

	_recycle_confirm_btn = Button.new()
	_recycle_confirm_btn.text = "回收"
	_recycle_confirm_btn.custom_minimum_size = Vector2(120, 40)
	_recycle_confirm_btn.disabled = true
	_recycle_confirm_btn.pressed.connect(_on_recycle_selected)
	bottom.add_child(_recycle_confirm_btn)


	c.add_child(panel)

# 【新增】2026-09-18 回收卡片网格：按钮卡片 + ☑/☐ 多选，装备中的珍兽置灰并给原因
func _fill_beast_recycle_cards(grid):
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var recyclable_ids := ["zou_yu", "bai_ze"]
	var total := 0
	for beast_id in recyclable_ids:
		total += data.beast_system.get_beast_instance_count(beast_id)
	if total <= 0:
		var empty = Label.new()
		empty.text = "当前没有可回收的驺虞/白泽"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(empty)
		return

	for beast_id in recyclable_ids:
		var cfg = data.get_beast_config(beast_id)
		var count = data.beast_system.get_beast_instance_count(beast_id)
		for i in range(count):
			var inst = data.get_beast_instance(beast_id, i)
			if inst == null: continue
			var info = data.beast_system.get_beast_recycle_info(beast_id, i)

			var eq = inst.get("equipped_hero", "")
			var eq_name = "未装备"
			if eq != "" and data.heroes.has(eq):
				eq_name = data.heroes[eq].name

			var key := "%s:%d" % [beast_id, i]
			var selected: bool = _recycle_selected_keys.has(key)
			var base_text := "%s #%d\nLv.%d（%s）" % [cfg.get("name", beast_id), i + 1, inst.level, eq_name]
			var card := Button.new()
			card.custom_minimum_size = Vector2(150, 64)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.mouse_filter = Control.MOUSE_FILTER_PASS
			card.add_theme_font_size_override("font_size", 12)
			card.disabled = not info.get("ok", false)
			card.tooltip_text = info.get("reason", "") if not info.get("ok", false) else "点击选中/取消（可多选）"
			card.pressed.connect(_on_recycle_card_clicked.bind(beast_id, i, card, base_text))
			grid.add_child(card)
			_set_recycle_card_visual(card, base_text, selected)

# 【新增】多选卡片视觉：☑/☐ + 选中金字（用户要“特效或勾选框”，这里用勾选框+变色）
func _set_recycle_card_visual(btn, base_text: String, selected: bool):
	btn.text = ("☑ " if selected else "☐ ") + base_text
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if selected else Color(0.9, 0.85, 0.75))

# 【修】2026-09-18 选中key有效性：数据里已不存在的实例不可再被选中/回收
func _recycle_key_exists(key) -> bool:
	var parts := String(key).split(":")
	if parts.size() != 2:
		return false
	return data.get_beast_instance(parts[0], int(parts[1])) != null

# 【修】剔除失效选中key；返回是否有剔除（供调用方决定是否原地刷新）
func _prune_recycle_selection() -> bool:
	var removed: bool = false
	for key in _recycle_selected_keys.duplicate():
		if not _recycle_key_exists(key):
			_recycle_selected_keys.erase(key)
			removed = true
	if _recycle_confirm_btn:
		_recycle_confirm_btn.disabled = _recycle_selected_keys.is_empty()
	return removed

func _on_recycle_card_clicked(beast_id: String, instance_index: int, card, base_text: String):
	# 卡片是旧帧残留时，点一下也触发剔除并重建网格，防止“不存在还能选”
	if data.get_beast_instance(beast_id, instance_index) == null:
		_prune_recycle_selection()
		_refresh_beast_recycle_panel()
		return
	var key := "%s:%d" % [beast_id, instance_index]
	if _recycle_selected_keys.has(key):
		_recycle_selected_keys.erase(key)
	else:
		_recycle_selected_keys.append(key)
	_set_recycle_card_visual(card, base_text, _recycle_selected_keys.has(key))
	if _recycle_confirm_btn:
		_recycle_confirm_btn.disabled = _recycle_selected_keys.is_empty()

func _on_recycle_selected():
	var had_selection: bool = not _recycle_selected_keys.is_empty()
	# 先剔除已不存在/状态变化的旧选中，避免拿旧下标去回收导致一串“珍兽不存在”
	if _prune_recycle_selection():
		_refresh_beast_recycle_panel()
	if _recycle_selected_keys.is_empty():
		if had_selection:
			c._show_stage_hint("所选珍兽已不存在或状态变化，请重新选择")
		else:
			c.flash_red(_recycle_confirm_btn.get_path())   # 【新增】闪红审计：操作失败反馈（2026-09-19）
			c._show_stage_hint("请先点击卡片选择要回收的珍兽（可多选）")
		return

	# 批量回收：同种珍兽按下标倒序删，避免先删小号导致后续下标位移
	var by_beast := {}
	for key in _recycle_selected_keys.duplicate():
		var parts := String(key).split(":")
		var bid := parts[0]
		if not by_beast.has(bid):
			by_beast[bid] = []
		by_beast[bid].append(int(parts[1]))

	var ok_count := 0
	var total_awaken := 0
	var total_beast := 0
	var fail_parts := []
	for bid in by_beast.keys():
		var idxs = by_beast[bid]
		idxs.sort()
		idxs.reverse()
		for idx in idxs:
			var res: Dictionary = data.beast_system.recycle_beast(bid, idx)
			if res.get("ok", false):
				ok_count += 1
				total_awaken += int(res.get("awaken_fruit", 0))
				total_beast += int(res.get("beast_fruit", 0))
			else:
				fail_parts.append(str(res.get("reason", "回收失败")))

	if ok_count <= 0:
		# 全失败也原地刷新并剔除失效key；不能只飘字不重建，否则旧卡片会继续可选
		_prune_recycle_selection()
		_refresh_beast_recycle_panel()
		var fail_msg := "未知原因"
		if not fail_parts.is_empty():
			fail_msg = "；".join(fail_parts)
		c.flash_red(_recycle_confirm_btn.get_path())   # 【新增】闪红审计：操作失败反馈（2026-09-19）
		c._show_stage_hint("回收失败：" + fail_msg)
		return

	var msg := "回收珍兽×%d：觉醒果×%d / 珍兽果×%d" % [ok_count, total_awaken, total_beast]
	if not fail_parts.is_empty():
		msg += "（失败：%s）" % "；".join(fail_parts)
	c._show_stage_hint(msg)

	_recycle_selected_keys.clear()
	if _recycle_confirm_btn:
		_recycle_confirm_btn.disabled = true
	# 【修】2026-09-18 先原地刷新回收网格，再刷新主界面/全局UI；旧卡片立即remove_child，避免queue_free延迟造成“回收后还在”
	_refresh_beast_recycle_panel()
	update_beast_page()
	c.update_bag_list()
	c.update_hero_panel()
	c.update_all_ui()

# 【新增】回收成功后原地刷新卡片网格（不关窗口）
func _refresh_beast_recycle_panel():
	if not c.has_node("BeastRecyclePanel"): return
	_prune_recycle_selection()
	var panel = c.get_node("BeastRecyclePanel")
	# 【修】2026-09-18 弹窗真实结构是 panel -> vbox(未命名) -> RecycleScroll -> RecycleGrid；
	#        NodePath "RecycleScroll/RecycleGrid" 要求逐级直接子节点，会找不到而不刷新；改递归 find_child。
	var grid = panel.find_child("RecycleGrid", true, false)
	if grid:
		_fill_beast_recycle_cards(grid)


func _on_hero_equipped_beast(hero_id: String, beast_id: String, instance_index: int):
	data.equip_beast(hero_id, beast_id, instance_index)
	c._safe_close("HeroEquipSelector")
	update_beast_page()
	c.update_all_ui()

func _on_beast_skill_clicked(skill_index: int):
	_selected_beast_skill_index = skill_index
	_show_beast_skill_refresh_panel()

func _show_beast_skill_refresh_panel():
	var parent = c.get_node("BeastDetailPanel")
	if parent == null: return
	if parent.has_node("BeastSkillRefreshPanel"): return
	
	var instance = data.get_beast_instance(_current_beast_id, _current_beast_index)
	if instance == null: return
	var skills = instance.get("skills", [])
	if _selected_beast_skill_index < 0 or _selected_beast_skill_index >= skills.size(): return
	var skill = skills[_selected_beast_skill_index]
	
	var panel = PanelContainer.new()
	panel.name = "BeastSkillRefreshPanel"
	panel.custom_minimum_size = Vector2(360, 260)
	panel.position = (parent.size - panel.custom_minimum_size) / 2
	panel.z_index = 50
	
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
	title.text = "技能槽位 #%d" % (_selected_beast_skill_index + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	# 当前加成
	var bonus_lbl = Label.new()
	bonus_lbl.name = "BeastSkillBonus"
	bonus_lbl.text = "当前加成：+%.0f%%" % (skill.percent * 100)
	bonus_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(bonus_lbl)
	
	# 状态/消耗
	var status_lbl = Label.new()
	status_lbl.name = "BeastSkillStatus"
	vbox.add_child(status_lbl)
	
	# 勾选框
	if skill.percent < 0.249:
		var aroma_check = CheckBox.new()
		aroma_check.name = "AromaCheck"
		aroma_check.text = "使用奇香果（拥有：%d）" % int(data.items.get("aroma_fruit", 0))
		vbox.add_child(aroma_check)
	
	# 按钮区
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	if skill.percent < 0.249:
		var refresh_btn = Button.new()
		refresh_btn.name = "BeastSkillRefreshBtn"
		refresh_btn.text = "刷新"
		refresh_btn.custom_minimum_size = Vector2(100, 40)
		refresh_btn.pressed.connect(_on_refresh_beast_skill)
		btn_box.add_child(refresh_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.pressed.connect(_close_beast_skill_refresh_panel)
	btn_box.add_child(close_btn)
	
	parent.add_child(panel)
	_update_beast_skill_refresh_panel()

func _update_beast_skill_refresh_panel():
	var parent = c.get_node("BeastDetailPanel")
	var panel = parent.get_node_or_null("BeastSkillRefreshPanel")
	if not panel: return
	
	var instance = data.get_beast_instance(_current_beast_id, _current_beast_index)
	if instance == null: return
	var skills = instance.get("skills", [])
	if _selected_beast_skill_index < 0 or _selected_beast_skill_index >= skills.size(): return
	var skill = skills[_selected_beast_skill_index]
	
	var bonus_lbl = panel.find_child("BeastSkillBonus", true, false)
	if bonus_lbl:
		bonus_lbl.text = "当前加成：+%.0f%%" % (skill.percent * 100)
	
	var status_lbl = panel.find_child("BeastSkillStatus", true, false)
	var aroma_check = panel.find_child("AromaCheck", true, false)
	if status_lbl:
		if skill.percent >= 0.249:
			status_lbl.text = "已满级"
			status_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			var use_aroma = aroma_check != null and aroma_check.button_pressed
			if use_aroma:
				status_lbl.text = "奇香果：%d/1" % int(data.items.get("aroma_fruit", 0))
			else:
				var cost = 100 * int(pow(2, skill.refresh_count))
				status_lbl.text = "刷新消耗：%s 铜钱" % c.format_number(cost)
			status_lbl.remove_theme_color_override("font_color")
	
	if aroma_check:
		aroma_check.text = "使用奇香果（拥有：%d）" % int(data.items.get("aroma_fruit", 0))
		if skill.percent >= 0.249:
			aroma_check.visible = false
	
	var refresh_btn = panel.find_child("BeastSkillRefreshBtn", true, false)
	if skill.percent >= 0.249:
		if refresh_btn:
			refresh_btn.queue_free()
		if aroma_check:
			aroma_check.queue_free()
	else:
		if refresh_btn:
			refresh_btn.text = "刷新"

func _on_refresh_beast_skill():
	if _selected_beast_skill_index < 0: return
	var parent = c.get_node("BeastDetailPanel")
	var panel = parent.get_node_or_null("BeastSkillRefreshPanel")
	var use_aroma = false
	if panel:
		var aroma_check = panel.find_child("AromaCheck", true, false)
		if aroma_check:
			use_aroma = aroma_check.button_pressed
	
	if data.refresh_beast_skill(_current_beast_id, _current_beast_index, _selected_beast_skill_index, use_aroma):
		_update_beast_detail(_current_beast_id, _current_beast_index)
		update_beast_page()
		c.update_all_ui()
		c.update_bag_list()
		var instance = data.get_beast_instance(_current_beast_id, _current_beast_index)
		var skills = instance.get("skills", [])
		var skill = skills[_selected_beast_skill_index]
		if skill.percent >= 0.249:
			_close_beast_skill_refresh_panel()
		else:
			_update_beast_skill_refresh_panel()
	else:
		var panel2 = c.get_node("BeastDetailPanel").get_node_or_null("BeastSkillRefreshPanel")
		if panel2:
			var refresh_btn = panel2.find_child("BeastSkillRefreshBtn", true, false)
			if refresh_btn:
				c.flash_red(refresh_btn.get_path())

func _close_beast_skill_refresh_panel():
	var parent = c.get_node_or_null("BeastDetailPanel")
	if parent == null: return
	var panel = parent.get_node_or_null("BeastSkillRefreshPanel")
	if panel:
		panel.queue_free()

# 【改】全屏页关闭：只清节点，不再碰 _current_popup/Overlay（全屏页不透明直盖下层，返回即露出）
func _close_beast_detail():
	# 先关闭内层面板
	if c.has_node("BeastDetailPanel/BeastSkillRefreshPanel"):
		var inner = c.get_node("BeastDetailPanel/BeastSkillRefreshPanel")
		inner.get_parent().remove_child(inner)
		inner.queue_free()
	# 立即从场景树移除旧面板，避免同名冲突
	if c.has_node("BeastDetailPanel"):
		var old = c.get_node("BeastDetailPanel")
		old.get_parent().remove_child(old)
		old.queue_free()
	# 下层门客面板若开着，刷新一次对账（珍兽装备/资质可能变了）
	if c.has_node("HeroPanel") and c.get_node("HeroPanel").visible:
		c.update_hero_panel()

# 【新增】填充光环区：光环一=系列自动加成（不可升级）；光环二=+5%/级（星神为全局技能倍率），集齐系列解锁升级；光环三=+1等级上限/级，光环二满级解锁；无光环兽显示"无"
func _fill_aura_box(aura_box, beast_id: String, instance_index: int):
	for child in aura_box.get_children():
		child.queue_free()
	var bs = data.beast_system
	var cfg = data.get_beast_config(beast_id)
	var auras = cfg.get("auras", [])
	if auras.is_empty():
		var none_lbl = Label.new()
		none_lbl.text = "光环：无"
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		aura_box.add_child(none_lbl)
		return
	# 光环一：系列光环（不可升级）
	var r1 = HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	var l1 = Label.new()
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.text = "%s：+%.0f%%　（系列光环·随数量自动加成）" % [auras[0], bs.get_aura1_bonus(beast_id) * 100]
	r1.add_child(l1)
	aura_box.add_child(r1)
	# 光环二：每级+5%（星神系列为全局技能倍率），集齐系列解锁升级
	if auras.size() >= 2:
		var lv2 = bs.get_aura2_lv(beast_id, instance_index)
		var r2 = HBoxContainer.new()
		r2.add_theme_constant_override("separation", 8)
		var l2 = Label.new()
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bs.is_star_series(beast_id):
			l2.text = "%s：全珍兽技能加成×%d%%　（Lv.%d/20）" % [auras[1], int(bs.get_star_skill_multiplier() * 100), lv2]
		else:
			l2.text = "%s：+%.0f%%　（Lv.%d/20）" % [auras[1], bs.get_aura2_bonus(beast_id, instance_index) * 100, lv2]
		r2.add_child(l2)
		r2.add_child(_make_aura_btn(beast_id, instance_index, 2))
		aura_box.add_child(r2)
	# 光环三：每级+1等级上限，光环二满级解锁（星神系列无光环三，整行不显示）
	if auras.size() >= 3:
		var lv3 = bs.get_aura3_lv(beast_id, instance_index)
		var r3 = HBoxContainer.new()
		r3.add_theme_constant_override("separation", 8)
		var l3 = Label.new()
		l3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l3.text = "%s：全体珍兽上限+%d　（Lv.%d/20）" % [auras[2], lv3, lv3]   # 【改】标明光环三全局生效
		r3.add_child(l3)
		r3.add_child(_make_aura_btn(beast_id, instance_index, 3))
		aura_box.add_child(r3)

# 【新增】光环升级按钮：满级/未解锁置灰显示条件；可升级时显示消耗（当前等级×10个兑换道具），道具不足置灰
func _make_aura_btn(beast_id: String, instance_index: int, which: int) -> Button:
	var bs = data.beast_system
	var cfg = data.get_beast_config(beast_id)
	var lv = bs.get_aura2_lv(beast_id, instance_index) if which == 2 else bs.get_aura3_lv(beast_id, instance_index)
	var unlocked = bs.can_upgrade_aura2(beast_id) if which == 2 else bs.can_upgrade_aura3(beast_id, instance_index)
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(170, 32)
	if lv >= 20:
		btn.text = "已满级"
		btn.disabled = true
	elif not unlocked:
		btn.text = "集齐系列解锁" if which == 2 else "光环二满级解锁"
		btn.disabled = true
	else:
		var item = cfg.get("exchange_item", "")
		var iname = data.ITEM_CONFIG.get(item, {}).get("name", item)
		var cost = bs.get_aura_upgrade_cost(beast_id, instance_index, which)
		btn.text = "升级（%s×%d）" % [iname, cost]
		btn.disabled = int(data.items.get(item, 0)) < cost
		btn.pressed.connect(_on_aura_upgrade.bind(beast_id, instance_index, which))
	return btn

# 【新增】光环升级回调：成功后面板原地重填+刷新珍兽页/背包（赚速经 HeroData 自动对账）
func _on_aura_upgrade(beast_id: String, instance_index: int, which: int):
	var res: Dictionary = data.beast_system.upgrade_aura(beast_id, instance_index, which)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "升级失败"))
		return
	_update_beast_detail(beast_id, instance_index)
	c.update_beast_page()
	c.update_bag_list()
