extends Control
## 挚友页：整窗复用原作 Patrons.Main（与门客页同一套外框），只把 list 换成挚友圆形格
## 用法：FriendFguiView.new(c) → ensure_built(parent) → refresh(rows)

const PKG_DIR := "res://assets/fgui/"
const PKGS := ["Basic", "Basic2", "Basic3", "Items", "AnimalsEntry", "Patrons"]
const HALF_DIR := "res://assets/portraits/friends_half/"
const WIN_W := 750.0
const WIN_H := 1334.0
const CELL_SCALE := 2.18     # 200×200 的挚友格放大后两列铺满 list 区（676 宽）

var _c: Node = null
var on_pick: Callable = Callable()
var on_back: Callable = Callable()
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
		var bg_path := "res://assets/ui/friend_bg.png"
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
	for hide_name in ["imgMask", "imgLock", "imgEffect", "txtTime", "imgAdd", "bgAttr", "imgNone"]:
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


func _layout() -> void:
	if _root == null:
		return
	var s: float = size.x / WIN_W if size.x > 1.0 else 1.0
	_root.scale = Vector2(s, s)
	_root.size = Vector2(WIN_W, maxf(size.y / s, WIN_H))
