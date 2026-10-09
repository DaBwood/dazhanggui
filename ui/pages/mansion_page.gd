# ============================================================
# 府邸页（第3批重构：从 game_controller.gd 拆分而来）
# 场景化批次：横滑地图 8 牌 + 顶网格活动宫格（最近批次见档案）
# ============================================================
class_name MansionPage
extends RefCounted

const SCENE: PackedScene = preload("res://ui/pages/mansion_page.tscn")

# 文件名即素材名（assets/mansion/）；充值豪礼(红袋)给 VIP、限时充值(宝箱)给充值豪礼入口=用户指定口径（2026-10-09）
# 素材文件名一律英文（仓库惯例+导出工具链稳健），显示文字中文在 Label 层——文件名≠显示名
# 图标运行时 load（底栏范式§控制器 1547-1557）：exists 守卫+丢图回退文字，不走 const preload
const ICON_PATHS := {
	"shop": "res://assets/mansion/icon_shop.png",
	"vip": "res://assets/mansion/icon_vip.png",
	"recharge": "res://assets/mansion/icon_recharge.png",
	"lottery": "res://assets/mansion/icon_lottery.png",
	"rank": "res://assets/mansion/icon_rank.png",
	"scroll": "res://assets/mansion/icon_scroll.png",
	"goals": "res://assets/mansion/icon_goals.png",
}

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

func generate_mansion_list():
	if not c.has_node("PageContainer/MansionPage"): return
	var page = c.get_node("PageContainer/MansionPage")
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 场景实例重挂必须用 free()：queue_free 帧末才回收，同帧重建会让旧实例占着名字导致契约断链
	for child in page.get_children():
		child.free()
	var scene = SCENE.instantiate()
	page.add_child(scene)
	# find_child 取网格：置顶浮层与地图解耦，取不到时 push_error 点名而不是静默跳过
	var grid = scene.find_child("TopGrid", true, false)
	if grid == null:
		c.push_error("mansion_page: TopGrid 未找到，检查 mansion_page.tscn 结构")
		return
	_build_top_grid(grid)
	_wire_map_entries(scene)
# 顶网格：第一排 6 图标钮固定（用户定 2026-10-09），动态钮自然流到第二排
func _build_top_grid(box: VBoxContainer):
	# 第一排 6 图标钮固定（用户定 2026-10-09），第二排挚友目标（全达成即隐）；行=居中 HBox，组=VBox 居中
	var row1 = HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 8)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 行间隙不吃点击，只有钮本身可点
	box.add_child(row1)
	var modules = [
		{"name": "商城", "func": "on_mall", "icon": ICON_PATHS["shop"]},
		{"name": "VIP", "func": "on_vip", "icon": ICON_PATHS["vip"]},
		{"name": "充值豪礼", "func": "on_recharge", "icon": ICON_PATHS["recharge"]},
		{"name": "幸运夺宝", "view": "lottery", "icon": ICON_PATHS["lottery"]},
		{"name": "三日榜", "func": "", "icon": ICON_PATHS["rank"]},
		{"name": "招财密卷", "func": "", "icon": ICON_PATHS["scroll"]},
	]
	for m in modules:
		row1.add_child(_make_icon_button(m))
	# 邮件入口按用户要求先隐藏（2026-10-09）；未领数接口 data.mail_system.get_unclaimed_count() 保留
	if not data.all_friend_goals_done():
		var row2 = HBoxContainer.new()
		row2.alignment = BoxContainer.ALIGNMENT_CENTER
		row2.add_theme_constant_override("separation", 8)
		row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row2)
		row2.add_child(_make_icon_button({"name": "挚友目标", "func": "on_friend_goals", "icon": ICON_PATHS["goals"]}))
# 图标钮：64 立绘在上+14 横排白字黑描边在下，贴合内容（参考图二宫格）
func _make_icon_button(m: Dictionary) -> Button:
	var btn = Button.new()
	btn.text = m.name
	# 统一格宽 80：六钮等宽才有图二的均匀节奏；图标+文字块居中于格内
	btn.custom_minimum_size = Vector2(80, 98)
	btn.add_theme_font_size_override("font_size", 16)
	# 白字黑描边：参考图一活动宫格标签口径；outline 键名与 ui_helpers.gd:625 先例一致
	btn.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 0.85, 0.6))
	# 透明底四态：参考图一无按钮框，立绘+文字直接浮在地图上
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, empty)
	# 图标运行时加载（底栏范式）：缩 64px 装 Button.icon，0=VERTICAL_TOP 图标在上文字在下
	var icon_path: String = m.icon
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_tex := load(icon_path) as Texture2D
		if icon_tex and icon_tex.get_image():
			var icon_img := icon_tex.get_image()
			var icon_s: float = 64.0 / max(icon_img.get_width(), icon_img.get_height())
			icon_img.resize(int(icon_img.get_width() * icon_s), int(icon_img.get_height() * icon_s), Image.INTERPOLATE_LANCZOS)
			btn.icon = ImageTexture.create_from_image(icon_img)
			btn.vertical_icon_alignment = 0  # VerticalAlignment.VERTICAL_TOP=0 图标在上文字在下（4.7.1 全局常量不可见，用字面量）
	if m.has("view"):
		btn.pressed.connect(Callable(c, "show_view").bind(m.view))
	elif m.func == "":
		btn.pressed.connect(_show_reserved_popup)
	else:
		btn.pressed.connect(Callable(c, m.func))
	return btn
# 纯字钮：第二排动态入口（邮件/挚友目标）用，与图标钮同宽保持网格对齐
# 暗底金字钮样式：府邸网格统一口径（图标钮/字钮共用）
# 地图 8 牌：坐标在 tscn 静态摆位（位置=设计数据，用户可在编辑器直接拖），脚本只接线
func _wire_map_entries(scene: Control):
	var grid = scene.get_node("MansionVBox/MapScroll/MapContent/MansionEntryGrid")
	var wired = {
		"EntryZhenshou": "on_beast",
		"EntryCollection": "on_collection",
		"EntryXiangfang": "on_xiangfang",
		"EntryFriend": "on_friend_page",
		"EntryTudi": "on_apprentice",
	}
	for node_name in wired:
		grid.get_node(node_name).pressed.connect(Callable(c, wired[node_name]))
	# 有可激活套装时藏品牌亮红点（原 BottomGrid 红点口径平移到地图牌）
	if data.collection_system.has_activatable_suit():
		grid.get_node("EntryCollection").add_child(_make_red_dot(Vector2(30, -4)))
	# 预留牌（绣房/山庄/寻珍探宝）：功能未做，统一"后续版本开放"
	for node_name in ["EntryXiufang", "EntryShanzhuang", "EntryXunzhen"]:
		grid.get_node(node_name).pressed.connect(_show_reserved_popup)

func _make_red_dot(pos: Vector2) -> Label:
	var dot = Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	dot.position = pos
	return dot

# 口径：规范"未接入统一后续版本开放"；_show_success_popup kind=info（ok金/warn红/info浅）
func _show_reserved_popup():
	c._show_success_popup("后续版本开放", 0.0, "info")

# 显示挚友目标弹窗：列出每个挚友的解锁目标与当前进度
func show_friend_goals_popup():
	# 第二个参数是 Vector2 尺寸；不传位置则自动按视口居中
	var panel = c._create_base_popup("挚友目标", Vector2(520, 380))
	var vbox = panel.get_child(0)   # 基础弹窗的内容容器就是面板的第一个子节点

	# 目标列表走中枢转发器，字段名与 goals.json 一致：friend / stat / need / desc
	for goal in data.get_friend_goal_list():
		var fid = goal.get("friend", "")
		var need = int(goal.get("need", 1))
		var cur = data.get_friend_goal_stat(goal.get("stat", ""))
		var done = data.is_friend_goal_done(goal)
		var fname = data.get_goal_friend_name(fid)

		var label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if done:
			label.text = "✅ %s：已达成（%d/%d）" % [fname, min(cur, need), need]
		else:
			label.text = "⬜ %s：%s（%d/%d）" % [fname, goal.get("desc", "目标"), min(cur, need), need]
		vbox.add_child(label)

	# 关闭按钮：回调里释放整个弹窗
	c.add_child(panel)

# 进府邸时重建（刷新挚友目标显隐/邮件藏品红点；进页重建是原页面既有口径）
func update_mansion_list():
	generate_mansion_list()
