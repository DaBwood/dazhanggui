extends Control
# 挚友仪容技能页：整窗套用原作 FGUI（BeautyLooks.Main）
# 结构：n9 大插画 / skillItem1+2 两条仪容技能 / btnClose 返回 / btnPrev.btnNext 翻页
# 数据：data/friends.json 的 caiyi_skills（duocai / chaoqun）

const PKG_DIR := "res://assets/fgui/"
const PKGS: Array = ["Basic", "Basic2", "Basic3", "Items", "Common2", "BeautyLooks"]
const WIN_SIZE := Vector2(750, 1334)
var SKILL_DEF: Array = [
	["duocai", "花颜月貌", "资质", "170000"],
	["chaoqun", "绝世佳人", "赚钱", "171000"],
]




var _c: Node = null
var _root: Control = null
var _main: FGUIComponent = null
var _friend: Dictionary = {}

var on_back: Callable = Callable()


func _init(p_c: Node) -> void:
	_c = p_c
	name = "FriendLooksFgui"
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false


func _bind_close(obj: FGUIObject) -> bool:
	var btn := obj as FGUIButton
	if btn != null:
		btn.on_click(func() -> void:
			if on_back.is_valid():
				on_back.call()
		)
		return true
	var comp := obj as FGUIComponent
	if comp != null:
		for i in range(comp.num_children):
			var ch: FGUIObject = comp.get_child_at(i)
			if ch != null and _bind_close(ch):
				return true
	var control := obj.node as Control
	if control != null:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
				if on_back.is_valid():
					on_back.call()
		)
		return true
	return false


func ensure_built(_parent: Node) -> bool:
	if _main != null:
		return true
	if not ensure_packages():
		return false
	var pkg := FGUIPackage.get_by_name("BeautyLooks")
	if pkg == null:
		return false
	_main = pkg.create_object("Main") as FGUIComponent
	if _main == null:
		return false
	_root = Control.new()
	_root.name = "LooksRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_root.add_child(_main.node)
	_main.node.position = Vector2.ZERO

	# 标题（原件 title 字段空着）
	var frame_obj: FGUIObject = _main.get_child("frame")
	if frame_obj != null:
		var title_obj: FGUIObject = (frame_obj as FGUIComponent).get_child("title")
		if title_obj is FGUITextField:
			(title_obj as FGUITextField).text = "仪容技能"

	# 关闭：原件 btnClose 图形缺失 → 换成我们弹窗那盏灯笼
	var close_item: FGUIObject = _main.get_child("btnClose")
	if close_item != null:
		close_item.visible = false
	_build_backdrop()
	_build_lantern_close()
	# 翻页暂时无效（只有一位挚友的两条才艺）
	for hide_name in ["btnPrev", "btnNext"]:
		var nav: FGUIObject = _main.get_child(hide_name)
		if nav != null:
			nav.visible = false

	_parent.add_child(self)
	_layout()
	resized.connect(_layout)
	return true


static func ensure_packages() -> bool:
	for p in PKGS:
		if FGUIPackage.get_by_name(str(p)) != null:
			continue
		if not FGUIPackage.add_package(PKG_DIR + str(p) + ".fui"):
			return false
	return true


func set_friend(info: Dictionary) -> void:
	_friend = info
	if _main == null:
		return
	var fid := str(info.get("id", ""))
	var fcfg: Dictionary = {}
	if _c != null and _c.data != null:
		fcfg = _c.data.get_friend_config(fid)
	var caiyi: Dictionary = fcfg.get("caiyi_skills", {})
	var category := str(fcfg.get("category", ""))
	for i in range(SKILL_DEF.size()):
		var item: FGUIObject = _main.get_child("skillItem%d" % (i + 1))
		if item == null:
			continue
		_fill_item(item, i, caiyi, category)


func _fill_item(item: FGUIObject, idx: int, caiyi: Dictionary, category: String) -> void:
	var def_row: Array = SKILL_DEF[idx]
	var key := str(def_row[0])
	var title := str(def_row[1])
	var kind := str(def_row[2])
	var icon_id := str(def_row[3])
	var lv := int(caiyi.get(key, 0))

	var name_txt := item.get_child("txtAttrName") as FGUITextField
	if name_txt != null:
		name_txt.text = title
	# 等级：类别 + 级数（原作是「士117级」这种写法）
	var lv_txt := item.get_child("txtValueName") as FGUITextField
	if lv_txt != null:
		lv_txt.text = "%s%d级" % [category, lv]
	# 效果：所有<类别>人门客 资质/赚钱 +数值
	var attr_txt := item.get_child("txtAttr") as FGUITextField
	if attr_txt != null:
		if kind == "资质":
			attr_txt.text = "所有%s人门客资质+%d" % [category, lv]
		else:
			attr_txt.text = "所有%s人门客赚钱+%d%%" % [category, lv * 1]
	# 下级预览：没有成长表，先空着
	for hide_name in ["txtNext", "btnUpgradeTen", "fullImg", "costIcon", "btnInfo", "effectAni"]:
		var extra: FGUIObject = item.get_child(hide_name)
		if extra != null:
			extra.visible = false

	# 图标：先用 skills_beauty 里的两张（花 / 月），后续再按真实映射换
	var icon_loader := item.get_child("icon") as FGUILoader
	if icon_loader != null:
		var path := "res://assets/skills_beauty/%s.png" % icon_id
		if ResourceLoader.exists(path):
			icon_loader.url = path

	var up_btn := item.get_child("btnUpgrade") as FGUIButton
	if up_btn != null:
		up_btn.on_click(func() -> void:
			if _c != null:
				_c._show_success_popup("仪容技能升级后续版本开放", 0.0, "warn")
		)


func _build_lantern_close() -> void:
	# 复用弹窗右上角那盏灯笼（米白灯身 + 朱绳 + 木牌），点击即关闭
	var holder := Control.new()
	holder.name = "LooksLantern"
	holder.position = Vector2(590, 228)
	holder.size = Vector2(96, 250)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(holder)

	var tex := TextureRect.new()
	tex.name = "LanternArt"
	tex.texture = load("res://assets/common/popup_corner_r.png")
	tex.self_modulate = Color(1.0, 0.93, 0.78)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.position = Vector2.ZERO
	tex.size = holder.size
	holder.add_child(tex)

	var hit := Button.new()
	hit.name = "LanternHit"
	hit.flat = true
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hit.position = Vector2(12, 60)
	hit.size = Vector2(64, 120)
	hit.pressed.connect(func() -> void:
		if on_back.is_valid():
			on_back.call()
	)
	holder.add_child(hit)


func _build_backdrop() -> void:
	# 弹窗背后压暗
	var back := ColorRect.new()
	back.name = "LooksBackdrop"
	back.color = Color(0, 0, 0, 0.55)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.size = WIN_SIZE
	back.position = Vector2.ZERO
	_root.add_child(back)
	_root.move_child(back, 0)


func _layout(_arg: Variant = null) -> void:
	if _root == null:
		return
	var area: Vector2 = size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	var s: float = area.x / WIN_SIZE.x
	_root.scale = Vector2(s, s)
	_root.size = WIN_SIZE


func show_page() -> void:
	visible = true
	call_deferred("_layout")


func hide_page() -> void:
	visible = false
