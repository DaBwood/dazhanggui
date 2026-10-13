# ============================================================
# 服装视图（门客/挚友服装弹窗 + 兑换页-服装兑换子视图）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本；data = GameData 数据中枢）
# ============================================================
class_name CostumeView
extends RefCounted

# 名牌/词条统一暗金（品质色亮金刺眼，用户拍板收敛）
const COS_NAME_GOLD := Color(0.72, 0.58, 0.3)

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
const COS_TAG_FILES := {"素装": "tag_suzhuang.png", "锦衣": "tag_jinyi.png", "华服": "tag_huafu.png"}

func show_hero_costume_popup(hero_id: String):
	_close_popup("HeroCostumePopup")
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
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.z_index = 30
	var p_sty := StyleBoxFlat.new()
	p_sty.bg_color = Color("#241d18")
	p_sty.content_margin_left = 12.0
	p_sty.content_margin_right = 12.0
	p_sty.content_margin_top = 10.0
	p_sty.content_margin_bottom = 10.0
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
	# ── 中部：左预览(图上压品质标+名牌) + 右 slim 卡列
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	root.add_child(mid)
	var pv_box := Panel.new()
	pv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pv_sty := StyleBoxFlat.new()
	pv_sty.bg_color = Color(0.12, 0.09, 0.07)
	pv_sty.set_corner_radius_all(8)
	pv_sty.set_border_width_all(1)
	pv_sty.border_color = Color(0.45, 0.33, 0.2)
	pv_box.add_theme_stylebox_override("panel", pv_sty)
	var preview := TextureRect.new()
	preview.name = "CosPreview"
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv_box.add_child(preview)
	# 左上：品质标签图 + 竖排名牌（上装名下角色名）
	var meta := Control.new()
	meta.position = Vector2(10, 8)
	pv_box.add_child(meta)
	var qtag := TextureRect.new()
	qtag.name = "CosQTag"
	qtag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qtag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qtag.position = Vector2.ZERO
	qtag.size = Vector2(118, 104)
	meta.add_child(qtag)
	var plate := Panel.new()
	plate.position = Vector2(30, 128)
	plate.size = Vector2(84, 236)
	var pl_sty := StyleBoxTexture.new()
	if ResourceLoader.exists("res://assets/costumes/name_plate.png"):
		pl_sty.texture = load("res://assets/costumes/name_plate.png")
		pl_sty.set_content_margin_all(6)
	plate.add_theme_stylebox_override("panel", pl_sty)
	meta.add_child(plate)
	var plate_col := VBoxContainer.new()
	plate_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate_col.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(plate_col)
	var name_lbl := Label.new()
	name_lbl.name = "CosName"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	plate_col.add_child(name_lbl)
	var hero_name_lbl := Label.new()
	var _hc := PackedStringArray()
	for _ch in data.heroes.get(hero_id, {}).get("name", hero_id):
		_hc.append(_ch)
	hero_name_lbl.text = "\n".join(_hc)
	hero_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_name_lbl.add_theme_font_size_override("font_size", 10)
	hero_name_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	plate_col.add_child(hero_name_lbl)
	mid.add_child(pv_box)
	# 右：slim 卡列（仅缩略图+已穿戴章，可下滑）
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(120, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cards := VBoxContainer.new()
	cards.name = "CosCards"
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 6)
	scroll.add_child(cards)
	mid.add_child(scroll)
	# ── 底部升级区域：标题 + 加成内容行 + 消耗/双钮（结构照参考图：深色木纹卡）
	var bottom := PanelContainer.new()
	var bt_sty := StyleBoxFlat.new()
	bt_sty.bg_color = Color(0.18, 0.13, 0.09)
	bt_sty.set_corner_radius_all(8)
	bt_sty.set_border_width_all(1)
	bt_sty.border_color = Color(0.45, 0.33, 0.2)
	bt_sty.content_margin_left = 12.0
	bt_sty.content_margin_right = 12.0
	bt_sty.content_margin_top = 8.0
	bt_sty.content_margin_bottom = 8.0
	bottom.add_theme_stylebox_override("panel", bt_sty)
	root.add_child(bottom)
	var up_vbox := VBoxContainer.new()
	up_vbox.add_theme_constant_override("separation", 6)
	bottom.add_child(up_vbox)
	# 标题行：左上职业光环钮（弹阶梯说明）+ 居中标题 + 右同宽占位对称
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	up_vbox.add_child(title_row)
	var halo_btn := Button.new()
	halo_btn.name = "CosHalo"
	halo_btn.text = "▦ 职业光环"
	halo_btn.custom_minimum_size = Vector2(96, 28)
	var h_sty := StyleBoxFlat.new()
	h_sty.bg_color = Color(0.25, 0.16, 0.09, 0.9)
	h_sty.set_corner_radius_all(6)
	h_sty.set_border_width_all(1)
	h_sty.border_color = Color(0.55, 0.4, 0.25)
	halo_btn.add_theme_stylebox_override("normal", h_sty)
	halo_btn.add_theme_stylebox_override("hover", h_sty)
	halo_btn.add_theme_stylebox_override("pressed", h_sty)
	halo_btn.add_theme_color_override("font_color", Color(0.95, 0.91, 0.8))
	halo_btn.add_theme_font_size_override("font_size", 13)
	title_row.add_child(halo_btn)
	var title_lbl := Label.new()
	title_lbl.name = "CosTitle"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.91, 0.77, 0.42))
	title_row.add_child(title_lbl)
	var tr_spacer := Control.new()
	tr_spacer.custom_minimum_size = Vector2(96, 0)
	title_row.add_child(tr_spacer)
	var body := VBoxContainer.new()
	body.name = "CosBody"
	body.add_theme_constant_override("separation", 4)
	up_vbox.add_child(body)
	# 按钮盒：消耗数在上居中，双钮在下居中（解锁居中=参考图）
	var btn_cell := VBoxContainer.new()
	btn_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_cell.add_theme_constant_override("separation", 4)
	up_vbox.add_child(btn_cell)
	var cost_lbl := Label.new()
	cost_lbl.name = "CosCost"
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	btn_cell.add_child(cost_lbl)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	btn_cell.add_child(btn_row)
	var up_btn := Button.new()
	up_btn.name = "CosUp"
	up_btn.custom_minimum_size = Vector2(120, 40)
	btn_row.add_child(up_btn)
	var act_btn := Button.new()
	act_btn.name = "CosAct"
	act_btn.custom_minimum_size = Vector2(150, 40)
	btn_row.add_child(act_btn)
	_build_cos_cards(cards, hero_id, preview, qtag, name_lbl, title_lbl, halo_btn, body, cost_lbl, act_btn, up_btn)

# 穿戴/解锁/升级/兑换后原地刷新（不整窗重建）：同帧重建同名弹窗会被自动改名，
# 返回钮按名关窗恒落空=关不掉（同病灶教训=勋章弹窗原地重建）。
func _refresh_hero_costume_popup(hero_id: String):
	var popup = c.get_node_or_null("HeroCostumePopup")
	if popup == null:
		show_hero_costume_popup(hero_id)
		return
	var cards = popup.find_child("CosCards", true, false)
	var preview = popup.find_child("CosPreview", true, false)
	var qtag = popup.find_child("CosQTag", true, false)
	var name_lbl = popup.find_child("CosName", true, false)
	var title_lbl = popup.find_child("CosTitle", true, false)
	var body = popup.find_child("CosBody", true, false)
	var halo_btn = popup.find_child("CosHalo", true, false)
	var cost_lbl = popup.find_child("CosCost", true, false)
	var act_btn = popup.find_child("CosAct", true, false)
	var up_btn = popup.find_child("CosUp", true, false)
	if cards == null or preview == null or qtag == null or name_lbl == null or title_lbl == null or halo_btn == null or body == null or cost_lbl == null or act_btn == null or up_btn == null:
		return
	_build_cos_cards(cards, hero_id, preview, qtag, name_lbl, title_lbl, halo_btn, body, cost_lbl, act_btn, up_btn)

func _build_cos_cards(cards: VBoxContainer, hero_id: String, preview: TextureRect, qtag: TextureRect, name_lbl: Label, title_lbl: Label, halo_btn: Button, body: VBoxContainer, cost_lbl: Label, act_btn: Button, up_btn: Button):
	for ch in cards.get_children():
		ch.queue_free()
	var cfgs = data.costume_system.get_hero_costume_cfgs(hero_id)
	var worn: String = data.costume_system.get_worn_cos(hero_id)
	if worn == "":
		worn = "__default"
	# 虚拟首卡=初始形象（立绘，永远可用）； costumes.json 各套全为额外解锁服装
	var all: Array = [{"id": "__default", "name": "初始形象", "quality": ""}]
	all.append_array(cfgs)
	var sel := {"id": worn}
	var entries: Array = []
	for cfg in all:
		var cos_id: String = cfg.get("id", "")
		var is_unlocked: bool = (cos_id == "__default") or data.costume_system.is_hero_cos_unlocked(hero_id, cos_id)
		# slim 卡：仅缩略图+已穿戴章+点击层（名字/品质在左侧详情区显示）
		var card := Panel.new()
		card.custom_minimum_size = Vector2(108, 136)
		var c_sty := StyleBoxFlat.new()
		c_sty.bg_color = Color("#3a2c20")
		c_sty.set_corner_radius_all(6)
		c_sty.set_border_width_all(2)
		c_sty.border_color = Color("#8a6a45")
		card.add_theme_stylebox_override("panel", c_sty)
		var th := TextureRect.new()
		th.set_anchors_preset(Control.PRESET_FULL_RECT)
		th.offset_left = 4.0
		th.offset_top = 4.0
		th.offset_right = -4.0
		th.offset_bottom = -20.0
		th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex_path: String = "res://assets/costumes/%s.png" % cos_id
		if cos_id == "__default":
			var base_p: String = "res://assets/portraits/heroes/%s.png" % hero_id
			tex_path = base_p if ResourceLoader.exists(base_p) else ""
		if tex_path != "" and ResourceLoader.exists(tex_path):
			th.texture = load(tex_path)
		if not is_unlocked:
			th.modulate = Color(0.45, 0.45, 0.45)
		card.add_child(th)
		if cos_id == worn:
			var worn_lbl := Label.new()
			worn_lbl.text = "已穿戴"
			worn_lbl.anchor_left = 0.0
			worn_lbl.anchor_right = 1.0
			worn_lbl.anchor_top = 1.0
			worn_lbl.anchor_bottom = 1.0
			worn_lbl.offset_top = -18.0
			worn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			worn_lbl.add_theme_font_size_override("font_size", 10)
			worn_lbl.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
			card.add_child(worn_lbl)
		var hit := Button.new()
		hit.flat = true
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_child(hit)
		entries.append({"card": card, "sty": c_sty, "id": cos_id, "cfg": cfg})
		hit.pressed.connect(_on_cos_card_click.bind(entries, sel, hero_id, cos_id, cfg, preview, qtag, name_lbl, title_lbl, halo_btn, body, cost_lbl, act_btn, up_btn))
		cards.add_child(card)
	for e in entries:
		e.sty.border_color = Color("#e8c56a") if e.id == worn else Color("#8a6a45")
	for e in entries:
		if e.id == worn:
			_on_cos_card_click(entries, sel, hero_id, e.id, e.cfg, preview, qtag, name_lbl, title_lbl, halo_btn, body, cost_lbl, act_btn, up_btn)
			break

# 点卡：金边选中 + 联动预览图/品质标/名牌/效果/双钮
func _on_cos_card_click(entries: Array, sel: Dictionary, hero_id: String, cos_id: String, cfg: Dictionary, preview: TextureRect, qtag: TextureRect, name_lbl: Label, title_lbl: Label, halo_btn: Button, body: VBoxContainer, cost_lbl: Label, act_btn: Button, up_btn: Button):
	sel.id = cos_id
	for e in entries:
		e.sty.border_color = Color("#e8c56a") if e.id == sel.id else Color("#8a6a45")
	var quality: String = cfg.get("quality", "")
	# 拍板：默认皮肤（仅数据 is_default 标记）不显示品质标签；虚拟初始卡 quality 空串自然落空隐藏
	var is_def: bool = cfg.get("is_default", false)
	if is_def:
		qtag.visible = false
	elif COS_TAG_FILES.has(quality) and ResourceLoader.exists("res://assets/costumes/" + COS_TAG_FILES[quality]):
		qtag.texture = load("res://assets/costumes/" + COS_TAG_FILES[quality])
		qtag.visible = true
	else:
		qtag.visible = false
	_update_cos_detail(hero_id, cfg, preview, qtag, name_lbl, title_lbl, halo_btn, body, cost_lbl, act_btn, up_btn)

# 选中联动：预览图/名字/效果/主钮（穿戴·已穿戴·解锁·兑换·未开放）/升级副钮
# 加成内容行：字号/颜色由态决定（▲纯展示行，不承载交互）
# 加成内容行：字号/颜色由态决定（▲纯展示行，不承载交互）
func _add_body_line(body: VBoxContainer, text: String, color: Color, fsize: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(l)

# 技能词条：圆图(缺图回落品质色圆点+首字) + 名称等级行 + 资质行
func _make_cos_chip(icon_path: String, fallback_char: String, chip_color: Color, title: String, sub: String) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 8)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(64, 64)
		chip.add_child(icon)
	else:
		var circ := PanelContainer.new()
		circ.custom_minimum_size = Vector2(64, 64)
		var c_sty := StyleBoxFlat.new()
		c_sty.bg_color = chip_color
		c_sty.set_corner_radius_all(32)
		circ.add_theme_stylebox_override("panel", c_sty)
		var cl := Label.new()
		cl.text = fallback_char
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.set_anchors_preset(Control.PRESET_FULL_RECT)
		cl.add_theme_font_size_override("font_size", 24)
		cl.add_theme_color_override("font_color", Color(0.15, 0.1, 0.07))
		circ.add_child(cl)
		chip.add_child(circ)
	var tx := VBoxContainer.new()
	tx.alignment = BoxContainer.ALIGNMENT_CENTER
	tx.add_theme_constant_override("separation", 2)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", chip_color)
	tx.add_child(tl)
	if sub != "":
		var sl := Label.new()
		sl.text = sub
		sl.add_theme_font_size_override("font_size", 12)
		sl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
		tx.add_child(sl)
	chip.add_child(tx)
	return chip

# 选中联动：预览图/名牌/升级区域（双态：未解锁=解锁效果，已解锁=升级效果）
func _update_cos_detail(hero_id: String, cfg: Dictionary, preview: TextureRect, _qtag: TextureRect, name_lbl: Label, title_lbl: Label, halo_btn: Button, body: VBoxContainer, cost_lbl: Label, act_btn: Button, up_btn: Button):
	for ch in body.get_children():
		ch.queue_free()
	var cos_id: String = cfg.get("id", "")
	var cos_name: String = cfg.get("name", cos_id)
	var quality: String = cfg.get("quality", "素装")
	var st: Dictionary = data.costume_system.get_hero_cos_state(hero_id, cos_id)
	var is_unlocked: bool = data.costume_system.is_hero_cos_unlocked(hero_id, cos_id)
	var stock: int = int(st.get("stock", 0))
	var worn: String = data.costume_system.get_worn_cos(hero_id)
	var per: int = int(data.costume_system._settings().get("apt_per_level", {}).get(quality, 2))
	var dup_bonus: int = int(data.costume_system._settings().get("dup_bonus", 15))
	for connH in halo_btn.pressed.get_connections():
		halo_btn.pressed.disconnect(connH.callable)
	halo_btn.visible = false
	# 初始形象（虚拟默认卡）：使用效果=固定文案+仅穿戴钮
	if cos_id == "__default":
		var bp: String = "res://assets/portraits/heroes/%s.png" % hero_id
		preview.texture = load(bp) if ResourceLoader.exists(bp) else null
		var _bnc := PackedStringArray()
		for _bch in cfg.get("name", "初始形象"):
			_bnc.append(_bch)
		name_lbl.text = "\n".join(_bnc)
		name_lbl.add_theme_color_override("font_color", COS_NAME_GOLD)
		title_lbl.text = "◆ 使用效果 ◆"
		_add_body_line(body, "默认形象，无法升级", Color(0.85, 0.8, 0.7), 15)
		cost_lbl.text = ""
		for conn in act_btn.pressed.get_connections():
			act_btn.pressed.disconnect(conn.callable)
		act_btn.disabled = false
		if worn == "":
			act_btn.text = "已穿戴"
			act_btn.disabled = true
		else:
			act_btn.text = "穿 戴"
			act_btn.pressed.connect(_on_cos_wear.bind(hero_id, "", cfg.get("name", "初始形象")))
		for conn2 in up_btn.pressed.get_connections():
			up_btn.pressed.disconnect(conn2.callable)
		up_btn.visible = false
		return
	var tex_path: String = "res://assets/costumes/%s.png" % cos_id
	preview.texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
	var _nc := PackedStringArray()
	for _ch in cos_name:
		_nc.append(_ch)
	name_lbl.text = "\n".join(_nc)
	name_lbl.add_theme_color_override("font_color", COS_NAME_GOLD)
	# ── 双态：解锁效果 / 升级效果（华服/锦衣双词条分列左右，解锁/双钮居中）
	halo_btn.visible = true
	halo_btn.pressed.connect(_show_halo_rule.bind(hero_id, cfg))
	cost_lbl.text = "库存 %d/1" % stock
	cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	if stock < 1:
		cost_lbl.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 48)
	if is_unlocked:
		title_lbl.text = "◆ 升级效果 ◆"
		_add_body_line(body, "升级：提高以下技能等级上限+%d" % dup_bonus, Color(0.7, 0.66, 0.58), 12)
		var lv: int = int(st.get("base", 1)) + int(st.get("extra", 0))
		chips.add_child(_make_cos_chip("res://assets/skill_icons/%s.png" % cos_id, cos_name.substr(0, 1), COS_NAME_GOLD, "%s %d级" % [cos_name, lv], "资质+%d" % (lv * per)))
		if quality == "华服" or quality == "锦衣":
			var way_cap: int = data.costume_system.get_cos_way_cap(hero_id, quality)
			var way_per: int = 3 if quality == "锦衣" else 1   # 口径=_cos_way_skill_base：华服1/锦衣3
			if way_cap > 0:
				var sk_name: String = _career_skill_name(hero_id, quality)
				chips.add_child(_make_cos_chip(_career_icon_path(hero_id, quality), sk_name.substr(0, 1), Color(0.95, 0.91, 0.8), "%s %d级" % [sk_name, way_cap], "资质+%d" % (way_cap * way_per)))
	else:
		title_lbl.text = "◆ 解锁效果 ◆"
		_add_body_line(body, "解锁以下技能：", Color(0.85, 0.8, 0.7), 13)
		chips.add_child(_make_cos_chip("res://assets/skill_icons/%s.png" % cos_id, cos_name.substr(0, 1), COS_NAME_GOLD, cos_name, ""))
		if quality == "华服" or quality == "锦衣":
			var sk_name2: String = _career_skill_name(hero_id, quality)
			chips.add_child(_make_cos_chip(_career_icon_path(hero_id, quality), sk_name2.substr(0, 1), Color(0.95, 0.91, 0.8), sk_name2, ""))
	body.add_child(chips)
	# ── 钮区：解锁居中(缺库存禁用) / 穿戴+升级(缺库存禁用)
	for conn5 in act_btn.pressed.get_connections():
		act_btn.pressed.disconnect(conn5.callable)
	for conn6 in up_btn.pressed.get_connections():
		up_btn.pressed.disconnect(conn6.callable)
	act_btn.disabled = false
	if is_unlocked:
		if cos_id == worn:
			act_btn.text = "已穿戴"
			act_btn.disabled = true
		else:
			act_btn.text = "穿 戴"
			act_btn.pressed.connect(_on_cos_wear.bind(hero_id, cos_id, cos_name))
		up_btn.visible = true
		up_btn.text = "升 级"
		up_btn.disabled = stock < 1
		up_btn.pressed.connect(_on_cos_extra_upgrade.bind(hero_id, cos_id))
	else:
		up_btn.visible = false
		act_btn.text = "解 锁"
		act_btn.disabled = stock < 1
		act_btn.pressed.connect(_on_cos_unlock.bind(hero_id, cos_id))

# 同名光环技能名：口径=_cos_way_skill_base（（极·）职业书名+（锦衣/华服）后缀）
func _career_skill_name(hero_id: String, quality: String) -> String:
	var cat: String = str(data.heroes.get(hero_id, {}).get("category", ""))
	var book_id: String = data.side_skill_system.get_career_book(cat)
	var book_name: String = str(data.ITEM_CONFIG.get(book_id, {}).get("name", book_id))
	if book_name == "":
		book_name = "职业之道"
	return ("极·" if quality == "锦衣" else "") + book_name + ("（锦衣）" if quality == "锦衣" else "（华服）")

# 职业光环技能词条图：res://assets/skill_icons/career_<拼音>.png（锦衣=career_<拼音>_ji.png）
# 现有素材仅士系；其余职业回落 _make_cos_chip 的品质圆点
func _career_icon_path(hero_id: String, quality: String) -> String:
	var cat: String = str(data.heroes.get(hero_id, {}).get("category", ""))
	var pin: String = {"士": "shi"}.get(cat, "")
	if pin == "":
		return ""
	return "res://assets/skill_icons/career_%s%s.png" % [pin, "_ji" if quality == "锦衣" else ""]

# 职业光环说明弹窗（钮=升级区域左上「▦ 职业光环」）：说明弹窗统一走仓库范式 _show_rule_popup
# 口径=get_halo_cap：服装1级解锁，每1级上限+10，封顶100
func _show_halo_rule(hero_id: String, cfg: Dictionary):
	var cos_name2: String = cfg.get("name", "")
	var cat2: String = str(data.heroes.get(hero_id, {}).get("category", ""))
	var text: String = "%s +1时，解锁光环技能%s·%s\n服装技能每提升1级，光环技能上限+10\n光环技能上限最高100级" % [cos_name2, cos_name2, cat2]
	c._show_rule_popup("职业光环", text)

# 【新增】穿戴回调：写 worn_cos → 刷新弹窗+详情面板+全局 UI
func _on_cos_wear(hero_id: String, cos_id: String, cos_name: String):
	if data.costume_system.wear_hero_cos(hero_id, cos_id):
		c._show_success_popup("已穿戴「%s」" % cos_name, 1.2, "ok")
		_refresh_hero_costume_popup(hero_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()


func _on_exchange_hero_cos(hero_id: String, cos_id: String):
	var res = data.costume_system.exchange_hero_costume(hero_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		_refresh_hero_costume_popup(hero_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# 【新增】手动解锁服装回调：消耗1库存，创建服装状态
func _on_cos_unlock(hero_id: String, cos_id: String):
	var res = data.costume_system.unlock_hero_cos(hero_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		_refresh_hero_costume_popup(hero_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# 【新增】手动升级服装（消耗库存加额外等级）回调
func _on_cos_extra_upgrade(hero_id: String, cos_id: String):
	var res = data.costume_system.upgrade_hero_cos_extra(hero_id, cos_id)
	c._show_success_popup(res.get("msg", ""), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if res.get("ok", false):
		_refresh_hero_costume_popup(hero_id)
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
