extends Control
## 挚友详情页（原作 FGUI 原样移植）
##
## 整页直接用 `Beauty.Info`（750×1334，43 个子件全是原件），只做数据填充：
##   bgIcon / icon      → 当前服装立绘（原作用 Spine，这里先贴立绘图）
##   nameItem.txtName   → 挚友名字（竖排）
##   txtIntimacy / txtGlamour → 友好 / 才华数值
##   btnSkill / btnPromotion / btnPatronize / btnSkin → 左侧四个功能钮
##   closeItem          → 返回

const PKGS: Array = ["Bag", "Basic", "Basic2", "Basic3", "Items", "Patrons", "Beauty", "Common2"]
const PKG_DIR := "res://assets/fgui/"
const PORTRAIT_DIR := "res://assets/portraits/friends/"
const WIN_SIZE := Vector2(750, 1334)
const QUALITY_NAMES := ["", "普通", "优秀", "卓越", "传奇", "无双"]
const QUALITY_COLORS := {
	1: Color("#7f8a93"),
	2: Color("#5cb85c"),
	3: Color("#4a90d9"),
	4: Color("#d9a441"),
	5: Color("#d94b4b"),
	7: Color("#a03c3c"),
}

var _c: Node = null
var _root: Control = null
var _info: FGUIObject = null
var _friend: Dictionary = {}
var on_back: Callable = Callable()
var on_tab: Callable = Callable()
var on_send: Callable = Callable()          # on_send(item_id: String, batch: bool)
var _batch: bool = false
var _gift_row: HBoxContainer = null
var _gift_scroll: ScrollContainer = null
var _quality_tag: PanelContainer = null
var _name_banner: PanelContainer = null
var _gift_buttons: Dictionary = {}
var _gift_names: Dictionary = {}


static func ensure_packages() -> bool:
	for pkg_name in PKGS:
		if FGUIPackage.get_by_name(pkg_name) != null:
			continue
		if not FGUIPackage.add_package(PKG_DIR + pkg_name + ".fui"):
			return false
	return true


func _init(p_c: Node) -> void:
	_c = p_c
	name = "FriendDetailFgui"


func ensure_built(parent: Node) -> bool:
	if _root != null:
		return true
	if not is_inside_tree() and parent != null:
		parent.add_child(self)
	if not ensure_packages():
		return false

	_root = Control.new()
	_root.name = "FriendDetailFguiRoot"
	_root.clip_contents = true
	_root.size = WIN_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	var pkg := FGUIPackage.get_by_name("Beauty")
	if pkg == null:
		return false
	_info = pkg.create_object("Info")
	if _info == null or _info.node == null:
		return false
	var host := Control.new()
	host.name = "InfoHost"
	host.size = WIN_SIZE
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(host)
	host.add_child(_info.node)

	# 友好/才华那两颗球上的光效（intimacyEffect / glamourEffect）是「赠送特效」，
	# 原件默认一直循环播，这里先停住，赠送时再各播一次
	for eff_name in ["intimacyEffect", "glamourEffect"]:
		var eff: FGUIObject = _info.get_child(eff_name)
		if eff != null and eff is FGUIObject:
			if "playing" in eff:
				eff.set("playing", false)

	# 原件里有几个部件默认隐藏/被控制器关掉，这里强制拉起来
	for show_name in ["closeItem", "btnTravelBook", "btnInfo", "btnSkill", "btnPromotion", "btnPatronize", "btnSkin", "nameItem", "itemList", "btnSend"]:
		var so: FGUIObject = _info.get_child(show_name)
		if so != null:
			so.visible = true

	# 原作里点立绘进入的 Spine 容器：我们暂时不用，隐藏掉免得留空槽
	for hide_name in ["skeletonDefault1", "skeletonDefault2", "skeletonContainer", "btnTouch", "btnPrev", "btnNext", "btnToggle2", "txt_mulUse2"]:
		var n: FGUIObject = _info.get_child(hide_name)
		if n != null:
			n.visible = false

	# 赠送特效默认藏起来（原件是循环播放，不藏会一直卡在最亮的一帧）
	for fx_name in ["intimacyEffect", "glamourEffect"]:
		var fx: FGUIObject = _info.get_child(fx_name)
		if fx != null:
			fx.visible = false

	# 场景背景：原件 bgIcon 是 750×1800 的 loader，直接喂图（原作房间图 bg2）
	var bg_loader: FGUIObject = _info.get_child("bgIcon")
	if bg_loader is FGUILoader:
		var bg_path := "res://assets/backgrounds/bg_friend_detail.png"
		if ResourceLoader.exists(bg_path):
			(bg_loader as FGUILoader).url = bg_path
		bg_loader.visible = true

	_fix_fonts(_info)

	# 标题：复用列表页那个「‹ 返回 + 标题」原件，只改字
	var close_item: FGUIObject = _info.get_child("closeItem")
	if close_item != null:
		_fill_title(close_item, "挚友培养")
		var btn: FGUIButton = close_item.get_child("btnClose") as FGUIButton
		if btn != null:
			btn.on_click(func() -> void:
				if on_back.is_valid():
					on_back.call()
			)

	# 左侧四个功能钮
	var tab_map := {"btnSkill": "skill", "btnPromotion": "fame", "btnPatronize": "play", "btnSkin": "cos"}
	for btn_name in tab_map.keys():
		var b: FGUIButton = _info.get_child(btn_name) as FGUIButton
		if b == null:
			continue
		var key := str(tab_map[btn_name])
		b.on_click(func() -> void:
			if on_tab.is_valid():
				on_tab.call(key)
		)

	_build_overlay()

	_layout(null)
	resized.connect(_layout)
	return true


func set_friend(info: Dictionary) -> void:
	_friend = info
	if _info == null:
		return
	var fid := str(info.get("id", ""))
	var path := PORTRAIT_DIR + fid + ".png"
	var tex: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null

	# 立绘：icon 是整页 GLoader，bgIcon 是背景条
	for loader_name in ["icon"]:
		var obj: FGUIObject = _info.get_child(loader_name)
		var l := obj as FGUILoader
		if l != null and tex != null:
			l.url = path      # GLoader 只认 url（res:// 会走外部贴图）

	# 名字区：原件把「品质字」和「名字」拆成上下两段
	var name_item: FGUIObject = _info.get_child("nameItem")
	if name_item != null:
		_apply_name_item(name_item, info)

	# 友好 / 才华
	var fi := _info.get_child("txtIntimacy") as FGUITextField
	if fi != null:
		fi.text = str(int(info.get("friendly", 0)))
	var gl := _info.get_child("txtGlamour") as FGUITextField
	if gl != null:
		gl.text = str(int(info.get("talent", 0)))


func _layout(_arg = null) -> void:
	if _root == null:
		return
	var area: Vector2 = size if size.x > 0.0 else get_viewport_rect().size
	_root.size = WIN_SIZE
	var s: float = area.x / WIN_SIZE.x
	_root.scale = Vector2(s, s)


## 原件里左侧四钮 / 返回 的图形来自别的包（Beauty 只导出了一张特效图集），
## 原件画出来是空白，这里用同样的坐标补一层自绘按钮，位置与原作一致。
func _build_overlay() -> void:
	var layer := Control.new()
	layer.name = "Overlay"
	layer.size = WIN_SIZE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(layer)


	# 旅行册：原件按钮带白边（图集切边没去干净），用自绘按钮盖掉
	var travel: FGUIObject = _info.get_child("btnTravelBook")
	if travel != null:
		travel.visible = false
	var travel_btn := Button.new()
	travel_btn.text = ""
	travel_btn.focus_mode = Control.FOCUS_NONE
	travel_btn.position = Vector2(596, 40)
	travel_btn.size = Vector2(120, 120)
	var travel_sb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		travel_btn.add_theme_stylebox_override(st, travel_sb)
	if ResourceLoader.exists("res://assets/ui/btn/travel.png"):
		var t_tr := TextureRect.new()
		t_tr.texture = load("res://assets/ui/btn/travel.png") as Texture2D
		t_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t_tr.size = Vector2(120, 120)
		t_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		travel_btn.add_child(t_tr)
	travel_btn.name = "TravelBtn"
	layer.add_child(travel_btn)

	# 六枚功能钮：原件图里烘焙着低分辨率文字，改用豆姐新画的高清图
	# （新图自带文字，所以把原件图标层、文本层、我们原来的自绘标签全部让位）
	var icon_art := {
		"btnSkill": "skill",
		"btnPromotion": "fame",
		"btnPatronize": "play",
		"btnSkin": "cos",
		"btnPeerless": "peerless",
		"btnLooks": "looks",
	}
	for btn_key in icon_art.keys():
		var btn_obj: FGUIObject = _info.get_child(btn_key)
		if btn_obj == null:
			continue
		_hide_texts(btn_obj)
		var old_art: FGUIObject = btn_obj.get_child("n0")
		if old_art != null:
			old_art.visible = false
		var tex_path := "res://assets/ui/btn/%s.png" % str(icon_art[btn_key])
		if not ResourceLoader.exists(tex_path):
			continue
		var tr := TextureRect.new()
		tr.name = "Art_" + str(icon_art[btn_key])
		tr.texture = load(tex_path) as Texture2D
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(120, 120)
		tr.position = btn_obj.node.position + Vector2((btn_obj.width - 120.0) * 0.5, (btn_obj.height - 120.0) * 0.5)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tr)

	_build_gift_row(layer)


	# 左侧四钮现在用原件（Beauty.BtnSkill 等的图标来自 Common2 包，已随包导入）。


func _mk_button(label: String, pos: Vector2, box: Vector2) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = box
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color("#f0dcb4"))
	b.add_theme_color_override("font_outline_color", Color("#2a1a0c"))
	b.add_theme_constant_override("outline_size", 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.09, 0.06, 0.72)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.58, 0.44, 0.24, 0.9)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	return b


## 礼物栏：原件 itemList 是空 FGUIList，这里按背包格子的样式补一排
## 横滑、只有「图标 + 品质描边 + 数量」，不显示名字
func _build_gift_row(layer: Control) -> void:
	_gift_scroll = ScrollContainer.new()
	_gift_scroll.name = "GiftScroll"
	_gift_scroll.position = Vector2(40, 1150)
	_gift_scroll.size = Vector2(436, 104)
	_gift_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_gift_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layer.add_child(_gift_scroll)

	_gift_row = HBoxContainer.new()
	_gift_row.name = "GiftRow"
	_gift_row.add_theme_constant_override("separation", 8)
	_gift_scroll.add_child(_gift_row)

	# 赠送键（原件 btnSend）
	var send := _info.get_child("btnSend") as FGUIButton
	if send != null:
		send.on_click(func() -> void:
			var picked := ""
			for gid in _gift_buttons.keys():
				if (_gift_buttons[gid] as Button).button_pressed:
					picked = str(gid)
					break
			if on_send.is_valid():
				on_send.call(picked, _batch)
		)
	# 十连赠送（原件 btnToggle）
	var toggle := _info.get_child("btnToggle") as FGUIButton
	if toggle != null:
		toggle.on_click(func() -> void:
			_batch = not _batch
			_update_batch_text()
		)
	_update_batch_text()


func _update_batch_text() -> void:
	var t1 := _info.get_child("txt_mulUse") as FGUITextField
	if t1 != null:
		t1.text = "十连赠送"


## rows: [{id, name, icon, count, quality}]
func set_gifts(rows: Array) -> void:
	if _gift_row == null:
		return
	for ch in _gift_row.get_children():
		ch.queue_free()
	_gift_buttons.clear()
	_gift_names.clear()
	for row in rows:
		var gid := str(row.get("id", ""))
		_gift_names[gid] = str(row.get("name", gid))
		var count := int(row.get("count", 0))
		var q := clampi(int(row.get("quality", 0)), 0, 7)

		var btn := Button.new()
		btn.name = "Gift_" + gid
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(96, 96)
		btn.size = Vector2(96, 96)
		btn.text = ""
		btn.disabled = count <= 0
		btn.tooltip_text = str(row.get("name", gid))

		# 图标铺满格子
		var icon_path := str(row.get("icon", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var tex := load(icon_path) as Texture2D
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.position = Vector2(4, 4)
				tr.size = Vector2(88, 88)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(tr)

		# 数量（右下角）
		var ct := Label.new()
		ct.text = str(count)
		ct.add_theme_font_size_override("font_size", 18)
		ct.add_theme_color_override("font_color", Color("#fff1cf"))
		ct.add_theme_color_override("font_outline_color", Color("#2a1a0c"))
		ct.add_theme_constant_override("outline_size", 4)
		ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ct.position = Vector2(0, 66)
		ct.size = Vector2(88, 24)
		ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(ct)

		# 品质描边（背包格子同款配色）
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.11, 0.07, 0.9)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(3)
		sb.border_color = QUALITY_COLORS.get(q, Color("#6b5a44"))
		btn.add_theme_stylebox_override("normal", sb)
		var sb_on := sb.duplicate() as StyleBoxFlat
		sb_on.border_color = Color(1, 0.9, 0.6)
		btn.add_theme_stylebox_override("pressed", sb_on)
		btn.add_theme_stylebox_override("hover", sb)
		btn.pressed.connect(func() -> void:
			for other in _gift_buttons.values():
				var ob := other as Button
				if ob != null and ob != btn:
					ob.button_pressed = false
		)
		_gift_row.add_child(btn)
		_gift_buttons[gid] = btn


## 在 closeItem 里找一个短文本域当标题（与列表页同一套做法）
func _fill_title(node: FGUIObject, title: String) -> void:
	if node == null:
		return
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


## 名字区：原件把「品质字 + 名字」做在 nameItem 里（96×274 @55,185）。
## 原件底图 qualityItem 的七档品质底带控制器但插件取不到页号，这里在原位置自绘竖牌：
## 上半截品质字（普通/优秀/卓越/传奇/无双）+ 下半截名字，整体染品质色。
## 原件里不少文本域绑的是位图字体（.fui 内嵌字形没导出会画成乱码），统一换成我们的 TTF
## 隐藏原件里的文字域（位图字体乱码）
func _hide_texts(obj: FGUIObject) -> void:
	if obj is FGUITextField:
		obj.visible = false
		return
	if not (obj is FGUIComponent or obj is FGUIList):
		return
	for i in obj.num_children:
		_hide_texts(obj.get_child_at(i))


func _fix_fonts(obj: FGUIObject) -> void:
	if obj is FGUITextField:
		var t := obj as FGUITextField
		# 友好/才华这两个数值域保留原作的位图字体 IntimacyFont（它只含数字字形）
		if t.name == "txtIntimacy" or t.name == "txtGlamour":
			return
		if t.font.begins_with("ui://"):
			t.visible = false          # 位图字体画中文只会出一片噪点，整块藏掉
		return
	if not (obj is FGUIComponent or obj is FGUIList):
		return
	for i in obj.num_children:
		_fix_fonts(obj.get_child_at(i))


func _apply_name_item(name_item: FGUIObject, info: Dictionary) -> void:
	var q := clampi(int(info.get("quality", 1)), 1, 5)
	for hide_name in ["qualityItem", "txtName", "txtName1", "txtName2", "krNameGroup"]:
		var n: FGUIObject = name_item.get_child(hide_name)
		if n != null:
			n.visible = false

	if _name_banner != null and is_instance_valid(_name_banner):
		_name_banner.queue_free()
	var banner := PanelContainer.new()
	banner.name = "NameBanner"
	var color: Color = QUALITY_COLORS.get(q, Color("#7f8a93"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.99, 0.93, 0.78, 0.95)
	banner.add_theme_stylebox_override("panel", sb)
	banner.position = name_item.node.position + Vector2(0, 0)
	banner.custom_minimum_size = Vector2(name_item.width, name_item.height)
	banner.size = Vector2(name_item.width, name_item.height)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(box)

	var ql := Label.new()
	ql.text = "\n".join(str(QUALITY_NAMES[q]).split())
	ql.add_theme_font_size_override("font_size", 26)
	ql.add_theme_color_override("font_color", Color("#fff8e6"))
	ql.add_theme_color_override("font_outline_color", Color("#3b2410"))
	ql.add_theme_constant_override("outline_size", 5)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ql)

	var nl := Label.new()
	nl.text = "\n".join(str(info.get("name", "")).split())
	nl.add_theme_font_size_override("font_size", 24)
	nl.add_theme_color_override("font_color", Color("#fff8e6"))
	nl.add_theme_color_override("font_outline_color", Color("#3b2410"))
	nl.add_theme_constant_override("outline_size", 5)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(nl)

	_root.add_child(banner)
	_name_banner = banner


## 赠送后刷新数值 + 播一次特效
func refresh_stats(info: Dictionary) -> void:
	_friend = info
	if _info == null:
		return
	var fi := _info.get_child("txtIntimacy") as FGUITextField
	if fi != null:
		fi.text = str(int(info.get("friendly", 0)))
	var gl := _info.get_child("txtGlamour") as FGUITextField
	if gl != null:
		gl.text = str(int(info.get("talent", 0)))
	for eff_name in ["intimacyEffect", "glamourEffect"]:
		var eff: FGUIObject = _info.get_child(eff_name)
		if eff != null and "playing" in eff:
			eff.set("playing", true)
			eff.set("playing", false)
