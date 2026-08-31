# ============================================================
# 兽魂全屏页（2026-08-30 v2：弹窗改独立全屏页 + 魂石拖拽放置）
# 纯代码 UI 模块：var c（game_controller 根脚本）、var data（GameData 中枢）
# 层级：SoulPage 挂 c 根节点 z_index=35——盖过珍兽详情（全屏化后z20/全屏化前z30弹窗）；
#       本页的词条/确认/重塑弹窗 z_index=40，再压 SoulPage 一档；飘字 z50 不受影响
# 交互：仓库魂石卡 点按=词条弹窗 / 按住拖动=上盘（幻影与魂盘格子同大同距、指尖拖动；
#       不做落点预判，松手时按幻影在魂盘上的实际位置整体换算形状落点，放得下才落子，
#       放不下自动回仓库列表）；点占用格=取下回仓库；点锁定格=解锁
# ============================================================
class_name SoulView
extends RefCounted

# 魂盘格子（拖放目标）。Godot 内置拖放必须重写 _can_drop_data/_drop_data 虚函数，
# 虚函数只能挂在节点子类上，所以格子/魂石卡用内置类实现
class SoulCell extends PanelContainer:
	var view          # SoulView 引用（由创建处注入）
	var cell: int = -1
	# 拖放悬停校验：不按单个格子算，统一按幻影当前位置换算形状落点校验
	func _can_drop_data(_pos, drop_data):
		return view != null and view._board_can_drop(drop_data)
	# 落下：按幻影位置换算的形状落点放置
	func _drop_data(_pos, drop_data):
		if view != null: view._board_drop(drop_data)
	# 点按：锁定格=解锁 / 占用格=取下 / 空格=提示拖动
	func _gui_input(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if view != null: view._on_cell_tapped(cell)

# 仓库魂石卡（拖放源）：点按=词条弹窗；按住拖动=放置
class StoneCard extends PanelContainer:
	var view
	var uid: String = ""
	var _dragging: bool = false   # 区分点按与拖动：拖起来过就不再当点按
	# 拖动开始：通知界面生成跟随指尖的形状幻影
	func _get_drag_data(_pos):
		if view == null: return null
		_dragging = true
		view._on_stone_drag_start(uid)
		return {"uid": uid}
	# 松开：没拖过=点按→词条弹窗
	func _gui_input(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if not _dragging and view != null:
				view._show_stone_info(uid)
			_dragging = false
	# 拖动结束（无论成功与否）：清幻影；没放下的魂石本来就没动过，天然"弹回"仓库
	func _notification(what):
		if what == NOTIFICATION_DRAG_END:
			_dragging = false
			if view != null: view._on_stone_drag_end()


# 【新增】魂盘网格本体也当拖放目标：格子之间的缝隙不属于任何 SoulCell，
# 多格魂石"完全对正"松手时指尖正好落在缝里，没有网格兜底就会判定无处安放
class SoulBoardGrid extends GridContainer:
	var view
	# 缝隙悬停/落下：与格子同一套逻辑，统一按幻影位置换算形状落点
	func _can_drop_data(_pos, drop_data):
		return view != null and view._board_can_drop(drop_data)
	func _drop_data(_pos, drop_data):
		if view != null: view._board_drop(drop_data)


# 【新增】拖动跟随幻影：引擎拖放期间每帧把全局位置钉在指尖；拖放一结束就自毁
# （引擎自带 set_drag_preview 在部分环境不渲染，故改手动幻影；自毁是兜底，正常由 _on_stone_drag_end 清除）
class DragGhost extends Control:
	func _process(_delta):
		if get_viewport() != null and get_viewport().gui_is_dragging():
			global_position = get_global_mouse_position() - size / 2
		else:
			queue_free()

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

const CELL_PX = 96   # 魂盘单格边长
const GAP = 8        # 格子间距
const STONE_BTN = 88 # 【新增】仓库魂石方形按钮边长（最宽形状4格×20px=80，装得下）
const STONE_COLS = 6 # 【新增】仓库每行按钮数（6×88+5×8=568，居中在600宽里）

var _beast_id: String = ""      # 当前操作珍兽ID（页面打开期间）
var _beast_index: int = 0       # 当前操作珍兽实例序号
var _drag_uid: String = ""      # 正在拖动的魂石uid
var _board_grid = null          # 当前魂盘 GridContainer（落点换算用）
var _recast_picks: Array = []   # 重塑弹窗中已选的魂石uid（最多2块）

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 全屏页 ============
# 打开兽魂全屏页（由珍兽培养面板【兽魂】按钮触发）
func show_soul_view(beast_id: String, instance_index: int = 0):
	if data.get_beast_instance(beast_id, instance_index) == null: return
	_beast_id = beast_id
	_beast_index = instance_index
	_drag_uid = ""
	_recast_picks = []
	# 已存在则先关，保证内容重建
	_close_node("SoulPage")
	_close_node("SoulConfirmPopup")
	_close_node("SoulRecastPopup")
	_close_node("SoulInfoPopup")
	_close_node("SoulAuraPopup")   # 【新增】满盘光环详情弹窗也随页面关闭

	# 根面板：禁用锚点预设（项目坑#3），显式 position+size 铺满窗口
	var page = Panel.new()
	page.name = "SoulPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	page.add_theme_stylebox_override("panel", bg)

	# 内容根容器：同样显式尺寸（Panel 不做子节点布局）
	var vb = VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 10)
	page.add_child(vb)

	# 顶栏：返回 + 标题
	var top = HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 56)
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var back_btn = Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(120, 44)
	back_btn.pressed.connect(_on_back)
	top.add_child(back_btn)
	var cfg = data.get_beast_config(beast_id)
	var title = Label.new()
	title.text = "兽魂 · %s" % cfg.get("name", beast_id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	# 右侧占位，让标题视觉上居中
	var pad = Control.new()
	pad.custom_minimum_size = Vector2(120, 44)
	top.add_child(pad)

	# 动态内容区（信息行/装备行/魂盘/按钮/仓库）都在这，操作后原地重填
	var body = VBoxContainer.new()
	body.name = "SoulBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	vb.add_child(body)

	c.add_child(page)
	_fill_body(body)

# 返回：关掉本页（连带关掉它上面的弹窗），下层页面自然露出
func _on_back():
	_close_node("SoulConfirmPopup")
	_close_node("SoulRecastPopup")
	_close_node("SoulInfoPopup")
	_close_node("SoulPage")
	_close_node("SoulAuraPopup")   # 【新增】满盘光环详情弹窗也随页面关闭

# 重填动态内容区（保留仓库滚动位置）
func _fill_body(body):
	var scroll = body.get_node_or_null("StoneScroll")
	var sv = scroll.scroll_vertical if scroll else 0
	for child in body.get_children():
		child.queue_free()

	var ss = data.soul_system
	var lv = ss.get_board_level(_beast_id, _beast_index)
	var pct = float(ss._settings().get("inspire_pct", {}).get(str(lv), 0.03))
	var bonus = ss.get_board_bonus(_beast_id, _beast_index)
	var placed = ss._get_board(_beast_id, _beast_index).get("stones", {}).size()

	# 信息行：魂盘等级 / 单格收益 / 容量 / 五色石
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 15)
	info.text = "魂盘Lv.%d（单格+%d%%）  魂石 %d/%d  五色石×%d" % [lv, int(pct * 100), placed, ss.get_capacity(_beast_id, _beast_index), int(data.items.get("wuse_shi", 0))]
	body.add_child(info)

	# 装备门客行：职业着色 + 兽魂总加成
	var hero_lbl = Label.new()
	hero_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_lbl.add_theme_font_size_override("font_size", 15)
	var inst = data.get_beast_instance(_beast_id, _beast_index)
	var hero_id: String = inst.get("equipped_hero", "")
	var category_now = ""
	if hero_id != "" and data.heroes.has(hero_id):
		category_now = data.get_hero_config(hero_id).get("category", "")
		hero_lbl.text = "装备门客：%s【%s】  加成：赚速+%d%% 资质+%d（激发%d格）" % [
			data.heroes[hero_id].get("name", hero_id), category_now,
			int(bonus.percent * 100), int(bonus.apt), int(bonus.inspired)]
		hero_lbl.add_theme_color_override("font_color", _career_color(category_now))
	else:
		hero_lbl.text = "未装备门客（魂石加成不生效）"
		hero_lbl.add_theme_color_override("font_color", Color("#888888"))
	body.add_child(hero_lbl)

	# 5×5 魂盘（居中）
	var grid_wrap = HBoxContainer.new()
	grid_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(grid_wrap)
	var grid = SoulBoardGrid.new()   # 【改】网格本体也当拖放目标：格缝松手由网格接住换算落点
	grid.view = self
	grid.mouse_filter = Control.MOUSE_FILTER_STOP   # 【新增】明确截停命中测试，缝隙处的拖放由本类处理
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid_wrap.add_child(grid)
	_board_grid = grid   # 存引用：拖放落点按幻影相对本网格的位置换算
	var unlocked = ss.get_unlocked_cells(_beast_id, _beast_index)
	for cell in range(25):
		grid.add_child(_make_cell(cell, unlocked, category_now))

	# 拖拽提示
	var hint = Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#aaaaaa"))
	hint.text = "按住下方魂石拖到魂盘，松手时形状落在哪就放哪（放不下会自动弹回）；点盘中魂石=取下"
	body.add_child(hint)

	# 操作行：重置（二次确认） / 重塑
	var op = HBoxContainer.new()
	op.alignment = BoxContainer.ALIGNMENT_CENTER
	op.add_theme_constant_override("separation", 20)
	body.add_child(op)
	var reset_btn = Button.new()
	reset_btn.text = "重置魂盘"
	reset_btn.custom_minimum_size = Vector2(140, 40)
	var soul = ss._get_board(_beast_id, _beast_index)
	reset_btn.disabled = soul.get("stones", {}).is_empty() and int(soul.get("spent", 0)) <= 0
	reset_btn.pressed.connect(_on_reset_pressed)
	op.add_child(reset_btn)
	var recast_btn = Button.new()
	recast_btn.text = "魂石重塑"
	recast_btn.custom_minimum_size = Vector2(140, 40)
	recast_btn.pressed.connect(_show_recast_popup)
	op.add_child(recast_btn)

# 【新增】魂盘光环按钮：填满已解锁格=金色点亮，未填满=灰色；点击弹出加成详情
	var aura_btn = Button.new()
	aura_btn.text = "魂盘光环"
	aura_btn.custom_minimum_size = Vector2(140, 40)
	var aura_sb = StyleBoxFlat.new()
	aura_sb.set_corner_radius_all(6)
	if ss.is_board_full(_beast_id, _beast_index):
		aura_sb.bg_color = Color("#5a4a12")          # 亮：金底金边金字
		aura_sb.set_border_width_all(2)
		aura_sb.border_color = Color("#ffd700")
		aura_btn.add_theme_color_override("font_color", Color("#ffd700"))
	else:
		aura_sb.bg_color = Color("#262233")          # 灰：暗底灰字
		aura_btn.add_theme_color_override("font_color", Color("#777777"))
	aura_btn.add_theme_stylebox_override("normal", aura_sb)
	aura_btn.pressed.connect(_show_aura_popup)
	op.add_child(aura_btn)

	# 魂石仓库
	var inv_title = Label.new()
	inv_title.text = "—— 魂石仓库（点按看词条，拖动上盘）——"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_font_size_override("font_size", 15)
	inv_title.add_theme_color_override("font_color", Color("#ffd700"))
	body.add_child(inv_title)
	var scroll2 = ScrollContainer.new()
	scroll2.name = "StoneScroll"
	scroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll2)
	# 【改】仓库改方形按钮网格：HBox 撑满宽度只为把网格整体居中
	var center_row = HBoxContainer.new()
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll2.add_child(center_row)
	var list = GridContainer.new()
	list.columns = STONE_COLS
	list.add_theme_constant_override("h_separation", GAP)
	list.add_theme_constant_override("v_separation", GAP)
	center_row.add_child(list)
	_build_stone_list(list)

	# 恢复仓库滚动位置
	var new_scroll = body.get_node_or_null("StoneScroll")
	if new_scroll: new_scroll.set_deferred("scroll_vertical", sv)

# ============ 魂盘格子 ============
# 构建单格：锁定（灰，点按解锁）/ 空（暗，拖放目标）/ 占用（职业色+词条，点按取下；激发格金框）
func _make_cell(cell: int, unlocked: Array, category_now: String) -> SoulCell:
	var ss = data.soul_system
	var node = SoulCell.new()
	node.view = self
	node.cell = cell
	node.custom_minimum_size = Vector2(CELL_PX, CELL_PX)

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	var lbl = Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)   # Label 用锚点铺满父格子（格子的坑只对显式 position/size 冲突，这里无显式坐标）
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE     # 不挡格子的点击/拖放
	node.add_child(lbl)

	if not unlocked.has(cell):
		style.bg_color = Color("#16131f")
		lbl.text = "锁\n%d石" % ss.get_unlock_cost(_beast_id, _beast_index)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color("#777777"))
		node.add_theme_stylebox_override("panel", style)
		return node

	var uid = ss.get_cell_stone(_beast_id, _beast_index, cell)
	if uid == "":
		style.bg_color = Color("#242038")   # 空格
		node.add_theme_stylebox_override("panel", style)
		return node

	# 占用格：找出本格在魂石 cells 里的颜色/词条
	var st: Dictionary = data.soul_stones.get(uid, {})
	var anchor = int(ss._get_board(_beast_id, _beast_index).get("stones", {}).get(uid, 0))
	var cells_abs = ss._stone_cells(st, anchor)
	var idx = cells_abs.find(cell)
	var color_name = "?"
	var apt = 0
	if idx >= 0 and idx < st.get("cells", []).size():
		color_name = st.cells[idx].get("color", "?")
		apt = int(st.cells[idx].get("apt", 0))
	var inspired = (color_name == category_now and category_now != "")
	style.bg_color = _career_color(color_name)
	style.bg_color.a = 0.45 if inspired else 0.18   # 激发格深一点，未激发暗下去
	lbl.text = "%s\n+%d" % [color_name, apt]
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color("#ffffff") if inspired else Color("#999999"))
	if inspired:
		style.set_border_width_all(3)
		style.border_color = Color("#ffd700")
	node.add_theme_stylebox_override("panel", style)
	return node

# 点按格子：锁定→解锁；占用→取下；空→提示拖动
func _on_cell_tapped(cell: int):
	var ss = data.soul_system
	if not ss.get_unlocked_cells(_beast_id, _beast_index).has(cell):
		var res: Dictionary = ss.unlock_cell(_beast_id, _beast_index, cell)
		if not res.get("ok", false):
			c._show_stage_hint(res.get("reason", "无法解锁"))
		_refresh_body()
		return
	var uid = ss.get_cell_stone(_beast_id, _beast_index, cell)
	if uid == "":
		c._show_stage_hint("按住下方仓库的魂石，拖到这里放置")
		return
	ss.remove_stone(_beast_id, _beast_index, uid)
	_refresh_body()
	c.update_all_ui()   # 加成变化，顶栏赚速对账

# ============ 拖放 ============
# 拖起：生成指尖幻影（与魂盘格子同大同距）；不做落点预判，落点松手时才算
func _on_stone_drag_start(uid: String):
	_drag_uid = uid
	_spawn_drag_ghost(uid)

# 拖动结束：清幻影
func _on_stone_drag_end():
	_drag_uid = ""
	_clear_drag_ghost()

# 幻影当前位置换算出的形状落点格序号（幻影左上角=形状包围盒左上角，四舍五入对齐盘格；出界返回-1）
func _ghost_anchor() -> int:
	var ghost = _find_node("SoulDragGhost")
	if ghost == null or _board_grid == null: return -1
	var pitch = CELL_PX + GAP
	var rel = ghost.global_position - _board_grid.global_position
	var tx = int(round(rel.x / pitch))
	var ty = int(round(rel.y / pitch))
	return ty * 5 + tx   # 可能落在盘外（负的或超24）——can_place_stone 会判"超出盘外"

# 拖放悬停校验：按幻影当前位置整体换算形状落点，放得下才接受（按形状来，不按锚点）
func _board_can_drop(drop_data) -> bool:
	if not (drop_data is Dictionary) or not drop_data.has("uid"): return false
	var anchor = _ghost_anchor()
	if anchor < 0 or anchor >= 25: return false
	return data.soul_system.can_place_stone(_beast_id, _beast_index, drop_data.uid, anchor).get("ok", false)

# 落下放置：按幻影位置换算的落点放置（校验与悬停同一套，双保险）
func _board_drop(drop_data):
	var anchor = _ghost_anchor()
	if anchor < 0 or anchor >= 25: return
	var res: Dictionary = data.soul_system.place_stone(_beast_id, _beast_index, drop_data.uid, anchor)
	if not res.get("ok", false):
		return   # 放不下：静默弹回仓库（拖动本来就什么都没改）
	_refresh_body()
	c.update_all_ui()   # 加成变化，顶栏赚速对账

# 【改】拖动跟随图形：引擎 set_drag_preview 在部分环境不渲染，改手动幻影（DragGhost 每帧跟指尖，拖完自毁）
func _spawn_drag_ghost(uid: String):
	_clear_drag_ghost()   # 防御：上一次没清干净就先清
	var mini_panel = _make_shape_mini(uid, CELL_PX, CELL_PX + GAP, 0)   # 【改】与魂盘格子同大同距，拖到哪就是哪
	mini_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ghost = DragGhost.new()
	ghost.name = "SoulDragGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 60   # 拖动中压过一切（飘字z50），一目了然
	ghost.size = mini_panel.size
	ghost.add_child(mini_panel)
	c.add_child(ghost)
	# 出生即对齐指尖，免得第一帧闪在左上角
	ghost.global_position = c.get_global_mouse_position() - ghost.size / 2

# 【新增】清拖动幻影（DragGhost 自己也有自毁兜底，这里防重复 queue_free）
func _clear_drag_ghost():
	var p = _find_node("SoulDragGhost")
	if p and not p.is_queued_for_deletion():
		p.queue_free()

# ============ 魂石仓库 ============
# 【改】方形按钮网格：一格一块魂石只显示形状（边框颜色=品质），点按=词条弹窗，拖动=上盘
func _build_stone_list(grid: GridContainer):
	var ss = data.soul_system
	var any = false
	for uid in data.soul_stones.keys():
		if ss._is_placed(uid): continue   # 已上盘的不进仓库列表
		var st: Dictionary = data.soul_stones[uid]
		any = true
		var card = StoneCard.new()
		card.view = self
		card.uid = uid
		card.custom_minimum_size = Vector2(STONE_BTN, STONE_BTN)   # 【改】方形按钮，一行能放多个
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color("#242038")
		card_style.set_corner_radius_all(6)
		# 【新增】边框颜色=品质色：文字概要去掉后靠边框认品质；不想要可删这两行
		card_style.set_border_width_all(2)
		card_style.border_color = _quality_color(st.get("quality", "优秀"))
		card.add_theme_stylebox_override("panel", card_style)

		# 形状小图居中（CenterContainer 设 IGNORE，不挡卡片本体的点击/拖动）
		var center = CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(center)
		var shape_view = _make_shape_mini(uid, 20)   # 最宽形状4格×20=80，装在88按钮里
		shape_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(shape_view)

		grid.add_child(card)
	if not any:
		var empty = Label.new()
		empty.text = "仓库空空如也\n（背包使用【魂石宝箱】/【无双魂石箱】获得魂石）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("#888888"))
		grid.add_child(empty)


# 画魂石形状小图：按形状包围盒显式摆色块。px=单格边长；step=格距（0=紧排，仓库小图用）；
# 幻影传 px=CELL_PX、step=CELL_PX+GAP，与魂盘格子同大同距——幻影左上角即形状包围盒左上角，落点按它换算
func _make_shape_mini(uid: String, px: int, step: int = 0, inset: int = 1) -> Panel:
	if step <= 0: step = px
	var st: Dictionary = data.soul_stones.get(uid, {})
	var shape: Array = st.get("shape", [[0, 0]])
	var cells: Array = st.get("cells", [])
	# 求包围盒
	var minx = 999
	var miny = 999
	var maxx = -999
	var maxy = -999
	for off in shape:
		minx = mini(minx, int(off[0]))
		maxx = maxi(maxx, int(off[0]))
		miny = mini(miny, int(off[1]))
		maxy = maxi(maxy, int(off[1]))
	var w = (maxx - minx) * step + px
	var h = (maxy - miny) * step + px
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.size = Vector2(w, h)
	var back = StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0)   # 透明底，只画色块
	panel.add_theme_stylebox_override("panel", back)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 【修】纯装饰：默认STOP会截获拖放命中，挡住落点判定
	for i in range(shape.size()):
		var off = shape[i]
		var blk = Panel.new()
		blk.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 【修】色块默认STOP会截获拖放命中——单格魂石幻影就是一整块色块，不忽略就永远放不上
		blk.position = Vector2((int(off[0]) - minx) * step + inset, (int(off[1]) - miny) * step + inset)
		blk.size = Vector2(px - inset * 2, px - inset * 2)
		var sb = StyleBoxFlat.new()
		var color_name = "?"
		if i < cells.size(): color_name = cells[i].get("color", "?")
		sb.bg_color = _career_color(color_name)
		sb.set_corner_radius_all(3)
		blk.add_theme_stylebox_override("panel", sb)
		panel.add_child(blk)
	return panel

# 点按魂石卡：词条详情弹窗（z40，压全屏页一档）
func _show_stone_info(uid: String):
	_close_node("SoulInfoPopup")
	var st: Dictionary = data.soul_stones.get(uid, {})
	if st.is_empty(): return
	var popup = c._create_base_popup("魂石详情", Vector2(400, 360))
	popup.name = "SoulInfoPopup"
	popup.z_index = 40   # 压过 SoulPage(35)
	var vb = popup.get_child(0)
	var q_lbl = Label.new()
	q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_lbl.add_theme_font_size_override("font_size", 18)
	q_lbl.add_theme_color_override("font_color", _quality_color(st.get("quality", "优秀")))
	q_lbl.text = "【%s】魂石 · %d格" % [st.get("quality", ""), st.get("cells", []).size()]
	vb.add_child(q_lbl)
	# 逐格词条
	for cell in st.get("cells", []):
		var l = Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text = "%s 格：资质 +%d" % [cell.get("color", "?"), int(cell.get("apt", 0))]
		l.add_theme_color_override("font_color", _career_color(cell.get("color", "")))
		vb.add_child(l)
	var tip = Label.new()
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color("#aaaaaa"))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.text = "颜色与装备门客职业一致的格才激发加成\n按住卡片拖到魂盘，形状落在哪就放哪"
	vb.add_child(tip)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# ============ 重置（二次确认） ============
# 点重置：弹确认框（说明退格子退五色石）
func _on_reset_pressed():
	_close_node("SoulConfirmPopup")
	var spent = int(data.soul_system._get_board(_beast_id, _beast_index).get("spent", 0))
	var popup = c._create_base_popup("重置魂盘", Vector2(420, 240))
	popup.name = "SoulConfirmPopup"
	popup.z_index = 40   # 压过 SoulPage(35)
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "将取下全部魂石回仓库、额外格子上锁\n退还五色石×%d\n（初始3×3保持解锁）" % spent
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	var ok = Button.new()
	ok.text = "确定重置"
	ok.custom_minimum_size = Vector2(120, 40)
	ok.pressed.connect(_on_reset_confirmed)
	row.add_child(ok)
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(func(): _close_node("SoulConfirmPopup"))
	row.add_child(cancel)
	c.add_child(popup)

# 确认重置：执行并刷新
func _on_reset_confirmed():
	var res: Dictionary = data.soul_system.reset_board(_beast_id, _beast_index)
	_close_node("SoulConfirmPopup")
	_refresh_body()
	c.update_all_ui()
	if int(res.get("refund", 0)) > 0:
		c._show_stage_hint("已重置，退还五色石×%d" % int(res.refund))

# ============ 重塑弹窗 ============
# 打开重塑弹窗：列仓库中可重塑魂石（未上盘、非无双），点选2块同品质后执行
func _show_recast_popup():
	_close_node("SoulRecastPopup")
	_recast_picks = []
	var popup = c._create_base_popup("魂石重塑", Vector2(520, 620))
	popup.name = "SoulRecastPopup"
	popup.z_index = 40   # 压过 SoulPage(35)
	c.add_child(popup)
	_fill_recast_popup(popup)

# 重填重塑弹窗内容
func _fill_recast_popup(popup):
	var vb = popup.get_child(0)
	var first = true
	for child in vb.get_children():
		if first:
			first = false
			continue
		child.queue_free()

	# 规则说明
	var rule = Label.new()
	rule.text = "同品质2块合一：优秀40%→卓越 / 卓越20%→传奇 / 传奇10%→无双\n失败则同品质全重随（形状/颜色/词条）；无双不可重塑"
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule.add_theme_font_size_override("font_size", 13)
	rule.add_theme_color_override("font_color", Color("#aaaaaa"))
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(rule)

	# 可重塑魂石列表
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var ss = data.soul_system
	var any = false
	for uid in data.soul_stones.keys():
		var st: Dictionary = data.soul_stones[uid]
		if st.get("quality", "") == "无双": continue   # 无双不可重塑
		if ss._is_placed(uid): continue               # 盘中魂石需先取下
		any = true
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var parts = []
		for cell in st.get("cells", []):
			parts.append("%s+%d" % [cell.get("color", "?"), int(cell.get("apt", 0))])
		btn.text = "【%s】%d格  %s" % [st.get("quality", ""), st.get("cells", []).size(), "  ".join(parts)]
		btn.add_theme_color_override("font_color", _quality_color(st.get("quality", "优秀")))
		if _recast_picks.has(uid):
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color("#3a3454")
			sb.set_border_width_all(2)
			sb.border_color = Color("#ffd700")
			sb.set_corner_radius_all(6)
			btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(_on_recast_pick.bind(uid))
		list.add_child(btn)
	if not any:
		var empty = Label.new()
		empty.text = "没有可重塑的魂石\n（无双不可重塑；盘中魂石需先取下）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("#888888"))
		list.add_child(empty)

	# 执行按钮：选满2块且同品质才可点
	var do_btn = Button.new()
	do_btn.custom_minimum_size = Vector2(200, 44)
	var ready = _recast_picks.size() == 2 and data.soul_stones.get(_recast_picks[0], {}).get("quality", "") == data.soul_stones.get(_recast_picks[1], {}).get("quality", "-")
	if ready:
		var q = data.soul_stones[_recast_picks[0]].get("quality", "")
		var chance = float(ss._settings().get("recast_up", {}).get(q, 0.0))
		do_btn.text = "重塑（%d%%升品）" % int(chance * 100)
	else:
		do_btn.text = "选择2块同品质魂石"
		do_btn.disabled = true
	do_btn.pressed.connect(_on_recast_do)
	vb.add_child(do_btn)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")

# 点选重塑材料：最多2块；选不同品质时清空重选（避免跨品质卡死）
func _on_recast_pick(uid: String):
	if _recast_picks.has(uid):
		_recast_picks.erase(uid)
	else:
		if _recast_picks.size() >= 2:
			_recast_picks = []
		if _recast_picks.size() == 1:
			var q0 = data.soul_stones.get(_recast_picks[0], {}).get("quality", "")
			if data.soul_stones.get(uid, {}).get("quality", "") != q0:
				_recast_picks = []   # 品质不同：清空，以新点选的重新开始
		_recast_picks.append(uid)
	var popup = _find_node("SoulRecastPopup")
	if popup: _fill_recast_popup(popup)

# 执行重塑：关闭弹窗，提示升品/重随结果，刷新主页面
func _on_recast_do():
	if _recast_picks.size() != 2: return
	var res: Dictionary = data.soul_system.recast(_recast_picks[0], _recast_picks[1])
	_recast_picks = []
	_close_node("SoulRecastPopup")
	_refresh_body()
	if not res.get("ok", false):
		c._show_stage_hint(res.get("reason", "无法重塑"))
		return
	var st: Dictionary = res.get("stone", {})
	if res.get("upgraded", false):
		c._show_stage_hint("升品成功！获得【%s】魂石" % st.get("quality", ""))
	else:
		c._show_stage_hint("未升品，【%s】魂石已重新随机" % st.get("quality", ""))

# ============ 魂盘光环详情 ============
# 【新增】满盘加成详情弹窗：当前状态（激活/未激活）+ 填满进度 + 规则说明 + 各等级加成表
func _show_aura_popup():
	_close_node("SoulAuraPopup")
	var ss = data.soul_system
	var lv = ss.get_board_level(_beast_id, _beast_index)
	var full = ss.is_board_full(_beast_id, _beast_index)
	var prog = ss.get_fill_progress(_beast_id, _beast_index)
	# 各等级满盘加成（读配置 full_pct，带兜底默认值）
	var full_pct: Dictionary = ss._settings().get("full_pct", {"1": 0.05, "2": 0.1, "3": 0.15, "4": 0.2, "5": 0.3})
	var popup = c._create_base_popup("魂盘光环", Vector2(420, 420))
	popup.name = "SoulAuraPopup"
	popup.z_index = 40   # 压过 SoulPage(35)
	var vb = popup.get_child(0)

	# 当前状态行：激活显示当前加成，未激活显示触发条件
	var state = Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 17)
	if full:
		state.text = "已激活：赚速 +%d%%" % int(float(full_pct.get(str(lv), 0.0)) * 100)
		state.add_theme_color_override("font_color", Color("#ffd700"))
	else:
		state.text = "未激活（填满所有已解锁格后生效）"
		state.add_theme_color_override("font_color", Color("#888888"))
	vb.add_child(state)

	# 填满进度行
	var prog_lbl = Label.new()
	prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog_lbl.text = "当前进度：%d/%d 格（魂盘Lv.%d）" % [int(prog.covered), int(prog.total), lv]
	vb.add_child(prog_lbl)

	# 规则说明
	var rule = Label.new()
	rule.text = "用魂石把当前所有已解锁格填满（不要求颜色激发）\n装备门客额外获得赚速百分比加成"
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule.add_theme_font_size_override("font_size", 13)
	rule.add_theme_color_override("font_color", Color("#aaaaaa"))
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(rule)

	# 各等级加成表（当前等级标金 + "◀ 当前"）
	var table_title = Label.new()
	table_title.text = "—— 各等级满盘加成 ——"
	table_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table_title.add_theme_font_size_override("font_size", 14)
	table_title.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(table_title)
	for i in range(1, 6):
		var row_lbl = Label.new()
		row_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cur = "  ◀ 当前" if i == lv else ""
		row_lbl.text = "魂盘Lv.%d：赚速 +%d%%%s" % [i, int(float(full_pct.get(str(i), 0.0)) * 100), cur]
		if i == lv:
			row_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		vb.add_child(row_lbl)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)


# ============ 内部工具 ============
# 原地重填动态内容区
func _refresh_body():
	var page = _find_node("SoulPage")
	if page == null: return
	# 【修】SoulBody 是内层 VBox 的子节点、不是 SoulPage 直属——改递归查找（原 get_node 直取路径报错）
	var body = page.find_child("SoulBody", true, false)
	if body:
		_fill_body(body)

# 在 game_controller 根节点下按名字找节点
func _find_node(node_name: String):
	if c.has_node(node_name):
		return c.get_node(node_name)
	return null

# 按名字关闭节点
func _close_node(node_name: String):
	var p = _find_node(node_name)
	if p: p.queue_free()

# 职业颜色（读 soulstones.json 的 colors 段，兜底灰）
func _career_color(career: String) -> Color:
	var colors: Dictionary = data._soul_configs.get("colors", {})
	return Color(colors.get(career, "#888888"))

# 魂石品质颜色（无双金/传奇橙/卓越紫/优秀蓝）
func _quality_color(q: String) -> Color:
	return Color({"无双": "#ffd700", "传奇": "#ffa500", "卓越": "#bf80ff", "优秀": "#4da6ff"}.get(q, "#ffffff"))
