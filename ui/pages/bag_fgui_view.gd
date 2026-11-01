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
const ICON_DIR := "res://assets/items/icons/"       # 道具图标库（原作 6 位图标 id 命名，2026-11-01 入库）
const ICON_MAP_PATH := "res://data/item_icon_map.json"   # 工程道具 id -> 图标 id + quality 映射
const FONT_UI := "res://assets/fonts/MNJYH.ttf"     # 原作 UI 字体「迷你简艺黑」（media/_uuid/MNJYH.ttf 提取）
# 「活动」页签数据源：活动限定产出的道具 id（原作由活动系统下发，本工程暂无活动玩法，
# 现阶段按显式清单列举——加活动道具就往这里加 id，加完自动出现在活动页签）
const EVENT_ITEM_IDS: Array = ["lottery_ticket"]

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

var _host: Control = null   # BagPage 宿主节点
var _node: Control = null   # 已实例化的整窗节点（Bag/Main 的 node）
var _comp: FGUIComponent = null   # Bag/Main 的组件包装（get_child/get_controller 用）
var _list: FGUIList = null        # 「道具」页签的 GList（list1）
var _ctrl: FGUIController = null  # 页签控制器 c1（0=道具 1=活动 2=合成）
var _lists: Array = []      # 三个列表 [list1, list2, list3]（list1/list2 是道具格，list3 是合成格）
var _tab_data: Array = [[], [], []]   # 各页签的数据源（道具：item_id 数组；合成：recipe 字典数组）
var _item_ids: Array = []   # 兼容旧引用：恒等于 _tab_data[0]
var _icon_map: Dictionary = {}   # 道具 id -> {icon, orig, match, file, quality}，懒加载一次
var _icon_cache: Dictionary = {} # 道具 id -> 图标 id（或空串），避免每帧查 ResourceLoader
var _resize_hooked := false

# 由 bag_page 首次进入 FGUI 模式时创建本模块并注入引用
func _init(p_c):
	c = p_c
	data = p_c.data
	# 原作字体：.fui 内未烘焙字体名，FGUIConfig.default_font 是所有 GTextField 的兜底字体
	if ResourceLoader.exists(FONT_UI):
		FGUIConfig.default_font = FONT_UI
	_load_icon_map()

# 道具图标映射（data/item_icon_map.json，由 clean/item_icons 流水线产出；缺失则整表留空，退化为纯文字格子）
func _load_icon_map() -> void:
	if not FileAccess.file_exists(ICON_MAP_PATH):
		push_warning("BagFguiView: 缺少 " + ICON_MAP_PATH + "，背包图标将不显示")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ICON_MAP_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BagFguiView: " + ICON_MAP_PATH + " 解析失败")
		return
	var m: Variant = parsed.get("map", {})
	if typeof(m) == TYPE_DICTIONARY:
		_icon_map = m

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
	# 挂到根节点：整窗是「页面之外」的全屏视图，挂 BagPage（夹在顶底栏之间的空壳）会撑不开
	c.add_child(_node)
	_node.visible = true
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

# 等比缩放铺满内容区（同背包复刻工程 main.gd 口径：min(宽比, 高比)）。
# 【改 2026-11-01】纳入顶栏/底栏：背包页要显示底部导航（用户口径），整窗只能占「夹心区」，
#   否则 1334 高的整窗会盖住底栏；两栏任一隐藏时对应高度自动并入内容区（和 PageContainer 同规则）。
func _layout() -> void:
	if not is_instance_valid(_node):
		return
	var vs: Vector2 = c.get_viewport_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	var top_h: float = 0.0
	if c.has_node("TopBar") and c.get_node("TopBar").visible:
		top_h = c.get_node("TopBar").size.y
	var bot_h: float = 0.0
	if c.has_node("BottomNav") and c.get_node("BottomNav").visible:
		bot_h = c.get_node("BottomNav").size.y
	var area := Rect2(Vector2(0.0, top_h), Vector2(vs.x, maxf(1.0, vs.y - top_h - bot_h)))
	# 【改 2026-11-01】按宽铺满（原作整窗是满宽设计）：等比缩到宽度正好等于视口宽，
	# 多出来的高度（1334 画布 − 夹心区）落到视口下方，被底栏挡住不露白边。
	var s: float = area.size.x / WIN_SIZE.x
	_node.scale = Vector2(s, s)
	_node.position = Vector2(area.position.x, area.position.y)

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

# ── 页签接线：点击切换控制器 c1（0=道具 1=活动 2=合成；三个列表都已经接真数据）──
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
	_update_empty_hint()

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

# ── 三个列表接线：list1=道具 list2=活动 list3=合成（三者格子组件同构：bgItem/icon/bgCount/txtCount）──
func _wire_item_list() -> void:
	_lists.clear()
	for nm in ["list1", "list2", "list3"]:
		var lst := _comp.get_child(nm) as FGUIList
		_lists.append(lst)
	_list = _lists[0] as FGUIList
	for tab in _lists.size():
		var lst := _lists[tab] as FGUIList
		if lst == null:
			push_error("BagFguiView: list" + str(tab + 1) + " 缺失")
			continue
		lst.item_renderer = _on_cell_render.bind(tab)

# 刷新三个页签的格子（数据变化/进页时由 bag_page.generate_bag_list 调用）
func refresh_items() -> void:
	if _lists.is_empty():
		return
	_tab_data[0] = _owned_item_ids(false)   # 道具：全部已拥有
	_tab_data[1] = _owned_item_ids(true)    # 活动：EVENT_ITEM_IDS 中已拥有的
	_tab_data[2] = _compose_entries()       # 合成：配方（显示产出物 + 现有数量）
	_item_ids = _tab_data[0]
	for tab in _lists.size():
		var lst := _lists[tab] as FGUIList
		if lst == null:
			continue
		var arr: Array = _tab_data[tab]
		lst.num_items = arr.size()
		# 插件 0.6.0 实测：非虚拟列表 num_items 只建池不回调 renderer，手动补一轮
		for i in range(lst.num_items):
			_on_cell_render(i, lst.get_child_at(i), tab)
	_update_empty_hint()

# 空列表提示：只在当前页签的列表为空时显示原作 txtEmpty
func _update_empty_hint() -> void:
	var empty_obj := _comp.get_child("txtEmpty")
	if empty_obj == null:
		return
	var tab: int = 0
	if _ctrl != null:
		tab = _ctrl.selected_index
	if tab < 0 or tab >= _tab_data.size():
		tab = 0
	var is_empty: bool = (_tab_data[tab] as Array).is_empty()
	if is_empty:
		if empty_obj is FGUITextField:
			(empty_obj as FGUITextField).text = "暂无道具"
		# 【修】txtCount/bgCount 在第一次渲染时被提到最上层；提示文字也要压过格子池
		if empty_obj.node != null:
			empty_obj.node.z_index = 5
	empty_obj.visible = is_empty

# 已拥有道具 id 列表；only_event=true 时只取 EVENT_ITEM_IDS 里的（活动页签）
func _owned_item_ids(only_event: bool) -> Array:
	var out: Array = []
	var src: Array = EVENT_ITEM_IDS if only_event else data.ITEM_CONFIG.keys()
	for item_id in src:
		if not data.ITEM_CONFIG.has(item_id):
			continue
		var cfg: Dictionary = data.ITEM_CONFIG[item_id]
		if cfg.get("hide_in_bag", false):
			continue
		if _get_item_count(item_id) <= 0:
			continue
		out.append(item_id)
	return out

# 合成页签条目：产出一格（配方字典原样带上，点击开合成弹窗）
# 产出是珍兽（output_type=beast）时 id 不在 ITEM_CONFIG 里，名字/数量走珍兽分支
func _compose_entries() -> Array:
	var out: Array = []
	for recipe in c.bag_page.COMPOSE_RECIPES:
		out.append(recipe)
	return out

func _get_item_count(item_id: String) -> int:
	if item_id == "lottery_ticket":
		return int(data.lottery_ticket)
	return int(data.items.get(item_id, 0))

# 格子渲染（三页签共用）：道具/活动格 = 图标 + 数量；合成格 = 产出物图标 + 现有数量，点击开合成弹窗
func _on_cell_render(index: int, obj: FGUIObject, tab: int = 0) -> void:
	if obj == null or tab < 0 or tab >= _tab_data.size():
		return
	var arr: Array = _tab_data[tab]
	if index < 0 or index >= arr.size():
		return
	var entry: Variant = arr[index]
	var recipe: Dictionary = {}
	var item_id := ""
	var count := 0
	if entry is Dictionary:
		recipe = entry
		item_id = str(recipe.get("output", ""))
		count = _recipe_count(recipe)
	else:
		item_id = str(entry)
		count = _get_item_count(item_id)
	var cfg: Dictionary = data.ITEM_CONFIG.get(item_id, {})
	var display_name := str(cfg.get("name", ""))
	if display_name == "" and recipe.has("output_type") and str(recipe.output_type) == "beast":
		display_name = _beast_name(item_id)
	if display_name == "":
		display_name = item_id
	_decorate_cell(obj, item_id, count, display_name)
	if obj.node != null:
		if recipe.is_empty():
			obj.node.set_meta("bag_item_id", item_id)
			if not obj.node.has_meta("bag_click_wired"):
				obj.node.set_meta("bag_click_wired", true)
				obj.on_click(_on_cell_clicked.bind(obj))
		else:
			obj.node.set_meta("bag_recipe", recipe)
			if not obj.node.has_meta("bag_compose_click_wired"):
				obj.node.set_meta("bag_compose_click_wired", true)
				obj.on_click(_on_compose_cell_clicked.bind(obj))

# 格子装饰：数量条层级/位图字体兜底/数字/品质底图/图标/缺图时的名字小标签
func _decorate_cell(obj: FGUIObject, item_id: String, count: int, display_name: String) -> void:
	var comp := obj as FGUIComponent
	if comp == null:
		return
	var cnt := comp.get_child("txtCount")
	if cnt != null:
		# bgCount（半透明黑数量条）在 .fui 里排在 icon 之前，被 114×114 图标盖住；
		# 原作数量条压在图标底部 → 把 bgCount 与 txtCount 提到最上层（每格只调一次）
		if obj.node != null and not obj.node.has_meta("bag_count_on_top"):
			var bgc := comp.get_child("bgCount")
			if bgc != null:
				comp.set_child_index(bgc, comp.num_children - 1)
				if bgc.node != null:
					bgc.node.z_index = 2
			comp.set_child_index(cnt, comp.num_children - 1)
			if cnt.node != null:
				cnt.node.z_index = 3
			obj.node.set_meta("bag_count_on_top", true)
		# .fui 里 txtCount 绑的是位图字体「ui://sq0gzulmk5ti1s5」，我们没导出该资源 →
		# 位图分支字形宽度为 0、数字全叠一格；显式指到 TTF 路径即可走动态字体分支
		if cnt.font.begins_with("ui://"):
			cnt.font = FONT_UI
		# 原作格子只写数字（右下角），不写 "x" 前缀
		cnt.text = str(count)
	_apply_cell_quality(comp, _quality_for(item_id))
	var has_icon := _apply_cell_icon(comp, _icon_id_for(item_id))
	if obj.node != null:
		_ensure_name_label(obj.node, display_name, not has_icon)

# 合成条目的现有份数：珍兽走珍兽仓，道具走背包
func _recipe_count(recipe: Dictionary) -> int:
	var out_id := str(recipe.get("output", ""))
	if str(recipe.get("output_type", "")) == "beast":
		if data.has_method("get_beast_instance_count"):
			return int(data.get_beast_instance_count(out_id))
		return int(data.beasts.get(out_id, 0))
	return _get_item_count(out_id)

func _beast_name(beast_id: String) -> String:
	if data.has_method("get_beast_config"):
		var cfg: Dictionary = data.get_beast_config(beast_id)
		if not cfg.is_empty():
			return str(cfg.get("name", beast_id))
	return beast_id

# 合成格点击：开合成弹窗（弹窗本体留在 bag_page，行为与旧版一致）
func _on_compose_cell_clicked(_event = null, obj: FGUIObject = null) -> void:
	if obj == null or obj.node == null or not obj.node.has_meta("bag_recipe"):
		return
	var recipe: Dictionary = obj.node.get_meta("bag_recipe")
	c.bag_page._show_compose_popup(recipe)

# 品质（1-5，来自原作道具表；0=未知）→ 格子底图 bgItem 的控制器 c1 页码 0-6
func _quality_for(item_id: String) -> int:
	var ent: Dictionary = _icon_map.get(item_id, {})
	return int(ent.get("quality", 0))

func _apply_cell_quality(comp: FGUIComponent, quality: int) -> void:
	if comp == null or quality <= 0:
		return
	var bg := comp.get_child("bgItem") as FGUIComponent
	if bg == null:
		return
	var ctrl: FGUIController = bg.get_controller("c1")
	if ctrl == null:
		return
	ctrl.selected_index = clampi(quality - 1, 0, 6)

# 取映射里的 6 位图标 id；无映射或文件缺失返回空串（结果缓存：每帧刷新不重复查盘）
func _icon_id_for(item_id: String) -> String:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var found := ""
	var ent: Dictionary = _icon_map.get(item_id, {})
	if not ent.is_empty():
		var icon_id := str(ent.get("icon", ""))
		if icon_id != "" and ResourceLoader.exists(ICON_DIR + icon_id + ".png"):
			found = icon_id
	_icon_cache[item_id] = found
	return found

# 把图标塞进格子组件的 icon 槽（FGUILoader 走 _load_external，res:// 路径直接 load 成贴图）
func _apply_cell_icon(comp: FGUIComponent, icon_id: String) -> bool:
	if comp == null:
		return false
	var loader := comp.get_child("icon") as FGUILoader
	if loader == null:
		return false
	if icon_id == "":
		loader.url = ""
		return false
	loader.url = ICON_DIR + icon_id + ".png"
	return true

# 格子名字小标签（仅在无图标时显示；有图标时原作格子不显示名字）
func _ensure_name_label(cell_node: Control, name_text: String, p_visible: bool = true) -> void:
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
	lbl.visible = p_visible
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
