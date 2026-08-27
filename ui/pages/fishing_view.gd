# ============================================================
# 垂钓页视图（第8批新增：闯荡页【垂钓】子视图）
# 纯代码 UI 模块：var c（game_controller 根脚本）、var data（GameData 中枢）
# 结构：入口按钮挂 AdventureEntryGrid；FishingView 子视图挂 AdventurePage 下
# 红点：任务/图鉴按钮右上角红点（显式 size/position，不用当帧 size 做定位依据）
# 弹窗刷新：任务/图鉴弹窗领取后原地重填列表并保留滚动位置；奖励弹窗后添加，保证在最上层
# ============================================================
class_name FishingView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 构建（由 adventure_page.generate_adventure_page 挂接） ============
func build_fishing_view(page, vbox):
	# --- 垂钓入口按钮 ---
	var fish_btn = Button.new()
	fish_btn.text = "垂钓"
	fish_btn.custom_minimum_size = Vector2(240, 60)
	fish_btn.pressed.connect(c.show_fishing_view)
	vbox.get_node("AdventureEntryGrid").add_child(fish_btn)

	# --- 垂钓子页面 ---
	var view = VBoxContainer.new()
	view.name = "FishingView"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.add_theme_constant_override("separation", 12)
	page.add_child(view)

	var back_btn = Button.new()
	back_btn.text = "< 返回闯荡"
	back_btn.pressed.connect(c.hide_fishing_view)
	view.add_child(back_btn)

	var title = Label.new()
	title.text = "垂钓"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	view.add_child(title)

	# 时段/天气/地龙信息栏
	var info = Label.new()
	info.name = "FishingInfo"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(info)

	# 操作行1：钓鱼 / 撒网捕鱼
	var op_box = HBoxContainer.new()
	op_box.alignment = BoxContainer.ALIGNMENT_CENTER
	op_box.add_theme_constant_override("separation", 16)
	view.add_child(op_box)

	var do_btn = Button.new()
	do_btn.name = "FishingDoBtn"
	do_btn.text = "钓鱼\n-1地龙"
	do_btn.custom_minimum_size = Vector2(160, 70)
	do_btn.pressed.connect(_on_fishing)
	op_box.add_child(do_btn)

	var net_btn = Button.new()
	net_btn.name = "FishingNetBtn"
	net_btn.text = "撒网捕鱼\n-10地龙"
	net_btn.custom_minimum_size = Vector2(160, 70)
	net_btn.pressed.connect(_on_fishing_multi)
	op_box.add_child(net_btn)

	# 操作行2：任务 / 图鉴 / 钓点(瀑湖) / 礼包
	var op_box2 = HBoxContainer.new()
	op_box2.alignment = BoxContainer.ALIGNMENT_CENTER
	op_box2.add_theme_constant_override("separation", 12)
	view.add_child(op_box2)

	# 任务按钮+红点（包一层 Control 以便红点绝对定位在按钮右上角）
	var task_wrap = Control.new()
	task_wrap.custom_minimum_size = Vector2(110, 60)
	op_box2.add_child(task_wrap)
	var task_btn = Button.new()
	task_btn.text = "任务"
	task_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	task_btn.pressed.connect(_on_task_btn)
	task_wrap.add_child(task_btn)
	var task_dot = _make_red_dot()
	task_dot.name = "TaskDot"
	task_wrap.add_child(task_dot)

	# 图鉴按钮+红点
	var dex_wrap = Control.new()
	dex_wrap.custom_minimum_size = Vector2(110, 60)
	op_box2.add_child(dex_wrap)
	var dex_btn = Button.new()
	dex_btn.text = "图鉴"
	dex_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	dex_btn.pressed.connect(_on_dex_btn)
	dex_wrap.add_child(dex_btn)
	var dex_dot = _make_red_dot()
	dex_dot.name = "DexDot"
	dex_wrap.add_child(dex_dot)

	# 钓点按钮（按钮文本=当前钓点名，点击弹窗显示当前可钓渔获）
	var loc_btn = Button.new()
	loc_btn.name = "FishingLocBtn"
	loc_btn.text = data.fishing_system.get_location_name()
	loc_btn.custom_minimum_size = Vector2(110, 60)
	loc_btn.pressed.connect(_on_location_btn)
	op_box2.add_child(loc_btn)

	# 元宝礼包按钮
	var pack_btn = Button.new()
	pack_btn.text = "礼包"
	pack_btn.custom_minimum_size = Vector2(110, 60)
	pack_btn.pressed.connect(_on_pack_btn)
	op_box2.add_child(pack_btn)

	# 本次钓鱼结果
	var result = Label.new()
	result.name = "FishingResult"
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", Color("#ffd700"))
	view.add_child(result)

# 生成一个红点控件（显式尺寸定位在父控件右上角，父控件尺寸已知为110×60）
func _make_red_dot() -> ColorRect:
	var dot = ColorRect.new()
	dot.color = Color("#ff3333")
	dot.size = Vector2(12, 12)
	dot.position = Vector2(94, 2)
	dot.visible = false
	return dot

# ============ 显示/隐藏 ============
# 打开垂钓：隐藏闯荡主入口区和其他子视图，只留垂钓视图
func show_fishing_view():
	if not c.has_node("PageContainer/AdventurePage/FishingView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	for child in page.get_children():
		child.visible = (child.name == "FishingView")
	update_fishing_view()

# 返回闯荡主页
func hide_fishing_view():
	if not c.has_node("PageContainer/AdventurePage/FishingView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("FishingView").visible = false
	page.get_node("AdventureVBox").visible = true

# ============ 刷新 ============
# 重绘信息栏与红点
func update_fishing_view():
	if not c.has_node("PageContainer/AdventurePage/FishingView"): return
	var view = c.get_node("PageContainer/AdventurePage/FishingView")
	_refresh_info()
	view.get_node("FishingResult").text = ""
	_refresh_dots()

# 刷新信息栏（时段·天气·地龙·赤龙）
func _refresh_info():
	if not c.has_node("PageContainer/AdventurePage/FishingView"): return
	var view = c.get_node("PageContainer/AdventurePage/FishingView")
	var fs = data.fishing_system
	var remain_h = int(fs.get_weather_remain() / 3600)
	view.get_node("FishingInfo").text = "%s · %s（约%d小时后变天） ｜ 地龙：%d ｜ 赤龙：%d" % [fs.get_period(), fs.get_weather(), remain_h, fs.get_dilong(), int(data.fishing_chilong)]

# 任务/图鉴红点显隐
func _refresh_dots():
	if not c.has_node("PageContainer/AdventurePage/FishingView"): return
	var view = c.get_node("PageContainer/AdventurePage/FishingView")
	var fs = data.fishing_system
	var task_dot = view.find_child("TaskDot", true, false)
	if task_dot: task_dot.visible = fs.has_ready_task()
	var dex_dot = view.find_child("DexDot", true, false)
	if dex_dot: dex_dot.visible = fs.has_claimable_dex()

# ============ 钓鱼 ============
# 点击钓鱼：调系统抛竿，结果显示在结果栏；触发任务/新图鉴时额外提示
func _on_fishing():
	var fs = data.fishing_system
	var res: Dictionary = fs.do_fishing()
	var view = c.get_node("PageContainer/AdventurePage/FishingView")
	var result_lbl = view.get_node("FishingResult")
	if not res.get("ok", false):
		result_lbl.text = res.get("reason", "钓鱼失败")
		c.flash_red("PageContainer/AdventurePage/FishingView")
		return
	if res.get("type") == "task":
		# 触发任务：弹窗提示接到了什么任务
		var task: Dictionary = res.task
		result_lbl.text = "触发了新任务！"
		var popup = c._create_base_popup("触发任务", Vector2(420, 200))
		var vb = popup.get_child(0)
		var lbl = Label.new()
		lbl.text = "【%s】\n奖励：%s" % [task.get("desc", ""), _rewards_text(task.get("rewards", {}))]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(lbl)
		c._add_ok_button(vb, func(): popup.queue_free())
		c.add_child(popup)
	else:
		# 钓到渔获/道具
		result_lbl.text = "钓到了【%s】%s！" % [res.get("quality", ""), res.get("name", "")]
		result_lbl.add_theme_color_override("font_color", _quality_color(res.get("quality", "无")))
		if res.get("dex_new", false):
			result_lbl.text += "\n新图鉴解锁，可领取图鉴奖励！"
	_refresh_info()
	_refresh_dots()

# 撒网捕鱼：依次钓10次，汇总弹窗展示渔获计数与触发的任务
func _on_fishing_multi():
	var fs = data.fishing_system
	var res: Dictionary = fs.do_fishing_multi(10)
	var view = c.get_node("PageContainer/AdventurePage/FishingView")
	var result_lbl = view.get_node("FishingResult")
	if not res.get("ok", false):
		result_lbl.text = res.get("reason", "钓鱼失败")
		c.flash_red("PageContainer/AdventurePage/FishingView")
		return
	result_lbl.text = "撒网捕鱼 %d 次！" % int(res.count)
	# 汇总弹窗
	var popup = c._create_base_popup("撒网收获", Vector2(460, 520))
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	# 渔获按品级顺序展示
	var fishes: Dictionary = res.fishes
	for q in FishingSystem.QUALITY_ORDER:
		for fid in fishes.keys():
			var f: Dictionary = fishes[fid]
			if f.quality != q: continue
			var lbl = Label.new()
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.text = "【%s】%s ×%d" % [f.quality, f.name, int(f.count)]
			lbl.add_theme_color_override("font_color", _quality_color(q))
			list.add_child(lbl)
	# 触发的任务
	for desc in res.tasks:
		var lbl2 = Label.new()
		lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl2.text = "触发任务：%s" % desc
		lbl2.add_theme_color_override("font_color", Color("#7CFC00"))
		list.add_child(lbl2)
	# 中途停止原因（如地龙不足）
	if res.get("reason", "") != "" and int(res.count) < 10:
		var lbl3 = Label.new()
		lbl3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl3.text = "（%s，提前停止）" % res.reason
		lbl3.add_theme_color_override("font_color", Color("#aaaaaa"))
		list.add_child(lbl3)
	c._add_ok_button(vb, func(): popup.queue_free())
	c.add_child(popup)
	_refresh_info()
	_refresh_dots()

# 品质颜色（无双红/传奇橙/普通蓝/无白）
func _quality_color(q: String) -> Color:
	return Color({"无双": "#ff4d4d", "传奇": "#ffa500", "普通": "#4da6ff", "无": "#ffffff"}.get(q, "#ffffff"))

# ============ 钓点（瀑湖）弹窗 ============
# 点击钓点按钮：弹窗显示当前时段天气下可获取的渔获（仅 kind=fish，不含道具），按品级分组
func _on_location_btn():
	var fs = data.fishing_system
	var loc_name = fs.get_location_name()
	var popup = c._create_base_popup("%s · 当前鱼池" % loc_name, Vector2(520, 520))
	var vb = popup.get_child(0)

	var hint = Label.new()
	hint.text = "%s · %s 可钓到的渔获" % [fs.get_period(), fs.get_weather()]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#aaaaaa"))
	vb.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	# 当前鱼池按品级分组（只列渔获，不列道具）
	var pool = fs.get_current_pool()
	for q in FishingSystem.QUALITY_ORDER:
		var head = Label.new()
		head.text = "—— %s ——" % q
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_color_override("font_color", _quality_color(q))
		list.add_child(head)
		var names = []
		for f in pool:
			if f.get("quality", "无") == q and f.get("kind", "fish") == "fish":
				names.append(f.get("name", f.id))
		var body = Label.new()
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.text = "、".join(names) if not names.is_empty() else "（无）"
		list.add_child(body)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# ============ 元宝礼包 ============
# 打开礼包弹窗：1988元宝购买 地龙×50+赤龙×50
func _on_pack_btn():
	var popup = c._create_base_popup("垂钓礼包", Vector2(420, 260))
	var vb = popup.get_child(0)

	var lbl = Label.new()
	lbl.name = "PackInfo"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = "1988元宝 → 地龙×50 + 赤龙×50\n（赤龙为下一钓点消耗道具）\n当前元宝：%d" % int(data.yuanbao)
	vb.add_child(lbl)

	var buy_btn = Button.new()
	buy_btn.text = "购买"
	buy_btn.custom_minimum_size = Vector2(120, 44)
	buy_btn.pressed.connect(_on_buy_pack.bind(popup))
	vb.add_child(buy_btn)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 购买礼包：成功则更新弹窗内元宝显示和主界面信息栏
func _on_buy_pack(popup):
	var res: Dictionary = data.fishing_system.buy_bait_pack()
	var vb = popup.get_child(0)
	var lbl = vb.get_node("PackInfo")
	if res.get("ok", false):
		lbl.text = "购买成功！地龙+%d 赤龙+%d\n当前元宝：%d" % [int(res.dilong), int(res.chilong), int(data.yuanbao)]
	else:
		lbl.text = res.get("reason", "购买失败") + "\n当前元宝：%d" % int(data.yuanbao)
	_refresh_info()

# ============ 任务弹窗 ============
# 打开任务列表弹窗：已接任务逐行显示 描述/进度/交付(领取)按钮
func _on_task_btn():
	var popup = c._create_base_popup("垂钓任务", Vector2(520, 520))
	popup.name = "FishingTaskPopup"
	var vb = popup.get_child(0)

	var hint = Label.new()
	hint.text = "任务最多同时持有3个，钓鱼时有几率触发新任务\n（接到交付任务后，对应道具才会出现在鱼池中）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#aaaaaa"))
	vb.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.name = "TaskScroll"
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "TaskList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	_fill_task_list(list)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 重填任务列表（领取后原地刷新用，不清弹窗）
func _fill_task_list(list: VBoxContainer):
	var fs = data.fishing_system
	for child in list.get_children():
		child.queue_free()
	var tasks = fs.get_tasks()
	if tasks.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "暂无任务，去钓鱼触发吧"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty_lbl)
		return
	for t in tasks:
		list.add_child(_build_task_row(t))

# 构建单个任务行：描述+进度+操作按钮
func _build_task_row(t: Dictionary) -> HBoxContainer:
	var fs = data.fishing_system
	var cfg = fs._get_task_cfg(t.get("id", ""))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 进度文本：交付类显示仓库库存，计数类显示进度
	var progress_text = ""
	if cfg.get("type", "") == "deliver":
		var have = int(data.fishing_storage.get(cfg.get("target", ""), 0))
		progress_text = "（%d/%d）" % [min(have, int(cfg.get("need", 1))), int(cfg.get("need", 1))]
	else:
		progress_text = "（%d/%d）" % [min(int(t.get("progress", 0)), int(cfg.get("need", 1))), int(cfg.get("need", 1))]
	lbl.text = cfg.get("desc", "") + progress_text + "\n奖励：" + _rewards_text(cfg.get("rewards", {}))
	row.add_child(lbl)

	var btn = Button.new()
	btn.text = "交付" if cfg.get("type", "") == "deliver" else "领取"
	btn.custom_minimum_size = Vector2(80, 44)
	btn.disabled = not fs.is_task_ready(t)
	btn.pressed.connect(_on_claim_task.bind(t.get("id", "")))
	row.add_child(btn)
	return row

# 交付/领取任务：原地重填任务列表（保留滚动位置），奖励弹窗后添加保证在最上层
func _on_claim_task(task_id: String):
	var res: Dictionary = data.fishing_system.claim_task(task_id)
	if not res.get("ok", false):
		return
	# 原地刷新任务列表
	var popup = _find_popup("FishingTaskPopup")
	if popup:
		var list = popup.find_child("TaskList", true, false)
		var scroll = popup.find_child("TaskScroll", true, false)
		var sv = scroll.scroll_vertical if scroll else 0
		if list: _fill_task_list(list)
		if scroll: scroll.set_deferred("scroll_vertical", sv)   # 保留滚动位置
	_refresh_dots()
	_show_gains_popup("任务奖励", res.get("gains", {}))

# ============ 图鉴弹窗 ============
# 打开图鉴弹窗：按品级分组列出全部条目，可领取的排在该品级最前，未解锁显示???
func _on_dex_btn():
	var popup = c._create_base_popup("垂钓图鉴", Vector2(560, 560))
	popup.name = "FishingDexPopup"
	var vb = popup.get_child(0)

	var scroll = ScrollContainer.new()
	scroll.name = "DexScroll"
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "DexList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	_fill_dex_list(list)

	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 重填图鉴列表（领取后原地刷新用，不清弹窗）
func _fill_dex_list(list: VBoxContainer):
	var fs = data.fishing_system
	for child in list.get_children():
		child.queue_free()
	var entries = fs.get_dex_entries()
	for q in FishingSystem.QUALITY_ORDER:
		# 品级标题
		var head = Label.new()
		head.text = "—— %s ——" % q
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 16)
		head.add_theme_color_override("font_color", Color("#ffd700"))
		list.add_child(head)
		# 该品级内：可领取的排最前，其余保持配置顺序
		var group = []
		for f in entries:
			if f.get("quality", "无") == q:
				group.append(f)
		group.sort_custom(func(a, b): return fs.get_dex_state(a.id) == 1 and fs.get_dex_state(b.id) != 1)
		for f in group:
			list.add_child(_build_dex_row(f))

# 构建单个图鉴行：名称(或???)+状态/领取按钮
func _build_dex_row(f: Dictionary) -> HBoxContainer:
	var fs = data.fishing_system
	var state = fs.get_dex_state(f.id)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	if state == 0:
		lbl.text = "？？？"
		lbl.add_theme_color_override("font_color", Color("#666666"))
	else:
		lbl.text = f.get("name", f.id)
		if state == 1:
			# 已解锁未领取：显示领取按钮
			var btn = Button.new()
			btn.text = "领取"
			btn.custom_minimum_size = Vector2(80, 40)
			btn.pressed.connect(_on_claim_dex.bind(f.id))
			row.add_child(btn)
		else:
			var done = Label.new()
			done.text = "已领取"
			done.add_theme_color_override("font_color", Color("#888888"))
			row.add_child(done)
	return row

# 领取图鉴奖励：原地重填图鉴列表（保留滚动位置），奖励弹窗后添加保证在最上层
func _on_claim_dex(fish_id: String):
	var res: Dictionary = data.fishing_system.claim_dex_reward(fish_id)
	if not res.get("ok", false):
		return
	# 原地刷新图鉴列表
	var popup = _find_popup("FishingDexPopup")
	if popup:
		var list = popup.find_child("DexList", true, false)
		var scroll = popup.find_child("DexScroll", true, false)
		var sv = scroll.scroll_vertical if scroll else 0
		if list: _fill_dex_list(list)
		if scroll: scroll.set_deferred("scroll_vertical", sv)   # 保留滚动位置
	_refresh_dots()
	_show_gains_popup("图鉴奖励", res.get("gains", {}))

# ============ 内部工具 ============
# 在 game_controller 根节点下按名字找弹窗
func _find_popup(popup_name: String):
	if c.has_node(popup_name):
		return c.get_node(popup_name)
	return null

# 奖励字典转显示文本（【名称】×数量）
func _rewards_text(rewards: Dictionary) -> String:
	var parts = []
	for iid in rewards.keys():
		var item_name = data.ITEM_CONFIG.get(iid, {}).get("name", iid)
		parts.append("%s×%d" % [item_name, int(rewards[iid])])
	return "、".join(parts)

# 奖励明细弹窗（参照 bag_page._show_item_gains_popup 的写法；后添加保证在最上层）
func _show_gains_popup(title: String, gains: Dictionary):
	var popup = c._create_base_popup(title, Vector2(420, 480))
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for iid in gains.keys():
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = "【%s】×%d" % [data.ITEM_CONFIG.get(iid, {}).get("name", iid), int(gains[iid])]
		list.add_child(lbl)
	c._add_ok_button(vb, func(): popup.queue_free(), "确定")
	c.add_child(popup)
