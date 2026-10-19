# ============================================================
# 酒肆玩法全屏页（商铺地图 酒肆店铺「▶」入口，层级：TavernPage z35，同医馆/客栈页惯例）
# 2026-09-16 批3完整版（覆盖批2）：
#   主页 = 代码配色背景（深酒红棕+酒字水印，后续有"红尘酒楼"素材可直接换底）
#          + 右上浮层（招牌/知名度/银条）+ 收益罐(领银条) + 叫号条(x/50+倒计时+【+】)
#          + 叫号/一键叫号（纯改数字转接待队列）+ 接待队列状态 + 餐饮/娱乐双入口（带红点）
#   设施弹窗 = 羊皮纸弹窗：项目页签 + 同步升级 + 设施卡片网格（框/标题条/设施图/Lv/红点）
#   信息弹窗 = 羊皮纸弹窗：招牌改名(免费限8字)/等级/简介/接待收益三行(当前→下级)/知名度进度/升级
# 重建刷新模式：操作后整页重建；0.05s Timer 推进接待批次+刷文本（不重建保流畅）
# ============================================================
class_name TavernView
extends BaseView   # 【改】公共层下沉 ui/base_view.gd（2026-09-18 架构重构批次⑤）

# c/data 引用、弹窗状态机（_popup_kind/_popup_id）由基类持有，此处不再声明

var _proj: Dictionary = {"餐饮": "", "娱乐": ""}   # 各区域当前选中项目（页签状态，切区保留）
var _timer: Timer = null               # 批处理/秒刷定时器（0.05s）
var _jar_icon: Button = null
var _call_all_check: CheckBox = null
var _jh_lbl: Label = null              # 叫号计数文本（主页）
# _popup_kind/_popup_id 由基类 BaseView 持有（2026-09-18 架构重构批次⑤），此处不再声明

const SCENE: PackedScene = preload("res://ui/pages/tavern_view.tscn")
const JAR_EMPTY: Texture2D = preload("res://assets/tavern/收益罐空.png")
const JAR_FULL: Texture2D = preload("res://assets/tavern/收益罐满.png")
const INFO_BG: Texture2D = preload("res://assets/tavern/酒肆信息弹窗.png")
const FAC_BG: Texture2D = preload("res://assets/tavern/酒肆设施弹窗.png")
# 设施卡片素材（2026-10-19 豆姐图入库）：框/标题条/五张设施图；白底已抠成透明
const FAC_FRAME: Texture2D = preload("res://assets/tavern/设施框.png")
const FAC_TITLE_BAR: Texture2D = preload("res://assets/tavern/设施标题.png")
const FAC_ART_GUITAI: Texture2D = preload("res://assets/tavern/设施_柜台.png")
const FAC_ART_CESUO: Texture2D = preload("res://assets/tavern/设施_厕所.png")
const FAC_ART_JINGGUAN: Texture2D = preload("res://assets/tavern/设施_景观.png")
const FAC_ART_DIAOXIANG: Texture2D = preload("res://assets/tavern/设施_雕像.png")
const FAC_ART_HOUDENG: Texture2D = preload("res://assets/tavern/设施_等候桌.png")
const ICON_YINTIAO: Texture2D = preload("res://assets/tavern/银条.png")
const ICON_FAME: Texture2D = preload("res://assets/tavern/知名度.png")
# 豆姐补的三枚图标（2026-10-19 入库）：百业=书、才艺=琵琶、改名=毛笔
const ICON_BAIYE: Texture2D = preload("res://assets/tavern/百业经验.png")
const ICON_CAIYI: Texture2D = preload("res://assets/tavern/才艺经验.png")
const ICON_RENAME: Texture2D = preload("res://assets/tavern/酒楼改名.png")

# ---------- 定制画底弹窗布局表（锚点外置：只调数值，不动结构；tavern_preview.py 直接读这张表出预览） ----------
# 数值=相对弹窗矩形的比例 [x0, y0, x1, y1]；popup=弹窗像素尺寸（600×1067 设计基准）
const UI_INFO := {
	"popup": Vector2(560, 469),
	"tag": [0.052, 0.335, 0.108, 0.500],
	"title_row": [0.50, 0.045, 0.95, 0.112],
	"level": [0.50, 0.115, 0.86, 0.165],
	"intro": [0.54, 0.175, 0.95, 0.335],
	"ribbon": [0.18, 0.443, 0.94, 0.505],
	"row1": 0.525,
	"row2": 0.583,
	"row3": 0.641,
	"rows_box": [0.22, 0.92],
	"row_h": 0.058,
	"fame": [0.22, 0.792, 0.92, 0.848],
	"button": [0.36, 0.858, 0.64, 0.928],
}
const UI_AREA := {
	"popup": Vector2(560, 830),
	"title": [0.28, 0.052, 0.72, 0.112],
	"content": [0.06, 0.135, 0.94, 0.925],
	"card_min": Vector2(150, 196),
	"card_bar": [0.07, 0.040, 0.93, 0.185],
	"card_art": [0.11, 0.20, 0.89, 0.72],
	"card_lv": [0.08, 0.735, 0.92, 0.815],
	"card_dot": [0.80, 0.015, 0.95, 0.075],
}

func _init(p_c):
	super(p_c)   # 【改】基类注入 c/data（2026-09-18 架构重构批次⑤）
	_page_name = "TavernPage"
	_popup_node_name = "TavernPopup"
	_page_bg = "#33150f"   # 深酒红棕底（无素材期的代码配色，后续丢"红尘酒楼"图换底）

func _sys() -> TavernSystem:
	return data.tavern_system

# ---------- 页面开关 ----------
func show_tavern_view():
	show_view()

func hide_tavern_view():
	hide_view()

# 【改】酒肆生命周期特殊，整体重写基类入口（2026-09-18 架构重构批次⑤）：
# 打开=清弹窗状态+关页关弹窗+建页（基类 show_view 刻意不清状态是照顾 _refresh 重建链，酒肆惯例相反）；
# 建页走 _build_page 而非基类 show_view 尾部——_build_page 不关弹窗节点，
# 道具面板等"无状态弹窗"刷新重建页面后仍须可见（基类 show_view 会把它们一并关掉）
func show_view():
	_popup_kind = ""
	_popup_id = ""
	_close_node(_page_name)
	_close_node(_popup_node_name)
	_close_node("TavernRulePopup")   # 【新增】批次②③④-B1修正：规则说明弹窗随页面重开清理
	_build_page()

# 关闭=进出复位页签（原 hide_tavern_view 语义，同 clinic 惯例）+ 基类清理。
# 基类比原实现多清 _popup_kind/_popup_id，无观测差异：下次 show 本就会清，页关期间无人读状态
func hide_view():
	_close_node("TavernRulePopup")   # 【新增】批次②③④-B1修正：离开酒肆时连带关闭规则说明弹窗
	super()

# 仅重建页面不关弹窗：连升/连解锁时设施弹窗常驻原位刷新（_refresh 用）；进出酒肆才全关
func _build_page():
	# 场景实例重挂用 free()：queue_free 帧末回收，同帧重建断契约（府邸铁律1）
	if c.has_node("TavernPage"):
		c.get_node("TavernPage").free()
	var page: Panel = SCENE.instantiate()
	page.name = "TavernPage"
	c.add_child(page)
	_wire_page(page)
	_fill(page)
	# 批处理定时器：0.05s 一次，每次最多跑 4ms（约5000+客/秒，帧压力恒定）
	_timer = Timer.new()
	_timer.wait_time = 0.05
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	page.add_child(_timer)

func _open_area(area: String):
	_popup_kind = "area"
	_popup_id = area
	_show_area_popup(area)

func _on_tick():
	# 接待队列批处理（时间盒 4ms，接待完自然停；队列随存档保留，重开页面接着接待）
	if _sys().get_serve_queue() > 0:
		_sys().process_serve_queue(4)
	if _jh_lbl:
		_jh_lbl.text = _jh_text()
	if _jar_icon:
		_jar_icon.icon = JAR_FULL if _sys().has_jar() else JAR_EMPTY

func _jh_text() -> String:
	return "体力：%d/%d" % [_sys().get_jiaohao(), _sys().get_jiaohao_cap()]

func _wire_page(page: Control):
	for n in ["TopBarPanel", "TopBar", "BackButton", "TitleLabel", "RuleButton", "CenterFill",
			"AreaScroll", "AreaBody", "MainNav", "CanButton", "JoyButton", "CanDot", "JoyDot",
			"InfoPanel", "InfoTitle", "FameLabel", "SilverLabel",
			"CallIconButton", "StaminaPanel", "JhLabel", "AddButton", "CallAllPanel", "CallAllCheck", "JarIcon"]:
		if page.find_child(n, true, false) == null:
			push_error("tavern_view: 必需节点 %s 缺失，检查 tavern_view.tscn" % n)
	page.find_child("BackButton", true, false).pressed.connect(_on_back)
	page.find_child("RuleButton", true, false).pressed.connect(_show_rule_popup)
	page.find_child("InfoTitle", true, false).pressed.connect(_show_info_popup)
	page.find_child("CanButton", true, false).pressed.connect(func(): _open_area("餐饮"))
	page.find_child("JoyButton", true, false).pressed.connect(func(): _open_area("娱乐"))
	page.find_child("JarIcon", true, false).pressed.connect(_on_collect)
	page.find_child("AddButton", true, false).pressed.connect(_on_add_jiaohao)
	page.find_child("CallAllCheck", true, false).toggled.connect(_on_call_all_toggled)
	page.find_child("CallIconButton", true, false).pressed.connect(_on_call)

# 状态驱动填充：静态结构/图标全在 tscn，脚本只灌文本/显隐（灌内容口径）
func _fill(page: Panel):
	var title: Label = page.find_child("TitleLabel", true, false)
	title.text = "酒肆"
	# 右上信息牌（酒肆信息图标化：标题可点=信息弹窗）
	page.find_child("InfoTitle", true, false).text = _sys().get_sign_name()
	page.find_child("FameLabel", true, false).text = "知名度：%s" % c.format_number(_sys().get_fame_total())
	page.find_child("SilverLabel", true, false).text = "银条：%s" % c.format_number(_sys().get_yintiao())
	# 餐饮/娱乐已改羊皮纸弹窗，页面常驻主页形态（AreaScroll 保留但不再使用）
	page.find_child("CenterFill", true, false).visible = true
	page.find_child("MainNav", true, false).visible = true
	page.find_child("AreaScroll", true, false).visible = false
	# 收益罐双态（tick 也活更新）
	_jar_icon = page.find_child("JarIcon", true, false)
	_jar_icon.icon = JAR_FULL if _sys().has_jar() else JAR_EMPTY
	# 体力行 + 一键叫号勾选（勾选=叫号消耗全部体力）
	_jh_lbl = page.find_child("JhLabel", true, false)
	_jh_lbl.text = _jh_text()
	_call_all_check = page.find_child("CallAllCheck", true, false)
	_call_all_check.button_pressed = _sys().get_auto_call_all()
	# 页签红点
	page.find_child("CanDot", true, false).visible = _area_has_hint("餐饮")
	page.find_child("JoyDot", true, false).visible = _area_has_hint("娱乐")

func _on_back():
	hide_tavern_view()

# 操作后统一刷新：只重建页面不关弹窗；弹窗在则按类别原位重建（连升/连解锁不用反复开关）
func _refresh():
	var had_popup: bool = c.get_node_or_null("TavernPopup") != null
	_close_node("TavernPage")
	_build_page()
	if not had_popup:
		return
	if _popup_kind == "info":
		_show_info_popup()
	elif _popup_kind == "area":
		_show_area_popup(_popup_id)
	elif _popup_kind == "facility" and _popup_id != "":
		_show_facility_popup(_popup_id)

# ---------- 主页：收益罐主卡 + 叫号操作 ----------
func _area_has_hint(area: String) -> bool:
	for f in _sys().get_facility_list():
		if str(f.get("area", "")) != area:
			continue
		var fid := str(f.get("id", ""))
		if _sys().can_upgrade_facility(fid).get("ok", false) or _sys().can_unlock_facility(fid).get("ok", false):
			return true
	return false

# ---------- 餐饮/娱乐：羊皮纸弹窗（项目页签 + 设施卡片网格） ----------
func _show_area_popup(area: String):
	_close_node("TavernPopup")
	_popup_kind = "area"
	_popup_id = area
	var sz: Vector2 = UI_AREA["popup"]
	var root: Control = _art_popup(FAC_BG, sz)
	var title := Label.new()
	title.text = area
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.97, 0.9, 0.96))
	_place_rect(root, title, UI_AREA["title"])
	# 内容容器：页签/同步升级/卡片网格；切项目只重铺它，不重建弹窗
	var content := VBoxContainer.new()
	content.name = "AreaContent"
	content.add_theme_constant_override("separation", 10)
	_place_rect(root, content, UI_AREA["content"])
	_fill_area_content(content, area)

func _fill_area_content(content: VBoxContainer, area: String):
	for ch in content.get_children():
		content.remove_child(ch)
		ch.queue_free()
	var projects: Array = _sys().get_projects(area)
	if projects.is_empty():
		return
	var cur: String = str(_proj.get(area, ""))
	if not projects.has(cur):
		cur = str(projects[0])
		_proj[area] = cur
	# 项目页签
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	content.add_child(tabs)
	for p in projects:
		var proj_name: String = str(p)
		var tb := Button.new()
		tb.text = proj_name
		tb.custom_minimum_size = Vector2(72, 32)
		tb.add_theme_font_size_override("font_size", 14)
		_style_area_tab(tb, proj_name == cur)
		tb.pressed.connect(func(): _on_pick_project(area, proj_name))
		tabs.add_child(tb)
		if _project_has_hint(proj_name):
			var dot := Label.new()
			dot.text = "●"
			dot.add_theme_color_override("font_color", Color("#d0453a"))
			dot.add_theme_font_size_override("font_size", 12)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.anchor_left = 1.0
			dot.anchor_right = 1.0
			dot.offset_left = -12
			dot.offset_right = 2
			dot.offset_top = -4
			dot.offset_bottom = 12
			tb.add_child(dot)
	# 同步升级行（同项目全部已解锁设施各+1级；银条不足者自动跳过）
	var sync_row := HBoxContainer.new()
	sync_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sync_row.add_theme_constant_override("separation", 8)
	content.add_child(sync_row)
	var sync_cost := 0
	for f in _sys().get_project_facilities(cur):
		var fid := str(f.get("id", ""))
		if _sys().can_upgrade_facility(fid).get("ok", false):
			sync_cost += _sys().get_upgrade_cost(fid)
	var sync_btn := Button.new()
	sync_btn.text = "同步升级（银条 %s）" % c.format_number(sync_cost)
	sync_btn.custom_minimum_size = Vector2(220, 34)
	sync_btn.add_theme_font_size_override("font_size", 15)
	sync_btn.disabled = sync_cost <= 0
	_style_paper_button(sync_btn)
	var proj_c: String = cur
	sync_btn.pressed.connect(func(): _on_sync_upgrade(proj_c))
	sync_row.add_child(sync_btn)
	# 设施卡片网格（3 列，纵向滚动）
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for f in _sys().get_project_facilities(cur):
		grid.add_child(_make_facility_card(f))

# 单张设施卡：框 + 红标题条 + 设施图 + Lv/解锁条件 + 红点
func _make_facility_card(fcfg: Dictionary) -> Control:
	var fid := str(fcfg.get("id", ""))
	var unlocked: bool = _sys().is_facility_unlocked(fid)
	var card := Control.new()
	var cmin: Vector2 = UI_AREA["card_min"]
	card.custom_minimum_size = cmin
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := TextureRect.new()
	bg.texture = FAC_FRAME
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)
	var bar := TextureRect.new()
	bar.texture = FAC_TITLE_BAR
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_rect(card, bar, UI_AREA["card_bar"])
	var name_lbl := Label.new()
	name_lbl.text = str(fcfg.get("name", fid))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1, 0.97, 0.9, 0.96))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_rect(card, name_lbl, UI_AREA["card_bar"])
	var art := TextureRect.new()
	var tex: Texture2D = _fac_art(fid)
	if tex != null:
		art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		art.modulate = Color(1, 1, 1, 0.45)
	_place_rect(card, art, UI_AREA["card_art"])
	var lv := Label.new()
	if unlocked:
		lv.text = "Lv.%d" % _sys().get_facility_level(fid)
	else:
		lv.text = "知名度 %s 解锁" % c.format_number(_sys().get_unlock_fame(fcfg))
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_theme_font_size_override("font_size", 12)
	lv.add_theme_color_override("font_color", Color("#5a3d26") if unlocked else Color("#a0524a"))
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_rect(card, lv, UI_AREA["card_lv"])
	if _sys().can_upgrade_facility(fid).get("ok", false) or _sys().can_unlock_facility(fid).get("ok", false):
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#d0453a"))
		dot.add_theme_font_size_override("font_size", 15)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place_rect(card, dot, UI_AREA["card_dot"])
	var btn := Button.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fid_c: String = fid
	btn.pressed.connect(func():
		_popup_kind = "facility"
		_popup_id = fid_c
		_show_facility_popup(fid_c))
	card.add_child(btn)
	return card

# 设施图：按 id 映射（缺失返回 null，卡片只显示框/标题/等级）
func _fac_art(fid: String) -> Texture2D:
	if fid == "guitai":
		return FAC_ART_GUITAI
	if fid == "cesuo":
		return FAC_ART_CESUO
	if fid == "jingguan":
		return FAC_ART_JINGGUAN
	if fid == "diaoxiang":
		return FAC_ART_DIAOXIANG
	if fid.begins_with("houdeng"):
		return FAC_ART_HOUDENG
	return null

func _project_has_hint(proj: String) -> bool:
	for f in _sys().get_project_facilities(proj):
		var fid := str(f.get("id", ""))
		if _sys().can_upgrade_facility(fid).get("ok", false) or _sys().can_unlock_facility(fid).get("ok", false):
			return true
	return false

func _style_area_tab(btn: Button, selected: bool):
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#b5523c") if selected else Color("#e8dcc4")
	sb.border_color = Color("#8a7355")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	var hover: StyleBoxFlat = sb.duplicate()
	hover.bg_color = Color("#c4644c") if selected else Color("#f2e8d4")
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", Color(1, 0.97, 0.9) if selected else Color("#5a3d26"))

func _style_paper_button(btn: Button):
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#e8dcc4")
	sb.border_color = Color("#8a7355")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	for st in ["normal", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sb)
	btn.add_theme_color_override("font_color", Color("#5a3d26"))

func _on_pick_project(area: String, proj: String):
	_proj[area] = proj
	var content: VBoxContainer = c.get_node_or_null("TavernPopup/AreaContent")
	if content == null:
		_show_area_popup(area)
		return
	_fill_area_content(content, area)

func _on_sync_upgrade(proj: String):
	var r := _sys().upgrade_project(proj)
	if not r.get("ok", false):
		c._show_success_popup(str(r.get("msg", "")), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		return
	c._show_success_popup("同步升级：%d 个设施各升 1 级" % int(r.get("count", 0)), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	_refresh()

# ---------- 设施弹窗：三属性当前→下级 + 升级/同步升级勾选 + 左右切设施 ----------
func _show_facility_popup(fid: String):
	_close_node("TavernPopup")
	_popup_kind = "facility"
	_popup_id = fid
	var fcfg: Dictionary = _sys().get_facility_cfg(fid)
	var root: Control = _art_popup(FAC_BG, Vector2(600, 889))
	# 红色横幅：设施名（未解锁不显示 Lv）+ 左右切换
	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	if _sys().is_facility_unlocked(fid):
		name_lbl.text = "【%s】 Lv.%d" % [str(fcfg.get("name", fid)), int(_sys().get_facility_level(fid))]
	else:
		name_lbl.text = "【%s】" % str(fcfg.get("name", fid))
	_place(root, name_lbl, 0.30, 0.062, 0.70, 0.128)
	var ids: Array = []
	for f in _sys().get_project_facilities(str(fcfg.get("project", ""))):
		ids.append(str(f.get("id", fid)))
	var idx: int = ids.find(fid)
	var prev_id: String = ids[(idx - 1 + ids.size()) % ids.size()] if idx >= 0 else fid
	var next_id: String = ids[(idx + 1) % ids.size()] if idx >= 0 else fid
	for b in [["prev", "◀", prev_id, 0.235, 0.075, 0.295, 0.115], ["next", "▶", next_id, 0.705, 0.075, 0.765, 0.115]]:
		var hb := Button.new()
		hb.text = b[1]
		hb.add_theme_font_size_override("font_size", 16)
		hb.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		for st in ["normal", "hover", "pressed", "focus"]:
			hb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var target: String = str(b[2])
		hb.pressed.connect(func():
			root.queue_free()
			_show_facility_popup(target))
		hb.disabled = target == fid
		_place(root, hb, float(b[3]), float(b[4]), float(b[5]), float(b[6]))
	# 风味
	var flavor := Label.new()
	flavor.text = str(fcfg.get("flavor", ""))
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.add_theme_font_size_override("font_size", 15)
	flavor.add_theme_color_override("font_color", Color("#8a7a66"))
	_place(root, flavor, 0.15, 0.20, 0.85, 0.30)
	if not _sys().is_facility_unlocked(fid):
		# 未解锁：解锁需求 + 开价 + 解锁主钮
		_kv_row(root, 0.16, 0.37, 0.84, 0.415, "解锁需求：知名度", int(_sys().get_fame_total()), int(_sys().get_unlock_fame(fcfg)))
		_kv_row(root, 0.16, 0.44, 0.84, 0.485, "开价：银条", int(_sys().get_yintiao()), int(_sys().get_unlock_cost(fcfg)))
		var unlock_btn := Button.new()
		unlock_btn.text = "解锁设施"
		unlock_btn.custom_minimum_size = Vector2(0, 46)
		var ub := StyleBoxFlat.new()
		ub.bg_color = Color("#c9a050")
		ub.set_corner_radius_all(10)
		for st in ["normal", "hover", "pressed"]:
			unlock_btn.add_theme_stylebox_override(st, ub)
		unlock_btn.add_theme_color_override("font_color", Color("#3a2613"))
		unlock_btn.add_theme_font_size_override("font_size", 18)
		unlock_btn.disabled = not _sys().can_unlock_facility(fid).get("ok", false)
		unlock_btn.pressed.connect(func(): _on_facility_unlock(fid))
		_place(root, unlock_btn, 0.28, 0.60, 0.72, 0.68)
		return
	# 已解锁：三属性 当前→下级
	var pv: Dictionary = _sys().get_facility_preview(fid)
	var bond_name: String = "友好" if str(pv.get("stat", "")) == "friendly" else "才华"
	var stat_rows := [
		"知名度：%d → %d" % [int(pv.get("fame", 0)), int(pv.get("next_fame", 0))],
		"银条收益：%d → %d" % [int(pv.get("income", 0)), int(pv.get("next_income", 0))],
		"%s类挚友%s：%d → %d" % [str(pv.get("cat", "")), bond_name, int(pv.get("bond", 0)), int(pv.get("next_bond", 0))]]
	for i in range(3):
		var rl := Label.new()
		rl.text = stat_rows[i]
		rl.add_theme_font_size_override("font_size", 17)
		rl.add_theme_color_override("font_color", Color("#5a3d26"))
		_place(root, rl, 0.16, 0.36 + i * 0.068, 0.84, 0.42 + i * 0.068)
	if bool(pv.get("maxed", false)):
		var maxed := Label.new()
		maxed.text = "设施已满级"
		maxed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		maxed.add_theme_font_size_override("font_size", 16)
		maxed.add_theme_color_override("font_color", Color("#9a8a76"))
		_place(root, maxed, 0.16, 0.585, 0.84, 0.635)
	else:
		_kv_row(root, 0.16, 0.585, 0.84, 0.625, "消耗：银条", int(_sys().get_yintiao()), int(pv.get("cost", 0)))
		var sync_cb := CheckBox.new()
		sync_cb.text = "同步升级（同项目全部设施各升1级）"
		sync_cb.add_theme_font_size_override("font_size", 14)
		sync_cb.add_theme_color_override("font_color", Color("#5a3d26"))
		_place(root, sync_cb, 0.16, 0.655, 0.84, 0.705)
		var up_btn := Button.new()
		up_btn.text = "升级设施"
		up_btn.custom_minimum_size = Vector2(0, 46)
		var usb := StyleBoxFlat.new()
		usb.bg_color = Color("#c9a050")
		usb.set_corner_radius_all(10)
		for st in ["normal", "hover", "pressed"]:
			up_btn.add_theme_stylebox_override(st, usb)
		up_btn.add_theme_color_override("font_color", Color("#3a2613"))
		up_btn.add_theme_font_size_override("font_size", 18)
		up_btn.disabled = not _sys().can_upgrade_facility(fid).get("ok", false)
		up_btn.pressed.connect(func(): _on_facility_upgrade(fid, str(fcfg.get("project", "")), sync_cb.button_pressed, up_btn))
		_place(root, up_btn, 0.28, 0.75, 0.72, 0.83)

func _on_facility_unlock(fid: String):
	var r := _sys().unlock_facility(fid)
	if not r.get("ok", false):
		c._show_success_popup(str(r.get("msg", "")), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		return
	c._show_success_popup("解锁成功", 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	_refresh()

func _on_facility_upgrade(fid: String, project: String, sync: bool, up_btn: Button = null):
	var r: Dictionary
	if sync:
		r = _sys().upgrade_project(project)
		if r.get("ok", false):
			c._show_success_popup("同步升级：%d 个设施各升 1 级" % int(r.get("count", 0)), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	else:
		r = _sys().upgrade_facility(fid)
		if r.get("ok", false):
			c._show_success_popup("升级成功", 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	if not r.get("ok", false):
		if up_btn != null: c.flash_red(up_btn.get_path())   # 【新增】闪红审计：操作失败反馈（2026-09-19）
		c._show_success_popup(str(r.get("msg", "")), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		return
	_refresh()

# 加号：弹出数量选择器，批量消耗佳酿恢复叫号（不受上限限制，背包不开放）
func _on_add_jiaohao():
	var item: String = data._tavern_configs.get("settings", {}).get("jiaohao_item", "jia_niang")
	var owned: int = int(data.items.get(item, 0))
	if owned <= 0:
		c._show_success_popup("没有【佳酿】", 0.0, "warn")   # 【改】飘字退休→warn 弹窗
		return
	_close_node("TavernPopup")
	_popup_kind = ""   # 道具面板不属于信息/设施弹窗，刷新时不重建
	var give: int = int(data._tavern_configs.get("settings", {}).get("jiaohao_give", 2))
	var popup: PanelContainer = c._create_base_popup("使用佳酿", Vector2(400, 240), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
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
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(90, 34)
	cancel_btn.pressed.connect(func(): _close_node("TavernPopup"))
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(90, 34)
	ok_btn.pressed.connect(func():
		var n: int = int(spin.value)
		data.items[item] = int(data.items.get(item, 0)) - n
		_sys().add_jiaohao(n * give)
		_close_node("TavernPopup")
		# 【改】成功反馈铺开：叫号成功弹窗
		c._show_success_popup("叫号成功\n+%d 位客人" % (n * give))
		_refresh())
	btn_row.add_child(ok_btn)

func _on_collect():
	if not _sys().has_jar():
		# 空罐也允许点击，给红色反馈（disabled 已取消，罐永可点）
		c._show_success_popup("收益罐还是空的", 1.0, "warn")
		return
	var r := _sys().collect_jar()
	# 【改】成功反馈铺开：领取成功弹窗
	c._show_success_popup("领取成功\n银条 +%s" % c.format_number(r))
	_refresh()

# 叫号：1 位客人转入接待队列（接待由定时器批处理）
# 一键叫号勾选落酒肆系统存档：退游重进保持
func _on_call_all_toggled(on: bool):
	_sys().set_auto_call_all(on)
	data.save_game()

# 叫号入口：勾选"一键叫号"→消耗全部体力（call_all），未勾选→消耗一点（call_one）
func _on_call():
	if _call_all_check != null and _call_all_check.button_pressed:
		_on_call_all()
	else:
		_on_call_one()

func _on_call_one():
	var r := _sys().call_one()
	if not r.get("ok", false):
		c._show_success_popup(str(r.get("msg", "")), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		return
	# 【改】成功反馈铺开：叫号成功弹窗
	c._show_success_popup("叫号成功\n接待中")
	_refresh()

# 一键叫号：全部转入接待队列（纯改数字，不卡）
func _on_call_all():
	var r := _sys().call_all()
	if not r.get("ok", false):
		c._show_success_popup(str(r.get("msg", "")), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		return
	c._show_success_popup("已叫号 %d 位客人，接待中…" % int(r.get("count", 0)), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	_refresh()

# 【新增】批次②③④-B1修正：酒肆规则/后台计算说明弹窗（只放说明，不放玩法操作）
func _show_rule_popup():
	_close_node("TavernRulePopup")
	var popup: PanelContainer = c._create_base_popup("酒肆说明", Vector2(380, 300))
	popup.name = "TavernRulePopup"
	popup.get_meta("popup_mask").z_index = 39
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	for line in [
		"门客百业经验：每位客人随机赠予一名已拥有门客。",
		"挚友才艺经验：每位客人随机赠予一名已拥有挚友。",
		"知名度达标即可免费升级酒肆（升级不消耗资源）。",
	]:
		var body := Label.new()
		body.text = line
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(body)

# ---------- 酒肆信息弹窗 ----------

# ---- 自定义画底弹窗（信息/设施专用：全屏遮罩点击关 + 画底 + 右上✕）----
func _place(parent: Control, node: Control, fx0: float, fy0: float, fx1: float, fy1: float) -> void:
	node.anchor_left = fx0
	node.anchor_top = fy0
	node.anchor_right = fx1
	node.anchor_bottom = fy1
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	parent.add_child(node)

# 布局表行 [x0,y0,x1,y1] 版本的 _place（锚点外置后统一走这里）
func _place_rect(parent: Control, node: Control, rect) -> void:
	_place(parent, node, float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))

func _art_popup(bg: Texture2D, popup_size: Vector2) -> Control:
	# 外壳统一走 ui_helpers.art_popup（2026-10-19 抽取：遮罩/居中/自适应/关闭钮/底图铺满）
	# 酒肆只负责自己的 UI_INFO 布局表与内容；药铺/酒坊/妙音坊后续按同法复用
	return c.art_popup(bg, popup_size, "TavernPopup")

# 画底弹窗键值行：左键右值（达不到红/达得到绿）
func _kv_row(parent: Control, fx0: float, fy0: float, fx1: float, fy1: float, key: String, have: int, need: int) -> void:
	var k := Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 16)
	k.add_theme_color_override("font_color", Color("#5a3d26"))
	_place(parent, k, fx0, fy0, fx0 + 0.42, fy1)
	var v := Label.new()
	v.text = "%s / %s" % [c.format_number(have), c.format_number(need)]
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_color_override("font_color", Color("#2e8b57") if have >= need else Color("#c0392b"))
	_place(parent, v, fx1 - 0.32, fy0, fx1, fy1)

func _show_info_popup():
	_close_node("TavernPopup")
	_popup_kind = "info"
	# 尺寸贴合视口：560×469（画底 1543×1293 等比），旧 720 宽会超出 600 设计宽导致裁切错位
	var sz: Vector2 = UI_INFO["popup"]
	var root: Control = _art_popup(INFO_BG, sz)
	# 左卷轴签条：两个字用 VBox 竖直堆叠并居中（Label 带换行时按行居中，容易看着歪）
	var tag_box := VBoxContainer.new()
	tag_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tag_box.add_theme_constant_override("separation", 2)
	_place_rect(root, tag_box, UI_INFO["tag"])
	for ch in ["酒", "肆"]:
		var tl := Label.new()
		tl.text = ch
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", 22)
		tl.add_theme_color_override("font_color", Color("#5a3d26"))
		tag_box.add_child(tl)
	# 招牌 + 改名同一行（改名紧跟名字，别再钉右边撞关闭钮）
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	_place_rect(root, title_row, UI_INFO["title_row"])
	var sign_lbl := Label.new()
	sign_lbl.text = "招牌：%s" % _sys().get_sign_name()
	sign_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sign_lbl.add_theme_font_size_override("font_size", 19)
	sign_lbl.add_theme_color_override("font_color", Color("#4a3018"))
	title_row.add_child(sign_lbl)
	var rename_btn := Button.new()
	rename_btn.text = ""
	rename_btn.icon = ICON_RENAME
	rename_btn.tooltip_text = "改名"
	rename_btn.custom_minimum_size = Vector2(28, 28)
	rename_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rename_btn.add_theme_constant_override("h_separation", 0)
	for st in ["normal", "hover", "pressed", "focus"]:
		rename_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	rename_btn.pressed.connect(_show_rename_popup)
	title_row.add_child(rename_btn)
	var lv := Label.new()
	lv.text = "等级：%d" % _sys().get_level()
	lv.add_theme_font_size_override("font_size", 15)
	lv.add_theme_color_override("font_color", Color("#6b5236"))
	_place_rect(root, lv, UI_INFO["level"])
	var intro_text := str(data._tavern_configs.get("settings", {}).get("intro", ""))
	if intro_text != "":
		var intro := Label.new()
		intro.text = intro_text
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intro.add_theme_font_size_override("font_size", 13)
		intro.add_theme_color_override("font_color", Color("#7a6348"))
		_place_rect(root, intro, UI_INFO["intro"])
	# 画底丝带：接待客人收益
	var ribbon := Label.new()
	ribbon.text = "接待客人收益"
	ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ribbon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon.add_theme_font_size_override("font_size", 19)
	ribbon.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_place_rect(root, ribbon, UI_INFO["ribbon"])
	# 三行收益：银条只显当前；百业/才艺显 当前→下一级（整行居中）
	var lv_next: int = _sys().get_level() + 1
	_info_row(root, float(UI_INFO["row1"]), "银条收益", ICON_YINTIAO, "", c.format_number(_sys().get_income_per_guest()), "")
	_info_row(root, float(UI_INFO["row2"]), "门客百业经验", ICON_BAIYE, "", c.format_number(_sys().get_baiye_per_guest()),
		c.format_number(_sys().get_baiye_per_guest(lv_next)))
	_info_row(root, float(UI_INFO["row3"]), "挚友才艺经验", ICON_CAIYI, "", c.format_number(_sys().get_caiyi_per_guest()),
		c.format_number(_sys().get_caiyi_per_guest(lv_next)))
	# 知名度紧贴升级钮上方（豆姐稿：此处不放进度条，只留一行数值）
	var fame_row := HBoxContainer.new()
	fame_row.add_theme_constant_override("separation", 6)
	fame_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_place_rect(root, fame_row, UI_INFO["fame"])
	var fame_icon := TextureRect.new()
	fame_icon.texture = ICON_FAME
	fame_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fame_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fame_icon.custom_minimum_size = Vector2(22, 22)
	fame_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fame_row.add_child(fame_icon)
	var fame_lbl := Label.new()
	fame_lbl.text = "知名度  %s / %s" % [c.format_number(_sys().get_fame_total()), c.format_number(_sys().get_fame_threshold())]
	fame_lbl.add_theme_font_size_override("font_size", 16)
	# 红绿原则（同消耗行）：达标绿、未达标红
	var fame_enough: bool = int(_sys().get_fame_total()) >= int(_sys().get_fame_threshold())
	fame_lbl.add_theme_color_override("font_color", Color("#2e8b57") if fame_enough else Color("#c0392b"))
	fame_row.add_child(fame_lbl)
	var up := Button.new()
	var up_sb := StyleBoxFlat.new()
	up_sb.bg_color = Color("#c9a050")
	up_sb.border_color = Color("#9a7433")
	up_sb.set_border_width_all(2)
	up_sb.set_corner_radius_all(8)
	var up_hover: StyleBoxFlat = up_sb.duplicate()
	up_hover.bg_color = Color("#dcb463")
	for st in ["normal", "pressed"]:
		up.add_theme_stylebox_override(st, up_sb)
	up.add_theme_stylebox_override("hover", up_hover)
	up.add_theme_stylebox_override("focus", up_sb)
	up.add_theme_color_override("font_color", Color("#3a2613"))
	up.add_theme_font_size_override("font_size", 20)
	if _sys().get_level() >= int(_sys().get_max_level()):
		up.text = "已满级"
		up.disabled = true
	else:
		up.text = "升级"
		up.disabled = not _sys().can_level_up().get("ok", false)
		up.pressed.connect(_on_level_up)
	_place_rect(root, up, UI_INFO["button"])

# 信息弹窗收益行：图标或字牌 + 名称 + 当前值（可选 → 下一级）
func _info_row(root: Control, y0: float, title_text: String, icon: Texture2D, badge: String, cur_text: String, next_text: String) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_place(root, row, float(UI_INFO["rows_box"][0]), y0, float(UI_INFO["rows_box"][1]), y0 + float(UI_INFO["row_h"]))
	if icon != null:
		var ir := TextureRect.new()
		ir.texture = icon
		ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ir.custom_minimum_size = Vector2(24, 24)
		ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ir)
	elif badge != "":
		var bl := Label.new()
		bl.text = badge
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bl.custom_minimum_size = Vector2(24, 24)
		bl.add_theme_font_size_override("font_size", 13)
		bl.add_theme_color_override("font_color", Color("#f0e6d2"))
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("#8a6a45")
		bs.set_corner_radius_all(12)
		bl.add_theme_stylebox_override("normal", bs)
		row.add_child(bl)
	var l := Label.new()
	l.text = title_text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("#5a3d26"))
	row.add_child(l)
	var v := Label.new()
	v.text = cur_text
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", Color("#3f2a15"))
	row.add_child(v)
	if next_text != "":
		var ar := Label.new()
		ar.text = "→ " + next_text
		ar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ar.add_theme_font_size_override("font_size", 17)
		ar.add_theme_color_override("font_color", Color("#2e8b57"))
		row.add_child(ar)

func _show_rename_popup():
	_close_node("TavernPopup")
	var popup: PanelContainer = c._create_base_popup("修改招牌", Vector2(400, 200), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
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
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(90, 34)
	cancel_btn.pressed.connect(func(): _refresh())   # 取消也回信息弹窗
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(90, 34)
	# 确定后回信息弹窗：_popup_kind 仍为 info，_refresh 会重建信息弹窗
	ok_btn.pressed.connect(func():
		var r := _sys().rename_sign(edit.text)
		if not r.get("ok", false):
			c._show_success_popup(str(r.get("msg", "")), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
			return
		_refresh())
	btn_row.add_child(ok_btn)

func _on_level_up():
	var r := _sys().level_up()
	if not r.get("ok", false):
		c._show_success_popup(str(r.get("msg", "")), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		return
	c._show_success_popup("酒肆升级：Lv.%d" % _sys().get_level(), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	_refresh()
