# ============================================================
# 门客渔获装备界面（第8批新增：HeroPanel 珍兽按钮旁【渔获】按钮打开）
# 纯代码 UI 模块：var c（game_controller 根脚本）、var data（GameData 中枢）
# 弹窗式（参照既有 _create_base_popup 用法）：主弹窗 FishEquipPopup，喂养材料弹窗 FishFeedPopup
# 刷新策略：操作后原地重填弹窗内容并保留滚动位置；同时刷新门客面板使赚速/资质对账
# ============================================================
class_name FishEquipView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

var _hero_id: String = ""   # 当前操作的门客（弹窗打开期间）

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 主弹窗 ============
# 打开渔获装备弹窗（由 HeroPanel 渔获按钮触发）
func show_fish_equip_view(hero_id: String):
	if not data.heroes.has(hero_id): return
	_hero_id = hero_id
	# 已存在则先关，保证内容重建
	_close_popup("FishEquipPopup")
	var popup = c._create_base_popup("渔获装备", Vector2(560, 600))
	popup.name = "FishEquipPopup"
	c.add_child(popup)
	_fill_equip_popup(popup)

# 重填主弹窗内容（保留滚动位置）
func _fill_equip_popup(popup):
	var vb = popup.get_child(0)
	var scroll = vb.get_node_or_null("EquipScroll")
	var sv = scroll.scroll_vertical if scroll else 0
	# 清空旧内容（保留标题，标题是 vb 第一个子节点）
	for child in vb.get_children():
		if child is Label and child.text == "渔获装备": continue
		child.queue_free()

	var fs = data.fishing_system
	var fish_id = fs.get_hero_fish(_hero_id)

	# 说明
	var hint = Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#aaaaaa"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "仅无双/传奇/普通渔获可装备，一种渔获只能装备一名门客"
	vb.add_child(hint)

	if fish_id == "":
		# ---- 未装备：显示可装备渔获列表 ----
		var scroll2 = ScrollContainer.new()
		scroll2.name = "EquipScroll"
		scroll2.custom_minimum_size = Vector2(0, 440)
		scroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(scroll2)
		var list = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll2.add_child(list)
		_build_fish_selector(list)
	else:
		# ---- 已装备：养成面板 ----
		_build_dev_panel(vb, fish_id)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	# 恢复滚动位置
	if scroll:
		var new_scroll = vb.get_node_or_null("EquipScroll")
		if new_scroll: new_scroll.set_deferred("scroll_vertical", sv)

# 可装备渔获列表（库存≥1、未被其他门客占用）
func _build_fish_selector(list: VBoxContainer):
	var fs = data.fishing_system
	var any = false
	for f in fs.get_dex_entries():
		if not fs.is_fish_equippable(f.id): continue
		var cnt = int(data.fishing_storage.get(f.id, 0))
		if cnt < 1: continue
		var holder = fs.get_fish_equipped_hero(f.id)
		if holder != "" and holder != _hero_id: continue
		any = true
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "【%s】%s ×%d（%d阶）" % [f.get("quality", ""), f.get("name", f.id), cnt, fs.get_fish_tier(f.id)]
		lbl.add_theme_color_override("font_color", _quality_color(f.get("quality", "无")))
		row.add_child(lbl)
		var btn = Button.new()
		btn.text = "装备"
		btn.custom_minimum_size = Vector2(80, 40)
		btn.pressed.connect(_on_equip.bind(f.id))
		row.add_child(btn)
		list.add_child(row)
	if not any:
		var empty_lbl = Label.new()
		empty_lbl.text = "暂无可装备的渔获\n（去【闯荡-垂钓】钓取无双/传奇/普通渔获）"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(empty_lbl)

# 已装备的养成面板：信息行 + 晋升/卸下 + 技能列表
func _build_dev_panel(vb, fish_id: String):
	var fs = data.fishing_system
	var quality = fs.get_fish_quality(fish_id)
	var tier = fs.get_fish_tier(fish_id)
	var cfg: Dictionary = fs._get_dev_cfg(fish_id)
	var max_tier = int(cfg.get("max_tier", 30))

	# 渔获信息
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", _quality_color(quality))
	info.text = "【%s】%s  %d/%d阶" % [quality, fs.get_fish_name(fish_id), tier, max_tier]
	vb.add_child(info)

	# 当前加成
	var bonus = Label.new()
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pct = fs.get_fish_percent_bonus(fish_id)
	var flat = fs.get_fish_flat_income(fish_id)
	var apt = fs.get_fish_skill_aptitude(fish_id)
	var parts = []
	if pct > 0.0: parts.append("赚速 +%d%%" % int(pct * 100))
	if flat > 0: parts.append("赚速 +%s" % c.format_number(flat))
	if apt > 0: parts.append("资质 +%d" % apt)
	bonus.text = "加成：" + ("、".join(parts) if not parts.is_empty() else "无")
	vb.add_child(bonus)

	# 操作行：晋升 / 卸下
	var op = HBoxContainer.new()
	op.alignment = BoxContainer.ALIGNMENT_CENTER
	op.add_theme_constant_override("separation", 16)
	vb.add_child(op)

	var promote_btn = Button.new()
	if tier >= max_tier:
		promote_btn.text = "已满阶"
		promote_btn.disabled = true
	else:
		var cost = fs.get_promote_cost(fish_id)
		promote_btn.text = "晋升（耗%d只同名）" % cost
		promote_btn.pressed.connect(_on_promote.bind(fish_id))
	promote_btn.custom_minimum_size = Vector2(200, 48)
	op.add_child(promote_btn)

	var unequip_btn = Button.new()
	unequip_btn.text = "卸下"
	unequip_btn.custom_minimum_size = Vector2(100, 48)
	unequip_btn.pressed.connect(_on_unequip)
	op.add_child(unequip_btn)

	# 技能列表
	var scroll = ScrollContainer.new()
	scroll.name = "EquipScroll"
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var head = Label.new()
	head.text = "—— 技能（喂鱼升级，加资质）——"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color("#ffd700"))
	list.add_child(head)

	for sk in fs.get_fish_skills(fish_id):
		list.add_child(_build_skill_row(fish_id, sk))

# 单个技能行：名称+解锁条件+等级+资质+经验+喂养按钮
func _build_skill_row(fish_id: String, sk: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if sk.unlocked:
		lbl.text = "%s Lv.%d/%d（资质+%d）\n经验 %d/%d" % [sk.name, int(sk.level), int(sk.max_level), int(sk.level) * int(sk.apt_per_level), int(sk.xp), int(sk.xp_need)]
	else:
		lbl.text = "%s（%d阶解锁）" % [sk.name, int(sk.unlock_tier)]
		lbl.add_theme_color_override("font_color", Color("#666666"))
	row.add_child(lbl)

	var btn = Button.new()
	btn.text = "喂养"
	btn.custom_minimum_size = Vector2(80, 44)
	btn.disabled = (not sk.unlocked) or int(sk.level) >= int(sk.max_level)
	btn.pressed.connect(_on_feed_btn.bind(fish_id, int(sk.index)))
	row.add_child(btn)
	return row

# ============ 喂养材料弹窗 ============
# 打开材料选择弹窗：鱼食/无品级鱼/满阶普通鱼/满阶传奇鱼
func _on_feed_btn(fish_id: String, skill_index: int):
	_close_popup("FishFeedPopup")
	var popup = c._create_base_popup("选择材料", Vector2(460, 420))
	popup.name = "FishFeedPopup"
	var vb = popup.get_child(0)

	var mats = [["yu_shi", "鱼食"], ["无", "无品级鱼"], ["普通", "普通鱼（满阶）"], ["传奇", "传奇鱼（满阶）"]]
	var fs = data.fishing_system
	var xp_cfg: Dictionary = fs._equip_cfgs().get("fodder_xp", {})
	for m in mats:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s（%d经验/个）拥有：%d" % [m[1], int(xp_cfg.get(m[0], 1)), fs.get_fodder_count(m[0])]
		row.add_child(lbl)
		var btn = Button.new()
		btn.text = "喂养"
		btn.custom_minimum_size = Vector2(80, 40)
		btn.disabled = fs.get_fodder_count(m[0]) <= 0
		btn.pressed.connect(_on_feed.bind(fish_id, skill_index, m[0]))
		row.add_child(btn)
		vb.add_child(row)

	var tip = Label.new()
	tip.text = "每次喂养自动消耗到升1级，材料不够则全喂攒经验"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color("#aaaaaa"))
	vb.add_child(tip)
	
	# 【新增】一键喂养按钮（关闭上方）：消耗所有材料直冲满级；满级或四种材料全空时禁用
	var feed_all_btn = Button.new()
	feed_all_btn.text = "一键喂养"
	feed_all_btn.custom_minimum_size = Vector2(100, 36)
	var dev = fs.get_fish_dev(fish_id)
	var cfg = fs._get_dev_cfg(fish_id)
	var max_lv = int(cfg.get("skill_max_level", 100))
	var has_mat = false
	for m in mats:
		if fs.get_fodder_count(m[0]) > 0:
			has_mat = true
			break
	feed_all_btn.disabled = int(dev.skills.get(str(skill_index), 0)) >= max_lv or not has_mat
	feed_all_btn.pressed.connect(_on_feed_all.bind(fish_id, skill_index))
	vb.add_child(feed_all_btn)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 喂养执行：关材料弹窗，原地刷新主弹窗与门客面板
func _on_feed(fish_id: String, skill_index: int, mat: String):
	var res: Dictionary = data.fishing_system.feed_skill(fish_id, skill_index, mat)
	_close_popup("FishFeedPopup")
	_refresh_equip_popup()
	c.hero_page.update_hero_panel()   # 资质变化，刷新门客面板对账
	if not res.get("ok", false):
		return

# 一键喂养执行：关材料弹窗，原地刷新主弹窗与门客面板，并提示升级结果与各材料消耗
func _on_feed_all(fish_id: String, skill_index: int):
	var res: Dictionary = data.fishing_system.feed_skill_max(fish_id, skill_index)
	_close_popup("FishFeedPopup")
	_refresh_equip_popup()
	c.hero_page.update_hero_panel()   # 资质变化，刷新门客面板对账
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "无法喂养"))
		return
	# 汇总提示：Lv.X→Lv.Y + 各材料消耗数量
	var names = {"yu_shi": "鱼食", "无": "无品级鱼", "普通": "普通鱼", "传奇": "传奇鱼"}
	var parts = []
	for mat in res.get("used", {}).keys():
		parts.append("%s×%d" % [names.get(mat, mat), int(res.used[mat])])
	c._show_stage_hint("一键喂养：Lv.%d→Lv.%d（消耗 %s）" % [int(res.from_level), int(res.to_level), "、".join(parts)])

# ============ 操作回调 ============
# 装备渔获
func _on_equip(fish_id: String):
	var res: Dictionary = data.fishing_system.equip_fish(_hero_id, fish_id)
	if not res.get("ok", false):
		return
	_refresh_equip_popup()
	c.hero_page.update_hero_panel()   # 面板赚速/资质对账

# 卸下渔获
func _on_unequip():
	data.fishing_system.unequip_fish(_hero_id)
	_refresh_equip_popup()
	c.hero_page.update_hero_panel()

# 晋升渔获
func _on_promote(fish_id: String):
	var res: Dictionary = data.fishing_system.promote_fish(fish_id)
	if not res.get("ok", false):
		return
	_refresh_equip_popup()
	c.hero_page.update_hero_panel()   # 晋升改变加成，刷新面板

# ============ 内部工具 ============
# 原地重填主弹窗
func _refresh_equip_popup():
	var popup = _find_popup("FishEquipPopup")
	if popup:
		_fill_equip_popup(popup)

# 在 game_controller 根节点下按名字找弹窗
func _find_popup(popup_name: String):
	if c.has_node(popup_name):
		return c.get_node(popup_name)
	return null

# 按名字关闭弹窗
func _close_popup(popup_name: String):
	var p = _find_popup(popup_name)
	if p: p.queue_free()

# 品质颜色（无双红/传奇橙/普通蓝/无白）
func _quality_color(q: String) -> Color:
	return Color({"无双": "#ff4d4d", "传奇": "#ffa500", "普通": "#4da6ff", "无": "#ffffff"}.get(q, "#ffffff"))
