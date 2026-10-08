# ============================================================
# 府邸页（第3批重构：从 game_controller.gd 拆分而来）
# 场景化批次：横滑地图 8 牌 + 上方网格 6 钮（最近批次见档案）
# ============================================================
class_name MansionPage
extends RefCounted

const SCENE: PackedScene = preload("res://ui/pages/mansion_page.tscn")

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
	_build_top_grid(scene.get_node("MansionVBox/TopGrid"))
	_wire_map_entries(scene)

# 上方网格 6 钮：用户圈图批次的分工是"上图入口走地图牌，其余留网格"
func _build_top_grid(grid: GridContainer):
	var modules = [
		{"name": "商城", "func": "on_mall"},
		{"name": "VIP", "func": "on_vip"},
		{"name": "充值豪礼", "func": "on_recharge"},
		{"name": "邮件", "func": "on_mail"},
		# controller.on_daily_task 本体是 print 占位，玩家无感知；按规范统一改走预留弹窗
		{"name": "每日任务", "func": ""},
	]
	# 挚友目标：全部达成后入口不再显示
	if not data.all_friend_goals_done():
		modules.append({"name": "挚友目标", "func": "on_friend_goals"})
	for m in modules:
		grid.add_child(_make_grid_button(m))

func _make_grid_button(m: Dictionary) -> Button:
	var btn = Button.new()
	btn.text = m.name
	btn.custom_minimum_size = Vector2(120, 40)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.14, 0.18)
	btn_style.border_color = Color(0.35, 0.32, 0.40)
	btn_style.border_width_bottom = 2
	btn_style.corner_radius_top_left = 3
	btn_style.corner_radius_top_right = 3
	btn_style.corner_radius_bottom_left = 3
	btn_style.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", btn_style)
	var hover_style = btn_style.duplicate()
	hover_style.bg_color = Color(0.22, 0.20, 0.28)
	hover_style.border_color = Color(0.50, 0.45, 0.60)
	btn.add_theme_stylebox_override("hover", hover_style)
	var press_style = btn_style.duplicate()
	press_style.bg_color = Color(0.10, 0.09, 0.13)
	btn.add_theme_stylebox_override("pressed", press_style)
	if m.func == "":
		btn.pressed.connect(_show_reserved_popup)
	else:
		btn.pressed.connect(Callable(c, m.func))
	# 有未领邮件时，邮件入口亮红点
	if m.func == "on_mail" and data.mail_system.get_unclaimed_count() > 0:
		btn.add_child(_make_red_dot())
	return btn

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
		grid.get_node("EntryCollection").add_child(_make_red_dot())
	# 预留牌（绣房/山庄/寻珍探宝）：功能未做，统一"后续版本开放"
	for node_name in ["EntryXiufang", "EntryShanzhuang", "EntryXunzhen"]:
		grid.get_node(node_name).pressed.connect(_show_reserved_popup)

func _make_red_dot() -> Label:
	var dot = Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	dot.position = Vector2(30, -4)
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
