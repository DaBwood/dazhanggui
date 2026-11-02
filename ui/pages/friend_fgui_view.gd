extends Control
## 挚友页：整窗复用原作 Patrons.Main（与门客页同一套外框），只把 list 换成挚友圆形格
## 用法：FriendFguiView.new(c) → ensure_built(parent) → refresh(rows)

const PKG_DIR := "res://assets/fgui/"
const PKGS := ["Basic", "Basic2", "Basic3", "Items", "AnimalsEntry", "Patrons"]
const HALF_DIR := "res://assets/portraits/friends_round/"
const WIN_W := 750.0
const WIN_H := 1334.0
const CELL_SCALE := 2.18     # 200×200 的挚友格放大后两列铺满 list 区（676 宽）

var _c: Node = null
var on_pick: Callable = Callable()
var on_back: Callable = Callable()
var on_chat: Callable = Callable()
var _bottom_bar: Control = null
var _energy_label: Label = null
var auto_chat: bool = false
var _full_bg: TextureRect = null
var _root: Control = null
var _main: FGUIComponent = null
var _grid: GridContainer = null
var _stat_left: FGUITextField = null
var _stat_rest: Label = null

func _init(p_c: Node):
	_c = p_c


static func ensure_packages() -> bool:
	for n in PKGS:
		if FGUIPackage.get_by_name(n) == null:
			if FGUIPackage.add_package(PKG_DIR + n) == null:
				return false
	return true


func ensure_built(parent: Node) -> bool:
	if _root != null and is_instance_valid(_root):
		return true
	if not ensure_packages():
		push_warning("[FriendFgui] 包加载失败")
		return false
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	if pkg == null:
		return false
	_main = pkg.create_object("Main") as FGUIComponent
	if _main == null:
		return false
	_root = Control.new()
	_root.name = "FriendFguiRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_root.add_child(_main.node)
	_main.node.position = Vector2.ZERO
	_build_bottom_bar()
	_build_full_bg()

	# 原件的 list 是门客大卡，这里隐藏，用同位置同尺寸的网格装挚友圆格
	var list_obj: FGUIObject = _main.get_child("list")
	var area_pos := Vector2(46, 155)
	var area_size := Vector2(676, 945)
	if list_obj != null:
		area_pos = Vector2(list_obj.x, list_obj.y)
		area_size = Vector2(list_obj.width, list_obj.height)
		list_obj.visible = false

	var scroll := ScrollContainer.new()
	scroll.name = "BeautyScroll"
	scroll.position = area_pos
	scroll.size = area_size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_main.node.add_child(scroll)
	var vb := scroll.get_v_scroll_bar()
	if vb != null:
		vb.modulate = Color(1, 1, 1, 0)      # 原作没有可见滚动条
	_grid = GridContainer.new()
	_grid.name = "BeautyGrid"
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(_grid)

	# 统计行：原件有「数量 / 属性名 / 属性值」三槽，总友好+总才华合并写进补充标签
	_stat_left = _main.get_child("txtPatronsNum") as FGUITextField
	var attr_name := _main.get_child("txtAttrName") as FGUITextField
	if attr_name != null:
		attr_name.text = ""
	var attr_val := _main.get_child("txtAttr") as FGUITextField
	if attr_val != null:
		attr_val.text = ""
	_stat_rest = Label.new()
	_stat_rest.name = "StatsRest"
	_stat_rest.position = Vector2(548, 92)
	_stat_rest.add_theme_font_size_override("font_size", 26)
	_stat_rest.add_theme_color_override("font_color", Color("#f0e2c0"))
	_main.node.add_child(_stat_rest)

	# 背景：Patrons.fui 里 bgIcon 的 ui://dpmcwa3b8fij6r 在本包内是悬空引用
	# （get_item_by_id 返回 null），原件那张 750×1800 底图不在包里，
	# 这里用暖棕渐变兜底，避免整页纯黑。
	var bg: FGUIObject = _main.get_child("bgIcon")
	if bg != null:
		bg.visible = false
	if _root.get_node_or_null("BgFill") == null:
		var back := TextureRect.new()
		back.name = "BgFill"
		var bg_path := "res://assets/backgrounds/bg_friend_detail.png"
		if ResourceLoader.exists(bg_path):
			back.texture = load(bg_path) as Texture2D
		else:
			var grad2 := Gradient.new()
			grad2.set_color(0, Color("#3a2819"))
			grad2.set_color(1, Color("#20140d"))
			var gtex := GradientTexture2D.new()
			gtex.gradient = grad2
			gtex.width = 8
			gtex.height = 64
			gtex.fill_to = Vector2(0.0, 1.0)
			back.texture = gtex
		back.stretch_mode = TextureRect.STRETCH_SCALE
		back.size = Vector2(750, 1334)
		back.position = Vector2(0, 0)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(back)
		_root.move_child(back, 0)

	# 标题条：原件 closeItem 里的文本字段默认是空的，运行时填「挚友」
	var close_item2: FGUIObject = _main.get_child("closeItem")
	if close_item2 is FGUIComponent:
		_fill_title(close_item2 as FGUIComponent, "挚友")

	for hide_name in ["btnFilter", "btnMyth", "btnAttrInfo", "n25"]:
		var hn: FGUIObject = _main.get_child(hide_name)
		if hn != null:
			hn.visible = false

	var close_item := _main.get_child("closeItem") as FGUIComponent
	if close_item != null:
		var bc := close_item.get_child("btnClose") as FGUIButton
		if bc != null:
			bc.on_click(func():
				if on_back.is_valid():
					on_back.call())

	resized.connect(_layout)
	_layout()
	return true


func show_view(v: bool) -> void:
	if _full_bg != null and is_instance_valid(_full_bg):
		_full_bg.visible = v
		if v:
			_sync_full_bg()
	if _root != null and is_instance_valid(_root):
		_root.visible = v


func refresh(rows: Array) -> void:
	if _root == null:
		return
	for ch in _grid.get_children():
		ch.queue_free()
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	if pkg == null:
		return
	var unlocked := 0
	var total_friendly := 0
	var total_talent := 0
	for row in rows:
		if bool(row.get("locked", false)):
			continue
		unlocked += 1
		total_friendly += int(row.get("friendly", 0))
		total_talent += int(row.get("talent", 0))
	if _stat_left != null:
		_stat_left.text = "挚友数量: %d" % unlocked
	var name_lbl := _main.get_child("txtAttrName") as FGUITextField
	if name_lbl != null:
		name_lbl.text = "总友好: %d" % total_friendly
	var val_lbl := _main.get_child("txtAttr") as FGUITextField
	if val_lbl != null:
		val_lbl.text = ""
	if _stat_rest != null:
		_stat_rest.text = "总才华: %d" % total_talent
	for row in rows:
		var cell := _make_cell(pkg, row)
		if cell != null:
			_grid.add_child(cell)
	_layout()


func _make_cell(pkg: FGUIPackage, row: Dictionary) -> Control:
	var obj: FGUIObject = pkg.create_object("DestinyBeautyItem")
	if obj == null:
		return null
	var comp := obj as FGUIComponent
	# 原件默认开着的遮罩/锁/特效/倒计时，游戏里按状态开关，这里一律关
	for hide_name in ["imgLock", "imgEffect", "txtTime", "imgAdd", "bgAttr", "imgNone"]:
		var h: FGUIObject = comp.get_child(hide_name)
		if h != null:
			h.visible = false
	var icon_comp := comp.get_child("iconItem") as FGUIComponent
	var loader: FGUILoader = null
	if icon_comp != null:
		loader = icon_comp.get_child("icon") as FGUILoader
	var path := str(row.get("portrait", ""))
	if path == "" or not ResourceLoader.exists(path):
		var alt := HALF_DIR + str(row.get("id", "")) + ".png"
		path = alt if ResourceLoader.exists(alt) else ""
	if loader != null and path != "":
		loader.url = path
	comp.on_click(func():
		if on_pick.is_valid():
			on_pick.call(row))
	if bool(row.get("locked", false)):
		comp.alpha = 0.45

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(330, 392)
	holder.clip_contents = false
	var node: Control = comp.node
	node.scale = Vector2(CELL_SCALE, CELL_SCALE)
	node.position = Vector2(-63, -63)    # 花环外框在原件里是 (29,29)，偏移把它对到格子原点
	holder.add_child(node)

	# 圆下属性条：原件 txtAttr 只放数字，图标另外叠两个 TextureRect
	var attr := comp.get_child("txtAttr") as FGUITextField
	if attr != null:
		attr.visible = false
	# 属性胶囊底（原作是圆下一条深棕圆角条）
	var locked_row := bool(row.get("locked", false))
	var pill := PanelContainer.new()
	pill.name = "AttrPill"
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.20, 0.14, 0.10, 0.92)
	psb.set_corner_radius_all(16)
	psb.set_border_width_all(2)
	psb.border_color = Color(0.55, 0.42, 0.24, 0.95)
	psb.content_margin_left = 12
	psb.content_margin_right = 12
	psb.content_margin_top = 2
	psb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", psb)
	pill.position = Vector2(24, 288)
	pill.custom_minimum_size = Vector2(226, 38)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill)

	var line := HBoxContainer.new()
	line.name = "AttrLine"
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_attr_fgui("Basic", "imgIntimacy", 30))
	line.add_child(_attr_num(int(row.get("friendly", 0))))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	line.add_child(gap)
	line.add_child(_attr_icon("res://assets/items/icons/118001.png", 30))
	line.add_child(_attr_num(int(row.get("talent", 0))))
	pill.add_child(line)

	# 竖排名签（自绘；原件 BeautyNameItem 的底图在我们这套图集里对不上）
	var plaque := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#e8d9b5")
	sb.set_border_width_all(2)
	sb.border_color = Color("#a8853f")
	sb.set_corner_radius_all(6)
	plaque.add_theme_stylebox_override("panel", sb)
	plaque.position = Vector2(262, 84)
	var cname := str(row.get("name", ""))
	plaque.custom_minimum_size = Vector2(46, maxf(120.0, float(cname.length()) * 34.0))
	var vlabel := Label.new()
	vlabel.text = "\n".join(cname.split())
	vlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vlabel.add_theme_font_size_override("font_size", 24)
	vlabel.add_theme_color_override("font_color", Color("#4a3418"))
	plaque.add_child(vlabel)
	holder.add_child(plaque)
	# 未解锁的挚友只有一个圆形 + 名签，不显示友好/才华
	if locked_row:
		pill.visible = false
	return holder


# 直接拿 FGUI 原件里的图当小图标（友好=Basic.imgIntimacy，原作就是它）
func _attr_fgui(pkg_name: String, item_name: String, side: int) -> Control:
	var pkg: FGUIPackage = FGUIPackage.get_by_name(pkg_name)
	if pkg == null:
		return Control.new()
	var o: FGUIObject = pkg.create_object(item_name)
	if o == null:
		return Control.new()
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(side, side)
	var k := float(side) / maxf(o.width, 1.0)
	o.node.scale = Vector2(k, k)
	holder.add_child(o.node)
	return holder


func _attr_icon(path: String, side: int) -> TextureRect:
	var tr := TextureRect.new()
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.custom_minimum_size = Vector2(side, side)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return tr


func _attr_num(v: int) -> Label:
	var lb := Label.new()
	lb.text = str(v)
	lb.add_theme_font_size_override("font_size", 26)
	lb.add_theme_color_override("font_color", Color("#ffe9c9"))
	lb.add_theme_color_override("font_outline_color", Color("#3a2410"))
	lb.add_theme_constant_override("outline_size", 4)
	return lb


# 递归把标题条里的第一个文本字段写成标题
func _fill_title(node: FGUIComponent, title: String) -> void:
	for i in node.num_children:
		var ch: FGUIObject = node.get_child_at(i)
		if ch is FGUITextField:
			var tf := ch as FGUITextField
			if tf.text.length() <= 4:
				tf.text = title
				return
		elif ch is FGUIComponent:
			var inner := ch as FGUIComponent
			for j in inner.num_children:
				var ch2: FGUIObject = inner.get_child_at(j)
				if ch2 is FGUITextField:
					(ch2 as FGUITextField).text = title
					return



## 底部操作栏：照原作摆——旅行册在左、三个入口居中、右侧精力＋一键谈心、最右谈心大按钮
func _build_bottom_bar() -> void:
	if _bottom_bar != null and is_instance_valid(_bottom_bar):
		return
	# 原件 Main 底部那两条深色横条（n15/n25）是“遮罩”观感的来源，先关掉
	_bottom_bar = Control.new()
	_bottom_bar.name = "BottomBar"
	_bottom_bar.size = Vector2(WIN_W, 226.0)
	_bottom_bar.position = Vector2(0, 1108)
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bottom_bar)


	# 左：旅行册
	_add_icon_btn(_bottom_bar, "travel", Vector2(18, 14), Vector2(98, 98), Callable())

	# 中：美名录 / 技能加成 / 萍水相逢（新图自带文字）
	var entries := [["minglu", 150.0], ["jinneng", 256.0], ["pingshui", 362.0]]
	for ent in entries:
		_add_icon_btn(_bottom_bar, str(ent[0]), Vector2(float(ent[1]), 96), Vector2(96, 96), Callable())

	# 右：精力 + 一键谈心
	var energy := Label.new()
	_energy_label = energy
	energy.text = "精力:-"
	energy.add_theme_font_size_override("font_size", 22)
	energy.add_theme_color_override("font_color", Color("#f6e6c8"))
	energy.add_theme_color_override("font_outline_color", Color("#2a1a0c"))
	energy.add_theme_constant_override("outline_size", 4)
	energy.position = Vector2(470, 108)
	energy.size = Vector2(140, 30)
	_bottom_bar.add_child(energy)

	var auto_btn := CheckBox.new()
	auto_btn.name = "AutoChat"
	auto_btn.text = "一键谈心"
	auto_btn.focus_mode = Control.FOCUS_NONE
	auto_btn.position = Vector2(470, 140)
	auto_btn.size = Vector2(126, 40)
	auto_btn.add_theme_font_size_override("font_size", 22)
	auto_btn.add_theme_color_override("font_color", Color("#f6e6c8"))
	auto_btn.add_theme_color_override("font_outline_color", Color("#2a1a0c"))
	auto_btn.add_theme_constant_override("outline_size", 4)
	auto_btn.toggled.connect(func(pressed: bool) -> void: auto_chat = pressed)
	_bottom_bar.add_child(auto_btn)

	# 最右：谈心大按钮
	_add_icon_btn(_bottom_bar, "talk", Vector2(596, 84), Vector2(104, 112), func() -> void:
		if on_chat.is_valid():
			on_chat.call()
	)


## 外部（friend_page）刷新精力显示
func set_energy(cur: int, capv: int) -> void:
	if _energy_label != null and is_instance_valid(_energy_label):
		_energy_label.text = "精力:%d/%d" % [cur, capv]


## 底部栏统一用「贴图 + 透明命中区」的画法，避免再叠底板
func _add_icon_btn(parent: Control, key: String, pos: Vector2, box: Vector2, cb: Callable) -> Button:
	var path := "res://assets/ui/btn/%s.png" % key
	var b := Button.new()
	b.name = "Btn_" + key
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = box
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	if ResourceLoader.exists(path):
		var img := TextureRect.new()
		img.texture = load(path) as Texture2D
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.size = box
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(img)
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _bar_button(label: String, pos: Vector2, box: Vector2) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = box
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color("#f6e6c8"))
	b.add_theme_color_override("font_outline_color", Color("#2a1a0c"))
	b.add_theme_constant_override("outline_size", 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.11, 0.07, 0.55)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.62, 0.47, 0.26, 0.9)
	for st2 in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st2, sb)
	return b



## 全屏背景：原作这一页是整屏底图，我们的 FGUI 视窗只占夹心区，所以另铺一层贴到游戏根上
func _build_full_bg() -> void:
	var bg_path := "res://assets/backgrounds/bg_friend_detail.png"
	if not ResourceLoader.exists(bg_path):
		return
	_full_bg = TextureRect.new()
	_full_bg.name = "FriendFullBg"
	_full_bg.texture = load(bg_path) as Texture2D
	_full_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_full_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_bg.visible = false
	_full_bg.z_index = -10   # 沉到最底，避免盖住 FGUI 面板
	_c.add_child(_full_bg)
	_c.move_child(_full_bg, 0)


func _sync_full_bg() -> void:
	if _full_bg == null or not is_instance_valid(_full_bg):
		return
	var vp: Vector2 = _c.get_viewport_rect().size
	_full_bg.position = Vector2.ZERO
	_full_bg.size = vp


func _layout() -> void:
	if _root == null:
		return
	# 宽高双约束取小者，整页落在夹心区里，不会顶到底部操作栏
	var sx: float = (size.x / WIN_W) if size.x > 1.0 else 1.0
	var sy: float = (size.y / WIN_H) if size.y > 1.0 else 1.0
	var s: float = minf(sx, sy)
	_root.scale = Vector2(s, s)
	_root.size = Vector2(WIN_W, WIN_H)
	_root.position = Vector2((size.x - WIN_W * s) * 0.5, 0.0)
	_sync_full_bg()
