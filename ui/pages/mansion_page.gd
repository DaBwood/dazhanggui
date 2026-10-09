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
	box.find_child("BtnFirst", true, false).pressed.connect(show_first_recharge_popup)
	# 首充入口：已领取则隐藏（重进页面不复活）
	box.find_child("BtnFirst", true, false).visible = int(data.goal_stats.get("recharge_done", 0)) == 0
	# 挚友目标：全部达成后按钮本身不再显示（Grid 按格填充，无整行显隐）
	var goals = box.find_child("BtnGoals", true, false)
	goals.visible = not data.goal_system.all_goals_claimed()
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

	# 领取式挚友目标：已领取 ✅ / 可领取 🎁+领取钮 / 进行中 ⬜；李师师只能走首充弹窗领取（此处不给钮）
	for goal in data.get_friend_goal_list():
		var fid = goal.get("friend", "")
		var need = int(goal.get("need", 1))
		var cur = data.get_friend_goal_stat(goal.get("stat", ""))
		var fname = data.get_goal_friend_name(fid)
		var gs = data.goal_system

		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(row)
		var label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if gs.is_goal_claimed(goal):
			label.text = "✅ %s：已领取" % fname
		elif gs.is_goal_done(goal):
			label.text = "🎁 %s：%s（%d/%d）" % [fname, goal.get("desc", "目标"), min(cur, need), need]
		else:
			label.text = "⬜ %s：%s（%d/%d）" % [fname, goal.get("desc", "目标"), min(cur, need), need]
		row.add_child(label)
		if fid != "li_shishi" and gs.is_goal_claimable(goal):
			var btn = Button.new()
			btn.text = "领取"
			btn.pressed.connect(func():
				if gs.claim_goal(goal):
					panel.queue_free()
					data.save_game()
					c._show_success_popup("%s 已加入挚友" % fname, 0.0, "ok")
					_refresh_goals_entry())
			row.add_child(btn)

	# 关闭按钮：回调里释放整个弹窗
	c.add_child(panel)

# 首充弹窗：充值任意金额领挚友·李师师+门客·武镖师；未充→前往充值，已充未领→领取
# 口径（用户 2026-10-09 拍板②）：vip_exp>0 且未领取=待领取态，老玩家可补领，无迁移代码
func show_first_recharge_popup():
	var claimed = int(data.goal_stats.get("recharge_done", 0)) > 0
	var panel = c._create_base_popup("首充豪礼", Vector2(440, 300))
	var vbox = panel.get_child(0)
	var tip = Label.new()
	tip.text = "充值任意金额，即可领取挚友·李师师 与 门客·武镖师！"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tip)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	if claimed:
		var done = Label.new()
		done.text = "已领取"
		row.add_child(done)
	elif data.vip_exp > 0:
		var claim_btn = Button.new()
		claim_btn.text = "领取"
		claim_btn.pressed.connect(func():
			panel.queue_free()
			_claim_first_recharge())
		row.add_child(claim_btn)
	else:
		var go_btn = Button.new()
		go_btn.text = "前往充值"
		go_btn.pressed.connect(func():
			panel.queue_free()
			c.on_recharge())
		row.add_child(go_btn)
	c.add_child(panel)

# 首充领取：置领取标记→挚友目标系统发李师师（已拥有自动跳过）→门客系统发武镖师（幂等）→存档→入口当场消失
func _claim_first_recharge():
	data.goal_stats["recharge_done"] = 1
	for goal in data.get_friend_goal_list():
		if goal.get("friend", "") == "li_shishi":
			data.goal_system.claim_goal(goal)
	data.hero_system.unlock_hero("wu_biaoshi")
	data.save_game()
	var btn = c.get_node_or_null("PageContainer/MansionPage/MansionScene/TopGrid/Grid/BtnFirst")
	if btn:
		btn.visible = false
	c._show_success_popup("首充奖励已发放", 0.0, "ok")

# 领取后刷新挚友目标入口显隐（全部领完即消失）
func _refresh_goals_entry():
	var goals = c.get_node_or_null("PageContainer/MansionPage/MansionScene/TopGrid/Grid/BtnGoals")
	if goals:
		goals.visible = not data.goal_system.all_goals_claimed()

# 进府邸时重建（刷新挚友目标显隐/邮件藏品红点；进页重建是原页面既有口径）
func update_mansion_list():
	generate_mansion_list()
