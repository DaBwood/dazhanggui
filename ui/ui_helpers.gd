# ============================================================
# 《大掌柜》UI 助手设施（2026-09-19 架构重构批次B，自 game_controller.gd 原样迁出）
# 职责：弹窗三件套（工厂/二次居中/OK按钮/滑条数字对）/ 通用关闭 / 主题样式动画 /
#       顶部提示（StageHint/解锁提示）/ 赚速·门客赚钱飘字徽标 / 数量选择器
# 约定（与 ui/net_ui.gd 相同）：
#   · 本类是 RefCounted 不是 Node——节点树操作（has_node/get_node/add_child/find_children/
#     get_viewport*/get_tree/create_tween）必须经 c 转发；弹窗/提示挂 c 根节点 z 序才有效；
#   · 对 controller 其它设施（data/数量选择器状态 _quantity_item_id/format_number）一律 c.xxx；
#   · 块内互调（本文件函数之间）直接本地调用。controller 留同名一行委托，全部调用点零改动。
# ============================================================
class_name UiHelpers
extends RefCounted

var c   # game_controller 根脚本（无类型，与 pages 模块一致）

var _last_total_income: int = -1   # 【新增】全局赚速飘字：上次总赚速快照（-1=未初始化，首次只记录不弹）
var _income_float_state := {"tween": null, "display": 0.0, "target": 0}   # 【新增】赚速飘字状态：动画引用/滚动显示值/累计目标增量（连点累加，飘尽归零）
var _hero_income_snapshot: Dictionary = {}   # 【新增】门客赚钱飘字：每个已拥有门客的赚钱快照 {hero_id: income}（首次建档不弹）
var _hero_float_state := {"tween": null, "display": 0.0, "target": 0}   # 【新增】门客赚钱飘字状态（同赚速飘字结构）

func _init(p_c):
	c = p_c

# ============ 弹窗工厂三件套 + 通用关闭（原 controller 924~933 行区域） ============

# 【新增】全屏遮罩：压暗背景并挡住弹窗期间切换页面/误触后台（z=25 低于弹窗 30、高于页面）；
#  引用挂在 panel 的 meta 上，由 _safe_close 连带摘除，113 处调用零改动
func _create_base_popup(title_text: String, popup_size: Vector2, _pos: Vector2 = Vector2.ZERO) -> PanelContainer:   # _pos 已废弃：一律居中（保留参数兼容46处旧调用）
	var mask = ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.55)
	mask.z_index = 25
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(mask)

	var panel = PanelContainer.new()
	panel.set_meta("popup_mask", mask)
	# 【新增】遮罩跟随弹窗生命周期：任何关闭路径（含直接 queue_free 绕过 _safe_close）都能摘掉遮罩
	panel.tree_exiting.connect(_on_popup_tree_exiting.bind(mask))
	# 【改】竖屏适配：弹窗尺寸钳制不超视口（四周留边）；写死的位置也钳制在屏幕内不出界
	var vs = c.get_viewport_rect().size
	popup_size = Vector2(minf(popup_size.x, vs.x - 40), minf(popup_size.y, vs.y - 80))
	panel.custom_minimum_size = popup_size
	# 【改】一律居中，忽略 pos 参数——旧 pos 全是横屏 1152×648 写死的坐标，
	#       钳制只能保证不出界、弹窗会贴边歪斜（30+处调用的 pos 都已失效，参数保留不删省得改签名）
	panel.position = (vs - popup_size) / 2
	panel.z_index = 30
	# 【新增】内容把面板撑大时按真实尺寸二次居中（custom_minimum_size 只是下限，不是实际尺寸）
	panel.ready.connect(_recenter_popup.bind(panel))

	var style = StyleBoxFlat.new()
	# 【改】底色提亮一档（原 #1e1b2e 与全屏门客面板同色，弹窗会融进背景）
	style.bg_color = Color("#2a2640")
	style.set_corner_radius_all(12)
	# 【新增】2px 淡紫描边，弹窗边界一眼可辨（想换金色描边就改成 "#a8893f"）
	style.set_border_width_all(2)
	style.border_color = Color("#6a5f9e")
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	if title_text != "":
		var title = Label.new()
		title.text = title_text
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color("#ffd700"))
		vbox.add_child(title)

	return panel

# 【新增】弹窗二次居中：等两帧布局完成后按真实 size 居中。
# 解决内容最小尺寸大于声明 popup_size 时（如长列表/宽网格撑大面板），按声明尺寸居中导致的偏移
func _recenter_popup(panel: Control):
	await c.get_tree().process_frame
	await c.get_tree().process_frame
	if not is_instance_valid(panel): return
	var vs = c.get_viewport_rect().size
	panel.position = ((vs - panel.size) / 2).max(Vector2(8, 8))  # 钳个最小边距，超大内容也不至于顶出左上

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

func style_nav_buttons():
	if not c.has_node("BottomNav"): return
	for btn in c.get_node("BottomNav").get_children():
		if btn is Button:
			if  (c.current_page == "mansion" and btn.name == "NavMansionBtn") or \
				(c.current_page == "shop" and btn.name == "NavShopBtn") or \
				(c.current_page == "hero" and btn.name == "NavHeroBtn") or \
				(c.current_page == "stage" and btn.name == "NavStageBtn") or \
				(c.current_page == "adventure" and btn.name == "NavAdventureBtn") or \
				(c.current_page == "bag" and btn.name == "NavBagBtn"):
				btn.modulate = Color("#e0c070")  # 高亮
			else:
				btn.modulate = Color("#c9a959")  # 普通

func style_button(btn: Button):
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color("#c9a959")
	for i in 4:
		normal.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color("#e0c070")
	for i in 4:
		hover.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color("#a08030")
	for i in 4:
		pressed.set_corner_radius(i, 8)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", Color("#2d2a2e"))
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

	_add_ok_button(vbox, func(): panel.queue_free())

	c.add_child(panel)

func _show_quantity_selector(item_id: String, title_text: String, on_confirm: Callable):
	_close_quantity_selector()
	c._quantity_item_id = item_id   # 状态本体留在 controller（bag_page 经 c._quantity_item_id 读写）

	var max_count = c.data.items.get(item_id, 0)
	if max_count <= 0: return

	var panel = _create_base_popup(title_text, Vector2(420, 260), Vector2(366, 200))
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

	var confirm_btn = Button.new()
	confirm_btn.text = "确认"
	confirm_btn.custom_minimum_size = Vector2(70, 32)
	confirm_btn.pressed.connect(on_confirm.bind(spin))
	btn_box.add_child(confirm_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(70, 32)
	cancel_btn.pressed.connect(_close_quantity_selector)
	btn_box.add_child(cancel_btn)

	c.add_child(panel)

func _close_quantity_selector():
	if c.has_node("QuantitySelector"):
		_safe_close("QuantitySelector")

# 通用顶部提示弹窗（关卡/行善/兑换/庄园等结果提示共用）
# 修复记录①：原写死 position=Vector2(376,250) 且 Label 无自动换行，长文本会把弹窗向右撑出屏幕；
# 修复记录②：锚点居中方案在根节点未铺满视口时失效（框跑左边缘），改回绝对定位，
#            按视口宽度手动算居中 x + 按文本实际宽度在 400~560 间取宽并自动换行
func _show_stage_hint(text: String, auto_hide: float = 2.5):
	var panel = c.get_node_or_null("StageHint")
	var vbox: VBoxContainer
	var label: Label

	if panel == null:
		panel = PanelContainer.new()
		panel.name = "StageHint"
		panel.custom_minimum_size = Vector2(400, 120)
		panel.z_index = 50

		var style = StyleBoxFlat.new()
		style.bg_color = Color("#1e1b2e")
		style.set_corner_radius_all(12)
		panel.add_theme_stylebox_override("panel", style)

		vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 12)
		panel.add_child(vbox)

		label = Label.new()
		label.name = "HintLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 长文本自动换行（中文按字断行）
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color("#ffd700"))
		vbox.add_child(label)

		c.add_child(panel)
	else:
		# 杀掉旧 tween，防止堆叠
		var old_tween = panel.get_meta("hint_tween", null)
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
		vbox = panel.get_child(0)
		label = vbox.get_node("HintLabel")

	label.text = text
	# 按文本实际宽度动态限宽：短提示维持原 400 宽，长提示限宽 560 并在该宽度内换行
	var font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font   # 兜底：主题未配字体时用引擎回退字体，防止空引用
	var text_w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	label.custom_minimum_size.x = clampf(text_w, 400, 560)
	# 水平居中：弹窗宽度≈label限宽（StyleBox无内边距），按视口宽度手动算 x，y固定250（每次显示重算）
	# （不能用锚点居中：根 Control 未铺满视口，锚点 0.5 会算到左边缘）
	panel.position = Vector2((c.get_viewport().get_visible_rect().size.x - label.custom_minimum_size.x) / 2, 250)

	var tween = c.create_tween()
	panel.set_meta("hint_tween", tween)
	tween.tween_interval(auto_hide)
	tween.tween_callback(func():
		if c.has_node("StageHint"):
			_safe_close("StageHint")
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
