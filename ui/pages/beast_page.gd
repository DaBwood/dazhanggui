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

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func _create_beast_card() -> Button:
	var cell = Button.new()
	cell.custom_minimum_size = Vector2(200, 240)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
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


func update_beast_page():
	if not c.has_node("PageContainer/BeastPage/BeastVBox"): return
	var vbox = c.get_node("PageContainer/BeastPage/BeastVBox")
	vbox.get_node("BeastRes").text = "珍兽果：%d  |  奇香果：%d" % [data.beast_fruit, data.aroma_fruit]
	
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
			if name_lbl: name_lbl.text = "【%s】" % cfg.name
			
			var info_lbl = cell.find_child("BeastInfoLabel", true, false)
			if info_lbl: info_lbl.text = "Lv.%d  |  %s" % [instance.level, cfg.quality]
			
			var apt_lbl = cell.find_child("BeastAptLabel", true, false)
			if apt_lbl: apt_lbl.text = "资质：%d" % apt
			
			var bonus_lbl = cell.find_child("BeastBonusLabel", true, false)
			if bonus_lbl: bonus_lbl.text = "加成：%.0f%%" % (bonus * 100)
			
			var hero_lbl = cell.find_child("BeastHeroLabel", true, false)
			if hero_lbl: hero_lbl.text = "装备：%s" % (hero_name if hero_name != "" else "未装备")
			
			grid.add_child(cell)


func open_beast_detail(beast_id: String, instance_index: int):
	_close_beast_detail()
	_current_beast_id = beast_id
	_current_beast_index = instance_index
	
	var cfg = data.get_beast_config(beast_id)
	var instance = data.get_beast_instance(beast_id, instance_index)
	if instance == null: return
	
	var panel = c._create_base_popup("【%s】" % cfg.name, Vector2(520, 620), Vector2(316, 30))
	panel.name = "BeastDetailPanel"
	var vbox = panel.get_child(0)
	
	# 品质
	var quality_lbl = Label.new()
	quality_lbl.name = "BeastQualityLbl"
	quality_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(quality_lbl)
	
	# 资质行（文字 + 升级按钮）
	var apt_row = HBoxContainer.new()
	apt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	apt_row.add_theme_constant_override("separation", 12)
	vbox.add_child(apt_row)
	
	var apt_lbl = Label.new()
	apt_lbl.name = "BeastAptLbl"
	apt_row.add_child(apt_lbl)
	
	var up_btn = Button.new()
	up_btn.name = "BeastUpBtn"
	up_btn.custom_minimum_size = Vector2(120, 32)
	up_btn.pressed.connect(_on_beast_upgrade.bind(beast_id, instance_index))
	apt_row.add_child(up_btn)
	
	# 光环
	var aura_lbl = Label.new()
	aura_lbl.name = "BeastAuraLbl"
	aura_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aura_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(aura_lbl)
	
	# 技能列表标题行
	var skill_title_row = HBoxContainer.new()
	skill_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_title_row.add_theme_constant_override("separation", 16)
	vbox.add_child(skill_title_row)
	
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
	skill_scroll.custom_minimum_size = Vector2(0, 220)
	skill_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(skill_scroll)
	
	var skill_grid = GridContainer.new()
	skill_grid.name = "BeastSkillGrid"
	skill_grid.columns = 4
	skill_grid.add_theme_constant_override("h_separation", 8)
	skill_grid.add_theme_constant_override("v_separation", 8)
	skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(skill_grid)
	
	# 创建技能按钮
	var skill_count = cfg.get("skill_count", 0)
	for i in range(skill_count):
		var btn = Button.new()
		btn.name = "BeastSkillBtn_%d" % i
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_beast_skill_clicked.bind(i))
		skill_grid.add_child(btn)
	
	# 装备/卸下按钮
	var equip_btn = Button.new()
	equip_btn.name = "BeastEquipBtn"
	equip_btn.custom_minimum_size = Vector2(200, 40)
	equip_btn.pressed.connect(_on_beast_equip_toggle.bind(beast_id, instance_index))
	vbox.add_child(equip_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_beast_detail)
	vbox.add_child(close_btn)
	
	c.add_child(panel)
	c._current_popup = panel
	c.get_node("Overlay").show()
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
	var aura_lbl = vbox.get_node("BeastAuraLbl")
	var skill_bonus_lbl = vbox.find_child("BeastSkillBonusLbl", true, false)
	var equip_btn = vbox.get_node("BeastEquipBtn")
	
	var apt = data.get_beast_aptitude(beast_id, instance_index)
	var skill_bonus = data.get_beast_skill_bonus(beast_id, instance_index)
	
	quality_lbl.text = "品质：%s" % cfg.quality
	apt_lbl.text = "资质：%d（基础%d + 等级%d×8）" % [apt, cfg.aptitude, instance.level - 1]
	
	up_btn.text = "升级" if instance.level < 200 else "已满级"
	up_btn.disabled = instance.level >= 200 or data.beast_fruit < 80
	
	# 光环显示具体列表
	var auras = cfg.get("auras", [])
	if auras.is_empty():
		aura_lbl.text = "光环：无"
	else:
		var aura_texts = []
		for a in auras:
			aura_texts.append(a)
		aura_lbl.text = "光环：%s" % " | ".join(aura_texts)
	
	skill_bonus_lbl.text = "技能加成：%.0f%%" % (skill_bonus * 100)
	
	# 更新技能网格按钮
	var skills = instance.get("skills", [])
	var skill_grid = vbox.find_child("BeastSkillGrid", true, false)
	if skill_grid:
		for i in range(skill_grid.get_child_count()):
			var btn = skill_grid.get_child(i)
			if i < skills.size():
				btn.visible = true
				var sk = skills[i]
				var txt = "+%.0f%%" % (sk.percent * 100)
				if sk.percent >= 0.249:
					txt += " [满]"
					btn.disabled = true
				else:
					btn.disabled = false
				btn.text = txt
			else:
				btn.visible = false
	
	# 装备状态
	var hid = instance.get("equipped_hero", "")
	if hid != "":
		equip_btn.text = "卸下"
	else:
		equip_btn.text = "装备"

func _on_beast_upgrade(beast_id: String, instance_index: int):
	if data.upgrade_beast(beast_id, instance_index):
		_update_beast_detail(beast_id, instance_index)
		update_beast_page()
		c.update_all_ui()


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
			var b_cfg = data.get_beast_config(equipped_beast)
			status = " [%s]" % b_cfg.name
		
		btn.text = "【%s】%s Lv.%d | %s/秒%s" % [h.name, h.category, h.level, c.format_number(income), status]
		
		if not btn.disabled:
			btn.pressed.connect(_on_hero_equipped_beast.bind(hero_id, beast_id, instance_index))
		list.add_child(btn)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("HeroEquipSelector"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

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
		aroma_check.text = "使用奇香果（拥有：%d）" % data.aroma_fruit
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
				status_lbl.text = "奇香果：%d/1" % data.aroma_fruit
			else:
				var cost = 100 * int(pow(2, skill.refresh_count))
				status_lbl.text = "刷新消耗：%s 铜钱" % c.format_number(cost)
			status_lbl.remove_theme_color_override("font_color")
	
	if aroma_check:
		aroma_check.text = "使用奇香果（拥有：%d）" % data.aroma_fruit
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
	# 如果下层 HeroPanel 还开着...
	if c.has_node("HeroPanel") and c.get_node("HeroPanel").visible:
		c._current_popup = c.get_node("HeroPanel")
		c.get_node("Overlay").show()
		c.update_hero_panel()
	else:
		c.get_node("Overlay").hide()
		c._current_popup = null
