# ============================================================
# 妙音坊全屏页（商铺地图 妙音坊「▶」入口；Page z35 / 弹窗 z40，照 BaseView 新模式）
# 第一批：主页骨架 + 收益罐领取 + 加速卡使用弹窗 + 勋章弹窗（含赚速升级挂点）
# 第二批：建筑页/设施升级弹窗/焕新表现 + 满意度意见簿（空态等批次③入住后自动有数据）。
# 红点口径：只页内展示（勋章可升 / 收益罐可领），不穿透商铺地图（照 2026-09-18 用户拍板）。
# ============================================================
class_name MiaoyinView
extends BaseView

var _tab: String = "home"   # home/buildings/satisfaction/rookies/audition
var _rookie_filter: String = "all"   # 新秀页职业筛选：all 或 profession_id
var _building_fac_idx: int = 0   # 【改】批次②③④-B10：建筑弹窗当前选中的设施页签
var _building_sync_checked: bool = false   # 同步升级勾选态；切换建筑/升级重建后保留
var _building_ten_checked: bool = false   # 十连勾选态；切换建筑/升级重建后保留

func _init(p_c):
	super(p_c)
	_page_name = "MiaoyinPage"
	_popup_node_name = "MiaoyinPopup"
	_page_bg = "#211d33"

func _sys() -> MiaoyinSystem:
	return data.miaoyin_system

func show_miaoyin_view():
	show_view()

func hide_miaoyin_view():
	hide_view()

# 【新增】批次②③④-B3：玩法说明弹窗（MiaoyinRulePopup）是独立节点名，基类只认 _popup_node_name，需显式清理
func show_view():
	_close_node("MiaoyinRulePopup")
	super()

func hide_view():
	_close_node("MiaoyinRulePopup")
	super()

func _build(page: Panel):
	_sys().settle_jar()
	if _tab == "buildings":
		_build_building_page(page)
		return
	if _tab == "satisfaction":
		_build_satisfaction_page(page)
		return
	if _tab == "rookies":
		_build_rookie_page(page)
		return
	if _tab == "audition":
		_build_audition_page(page)
		return
	var root := VBoxContainer.new()
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 14
	root.offset_top = 12
	root.offset_right = -14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 10)
	page.add_child(root)

	# 顶栏：返回 + 标题 + 勋章入口
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back := Button.new()
	back.text = "< 返回"   # 【改】UI统一批次①：返回文案统一 < 返回
	back.custom_minimum_size = Vector2(72, 40)
	back.pressed.connect(hide_miaoyin_view)
	top.add_child(back)
	# 【改】批次②③④-B3：弹簧居中标题组，"?"只出现在玩法主标题旁（说明流程/规则）
	var left_spring := Control.new()
	left_spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(left_spring)
	var title := Label.new()
	title.text = "妙音坊"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var rule_btn := Button.new()
	rule_btn.text = "?"
	rule_btn.custom_minimum_size = Vector2(30, 30)
	rule_btn.add_theme_font_size_override("font_size", 16)
	rule_btn.pressed.connect(_show_rule_popup)
	top.add_child(rule_btn)
	var right_spring := Control.new()
	right_spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right_spring)
	var medal_btn := Button.new()
	medal_btn.text = "勋章"
	medal_btn.custom_minimum_size = Vector2(84, 40)
	medal_btn.pressed.connect(_show_medal_popup)
	top.add_child(medal_btn)
	_add_btn_dot(medal_btn, _sys().can_upgrade_medal().get("ok", false))

	# 左上资源行：应援币 + 加速卡入口
	var res := HBoxContainer.new()
	res.alignment = BoxContainer.ALIGNMENT_CENTER
	res.add_theme_constant_override("separation", 8)
	root.add_child(res)
	var yyb_lbl := Label.new()
	yyb_lbl.text = "应援币 %s（+%s/分）" % [c.format_number(int(_sys().yyb)), _fmt_rate(_sys().get_yyb_per_min())]
	yyb_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yyb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.add_child(yyb_lbl)
	var plus := Button.new()
	plus.text = "＋"
	plus.custom_minimum_size = Vector2(42, 36)
	plus.pressed.connect(_on_plus_pressed)
	res.add_child(plus)

	# 中间收益罐：三轨累积，点击领取
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 250)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("#2a2640")
	card_style.set_corner_radius_all(12)
	card_style.set_border_width_all(2)
	card_style.border_color = Color("#6a5f9e")
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	var jar_title := Label.new()
	jar_title.text = "收益罐"
	jar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jar_title.add_theme_font_size_override("font_size", 22)
	jar_title.add_theme_color_override("font_color", Color("#ffd700"))
	cv.add_child(jar_title)
	var pending_total: int = _sys().get_pending_total()
	var pending_lbl := Label.new()
	pending_lbl.text = "可领取：%s" % c.format_number(pending_total)
	pending_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pending_lbl.add_theme_font_size_override("font_size", 20)
	cv.add_child(pending_lbl)
	var rate_lbl := Label.new()
	rate_lbl.text = "产出/分：应援币 %s｜应援物 %s｜缘分物 %s" % [
		_fmt_rate(_sys().get_yyb_per_min()), _fmt_rate(_sys().get_yyw_per_min()), _fmt_rate(_sys().get_yyf_per_min())]
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_lbl.add_theme_font_size_override("font_size", 15)
	rate_lbl.add_theme_color_override("font_color", Color("#bdb7d8"))
	cv.add_child(rate_lbl)
	var claim := Button.new()
	claim.text = "领取收益"
	claim.custom_minimum_size = Vector2(140, 44)
	claim.disabled = pending_total <= 0
	claim.pressed.connect(_on_claim_pressed)
	cv.add_child(claim)
	_add_btn_dot(claim, pending_total > 0)

	# 底部四入口：建筑/满意度批次②已接；新秀/选秀仍占位，红点随对应批次接入
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	var b_build := Button.new()
	b_build.text = "建筑"
	b_build.custom_minimum_size = Vector2(82, 52)
	b_build.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_build.pressed.connect(_open_building_page)
	bottom.add_child(b_build)
	_add_btn_dot(b_build, _sys().has_any_upgradeable_building())
	var b_rookie := Button.new()
	b_rookie.text = "新秀"
	b_rookie.custom_minimum_size = Vector2(82, 52)
	b_rookie.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_rookie.pressed.connect(_open_rookie_page)
	bottom.add_child(b_rookie)
	_add_btn_dot(b_rookie, _sys().has_rookie_attention())
	var b_sat := Button.new()
	b_sat.text = "满意度"
	b_sat.custom_minimum_size = Vector2(82, 52)
	b_sat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_sat.pressed.connect(_open_satisfaction_page)
	bottom.add_child(b_sat)
	_add_btn_dot(b_sat, _sys().get_bad_unresolved_count() > 0)
	var b_aud := Button.new()
	b_aud.text = "选秀"
	b_aud.custom_minimum_size = Vector2(82, 52)
	b_aud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_aud.pressed.connect(_open_audition_page)
	bottom.add_child(b_aud)
	_add_btn_dot(b_aud, _sys().has_audition_attention())

func _fmt_rate(x: float) -> String:
	if x >= 100.0:
		return c.format_number(int(round(x)))
	if x > 0.0:
		return "%.1f" % x
	return "0"

func _on_plus_pressed():
	var count: int = int(data.items.get("miaoyin_jiasu_ka", 0))
	if count <= 0:
		c._show_stage_hint("没有妙音坊加速卡")
		return
	_show_accel_popup()

func _on_claim_pressed():
	var r: Dictionary = _sys().claim_jar()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "暂无可领取收益")))
		return
	c._show_stage_hint(str(r.get("msg", "领取成功")))
	c.update_all_ui()
	_refresh()

# 【新增】批次②③④-B3：妙音坊玩法说明弹窗（只从主标题旁"?"进入；长说明不进画面）
func _show_rule_popup():
	_close_node("MiaoyinRulePopup")
	var popup: PanelContainer = c._create_base_popup("妙音坊说明", Vector2(380, 320))
	popup.name = "MiaoyinRulePopup"
	popup.get_meta("popup_mask").z_index = 39
	popup.z_index = 40
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child
	var vb: VBoxContainer = popup.get_child(0)
	for line in [
		"收益罐三轨（应援币/应援物/缘分物）随时间累积，领取后入账；加速卡每张=立即获得60分钟三轨收益。",
		"设施等级独立，建筑等级=设施等级之和；设施升级消耗应援币。",
		"训练仅吃本职业应援物：材料足够时自动吃到升级，不足不扣。",
		"入住免费，每职业最多入住%d人，替换会迁出原住客；选秀只能上阵已入住挚友。" % MiaoyinSystem.ROOKIE_PROF_CAP,
		"勋章：繁荣度=应援币总产出/分，只作门槛不消耗；每级全部商铺赚速+100%。",
	]:
		var body := Label.new()
		body.text = line
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(body)

# ---------- 内部子页切换：主页 / 建筑 / 满意度（新秀=批次③，选秀=批次④，仍占位） ----------
func _open_building_page():
	_tab = "buildings"
	close_popup()
	_refresh()

func _open_satisfaction_page():
	_tab = "satisfaction"
	close_popup()
	_refresh()

func _go_home():
	_tab = "home"
	close_popup()
	_refresh()

func _new_page_root(page: Panel) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 14
	root.offset_top = 12
	root.offset_right = -14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 10)
	page.add_child(root)
	return root

func _add_sub_header(root: VBoxContainer, title_text: String):
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back := Button.new()
	back.text = "< 返回"   # 【改】UI统一批次①：返回文案统一 < 返回
	back.custom_minimum_size = Vector2(72, 40)
	back.pressed.connect(_go_home)
	top.add_child(back)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var yyb_lbl := Label.new()
	yyb_lbl.text = "应援币 %s" % c.format_number(int(_sys().yyb))
	yyb_lbl.custom_minimum_size = Vector2(112, 40)
	yyb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(yyb_lbl)

func _build_building_page(page: Panel):
	var root := _new_page_root(page)
	_add_sub_header(root, "妙音坊建筑")
	var tip := Label.new()
	tip.text = "建筑按下一级费用升序；[荐]=当前最省钱升级。设施名变色/红星为焕新表现，不加属性。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", Color("#bdb7d8"))
	root.add_child(tip)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for card in _sys().get_building_card_list():
		var bid: String = str(card.get("bid", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if card.get("unlocked", false):
			var prefix: String = "[荐] " if card.get("recommended", false) else ""
			var type_name: String = "功能" if str(card.get("type", "")) == "function" else "居所"
			b.text = "%s%s（%s）  Lv.%d\n下一级费用 %s" % [
				prefix, str(card.get("name", bid)), type_name, int(card.get("level", 0)),
				c.format_number(int(card.get("next_cost", 0)))]
			b.pressed.connect(_open_building_popup.bind(bid))
			_add_btn_dot(b, card.get("upgradeable", false))
		else:
			b.text = "锁 %s（%s）\n需要勋章 %d 级解锁" % [
				str(card.get("name", bid)), "功能" if str(card.get("type", "")) == "function" else "居所",
				int(card.get("unlock_medal", 1))]
			var need_lv: int = int(card.get("unlock_medal", 1))
			b.pressed.connect(func(): c._show_stage_hint("需要妙音坊勋章 %d 级解锁" % need_lv))
		list.add_child(b)

func _open_building_popup(bid: String):
	_building_fac_idx = 0   # 打开另一栋建筑时回到第一个设施页签；同步/十连勾选态保留
	_show_building_popup(bid)

func _show_building_popup(bid: String):
	var bcfg: Dictionary = _sys().get_building_cfg(bid)
	if bcfg.is_empty():
		return
	if not _sys().is_building_unlocked(bcfg):
		c._show_stage_hint("需要妙音坊勋章 %d 级解锁" % int(bcfg.get("unlock_medal", 1)))
		return
	close_popup()
	_popup_kind = "building"
	_popup_id = bid
	var popup: PanelContainer = c._create_base_popup(str(bcfg.get("name", "建筑")), Vector2(520, 560))
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	
	var fac_count: int = _sys().get_facility_count(bid)
	_building_fac_idx = clampi(_building_fac_idx, 0, maxi(0, fac_count - 1))
	var type_name: String = "功能建筑" if str(bcfg.get("type", "")) == "function" else "居住建筑"
	var head := Label.new()
	head.text = "%s　总等级 Lv.%d　设施 %d 个" % [type_name, _sys().get_building_level(bid), fac_count]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 16)
	vb.add_child(head)
	var yyb_lbl := Label.new()
	yyb_lbl.text = "应援币 %s" % c.format_number(int(_sys().yyb))
	yyb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yyb_lbl.add_theme_color_override("font_color", Color("#bdb7d8"))
	vb.add_child(yyb_lbl)
	
	# 设施页签区：同步升级入口固定放在页签上方；勾选后升级动作从“单设施”切换为“整栋建筑”
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 10)
	vb.add_child(mode_row)
	var sync_chk := CheckBox.new()
	sync_chk.text = "同步升级"
	sync_chk.button_pressed = _building_sync_checked
	sync_chk.toggled.connect(_on_building_sync_toggled)
	mode_row.add_child(sync_chk)
	var mode_hint := Label.new()
	mode_hint.text = "勾选后升级整栋建筑全部设施"
	mode_hint.add_theme_color_override("font_color", Color("#9a93b8"))
	mode_row.add_child(mode_hint)
	
	var tabs_row := HBoxContainer.new()
	tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs_row.add_theme_constant_override("separation", 6)
	vb.add_child(tabs_row)
	for i in range(fac_count):
		var fac: Dictionary = _sys().get_facility_cfg(bid, i)
		var lv: int = _sys().get_facility_level(bid, i)
		var fac_tab := Button.new()
		fac_tab.text = "%s\nLv.%d" % [str(fac.get("name", "设施")), lv]
		fac_tab.custom_minimum_size = Vector2(74, 48)
		fac_tab.add_theme_font_size_override("font_size", 11)
		fac_tab.toggle_mode = true
		fac_tab.button_pressed = i == _building_fac_idx
		fac_tab.add_theme_color_override("font_color", _sys().get_facility_color(lv))
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = Color("#2a2640")
		normal_style.set_corner_radius_all(6)
		normal_style.set_border_width_all(1)
		normal_style.border_color = Color("#5a537a")
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color("#332c4c")
		hover_style.set_corner_radius_all(6)
		hover_style.set_border_width_all(1)
		hover_style.border_color = Color("#7d73a8")
		var selected_style := StyleBoxFlat.new()
		selected_style.bg_color = Color("#3a3156")
		selected_style.set_corner_radius_all(6)
		selected_style.set_border_width_all(2)
		selected_style.border_color = Color("#ffd700")
		fac_tab.add_theme_stylebox_override("normal", selected_style if i == _building_fac_idx else normal_style)
		fac_tab.add_theme_stylebox_override("hover", selected_style if i == _building_fac_idx else hover_style)
		fac_tab.add_theme_stylebox_override("pressed", selected_style)
		fac_tab.add_theme_stylebox_override("focus", selected_style if i == _building_fac_idx else normal_style)
		fac_tab.pressed.connect(_select_building_facility.bind(i))
		tabs_row.add_child(fac_tab)
	
	# 底部固定升级区：始终显示当前设施信息；同步勾选时费用/动作切换为整栋建筑聚合口径
	var detail := PanelContainer.new()
	detail.custom_minimum_size = Vector2(0, 260)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color("#241f38")
	detail_style.set_corner_radius_all(8)
	detail_style.set_border_width_all(1)
	detail_style.border_color = Color("#6a5f9e")
	detail.add_theme_stylebox_override("panel", detail_style)
	vb.add_child(detail)
	var dv := VBoxContainer.new()
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_theme_constant_override("separation", 10)
	detail.add_child(dv)
	var cur_fac: Dictionary = _sys().get_facility_cfg(bid, _building_fac_idx)
	var cur_lv: int = _sys().get_facility_level(bid, _building_fac_idx)
	var fac_title := Label.new()
	fac_title.text = _sys().get_facility_display_name(str(cur_fac.get("name", "设施")), cur_lv)
	fac_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fac_title.add_theme_font_size_override("font_size", 18)
	fac_title.add_theme_color_override("font_color", _sys().get_facility_color(cur_lv))
	dv.add_child(fac_title)
	var fac_info := Label.new()
	fac_info.text = "所属建筑：%s　设施 %d/%d　建筑总等级 Lv.%d" % [
		str(bcfg.get("name", bid)), _building_fac_idx + 1, fac_count, _sys().get_building_level(bid)]
	fac_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fac_info.add_theme_color_override("font_color", Color("#bdb7d8"))
	dv.add_child(fac_info)
	
	var action_count: int = 10 if _building_ten_checked else 1
	var action_cost: int = _get_building_sync_cost(bid, action_count) if _building_sync_checked else _sys().get_facility_upgrade_cost(bid, _building_fac_idx, action_count)
	var cost_prefix: String = "同步消耗：应援币" if _building_sync_checked else "升级消耗：应援币"
	c._add_cost_row(dv, cost_prefix, int(_sys().yyb), action_cost)   # 【改】批次②③④-B10：统一（拥有/消耗），数字红绿
	var action_hint := Label.new()
	action_hint.text = "同步模式：全部可升级设施各升 %d 级" % action_count if _building_sync_checked else "当前模式：仅升级选中设施 %d 级" % action_count
	action_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_hint.add_theme_color_override("font_color", Color("#9a93b8"))
	dv.add_child(action_hint)
	
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 12)
	dv.add_child(action_row)
	var up_btn := Button.new()
	up_btn.text = "升级"
	up_btn.custom_minimum_size = Vector2(130, 42)
	var can_act: Dictionary = _sys().can_upgrade_building_sync(bid, action_count) if _building_sync_checked else _sys().can_upgrade_facility(bid, _building_fac_idx, action_count)
	up_btn.disabled = not can_act.get("ok", false)
	if not can_act.get("ok", false):
		up_btn.tooltip_text = str(can_act.get("msg", "无法升级"))
	up_btn.pressed.connect(_on_building_upgrade_action.bind(bid, _building_fac_idx))
	action_row.add_child(up_btn)
	var ten_chk := CheckBox.new()
	ten_chk.text = "十连"
	ten_chk.button_pressed = _building_ten_checked
	ten_chk.toggled.connect(_on_building_ten_toggled)
	action_row.add_child(ten_chk)

func _select_building_facility(fac_idx: int):
	# Toggle 按钮点击已选页签时会先短暂取消选中；统一重建，确保选中态视觉不被卡在未选状态
	_building_fac_idx = fac_idx
	_rebuild_popup()

func _on_building_sync_toggled(pressed: bool):
	_building_sync_checked = pressed
	_rebuild_popup()

func _on_building_ten_toggled(pressed: bool):
	_building_ten_checked = pressed
	_rebuild_popup()

func _get_building_sync_cost(bid: String, count: int) -> int:
	# 只按等级上限过滤；不能因当前应援币不足就把需求费用显示为 0，是否足够由消耗行红绿/按钮禁用表达
	var total: int = 0
	for i in range(_sys().get_facility_count(bid)):
		if _sys().get_facility_level(bid, i) + count <= _sys().get_facility_max_lv_pub():
			total += _sys().get_facility_upgrade_cost(bid, i, count)
	return total

func _on_building_upgrade_action(bid: String, fac_idx: int):
	var count: int = 10 if _building_ten_checked else 1
	if _building_sync_checked:
		_on_building_sync(bid, count)
	else:
		_on_facility_upgrade(bid, fac_idx, count)

func _on_facility_upgrade(bid: String, fac_idx: int, count: int):
	var r: Dictionary = _sys().upgrade_facility(bid, fac_idx, count)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "升级失败")))
		return
	c._show_stage_hint("十连升级成功" if count >= 10 else "升级成功")
	c.update_all_ui()
	_refresh()

func _on_building_sync(bid: String, count: int):
	var r: Dictionary = _sys().upgrade_building_sync(bid, count)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "同步升级失败")))
		return
	c._show_stage_hint("同步十连：%d 个设施升级" % int(r.get("count", 0)) if count >= 10 else "同步升级：%d 个设施升级" % int(r.get("count", 0)))
	c.update_all_ui()
	_refresh()

func _build_satisfaction_page(page: Panel):
	var root := _new_page_root(page)
	_add_sub_header(root, "满意度")
	var score: float = _sys().get_satisfaction_score()
	var bonus_pct: float = _sys().get_satisfaction_bonus_pct()
	var bad_n: int = _sys().get_bad_unresolved_count()
	var summary := Label.new()
	summary.text = "满意度 %.0f%%　三轨产出 +%.0f%%　未处理差评 %d　每日12:00刷新" % [score * 100.0, bonus_pct * 100.0, bad_n]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 16)
	root.add_child(summary)
	# 【改】2026-09-19：逐件列出拥有的满意度产出藏品（含 c194 冷月寒泉）；文案=满意度产出（乘产出率，非满意度本体）
	for line_text in _sys().get_collection_satisfaction_lines():
		var cl := Label.new()
		cl.text = line_text
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.add_theme_color_override("font_color", Color("#7ee787"))
		root.add_child(cl)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	var ops: Array = _sys().get_opinion_list()
	if ops.is_empty():
		var empty := Label.new()
		empty.text = "暂无入住挚友，意见簿为空；入住后自动生成。"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("#bdb7d8"))
		rows.add_child(empty)
		return
	for op in ops:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)
		var state_lbl := Label.new()
		if op.get("bad", false):
			state_lbl.text = "[差评]"
			state_lbl.add_theme_color_override("font_color", Color("#ff6b6b"))
		elif op.get("resolved", false):
			state_lbl.text = "[已处理]"
			state_lbl.add_theme_color_override("font_color", Color("#7ee787"))
		else:
			state_lbl.text = "[好评]"
			state_lbl.add_theme_color_override("font_color", Color("#9be28f"))
		state_lbl.custom_minimum_size = Vector2(70, 30)
		row.add_child(state_lbl)
		var text_lbl := Label.new()
		text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if op.get("bad", false):
			text_lbl.text = "%s 不满：%s / %s" % [str(op.get("friend_name", "")), str(op.get("building_name", "")), str(op.get("facility_name", ""))]
		else:
			text_lbl.text = "%s 满意：%s / %s" % [str(op.get("friend_name", "")), str(op.get("building_name", "")), str(op.get("facility_name", ""))]
		row.add_child(text_lbl)
		if op.get("bad", false):
			var go := Button.new()
			go.text = "前往"
			go.custom_minimum_size = Vector2(64, 32)
			go.pressed.connect(_show_building_popup.bind(str(op.get("bid", ""))))
			row.add_child(go)


# ---------- 新秀子页（批次③：挚友=新秀；总览/详情/训练/入住；芳华待专项定稿后追加） ----------
func _open_rookie_page():
	_tab = "rookies"
	close_popup()
	_refresh()

func _set_rookie_filter(prof_id: String):
	_rookie_filter = prof_id
	close_popup()
	_refresh()

func _rookie_card_attention(entry: Dictionary) -> bool:
	return entry.get("can_train", false) or entry.get("can_checkin", false)

func _build_rookie_page(page: Panel):
	var root := _new_page_root(page)
	_add_sub_header(root, "妙音坊新秀")
	_ensure_rookie_shape_hint()
	var prof_list: Array = _sys().get_profession_list()
	var valid_filter: bool = false
	for p in prof_list:
		if str(p.get("id", "")) == _rookie_filter:
			valid_filter = true
	if not valid_filter and prof_list.size() > 0:
		_rookie_filter = str(prof_list[0].get("id", ""))
	var filter_row := HBoxContainer.new()
	filter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	filter_row.add_theme_constant_override("separation", 6)
	root.add_child(filter_row)
	for p in prof_list:
		var pid: String = str(p.get("id", ""))
		var b := Button.new()
		b.text = str(p.get("name", pid))
		b.custom_minimum_size = Vector2(54, 32)
		b.disabled = _rookie_filter == pid
		b.pressed.connect(_set_rookie_filter.bind(pid))
		filter_row.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var ov: Dictionary = _sys().get_rookie_overview(_rookie_filter)
	var housed: Array = ov.get("housed", [])
	var unhoused: Array = ov.get("unhoused", [])
	var summary := Label.new()
	summary.text = "已入住 %d　未入住 %d　空居所 %d　入住免费" % [housed.size(), unhoused.size(), _sys().get_empty_residences().size()]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_color_override("font_color", Color("#bdb7d8"))
	list.add_child(summary)
	var sync_all := Button.new()
	sync_all.text = "本职业同步升1级"
	sync_all.custom_minimum_size = Vector2(150, 38)
	sync_all.pressed.connect(_on_sync_profession_rookies)
	list.add_child(sync_all)
	_add_rookie_section(list, "已入住", housed)
	_add_rookie_section(list, "未入住", unhoused)

func _ensure_rookie_shape_hint():
	# 触一次新秀注册，避免总览首次打开为空
	_sys().get_rookie_overview(_rookie_filter)

func _add_rookie_section(list: VBoxContainer, title: String, entries: Array):
	var sec := Label.new()
	sec.text = "%s（%d）" % [title, entries.size()]
	sec.add_theme_font_size_override("font_size", 18)
	sec.add_theme_color_override("font_color", Color("#e6c07b"))
	list.add_child(sec)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "暂无"
		empty.add_theme_color_override("font_color", Color("#bdb7d8"))
		list.add_child(empty)
		return
	for e in entries:
		var fid: String = str(e.get("fid", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "%s　%s　Lv.%d\n居所：%s　服装：%d　经验 %s/%s" % [
			str(e.get("name", fid)), str(e.get("prof_name", "")), int(e.get("lv", 1)),
			str(e.get("house_name", "未入住")), int(e.get("costume_count", 0)),
			c.format_number(int(e.get("exp", 0))), c.format_number(int(e.get("next_exp", 0)))]
		b.pressed.connect(_show_rookie_popup.bind(fid))
		list.add_child(b)
		_add_btn_dot(b, _rookie_card_attention(e))

func _show_rookie_popup(fid: String):
	var r: Dictionary = _sys().get_rookie_entry(fid)
	if r.is_empty():
		return
	close_popup()
	_popup_kind = "rookie"
	_popup_id = fid
	var cfg: Dictionary = data.get_friend_config(fid)
	var popup: PanelContainer = c._create_base_popup(str(cfg.get("name", fid)), Vector2(470, 560))
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var lv: int = int(r.get("lv", 1))
	var cur_exp: int = int(r.get("exp", 0))
	var next_exp: int = _sys().get_rookie_next_exp(lv)
	var head := Label.new()
	head.text = "%s　Lv.%d　服装 %d 件" % [_sys()._profession_name(str(r.get("prof", ""))), lv, _sys().get_rookie_costume_count(fid)]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 16)
	vb.add_child(head)
	var house_txt := Label.new()
	house_txt.text = "居所：%s" % (str(_sys().get_building_cfg(str(r.get("house", ""))).get("name", "未入住")) if str(r.get("house", "")) != "" else "未入住")
	house_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	house_txt.add_theme_color_override("font_color", Color("#bdb7d8"))
	vb.add_child(house_txt)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = float(next_exp)
	bar.value = minf(float(cur_exp), float(next_exp))
	bar.show_percentage = true
	bar.custom_minimum_size = Vector2(420, 18)
	vb.add_child(bar)
	var attrs: Dictionary = _sys().get_rookie_attrs(fid)
	var attr_lbl := Label.new()
	var attr_parts: Array = []
	for pid in attrs.keys():
		attr_parts.append("%s %s%d" % [_sys()._profession_name(pid), str(attrs[pid].get("tag", "")), int(attrs[pid].get("attr", 0))])
	attr_lbl.text = "　".join(attr_parts)
	attr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attr_lbl.add_theme_font_size_override("font_size", 13)
	attr_lbl.add_theme_color_override("font_color", Color("#bdb7d8"))
	vb.add_child(attr_lbl)
	# 【删】批次②③④-B3：训练规则说明迁入主标题旁"?"玩法说明
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	for it in _sys().get_rookie_support_items(fid):
		var sid: String = str(it.get("id", ""))
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		rows.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = "%s（+%d经验）" % [str(it.get("name", sid)), int(it.get("exp", 0))]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var own_lbl := Label.new()
		own_lbl.text = "×%d" % int(it.get("owned", 0))
		own_lbl.custom_minimum_size = Vector2(54, 28)
		row.add_child(own_lbl)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	vb.add_child(btns)
	var house_btn := Button.new()
	house_btn.text = "住所"
	house_btn.custom_minimum_size = Vector2(74, 34)
	house_btn.pressed.connect(_show_house_popup.bind(fid))
	btns.add_child(house_btn)
	var up_btn := Button.new()
	up_btn.text = "升一级"
	up_btn.custom_minimum_size = Vector2(76, 34)
	up_btn.disabled = not _sys().can_rookie_train(fid)
	up_btn.pressed.connect(_on_train_level_up.bind(fid))
	btns.add_child(up_btn)

func _on_sync_profession_rookies():
	var r: Dictionary = _sys().train_profession_rookies_level_up(_rookie_filter)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "同步升级失败")))
		return
	c._show_stage_hint(str(r.get("msg", "同步升级成功")))
	c.update_all_ui()
	_refresh()

func _on_train_level_up(fid: String):
	var r: Dictionary = _sys().train_rookie_level_up_once(fid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "升级失败")))
		return
	c._show_stage_hint("升级成功")
	c.update_all_ui()
	_refresh()

func _show_house_popup(fid: String):
	var r: Dictionary = _sys().get_rookie_entry(fid)
	if r.is_empty():
		return
	close_popup()
	_popup_kind = "house"
	_popup_id = fid
	var cfg: Dictionary = data.get_friend_config(fid)
	var popup: PanelContainer = c._create_base_popup("安排住所 - " + str(cfg.get("name", fid)), Vector2(520, 520))
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	# 【删】批次②③④-B3：入住规则说明迁入主标题旁"?"玩法说明
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	var cur_house: String = str(r.get("house", ""))
	for card in _sys().get_residence_cards():
		var bid: String = str(card.get("bid", ""))
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)
		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text = "%s　Lv.%d　应援 %d/分" % [str(card.get("name", bid)), int(card.get("level", 0)), int(card.get("yyw_per_min", 0))]
		row.add_child(name_lbl)
		var occ_lbl := Label.new()
		occ_lbl.custom_minimum_size = Vector2(96, 30)
		occ_lbl.text = str(card.get("occupant_name", "")) if str(card.get("occupant", "")) != "" else "空"
		row.add_child(occ_lbl)
		var go := Button.new()
		go.custom_minimum_size = Vector2(70, 32)
		if bid == cur_house:
			go.text = "当前"
			go.disabled = true
		elif str(card.get("occupant", "")) == "":
			go.text = "入住"
			go.disabled = not _sys().can_checkin_rookie(fid, bid).get("ok", false)
		else:
			go.text = "替换"
			go.disabled = not _sys().can_checkin_rookie(fid, bid).get("ok", false)
		if go.disabled:
			go.tooltip_text = str(_sys().can_checkin_rookie(fid, bid).get("msg", ""))
		go.pressed.connect(_on_checkin.bind(fid, bid))
		row.add_child(go)

func _on_checkin(fid: String, bid: String):
	var r: Dictionary = _sys().checkin_rookie(fid, bid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "入住失败")))
		return
	c._show_stage_hint(str(r.get("msg", "入住成功")))
	c.update_all_ui()
	_refresh()


# ---------- 选秀子页（批次④：三属性门/一键上阵/挑战/奖励） ----------
func _open_audition_page():
	_tab = "audition"
	close_popup()
	_refresh()

func _build_audition_page(page: Panel):
	var root := _new_page_root(page)
	_add_sub_header(root, "赛区选秀")
	var ov: Dictionary = _sys().get_audition_overview()
	var info: Dictionary = ov.get("info", {})
	var chk: Dictionary = ov.get("check", {})
	var title := Label.new()
	title.text = "选秀第 %d 场　第 %d 轮 %d/5　推荐新秀平均等级 %d" % [int(info.get("stage", 1)), int(info.get("round", 1)), int(info.get("pos", 1)), int(info.get("rec_lv", 30))]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#e6c07b"))
	root.add_child(title)
	var gates := VBoxContainer.new()
	gates.add_theme_constant_override("separation", 6)
	root.add_child(gates)
	_add_gate_row(gates, "主属性 %s" % _sys()._profession_name(str(info.get("main_prof", ""))), int(chk.get("main_sum", 0)), int(info.get("main_gate", 0)))
	_add_gate_row(gates, "副属性 %s" % _sys()._profession_name(str(info.get("good_prof", ""))), int(chk.get("good_sum", 0)), int(info.get("good_gate", 0)))
	_add_gate_row(gates, "副属性 %s" % _sys()._profession_name(str(info.get("bad_prof", ""))), int(chk.get("bad_sum", 0)), int(info.get("bad_gate", 0)))
	var reward_lbl := Label.new()
	reward_lbl.text = "通关奖励：%s×%s　应援物×%s　应援币×%s" % [
		str(data.ITEM_CONFIG.get(_sys().get_flower_by_profession(str(info.get("main_prof", ""))), {}).get("name", "缘分物")),
		c.format_number(int(info.get("yyf_reward", 0))), c.format_number(int(info.get("yyw_reward", 0))), c.format_number(int(info.get("yyb_reward", 0)))]
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_lbl.add_theme_color_override("font_color", Color("#bdb7d8"))
	root.add_child(reward_lbl)
	var team_title := Label.new()
	team_title.text = "上阵队伍（%d/%d）" % [int(chk.get("filled", 0)), int(chk.get("team_size", 4))]
	team_title.add_theme_font_size_override("font_size", 16)
	root.add_child(team_title)
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 8)
	root.add_child(slots)
	var team_cards: Array = ov.get("team", [])
	for i in range(team_cards.size()):
		var card: Dictionary = team_cards[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(92, 58)
		b.text = str(card.get("name", "空")) if str(card.get("fid", "")) != "" else "空"
		if str(card.get("fid", "")) != "":
			b.text += "\nLv.%d" % int(card.get("lv", 0))
		b.pressed.connect(_show_audition_team_popup.bind(i))
		slots.add_child(b)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 10)
	root.add_child(btns)
	var auto_btn := Button.new()
	auto_btn.text = "一键上阵"
	auto_btn.custom_minimum_size = Vector2(92, 36)
	auto_btn.pressed.connect(_on_auto_audition_team)
	btns.add_child(auto_btn)
	var fight_btn := Button.new()
	fight_btn.text = "挑战"
	fight_btn.custom_minimum_size = Vector2(92, 36)
	fight_btn.disabled = not chk.get("ok", false)
	fight_btn.pressed.connect(_on_challenge_audition)
	btns.add_child(fight_btn)

func _add_gate_row(parent: VBoxContainer, label_text: String, value: int, gate: int):
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	# 【改】批次②③④-B10：属性门槛统一（当前/需求）格式，属性名默认色、数字红绿
	var gate_cost_row: HBoxContainer = c._add_cost_row(row, label_text, value, gate)
	gate_cost_row.custom_minimum_size = Vector2(190, 26)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(1.0, float(gate))
	bar.value = minf(float(value), float(gate))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 16)
	row.add_child(bar)

func _show_audition_team_popup(slot: int):
	close_popup()
	_popup_kind = "audition_team"
	_popup_id = str(slot)
	var popup: PanelContainer = c._create_base_popup("选择上阵挚友 - 槽位 %d" % (slot + 1), Vector2(500, 520))
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	# 【删】批次②③④-B3：上阵规则说明迁入主标题旁"?"玩法说明
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	var info: Dictionary = _sys().get_audition_stage_info()
	for fid in _sys().get_housed_rookie_ids():
		var r: Dictionary = _sys().get_rookie_entry(fid)
		var attrs: Dictionary = _sys().get_rookie_attrs(fid)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)
		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text = "%s　%s　Lv.%d　主属性 %d" % [
			str(data.get_friend_config(fid).get("name", fid)), _sys()._profession_name(str(r.get("prof", ""))),
			int(r.get("lv", 1)), int(attrs.get(str(info.get("main_prof", "")), {}).get("attr", 0))]
		row.add_child(name_lbl)
		var pick := Button.new()
		pick.text = "上阵"
		pick.custom_minimum_size = Vector2(70, 32)
		pick.pressed.connect(_on_pick_audition_slot.bind(slot, fid))
		row.add_child(pick)
	var clear_btn := Button.new()
	clear_btn.text = "清空该槽"
	clear_btn.custom_minimum_size = Vector2(100, 34)
	clear_btn.pressed.connect(_on_pick_audition_slot.bind(slot, ""))
	vb.add_child(clear_btn)

func _on_pick_audition_slot(slot: int, fid: String):
	var r: Dictionary = _sys().set_audition_team_slot(slot, fid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "上阵失败")))
		return
	c.update_all_ui()
	_refresh()

func _on_auto_audition_team():
	_sys().set_audition_team(_sys().auto_pick_audition_team())
	c._show_stage_hint("已按主属性职业自动上阵")
	c.update_all_ui()
	_refresh()

func _on_challenge_audition():
	var r: Dictionary = _sys().pass_audition()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "挑战失败")))
		return
	var rewards: Dictionary = r.get("rewards", {})
	c._show_stage_hint("通关：缘分物+%s 应援物+%s 应援币+%s" % [
		c.format_number(int(rewards.get("yyf", 0))), c.format_number(int(rewards.get("yyw", 0))), c.format_number(int(rewards.get("yyb", 0)))])
	c.update_all_ui()
	_refresh()


func _rebuild_popup():
	if _popup_kind == "medal":
		_show_medal_popup()
	elif _popup_kind == "accel":
		_show_accel_popup()
	elif _popup_kind == "building" and _popup_id != "":
		_show_building_popup(_popup_id)
	elif _popup_kind == "rookie" and _popup_id != "":
		_show_rookie_popup(_popup_id)
	elif _popup_kind == "house" and _popup_id != "":
		_show_house_popup(_popup_id)
	elif _popup_kind == "audition_team":
		_show_audition_team_popup(int(_popup_id))

# ---------- 弹窗：勋章（15 级全表；繁荣度=应援币总产出/分；全部商铺赚速 +100%×级） ----------
# 勋章固定样式（2026-09-19 用户拍板）：主页右上角【勋章】入口 -> 460×420「勋章」弹窗 -> #2a2640/#6a5f9e 勋章卡 -> 等级旁[?]规则 -> 当前效果 -> 下一级进度条 -> 升级按钮 -> 关闭。后续新玩法照此模板，不再另起样式。
func _show_medal_popup():
	close_popup()
	_popup_kind = "medal"
	var popup: PanelContainer = c._create_base_popup("勋章", Vector2(460, 420))
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var pvb: VBoxContainer = popup.get_child(0)
	var lv: int = _sys().get_medal_lv()
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#2a2640")
	cs.set_corner_radius_all(6)
	cs.set_border_width_all(2)
	cs.border_color = Color("#6a5f9e")
	card.add_theme_stylebox_override("panel", cs)
	pvb.add_child(card)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 4)
	card.add_child(cvb)
	var head_row := HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_theme_constant_override("separation", 6)
	cvb.add_child(head_row)
	var head := Label.new()
	head.text = "勋章：%s（%d级）" % [_sys().get_medal_name(lv), lv]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	head_row.add_child(head)
	var help_btn := Button.new()
	help_btn.text = "i"   # 【改】批次②③④-B3：面板内补充信息入口统一用"i"（"?"只留玩法主标题旁）
	help_btn.custom_minimum_size = Vector2(24, 24)
	help_btn.tooltip_text = "点击查看勋章规则"
	help_btn.pressed.connect(_on_medal_help)
	head_row.add_child(help_btn)
	var effect := Label.new()
	effect.text = "全部商铺赚速 +%d%%" % int(round(_sys().get_medal_shop_pct() * 100.0))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.add_theme_color_override("font_color", Color("#e6c07b"))
	cvb.add_child(effect)
	var need: int = _sys().get_next_medal_need()
	if need < 0:
		var full := Label.new()
		full.text = "已满级"
		full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		full.add_theme_color_override("font_color", Color("#9a93b8"))
		cvb.add_child(full)
	else:
		# 【改】批次②③④-B10：繁荣度门槛统一（当前/需求）格式，保留达到/未达到红绿提示
		c._add_cost_row(cvb, "繁荣度", int(_sys().get_prosperity()), need)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = maxf(1.0, float(need))
		bar.value = minf(float(_sys().get_prosperity()), float(need))
		bar.show_percentage = true
		bar.custom_minimum_size = Vector2(410, 18)
		cvb.add_child(bar)
		var next_effect := Label.new()
		next_effect.text = "下级效果：全部商铺赚速 +%d%%" % int(round(float(lv + 1) * 100.0))
		next_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next_effect.add_theme_color_override("font_color", Color("#7ee787"))
		cvb.add_child(next_effect)
		var up := Button.new()
		up.text = "升级勋章"
		up.custom_minimum_size = Vector2(130, 38)
		up.disabled = not _sys().can_upgrade_medal().get("ok", false)
		up.pressed.connect(_on_medal_upgrade)
		cvb.add_child(up)

func _on_medal_help():
	c._show_stage_hint("妙音坊勋章：繁荣度=应援币总产出/分；全部商铺赚速+100%×等级；升级只校验繁荣度，不消耗繁荣度。")

func _on_medal_upgrade():
	var r: Dictionary = _sys().upgrade_medal()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "暂不可升级")))
		return
	c._show_stage_hint("勋章升级成功")
	c.update_all_ui()
	_refresh()

# ---------- 弹窗：妙音坊加速卡（数量选择；每张=立即获得60分钟三轨收益） ----------
func _show_accel_popup():
	close_popup()
	_popup_kind = "accel"
	var count: int = int(data.items.get("miaoyin_jiasu_ka", 0))
	if count <= 0:
		c._show_stage_hint("没有妙音坊加速卡")
		return
	var popup: PanelContainer = c._create_base_popup("使用妙音坊加速卡", Vector2(430, 300), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var own := Label.new()
	own.text = "拥有加速卡：%d" % count
	own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(own)
	var pair: Dictionary = c._create_slider_spin_pair(vb, count)
	var spin: SpinBox = pair["spin"]
	var hint := Label.new()
	hint.text = "每张立即获得60分钟当前妙音坊三轨收益"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#bdb7d8"))
	vb.add_child(hint)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(82, 36)
	cancel.pressed.connect(close_popup)
	btns.add_child(cancel)
	var ok := Button.new()
	ok.text = "确定"
	ok.custom_minimum_size = Vector2(82, 36)
	ok.pressed.connect(_on_accel_confirm.bind(spin))
	btns.add_child(ok)

func _on_accel_confirm(spin: SpinBox):
	var n: int = int(spin.value)
	var r: Dictionary = data.use_item("miaoyin_jiasu_ka", n)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "使用失败")))
		return
	c._show_stage_hint(str(r.get("msg", "使用成功")))
	c.update_all_ui()
	close_popup()
	_refresh()
