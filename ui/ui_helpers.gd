# ============================================================
# 《大掌柜》UI 助手设施（2026-09-19 架构重构批次B，自 game_controller.gd 原样迁出）
# 职责：弹窗三件套（工厂/二次居中/OK按钮/滑条数字对）/ 通用关闭 / 主题样式动画 /
#       顶部提示 / 成功·警告结果弹窗 / 赚速·门客赚钱徽标（飘字已退休 2026-10-02） / 数量选择器
#       弹窗皮肤三件套（2026-10-17 批次：羊皮纸九切片框体/金匾标题/灯笼关闭钮，全部弹窗工厂一处切）
# 约定（与 ui/net_ui.gd 相同）：
#   · 本类是 RefCounted 不是 Node——节点树操作（has_node/get_node/add_child/find_children/
#     get_viewport*/get_tree/create_tween）必须经 c 转发；弹窗/提示挂 c 根节点 z 序才有效；
#   · 对 controller 其它设施（data/数量选择器状态 _quantity_item_id/format_number）一律 c.xxx；
#   · 块内互调（本文件函数之间）直接本地调用。controller 留同名一行委托，全部调用点零改动。
# ============================================================
class_name UiHelpers
extends RefCounted

var c   # game_controller 根脚本（无类型，与 pages 模块一致）
var _popup_gen: int = 0   # 【新增】成功反馈：成功弹窗代际号（连点顶替时关闭校验用，lambda 只捕获 int 防 freed 警告）

var _last_total_income: int = -1   # 【新增】全局赚速飘字：上次总赚速快照（-1=未初始化，首次只记录不弹）
var _income_float_state := {"tween": null, "display": 0.0, "target": 0}   # 【新增】赚速飘字状态：动画引用/滚动显示值/累计目标增量（连点累加，飘尽归零）
var _hero_income_snapshot: Dictionary = {}   # 【新增】门客赚钱飘字：每个已拥有门客的赚钱快照 {hero_id: income}（首次建档不弹）
var _hero_float_state := {"tween": null, "display": 0.0, "target": 0}   # 【新增】门客赚钱飘字状态（同赚速飘字结构）

# 【改】弹窗统一批次（2026-11-03 第七章）：窗框素材换回原作 Basic3.Frame1 的 NinePatchRect 原件（747×600），
#      预缩放成 576×463 入库 popup_frame_uni.png；匾/飞檐/底座/绿植全部烘焙进整图，不再叠贴片，只剩右上灯笼一张
# 【改】2026-11-04 用户拍板：统一窗尺寸改成和「仪容技能」窗（ui/pages/friend_looks_fgui_view.gd，实测 600×625）一样大。
#      原 576×760 竖向几乎铺满整屏、短内容大片留白；内容超出固定窗时改「上下滚动（滚动条一律隐藏）」，
#      不再等比缩放整窗（缩放会把字缩糊）。实现见本文件 PopupScrollPanel。
const POPUP_W := 576.0        # 统一窗宽（600 宽逻辑视口下的固定值；更窄视口按 vs.x-16 再收）
const POPUP_H := 625.0        # 统一窗高（= 仪容技能窗基准 600×625 的高度；竖向多出的高度只拉伸羊皮纸中段）
const POPUP_PAD_L := 46.0     # stylebox 内容左边距：框内实测 x27~36=金边、37~48=毛边纸毛口，正文从 49 起才干净
const POPUP_PAD_R := 46.0     # 右缘对称（x534~545 是右侧毛口）→ 内容净宽 = 576-92 = 484
const POPUP_PAD_T := 62.0     # 顶梁下沿 = 0.771×66 ≈ 51，再让 11px 给匾底投影
const POPUP_PAD_B := 90.0     # 停在底部风景画带（625 窗下画带从 y≈542 起）之上，正文不压画
var _popup_skin_frame: Texture2D = null   # 窗框整图（576×463，九切片用）
var _popup_skin_corner_r: Texture2D = null   # 右上灯笼整块原画（挂关闭钮子节点）

func _init(p_c):
	c = p_c

# 【新增】弹窗皮肤批次（2026-10-17）：金匾上的可视标题——
# 契约标题 Label（vbox 下标0、名 PopupTitle）必须留在内容流供原地重建类按名改写；但匾贴片是面板后绘制子节点，
# 内容流会被压在匾下面——故契约标题隐藏占位，本标签每帧对账镜像 text/水平对齐，调用方与既有契约零感知
class PlaqueTitleLabel:
	extends Label

	var source: Label = null

	func _process(_dt):
		if source == null or not is_instance_valid(source):
			set_process(false)
			return
		if text != source.text:
			text = source.text
		if horizontal_alignment != source.horizontal_alignment:
			horizontal_alignment = source.horizontal_alignment

# 【新增】第七章滚动批次（2026-11-04 用户拍板）：固定窗 + 内容超高改上下滚动、滚动条一律隐藏。
# 为什么不用 PanelContainer 当窗根：实测 PanelContainer 的尺寸下限 = 窗框最小尺寸 + 内容最小尺寸
# （C++ 的 get_minimum_size 不理会脚本覆写；把 size 压小也会被立刻打回 940×970），内容一长窗就跟着长，
# 「固定尺寸」根本保不住。故窗根改成自定义 Container：自己画 StyleBox 窗框、自己算内容矩形
# （取 stylebox 的 content_margin，与旧 PanelContainer 完全一致）、
# body（= child 0，全仓 200 处 get_child(0) 契约不变）超高时按 scroll_y 上移；
# 根节点 clip_contents 裁掉窗外部分，内容矩形外的上下带由 PopupBandMask 补画窗框盖住。
class PopupScrollPanel:
	extends Container

	const STEP := 64.0   # 一格滚轮滚多少像素

	var body: Control = null        # 内容体（= child 0）
	var band_mask: Control = null   # 上下遮挡带（内容溢出时才显示）
	var scroll_y: float = 0.0
	var overflow: float = 0.0
	var avail_w: float = 0.0
	var avail_h: float = 0.0
	var _dragging: bool = false
	var _fit_tick: int = 0   # 横向自愈扫描节流计数

	func _ready() -> void:
		clip_contents = true   # 内容超出内容矩形时靠根裁剪（滚动条不出现，符合「滚动条一律隐藏」）
		set_process(true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAW:
			var sb := get_theme_stylebox("panel")
			if sb != null:
				draw_style_box(sb, Rect2(Vector2.ZERO, size))
		elif what == NOTIFICATION_SORT_CHILDREN:
			_layout_children()

	func _process(_dt: float) -> void:
		# 内容多是 add_child 之后才塞进来（列表/网格/提示），Container 的排序通知不一定每次都到；
		# 每帧对一遍账（尺寸相同即零写入，不会引发重排循环），autowrap 文字重排也能跟着修正高度
		_layout_children()

	func _layout_children() -> void:
		var sb := get_theme_stylebox("panel")
		if sb == null:
			return
		var pl := sb.get_content_margin(SIDE_LEFT)
		var pt := sb.get_content_margin(SIDE_TOP)
		var pr := sb.get_content_margin(SIDE_RIGHT)
		var pb := sb.get_content_margin(SIDE_BOTTOM)
		avail_w = maxf(8.0, size.x - pl - pr)
		avail_h = maxf(8.0, size.y - pt - pb)
		if body != null:
			# 【新增】第七章滚动批次（2026-11-04）：固定窗宽 576（内容净宽 484）后，超宽的说明文字会被窗框硬裁。
			# 这里在「横向溢出」时把该 Label 改成自动换行（只动真正超宽的那几个，标题/短文案零影响）——
			# 换行后它的最小宽缩到一行字宽，纵向由滚动兜住，不再出现「字被切掉一半」。
			# 每 6 帧扫一次即可（文案是事后填的，最多晚 0.1 秒换行），避免每帧 find_children 造成无谓开销
			_fit_tick += 1
			if _fit_tick % 6 == 1:
				_fit_width(avail_w)
			var need := body.get_combined_minimum_size()
			var w := maxf(avail_w, need.x)
			if not is_equal_approx(body.size.x, w):
				body.size.x = w
				need = body.get_combined_minimum_size()   # 宽变了要重算（autowrap 的文字会重排）
			overflow = maxf(0.0, need.y - avail_h)
			scroll_y = clampf(scroll_y, 0.0, overflow)
			var h := maxf(avail_h, need.y)
			if not is_equal_approx(body.size.y, h):
				body.size.y = h
			var want := Vector2(pl, pt - scroll_y)
			if not body.position.is_equal_approx(want):
				body.position = want
		# 其余子节点（✕ 层 / 匾标题）铺满内容矩形——完全复刻 PanelContainer 的排布基准：
		# 它们的坐标都是「内容矩形系」的写死偏移，基准一变全部歪掉
		for ch in get_children():
			var cc := ch as Control
			if cc == null or cc == body or cc == band_mask:
				continue
			cc.position = Vector2(pl, pt)
			cc.size = Vector2(avail_w, avail_h)
		if band_mask != null:
			band_mask.position = Vector2.ZERO
			band_mask.size = size
			band_mask.visible = overflow > 0.0

	# 【新增】横向自愈：只对「最小宽超过内容净宽」且没开换行的 Label 动手（开了换行的本身不会再超宽）
	func _fit_width(w: float) -> void:
		for n in body.find_children("*", "Label", true, false):
			var lb := n as Label
			if lb == null or lb.autowrap_mode != TextServer.AUTOWRAP_OFF:
				continue
			if lb.get_combined_minimum_size().x > w:
				lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	func _scroll_by(dy: float) -> void:
		if overflow <= 0.0:
			return
		scroll_y = clampf(scroll_y + dy, 0.0, overflow)
		_layout_children()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_scroll_by(-STEP)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_scroll_by(STEP)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed   # 左键按住空白处上下拖（点按钮时按钮自己吃输入，不会走到这里）
		elif ev is InputEventMouseMotion and _dragging:
			var mm := ev as InputEventMouseMotion
			if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_scroll_by(-mm.relative.y)
		elif ev is InputEventScreenDrag:
			_scroll_by(-(ev as InputEventScreenDrag).relative.y)   # 触摸拖动
		elif ev is InputEventPanGesture:
			_scroll_by((ev as InputEventPanGesture).delta.y * STEP)

# 【新增】上/下遮挡带：根节点只裁到窗边，裁不到「内容矩形」以外——滚动时内容会画到顶梁/底座上。
# 这里把窗框贴图的上 PAD_T 行、下 PAD_B 行按原图像素重画一遍盖住（这两带在九切片里 1:1 不缩放，
# 所以与原图逐像素一致）；仅内容溢出时显示，常态完全不影响画面。
class PopupBandMask:
	extends Control

	var tex: Texture2D = null
	var pad_t: float = 0.0
	var pad_b: float = 0.0

	func _draw() -> void:
		if tex == null:
			return
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		if pad_t > 0.0:
			draw_texture_rect_region(tex, Rect2(0.0, 0.0, size.x, pad_t), Rect2(0.0, 0.0, tw, pad_t))
		if pad_b > 0.0:
			draw_texture_rect_region(tex, Rect2(0.0, size.y - pad_b, size.x, pad_b), Rect2(0.0, th - pad_b, tw, pad_b))

# ============ 弹窗工厂三件套 + 通用关闭（原 controller 924~933 行区域） ============

# 【新增】全屏遮罩：压暗背景并挡住弹窗期间切换页面/误触后台（z=25 低于弹窗 30、高于页面）；
#  引用挂在 panel 的 meta 上，由 _safe_close 连带摘除，113 处调用零改动
func _create_base_popup(title_text: String, popup_size: Vector2, _pos: Vector2 = Vector2.ZERO, with_close: bool = true, decorated: bool = true) -> Control:   # _pos 已废弃：一律居中（保留参数兼容旧调用）；with_close=false=确认弹窗不带右上✕（范式§十一.8）；decorated=false=素面弹窗（暗底、无匾无灯笼、不补【确定】；2026-11-04 第七章统一后已无调用点，规则说明也改走装饰窗，保留仅为兼容）
	var mask = ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.55)
	mask.z_index = 25
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(mask)
	# 【修】anchors 预设在不吃布局的父节点上会退化成 0 尺寸，显式铺满视口
	mask.position = Vector2.ZERO
	mask.size = c.get_viewport_rect().size

	# 【改】第七章滚动批次（2026-11-04）：窗根用自定义 Container（自绘窗框 + 自己算内容矩形 + 内容超高上下滚），
	#  PanelContainer 做不到固定高度（它的下限含内容最小尺寸，见 PopupScrollPanel 类注释）
	var panel := PopupScrollPanel.new()
	panel.set_meta("popup_mask", mask)
	# 【新增】遮罩跟随弹窗生命周期：任何关闭路径（含直接 queue_free 绕过 _safe_close）都能摘掉遮罩
	panel.tree_exiting.connect(_on_popup_tree_exiting.bind(mask))
	# 【改】竖屏适配：弹窗尺寸钳制不超视口（四周留边）；写死的位置也钳制在屏幕内不出界
	# 【改】弹窗统一批次（2026-11-03 第七章 7.4 落码）：装饰弹窗一律固定尺寸——不随调用方传值/内容变高矮；
	#      decorated 分支忽略 popup_size（签名与 166 处传参保留，迁移零改动），素面规则弹窗仍按传入值钳制
	var vs = c.get_viewport_rect().size
	if decorated:
		# 宽就用窗框贴图原宽 576：九切片中段不被挤扁、匾额正好居中；只有比视口更小的屏幕才等比缩
		popup_size = Vector2(minf(POPUP_W, vs.x - 8.0), minf(POPUP_H, vs.y - 24.0))
	else:
		popup_size = Vector2(minf(popup_size.x, vs.x - 40), minf(popup_size.y, vs.y - 80))
	panel.custom_minimum_size = popup_size
	panel.set_meta("popup_target", popup_size)   # 巡检用：_recenter_popup 里对比真实尺寸，超窗即报（见第七章自检）
	panel.set_meta("popup_decorated", decorated)   # 供 _recenter_popup 补做「后建内容」的字色/横滚统一
	# 【改】一律居中，忽略 pos 参数——旧 pos 全是横屏 1152×648 写死的坐标，
	#       钳制只能保证不出界、弹窗会贴边歪斜（30+处调用的 pos 都已失效，参数保留不删省得改签名）
	panel.position = (vs - popup_size) / 2
	panel.z_index = 30
	# 【新增】内容把面板撑大时按真实尺寸二次居中（custom_minimum_size 只是下限，不是实际尺寸）
	panel.ready.connect(_recenter_popup.bind(panel))

	if decorated:
		# 【新增】弹窗皮肤批次（2026-10-17 用户拍板）：国风羊皮纸框体替暗色底板——九切片
		# （角帽=飞檐/石板座原大不拉伸，中间羊皮纸随弹窗尺寸伸缩）；面板默认字体色改深棕（米白纸底，金字不可读）
		if _popup_skin_frame == null:
			# 原作窗框：Basic3.Frame1 的 NinePatchRect 原件（747×600）预缩放到 576×463 入库。
			# 九切片角块是 1:1 绘制不缩放的，若直接给未缩放原件设边距，会出现「角块比中段大 30%」的接缝
			_popup_skin_frame = load("res://assets/common/popup_frame_uni.png")
			_popup_skin_corner_r = load("res://assets/common/popup_corner_r.png")
		var skin := StyleBoxTexture.new()
		skin.texture = _popup_skin_frame
		# 九切片边距 = 原件 (左188/上130/右188/下195) × s（s=576/747=0.771）：左右切到金边内侧，
		# 上下切到横梁/底座为止；中间那块是纯羊皮纸竖渐变，随弹窗高度拉伸肉眼不可辨
		skin.texture_margin_left = 145
		skin.texture_margin_right = 145
		skin.texture_margin_top = 100
		skin.texture_margin_bottom = 150
		skin.content_margin_left = POPUP_PAD_L
		skin.content_margin_right = POPUP_PAD_R
		skin.content_margin_top = POPUP_PAD_T
		skin.content_margin_bottom = POPUP_PAD_B
		panel.add_theme_stylebox_override("panel", skin)
		panel.add_theme_color_override("font_color", Color("#3a2613"))
		# 【新增】弹窗按钮统一绿意（2026-10-17 用户拍板）：主题挂面板，后代 Button 全体生效（调用方显式覆写者除外）
		var btn_theme := Theme.new()
		var sb_btn_n := StyleBoxFlat.new()
		sb_btn_n.bg_color = Color("#4a9e5c")
		sb_btn_n.set_corner_radius_all(8)
		var sb_btn_h := StyleBoxFlat.new()
		sb_btn_h.bg_color = Color("#57b56c")
		sb_btn_h.set_corner_radius_all(8)
		var sb_btn_p := StyleBoxFlat.new()
		sb_btn_p.bg_color = Color("#3d8450")
		sb_btn_p.set_corner_radius_all(8)
		var sb_btn_d := StyleBoxFlat.new()
		sb_btn_d.bg_color = Color("#a9b5aa")
		sb_btn_d.set_corner_radius_all(8)
		btn_theme.set_stylebox("normal", "Button", sb_btn_n)
		btn_theme.set_stylebox("hover", "Button", sb_btn_h)
		btn_theme.set_stylebox("pressed", "Button", sb_btn_p)
		btn_theme.set_stylebox("disabled", "Button", sb_btn_d)
		btn_theme.set_stylebox("focus", "Button", sb_btn_h)
		# 字色进主题而非面板覆盖——Godot4 的 add_theme_color_override 不传子节点，theme 类型项才传播（动态建的标签免疫白字）
		btn_theme.set_color("font_color", "Label", Color("#3a2613"))
		btn_theme.set_color("font_color", "LineEdit", Color("#3a2613"))
		btn_theme.set_color("font_color", "RichTextLabel", Color("#3a2613"))
		btn_theme.set_color("font_color", "Button", Color("#ffffff"))
		btn_theme.set_color("font_hover_color", "Button", Color("#ffffff"))
		btn_theme.set_color("font_pressed_color", "Button", Color("#e8f5ec"))
		btn_theme.set_color("font_disabled_color", "Button", Color("#f0f0f0"))
		panel.theme = btn_theme
	else:
		var style = StyleBoxFlat.new()
		# 【改】底色提亮一档（原 #1e1b2e 与全屏门客面板同色，弹窗会融进背景）
		style.bg_color = Color("#2a2640")
		style.set_corner_radius_all(12)
		# 【新增】2px 淡紫描边，弹窗边界一眼可辨（想换金色描边就改成 "#a8893f"）
		style.set_border_width_all(2)
		style.border_color = Color("#6a5f9e")
		panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	# 内容垂直居中（皮肤批次曾改顶对齐，实测短内容偏上、底部大片空；匾标题是 overlay 不吃对齐，居中无影响）
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	if decorated:
		vbox.z_index = 1   # 内容抬到装饰层之上：匾/飞檐/灯笼/底座贴片先画、内容后盖，杜绝"组件啃内容角"（z 只管绘制序；点击区在内容矩形右缘外不受影响）
	vbox.add_theme_constant_override("separation", 12)
	# 【新增】第七章滚动批次：滚轮/触摸拖动要冒泡到窗根才滚得动，容器默认 STOP 会吞掉（PASS 只让事件往上走，不影响点击）
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(vbox)
	panel.body = vbox   # 窗根按 stylebox 内容矩形排版它（= child 0，全仓 200 处 get_child(0) 契约不变）
	if decorated:
		# 【新增】第七章滚动批次：滚动内容会画到顶梁/底座上（根只裁到窗边），这层补画窗框上下带盖住；
		# z=2 压住内容(z=1)，✕/匾(z=3)仍在其上；仅内容溢出时可见
		var band := PopupBandMask.new()
		band.name = "PopupBandMask"
		band.tex = _popup_skin_frame
		band.pad_t = POPUP_PAD_T
		band.pad_b = POPUP_PAD_B
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.z_index = 2
		band.visible = false
		panel.add_child(band)
		panel.band_mask = band

	# 【改】UI统一批次①补充：标题回到内容流第一个子节点（随内容整体居中，同旧行为）；
	#       with_close=true 时空标题也建命名 Label——原地重建类弹窗（厢房/庄园/钓点）按名 PopupTitle 改标题、
	#       清空重建保留下标0；确认弹窗（with_close=false）不带✕、遮罩点击不关闭（必须点按钮做选择）
	var title: Label = null
	if with_close or title_text != "":
		title = Label.new()
		title.name = "PopupTitle"
		title.text = title_text
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color("#ffd700"))
		if decorated:
			title.visible = false   # 【新增】皮肤批次：契约标题隐藏占位（原地重建类按名 PopupTitle 改写的仍是它），匾上可视标题=镜像标签
		vbox.add_child(title)
	
	var overlay: Control = null
	if with_close:
		# 【改】✕ 总关闭钮改悬浮层钉右上角（原 vbox 顶行方案作废：vbox 整体垂直居中，内容少时✕浮在半空）——
		#       x_layer 是 PanelContainer 子节点被容器拉伸满幅（项目既有行为）、IGNORE 不挡点击、后绘制压内容之上；
		#       ✕ 锚定右上角，随面板尺寸/二次居中自动贴角，z 随面板被调用方提升
		var x_layer = Control.new()
		x_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		x_layer.z_index = 3   # 【新增】第七章滚动批次：压在上下遮挡带(z=2)之上，滚动时✕/灯笼始终可见
		panel.add_child(x_layer)
		var close_x = Button.new()
		close_x.name = "PopupCloseX"
		close_x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		close_x.mouse_filter = Control.MOUSE_FILTER_STOP   # 显式STOP：必须吃点击（PASS会把点击让出去）
		# 无底空钮：四态空底板，视觉/字形随皮肤分支
		var empty_sb = StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus"]:
			close_x.add_theme_stylebox_override(st, empty_sb)
		if decorated:
			# 【新增】皮肤批次：右上角灯笼=关闭钮（红 X 已画在灯笼图里），透明 hit 区盖灯罩、无字；
			# 灯笼挂按钮子节点而非兄弟——厢房命格对比按名摘 PopupCloseX 时灯笼随之销毁，杜绝"看的不能点"死饵
			close_x.text = ""
			# 【改】弹窗统一批次：窗框自带右上绿植，灯笼改挂梁下右缘内侧（原作 Basic3.Frame1 同位）。
			# 坐标基准=内容矩形（panel = 内容 + (30,62)）：内容右缘 = panel(W-30) → pos_x -50 = panel(W-80)；
			# hit 区只盖灯罩 42×100，不整块铺开，避免挡住内容区右上角的可点控件
			close_x.position = Vector2(-50, 8)
			close_x.size = Vector2(42, 100)
			var corner_r = TextureRect.new()
			corner_r.name = "PopupCornerR"
			corner_r.texture = _popup_skin_corner_r
			corner_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			corner_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 【改】原作灯笼是暖琥珀色，我们的贴图偏奶白 → 乘一层暖色把它压成原作那口气
			corner_r.self_modulate = Color(1.0, 0.93, 0.78)
			# 整块原画（绳+叶+灯+穗，零抠图）：从 hit 区 (-22,-52) 铺开 87×232 → panel(W-102,18) 起，右缘留 15px 在框内；
			# 挂按钮子节点——厢房命格对比按名摘 PopupCloseX 时整块随之销毁，杜绝死饵
			corner_r.position = Vector2(-22, -52)
			corner_r.size = Vector2(87, 232)
			close_x.add_child(corner_r)
		else:
			close_x.text = "×"   # 【改】✕(U+2715) 不在 Noto Sans SC 字形内，×(U+00D7 Latin-1) 才有——关闭钮的 X 不用赌源字体覆盖
			close_x.position = Vector2(-44, 8)   # 相对右上角：右留8px、上留8px
			close_x.size = Vector2(36, 36)
			close_x.add_theme_color_override("font_color", Color("#ff6666"))
			close_x.add_theme_color_override("font_hover_color", Color("#ff9999"))
			close_x.add_theme_color_override("font_pressed_color", Color("#ff4444"))
			close_x.add_theme_font_size_override("font_size", 20)
		close_x.pressed.connect(panel.queue_free)   # 关自己：遮罩走 tree_exiting 连带清理，无需按名
		x_layer.add_child(close_x)
		overlay = x_layer
	if decorated:
		# 【改】弹窗统一批次（2026-11-03 第七章）：金匾/左上飞檐/左下右下底座已烘焙进窗框整图，
		# 这里不再建贴片，只留「匾上可视标题」——overlay 是普通 Control（PanelContainer 把它拉到内容矩形），
		# 不吃内容流排布，坐标基准=内容矩形，负偏移即落到框梁上
		if overlay == null:
			overlay = Control.new()
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.z_index = 3   # 【新增】第七章滚动批次：同 x_layer，压在遮挡带之上
			panel.add_child(overlay)
		var plaque_title := PlaqueTitleLabel.new()
		plaque_title.name = "PlaqueTitleVisible"
		plaque_title.source = title
		plaque_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plaque_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# 匾面是暗金底 (~120,104,71)，旧 22 号深棕字在上面读不出 → 浅描金字 + 1px 深投影（原作匾字就是亮色）
		plaque_title.add_theme_font_size_override("font_size", 17)
		plaque_title.add_theme_color_override("font_color", Color("#f6e6bb"))
		plaque_title.add_theme_color_override("font_shadow_color", Color(0.24, 0.17, 0.08, 0.75))
		plaque_title.add_theme_constant_override("shadow_offset_x", 0)
		plaque_title.add_theme_constant_override("shadow_offset_y", 1)
		plaque_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 匾面实测 = popup x 191~375 / y 6~37；取 184×30 居中到 panel x 288 → 内容矩形系 (-30,-62)
		plaque_title.position = Vector2(166, -55)
		plaque_title.size = Vector2(184, 30)
		overlay.add_child(plaque_title)
	if with_close or not decorated:
		# 【新增】遮罩点击关闭（2026-09-25 用户拍板；确认弹窗不启用——必须点【取消/确定】明确选择；
		#       2026-10-17 皮肤批次：素面弹窗无✕，点任意处关闭也走这里）
		mask.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				panel.queue_free()
		)
		if with_close and decorated:
			# 【新增】纯信息弹窗自动补底部【确定】（2026-09-25 用户拍板）：等两帧内容建完再扫描
			#       （2026-10-17 皮肤批次：仅装饰版补——素面规则弹窗点击任意处即关，不补确定钮）
			panel.ready.connect(_auto_add_ok_button.bind(panel))
	if decorated:
		# 【新增】弹窗皮肤批次（2026-10-17 用户拍板）：装饰版弹窗一律禁横向滚动——超宽内容容器内自缩，不出横滚条
		panel.ready.connect(_disable_h_scroll.bind(panel))
		# 【新增】浅色显式字色→深棕：只作用于弹窗子树（页内同构建器实例不受影响，解决深底/parchment 双色复用）
		panel.ready.connect(_adapt_popup_contrast.bind(panel))

	return panel

# 【新增】弹窗二次居中：等两帧布局完成后按真实 size 居中。
# 解决内容最小尺寸大于声明 popup_size 时（如长列表/宽网格撑大面板），按声明尺寸居中导致的偏移
func _recenter_popup(panel: Control):
	await c.get_tree().process_frame
	await c.get_tree().process_frame
	if not is_instance_valid(panel): return
	var vs = c.get_viewport_rect().size
	# 【改】第七章滚动批次（2026-11-04 用户拍板）：窗根是自定义 Container，尺寸被钉死在固定值上
	#   （内容超高改上下滚动，见 PopupScrollPanel），不会再被内容撑大 → 这里只做居中，不再等比缩放整窗
	panel.position = ((vs - panel.size) / 2).max(Vector2(8, 8))  # 钳个最小边距，小屏上也不至于顶出左上
	# 【新增】第七章（2026-11-04）：ready 时扫描只覆盖「创建前就建好的」内容——绝大多数弹窗是
	#   add_child 之后才往里塞控件（列表/网格/提示），ready 那趟全漏掉，深底时代的近白字在羊皮纸上发虚。
	#   这里等两帧布局完成后再统一扫一遍（同一套判定：亮且低饱和→深棕），后建内容也一并救回。
	if panel.get_meta("popup_decorated", false):
		_disable_h_scroll(panel)
		_adapt_popup_contrast(panel)
		_make_scroll_friendly(panel)   # 【新增】第七章滚动批次：非交互容器改 PASS，滚轮才冒泡到窗根
	# 【新增】第七章自检（仅 debug 构建）：内容超出固定窗时打一行日志（已自动改为上下滚动）；
	#   横向超出是「会被窗框裁掉」的硬伤，单独报出来指出该收窄哪个调用方
	if OS.is_debug_build() and panel is PopupScrollPanel:
		var psp := panel as PopupScrollPanel
		var tname := ""
		if psp.body != null and psp.body.get_child_count() > 0 and psp.body.get_child(0) is Label:
			tname = (psp.body.get_child(0) as Label).text
		if psp.overflow > 0.0:
			print("[popup] 内容超高→上下滚动 title=%s 内容区=%dx%d 溢出=%.0f" % [tname, int(psp.avail_w), int(psp.avail_h), psp.overflow])
		if psp.body != null:
			var need_w := psp.body.get_combined_minimum_size().x
			if need_w > psp.avail_w + 1.0:
				print("[popup] 内容超宽（会被窗框裁掉，需收窄调用方）title=%s 内容宽=%d 上限=%d" % [tname, int(need_w), int(psp.avail_w)])

# 【新增】纯信息弹窗自动补底部【确定】（2026-09-25 用户拍板）：等两帧内容建完后扫描内容区，
# 一个动作钮都没有（纯展示）才在底部补【确定】（=queue_free，与✕/遮罩点击同路径）；
# 有使用/升级/列表按钮的弹窗不补；CheckBox/CheckButton 勾选框不算动作钮
# 【新增】弹窗皮肤批次（2026-10-17 用户拍板）：弹窗子树内浅色显式字色统一改深棕——
# 深底色时代留的灰/薰衣草字在羊皮纸上发虚；按解析后实际字色判定（亮度高且低饱和才改），金/红/绿等彩色字不动。
# 只走弹窗子树：同一份卡片构建器在全屏页（深底）里的实例不受影响。限制：原地重建类弹窗重建后的新标签不覆盖（撞见再静态修）。
func _adapt_popup_contrast(panel: Control):
	for lbl in panel.find_children("*", "Label", true, false):
		if lbl.name == "PlaqueTitleVisible":
			continue   # 匾上标题本就该亮（暗金底亮字），别被下面的「浅色改深棕」规则吃掉
		var col = lbl.get_theme_color("font_color")
		var mx = maxf(col.r, maxf(col.g, col.b))
		var mn = minf(col.r, minf(col.g, col.b))
		if (mx + mn) * 0.5 > 0.45 and (mx - mn) < 0.35 * mx:
			lbl.add_theme_color_override("font_color", Color("#5a3d26"))

# 【新增】弹窗皮肤批次（2026-10-17 用户拍板）：装饰版弹窗内全部 ScrollContainer 禁横滚（防内容超宽出横滚条；动态后建的列表需调用方自行禁）
# 【改】第七章滚动批次（2026-11-04 用户拍板「滚动条一律隐藏」）：竖滚条也改 SHOW_NEVER——
#   滚动照常可用，只是不画条也不占位（与 popup_scroll 既有范式一致）
func _disable_h_scroll(panel: Control):
	for sc in panel.find_children("*", "ScrollContainer", true, false):
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER

# 【新增】第七章滚动批次（2026-11-04）：滚轮/拖动要能冒泡到窗根（PopupScrollPanel._gui_input 收滚轮/触摸拖动），
# 但 PanelContainer 等普通容器默认 STOP 会把事件吃掉。这里把弹窗子树里的「非交互容器」统一改 PASS：
#   · Button/ScrollContainer/输入框/滑块/列表/树 —— 一律不动（它们自己要吃输入）；
#   · 纯装饰的 Label/TextureRect → IGNORE（直接穿透，连 hover 都不吃）；
#   · 其余容器 STOP → PASS（只让事件继续往上走，点击命中与层级完全不变）。
# 有 gui_input 连接的节点视为「交互件」保持原样，避免把可点的图/字改成穿透。
func _make_scroll_friendly(panel: Control):
	for node in panel.find_children("*", "Control", true, false):
		if node is BaseButton or node is ScrollContainer or node is LineEdit or node is TextEdit:
			continue
		if node is Range or node is TabBar or node is ItemList or node is Tree:
			continue
		var cc := node as Control
		var interactive := not cc.gui_input.get_connections().is_empty()
		if node is Label or node is TextureRect:
			if not interactive:
				cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		elif cc.mouse_filter == Control.MOUSE_FILTER_STOP and not interactive:
			cc.mouse_filter = Control.MOUSE_FILTER_PASS

func _auto_add_ok_button(panel: Control):
	await c.get_tree().process_frame
	await c.get_tree().process_frame
	if not is_instance_valid(panel): return
	var vbox = panel.get_child(0)
	if _has_action_button(vbox): return
	var ok_btn = Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(120, 40)
	ok_btn.pressed.connect(panel.queue_free)
	vbox.add_child(ok_btn)

# 【新增】递归扫描弹窗内容区是否已有动作钮（排除纯勾选控件），供自动补【确定】判定
func _has_action_button(node: Node) -> bool:
	for child in node.get_children():
		if child is BaseButton and not (child is CheckBox or child is CheckButton):
			return true
		if _has_action_button(child):
			return true
	return false

func _add_ok_button(parent: Node, callback: Callable, text: String = "确定") -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 36)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _create_slider_spin_pair(parent: Node, max_val: int, min_val: int = 1) -> Dictionary:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = min_val
	slider.custom_minimum_size = Vector2(180, 30)
	hbox.add_child(slider)

	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = min_val
	hbox.add_child(spin)

	slider.value_changed.connect(spin.set_value)
	spin.value_changed.connect(slider.set_value)

	return {"slider": slider, "spin": spin, "hbox": hbox}

func _safe_close(node_name: String):
	if c.has_node(node_name):
		var node = c.get_node(node_name)
		# 【新增】连带摘除弹窗遮罩（_create_base_popup 创建时挂在 meta 上）
		if node.has_meta("popup_mask"):
			var mask = node.get_meta("popup_mask")
			if is_instance_valid(mask):
				mask.queue_free()
		node.queue_free()

# 【新增】弹窗销毁时连带销毁遮罩（tree_exiting 信号，覆盖所有关闭路径）
func _on_popup_tree_exiting(mask):
	if is_instance_valid(mask):
		mask.queue_free()

# ============ 主题/样式/动画（原 controller apply_theme~flash_red） ============

func apply_theme():
	if c.has_node("Background"):
		c.get_node("Background").color = Color("#2d2a2e")

	# 遍历所有按钮统一美化
	for btn in c.find_children("*", "Button"):
		if btn.name == "CloseBtn":
			continue
		style_button(btn)

	# 遍历所有 Label 统一字体
	for lbl in c.find_children("*", "Label"):
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color("#f2e9e4"))

# 底栏皮肤样式盒缓存：style_nav_buttons 每次切页都跑，静态材质只建一次
#（DeepSeek 复核点：原先每切页重建 5×5=25 个 StyleBoxFlat）
var _nav_transparent_sb: StyleBoxFlat = null
var _nav_hover_sb: StyleBoxFlat = null
var _nav_pressed_sb: StyleBoxFlat = null

func _ensure_nav_styleboxes():
	if _nav_transparent_sb != null:
		return
	_nav_transparent_sb = StyleBoxFlat.new()
	_nav_hover_sb = StyleBoxFlat.new()
	_nav_pressed_sb = StyleBoxFlat.new()
	# hover/pressed 全透明：按钮格（≈116×96）比图标（82）大一圈，任何矩形光晕都会
	# 在图标外冒黑边且重心偏移（用户实测）；点击反馈交给「切页后选中图标变亮」
	for sb in [_nav_transparent_sb, _nav_hover_sb, _nav_pressed_sb]:
		sb.bg_color = Color(0, 0, 0, 0)

func style_nav_buttons():
	if not c.has_node("BottomNav"): return
	_ensure_nav_styleboxes()
	for btn in c.get_node("BottomNav").get_children():
		if btn is Button:
			# 木纹由 BottomNavBg 提供，按钮五态全透明（hover/pressed 光晕下线，理由见 _ensure_nav_styleboxes）
			btn.add_theme_stylebox_override("normal", _nav_transparent_sb)
			btn.add_theme_stylebox_override("hover", _nav_hover_sb)
			btn.add_theme_stylebox_override("pressed", _nav_pressed_sb)
			btn.add_theme_stylebox_override("focus", _nav_transparent_sb)
			btn.add_theme_stylebox_override("disabled", _nav_transparent_sb)
			if  (c.current_page == "mansion" and btn.name == "NavMansionBtn") or \
				(c.current_page == "shop" and btn.name == "NavShopBtn") or \
				(c.current_page == "hero" and btn.name == "NavHeroBtn") or \
				(c.current_page == "stage" and btn.name == "NavStageBtn") or \
				(c.current_page == "adventure" and btn.name == "NavAdventureBtn") or \
				(c.current_page == "bag" and btn.name == "NavBagBtn"):
				btn.modulate = Color(1, 1, 1)  # 高亮：原色
			else:
				btn.modulate = Color(0.62, 0.60, 0.56)  # 普通：压暗

func style_button(btn: Button):
	# 【改】批次②③④-B12：按钮统一改暗紫底+细描边+圆角，避免大面积金色显得拥挤、廉价
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color("#3b3354")
	normal.set_border_width_all(1)
	normal.border_color = Color("#6a5f9e")
	normal.set_content_margin_all(6)
	for i in 4:
		normal.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color("#4a4168")
	hover.set_border_width_all(1)
	hover.border_color = Color("#8b7fb8")
	hover.set_content_margin_all(6)
	for i in 4:
		hover.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color("#2e2848")
	pressed.set_border_width_all(1)
	pressed.border_color = Color("#ffd700")
	pressed.set_content_margin_all(6)
	for i in 4:
		pressed.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("pressed", pressed)

	var focus = StyleBoxFlat.new()
	focus.bg_color = Color("#3b3354")
	focus.set_border_width_all(1)
	focus.border_color = Color("#ffd700")
	focus.set_content_margin_all(6)
	for i in 4:
		focus.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("focus", focus)

	var disabled = StyleBoxFlat.new()
	disabled.bg_color = Color("#2a2636")
	disabled.set_border_width_all(1)
	disabled.border_color = Color("#4d4566")
	disabled.set_content_margin_all(6)
	for i in 4:
		disabled.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", Color("#f2e9e4"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffd700"))
	btn.add_theme_color_override("font_disabled_color", Color("#8a819f"))
	btn.add_theme_font_size_override("font_size", 16)

func animate_button(node_path: String):
	if not c.has_node(node_path): return
	var btn = c.get_node(node_path)
	var tween = c.create_tween()
	tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.05)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.05)

func flash_red(node_path: String):
	if not c.has_node(node_path): return
	var btn = c.get_node(node_path)

	# 防止重复调用导致样式错乱
	if btn.has_meta("flashing"):
		return

	var original_normal = btn.get_theme_stylebox("normal")
	if original_normal == null: return
	var original_hover = btn.get_theme_stylebox("hover")
	var original_pressed = btn.get_theme_stylebox("pressed")
	btn.set_meta("flashing", true)

	var red = StyleBoxFlat.new()
	red.bg_color = Color("#ff4444")
	for i in 4:
		red.set_corner_radius(i, 8)

	# 【修】normal/hover/pressed 三态一起盖红：原来只盖 normal，按住时显示 pressed 深棕、
	# 松手还悬停时显示 hover 亮棕，红色全被盖住，必须把鼠标挪开才看得见（2026-09-19 用户实测反馈）
	btn.add_theme_stylebox_override("normal", red)
	btn.add_theme_stylebox_override("hover", red)
	btn.add_theme_stylebox_override("pressed", red)
	# 【修】回调不捕获节点本体与样式板——闪红期间页面可能已刷新重建（如庄园升级后 update_manor_view 重建
	# 地块钮），闭包捕获 freed 对象会在 tween 触发时被引擎刷 "Lambda capture was freed" 错误甚至崩（2026-09-19 复现）。
	# 改为只捕获路径字符串（永不失效）；原件样式板挂在按钮 meta 上（生命周期跟随按钮），回调重新解析+校验 meta
	btn.set_meta("flash_orig", {"normal": original_normal, "hover": original_hover, "pressed": original_pressed})
	var btn_path := str(btn.get_path())
	var tween = c.create_tween()
	tween.tween_interval(0.2)
	tween.tween_callback(func():
		var b = c.get_node_or_null(btn_path)
		if b == null or not b.has_meta("flashing"):
			return
		var orig = b.get_meta("flash_orig")
		b.add_theme_stylebox_override("normal", orig["normal"])
		if orig["hover"] != null:
			b.add_theme_stylebox_override("hover", orig["hover"])
		else:
			b.remove_theme_stylebox_override("hover")
		if orig["pressed"] != null:
			b.add_theme_stylebox_override("pressed", orig["pressed"])
		else:
			b.remove_theme_stylebox_override("pressed")
		b.remove_meta("flashing")
		b.remove_meta("flash_orig")
	)

# 【改】批次②③④-B11：保留消耗数字着色公共件（原 hero_page 局部件下沉）
# 够=绿 #7ee787，不够=红 #ff6666；页面经 c._cost_color 委托调用
func _cost_color(have: int, need: int) -> Color:
	return Color("#7ee787") if have >= need else Color("#ff6666")


# 【新增】批次②③④-B12：商铺主页居中主卡公共容器（收益罐/主操作卡统一参考妙音坊）
# 调用方负责往返回的 VBoxContainer 内放内容；卡片在父容器中垂直居中，底部页签仍由页面自行控制
func _add_centered_panel(parent: Control, min_size: Vector2) -> VBoxContainer:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = min_size
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("#2a2640")
	card_style.set_corner_radius_all(8)
	card_style.set_border_width_all(1)
	card_style.border_color = Color("#6a5f9e")
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	return body

# ============ 普通弹窗内容组件（2026-10-19：羊皮纸皮肤配套；画底弹窗另走 art_popup） ============
const PAPER_TEXT: Color = Color("#3a2613")
const PAPER_TEXT_SUB: Color = Color("#6b5236")
const PAPER_OK: Color = Color("#2e8b57")
const PAPER_BAD: Color = Color("#c0392b")
const PAPER_CARD_BG: Color = Color("#efe3cc")
const PAPER_CARD_LINE: Color = Color("#8a7355")

# 滚动区：禁横滚 + 内层 VBox（常规竖排内容直接往里塞）
func popup_scroll(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # 弹窗横滚只禁（横向仅限大地图白名单）
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # 用户拍板 2026-10-19：弹窗滚动条默认隐藏（竖滚保留，不显示不占位）
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	return vb

# 段落小标题：深棕 15 号 + 一条淡分隔线（替代各页自造「标题+线」）
func popup_section(parent: Control, text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", PAPER_TEXT_SUB)
	box.add_child(l)
	var line := ColorRect.new()
	line.color = Color(0.54, 0.45, 0.33, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	return box

# 纸面卡片：浅纸底 + 棕边圆角，返回内部 VBox（调用方直接往返回容器塞内容）
func popup_card(parent: Control, min_height: float = 0.0) -> VBoxContainer:
	var card := PanelContainer.new()
	if min_height > 0.0:
		card.custom_minimum_size = Vector2(0, min_height)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER_CARD_BG
	sb.border_color = PAPER_CARD_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	return vb

# 键值行：左名（次字色）+ 右值（默认绿，不达标红）
func popup_kv_row(parent: Control, key: String, value: String, ok: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_color_override("font_color", PAPER_TEXT_SUB)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 15)
	v.add_theme_color_override("font_color", PAPER_OK if ok else PAPER_BAD)
	row.add_child(v)
	return row

# 底部按钮行：居中 + 10 间距（调用方往里加按钮）
func popup_button_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	return row

# 画底弹窗壳（酒肆/药铺/酒坊/妙音坊共用）：遮罩 + 居中 + 视口自适应 + 右上朱红圆钮 + 底图铺满
# 只提供外壳；背景图与内容由页面各自负责
func art_popup(bg: Texture2D, popup_size: Vector2, node_name: String = "ArtPopup") -> Control:
	var vp: Vector2 = c.get_viewport_rect().size
	var fit: float = minf(1.0, minf((vp.x - 24.0) / popup_size.x, (vp.y - 32.0) / popup_size.y))
	var real_size: Vector2 = popup_size * fit
	var mask := ColorRect.new()
	mask.color = Color(0, 0, 0, 0.55)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.z_index = 39
	c.add_child(mask)
	var root := Control.new()
	root.name = node_name
	root.z_index = 40
	root.custom_minimum_size = real_size
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = (vp - real_size) * 0.5
	root.size = real_size
	c.add_child(root)
	var bgt := TextureRect.new()
	bgt.texture = bg
	bgt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgt.stretch_mode = TextureRect.STRETCH_SCALE
	bgt.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bgt)
	var close_x := Button.new()
	close_x.text = "×"
	close_x.add_theme_font_size_override("font_size", 22)
	close_x.add_theme_color_override("font_color", Color(1, 0.96, 0.9))
	close_x.anchor_left = 1.0
	close_x.anchor_right = 1.0
	close_x.offset_left = -56
	close_x.offset_right = -10
	close_x.offset_top = 6
	close_x.offset_bottom = 52
	var cx_sb := StyleBoxFlat.new()
	cx_sb.bg_color = Color("#b23a30")
	cx_sb.border_color = Color("#7d241d")
	cx_sb.set_border_width_all(2)
	cx_sb.set_corner_radius_all(23)
	var cx_hover: StyleBoxFlat = cx_sb.duplicate()
	cx_hover.bg_color = Color("#c94a3d")
	for st in ["normal", "pressed"]:
		close_x.add_theme_stylebox_override(st, cx_sb)
	close_x.add_theme_stylebox_override("hover", cx_hover)
	close_x.add_theme_stylebox_override("focus", cx_sb)
	close_x.z_index = 10
	root.add_child(close_x)
	close_x.pressed.connect(root.queue_free)
	mask.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			root.queue_free())
	root.tree_exiting.connect(mask.queue_free)
	return root

# 【新增】批次②③④-B6：消耗类统一范式（用户 2026-09-26 定调）——消耗物名字不变色，数字固定"（拥有/消耗）"，拥有≥消耗绿色否则红色
# 数字 Label 固定命名 CostNum：需要原地刷新的场景用 find_child("CostNum", true, false) 定位改文本和着色
func _add_cost_row(parent: Node, prefix: String, have: int, need: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var prefix_lbl := Label.new()
	prefix_lbl.text = prefix
	row.add_child(prefix_lbl)
	var num_lbl := Label.new()
	num_lbl.name = "CostNum"
	num_lbl.text = "（%s/%s）" % [c.format_number(have), c.format_number(need)]
	num_lbl.add_theme_color_override("font_color", _cost_color(have, need))
	row.add_child(num_lbl)
	parent.add_child(row)
	return row

# ============ 顶部提示 / 解锁提示 / 数量选择器 ============

func _show_unlock_hint(role_name: String, vip_level: int):
	_safe_close("UnlockHint")

	var panel = _create_base_popup("", Vector2(400, 150), Vector2(376, 220))
	panel.name = "UnlockHint"

	var vbox = panel.get_child(0)
	var label = Label.new()
	label.text = "【%s】需要 VIP%d 解锁" % [role_name, vip_level]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# 【删】UI统一批次①：底部纯关闭"确定"钮移除，右上✕总关闭接管（范式§十一.8）

	c.add_child(panel)

func _show_quantity_selector(item_id: String, title_text: String, on_confirm: Callable):
	_close_quantity_selector()
	c._quantity_item_id = item_id   # 状态本体留在 controller（bag_page 经 c._quantity_item_id 读写）

	var max_count = c.data.items.get(item_id, 0)
	if max_count <= 0: return

	var panel = _create_base_popup(title_text, Vector2(420, 260), Vector2(366, 200), false)   # 【改】UI统一批次①：数量选择=确认弹窗，不带右上✕
	panel.name = "QuantitySelector"

	var vbox = panel.get_child(0)

	var own_label = Label.new()
	own_label.text = "拥有：%d" % max_count
	own_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(own_label)

	var pair = _create_slider_spin_pair(vbox, max_count)
	var spin = pair.spin

	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_box)

	# 【改】UI统一批次①：确认弹窗双钮定规——【取消】左【确定】右，文案只用 确定/取消（范式§十一.8）
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(70, 32)
	cancel_btn.pressed.connect(_close_quantity_selector)
	btn_box.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "确定"
	confirm_btn.custom_minimum_size = Vector2(70, 32)
	confirm_btn.pressed.connect(on_confirm.bind(spin))
	btn_box.add_child(confirm_btn)

	c.add_child(panel)

func _close_quantity_selector():
	if c.has_node("QuantitySelector"):
		_safe_close("QuantitySelector")

# 通用顶部提示弹窗（关卡/行善/兑换/庄园等结果提示共用）
# 修复记录①：原写死 position=Vector2(376,250) 且 Label 无自动换行，长文本会把弹窗向右撑出屏幕；
# 修复记录②：锚点居中方案在根节点未铺满视口时失效（框跑左边缘），改回绝对定位，
#            按视口宽度手动算居中 x + 按文本实际宽度在 400~560 间取宽并自动换行
		# 长文本自动换行（中文按字断行）
		# 杀掉旧 tween，防止堆叠
	# 按文本实际宽度动态限宽：短提示维持原 400 宽，长提示限宽 560 并在该宽度内换行
	# 水平居中：弹窗宽度≈label限宽（StyleBox无内边距），按视口宽度手动算 x，y固定250（每次显示重算）
	# （不能用锚点居中：根 Control 未铺满视口，锚点 0.5 会算到左边缘）
# ============ 成功结果弹窗（后续优先级第 2 条·试点） ============
# 【新增】成功反馈：gains 字典 → 文案（按 ITEM_CONFIG 配置顺序、顿号连接；每两项换行适配弹窗卡宽度；未配置 id 排尾防御）

func _format_gains(gains: Dictionary) -> String:
	var ordered = []
	for iid in c.data.ITEM_CONFIG.keys():
		if gains.has(iid):
			ordered.append(iid)
	for iid in gains.keys():
		if not ordered.has(iid):
			ordered.append(iid)
	var parts := []
	for iid in ordered:
		parts.append("【%s】×%d" % [c.data.ITEM_CONFIG.get(iid, {}).get("name", iid), gains[iid]])
	# 每两项一行：成功弹窗卡为 Button（不支持 autowrap），手动折行防超宽
	var lines := []
	for i in range(0, parts.size(), 2):
		lines.append("、".join(parts.slice(i, min(i + 2, parts.size()))))
	return "\n".join(lines)

# 【新增】规则说明弹窗（"?"按钮）：带遮罩、点外部关闭、不自动关——区别于成功/警告弹窗（可自动关），2026-10-02 用户拍板规则长文必须弹窗。
func _show_rule_popup(title: String, text: String):
	# 【改】弹窗统一批次（第七章 7.1）：规则说明也走同款固定窗框 + 匾额标题 + ✕ + 自动【确定】
	#   （2026-10-17 曾判「频率低走素面」，与「所有弹窗同一尺寸」冲突，按 7.1 覆盖）
	var popup: Control = _create_base_popup(title, Vector2(480, 320), Vector2.ZERO, true, true)
	popup.name = "RuleHelpPopup"
	popup.z_index = 40   # 盖过页面(z35)，同科室/病症弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child
	var vb: VBoxContainer = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)

# 【新增】成功反馈：成功弹窗是否开着（供 controller._input 关闭钩子查询）
func _success_popup_open() -> bool:
	return c.get_node_or_null("SuccessPopup") != null

# 【新增】成功反馈：结果弹窗——居中、1.5~2 秒自动关闭、点击任意位置立即关闭。
# kind 色调："ok" 成功金 / "warn" 警告红 / "info" 信息浅（失败与警告提示同享可关+自动关，2026-10-02 用户拍板 _show_stage_hint 全面退休）。
# 关闭主路径 = controller._input 节点级钩子（先于 GUI 分发，任何 Control 都挡不住）；本面板 pressed 仅作双保险。
# 弹窗卡 Button 化（pressed 引擎级信号）；单例防堆叠（新替旧）；无视觉遮罩（用户拍板）。
func _show_success_popup(text: String, auto_hide: float = 0.0, kind: String = "ok"):
	var tone: Color = {"ok": Color("#ffd700"), "warn": Color("#ff6b6b"), "info": Color("#f2e9e4")}.get(kind, Color("#ffd700"))
	var panel = c.get_node_or_null("SuccessPopup")
	if panel == null or not panel.is_inside_tree():
		panel = Button.new()
		panel.name = "SuccessPopup"
		panel.z_index = 60
		# 卡面样式直接挂按钮（四态同款，避免 hover 变色打断观感）
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#2a2640")
		style.set_corner_radius_all(12)
		style.set_border_width_all(2)
		style.border_color = Color("#6a5f9e")
		panel.add_theme_stylebox_override("normal", style)
		panel.add_theme_stylebox_override("hover", style)
		panel.add_theme_stylebox_override("pressed", style)
		panel.add_theme_stylebox_override("disabled", style)
		panel.add_theme_font_size_override("font_size", 16)
		panel.add_theme_color_override("font_color", tone)
		panel.pressed.connect(func(): c._safe_close("SuccessPopup"))
		c.add_child(panel)
	else:
		# 单例复用：杀旧 tween（防堆叠惯例）
		var old_tween0 = panel.get_meta("success_tween", null)
		if old_tween0 != null and old_tween0.is_valid():
			old_tween0.kill()

	panel.text = text
	panel.add_theme_color_override("font_color", tone)   # 复用时按 kind 换色调
	# 动态限宽：按最长一行实测宽度 + 按钮内边距
	var font = panel.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font   # 兜底：主题未配字体时用引擎回退字体，防止空引用
	var max_w: float = 0.0
	for line in text.split("\n"):
		max_w = maxf(max_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, panel.get_theme_font_size("font_size")).x)
	panel.custom_minimum_size = Vector2(clampf(max_w + 80, 260, 560), 96)
	# 居中（根 Control 未铺满视口，锚点居中会算到左边缘——手动算，y 取视口 38% 偏上视觉中心）
	var vs = c.get_viewport().get_visible_rect().size
	panel.position = Vector2((vs.x - panel.custom_minimum_size.x) / 2, vs.y * 0.38)
	# 展示时长必须 lambda 外算好（GDScript lambda 按值捕获，内部赋值不生效）
	if auto_hide <= 0.0:
		auto_hide = clampf(1.2 + text.length() * 0.02, 1.5, 2.0)   # 未显式传时按文案长度取 1.5~2 秒（拍板口径 1–2 秒）
	# 代际号：连点顶替时"只关自己这代"的校验凭据；lambda 只捕获 int/float（零对象捕获，杜绝 capture-freed 警告）
	_popup_gen += 1
	panel.set_meta("gen", _popup_gen)
	var gen: int = _popup_gen
	# 立即入场（无延迟）：淡入 + 轻微回弹缩放
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	var tween = c.create_tween()
	panel.set_meta("success_tween", tween)
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 自动关闭：独立一次性定时器（0.2 动效 + 展示时长），只被自身 timeout 触发一次；代际校验防复用误关
	c.get_tree().create_timer(0.2 + auto_hide).timeout.connect(func():
		var cur2 = c.get_node_or_null("SuccessPopup")
		if cur2 != null and int(cur2.get_meta("gen", 0)) == gen:
			c._safe_close("SuccessPopup")
	)

# ============ 飘字徽标（赚速 / 门客赚钱） ============

# 【新增】全局赚速提升飘字（2026-09-11 定稿，2026-09-16 重新接入——曾被后交付的整文件覆盖丢失）：
# 中央对比方案——中枢快照 + update_all_ui 汇流。所有养成系统操作后都汇流 update_all_ui
# （含每秒 on_auto_earn），diff≠0 即弹、更新快照；批量/十连天然合并为一次总增量；新系统零成本继承
func _check_income_float():
	# 【修】门客赚钱检查必须无条件先跑：它负担快照建档，若挂在全局 diff≠0 分支后，
	# 启动阶段全局无变化时快照永不建档，导致"每局第一次提升不弹、第二次起才弹"（2026-09-11 用户复现）
	_check_hero_income_float()
	var cur: int = c.data.get_total_auto_income()
	if _last_total_income < 0:
		_last_total_income = cur   # 首次/刚进游戏：只建快照不弹，避免开场飘字
		return
	var delta: int = cur - _last_total_income
	_last_total_income = cur
	if delta == 0:
		return
	_show_income_float(cur, delta)

# 【新增】通用徽标飘字：半透明圆角背景板（不与底层页面文字糊在一起）+ 增量数字滚动上涨
# （1.2s 内从当前显示值滚到最新累计目标，涨完固定，再随板子渐隐 0.8s）+ 连点累加。
# cfg = {"tween": 动画引用, "display": 当前滚动显示值, "target": 累计目标增量}（Dictionary 传引用，天然共享状态）
# make_text = Callable(显示值:int, 正负号:String, 增量色:String) -> String 文案（外部值如总数用闭包捕获）
func _show_float_badge(cfg: Dictionary, node_name: String, y: int, delta: int, make_text: Callable):
	var panel: PanelContainer = c.get_node_or_null(node_name)
	if panel == null:
		panel = PanelContainer.new()
		panel.name = node_name
		panel.z_index = 50   # 飘字层级惯例
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 【修】飘尽是 alpha=0 不是 free，残留全屏吃点击（牧场/农场顶部点不到的元凶）
		# 背景板：深紫底 85% 不透明度 + 圆角，挡得住页面文字又不死板
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#1e1b2e", 0.85)
		style.set_corner_radius_all(10)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		panel.add_theme_stylebox_override("panel", style)
		var rtl := RichTextLabel.new()
		rtl.name = "Text"
		rtl.bbcode_enabled = true   # 双色：主体橙金 / 增量绿(红)
		rtl.scroll_active = false
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 穿透到下层页面（板子已 IGNORE，双保险）
		rtl.add_theme_font_size_override("normal_font_size", 20)
		rtl.add_theme_color_override("default_color", Color("#e6a23c"))
		rtl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		rtl.add_theme_constant_override("outline_size", 3)
		rtl.custom_minimum_size = Vector2(320, 28)   # 固定徽标内宽，文字居中不随字数跳动
		panel.add_child(rtl)
		c.add_child(panel)   # 【修】重写时遗漏：panel 必须挂进场景树，否则徽标永远不显示（不报错只隐身）
	panel.size = Vector2(352, 38)   # 320+两侧边距；显式定尺寸防首帧 0 尺寸（新节点坑）
	panel.position = Vector2(124, y)   # 屏宽 600 徽标 352 居中（写死 124，避开整数除法警告）
	# 累加制：飘还亮着时叠到目标上（+10→+20→+30）；飘尽归零重新累计
	if panel.modulate.a <= 0.05:
		cfg["display"] = 0.0
		cfg["target"] = 0
	cfg["target"] = int(cfg["target"]) + delta
	var sign_txt := "+" if int(cfg["target"]) > 0 else "-"
	var delta_col := "#2ecc71" if int(cfg["target"]) > 0 else "#e74c3c"
	panel.modulate.a = 1.0   # 重弹满亮（连点时板子一直亮着只换数字）
	var tw: Tween = cfg["tween"]
	if tw != null and tw.is_valid():
		tw.kill()
	tw = c.create_tween()
	cfg["tween"] = tw
	var label: RichTextLabel = panel.get_node("Text")
	var start_val: float = cfg["display"]
	var target_val: int = int(cfg["target"])
	# 数字滚动上涨：1.2s 线性滚到目标（连点杀旧动画会从当前显示值无缝续涨），滚完即固定
	tw.tween_method(func(v: float):
		cfg["display"] = v
		label.text = make_text.call(int(round(v)), sign_txt, delta_col)
	, start_val, float(target_val), 1.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)   # 数字固定后板子渐隐

# 【新增】赚速飘字（y=114，门客赚钱飘字下方一层）：总数橙金 / +增量绿（负红），数字复用 format_number
func _show_income_float(total: int, delta: int):
	_show_float_badge(_income_float_state, "IncomeFloat", 114, delta,
		func(v: int, sign_txt: String, delta_col: String):
			return "[center][color=#e6a23c]赚速 %s/秒[/color]  [color=%s](%s%s)[/color][/center]" % [c.format_number(total), delta_col, sign_txt, c.format_number(abs(v))])

# 【新增】门客赚钱飘字：全局固定位置 y=72（赚速飘字 y=114 上方一层，同时触发不错层）；
# 显示门客总赚钱增量（全部已拥有门客合并，不显示单个门客名）
func _show_hero_power_float(delta: int):
	_show_float_badge(_hero_float_state, "HeroPowerFloat", 72, delta,
		func(v: int, sign_txt: String, delta_col: String):
			return "[center][color=#e6a23c]门客赚钱[/color] [color=%s]%s%s[/color][/center]" % [delta_col, sign_txt, c.format_number(abs(v))])

# 【新增】门客赚钱飘字（游戏内口径=门客赚钱，即单门客赚速 HeroData.get_income），
# 赚速=全局挂机货币速度（get_total_auto_income）。本函数逐门客 diff：任何页面（门客面板/挚友技能/
# 珍兽培养/促织园/背包/藏品…）提升任一已拥有门客赚钱，1 秒内必弹，无需逐页接线；
# 多门客同帧变化时增量合并为"门客总赚钱"显示
func _check_hero_income_float():
	var changed := {}   # hero_id -> 赚钱差值（本帧有变化的门客）
	for hero_id in c.data.heroes.keys():
		var cur: int = c.data.get_hero_income(hero_id)
		if _hero_income_snapshot.has(hero_id):
			var d: int = cur - int(_hero_income_snapshot[hero_id])
			if d != 0:
				changed[hero_id] = d
		_hero_income_snapshot[hero_id] = cur   # 无论有无变化都刷新快照
	if changed.is_empty():
		return
	# 【改】不显示单个门客：所有变化门客的增量合并为"门客总赚钱"增量（用户 09-11 拍板）
	var total_delta := 0
	for d in changed.values():
		total_delta += int(d)
	_show_hero_power_float(total_delta)

# ==================== 【新增】Web 端中文输入统一兜底（2026-10-06） ====================
# 背景：Godot Web 中文 IME 走组合事件，引擎级未修（官方 issue 91204，4.2 至今 open）；
# 实验性虚拟键盘骗得出键盘但中文进不了输入框，英文/数字走普通按键所以正常。
# 方案：Web 端给 LineEdit 挂 focus 兜底——聚焦即弹浏览器原生 prompt（中文走浏览器 IME），
# 结果写回输入框并触发 text_changed（实时过滤类输入框无需改逻辑）。
# 判定只用 OS.has_feature("web")：部分手机浏览器触屏检测不可靠，桌面网页弹 prompt 属可接受代价。

# 给输入框挂 Web 中文兜底（title=提示语；非 Web 端调用即空操作）
# 挂 gui_input 而非 focus_entered：浏览器在 prompt 关闭后会把焦点还给输入框，
# focus 方案会无限重弹；按下事件不经过聚焦，天然无回环。meta 存上次弹窗时间戳做防重入闸门。
func _hook_web_cjk_input(edit: LineEdit, title: String) -> void:
	if not OS.has_feature("web"):
		return
	edit.placeholder_text = "点此输入" + title
	edit.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		var now := Time.get_ticks_msec()
		if now - int(edit.get_meta("cjk_last", 0)) < 500:
			return   # 同一次点按/焦点归还的重复触发，闸掉
		edit.set_meta("cjk_last", now)
		edit.release_focus()   # 阻止 LineEdit 自聚焦弹出那个中文进不来的实验键盘
		var r = JavaScriptBridge.eval("prompt(%s, '')" % JSON.stringify(title))
		if r != null:
			edit.text = str(r)   # 写回触发 text_changed，实时过滤逻辑零改动
	)
