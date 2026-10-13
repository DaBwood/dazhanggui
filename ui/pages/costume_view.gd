# ============================================================
# 服装视图（门客/挚友服装弹窗 + 兑换页-服装兑换子视图）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本；data = GameData 数据中枢）
# ============================================================
class_name CostumeView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 通用 ============
# 品质颜色：素装白 / 锦衣蓝 / 华服金
func _quality_color(quality: String) -> Color:
	match quality:
		"华服": return Color("#ffd700")
		"锦衣": return Color("#66aaff")
	return Color("#ffffff")

# 关闭指定名字的弹窗
func _close_popup(pname: String):
	if c.has_node(pname):
		c.get_node(pname).queue_free()

# ============================================================
# 门客服装弹窗（门客面板【服装】按钮）
# ============================================================
func show_hero_costume_popup(hero_id: String):
	_close_popup("HeroCostumePopup")
	var vs = c.get_viewport_rect().size
	var mask = ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.55)
	mask.z_index = 25
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(mask)
	var panel = PanelContainer.new()
	panel.name = "HeroCostumePopup"
	panel.set_meta("popup_mask", mask)
	panel.tree_exiting.connect(func(): mask.queue_free())
	panel.custom_minimum_size = Vector2(minf(560.0, vs.x - 24.0), vs.y - 60.0)
	panel.position = Vector2((vs.x - panel.custom_minimum_size.x) * 0.5, 30.0)
	panel.z_index = 30
	var p_sty := StyleBoxFlat.new()
	p_sty.bg_color = Color("#241d18")
	p_sty.set_corner_radius_all(10)
	p_sty.set_border_width_all(2)
	p_sty.border_color = Color("#8a6a45")
	panel.add_theme_stylebox_override("panel", p_sty)
	c.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	# ── 顶栏：< 返回 + 门客换装
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "<"
	back.custom_minimum_size = Vector2(44, 36)
	var b_sty := StyleBoxFlat.new()
	b_sty.bg_color = Color(0.25, 0.16, 0.09, 0.9)
	b_sty.set_corner_radius_all(6)
	b_sty.set_border_width_all(1)
	b_sty.border_color = Color(0.55, 0.4, 0.25)
	back.add_theme_stylebox_override("normal", b_sty)
	back.add_theme_stylebox_override("hover", b_sty)
	back.add_theme_stylebox_override("pressed", b_sty)
	back.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	back.pressed.connect(func(): _close_popup("HeroCostumePopup"))
	top.add_child(back)
	var title := Label.new()
	title.text = "门客换装"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	top.add_child(title)
	root.add_child(top)
	# ── 中部：左大预览 + 右服装卡列（木架格，可下滑）
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	root.add_child(mid)
	var pv_box := PanelContainer.new()
	pv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pv_sty := StyleBoxFlat.new()
	pv_sty.bg_color = Color(0.12, 0.09, 0.07)
	pv_sty.set_corner_radius_all(8)
	pv_sty.set_border_width_all(1)
	pv_sty.border_color = Color(0.45, 0.33, 0.2)
	pv_box.add_theme_stylebox_override("panel", pv_sty)
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv_box.add_child(preview)
	mid.add_child(pv_box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(158, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cards := VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 8)
	scroll.add_child(cards)
	mid.add_child(scroll)
	# ── 底栏：名字+效果 | 升级副钮 | 主操作钮
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	var eff_lbl := Label.new()
	eff_lbl.add_theme_font_size_override("font_size", 13)
	eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(name_lbl)
	info.add_child(eff_lbl)
	bottom.add_child(info)
	var up_btn := Button.new()
	up_btn.custom_minimum_size = Vector2(104, 40)
	bottom.add_child(up_btn)
	var act_btn := Button.new()
	act_btn.custom_minimum_size = Vector2(128, 40)
	bottom.add_child(act_btn)
	root.add_child(bottom)
	_build_cos_cards(cards, hero_id, preview, name_lbl, eff_lbl, act_btn, up_btn)

# 卡列构建：缩略图+品质竖签+已穿戴章；点卡选中（金边）→联动预览/效果/双钮
func _build_cos_cards(cards: VBoxContainer, hero_id: String, preview: TextureRect, name_lbl: Label, eff_lbl: Label, act_btn: Button, up_btn: Button):
	for ch in cards.get_children():
		ch.queue_free()
	var cfgs = data.costume_system.get_hero_costume_cfgs(hero_id)
	var worn: String = data.costume_system.get_worn_cos(hero_id)
	var sel := {"id": worn}
	var entries: Array = []
	for cfg in cfgs:
		var cos_id: String = cfg.get("id", "")
		var quality: String = cfg.get("quality", "素装")
		var is_unlocked: bool = data.costume_system.is_hero_cos_unlocked(hero_id, cos_id)
		# ── 木架格卡：VBox(缩略图横排+名字)+整卡点击层
		var card := Panel.new()
		card.custom_minimum_size = Vector2(146, 172)
		var c_sty := StyleBoxFlat.new()
		c_sty.bg_color = Color("#3a2c20")
		c_sty.set_corner_radius_all(6)
		c_sty.set_border_width_all(2)
		c_sty.border_color = Color("#8a6a45")
		card.add_theme_stylebox_override("panel", c_sty)
		var cvb := VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 2)
		card.add_child(cvb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		cvb.add_child(row)
		var th := TextureRect.new()
		th.custom_minimum_size = Vector2(112, 146)
		th.size_flags_vertical = Control.SIZE_EXPAND_FILL
		th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex_path: String = "res://assets/costumes/%s.png" % cos_id
		if ResourceLoader.exists(tex_path):
			th.texture = load(tex_path)
		if not is_unlocked:
			th.modulate = Color(0.45, 0.45, 0.45)
		row.add_child(th)
		# 右竖条：品质竖签（逐字竖排，红笔刷底）+ 已穿戴章
		var side := VBoxContainer.new()
		side.custom_minimum_size = Vector2(26, 0)
		side.size_flags_vertical = Control.SIZE_EXPAND_FILL
		side.add_theme_constant_override("separation", 2)
		row.add_child(side)
		var tag := Label.new()
		var qc := PackedStringArray()
		for ch in quality:
			qc.append(ch)
		tag.text = "\n".join(qc)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(1, 1, 1))
		var t_sty := StyleBoxTexture.new()
		if ResourceLoader.exists("res://assets/heroes/slot_label.png"):
			t_sty.texture = load("res://assets/heroes/slot_label.png")
			t_sty.set_content_margin_all(2)
			tag.add_theme_stylebox_override("normal", t_sty)
		side.add_child(tag)
		if cos_id == worn:
			var worn_lbl := Label.new()
			worn_lbl.text = "已穿戴"
			worn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			worn_lbl.add_theme_font_size_override("font_size", 10)
			worn_lbl.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
			side.add_child(worn_lbl)
		var nm := Label.new()
		nm.text = cfg.get("name", cos_id)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 12)
		nm.add_theme_color_override("font_color", Color(0.9, 0.86, 0.75))
		cvb.add_child(nm)
		var hit := Button.new()
		hit.flat = true
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_child(hit)
		entries.append({"card": card, "sty": c_sty, "id": cos_id, "cfg": cfg})
		hit.pressed.connect(_show_cos_detail.bind(hero_id, cos_id))
		cards.add_child(card)
	# 默认选中=穿戴中
	for e in entries:
		e.sty.border_color = Color("#e8c56a") if e.id == worn else Color("#8a6a45")
	for e in entries:
		if e.id == worn:
			_update_cos_detail(hero_id, e.cfg, preview, name_lbl, eff_lbl, act_btn, up_btn)
			break

# 【新增】全屏服装详情（参考图样式）：满幅服装图 + 左上品质标签 + 竖排名牌(上装名下角色名) + 右上返回 + 底部效果双钮
const COS_TAG_FILES := {"素装": "tag_suzhuang.png", "锦衣": "tag_jinyi.png", "华服": "tag_huafu.png"}

func _show_cos_detail(hero_id: String, cos_id: String):
	_close_popup("CosDetailPanel")
	var cfg: Dictionary = {}
	for c0 in data.costume_system.get_hero_costume_cfgs(hero_id):
		if c0["id"] == cos_id:
			cfg = c0
			break
	var mask = ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.4)
	mask.z_index = 35
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(mask)
	var panel := Panel.new()
	panel.name = "CosDetailPanel"
	panel.set_meta("popup_mask", mask)
	panel.tree_exiting.connect(func(): mask.queue_free())
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.z_index = 40
	c.add_child(panel)
	# ── 满幅服装图（COVERED 铺满全屏）
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex_path: String = "res://assets/costumes/%s.png" % cos_id
	if ResourceLoader.exists(tex_path):
		art.texture = load(tex_path)
	panel.add_child(art)
	if art.texture == null:
		var dbg := ColorRect.new()
		dbg.set_anchors_preset(Control.PRESET_FULL_RECT)
		dbg.color = Color(0.13, 0.1, 0.08)
		panel.add_child(dbg)
	# ── 左上：品质标签图（素装/锦衣/华服）
	var quality: String = cfg.get("quality", "")
	if COS_TAG_FILES.has(quality) and ResourceLoader.exists("res://assets/costumes/" + COS_TAG_FILES[quality]):
		var qtag := TextureRect.new()
		qtag.texture = load("res://assets/costumes/" + COS_TAG_FILES[quality])
		qtag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		qtag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		qtag.position = Vector2(14, 12)
		qtag.size = Vector2(118, 104)
		panel.add_child(qtag)
	# ── 名牌：竖排名牌底 + 上服装名/下角色名（逐字竖排）
	var plate := Panel.new()
	plate.position = Vector2(14, 124)
	plate.size = Vector2(118, 290)
	var pl_sty := StyleBoxTexture.new()
	if ResourceLoader.exists("res://assets/costumes/name_plate.png"):
		pl_sty.texture = load("res://assets/costumes/name_plate.png")
		pl_sty.set_content_margin_all(10)
	plate.add_theme_stylebox_override("panel", pl_sty)
	panel.add_child(plate)
	var plate_col := VBoxContainer.new()
	plate_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate_col.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(plate_col)
	var cos_name_lbl := Label.new()
	var nc := PackedStringArray()
	for ch in cfg.get("name", cos_id):
		nc.append(ch)
	cos_name_lbl.text = "\n".join(nc)
	cos_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cos_name_lbl.add_theme_font_size_override("font_size", 22)
	cos_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	plate_col.add_child(cos_name_lbl)
	var hero_name_lbl := Label.new()
	var hnm: String = data.heroes.get(hero_id, {}).get("name", hero_id)
	var hc2 := PackedStringArray()
	for ch in hnm:
		hc2.append(ch)
	hero_name_lbl.text = "\n".join(hc2)
	hero_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_name_lbl.add_theme_font_size_override("font_size", 13)
	hero_name_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	plate_col.add_child(hero_name_lbl)
	# ── 右上：返回（半透明）
	var back := Button.new()
	back.text = "<"
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.offset_left = -58.0
	back.offset_top = 12.0
	back.offset_right = -12.0
	back.offset_bottom = 52.0
	var bk_sty := StyleBoxFlat.new()
	bk_sty.bg_color = Color(0.15, 0.11, 0.08, 0.75)
	bk_sty.set_corner_radius_all(8)
	back.add_theme_stylebox_override("normal", bk_sty)
	back.add_theme_stylebox_override("hover", bk_sty)
	back.add_theme_stylebox_override("pressed", bk_sty)
	back.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	back.pressed.connect(func(): _close_popup("CosDetailPanel"))
	panel.add_child(back)
	# ── 底部条：效果 + 升级副钮 + 主钮（复用 _update_cos_detail 五态机）
	var bar := Panel.new()
	bar.anchor_left = 0.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -112.0
	var bar_sty := StyleBoxFlat.new()
	bar_sty.bg_color = Color(0.1, 0.08, 0.06, 0.85)
	bar_sty.content_margin_left = 10.0
	bar_sty.content_margin_right = 10.0
	bar_sty.content_margin_top = 8.0
	bar_sty.content_margin_bottom = 8.0
	bar.add_theme_stylebox_override("panel", bar_sty)
	panel.add_child(bar)
	var bar_h := HBoxContainer.new()
	bar_h.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_h.offset_left = 8.0
	bar_h.offset_top = 6.0
	bar_h.offset_right = -8.0
	bar_h.offset_bottom = -6.0
	bar_h.add_theme_constant_override("separation", 8)
	bar.add_child(bar_h)
	var eff_lbl := Label.new()
	eff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff_lbl.add_theme_font_size_override("font_size", 14)
	eff_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	bar_h.add_child(eff_lbl)
	var up_btn := Button.new()
	up_btn.custom_minimum_size = Vector2(104, 40)
	bar_h.add_child(up_btn)
	var act_btn := Button.new()
	act_btn.custom_minimum_size = Vector2(128, 40)
	bar_h.add_child(act_btn)
	var dummy := Label.new()
	_update_cos_detail(hero_id, cfg, art, dummy, eff_lbl, act_btn, up_btn)

# 选中联动：预览图/名字/效果/主钮（穿戴·已穿戴·解锁·兑换·未开放）/升级副钮
func _update_cos_detail(hero_id: String, cfg: Dictionary, preview: TextureRect, name_lbl: Label, eff_lbl: Label, act_btn: Button, up_btn: Button):
	var cos_id: String = cfg.get("id", "")
	var quality: String = cfg.get("quality", "素装")
	var series: String = cfg.get("series", "")
	var st: Dictionary = data.costume_system.get_hero_cos_state(hero_id, cos_id)
	var is_unlocked: bool = data.costume_system.is_hero_cos_unlocked(hero_id, cos_id)
	var stock: int = int(st.get("stock", 0))
	var worn: String = data.costume_system.get_worn_cos(hero_id)
	var tex_path: String = "res://assets/costumes/%s.png" % cos_id
	preview.texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
	name_lbl.text = "%s（%s）" % [cfg.get("name", cos_id), quality]
	if is_unlocked:
		var extra: int = int(st.get("extra", 0))
		var per: int = int(data.costume_system._settings().get("apt_per_level", {}).get(quality, 2))
		var dup_bonus: int = int(data.costume_system._settings().get("dup_bonus", 15))
		eff_lbl.text = "解锁%d级，提供资质+%d，升级服装+%d级" % [extra, extra * per, dup_bonus]
		name_lbl.add_theme_color_override("font_color", _quality_color(quality))
	elif stock > 0:
		eff_lbl.text = "待解锁（库存%d）" % stock
	elif series == "":
		eff_lbl.text = "暂未开放"
	else:
		var s: Dictionary = data.costume_system._get_series_cfg(series)
		var cost: int = int(data.costume_system._settings().get("exchange_cost", 100))
		var have: int = int(data.items.get(s.get("cost_item", ""), 0))
		eff_lbl.text = "%s %d/%d" % [s.get("item_name", ""), have, cost]
	# ── 主操作钮
	for conn in act_btn.pressed.get_connections():
		act_btn.pressed.disconnect(conn.callable)
	act_btn.disabled = false
	if cos_id == worn:
		act_btn.text = "已穿戴"
		act_btn.disabled = true
	elif is_unlocked:
		act_btn.text = "穿 戴"
		act_btn.pressed.connect(_on_cos_wear.bind(hero_id, cos_id, cfg.get("name", cos_id)))
	elif stock > 0:
		act_btn.text = "解锁（库存%d）" % stock
		act_btn.pressed.connect(_on_cos_unlock.bind(hero_id, cos_id))
	elif series != "":
		var s2: Dictionary = data.costume_system._get_series_cfg(series)
		var cost2: int = int(data.costume_system._settings().get("exchange_cost", 100))
		var have2: int = int(data.items.get(s2.get("cost_item", ""), 0))
		act_btn.text = "兑换 %d/%d" % [have2, cost2]
		act_btn.disabled = have2 < cost2
		act_btn.pressed.connect(_on_exchange_hero_cos.bind(hero_id, cos_id))
	else:
		act_btn.text = "暂未开放"
		act_btn.disabled = true
	# ── 升级副钮：已解锁且有库存才显示
	for conn2 in up_btn.pressed.get_connections():
		up_btn.pressed.disconnect(conn2.callable)
	if is_unlocked and stock > 0:
		up_btn.visible = true
		up_btn.text = "升级（库存%d）" % stock
		up_btn.pressed.connect(_on_cos_extra_upgrade.bind(hero_id, cos_id))
	else:
		up_btn.visible = false

# 【新增】穿戴回调：写 worn_cos → 刷新弹窗+详情面板+全局 UI
func _on_cos_wear(hero_id: String, cos_id: String, cos_name: String):
	if data.costume_system.wear_hero_cos(hero_id, cos_id):
		c._show_success_popup("已穿戴「%s」" % cos_name, 1.2, "ok")
		show_hero_costume_popup(hero_id)
		if c.has_node("CosDetailPanel"):
			_show_cos_detail(hero_id, cos_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()


# 填充门客服装列表：
#   已解锁=亮（显示总等级；有库存则显示"升级"按钮）
#   有库存未解锁=显示"解锁"按钮
#   无库存=灰（显示兑换按钮或暂未开放）
func _fill_hero_costume_list(list: VBoxContainer, hero_id: String):
	for child in list.get_children():
		child.queue_free()
	var cfs = data.costume_system.get_hero_costume_cfgs(hero_id)
	if cfs.is_empty():
		var lbl = Label.new()
		lbl.text = "该门客暂无服装"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)
		return
	for cfg in cfs:
		var cos_id = cfg.get("id", "")
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		var quality = cfg.get("quality", "素装")
		var series = cfg.get("series", "")
		var st = data.costume_system.get_hero_cos_state(hero_id, cos_id)
		var is_unlocked = data.costume_system.is_hero_cos_unlocked(hero_id, cos_id)
		var stock = int(st.get("stock", 0))
		
		if is_unlocked:
			# 【改】已解锁：只显示 extra——几级、提供多少资质、下次升级加几级（无上限）
			var extra = int(st.get("extra", 0))
			var per = int(data.costume_system._settings().get("apt_per_level", {}).get(quality, 2))
			var dup_bonus = int(data.costume_system._settings().get("dup_bonus", 15))
			lbl.text = "【%s】%s｜解锁%d级，提供资质+%d，升级服装+%d级" % [quality, cfg.get("name", cos_id), extra, extra * per, dup_bonus]
			lbl.add_theme_color_override("font_color", _quality_color(quality))
			row.add_child(lbl)
			# 已解锁且有库存：显示"升级"按钮（消耗1库存，加额外等级）
			if stock > 0:
				var up_btn = Button.new()
				up_btn.text = "升级（库存%d）" % stock
				up_btn.custom_minimum_size = Vector2(100, 32)
				up_btn.add_theme_font_size_override("font_size", 12)
				up_btn.pressed.connect(_on_cos_extra_upgrade.bind(hero_id, cos_id))
				row.add_child(up_btn)
		else:
			# 未解锁
			lbl.text = "【%s】%s" % [quality, cfg.get("name", cos_id)]
			row.add_child(lbl)
			if stock > 0:
				# 有库存但未解锁：显示"解锁"按钮
				var unlock_btn = Button.new()
				unlock_btn.text = "解锁（库存%d）" % stock
				unlock_btn.custom_minimum_size = Vector2(100, 32)
				unlock_btn.add_theme_font_size_override("font_size", 12)
				unlock_btn.pressed.connect(_on_cos_unlock.bind(hero_id, cos_id))
				row.add_child(unlock_btn)
				lbl.add_theme_color_override("font_color", Color("#aaaaaa"))   # 有库存但待解锁，淡灰
			else:
				# 无库存
				lbl.add_theme_color_override("font_color", Color("#777777"))   # 未拥有置灰
				if series == "":
					var lock_lbl = Label.new()
					lock_lbl.text = "暂未开放"
					lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					lock_lbl.add_theme_font_size_override("font_size", 12)
					lock_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
					row.add_child(lock_lbl)
				else:
					# 可兑换：显示价格（100个系列道具），不足禁用
					var s = data.costume_system._get_series_cfg(series)
					var cost = int(data.costume_system._settings().get("exchange_cost", 100))
					var have = int(data.items.get(s.get("cost_item", ""), 0))
					var buy_btn = Button.new()
					buy_btn.text = "%s %d/%d" % [s.get("item_name", ""), have, cost]
					buy_btn.custom_minimum_size = Vector2(130, 32)
					buy_btn.add_theme_font_size_override("font_size", 12)
					buy_btn.disabled = have < cost
					buy_btn.pressed.connect(_on_exchange_hero_cos.bind(hero_id, cos_id))
					row.add_child(buy_btn)
		list.add_child(row)

# 门客服装兑换回调：兑换后原地刷新列表 + 门客面板（资质/赚速变化）
func _on_exchange_hero_cos(hero_id: String, cos_id: String):
	var res = data.costume_system.exchange_hero_costume(hero_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		show_hero_costume_popup(hero_id)
		if c.has_node("CosDetailPanel"):
			_show_cos_detail(hero_id, cos_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# 【新增】手动解锁服装回调：消耗1库存，创建服装状态
func _on_cos_unlock(hero_id: String, cos_id: String):
	var res = data.costume_system.unlock_hero_cos(hero_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		show_hero_costume_popup(hero_id)
		if c.has_node("CosDetailPanel"):
			_show_cos_detail(hero_id, cos_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# 【新增】手动升级服装（消耗库存加额外等级）回调
func _on_cos_extra_upgrade(hero_id: String, cos_id: String):
	var res = data.costume_system.upgrade_hero_cos_extra(hero_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		show_hero_costume_popup(hero_id)
		if c.has_node("CosDetailPanel"):
			_show_cos_detail(hero_id, cos_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# ============================================================
# 挚友服装弹窗（挚友详情【服装】按钮）
# ============================================================
func show_friend_costume_popup(friend_id: String):
	_close_popup("FriendCostumePopup")
	var popup = c._create_base_popup("挚友服装", Vector2(640, 500))
	popup.name = "FriendCostumePopup"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 380)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	list.name = "CosList"
	scroll.add_child(list)
	_fill_friend_costume_list(list, friend_id)
	c.add_child(popup)

# 填充挚友服装列表：已兑换次数 + 下次兑换收益；挚友服装无技能无光环
func _fill_friend_costume_list(list: VBoxContainer, friend_id: String):
	for child in list.get_children():
		child.queue_free()
	var cfs = data.costume_system.get_friend_costume_cfgs(friend_id)
	if cfs.is_empty():
		var lbl = Label.new()
		lbl.text = "该挚友暂无服装"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)
		return
	var st = data.costume_system._settings()
	for cfg in cfs:
		var cos_id = cfg.get("id", "")
		var quality = cfg.get("quality", "素装")
		var series = cfg.get("series", "")
		var copies = data.costume_system.get_friend_cos_copies(friend_id, cos_id)
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		# 下次兑换的收益档位：首次 unlock 档，重复 dup 档
		var gain = st.get("friend_unlock" if copies == 0 else "friend_dup", {}).get(quality, [300, 300])
		lbl.text = "【%s】%s%s（下次：友好+%d 才华+%d）" % [quality, cfg.get("name", cos_id), " x%d" % copies if copies > 0 else "", int(gain[0]), int(gain[1])]
		lbl.add_theme_color_override("font_color", _quality_color(quality) if copies > 0 else Color("#777777"))
		row.add_child(lbl)
		if series == "":
			var lock_lbl = Label.new()
			lock_lbl.text = "暂未开放"
			lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lock_lbl.add_theme_font_size_override("font_size", 12)
			lock_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
			row.add_child(lock_lbl)
		else:
			var s = data.costume_system._get_series_cfg(series)
			var cost = int(st.get("exchange_cost", 100))
			var have = int(data.items.get(s.get("cost_item", ""), 0))
			var buy_btn = Button.new()
			buy_btn.text = "%s %d/%d" % [s.get("item_name", ""), have, cost]
			buy_btn.custom_minimum_size = Vector2(130, 32)
			buy_btn.add_theme_font_size_override("font_size", 12)
			buy_btn.disabled = have < cost
			buy_btn.pressed.connect(_on_exchange_friend_cos.bind(friend_id, cos_id))
			row.add_child(buy_btn)
		list.add_child(row)

# 挚友服装兑换回调：兑换后原地刷新列表 + 挚友详情（友好/才华变化）
func _on_exchange_friend_cos(friend_id: String, cos_id: String):
	var res = data.costume_system.exchange_friend_costume(friend_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		var popup = c.get_node_or_null("FriendCostumePopup")
		if popup:
			_fill_friend_costume_list(popup.find_child("CosList", true, false), friend_id)
		c.friend_page._update_friend_page_detail()
		c.update_all_ui()

# ============================================================
# 兑换页-服装兑换子视图（代码构建，挂在场景 ExchangeView 下）
# ============================================================
# 确保 CostumeExchangeView 存在（首次进入兑换页时构建）
func ensure_costume_exchange_view():
	var ev_path = "PageContainer/AdventurePage/ExchangeView"
	if not c.has_node(ev_path): return
	var ev = c.get_node(ev_path)
	if ev.has_node("CostumeExchangeView"): return
	var vw = c.get_viewport_rect().size
	# 全尺寸子视图：标题 + 滚动列表
	var view = VBoxContainer.new()
	view.name = "CostumeExchangeView"
	view.visible = false
	view.position = Vector2.ZERO
	view.size = vw
	view.add_theme_constant_override("separation", 8)
	ev.add_child(view)
	var title = Label.new()
	title.name = "CosExTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	view.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.name = "CosExScroll"
	scroll.custom_minimum_size = Vector2(vw.x - 40, vw.y - 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "CosExList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

# 显示服装兑换子视图（从兑换目录进入）
func show_costume_exchange_view():
	ensure_costume_exchange_view()
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	# 隐藏目录与其他子视图，只留服装兑换
	if ev.has_node("ExchangeEntryBox"): ev.get_node("ExchangeEntryBox").visible = false
	if ev.has_node("TokenExchangeView"): ev.get_node("TokenExchangeView").visible = false
	if ev.has_node("BeastExchangeView"): ev.get_node("BeastExchangeView").visible = false
	if ev.has_node("SeriesExchangeView"): ev.get_node("SeriesExchangeView").visible = false
	ev.get_node("CostumeExchangeView").visible = true
	update_costume_exchange_view()

# 隐藏服装兑换子视图（返回目录）
func hide_costume_exchange_view():
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("CostumeExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

# 刷新服装兑换列表：8个系列分区，每区5件服装卡片
func update_costume_exchange_view():
	var view = c.get_node_or_null("PageContainer/AdventurePage/ExchangeView/CostumeExchangeView")
	if view == null or not view.visible: return
	view.get_node("CosExTitle").text = "—— 服装兑换 ——"
	var list = view.get_node("CosExScroll/CosExList")
	for child in list.get_children():
		child.queue_free()
	for series in data.costume_system._cfgs().get("series", []):
		_add_series_section(list, series)

# 单系列分区：标题（含消耗道具）+ 5件服装行
func _add_series_section(list: VBoxContainer, series: Dictionary):
	var st = data.costume_system._settings()
	var cost = int(st.get("exchange_cost", 100))
	var item_id = series.get("cost_item", "")
	var have = int(data.items.get(item_id, 0))
	# 分区标题：系列名 + 消耗道具拥有/单价
	var title = Label.new()
	var unlocked_cnt = data.costume_system.count_series_unlocked(series.get("name", ""))
	title.text = "【%s】%d/%d 件  （%s：%d/%d）" % [series.get("name", ""), unlocked_cnt, series.get("members", []).size(), series.get("item_name", ""), have, cost]
	title.add_theme_color_override("font_color", Color("#ffd700"))
	list.add_child(title)
	# 服装行
	for m in series.get("members", []):
		var is_friend = series.get("owner_type", "hero") == "friend"
		var owner_id = m.get("owner", "")
		var cfg = data.costume_system._find_cos_cfg_by_name(owner_id, m.get("costume", ""), is_friend)
		if cfg.is_empty(): continue
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		# 拥有者名字（门客/挚友都可能未拥有，未拥有也可查看但不可兑换）
		var owner_name = ""
		var owner_owned = false
		if is_friend:
			owner_owned = data.friends.has(owner_id)
			owner_name = data.friends[owner_id].name if owner_owned else data.get_friend_config(owner_id).get("name", owner_id)
		else:
			owner_owned = data.heroes.has(owner_id)
			owner_name = data.heroes[owner_id].name if owner_owned else data.get_hero_config(owner_id).get("name", owner_id)
		var quality = cfg.get("quality", "素装")
		var state_txt = ""
		if is_friend:
			var copies = data.costume_system.get_friend_cos_copies(owner_id, cfg.get("id", ""))
			if copies > 0:
				state_txt = "（已兑换x%d）" % copies
			else:
				state_txt = "（未拥有挚友）"
		elif owner_owned:
			var cos_st = data.costume_system.get_hero_cos_state(owner_id, cfg.get("id", ""))
			var is_unlocked = data.costume_system.is_hero_cos_unlocked(owner_id, cfg.get("id", ""))
			var stock = int(cos_st.get("stock", 0))
			if is_unlocked:
				state_txt = "（已解锁"
				if stock > 0:
					state_txt += "，库存%d" % stock
				state_txt += "）"
			elif stock > 0:
				state_txt = "（未解锁，库存%d）" % stock
			else:
				state_txt = "（未拥有）"
		else:
			state_txt = "（未拥有门客）"
		lbl.text = "【%s】%s - %s%s" % [quality, cfg.get("name", ""), owner_name, state_txt]
		# 颜色判断：挚友已兑换 / 门客已解锁或有库存 → 品质色；否则白色
		var use_quality_color = false
		if is_friend:
			use_quality_color = data.costume_system.get_friend_cos_copies(owner_id, cfg.get("id", "")) > 0
		elif owner_owned:
			var cos_st2 = data.costume_system.get_hero_cos_state(owner_id, cfg.get("id", ""))
			use_quality_color = data.costume_system.is_hero_cos_unlocked(owner_id, cfg.get("id", "")) or int(cos_st2.get("stock", 0)) > 0
		lbl.add_theme_color_override("font_color", _quality_color(quality) if use_quality_color else Color("#ffffff"))
		row.add_child(lbl)
		var buy_btn = Button.new()
		buy_btn.text = "兑换"
		buy_btn.custom_minimum_size = Vector2(80, 32)
		buy_btn.add_theme_font_size_override("font_size", 12)
		buy_btn.disabled = (not owner_owned) or have < cost
		buy_btn.pressed.connect(_on_exchange_from_view.bind(owner_id, cfg.get("id", ""), is_friend))
		row.add_child(buy_btn)
		list.add_child(row)

# 兑换页里的兑换回调：兑换后原地刷新服装兑换列表
func _on_exchange_from_view(owner_id: String, cos_id: String, is_friend: bool):
	var res = data.costume_system.exchange_friend_costume(owner_id, cos_id) if is_friend else data.costume_system.exchange_hero_costume(owner_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		update_costume_exchange_view()
		c.update_all_ui()
