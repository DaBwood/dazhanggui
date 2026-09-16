# ============================================================
# 酒肆玩法全屏页（商铺地图 酒肆店铺「▶」入口，层级：TavernPage z35，同医馆/客栈页惯例）
# 2026-09-16 批3完整版（覆盖批2）：
#   主页 = 代码配色背景（深酒红棕+酒字水印，后续有"红尘酒楼"素材可直接换底）
#          + 右上浮层（招牌/知名度/银条）+ 收益罐(领银条) + 叫号条(x/50+倒计时+【+】)
#          + 叫号/一键叫号（纯改数字转接待队列）+ 接待队列状态 + 餐饮/娱乐双入口（带红点）
#   设施区 = 项目页签（餐饮6项目/娱乐5项目）+ 同步升级 + 设施卡片网格（红点：可升级/可解锁）
#   设施弹窗 = 图+名+等级+flavor + 三属性当前→下级 + 消耗 + 升级/同步升级勾选 + 左右切设施
#   信息弹窗 = 招牌改名(免费限8字)/等级升级(知名度达标免费升)/接待收益/百业/才艺/知名度进度
# 重建刷新模式：操作后整页重建；0.05s Timer 推进接待批次+刷文本（不重建保流畅）
# ============================================================
class_name TavernView
extends RefCounted

var c      # game_controller 根脚本引用
var data: GameData   # 数据中枢（显式标注 GameData：让中枢字段被静态引用，消 UNUSED 提示，同 inn/clinic 先例）

var _tab: String = "main"              # 当前视图 main/餐饮/娱乐
var _proj: Dictionary = {"餐饮": "", "娱乐": ""}   # 各区域当前选中项目（页签状态，切区保留）
var _timer: Timer = null               # 批处理/秒刷定时器（0.05s）
var _jh_lbl: Label = null              # 叫号计数文本（主页）
var _cd_lbl: Label = null              # 叫号恢复倒计时文本（主页）
var _jar_lbl: Label = null             # 收益罐文本（主页）
var _tq_lbl: Label = null              # 接待队列状态文本（主页）
var _popup_kind: String = ""           # 当前打开的弹窗类别 info/facility
var _popup_id: String = ""             # 当前弹窗对应的设施 id（facility 用）

func _init(p_c):
	c = p_c
	data = p_c.data

func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

func _sys() -> TavernSystem:
	return data.tavern_system

# ---------- 页面开关 ----------
func show_tavern_view():
	_close_node("TavernPage")
	_close_node("TavernPopup")
	_popup_kind = ""
	_popup_id = ""
	_build_page()

# 仅重建页面不关弹窗：连升/连解锁时设施弹窗常驻原位刷新（_refresh 用）；进出酒肆才全关
func _build_page():
	var page := Panel.new()
	page.name = "TavernPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#33150f")   # 深酒红棕底（无素材期的代码配色，后续丢"红尘酒楼"图换底）
	page.add_theme_stylebox_override("panel", bg)
	c.add_child(page)
	_build(page)
	# 批处理定时器：0.05s 一次，每次最多跑 4ms（约5000+客/秒，帧压力恒定）
	_timer = Timer.new()
	_timer.wait_time = 0.05
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	page.add_child(_timer)

func hide_tavern_view():
	_tab = "main"   # 下次进入回到主页（同 clinic 进出复位惯例）
	_close_node("TavernPage")
	_close_node("TavernPopup")

func _switch_tab(t: String):
	_tab = t
	_popup_kind = ""
	_popup_id = ""
	_close_node("TavernPopup")
	_close_node("TavernPage")
	show_tavern_view()

func _on_tick():
	# 接待队列批处理（时间盒 4ms，接待完自然停；队列随存档保留，重开页面接着接待）
	if _sys().get_serve_queue() > 0:
		_sys().process_serve_queue(4)
	if _jh_lbl:
		_jh_lbl.text = _jh_text()
	if _cd_lbl:
		_cd_lbl.text = _cd_text()
	if _jar_lbl:
		_jar_lbl.text = _jar_text()
	if _tq_lbl:
		_tq_lbl.text = _tq_text()

func _jh_text() -> String:
	return "叫号：%d / %d" % [_sys().get_jiaohao(), _sys().get_jiaohao_cap()]

func _cd_text() -> String:
	var sec := _sys().get_next_jiaohao_seconds()
	if sec <= 0:
		return "叫号已满" if _sys().get_jiaohao() >= _sys().get_jiaohao_cap() else "恢复中…"
	return "叫号恢复 %02d:%02d:%02d" % [int(sec / 3600.0), int(sec / 60.0) % 60, sec % 60]

func _jar_text() -> String:
	return "收益罐：银条 %s" % c.format_number(_sys().get_jar())

func _tq_text() -> String:
	var n := _sys().get_serve_queue()
	if n > 0:
		return "接待队列：%d（接待中…）" % n
	return "接待队列：0"

# ---------- 页面构建 ----------
func _build(page: Panel):
	# 装饰：酒字水印（鼠标穿透，不挡操作；换背景素材时可删）
	var mark := Label.new()
	mark.text = "酒"
	mark.add_theme_font_size_override("font_size", 200)
	mark.add_theme_color_override("font_color", Color(0.85, 0.62, 0.28, 0.10))
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(mark)
	# 右上浮层：招牌 / 知名度 / 银条（锚定右上，鼠标穿透）
	var overlay := MarginContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	overlay.add_theme_constant_override("margin_top", 56)
	overlay.add_theme_constant_override("margin_right", 16)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(overlay)
	var ov_vb := VBoxContainer.new()
	ov_vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	overlay.add_child(ov_vb)
	var sign_lbl := Label.new()
	sign_lbl.text = "【%s】 Lv.%d" % [_sys().get_sign_name(), _sys().get_level()]
	sign_lbl.add_theme_font_size_override("font_size", 20)
	sign_lbl.add_theme_color_override("font_color", Color("#f0d9a8"))
	sign_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ov_vb.add_child(sign_lbl)
	var fame_lbl := Label.new()
	fame_lbl.text = "知名度：%s" % c.format_number(_sys().get_fame_total())
	fame_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	fame_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ov_vb.add_child(fame_lbl)
	var yt_lbl := Label.new()
	yt_lbl.text = "银条：%s" % c.format_number(_sys().get_yintiao())
	yt_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	yt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ov_vb.add_child(yt_lbl)
	# 主体：顶栏 + 可滚内容
	var vb := VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
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
	title.text = "酒肆" if _tab == "main" else "酒肆 · %s" % _tab
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	var info_btn := Button.new()
	info_btn.text = "酒肆信息"
	info_btn.custom_minimum_size = Vector2(104, 40)
	info_btn.pressed.connect(_show_info_popup)
	top.add_child(info_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	if _tab == "main":
		_fill_main(body)
	else:
		_fill_area(body, _tab)

func _on_back():
	if _tab == "main":
		hide_tavern_view()
	else:
		_switch_tab("main")

# 操作后统一刷新：只重建页面不关弹窗；弹窗在则按类别原位重建（连升/连解锁不用反复开关）
func _refresh():
	var had_popup: bool = c.get_node_or_null("TavernPopup") != null
	_close_node("TavernPage")
	_build_page()
	if not had_popup:
		return
	if _popup_kind == "info":
		_show_info_popup()
	elif _popup_kind == "facility" and _popup_id != "":
		_show_facility_popup(_popup_id)

# ---------- 主页：收益罐 + 叫号条 + 双入口 ----------
func _fill_main(body: VBoxContainer):
	# 收益罐（银条）
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
	# 叫号条：计数 + 加号（佳酿道具面板，仅限此处）
	var jh_row := HBoxContainer.new()
	jh_row.add_theme_constant_override("separation", 6)
	body.add_child(jh_row)
	_jh_lbl = Label.new()
	_jh_lbl.text = _jh_text()
	_jh_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jh_row.add_child(_jh_lbl)
	var add_btn := Button.new()
	add_btn.text = "＋"
	add_btn.custom_minimum_size = Vector2(40, 32)
	add_btn.tooltip_text = "使用【佳酿】+2 叫号"
	add_btn.pressed.connect(_on_add_jiaohao)
	jh_row.add_child(add_btn)
	_cd_lbl = Label.new()
	_cd_lbl.text = _cd_text()
	_cd_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
	body.add_child(_cd_lbl)
	# 叫号 / 一键叫号：只做搬运纯改数字永不卡，接待由定时器批处理
	# 按钮只写功能名，不展示"转入队列"等内部设定说明（对玩家隐藏实现细节）
	var has_jh: bool = _sys().get_jiaohao() > 0
	var call_btn := Button.new()
	call_btn.text = "叫号"
	call_btn.custom_minimum_size = Vector2(0, 46)
	call_btn.disabled = not has_jh
	call_btn.pressed.connect(_on_call_one)
	body.add_child(call_btn)
	var call_all_btn := Button.new()
	call_all_btn.text = "一键叫号"
	call_all_btn.custom_minimum_size = Vector2(0, 40)
	call_all_btn.disabled = not has_jh
	call_all_btn.pressed.connect(_on_call_all)
	body.add_child(call_all_btn)
	# 接待队列状态（接待由定时器后台批处理推进）
	_tq_lbl = Label.new()
	_tq_lbl.text = _tq_text()
	_tq_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	body.add_child(_tq_lbl)
	# 餐饮/娱乐双入口（带红点）
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for t in [["餐饮", "餐饮", _area_has_hint("餐饮")],
			["娱乐", "娱乐", _area_has_hint("娱乐")]]:
		# 入口红点（参考药铺 wrap_node 模式：外套 Control 显式尺寸，红点 IGNORE 不拦截触摸）
		var wrap_node := Control.new()
		wrap_node.custom_minimum_size = Vector2(260, 64)
		grid.add_child(wrap_node)
		var b := Button.new()
		b.text = "【%s】设施" % t[1]
		b.position = Vector2.ZERO
		b.size = Vector2(260, 64)
		var area: String = t[0]
		b.pressed.connect(func(): _switch_tab(area))
		wrap_node.add_child(b)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#e74c3c"))
		dot.add_theme_font_size_override("font_size", 16)
		dot.position = Vector2(236, -6)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = t[2]
		wrap_node.add_child(dot)

# 区域红点口径：该区域存在"可升级或可解锁"的设施即亮
func _area_has_hint(area: String) -> bool:
	for f in _sys().get_facility_list():
		if str(f.get("area", "")) != area:
			continue
		var fid := str(f.get("id", ""))
		if _sys().can_upgrade_facility(fid).get("ok", false) or _sys().can_unlock_facility(fid).get("ok", false):
			return true
	return false

# ---------- 设施区：项目页签 + 同步升级 + 设施卡片网格 ----------
func _fill_area(body: VBoxContainer, area: String):
	var projects: Array = _sys().get_projects(area)
	if projects.is_empty():
		return
	# 页签行：默认选中第一个（或保留上次选择）
	var cur: String = str(_proj.get(area, ""))
	if not projects.has(cur):
		cur = str(projects[0])
		_proj[area] = cur
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	body.add_child(tabs)
	for p in projects:
		var pb := Button.new()
		pb.text = str(p)
		pb.custom_minimum_size = Vector2(96, 34)
		if str(p) == cur:
			pb.add_theme_color_override("font_color", Color("#ffd700"))   # 选中页签金色高亮
		var proj_name: String = str(p)
		pb.pressed.connect(func(): _on_pick_project(area, proj_name))
		tabs.add_child(pb)
	# 同步升级行（同项目全部已解锁设施各+1级；银条不足者自动跳过）
	var sync_row := HBoxContainer.new()
	sync_row.add_theme_constant_override("separation", 8)
	body.add_child(sync_row)
	var sync_cost := 0
	for f in _sys().get_project_facilities(cur):
		var fid := str(f.get("id", ""))
		if _sys().can_upgrade_facility(fid).get("ok", false):
			sync_cost += _sys().get_upgrade_cost(fid)
	var sync_btn := Button.new()
	sync_btn.text = "同步升级（银条 %s）" % c.format_number(sync_cost)
	sync_btn.custom_minimum_size = Vector2(220, 36)
	sync_btn.disabled = sync_cost <= 0
	var proj_c: String = cur
	sync_btn.pressed.connect(func(): _on_sync_upgrade(proj_c))
	sync_row.add_child(sync_btn)
	# 设施卡片网格（2列：点击弹详情，红点=可升级或可解锁）
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for f in _sys().get_project_facilities(cur):
		var fid := str(f.get("id", ""))
		var fname := str(f.get("name", fid))
		var wrap_node := Control.new()
		wrap_node.custom_minimum_size = Vector2(260, 64)
		grid.add_child(wrap_node)
		var b := Button.new()
		if _sys().is_facility_unlocked(fid):
			b.text = "【%s】\nLv.%d　知名度 %d　银条 %d" % [fname, _sys().get_facility_level(fid),
				_sys().get_facility_fame(f), _sys().get_facility_income(f)]
		else:
			b.text = "【%s】\n知名度 %s 解锁" % [fname, c.format_number(_sys().get_unlock_fame(f))]
			b.add_theme_color_override("font_color", Color("#8f88ad"))
		b.position = Vector2.ZERO
		b.size = Vector2(260, 64)
		var fid_c: String = fid
		b.pressed.connect(func(): _show_facility_popup(fid_c))
		wrap_node.add_child(b)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#e74c3c"))
		dot.add_theme_font_size_override("font_size", 16)
		dot.position = Vector2(236, -6)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = _sys().can_upgrade_facility(fid).get("ok", false) or _sys().can_unlock_facility(fid).get("ok", false)
		wrap_node.add_child(dot)

func _on_pick_project(area: String, proj: String):
	_proj[area] = proj
	_popup_kind = ""
	_popup_id = ""
	_close_node("TavernPopup")
	_refresh()

func _on_sync_upgrade(proj: String):
	var r := _sys().upgrade_project(proj)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("同步升级：%d 个设施各升 1 级" % int(r.get("count", 0)))
	_refresh()

# ---------- 设施弹窗：三属性当前→下级 + 升级/同步升级勾选 + 左右切设施 ----------
func _show_facility_popup(fid: String):
	_popup_kind = "facility"
	_popup_id = fid
	_close_node("TavernPopup")
	var fcfg := _sys().get_facility_cfg(fid)
	if fcfg.is_empty():
		return
	var fname := str(fcfg.get("name", fid))
	var popup: PanelContainer = c._create_base_popup("设施", Vector2(440, 500))
	popup.name = "TavernPopup"
	popup.z_index = 40   # 盖过 TavernPage(z35)，同 inn/bank 弹窗惯例
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	# 头部：左切换 | 名称+等级+类别 | 右切换（同项目内循环）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(head)
	var sib_ids := []
	for sf in _sys().get_project_facilities(str(fcfg.get("project", ""))):
		sib_ids.append(str(sf.get("id", "")))
	var idx: int = sib_ids.find(fid)
	var prev_btn := Button.new()
	prev_btn.text = "◀"
	prev_btn.custom_minimum_size = Vector2(40, 32)
	prev_btn.disabled = sib_ids.size() <= 1
	if idx >= 0:
		var prev_id: String = str(sib_ids[(idx - 1 + sib_ids.size()) % sib_ids.size()])
		prev_btn.pressed.connect(func(): _show_facility_popup(prev_id))
	head.add_child(prev_btn)
	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _sys().is_facility_unlocked(fid):
		name_lbl.text = "【%s】 Lv.%d（%s类）" % [fname, _sys().get_facility_level(fid), str(fcfg.get("category", ""))]
	else:
		name_lbl.text = "【%s】（%s类）" % [fname, str(fcfg.get("category", ""))]
	name_lbl.add_theme_font_size_override("font_size", 18)
	head.add_child(name_lbl)
	var next_btn := Button.new()
	next_btn.text = "▶"
	next_btn.custom_minimum_size = Vector2(40, 32)
	next_btn.disabled = sib_ids.size() <= 1
	if idx >= 0:
		var next_id: String = str(sib_ids[(idx + 1) % sib_ids.size()])
		next_btn.pressed.connect(func(): _show_facility_popup(next_id))
	head.add_child(next_btn)
	# 设施图占位（后续丢图： assets 下放设施图按 id 命名即可替换此处）
	var pic := Label.new()
	pic.text = "〔%s〕" % fname
	pic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pic.custom_minimum_size = Vector2(0, 72)
	pic.add_theme_font_size_override("font_size", 28)
	pic.add_theme_color_override("font_color", Color(0.85, 0.62, 0.28, 0.35))
	vb.add_child(pic)
	# flavor 文案
	var flavor := Label.new()
	flavor.text = str(fcfg.get("flavor", ""))
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.add_theme_color_override("font_color", Color("#9a93b8"))
	vb.add_child(flavor)
	if not _sys().is_facility_unlocked(fid):
		# 未解锁：解锁需求（知名度门槛 + 银条开价）
		var need_fame := Label.new()
		need_fame.text = "解锁需求：知名度 %s（当前 %s）" % [
			c.format_number(_sys().get_unlock_fame(fcfg)), c.format_number(_sys().get_fame_total())]
		vb.add_child(need_fame)
		var cost := Label.new()
		cost.text = "开价：银条 %s（拥有 %s）" % [
			c.format_number(_sys().get_unlock_cost(fcfg)), c.format_number(_sys().get_yintiao())]
		vb.add_child(cost)
		var unlock_btn := Button.new()
		unlock_btn.text = "解锁设施"
		unlock_btn.custom_minimum_size = Vector2(0, 42)
		unlock_btn.disabled = not _sys().can_unlock_facility(fid).get("ok", false)
		unlock_btn.pressed.connect(func(): _on_facility_unlock(fid))
		vb.add_child(unlock_btn)
		c._add_ok_button(vb, func(): _close_node("TavernPopup"))
		return
	# 已解锁：三属性 当前→下级
	var pv := _sys().get_facility_preview(fid)
	var bond_name: String = "友好" if str(pv.get("stat", "")) == "friendly" else "才华"
	var row1 := Label.new()
	row1.text = "知名度：%d → %d" % [int(pv.get("fame", 0)), int(pv.get("next_fame", 0))]
	vb.add_child(row1)
	var row2 := Label.new()
	row2.text = "银条收益：%d → %d" % [int(pv.get("income", 0)), int(pv.get("next_income", 0))]
	vb.add_child(row2)
	var row3 := Label.new()
	row3.text = "%s类挚友%s：%d → %d" % [str(pv.get("cat", "")), bond_name, int(pv.get("bond", 0)), int(pv.get("next_bond", 0))]
	vb.add_child(row3)
	if bool(pv.get("maxed", false)):
		var maxed := Label.new()
		maxed.text = "设施已满级"
		maxed.add_theme_color_override("font_color", Color("#9a93b8"))
		vb.add_child(maxed)
	else:
		var cost := Label.new()
		cost.text = "消耗：银条 %s（拥有 %s）" % [
			c.format_number(int(pv.get("cost", 0))), c.format_number(_sys().get_yintiao())]
		vb.add_child(cost)
		# 同步升级勾选：勾选后升级按钮=同项目全部已解锁设施各升1级
		var sync_cb := CheckBox.new()
		sync_cb.text = "同步升级（同项目全部设施各升1级）"
		vb.add_child(sync_cb)
		var up_btn := Button.new()
		up_btn.text = "升级"
		up_btn.custom_minimum_size = Vector2(0, 42)
		up_btn.disabled = not _sys().can_upgrade_facility(fid).get("ok", false)
		up_btn.pressed.connect(func(): _on_facility_upgrade(fid, str(fcfg.get("project", "")), sync_cb.button_pressed))
		vb.add_child(up_btn)
	c._add_ok_button(vb, func(): _close_node("TavernPopup"))

func _on_facility_unlock(fid: String):
	var r := _sys().unlock_facility(fid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("解锁成功")
	_refresh()

func _on_facility_upgrade(fid: String, project: String, sync: bool):
	var r: Dictionary
	if sync:
		r = _sys().upgrade_project(project)
		if r.get("ok", false):
			c._show_stage_hint("同步升级：%d 个设施各升 1 级" % int(r.get("count", 0)))
	else:
		r = _sys().upgrade_facility(fid)
		if r.get("ok", false):
			c._show_stage_hint("升级成功")
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

# 加号：弹出数量选择器，批量消耗佳酿恢复叫号（不受上限限制，背包不开放）
func _on_add_jiaohao():
	var item: String = data._tavern_configs.get("settings", {}).get("jiaohao_item", "jia_niang")
	var owned: int = int(data.items.get(item, 0))
	if owned <= 0:
		c._show_stage_hint("没有【佳酿】")
		return
	_close_node("TavernPopup")
	_popup_kind = ""   # 道具面板不属于信息/设施弹窗，刷新时不重建
	var give: int = int(data._tavern_configs.get("settings", {}).get("jiaohao_give", 2))
	var popup: PanelContainer = c._create_base_popup("使用佳酿", Vector2(400, 240))
	popup.name = "TavernPopup"
	popup.z_index = 40   # 盖过 TavernPage(z35)，同 inn/bank 弹窗惯例
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var info := Label.new()
	info.text = "拥有 %d 坛，每坛 +%d 叫号" % [owned, give]
	vb.add_child(info)
	# 数量选择：滑动条 + 输入框联动（项目惯例，同 friend_page 赠送/clinic 道具面板）
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
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(90, 34)
	ok_btn.pressed.connect(func():
		var n: int = int(spin.value)
		data.items[item] = int(data.items.get(item, 0)) - n
		_sys().add_jiaohao(n * give)
		_close_node("TavernPopup")
		c._show_stage_hint("叫号 +%d" % (n * give))
		_refresh())
	btn_row.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(90, 34)
	cancel_btn.pressed.connect(func(): _close_node("TavernPopup"))
	btn_row.add_child(cancel_btn)

func _on_collect():
	var r := _sys().collect_jar()
	c._show_stage_hint("领取：银条 +%s" % c.format_number(r))
	_refresh()

# 叫号：1 位客人转入接待队列（接待由定时器批处理）
func _on_call_one():
	var r := _sys().call_one()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("已叫号，接待中…")
	_refresh()

# 一键叫号：全部转入接待队列（纯改数字，不卡）
func _on_call_all():
	var r := _sys().call_all()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("已叫号 %d 位客人，接待中…" % int(r.get("count", 0)))
	_refresh()

# ---------- 酒肆信息弹窗 ----------
func _show_info_popup():
	_popup_kind = "info"
	_popup_id = ""
	_close_node("TavernPopup")
	var popup: PanelContainer = c._create_base_popup("酒肆信息", Vector2(440, 460))
	popup.name = "TavernPopup"
	popup.z_index = 40   # 盖过 TavernPage(z35)，同 inn/bank 弹窗惯例
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	# 招牌 + 改名（改名免费，限8字；改名后重进弹窗即可见新名）
	var sign_row := HBoxContainer.new()
	sign_row.add_theme_constant_override("separation", 8)
	vb.add_child(sign_row)
	var sign_lbl := Label.new()
	sign_lbl.text = "招牌：%s" % _sys().get_sign_name()
	sign_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sign_row.add_child(sign_lbl)
	var rename_btn := Button.new()
	rename_btn.text = "改名"
	rename_btn.custom_minimum_size = Vector2(70, 32)
	rename_btn.pressed.connect(_show_rename_popup)
	sign_row.add_child(rename_btn)
	# 等级 + 升级（知名度达标免费升）
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 8)
	vb.add_child(lv_row)
	var lv_lbl := Label.new()
	lv_lbl.text = "等级：Lv.%d" % _sys().get_level()
	lv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_row.add_child(lv_lbl)
	if _sys().get_level() < _sys().get_max_level():
		var up_btn := Button.new()
		up_btn.text = "升级"
		up_btn.custom_minimum_size = Vector2(70, 32)
		up_btn.disabled = not _sys().can_level_up().get("ok", false)
		up_btn.pressed.connect(_on_level_up)
		lv_row.add_child(up_btn)
	else:
		var max_lbl := Label.new()
		max_lbl.text = "已满级"
		max_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
		lv_row.add_child(max_lbl)
	# 接待收益三项
	var gain := Label.new()
	gain.text = "接待客人收益：银条 %s" % c.format_number(_sys().get_income_per_guest())
	vb.add_child(gain)
	var baiye := Label.new()
	baiye.text = "门客百业经验：%d（每位客人随机赠予一名已拥有门客）" % _sys().get_baiye_per_guest()
	baiye.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(baiye)
	var caiyi := Label.new()
	caiyi.text = "挚友才艺经验：%d（每位客人随机赠予一名已拥有挚友）" % _sys().get_caiyi_per_guest()
	caiyi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(caiyi)
	# 小喇叭知名度：进度 + 阈值
	var fame_cur := _sys().get_fame_total()
	var fame_need := _sys().get_fame_threshold()
	var fame := Label.new()
	if _sys().get_level() >= _sys().get_max_level():
		fame.text = "小喇叭知名度：%s（已满级）" % c.format_number(fame_cur)
	else:
		fame.text = "小喇叭知名度：%s / %s" % [c.format_number(fame_cur), c.format_number(fame_need)]
	vb.add_child(fame)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(1, fame_need)
	bar.value = fame_cur
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	vb.add_child(bar)
	if _sys().get_level() < _sys().get_max_level():
		var hint := Label.new()
		hint.text = "知名度达标即可免费升级酒肆（升级不消耗资源）"
		hint.add_theme_color_override("font_color", Color("#9a93b8"))
		vb.add_child(hint)
	c._add_ok_button(vb, func(): _close_node("TavernPopup"))

# 改名弹窗：免费，限8个中文字
func _show_rename_popup():
	_close_node("TavernPopup")
	var popup: PanelContainer = c._create_base_popup("修改招牌", Vector2(400, 200))
	popup.name = "TavernPopup"
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var edit := LineEdit.new()
	edit.text = _sys().get_sign_name()
	edit.custom_minimum_size = Vector2(240, 40)
	edit.placeholder_text = "输入新招牌（最多8字）"
	vb.add_child(edit)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vb.add_child(btn_row)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(90, 34)
	# 确定后回信息弹窗：_popup_kind 仍为 info，_refresh 会重建信息弹窗
	ok_btn.pressed.connect(func():
		var r := _sys().rename_sign(edit.text)
		if not r.get("ok", false):
			c._show_stage_hint(str(r.get("msg", "")))
			return
		_refresh())
	btn_row.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(90, 34)
	cancel_btn.pressed.connect(func(): _refresh())   # 取消也回信息弹窗
	btn_row.add_child(cancel_btn)

func _on_level_up():
	var r := _sys().level_up()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("酒肆升级：Lv.%d" % _sys().get_level())
	_refresh()
