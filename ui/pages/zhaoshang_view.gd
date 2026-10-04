# ============================================================
# 招商玩法全屏页（闯荡页「招商」入口，层级：ZhaoshangPage z35，弹窗 z40，照 BaseView 惯例）
# 三页签：承包项目（自己立项）/ 项目招商（批次①=人机兜底，真人 Worker 批次②）/ 名流榜（批次①本地账+空态）
# 口径：门客个体="赚钱"（本页不涉及），全局每分钟资历=结算公式唯一入口在 zhaoshang_system
# 弹窗：签订承包（数量步进 1~4 份）/ 项目内部页（主位+4空位+加入钮）
# 最近批次见档案 §十一
# ============================================================
class_name ZhaoshangView
extends BaseView

var _tab: String = "contract"   # 页签 contract/join/rank（类变量记忆，不依赖节点重建默认值）
var _copies: int = 1            # 签订弹窗当前份数（1~max_copies）
var _proj: Dictionary = {}      # 项目内部页当前项目（加入校验用）
var _remain_labels: Array = []  # 倒计时标签引用 [{lbl,end_ts}]（Timer 每秒就地改字，不整页重建）
var _tick_timer = null          # 页内 1s Timer（进出复位：hide_view 停止并清引用）
var _want_join_refresh: bool = false   # 进页签/手动刷新置 true；fetch 成功只允许重建一次（防"成功→重建→再fetch→再成功"死循环）

func _init(p_c):
	super(p_c)
	_page_name = "ZhaoshangPage"
	_popup_node_name = "ZhaoshangPopup"

func _sys() -> ZhaoshangSystem:
	return data.zhaoshang_system

func show_zhaoshang_view():
	show_view()
	_sys().flush_pending()   # 批次②：进页补报断网/Worker挂时暂存的项目（幂等 id 重发）
	if _tab == "join": _want_join_refresh = true   # 重进页面落在本页签时允许成功回包重建一次
	# 离线补算摘要：读档时结算的项目在首次进页一次弹出（弹后即清，不落盘）
	if _sys().offline_notice.size() > 0:
		var txt: String = ""
		for s in _sys().offline_notice:
			if txt != "": txt += "\n"
			txt += _sys().settle_text(s)
		_sys().offline_notice = []
		c._show_success_popup(txt, 0.0, "ok")

func hide_zhaoshang_view():
	hide_view()

func show_view():
	super()
	_after_show()   # 基类 show_view 已 _build；此处接离线摘要弹窗逻辑

func hide_view():
	if _tick_timer != null and is_instance_valid(_tick_timer):
		_tick_timer.stop()
	_tick_timer = null
	_remain_labels = []
	super()

# ---------- 页面构建 ----------
func _build(page: Panel):
	_remain_labels = []   # 重建前清空倒计时引用（旧标签随旧页销毁，引用悬挂由 is_instance_valid 守卫）
	var vb := VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)

	# 顶栏：返回 + 标题 + ?规则
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 48)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(90, 42)
	back_btn.pressed.connect(hide_zhaoshang_view)
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "招商"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var rule_btn := Button.new()
	rule_btn.text = "?"
	rule_btn.custom_minimum_size = Vector2(30, 30)
	rule_btn.pressed.connect(_on_rule)
	top.add_child(rule_btn)

	# 资源行：自己每分钟资历 + 槽位/次数状态
	var st := Label.new()
	st.add_theme_font_size_override("font_size", 14)
	st.add_theme_color_override("font_color", Color("#c8c3e0"))
	st.text = "每分钟资历 %d ｜ 承包 %d/%d ｜ 参与 %d/%d" % [
		_sys().get_merit_per_min(),
		_sys().active_projects.size(), _sys().get_project_slot_total(),
		_sys().joined_projects.size(), _sys().get_join_slot_total()]
	vb.add_child(st)

	# 页签栏
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for t in [["contract", "承包项目"], ["join", "项目招商"], ["rank", "名流榜"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.custom_minimum_size = Vector2(120, 40)
		# 选中页签高亮（类变量 _tab 记忆，重建后不回跳）
		tb.add_theme_color_override("font_color", Color("#ffd700") if _tab == t[0] else Color("#f2f2f2"))
		tb.pressed.connect(_on_tab.bind(t[0]))
		tabs.add_child(tb)

	# 内容区
	var body := ScrollContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	body.add_child(list)

	match _tab:
		"join": _build_join_tab(list)
		"rank": _build_rank_tab(list)
		_: _build_contract_tab(list)

# ---------- 页签一：承包项目 ----------
func _build_contract_tab(list: VBoxContainer):
	# 进行中列表（剩余倒计时由页内 Timer 每秒就地改字）
	for p in _sys().active_projects:
		var conf: Dictionary = _sys().get_project_cfg(str(p.get("type", "")))
		var card := PanelContainer.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color("#221d33")
		sty.border_color = Color("#6a5f8a")
		sty.set_border_width_all(1)
		sty.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", sty)
		list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 15)
		info.text = "【%s】×%d\n预计 %s+%d" % [str(conf.get("name", "项目")), int(p.get("copies", 1)),
			_sys().merit_name(str(conf.get("merit", ""))), int(p.get("merit", 0))]
		row.add_child(info)
		var remain := Label.new()
		remain.add_theme_font_size_override("font_size", 15)
		remain.add_theme_color_override("font_color", Color("#7ee787"))
		remain.text = _fmt_remain(int(p.get("end_ts", 0)))
		row.add_child(remain)
		_remain_labels.append({"lbl": remain, "end_ts": int(p.get("end_ts", 0))})

	if not _sys().pending_projects.is_empty():
		var pend := Label.new()
		pend.add_theme_font_size_override("font_size", 13)
		pend.add_theme_color_override("font_color", Color("#ffb84d"))
		pend.text = "有 %d 个项目待补报（联网进入本页自动上报）" % _sys().pending_projects.size()
		list.add_child(pend)

	if _sys().active_projects.size() == 0:
		var empty := Label.new()
		empty.text = "暂无进行中的项目（下方选择项目承包）"
		empty.add_theme_color_override("font_color", Color("#8a84a8"))
		list.add_child(empty)

	# 五项目网格（3+2 排列照截图）：批文名 + 持有数
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)
	for p_type in _sys().get_projects().keys():
		var conf: Dictionary = _sys().get_project_cfg(p_type)
		var have: int = int(data.items.get(str(conf.get("piwen", "")), 0))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(170, 76)
		btn.text = "%s\n%s ×%d" % [str(conf.get("name", p_type)), str(conf.get("piwen_name", "批文")), have]
		btn.pressed.connect(_on_sign.bind(p_type))
		grid.add_child(btn)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#8a84a8"))
	hint.text = "资历产出受自身身份、藏品效果影响；每份批文持续180分钟，结束一次性结算"
	list.add_child(hint)

# ---------- 页签二：项目招商（真人 Worker 项目 + 人机兜底） ----------
func _build_join_tab(list: VBoxContainer):
	# 真机项目：进页拉取（排除自己/满员/已结束）；拉取失败显示重试钮，列表照常用 AI 兜底
	# 成功才自动重建，且每轮进入只重建一次：成败都重建都会成环（失败环/成功环，批次②两次实测教训）；
	# 回调晚于用户离开页面到达时必须放弃——get_node_or_null 守卫防"返回后被弹回招商页"
	_sys().fetch_real_projects(func(_ok: bool):
		if _ok and _tab == "join" and _want_join_refresh and c.get_node_or_null(_page_name) != null:
			_want_join_refresh = false
			_refresh())
	# 登录后常驻刷新钮（兼作失败重试）；real_projects_failed 仅作内部态，不驱动重建
	if _sys().net != null and _sys().net.token != "":
		var retry := Button.new()
		retry.text = "刷新真人项目"
		retry.custom_minimum_size = Vector2(0, 44)
		retry.pressed.connect(_on_join_refresh)
		list.add_child(retry)
	for p in _sys().real_projects:
		_add_join_card(list, p, false)
	# 人机项目 5 个常驻、每次打开重新生成倒计时；只显示有空位项目（人机恒有空位）
	for p in _sys().get_ai_projects():
		_add_join_card(list, p, true)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#8a84a8"))
	hint.text = "加入后按自己每分钟资历×剩余分钟结算，占用参与槽位至项目结束"
	list.add_child(hint)

# 项目招商卡（真人/人机共用）：真人标"真人"且人数取服务端 joined；人机人数=自己是否加入
func _add_join_card(list: VBoxContainer, p: Dictionary, is_ai: bool):
	var conf: Dictionary = _sys().get_project_cfg(str(p.get("type", "")))
	var joined: bool = _sys().has_joined(str(p.get("id", "")))
	var card := PanelContainer.new()
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color("#221d33")
	sty.border_color = Color("#6a5f8a")
	sty.set_corner_radius_all(6)
	sty.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", sty)
	card.add_theme_constant_override("margin_left", 10)
	list.add_child(card)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 64)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var joined_cnt: int = int(p.get("joined", 0)) if not is_ai else (1 if joined else 0)
	var tag: String = "人机" if is_ai else "真人"
	var state: String = "参与中" if joined else "%d/%d" % [joined_cnt, int(p.get("slots", 5))]
	btn.text = "[%s]【%s】%s  剩余%s\n立项人：%s   已加入 %s" % [tag, str(conf.get("name", "项目")),
		_sys().merit_name(str(conf.get("merit", ""))), _fmt_remain(int(p.get("end_ts", 0))),
		str(p.get("owner_name", "神秘商贾")), state]
	btn.pressed.connect(_on_project.bind(p))
	card.add_child(btn)

# ---------- 页签三：名流榜（批次①：本地本周账+空态，真人榜/点赞批次③） ----------
func _build_rank_tab(list: VBoxContainer):
	# 本周榜周一 0 点重置；批次①只显示自己本周五种资历账（真人榜与点赞 Worker 批次③接入）
	var names: Dictionary = _sys().get_merit_names()
	for key in names.keys():
		var row := PanelContainer.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color("#221d33")
		sty.border_color = Color("#6a5f8a")
		sty.set_border_width_all(1)
		sty.set_corner_radius_all(6)
		row.add_theme_stylebox_override("panel", sty)
		list.add_child(row)
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.text = "%s　本周 +%s" % [str(names[key]), c.format_number(_sys().get_merit(str(key)))]
		row.add_child(lbl)
	var empty := Label.new()
	empty.add_theme_font_size_override("font_size", 14)
	empty.add_theme_color_override("font_color", Color("#8a84a8"))
	empty.text = "本周榜虚位以待（名流榜排名批次开放）；每周一 0 点重置"
	list.add_child(empty)

# ---------- 签订承包弹窗 ----------
func _on_sign(p_type: String):
	_popup_kind = "sign"
	_popup_id = p_type
	_copies = 1
	_open_sign_popup()

func _open_sign_popup():
	_close_node(_popup_node_name)
	var popup = c._create_base_popup("签订承包", Vector2(420, 360))
	popup.name = _popup_node_name
	# _create_base_popup 出厂弹窗 z30/遮罩 z25，会被 z35 全屏页盖住（点击"没反应"实已弹出）；
	# 抬层照 winery/drugshop 页内弹窗惯例：遮罩 39 + 弹窗 40
	popup.get_meta("popup_mask").z_index = 39
	popup.z_index = 40
	c.add_child(popup)
	_fill_sign_popup(popup)

# 原地重建内容（同名弹窗禁删旧建新：queue_free 帧末删除会让新节点改名，勋章批次踩坑14）
func _fill_sign_popup(popup):
	var vbox = popup.get_child(0)
	for ch in vbox.get_children():
		vbox.remove_child(ch)
		ch.queue_free()
	var conf: Dictionary = _sys().get_project_cfg(_popup_id)
	var have: int = int(data.items.get(str(conf.get("piwen", "")), 0))
	var max_c: int = mini(_sys().get_max_copies(), maxi(1, have))
	_copies = clampi(_copies, 1, maxi(1, max_c))

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.text = "【%s】%s" % [str(conf.get("name", "项目")), _sys().merit_name(str(conf.get("merit", "")))]
	vbox.add_child(name_lbl)

	var own := Label.new()
	own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	own.text = "%s ×%d" % [str(conf.get("piwen_name", "批文")), have]
	vbox.add_child(own)

	# 数量步进（纯按钮步进，Web 手机虚拟键盘输入是引擎已知 bug——教训33）
	var step := HBoxContainer.new()
	step.alignment = BoxContainer.ALIGNMENT_CENTER
	step.add_theme_constant_override("separation", 16)
	vbox.add_child(step)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(48, 40)
	minus.pressed.connect(_on_step.bind(-1))
	step.add_child(minus)
	var cnt := Label.new()
	cnt.text = "%d 份" % _copies
	cnt.custom_minimum_size = Vector2(80, 40)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.add_theme_font_size_override("font_size", 18)
	step.add_child(cnt)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(48, 40)
	plus.pressed.connect(_on_step.bind(1))
	step.add_child(plus)

	var minutes: int = _sys().get_minutes_per_copy()
	var per_min: int = _sys().get_merit_per_min()
	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", Color("#c8c3e0"))
	info.text = "项目时长 %d 分钟\n每分钟资历 %d\n预计结算 %s+%d" % [_copies * minutes, per_min,
		_sys().merit_name(str(conf.get("merit", ""))), per_min * _copies * minutes]
	vbox.add_child(info)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#8a84a8"))
	hint.text = "资历产出受自身身份、藏品效果影响"
	vbox.add_child(hint)

	var ok := Button.new()
	ok.text = "承包"
	ok.custom_minimum_size = Vector2(140, 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_on_contract)
	vbox.add_child(ok)

func _on_step(d: int):
	_copies += d
	_fill_sign_popup(c.get_node(_popup_node_name))

func _on_contract():
	var res: Dictionary = _sys().contract(_popup_id, _copies)
	if bool(res.get("ok", false)):
		c._show_success_popup(str(res.get("msg", "")) + "\n预计+%s资历" % c.format_number(int(res.get("merit", 0))), 0.0, "ok")
		close_popup()
		_refresh()
		# 批次②：立项成功即向 Worker 发布；失败两口径由 system 按 code 分流（补报/回滚），红字在此透传
		_sys().publish_project(res.get("project", {}), func(msg: String): c._show_success_popup(msg, 0.0, "warn"))
	else:
		c._show_success_popup(str(res.get("msg", "无法承包")), 0.0, "warn")

# ---------- 项目内部页（弹窗承载：顶部信息+主位卡+4空位+加入钮） ----------
func _on_project(p: Dictionary):
	_proj = p
	_popup_kind = "project"
	_popup_id = str(p.get("id", ""))
	_close_node(_popup_node_name)
	var conf: Dictionary = _sys().get_project_cfg(str(p.get("type", "")))
	var popup = c._create_base_popup(str(conf.get("name", "项目")), Vector2(440, 420))
	popup.name = _popup_node_name
	# 同签订弹窗：出厂 z30 会被 z35 页面盖住，抬 40（遮罩 39）
	popup.get_meta("popup_mask").z_index = 39
	popup.z_index = 40
	c.add_child(popup)
	var vbox = popup.get_child(0)

	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", Color("#c8c3e0"))
	info.text = "剩余 %s\n自己每分钟资历 %d（%s）" % [_fmt_remain(int(p.get("end_ts", 0))),
		_sys().get_merit_per_min(), _sys().merit_name(str(conf.get("merit", "")))]
	vbox.add_child(info)

	# 主位卡（立项人）+ 4 个加入位
	var seats := GridContainer.new()
	seats.columns = 2
	seats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seats.add_theme_constant_override("h_separation", 8)
	seats.add_theme_constant_override("v_separation", 8)
	vbox.add_child(seats)
	var host := Button.new()
	host.text = "主位\n%s" % str(p.get("owner_name", "神秘商贾"))
	host.custom_minimum_size = Vector2(150, 60)
	host.disabled = true
	seats.add_child(host)
	for i in range(4):
		var seat := Button.new()
		seat.text = "空位" if not (_sys().has_joined(_popup_id) and i == 0) else "我（参与中）"
		seat.custom_minimum_size = Vector2(150, 60)
		seat.disabled = true
		seats.add_child(seat)

	var check: Dictionary = _sys().get_join_check(p)
	var join := Button.new()
	join.text = "加入" if bool(check.get("ok", false)) else str(check.get("reason", "无法加入"))
	join.custom_minimum_size = Vector2(140, 44)
	join.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join.disabled = not bool(check.get("ok", false))
	join.pressed.connect(_on_join)
	vbox.add_child(join)

func _on_join():
	if bool(_proj.get("is_ai", false)):
		var res: Dictionary = _sys().join_project(_proj)
		if bool(res.get("ok", false)):
			c._show_success_popup(str(res.get("msg", "")), 0.0, "ok")
			close_popup()
			_refresh()
		else:
			c._show_success_popup(str(res.get("msg", "无法加入")), 0.0, "warn")
	else:
		# 真人项目：服务器确认成功才占槽位（弱网不占槽，拍板口径）
		_sys().join_real(_proj, func(ok: bool, msg: String):
			if ok:
				c._show_success_popup(msg, 0.0, "ok")
				close_popup()
				_refresh()
			else:
				c._show_success_popup(msg, 0.0, "warn"))

# ---------- 通用 ----------
func _on_tab(t: String):
	_tab = t
	if t == "join": _want_join_refresh = true   # 主动切进本页签允许成功回包重建一次
	_refresh()

func _on_join_refresh():
	_want_join_refresh = true
	_refresh()

func _on_rule():
	c._show_rule_popup("招商规则",
		"承包：消耗批文立项项目，每份批文持续180分钟，份数1~4，结束一次性结算资历。\n" +
		"结算：每分钟资历=基础60×身份倍数×(1+藏品加成)，承包资历=每分钟×份数×180。\n" +
		"加入：加入他人项目按自己每分钟资历×剩余分钟结算，占用参与槽位至项目结束。\n" +
		"槽位：承包槽位=基础1+藏品岱宗+天赋；参与槽位=基础2+天赋。\n" +
		"次数：每日可承包次数随VIP等级提升，每日0点重置。")

func _fmt_remain(end_ts: int) -> String:
	var left: int = maxi(0, end_ts - int(Time.get_unix_time_from_system()))
	var h: int = floori(left / 3600.0)
	var m: int = floori((left % 3600) / 60.0)
	var s: int = left % 60
	return "%02d:%02d:%02d" % [h, m, s]

# 页内 1s Timer：只就地改倒计时文字；有项目到期则整页重建（结算弹窗由 controller 节拍统一弹）
func _after_show():
	var page = c.get_node_or_null(_page_name)
	if page == null: return
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	page.add_child(timer)
	_tick_timer = timer
	timer.timeout.connect(_on_tick)

func _on_tick():
	for e in _remain_labels:
		var lbl = e.get("lbl")
		if lbl == null or not is_instance_valid(lbl): continue
		lbl.text = _fmt_remain(int(e.get("end_ts", 0)))
	var now: int = int(Time.get_unix_time_from_system())
	for e in _remain_labels:
		if now >= int(e.get("end_ts", 0)):
			_remain_labels = []
			show_view()   # 到期项目已由 controller 节拍结算，这里重建列表
			return
