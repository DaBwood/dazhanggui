# ============================================================
# 魂力培养全屏页（2026-08-31 新增：珍兽魂体 + 魂骨装配/养成/回收）
# 纯代码 UI 模块：var c（game_controller 根脚本）、var data（GameData 中枢）
# 层级约定与兽魂页一致：HunliPage z35（盖珍兽详情z20），页内弹窗 z40，飘字 z50
# 交互：点锁定槽=免费解锁（二次确认，不可回锁）；点空槽=选骨装配；
#       点已装魂骨/仓库魂骨=详情弹窗（升阶/技能升级/装备/卸下/回收）
# ============================================================
class_name SoulpowerView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

const SLOT_COLS = 3      # 槽位区每行数（6槽=3列×2行）
const SLOT_BTN = Vector2(180, 96)   # 槽位按钮尺寸
const BONE_COLS = 5      # 仓库每行魂骨按钮数
const BONE_BTN = 104     # 仓库魂骨按钮边长

var _beast_id: String = ""      # 当前操作珍兽ID（页面打开期间）
var _beast_index: int = 0       # 当前操作珍兽实例序号

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 全屏页 ============
# 打开魂力培养全屏页（由珍兽详情页【魂力】按钮触发）
func show_hunli_view(beast_id: String, instance_index: int = 0):
	if data.get_beast_instance(beast_id, instance_index) == null: return
	_beast_id = beast_id
	_beast_index = instance_index
	# 已存在则先关，保证内容重建
	_close_node("HunliPage")
	_close_node("HunliBonePopup")
	_close_node("HunliPickPopup")
	_close_node("HunliConfirmPopup")
	_close_node("HunliResonancePopup")

	# 根面板：禁用锚点预设（项目坑#3），显式 position+size 铺满窗口；不透明底色直盖下层
	var page = Panel.new()
	page.name = "HunliPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	page.add_theme_stylebox_override("panel", bg)

	# 内容根容器：同样显式尺寸（Panel 不做子节点布局）
	var vb = VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 10)
	page.add_child(vb)

	# 顶栏：返回 + 标题 + 右侧占位
	var top = HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 56)
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var back_btn = Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(120, 44)
	back_btn.pressed.connect(_on_back)
	top.add_child(back_btn)
	var cfg = data.get_beast_config(beast_id)
	var title = Label.new()
	title.text = "魂力培养 · %s" % cfg.get("name", beast_id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var pad = Control.new()   # 右侧占位，让标题视觉居中
	pad.custom_minimum_size = Vector2(120, 44)
	top.add_child(pad)

	# 动态内容区（信息行/槽位/仓库）都在这，操作后原地重填
	var body = VBoxContainer.new()
	body.name = "HunliBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	vb.add_child(body)

	c.add_child(page)
	_fill_body(body)

# 返回：关掉本页（连带关掉它上面的弹窗），下层页面自然露出
func _on_back():
	_close_node("HunliBonePopup")
	_close_node("HunliPickPopup")
	_close_node("HunliConfirmPopup")
	_close_node("HunliResonancePopup")
	_close_node("HunliPage")

# 重填动态内容区（保留仓库滚动位置）
func _fill_body(body):
	var scroll = body.get_node_or_null("BoneScroll")
	var sv = scroll.scroll_vertical if scroll else 0
	for child in body.get_children():
		child.queue_free()

	var sp = data.soulpower_system
	var body_data = sp._get_body(_beast_id, _beast_index)
	var lv = int(body_data.get("level", 1))
	var max_lv = int(sp._settings().get("body_max_level", 200))
	var lv_cost = int(sp._settings().get("body_level_cost", 60))
	var apt_per_lv = int(sp._settings().get("body_apt_per_level", 6))
	var bonus = sp.get_body_bonus(_beast_id, _beast_index)

	# 魂体行：等级/资质 + 升级/十连按钮
	var body_row = HBoxContainer.new()
	body_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body_row.add_theme_constant_override("separation", 12)
	body.add_child(body_row)
	var body_lbl = Label.new()
	body_lbl.add_theme_font_size_override("font_size", 15)
	body_lbl.text = "魂体 Lv.%d/%d（资质+%d）  龙芝草×%d" % [lv, max_lv, lv * apt_per_lv, int(data.items.get("long_zhi_cao", 0))]
	body_row.add_child(body_lbl)
	var up_btn = Button.new()
	up_btn.text = "升级(%d)" % lv_cost
	up_btn.custom_minimum_size = Vector2(110, 36)
	up_btn.disabled = lv >= max_lv or int(data.items.get("long_zhi_cao", 0)) < lv_cost
	up_btn.pressed.connect(_on_upgrade_body.bind(1))
	body_row.add_child(up_btn)
	var up10_btn = Button.new()
	up10_btn.text = "十连"
	up10_btn.custom_minimum_size = Vector2(80, 36)
	up10_btn.disabled = lv >= max_lv or int(data.items.get("long_zhi_cao", 0)) < lv_cost
	up10_btn.pressed.connect(_on_upgrade_body.bind(10))
	body_row.add_child(up10_btn)

	# 共鸣行：已装数/基础资质/印记倍率 + 详情按钮
	var rz = sp.get_resonance(_beast_id, _beast_index)
	var rz_row = HBoxContainer.new()
	rz_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rz_row.add_theme_constant_override("separation", 12)
	body.add_child(rz_row)
	var rz_lbl = Label.new()
	rz_lbl.add_theme_font_size_override("font_size", 15)
	rz_lbl.text = "魂骨共鸣：已装%d/6 → 资质+%d（基础%d×倍率%.1f，印记%d枚）" % [int(rz.filled), int(rz.apt), int(rz.base), float(rz.mult), int(rz.marks)]
	rz_row.add_child(rz_lbl)
	var rz_btn = Button.new()
	rz_btn.text = "共鸣详情"
	rz_btn.custom_minimum_size = Vector2(110, 36)
	rz_btn.pressed.connect(_show_resonance_popup)
	rz_row.add_child(rz_btn)

	# 装备门客行：本魂体全部加成只作用于装备门客
	var hero_lbl = Label.new()
	hero_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_lbl.add_theme_font_size_override("font_size", 15)
	var inst = data.get_beast_instance(_beast_id, _beast_index)
	var hero_id: String = inst.get("equipped_hero", "")
	if hero_id != "" and data.heroes.has(hero_id):
		hero_lbl.text = "装备门客：%s　总加成：资质+%d 赚速+%s 赚钱+%d%%" % [
			data.heroes[hero_id].get("name", hero_id), int(bonus.apt),
			c.format_number(int(bonus.income)), int(bonus.percent * 100)]
	else:
		hero_lbl.text = "未装备门客（魂力加成不生效）　总加成：资质+%d 赚速+%s 赚钱+%d%%" % [
			int(bonus.apt), c.format_number(int(bonus.income)), int(bonus.percent * 100)]
		hero_lbl.add_theme_color_override("font_color", Color("#888888"))
	body.add_child(hero_lbl)

	# 槽位区：3列×2行，居中
	var grid_wrap = HBoxContainer.new()
	grid_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(grid_wrap)
	var grid = GridContainer.new()
	grid.columns = SLOT_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid_wrap.add_child(grid)
	for slot in sp.get_slots():
		grid.add_child(_make_slot_btn(slot, body_data))

	# 操作提示
	var hint = Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#aaaaaa"))
	hint.text = "点锁定槽=免费解锁（不可回锁）；点空槽=装配魂骨；点魂骨=养成详情"
	body.add_child(hint)

	# 魂骨仓库
	var inv_title = Label.new()
	inv_title.text = "—— 魂骨仓库（背包使用【魂骨盒子】获得魂骨）——"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_font_size_override("font_size", 15)
	inv_title.add_theme_color_override("font_color", Color("#ffd700"))
	body.add_child(inv_title)
	var scroll2 = ScrollContainer.new()
	scroll2.name = "BoneScroll"
	scroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll2)
	# HBox 撑满宽度只为把网格整体居中
	var center_row = HBoxContainer.new()
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll2.add_child(center_row)
	var list = GridContainer.new()
	list.columns = BONE_COLS
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 8)
	center_row.add_child(list)
	_build_bone_list(list)

	# 恢复仓库滚动位置
	var new_scroll = body.get_node_or_null("BoneScroll")
	if new_scroll: new_scroll.set_deferred("scroll_vertical", sv)

# ============ 槽位 ============
# 构建槽位按钮：锁定（灰）/ 空（暗）/ 已装魂骨（品质色边框+概要）
func _make_slot_btn(slot: String, body_data: Dictionary) -> Button:
	var sp = data.soulpower_system
	var btn = Button.new()
	btn.custom_minimum_size = SLOT_BTN
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	var unlocked: Array = body_data.get("unlocked", [])
	var uid: String = body_data.get("bones", {}).get(slot, "")
	if not unlocked.has(slot):
		sb.bg_color = Color("#16131f")
		sb.border_color = Color("#333333")
		btn.text = "%s\n锁·点击解锁" % sp.get_slot_name(slot)
		btn.add_theme_color_override("font_color", Color("#777777"))
	elif uid == "":
		sb.bg_color = Color("#242038")
		sb.border_color = Color("#4a4460")
		btn.text = "%s\n（空·点击装配）" % sp.get_slot_name(slot)
		btn.add_theme_color_override("font_color", Color("#aaaaaa"))
	else:
		var bone: Dictionary = data.soul_bones.get(uid, {})
		var q: String = bone.get("quality", "")
		sb.bg_color = Color("#242038")
		sb.border_color = _quality_color(q)
		btn.text = "%s·%s\n%d阶" % [q, sp.get_slot_name(slot), int(bone.get("tier", 1))]
		btn.add_theme_color_override("font_color", _quality_color(q))
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(_on_slot_tapped.bind(slot))
	return btn

# 点槽位：锁定→解锁确认；空→选骨装配；已装→魂骨详情
func _on_slot_tapped(slot: String):
	var sp = data.soulpower_system
	var body_data = sp._get_body(_beast_id, _beast_index)
	if not body_data.get("unlocked", []).has(slot):
		_show_unlock_confirm(slot)
		return
	var uid: String = body_data.get("bones", {}).get(slot, "")
	if uid != "":
		_show_bone_popup(uid)
	else:
		_show_pick_popup(slot)

# 解锁二次确认（免费无损，但不可回锁）
func _show_unlock_confirm(slot: String):
	_close_node("HunliConfirmPopup")
	var popup = c._create_base_popup("解锁槽位", Vector2(420, 240))
	popup.name = "HunliConfirmPopup"
	popup.z_index = 40   # 压过 HunliPage(35)
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "免费解锁【%s】槽位\n解锁后无法重新锁上\n（填满槽位有共鸣加成，全解开会让填满变难）" % data.soulpower_system.get_slot_name(slot)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	var ok = Button.new()
	ok.text = "确定解锁"
	ok.custom_minimum_size = Vector2(120, 40)
	ok.pressed.connect(_on_unlock_confirmed.bind(slot))
	row.add_child(ok)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(func(): _close_node("HunliConfirmPopup"))
	row.add_child(cancel)
	c.add_child(popup)

# 确认解锁：免费，直接解锁并刷新
func _on_unlock_confirmed(slot: String):
	data.soulpower_system.unlock_slot(_beast_id, _beast_index, slot)
	_close_node("HunliConfirmPopup")
	_refresh_body()

# 空槽选骨：列出仓库中该部位的魂骨，点击即装备
func _show_pick_popup(slot: String):
	_close_node("HunliPickPopup")
	var sp = data.soulpower_system
	var popup = c._create_base_popup("装配%s" % sp.get_slot_name(slot), Vector2(460, 480))
	popup.name = "HunliPickPopup"
	popup.z_index = 40   # 压过 HunliPage(35)
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 320)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var any = false
	for uid in data.soul_bones.keys():
		var bone: Dictionary = data.soul_bones[uid]
		if bone.get("slot", "") != slot: continue
		if sp.is_equipped(uid): continue   # 已装在其他魂体上的不列
		any = true
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 【修】手机端：按钮默认 STOP 拦截触摸滚动，改 PASS 让滑动穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.text = "【%s】%d阶" % [bone.get("quality", ""), int(bone.get("tier", 1))]
		btn.add_theme_color_override("font_color", _quality_color(bone.get("quality", "")))
		btn.pressed.connect(_on_equip.bind(uid))
		list.add_child(btn)
	if not any:
		var empty = Label.new()
		empty.text = "仓库没有该部位魂骨\n（背包使用【魂骨盒子】自选部位+品级获得）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("#888888"))
		list.add_child(empty)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# ============ 魂骨详情弹窗 ============
# 点魂骨（槽上或仓库）：品级/阶/升阶 + 技能列表/升级 + 装备/卸下/回收；操作后重建本弹窗
func _show_bone_popup(uid: String):
	_close_node("HunliBonePopup")
	var bone = data.soul_bones.get(uid, {})
	if bone.is_empty(): return
	var sp = data.soulpower_system
	var q: String = bone.get("quality", "")
	var slot: String = bone.get("slot", "")
	var tier = int(bone.get("tier", 1))
	var max_tier = int(sp._settings().get("bone_max_tier", 20))
	var qcfg = data._soulpower_configs.get("qualities", {}).get(q, {})

	var popup = c._create_base_popup("%s·%s" % [q, sp.get_slot_name(slot)], Vector2(470, 640))
	popup.name = "HunliBonePopup"
	popup.z_index = 40   # 压过 HunliPage(35)
	var vb = popup.get_child(0)

	# 阶行：当前阶/资质/升阶按钮（百万年附赚钱%）
	var tier_row = HBoxContainer.new()
	tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tier_row.add_theme_constant_override("separation", 12)
	vb.add_child(tier_row)
	var tier_lbl = Label.new()
	tier_lbl.add_theme_font_size_override("font_size", 15)
	var tier_txt = "%d/%d阶  资质+%d" % [tier, max_tier, tier * int(qcfg.get("apt_per_tier", 0))]
	var pct = float(qcfg.get("income_pct_per_tier", 0.0))
	if pct > 0.0:
		tier_txt += "  赚钱+%d%%" % int(tier * pct * 100)
	tier_lbl.text = tier_txt
	tier_row.add_child(tier_lbl)
	var tier_btn = Button.new()
	tier_btn.custom_minimum_size = Vector2(150, 36)
	var cost_info = sp.get_tier_upgrade_cost(uid)
	if cost_info.is_empty():
		tier_btn.text = "已满阶"
		tier_btn.disabled = true
	else:
		var core_item: String = cost_info.get("item", "")
		var core_name = data.ITEM_CONFIG.get(core_item, {}).get("name", core_item)
		var core_cost = int(cost_info.get("cost", 1))
		tier_btn.text = "升阶(%s%d/%d)" % [core_name, int(data.items.get(core_item, 0)), core_cost]
		tier_btn.disabled = int(data.items.get(core_item, 0)) < core_cost
		tier_btn.pressed.connect(_on_upgrade_tier.bind(uid))
	tier_row.add_child(tier_btn)

	# 技能列表：每技能一行（名称/星数/等级/效果/升级按钮）
	var max_skill = int(sp._settings().get("skill_max_level", 50))
	var star_names = ["", "一星", "二星", "三星", "四星", "五星"]
	for entry in qcfg.get("skills", []):
		var sid: String = entry.get("id", "")
		var scfg = data._soulpower_configs.get("skills", {}).get(sid, {})
		var star = int(entry.get("star", 1))
		var slv = int(bone.get("skills", {}).get(sid, 0))
		var per_lv = sp.get_skill_per_level_value(q, sid)
		var is_income = scfg.get("type", "") == "income"
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var eff_txt = ("每级赚速+%s" % c.format_number(int(per_lv))) if is_income else ("每级资质+%d" % int(per_lv))
		var cur_txt = ("（当前+%s）" % c.format_number(int(per_lv * slv))) if is_income else ("（当前+%d）" % int(per_lv * slv))
		lbl.text = "%s%s Lv.%d/%d\n%s%s" % [star_names[clampi(star, 1, 5)], scfg.get("name", sid), slv, max_skill, eff_txt, cur_txt if slv > 0 else ""]
		row.add_child(lbl)
		var up = Button.new()
		up.custom_minimum_size = Vector2(130, 44)
		var cost = sp.get_skill_upgrade_cost(uid, sid)
		if cost <= 0:
			up.text = "已满级"
			up.disabled = true
		else:
			up.text = "升级(尘%d/%d)" % [int(data.items.get("cui_gu_jing_chen", 0)), cost]
			up.disabled = int(data.items.get("cui_gu_jing_chen", 0)) < cost
			up.pressed.connect(_on_upgrade_skill.bind(uid, sid))
		row.add_child(up)

	# 操作行：装备/卸下 + 回收 + 关闭
	var op = HBoxContainer.new()
	op.alignment = BoxContainer.ALIGNMENT_CENTER
	op.add_theme_constant_override("separation", 16)
	vb.add_child(op)
	var equipped_here: String = sp._get_body(_beast_id, _beast_index).get("bones", {}).get(slot, "")
	if equipped_here == uid:
		var un_btn = Button.new()
		un_btn.text = "卸下"
		un_btn.custom_minimum_size = Vector2(110, 40)
		un_btn.pressed.connect(_on_unequip.bind(slot))
		op.add_child(un_btn)
	elif not sp.is_equipped(uid):
		var eq_btn = Button.new()
		eq_btn.text = "装备到本兽"
		eq_btn.custom_minimum_size = Vector2(130, 40)
		var slot_unlocked = sp._get_body(_beast_id, _beast_index).get("unlocked", []).has(slot)
		eq_btn.disabled = not slot_unlocked
		if not slot_unlocked:
			eq_btn.text = "槽位未解锁"
		eq_btn.pressed.connect(_on_equip.bind(uid))
		op.add_child(eq_btn)
		var re_btn = Button.new()
		re_btn.text = "回收"
		re_btn.custom_minimum_size = Vector2(110, 40)
		re_btn.pressed.connect(_show_recycle_confirm.bind(uid))
		op.add_child(re_btn)
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(110, 40)
	close_btn.pressed.connect(func(): _close_node("HunliBonePopup"))
	op.add_child(close_btn)
	c.add_child(popup)

# ============ 操作回调 ============
# 魂体升级（times=1单升/10十连；材料不足逐次停，提示实际升级数）
func _on_upgrade_body(times: int):
	var res: Dictionary = data.soulpower_system.upgrade_body(_beast_id, _beast_index, times)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "无法升级"))
	elif int(res.get("up", 0)) < times:
		c._show_stage_hint("材料不足，升了%d级" % int(res.get("up", 0)))
	_refresh_body()
	c.update_all_ui()   # 资质变化，顶栏赚速对账

# 魂骨升阶：成功后重建详情弹窗+刷新主页
func _on_upgrade_tier(uid: String):
	var res: Dictionary = data.soulpower_system.upgrade_bone_tier(uid)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "无法升阶"))
	_show_bone_popup(uid)
	_refresh_body()
	c.update_all_ui()

# 技能升级：成功后重建详情弹窗+刷新主页
func _on_upgrade_skill(uid: String, skill_id: String):
	var res: Dictionary = data.soulpower_system.upgrade_bone_skill(uid, skill_id)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "无法升级"))
	_show_bone_popup(uid)
	_refresh_body()
	c.update_all_ui()

# 装备魂骨（该槽已有魂骨时系统自动无损换下）
func _on_equip(uid: String):
	var res: Dictionary = data.soulpower_system.equip_bone(_beast_id, _beast_index, uid)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "无法装备"))
	else:
		_close_node("HunliPickPopup")
		_close_node("HunliBonePopup")
	_refresh_body()
	c.update_all_ui()

# 卸下魂骨（无损回仓库）
func _on_unequip(slot: String):
	data.soulpower_system.unequip_bone(_beast_id, _beast_index, slot)
	_close_node("HunliBonePopup")
	_refresh_body()
	c.update_all_ui()

# 回收二次确认：列出返还物
func _show_recycle_confirm(uid: String):
	_close_node("HunliConfirmPopup")
	var bone = data.soul_bones.get(uid, {})
	if bone.is_empty(): return
	var qcfg = data._soulpower_configs.get("qualities", {}).get(bone.get("quality", ""), {})
	var core: String = qcfg.get("core_item", "")
	var core_name = data.ITEM_CONFIG.get(core, {}).get("name", core)
	var popup = c._create_base_popup("回收魂骨", Vector2(420, 240))
	popup.name = "HunliConfirmPopup"
	popup.z_index = 45   # 压过 HunliBonePopup(40)
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "回收【%s·%s】（%d阶）\n返还：%s×1 + 淬骨精尘×%d\n（升阶/技能投入不返还）" % [
		bone.get("quality", ""), data.soulpower_system.get_slot_name(bone.get("slot", "")),
		int(bone.get("tier", 1)), core_name, int(qcfg.get("recycle_dust", 0))]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	var ok = Button.new()
	ok.text = "确定回收"
	ok.custom_minimum_size = Vector2(120, 40)
	ok.pressed.connect(_on_recycle_confirmed.bind(uid))
	row.add_child(ok)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(func(): _close_node("HunliConfirmPopup"))
	row.add_child(cancel)
	c.add_child(popup)

# 确认回收：执行并关掉详情弹窗，刷新主页+背包对账
func _on_recycle_confirmed(uid: String):
	var res: Dictionary = data.soulpower_system.recycle_bone(uid)
	_close_node("HunliConfirmPopup")
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "无法回收"))
		return
	_close_node("HunliBonePopup")
	c._show_stage_hint("已回收，返还晶核×1 + 淬骨精尘×%d" % int(res.get("dust", 0)))
	_refresh_body()
	c.update_bag_list()
	c.update_all_ui()

# ============ 共鸣详情弹窗 ============
# 当前状态 + 基础资质表 + 印记规则说明
func _show_resonance_popup():
	_close_node("HunliResonancePopup")
	var sp = data.soulpower_system
	var rz = sp.get_resonance(_beast_id, _beast_index)
	var popup = c._create_base_popup("魂骨共鸣", Vector2(440, 520))
	popup.name = "HunliResonancePopup"
	popup.z_index = 40   # 压过 HunliPage(35)
	var vb = popup.get_child(0)

	var state = Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 16)
	state.text = "已装%d/6 → 资质+%d" % [int(rz.filled), int(rz.apt)]
	state.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(state)

	var detail = Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.text = "基础资质%d × 印记倍率%.1f（印记%d枚）" % [int(rz.base), float(rz.mult), int(rz.marks)]
	vb.add_child(detail)

	var t1 = Label.new()
	t1.text = "—— 填满槽数 → 基础资质 ——"
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_font_size_override("font_size", 14)
	t1.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(t1)
	var base_cfg: Dictionary = sp._settings().get("resonance_base", {})
	for i in range(1, 7):
		var l = Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cur = "  ◀ 当前" if i == int(rz.filled) else ""
		l.text = "%d槽：%d%s" % [i, int(base_cfg.get(str(i), 0)), cur]
		if i == int(rz.filled):
			l.add_theme_color_override("font_color", Color("#ffd700"))
		vb.add_child(l)

	var t2 = Label.new()
	t2.text = "—— 印记规则 ——"
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.add_theme_font_size_override("font_size", 14)
	t2.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(t2)
	var rule = Label.new()
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule.add_theme_font_size_override("font_size", 13)
	rule.add_theme_color_override("font_color", Color("#aaaaaa"))
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.text = "装备魂骨按品级给印记：百年1 / 千年4 / 万年5 / 十万年6 / 百万年7\n印记≥4枚起，每多1枚倍率+0.1（4枚×1.0 … 42枚×4.8）\n不足4枚不惩罚，按×1.0计"
	vb.add_child(rule)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# ============ 魂骨仓库 ============
# 方形按钮网格：一格一块（品质色边框），点按=详情弹窗；已装备的不进列表
func _build_bone_list(grid: GridContainer):
	var sp = data.soulpower_system
	var any = false
	for uid in data.soul_bones.keys():
		if sp.is_equipped(uid): continue
		var bone: Dictionary = data.soul_bones[uid]
		any = true
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(BONE_BTN, BONE_BTN)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color("#242038")
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.border_color = _quality_color(bone.get("quality", ""))
		btn.add_theme_stylebox_override("normal", sb)
		btn.text = "%s\n%s\n%d阶" % [bone.get("quality", ""), sp.get_slot_name(bone.get("slot", "")), int(bone.get("tier", 1))]
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", _quality_color(bone.get("quality", "")))
		btn.pressed.connect(_show_bone_popup.bind(uid))
		grid.add_child(btn)
	if not any:
		var empty = Label.new()
		empty.text = "仓库空空如也\n（背包使用【魂骨盒子】自选部位+品级获得魂骨）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("#888888"))
		grid.add_child(empty)

# ============ 内部工具 ============
# 原地重填动态内容区
func _refresh_body():
	var page = _find_node("HunliPage")
	if page == null: return
	var body = page.find_child("HunliBody", true, false)   # 递归查找（HunliBody 是内层 VBox 子节点）
	if body:
		_fill_body(body)

# 在 game_controller 根节点下按名字找节点
func _find_node(node_name: String):
	if c.has_node(node_name):
		return c.get_node(node_name)
	return null

# 按名字关闭节点
func _close_node(node_name: String):
	var p = _find_node(node_name)
	if p: p.queue_free()

# 魂骨品质颜色（读 soulpower.json 的 qualities 段 color，兜底白）
func _quality_color(q: String) -> Color:
	return Color(data._soulpower_configs.get("qualities", {}).get(q, {}).get("color", "#ffffff"))
