# ============================================================
# 府邸页（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name MansionPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_mansion_list():
	if not c.has_node("PageContainer/MansionPage"): return
	var page = c.get_node("PageContainer/MansionPage")
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# 【改】清理旧的大卡片布局（如果存在）
	if page.has_node("MansionGrid"):
		page.get_node("MansionGrid").queue_free()
	
	# 主容器：上下两部分垂直排列
	var main_vbox: VBoxContainer
	if page.has_node("MainVBox"):
		main_vbox = page.get_node("MainVBox")
		for child in main_vbox.get_children():
			child.queue_free()
	else:
		main_vbox = VBoxContainer.new()
		main_vbox.name = "MainVBox"
		main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		main_vbox.add_theme_constant_override("separation", 16)
		page.add_child(main_vbox)
	
	# 上半部分：商城、VIP、充值豪礼、挚友目标
	var top_modules = [
		{"name": "商城", "func": "on_mall"},
		{"name": "VIP", "func": "on_vip"},
		{"name": "充值豪礼", "func": "on_recharge"},
	]
	# 挚友目标：全部达成后入口不再显示
	if not data.all_friend_goals_done():
		top_modules.append({"name": "挚友目标", "func": "on_friend_goals"})
	
	# 下半部分：挚友、珍兽、徒弟、每日任务
	var bottom_modules = [
		{"name": "挚友", "func": "on_friend_page"},
		{"name": "珍兽", "func": "on_beast"},
		{"name": "徒弟", "func": "on_apprentice"},
		{"name": "每日任务", "func": "on_daily_task"},
	]
	
	# 创建上半网格（4列，紧凑按钮）
	var top_grid = _create_button_grid(top_modules, 4)
	top_grid.name = "TopGrid"
	main_vbox.add_child(top_grid)
	
	# 创建下半网格（4列，紧凑按钮）
	var bottom_grid = _create_button_grid(bottom_modules, 4)
	bottom_grid.name = "BottomGrid"
	main_vbox.add_child(bottom_grid)


# 【新增】创建紧凑按钮网格的辅助函数
func _create_button_grid(modules: Array, columns: int) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = columns
	# 网格本身在父容器中水平居中，宽度随内容自适应
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	
	for m in modules:
		var btn = Button.new()
		btn.text = m.name
		# 普通按钮大小：宽120高40，在4列中会自然撑开
		btn.custom_minimum_size = Vector2(120, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 文字样式：14号，暖金色
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.8))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		# 按钮样式：深色底+淡边框
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.14, 0.18)
		btn_style.border_color = Color(0.35, 0.32, 0.40)
		btn_style.border_width_bottom = 2
		btn_style.corner_radius_top_left = 3
		btn_style.corner_radius_top_right = 3
		btn_style.corner_radius_bottom_left = 3
		btn_style.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", btn_style)
		# 悬停样式
		var hover_style = btn_style.duplicate()
		hover_style.bg_color = Color(0.22, 0.20, 0.28)
		hover_style.border_color = Color(0.50, 0.45, 0.60)
		btn.add_theme_stylebox_override("hover", hover_style)
		# 按下样式
		var press_style = btn_style.duplicate()
		press_style.bg_color = Color(0.10, 0.09, 0.13)
		btn.add_theme_stylebox_override("pressed", press_style)
		# 点击事件
		btn.pressed.connect(Callable(c, m.func))
		grid.add_child(btn)
	
	return grid


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
	c._add_ok_button(vbox, func(): panel.queue_free(), "关闭")
	c.add_child(panel)

# 进府邸时重建列表（刷新挚友目标进度；原本无动态数据为 pass）
func update_mansion_list():
	generate_mansion_list()
