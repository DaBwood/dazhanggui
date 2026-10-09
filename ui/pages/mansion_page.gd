# ============================================================
# 府邸页（第3批重构：从 game_controller.gd 拆分而来）
# 场景化批次：横滑地图 8 牌 + 顶网格活动宫格（最近批次见档案）
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
	# 顶网格：结构/图标/样式全在 tscn（场景化迁移口径），脚本只接线与显隐
	var top = scene.find_child("TopGrid", true, false)
	if top == null:
		c.push_error("mansion_page: TopGrid 未找到，检查 mansion_page.tscn 结构")
		return
	_wire_top_grid(top)
	_wire_map_entries(scene)

# 顶网格接线：按钮结构在 tscn 静态摆位，这里只连信号 + 挚友目标行显隐
func _wire_top_grid(box: Control):
	var wired = {
		"BtnShop": "on_mall",
		"BtnVip": "on_vip",
		"BtnRecharge": "on_recharge",
	}
	for node_name in wired:
		box.find_child(node_name, true, false).pressed.connect(Callable(c, wired[node_name]))
	box.find_child("BtnLottery", true, false).pressed.connect(Callable(c, "show_view").bind("lottery"))
	# 预留：三日榜/招财密卷，统一"后续版本开放"
	for node_name in ["BtnRank", "BtnScroll"]:
		box.find_child(node_name, true, false).pressed.connect(_show_reserved_popup)
	# 挚友目标：全部达成后按钮本身不再显示（Grid 按格填充，无整行显隐）
	var goals = box.find_child("BtnGoals", true, false)
	goals.visible = not data.all_friend_goals_done()
	goals.pressed.connect(Callable(c, "on_friend_goals"))

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
