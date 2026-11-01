# ============================================================
# 背包页·原作 FairyGUI 整窗视图（2026-11-01 背包复刻并入）
# 效果基准：背包复刻工程——Bag 包 Main 组件（750×1334 竖屏），
#   依赖 Basic/Basic2/Basic3/Items 四包，必须先全部加载（复刻工程已验证口径）
# 纯 UI 模块：RefCounted，持 c = game_controller、data = GameData（与各页面模块同范式）
# 懒建：首次打开背包页才解析 .fui 与图集；整窗建一次后缓存复用，翻页只切显隐
# 挂点：PageContainer/BagPage 宿主内，等比缩放居中（同复刻工程 main.gd 口径）
# 【实测补充】.fui 内不烘焙标题/页签/下拉文字，格子列表也无默认演示内容
#   （原作由游戏代码运行时注入；复刻工程静态渲染同为空壳，已逐窗实测核对）。
#   故本模块按任务书口径注入静态文字，并把「道具」页签接到主仓真实背包数据：
#   格子数量读 data.items，点击格子复用旧版 _show_item_detail_popup（功能不丢）。
# ============================================================
class_name BagFguiView
extends RefCounted

const PKG_DIR := "res://assets/fgui"   # 背包链路子集（5 包 + 图集，取舍见交付说明）
const PKG_NAMES: Array = ["Basic", "Basic2", "Basic3", "Items", "Bag"]   # 依赖序：Basic 系与 Items 先于 Bag
const WIN_SIZE := Vector2(750, 1334)   # 原作整窗设计尺寸（fgui_parsed.json：Bag/Main 750×1334）
const TAB_TITLES: Array = ["道具", "活动", "合成"]   # 原作三页签文字（任务书口径）

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

var _host: Control = null   # BagPage 宿主节点
var _node: Control = null   # 已实例化的整窗节点（Bag/Main 的 node）
var _comp: FGUIComponent = null   # Bag/Main 的组件包装（get_child/get_controller 用）
var _list: FGUIList = null        # 「道具」页签的 GList（list1）
var _ctrl: FGUIController = null  # 页签控制器 c1（0=道具 1=活动 2=合成）
var _item_ids: Array = []   # 格子数据源（与旧版 _fill_bag_grid 同口径）
var _resize_hooked := false

# 由 bag_page 首次进入 FGUI 模式时创建本模块并注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# 确保整窗已建并挂到背包页；成功返回 true，失败返回 false（调用方回退旧版）
func ensure_built(host: Control) -> bool:
	if is_instance_valid(_node):
		_layout()
		refresh_items()
		return true
	if not _load_packages():
		return false
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Bag")
	if pkg == null:
		push_error("BagFguiView: Bag 包未注册")
		return false
	var view: FGUIObject = pkg.create_object("Main")
	if view == null:
		push_error("BagFguiView: Bag/Main 创建失败")
		return false
	_comp = view as FGUIComponent
	if _comp == null:
		push_error("BagFguiView: Bag/Main 不是组件")
		return false
	_host = host
	_node = view.node
	_node.name = "BagFguiMain"
	host.add_child(_node)
	_inject_static_texts()
	_wire_tabs()
	_wire_close_button()
	_wire_item_list()
	# 窗口尺寸变化时重排（连接晚于 controller._apply_portrait_layout，两栏/页面尺寸先就位）
	if not _resize_hooked:
		_resize_hooked = true
		c.get_tree().root.size_changed.connect(_layout)
	_layout()
	# switch_page 里 update_bag_list 先于 _apply_portrait_layout 执行，
	# 首建时宿主矩形尚未刷新，延迟一帧按最终矩形再排一次
	call_deferred("_layout")
	refresh_items()
	return true

func set_visible(p_visible: bool) -> void:
	if is_instance_valid(_node):
		_node.visible = p_visible

# 等比缩放居中（同背包复刻工程 main.gd 口径：min(宽比, 高比)，居中摆放）
func _layout() -> void:
	if not is_instance_valid(_host) or not is_instance_valid(_node):
		return
	var hs: Vector2 = _host.size
	if hs.x <= 0.0 or hs.y <= 0.0:
		return
	var s: float = minf(hs.x / WIN_SIZE.x, hs.y / WIN_SIZE.y)
	_node.scale = Vector2(s, s)
	_node.position = (hs - WIN_SIZE * s) / 2.0

# 加载五包（FGUIPackage 静态注册表按名去重，重复调用幂等）
func _load_packages() -> bool:
	for pkg_name in PKG_NAMES:
		if FGUIPackage.get_by_name(pkg_name) != null:
			continue
		var pkg: FGUIPackage = FGUIPackage.add_package(PKG_DIR + "/" + pkg_name)
		if pkg == null:
			push_error("BagFguiView: " + pkg_name + " 包加载失败")
			return false
	return true

# ── 静态文字注入：.fui 未烘焙（实测），按任务书口径补齐标题/页签/底部下拉 ──
func _inject_static_texts() -> void:
	var close_comp := _comp.get_child("closeItem") as FGUIComponent
	if close_comp != null:
		var title_obj := close_comp.get_child("txtTitle")
		if title_obj != null:
			title_obj.text = "背包"
	for i in range(1, 4):
		for prefix in ["btnTabSelected", "btnTabUnSelect"]:
			var tab := _comp.get_child(prefix + str(i))
			if tab != null:
				tab.title = TAB_TITLES[i - 1]
	var combo_use := _comp.get_child("comboUse")
	if combo_use != null:
		combo_use.get_child("title").text = "所有"   # GComboBox.title 只读，写子文本（插件 0.6.0 实测）
	var combo_quality := _comp.get_child("comboQuality")
	if combo_quality != null:
		combo_quality.get_child("title").text = "品质"

# ── 页签接线：点击切换控制器 c1（0=道具 1=活动 2=合成；2/3 列表数据后续接）──
func _wire_tabs() -> void:
	_ctrl = _comp.get_controller("c1")
	for i in range(1, 4):
		var tab_idx: int = i - 1   # 循环体局部量，供 lambda 按值捕获
		for prefix in ["btnTabSelected", "btnTabUnSelect"]:
			var tab := _comp.get_child(prefix + str(i))
			if tab != null:
				tab.on_click(func(_event = null): _on_tab_clicked(tab_idx))

func _on_tab_clicked(tab_idx: int) -> void:
	if _ctrl != null:
		_ctrl.selected_index = tab_idx

# ── 接线原作关闭钮（closeItem/btnClose）：回府邸页（对齐原作"关闭背包回主界面"语义）──
func _wire_close_button() -> void:
	var close_comp := _comp.get_child("closeItem") as FGUIComponent
	if close_comp == null:
		return
	var btn_close := close_comp.get_child("btnClose")
	if btn_close != null:
		btn_close.on_click(_on_close_clicked)

func _on_close_clicked(_event = null) -> void:
	c.switch_page("mansion")

# ── 「道具」列表接线：数据源与旧版 _fill_bag_grid 同口径（只列已拥有、跳过隐藏道具）──
func _wire_item_list() -> void:
	_list = _comp.get_child("list1")
	if _list == null:
		push_error("BagFguiView: list1 缺失")
		return
	_list.item_renderer = _on_item_render

# 刷新格子（背包数据变化/进页时由 bag_page.generate_bag_list 调用）
func refresh_items() -> void:
	if _list == null:
		return
	_item_ids.clear()
	for item_id in data.ITEM_CONFIG.keys():
		var cfg: Dictionary = data.ITEM_CONFIG[item_id]
		if cfg.get("hide_in_bag", false):
			continue
		var count: int = _get_item_count(item_id)
		if count <= 0:
			continue
		_item_ids.append(item_id)
	_list.num_items = _item_ids.size()
	# 插件 0.6.0 实测：非虚拟列表 num_items 只建池不回调 renderer，手动补一轮
	for i in range(_list.num_items):
		_on_item_render(i, _list.get_child_at(i))

func _get_item_count(item_id: String) -> int:
	if item_id == "lottery_ticket":
		return int(data.lottery_ticket)
	return int(data.items.get(item_id, 0))

# 格子渲染：数量入 txtCount；原作格子只有图标+数量，主仓暂无图标映射，
# 补一个不抢戏的名字小标签（node 子节点，明确标识 BagNameLabel，后续接图标映射时移除）
func _on_item_render(index: int, obj: FGUIObject) -> void:
	if index < 0 or index >= _item_ids.size():
		return
	var item_id: String = _item_ids[index]
	var cfg: Dictionary = data.ITEM_CONFIG.get(item_id, {})
	var comp := obj as FGUIComponent
	if comp != null:
		var cnt := comp.get_child("txtCount")
		if cnt != null:
			cnt.text = "x%d" % _get_item_count(item_id)
	if obj.node != null:
		obj.node.set_meta("bag_item_id", item_id)
		_ensure_name_label(obj.node, str(cfg.get("name", item_id)))
		if not obj.node.has_meta("bag_click_wired"):
			obj.node.set_meta("bag_click_wired", true)
			obj.on_click(_on_cell_clicked.bind(obj))

# 格子名字小标签（格子节点底部居中，不改动 FGUI 对象树结构）
func _ensure_name_label(cell_node: Control, name_text: String) -> void:
	var lbl: Label
	if cell_node.has_node("BagNameLabel"):
		lbl = cell_node.get_node("BagNameLabel")
	else:
		lbl = Label.new()
		lbl.name = "BagNameLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不挡格子点击
		cell_node.add_child(lbl)
	lbl.text = name_text
	lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lbl.position = Vector2(0, cell_node.size.y - 18)
	lbl.size = Vector2(cell_node.size.x, 18)

# 点击格子：复用旧版详情弹窗（数量选择/使用/各类盒子选择器全部保留）
# 注意参数序：bind(obj) 追加在事件参数之后，实际回调签名是 (event, obj)
func _on_cell_clicked(_event = null, obj: FGUIObject = null) -> void:
	if obj == null or obj.node == null or not obj.node.has_meta("bag_item_id"):
		return
	var item_id: String = obj.node.get_meta("bag_item_id")
	c.bag_page._show_item_detail_popup(item_id)
