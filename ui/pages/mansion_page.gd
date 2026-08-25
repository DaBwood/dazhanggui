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
	page.set_anchors_preset(Control.PRESET_FULL_RECT)  # 【新增】让 page 先铺满
	
	# 自动创建 GridContainer
	var grid: GridContainer
	if page.has_node("MansionGrid"):
		grid = page.get_node("MansionGrid")
	else:
		grid = GridContainer.new()
		grid.name = "MansionGrid"
		grid.columns = 5
		# 【删】grid.custom_minimum_size = Vector2(1100, 500)
		# 【新增】让 grid 铺满 page
		grid.set_anchors_preset(Control.PRESET_FULL_RECT)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		page.add_child(grid)
	
	# 清空
	for child in grid.get_children():
		child.queue_free()
	
	var modules = [
		{"name": "挚友", "func": "on_friend_page"},
		{"name": "商城", "func": "on_mall"},
		{"name": "每日任务", "func": "on_daily_task"},
		{"name": "VIP", "func": "on_vip"},
		{"name": "充值豪礼", "func": "on_recharge"},
		{"name": "珍兽", "func": "on_beast"},
		{"name": "徒弟", "func": "on_apprentice"},   # 【新增】
	]
	
	for m in modules:
		var cell = PanelContainer.new()
		# 【改】允许 cell 扩展填满
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(200, 140)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		# 【新增】让内部也跟随扩展
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.add_child(vbox)
		
		var name_lbl = Label.new()
		name_lbl.text = m.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_lbl)
		
		var btn = Button.new()
		btn.text = "进入"
		btn.custom_minimum_size = Vector2(80, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(Callable(c, m.func))
		vbox.add_child(btn)
		
		grid.add_child(cell)
	# 挚友目标：全部达成后入口不再显示
	if not data.all_friend_goals_done():
		modules.append({"name": "挚友目标", "func": "on_friend_goals"})

# 显示挚友目标弹窗：列出每个挚友的解锁目标与当前进度
func show_friend_goals_popup():
	var popup = c._create_base_popup("挚友目标", 560)
	var vbox = popup.get_node("panel") # 若你的基础弹窗容器节点名不同，改成实际容器节点名

	for goal in data._goal_configs:
		var fid = goal.get("friend_id", "")
		var need = int(goal.get("count", 0))
		var cur = data.get_friend_goal_stat(goal.get("stat", ""))
		var done = data.is_goal_done(fid)
		var fname = fid
		if data._friend_configs.has(fid):
			fname = data._friend_configs[fid].get("name", fid)

		var label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if done:
			label.text = "✅ %s：已达成（%d/%d）" % [fname, min(cur, need), need]
		else:
			label.text = "⬜ %s：%s（%d/%d）" % [fname, goal.get("desc", "目标"), min(cur, need), need]
		vbox.add_child(label)

	c._add_ok_button(popup, "关闭")

# 进府邸时重建列表（刷新挚友目标进度；原本无动态数据为 pass）
func update_mansion_list():
	generate_mansion_list()
