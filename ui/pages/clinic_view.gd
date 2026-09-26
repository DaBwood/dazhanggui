# ============================================================
# 医馆玩法全屏页（商铺地图 医馆「▶」入口，层级：ClinicPage z35，同客栈/钱庄页惯例）
# 2026-09-15 队列化改造（用户拍板）：
#   主页 = 接诊(转1人入队) + 一键接诊(全部转入,纯改数字不卡) + 接诊队列状态 + 收益罐(仅医术) + 三入口
#   治疗由秒刷定时器以【时间盒 4ms/0.05s】批处理（约5000+/秒，帧压力恒定）；队列进存档，离线不假结算
#   科室 = 卡片网格：初始仅药房已建，其余先【新增】(耗图纸)再升级；点卡片弹详情
#   病症 = 卡片网格只显名字，顶部按店铺类目分列加成；点卡片弹详情
#          （经过科室/收益预览/该病症独立评分池余额/加成/升级）
# 重建刷新模式：操作后整页重建；0.05s Timer 推进治疗批次+刷文本（不重建保流畅）
# ============================================================
class_name ClinicView
extends BaseView   # 【改】公共层下沉 ui/base_view.gd（2026-09-18 架构重构批次⑧）

# c/data 引用由基类持有，此处不再声明

var _tab: String = "main"        # 当前视图 main/patient/dept/illness
var _timer: Timer = null         # 批处理/秒刷定时器（0.05s）
var _count_lbl: Label = null     # 病人数量文本
var _cd_lbl: Label = null        # 恢复倒计时文本
var _jar_lbl: Label = null       # 收益罐文本
var _tq_lbl: Label = null        # 接诊队列状态文本
# _popup_kind/_popup_id 由基类 BaseView 持有（2026-09-18 架构重构批次⑧），此处不再声明

func _init(p_c):
	super(p_c)   # 【改】基类注入 c/data（2026-09-18 架构重构批次⑧）
	_page_name = "ClinicPage"
	_popup_node_name = "ClinicPopup"

func _sys() -> ClinicSystem:
	return data.clinic_system

# ---------- 页面开关 ----------
func show_clinic_view():
	show_view()

func hide_clinic_view():
	hide_view()

# 【新增】批次②③④-B2：玩法说明弹窗（ClinicRulePopup）是独立节点名，基类只认 _popup_node_name，需显式清理
func show_view():
	_close_node("ClinicRulePopup")
	super()

func hide_view():
	_close_node("ClinicRulePopup")
	super()

# 【改】批处理定时器挂在基类建页后的钩子（原 show_clinic_view 尾部，2026-09-18 批次⑧）；
# Timer 挂在 page 上，随关页 queue_free 自动销毁，hide 无需手动停
func _after_build(page: Panel):
	_timer = Timer.new()
	_timer.wait_time = 0.05
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	page.add_child(_timer)

func _on_tick():
	# 接诊队列批处理（时间盒 4ms，治完自然停；队列在页面外也随存档保留，重开页面继续治）
	if _sys().get_treat_queue() > 0:
		_sys().process_treat_queue(4)
	if _count_lbl:
		_count_lbl.text = "病人：%d / %d" % [_sys().get_patient_count(), _sys().get_patient_cap()]
	if _cd_lbl:
		_cd_lbl.text = _cd_text()
	if _jar_lbl:
		_jar_lbl.text = _jar_text()
	if _tq_lbl:
		_tq_lbl.text = _tq_text()

func _cd_text() -> String:
	var sec := _sys().get_next_patient_seconds()
	if sec <= 0:
		return "队列已满" if _sys().get_patient_count() >= _sys().get_patient_cap() else "下个病人即将恢复"
	return "下个病人：%d分%02d秒" % [int(sec / 60.0), sec % 60]

func _jar_text() -> String:
	return "收益罐：医术 %s" % c.format_number(_sys().get_jar_total()["yishu"])

func _tq_text() -> String:
	var n := _sys().get_treat_queue()
	if n > 0:
		return "接诊队列：%d（治疗中…）" % n
	return "接诊队列：0"

# ---------- 页面构建 ----------
func _build(page: Panel):
	var vb := VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
	# 顶栏：返回 + 标题（子页返回=回主页，主页返回=退出医馆）
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 48)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(90, 42)
	back_btn.pressed.connect(_on_back)
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "医馆" if _tab == "main" else ("医馆 · 病人" if _tab == "patient" else ("医馆 · 科室" if _tab == "dept" else "医馆 · 病症"))
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	# 【新增】批次②③④-B2：玩法说明入口"?"（只在玩法主标题旁，说明流程/规则/后台计算）
	var rule_btn := Button.new()
	rule_btn.text = "?"
	rule_btn.custom_minimum_size = Vector2(30, 30)
	rule_btn.add_theme_font_size_override("font_size", 16)
	rule_btn.pressed.connect(_show_rule_popup)
	top.add_child(rule_btn)
	# 资源行：医术 / 科室图纸（评分已按病症独立，顶部不再显示全局评分）
	var res := Label.new()
	res.text = "医术 %s　图纸 %d" % [
		c.format_number(_sys().yishu), int(data.items.get("ke_shi_tu_zhi", 0))]
	res.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(res)
	# 内容体
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	match _tab:
		"patient":
			_fill_patient(body)
		"dept":
			_fill_dept(body)
		"illness":
			_fill_illness(body)
		_:
			_fill_main(body)

func _on_back():
	if _tab == "main":
		hide_clinic_view()
	else:
		_switch_tab("main")

func _switch_tab(t: String):
	_tab = t
	_close_node("ClinicPage")
	show_clinic_view()

# 操作后统一刷新：重建页面；仅当弹窗节点真实存在（未按确定关闭）才重建弹窗
func _refresh():
	_close_node("ClinicPage")
	show_clinic_view()
	if _popup_kind != "" and c.get_node_or_null("ClinicPopup") != null:
		_close_node("ClinicPopup")
		if _popup_kind == "dept":
			_show_dept_popup(_popup_id)
		else:
			_show_illness_popup(_popup_id)

# 【新增】批次②③④-B2：医馆玩法说明弹窗（只从主标题旁"?"进入；长说明不进画面）
func _show_rule_popup():
	_close_node("ClinicRulePopup")
	var popup: PanelContainer = c._create_base_popup("医馆说明", Vector2(380, 300))
	popup.name = "ClinicRulePopup"
	popup.get_meta("popup_mask").z_index = 39
	popup.z_index = 40
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child
	var vb: VBoxContainer = popup.get_child(0)
	for line in [
		"病人随时间恢复；接诊后进入队列，由后台批处理治疗结算。",
		"治疗产出医术与评分：医术进收益罐，评分进入对应病症的独立池。",
		"科室先消耗图纸【新增】再升级；病症升级消耗自身评分池。",
	]:
		var body := Label.new()
		body.text = line
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(body)

# ---------- 主页：接诊队列 + 收益罐 + 三入口 ----------
func _fill_main(body: VBoxContainer):
	# 收益罐（医术）
	var jar_row := HBoxContainer.new()
	jar_row.add_theme_constant_override("separation", 8)
	body.add_child(jar_row)
	_jar_lbl = Label.new()
	_jar_lbl.text = _jar_text()
	_jar_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jar_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jar_row.add_child(_jar_lbl)
	var collect_btn := Button.new()
	collect_btn.text = "领取"
	collect_btn.custom_minimum_size = Vector2(90, 36)
	collect_btn.disabled = not _sys().has_jar()
	collect_btn.pressed.connect(_on_collect)
	jar_row.add_child(collect_btn)
	# 病人区：计数 + 加号（病人手册，仅限此处）
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 6)
	body.add_child(count_row)
	_count_lbl = Label.new()
	_count_lbl.text = "病人：%d / %d" % [_sys().get_patient_count(), _sys().get_patient_cap()]
	_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(_count_lbl)
	var add_btn := Button.new()
	add_btn.text = "＋"
	add_btn.custom_minimum_size = Vector2(40, 32)
	add_btn.tooltip_text = "使用【病人手册】+3 病人"
	add_btn.pressed.connect(_on_add_patient)
	count_row.add_child(add_btn)
	_cd_lbl = Label.new()
	_cd_lbl.text = _cd_text()
	_cd_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
	body.add_child(_cd_lbl)
	# 接诊 / 一键接诊：只做搬运转入接诊队列，纯改数字永不卡
	# 按钮只写功能名，不展示"转入队列"等内部设定说明（用户要求对玩家隐藏实现细节）
	var has_p: bool = _sys().get_patient_count() > 0
	var treat_btn := Button.new()
	treat_btn.text = "接诊"
	treat_btn.custom_minimum_size = Vector2(0, 46)
	treat_btn.disabled = not has_p
	treat_btn.pressed.connect(_on_treat)
	body.add_child(treat_btn)
	var treat_all_btn := Button.new()
	treat_all_btn.text = "一键接诊"
	treat_all_btn.custom_minimum_size = Vector2(0, 40)
	treat_all_btn.disabled = not has_p
	treat_all_btn.pressed.connect(_on_treat_all)
	body.add_child(treat_all_btn)
	# 接诊队列状态（治疗由定时器后台批处理推进）
	_tq_lbl = Label.new()
	_tq_lbl.text = _tq_text()
	_tq_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	body.add_child(_tq_lbl)
	# 三入口按钮
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for t in [["patient", "病人", _sys().has_unlockable_patient()],
			["dept", "科室", _sys().has_upgradeable_dept()],
			["illness", "病症", _sys().has_upgradeable_illness()]]:
		# 【新增】2026-09-16 三入口红点（参考药铺 wrap_node 模式：外套 Control 显式尺寸，红点 IGNORE 不拦截触摸）
		var wrap_node := Control.new()
		wrap_node.custom_minimum_size = Vector2(170, 56)
		grid.add_child(wrap_node)
		var b := Button.new()
		b.text = t[1]
		b.position = Vector2.ZERO
		b.size = Vector2(170, 56)
		b.pressed.connect(func(): _switch_tab(t[0]))
		wrap_node.add_child(b)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#e74c3c"))
		dot.add_theme_font_size_override("font_size", 16)
		dot.position = Vector2(148, -6)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = t[2]
		wrap_node.add_child(dot)

# 加号：弹出数量选择器，批量消耗病人手册恢复病人（不受队列上限限制，背包不开放）
func _on_add_patient():
	var manual: String = data._clinic_configs.get("settings", {}).get("manual_item", "patient_manual")
	var owned: int = int(data.items.get(manual, 0))
	if owned <= 0:
		c._show_stage_hint("没有【病人手册】")
		return
	_close_node("ClinicPopup")
	var give: int = int(data._clinic_configs.get("settings", {}).get("manual_give", 3))
	var popup: PanelContainer = c._create_base_popup("使用病人手册", Vector2(400, 240), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
	popup.name = "ClinicPopup"
	popup.z_index = 40   # 盖过 ClinicPage(z35)，同 inn/bank 弹窗惯例
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var info := Label.new()
	info.text = "拥有 %d 本，每本 +%d 病人" % [owned, give]
	vb.add_child(info)
	# 数量选择：滑动条 + 输入框联动（项目惯例，同 friend_page 赠送/inn 物品）
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vb.add_child(hbox)
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = owned
	slider.value = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(140, 24)
	hbox.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = owned
	spin.value = 1
	hbox.add_child(spin)
	slider.value_changed.connect(spin.set_value)
	spin.value_changed.connect(slider.set_value)
	# 确认/取消按钮（项目无 confirm_cancel 工厂，按 friend_page 惯例手写）
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(90, 34)
	cancel_btn.pressed.connect(func(): _close_node("ClinicPopup"))
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(90, 34)
	ok_btn.pressed.connect(func():
		var n: int = int(spin.value)
		data.items[manual] = int(data.items.get(manual, 0)) - n
		_sys().add_patients(n * give)
		_close_node("ClinicPopup")
		c._show_stage_hint("病人 +%d" % (n * give))
		_refresh())
	btn_row.add_child(ok_btn)

func _on_collect():
	var r := _sys().collect_jar()
	c._show_stage_hint("领取：医术 +%s" % c.format_number(r["yishu"]))
	_refresh()

# 接诊：1 人转入接诊队列（治疗由定时器批处理）
func _on_treat():
	var r := _sys().admit_one()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("已转入接诊队列，治疗中…")
	_refresh()

# 一键接诊：全部转入接诊队列（纯改数字，不卡）
func _on_treat_all():
	var r := _sys().admit_all()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("已将 %d 人转入接诊队列，治疗中…" % int(r.get("count", 0)))
	_refresh()

# ---------- 子页：病人 ----------
func _fill_patient(body: VBoxContainer):
	var head := Label.new()
	head.text = "病人解锁（医术 %s）" % c.format_number(_sys().yishu)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	body.add_child(head)
	for p in _sys().get_patient_unlock_info():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		body.add_child(row)
		# 【改】2026-09-16 手动解锁制：入池以解锁表为准；医术判定只决定"能否点解锁"
		var pid := str(p.get("id", ""))
		var is_unlocked: bool = _sys().is_patient_unlocked(pid)
		var yishu_ok: bool = _sys().yishu >= int(p.get("need_yishu", 0))
		var nm := Label.new()
		nm.text = str(p.get("name", ""))
		nm.custom_minimum_size = Vector2(110, 0)
		if not is_unlocked:
			nm.add_theme_color_override("font_color", Color("#666080"))
		row.add_child(nm)
		var info: Label = null   # 【改】批次②③④-B10：未解锁门槛不再整行着色，改走统一消耗/门槛行
		if is_unlocked:
			info = Label.new()
			info.text = "加成 +%d%%" % int(float(p.get("bonus", 0)) * 100)
		else:
			var unlock_row: HBoxContainer = c._add_cost_row(row, "需医术", int(_sys().yishu), int(p.get("need_yishu", 0)))
			unlock_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 保持右侧解锁按钮贴行尾
		if info != null:
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
		# 【新增】2026-09-16 手动解锁（无消耗）：医术达阈值未解锁的显示【解锁】
		if not is_unlocked and yishu_ok:
			var ub := Button.new()
			ub.text = "解锁"
			ub.custom_minimum_size = Vector2(64, 28)
			ub.pressed.connect(_on_unlock_patient.bind(pid))
			row.add_child(ub)

# 【新增】2026-09-16 解锁病人：解锁后进入接诊随机池
func _on_unlock_patient(pid: String):
	var r: Dictionary = _sys().unlock_patient(pid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

# 【新增】2026-09-16 病症一键升级：全部升完后刷新页面+全局飘字（类目赚速变化）
func _on_upgrade_all_illness():
	var n: int = _sys().upgrade_all_illnesses()
	if n <= 0:
		c._show_stage_hint("暂无可升级病症")
		return
	_refresh()
	c.update_all_ui()

# ---------- 子页：科室（卡片网格，先新增再升级） ----------
func _fill_dept(body: VBoxContainer):
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for dept_id in data._clinic_configs.get("departments", {}):
		var d: Dictionary = data._clinic_configs["departments"][dept_id]
		# 【新增】2026-09-16 可新增/可升级科室红点：外套 Control 显式尺寸
		var wrap_node := Control.new()
		wrap_node.custom_minimum_size = Vector2(260, 64)
		grid.add_child(wrap_node)
		var b := Button.new()
		if _sys().is_dept_unlocked(dept_id):
			b.text = "【%s】\nLv.%d" % [d.get("name", dept_id), _sys().get_dept_level(dept_id)]
		else:
			b.text = "【%s】\n新增（图纸 %d）" % [d.get("name", dept_id), _sys().get_dept_unlock_cost(dept_id)]
			b.add_theme_color_override("font_color", Color("#8f88ad"))
		b.position = Vector2.ZERO
		b.size = Vector2(260, 64)
		var did: String = dept_id
		b.pressed.connect(func(): _show_dept_popup(did))
		wrap_node.add_child(b)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#e74c3c"))
		dot.add_theme_font_size_override("font_size", 16)
		dot.position = Vector2(236, -6)   # 260宽按钮右上角
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = _sys().can_unlock_dept(dept_id).get("ok", false) or _sys().can_upgrade_dept(dept_id).get("ok", false)
		wrap_node.add_child(dot)

func _show_dept_popup(dept_id: String):
	_popup_kind = "dept"
	_popup_id = dept_id
	_close_node("ClinicPopup")
	var d: Dictionary = data._clinic_configs.get("departments", {}).get(dept_id, {})
	var popup: PanelContainer = c._create_base_popup(str(d.get("name", dept_id)), Vector2(420, 300))
	popup.name = "ClinicPopup"
	popup.z_index = 40   # 盖过 ClinicPage(z35)，同 inn/bank 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child（同 inn/bank 惯例）
	var vb: VBoxContainer = popup.get_child(0)
	if _sys().is_dept_unlocked(dept_id):
		# 已建科室：属性 + 下级解锁 + 升级
		var lv := _sys().get_dept_level(dept_id)
		var info := Label.new()
		info.text = "Lv.%d　医术 %d　评分 %d" % [lv, _sys().get_dept_yishu(dept_id), _sys().get_dept_score(dept_id)]
		vb.add_child(info)
		var next_txt := "病症已全部解锁"
		for iid in d.get("illnesses", {}):
			var ic: Dictionary = d["illnesses"][iid]
			if int(ic.get("unlock_level", 1)) > lv:
				next_txt = "下级解锁：Lv.%d【%s】" % [int(ic.get("unlock_level", 1)), ic.get("name", "")]
				break
		var next_lbl := Label.new()
		next_lbl.text = next_txt
		next_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
		vb.add_child(next_lbl)
		# 【改】批次②③④-B10：升级消耗统一（拥有/消耗），道具名默认色、数字红绿
		c._add_cost_row(vb, "升级消耗：图纸", int(data.items.get("ke_shi_tu_zhi", 0)), _sys().get_dept_upgrade_cost(dept_id))
		var btn := Button.new()
		btn.text = "升级"
		btn.disabled = not _sys().can_upgrade_dept(dept_id).get("ok", false)
		btn.pressed.connect(func(): _on_dept_upgrade(dept_id))
		vb.add_child(btn)
	else:
		# 【改】批次②③④-B10：新增消耗统一（拥有/消耗），道具名默认色、数字红绿
		c._add_cost_row(vb, "新增消耗：图纸", int(data.items.get("ke_shi_tu_zhi", 0)), _sys().get_dept_unlock_cost(dept_id))
		var btn := Button.new()
		btn.text = "新增科室"
		btn.disabled = not _sys().can_unlock_dept(dept_id).get("ok", false)
		btn.pressed.connect(func(): _on_dept_unlock(dept_id))
		vb.add_child(btn)

func _on_dept_unlock(dept_id: String):
	var r := _sys().unlock_dept(dept_id)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

func _on_dept_upgrade(dept_id: String):
	var r := _sys().upgrade_dept(dept_id)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

# ---------- 子页：病症（卡片网格，顶部类目加成，弹详情） ----------
func _fill_illness(body: VBoxContainer):
	# 按店铺类目分列显示加成（每个病症只加其科室对应的类目，此处仅为分项汇总展示）
	var head := Label.new()
	var parts := []
	for cat in ["士", "农", "工", "商", "侠"]:
		# 【改】2026-09-16 0.05 浮点累加后×100 可能是 1264.999…，int() 截断吃掉 1（应显 1265）→ round 后取整
		parts.append("%s +%d%%" % [cat, int(round(_sys().get_category_bonus(cat) * 100))])
	head.text = "店铺赚速加成：%s" % "　".join(parts)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	body.add_child(head)
	# 【新增】2026-09-16 病症一键升级：全部可升级病症一键升到评分不足
	var all_btn := Button.new()
	all_btn.text = "一键升级"
	all_btn.custom_minimum_size = Vector2(104, 30)
	all_btn.disabled = not _sys().has_upgradeable_illness()
	all_btn.pressed.connect(_on_upgrade_all_illness)
	body.add_child(all_btn)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for dept_id in data._clinic_configs.get("departments", {}):
		var d: Dictionary = data._clinic_configs["departments"][dept_id]
		for iid in d.get("illnesses", {}):
			var ic: Dictionary = d["illnesses"][iid]
			# 【新增】2026-09-16 可升级病症红点（仅"已解锁且评分够升级"的）：外套 Control 显式尺寸
			var wrap_node := Control.new()
			wrap_node.custom_minimum_size = Vector2(170, 52)
			grid.add_child(wrap_node)
			var b := Button.new()
			b.text = str(ic.get("name", iid))
			if not _sys().is_illness_unlocked(iid):
				# 【改】明确写"哪个科室多少级解锁"，避免玩家误解为病症等级；不用全角括号（部分环境不渲染）
				b.text = "%s\n%s %d级解锁" % [str(ic.get("name", iid)), d.get("name", ""), int(ic.get("unlock_level", 1))]
				b.add_theme_color_override("font_color", Color("#666080"))
			b.position = Vector2.ZERO
			b.size = Vector2(170, 52)
			var iid_c: String = iid
			b.pressed.connect(func(): _show_illness_popup(iid_c))
			wrap_node.add_child(b)
			var dot := Label.new()
			dot.text = "●"
			dot.add_theme_color_override("font_color", Color("#e74c3c"))
			dot.add_theme_font_size_override("font_size", 15)
			dot.position = Vector2(148, -6)   # 170宽按钮右上角
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.visible = _sys().is_illness_unlocked(iid) and _sys().can_upgrade_illness(iid).get("ok", false)
			wrap_node.add_child(dot)

func _show_illness_popup(illness_id: String):
	_popup_kind = "illness"
	_popup_id = illness_id
	_close_node("ClinicPopup")
	var info := _sys().get_illness_cfg(illness_id)
	if info.is_empty():
		return
	var ic: Dictionary = info["cfg"]
	var home: Dictionary = data._clinic_configs.get("departments", {}).get(str(info.get("dept", "")), {})
	var popup: PanelContainer = c._create_base_popup(str(ic.get("name", illness_id)), Vector2(420, 340))
	popup.name = "ClinicPopup"
	popup.z_index = 40   # 盖过 ClinicPage(z35)，同 inn/bank 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child（同 inn/bank 惯例）
	var vb: VBoxContainer = popup.get_child(0)
	if not _sys().is_illness_unlocked(illness_id):
		var lock := Label.new()
		lock.text = "【%s】科室 Lv.%d 解锁" % [home.get("name", ""), int(ic.get("unlock_level", 1))]
		vb.add_child(lock)
		return
	# 经过科室
	var chain_names := []
	for dept_id in _sys().get_illness_departments(illness_id):
		chain_names.append(str(data._clinic_configs.get("departments", {}).get(str(dept_id), {}).get("name", dept_id)))
	var chain := Label.new()
	chain.text = "经过科室：%s" % "、".join(chain_names)
	chain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(chain)
	# 收益预览（不含病人加成）
	var preview := _sys().get_illness_preview(illness_id)
	var gain := Label.new()
	gain.text = "诊治可获得：医术 %d　评分 %d" % [int(preview["yishu"]), int(_sys().get_illness_preview_boosted(illness_id)["score"])]
	vb.add_child(gain)
	# 当前加成
	var pct_lbl := Label.new()
	pct_lbl.text = "店铺赚速加成：+%d%%（%s类店铺）　图鉴 Lv.%d" % [
		int(_sys().get_illness_pct(illness_id) * 100), home.get("category", ""), _sys().get_illness_level(illness_id)]
	pct_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(pct_lbl)
	# 【改】批次②③④-B10：病症评分升级消耗统一（拥有/消耗），数字红绿
	c._add_cost_row(vb, "升级消耗：该病症评分", int(_sys().get_illness_score(illness_id)), _sys().get_illness_upgrade_cost(illness_id))
	# 升级按钮（扣该病症自己的评分池）
	var btn := Button.new()
	btn.text = "升级"
	btn.disabled = not _sys().can_upgrade_illness(illness_id).get("ok", false)
	btn.pressed.connect(func(): _on_illness_upgrade(illness_id))
	vb.add_child(btn)

func _on_illness_upgrade(illness_id: String):
	var r := _sys().upgrade_illness(illness_id)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()
