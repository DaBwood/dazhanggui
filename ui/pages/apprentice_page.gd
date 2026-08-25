# ============================================================
# 徒弟页（含培养/结业/联姻）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name ApprenticePage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var _apprentice_batch_train: bool = false   # 徒弟一键培养勾选状态（页面重建时保持）
var _apprentice_tab: String = "train"   # train / lover / magician / married
var _proposed_spouse: Dictionary = {}
var _proposing_slot: int = -1
var _vitality_target_slot: int = -1         # 活力丹目标槽位

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_apprentice_page():
	if not c.has_node("PageContainer"): return
	var page = c.get_node("PageContainer/ApprenticePage") if c.has_node("PageContainer/ApprenticePage") else null
	if page == null:
		page = Panel.new()
		page.name = "ApprenticePage"
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		c.get_node("PageContainer").add_child(page)
	
	for child in page.get_children():
		child.queue_free()
	
	var vbox = VBoxContainer.new()
	vbox.name = "ApprenticeVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	page.add_child(vbox)
	
	var title = Label.new()
	title.text = "徒弟"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	
	# 板块切换栏
	var tab_bar = HBoxContainer.new()
	tab_bar.name = "ApprenticeTabBar"
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(tab_bar)
	
	var tabs = [["train", "徒弟培养"], ["lover", "现充"], ["magician", "魔法师"], ["married", "已婚"]]
	for t in tabs:
		var btn = Button.new()
		btn.name = "Tab_" + t[0]
		btn.text = t[1]
		btn.custom_minimum_size = Vector2(140, 44)
		btn.pressed.connect(_on_apprentice_tab.bind(t[0]))
		tab_bar.add_child(btn)
	
	# 内容滚动区（套用修好的布局模式：scroll双向填充，内容只横向填充）
	var scroll = ScrollContainer.new()
	scroll.name = "ApprenticeScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var content = VBoxContainer.new()
	content.name = "ApprenticeContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

func _on_apprentice_tab(tab: String):
	_apprentice_tab = tab
	update_apprentice_page()

func update_apprentice_page():
	if not c.has_node("PageContainer/ApprenticePage/ApprenticeVBox"): return
	var vbox = c.get_node("PageContainer/ApprenticePage/ApprenticeVBox")
	var content = vbox.get_node("ApprenticeScroll/ApprenticeContent")
	for child in content.get_children():
		child.queue_free()
	
	match _apprentice_tab:
		"train": _update_apprentice_train(content)
		_: _update_apprentice_list_view(content, _apprentice_tab)
	
	# 高亮当前板块按钮
	for btn in vbox.get_node("ApprenticeTabBar").get_children():
		btn.modulate = Color("#e0c070") if btn.name == "Tab_" + _apprentice_tab else Color("#c9a959")

func _update_apprentice_train(content: VBoxContainer):
	# 一键培养勾选框（状态存成员变量，页面刷新不丢）
	var batch_check = CheckBox.new()
	batch_check.name = "BatchTrainCheck"
	batch_check.text = "一键培养（消耗全部活力）"
	batch_check.button_pressed = _apprentice_batch_train
	batch_check.toggled.connect(func(pressed): _apprentice_batch_train = pressed)
	content.add_child(batch_check)
	
	var unlocked = data.get_apprentice_slot_count()
	for i in range(5):
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		content.add_child(row)
		
		var info = Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(info)
		
		# 未解锁槽位
		if i >= unlocked:
			info.text = "【槽位%d】身份等级 Lv.%d 解锁" % [i + 1, data.APPRENTICE_UNLOCK_LEVELS[i]]
			info.modulate = Color(0.5, 0.5, 0.5)
			continue
		
		var entry = data.apprentices[i]
		# 空位
		if entry == null or (entry is Array and entry.is_empty()):
			info.text = "【槽位%d】空位 —— 与挚友谈心可领养徒弟" % (i + 1)
			continue
		
		# 已有徒弟（1~2名，双胞胎占同一槽位）
		var list = entry if entry is Array else [entry]
		var first = list[0]
		var state_txt = {"training": "培养中", "adult": "待结业"}.get(first.state, first.state)
		var friend_name = ""
		if data.friends.has(first.friend_id):
			friend_name = data.friends[first.friend_id].name
		
		# 每个徒弟的名字行
		var names_txt = ""
		for a in list:
			var q = data.FRIEND_TITLES[clamp(a.get("quality_idx", 0), 0, data.FRIEND_TITLES.size() - 1)].quality
			names_txt += "【%s】%s | %s | 品质:%s\n" % [a.name, a.gender, a.career, q]
		if list.size() > 1:
			names_txt = "双胞胎！\n" + names_txt
		
		info.text = "%s挚友:%s\n进度 %d/10000 | 赚速 %s/秒 | 活力 %d/500 | %s" % [
			names_txt, friend_name,
			first.progress, c.format_number(data.get_apprentice_income(i)),
			data.get_slot_vigor(i), state_txt
		]
		
		# 培养中：活力旁加"+"按钮（使用活力丹）
		if first.state == "training":
			var plus_btn = Button.new()
			plus_btn.text = "+"
			plus_btn.custom_minimum_size = Vector2(36, 40)
			plus_btn.tooltip_text = "使用活力丹恢复活力"
			plus_btn.pressed.connect(_show_vitality_pill_prompt.bind(i))
			row.add_child(plus_btn)
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(100, 40)
		if first.state == "training":
			btn.text = "培养"
			btn.pressed.connect(_on_train_apprentice.bind(i))
		else:
			# 待结业（结业的徒弟会离开槽位）
			btn.text = "结业"
			btn.pressed.connect(_show_graduate_selector.bind(i))
		row.add_child(btn)

func _update_apprentice_list_view(content: VBoxContainer, state: String):
	var has_any = false
	for i in range(data.graduated_apprentices.size()):
		var a = data.graduated_apprentices[i]
		if a == null or a.state != state: continue
		has_any = true
		
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		content.add_child(row)
		
		var info = Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var quality_txt = data.FRIEND_TITLES[clamp(a.get("quality_idx", 0), 0, data.FRIEND_TITLES.size() - 1)].quality
		var txt = "【%s】%s | %s | 品质:%s | 赚速 %s/秒" % [a.name, a.gender, a.career, quality_txt, c.format_number(data.get_graduated_income(i))]
		if state == "magician":
			txt += " | 魔法加成 +%d%%" % int(a.magic_bonus * 100)
		elif state == "married":
			var sp = a.get("spouse", {})
			txt += " | 配偶:【%s】%s +%s/秒" % [sp.get("name", ""), sp.get("gender", ""), c.format_number(a.get("spouse_income", 0))]
		info.text = txt
		row.add_child(info)
		
		# 现充板块有提亲按钮
		if state == "lover":
			var btn = Button.new()
			btn.text = "提亲"
			btn.custom_minimum_size = Vector2(100, 40)
			btn.pressed.connect(_show_marriage_proposal.bind(i))
			row.add_child(btn)
	
	if not has_any:
		var empty = Label.new()
		empty.text = "暂无徒弟"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty)

func _on_train_apprentice(slot: int):
	if _apprentice_batch_train:
		var result = data.train_apprentice_batch(slot)
		if result.ok:
			update_apprentice_page()
			c.update_all_ui()
			var msg = "一键培养 ×%d" % result.count
			if result.get("adult", false):
				msg += "，徒弟已成年，可以结业了"
			elif result.get("stop_reason", "") != "":
				msg += "（%s）" % result.stop_reason
			c._show_stage_hint(msg)
		else:
			_handle_train_fail(slot, result.reason)
	else:
		var result = data.train_apprentice(slot)
		if result.ok:
			update_apprentice_page()
			c.update_all_ui()
			if result.get("adult", false):
				c._show_stage_hint("培养完成！徒弟已成年，可以结业了")
		else:
			_handle_train_fail(slot, result.reason)

func _handle_train_fail(slot: int, reason: String):
	if reason == "活力不足" and data.items.get("vitality_pill", 0) > 0:
		_show_vitality_pill_prompt(slot)
	else:
		c._show_stage_hint(reason)

func _show_graduate_selector(slot: int):
	c._safe_close("GraduatePanel")
	var entry = data.apprentices[slot]
	if entry == null: return
	var list = entry if entry is Array else [entry]
	if list.is_empty(): return
	var a = list[0]
	
	var panel = c._create_base_popup("选择结业方向", Vector2(420, 280), Vector2(366, 170))
	panel.name = "GraduatePanel"
	var vbox = panel.get_child(0)
	
	# 双胞胎提示当前进度
	if list.size() > 1:
		var twin_lbl = Label.new()
		twin_lbl.text = "双胞胎结业（第1个/共%d个）" % list.size()
		twin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		twin_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		vbox.add_child(twin_lbl)
	
	var info = Label.new()
	info.text = "【%s】%s | %s\n当前赚速：%s/秒" % [
		a.name, a.gender, a.career,
		c.format_number(data._get_single_apprentice_income(a))
	]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	var magic_btn = Button.new()
	magic_btn.text = "转职魔法师\n赚速提升70%-140%"
	magic_btn.custom_minimum_size = Vector2(200, 60)
	magic_btn.pressed.connect(_on_graduate.bind(slot, "magician"))
	vbox.add_child(magic_btn)
	
	var lover_btn = Button.new()
	lover_btn.text = "成为现充\n可提亲联姻"
	lover_btn.custom_minimum_size = Vector2(200, 60)
	lover_btn.pressed.connect(_on_graduate.bind(slot, "lover"))
	vbox.add_child(lover_btn)
	
	c._add_ok_button(vbox, func(): c._safe_close("GraduatePanel"), "取消")
	c.add_child(panel)

func _on_graduate(slot: int, path: String):
	if data.graduate_apprentice_one(slot, path):
		c._safe_close("GraduatePanel")
		# 刚结业的徒弟在已结业列表末尾
		var a = data.graduated_apprentices.back()
		if path == "magician":
			c._show_stage_hint("【%s】转职魔法师！赚速提升 %d%%" % [a.name, int(a.magic_bonus * 100)])
		else:
			c._show_stage_hint("【%s】结业成功！已进入现充" % a.name)
		update_apprentice_page()
		c.update_all_ui()
		# 双胞胎：槽位里还有徒弟，继续为其选择方向
		if data.apprentices[slot] != null:
			_show_graduate_selector(slot)

func _show_vitality_pill_prompt(slot: int):
	var max_pills = data.items.get("vitality_pill", 0)
	if max_pills <= 0:
		c._show_stage_hint("没有活力丹，可前往商城购买活力礼包")
		return
	_vitality_target_slot = slot
	c._safe_close("VitalityPillPrompt")
	
	var panel = c._create_base_popup("使用活力丹", Vector2(420, 280), Vector2(366, 184))
	panel.name = "VitalityPillPrompt"
	var vbox = panel.get_child(0)
	
	var info = Label.new()
	info.text = "槽位%d 当前活力：%d/500\n拥有活力丹：%d（每个+5）" % [slot + 1, data.get_slot_vigor(slot), max_pills]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	var pair = c._create_slider_spin_pair(vbox, max_pills)
	var spin = pair.spin
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	var use_btn = Button.new()
	use_btn.text = "使用"
	use_btn.custom_minimum_size = Vector2(80, 36)
	use_btn.pressed.connect(_on_use_vitality_pill.bind(spin))
	btn_box.add_child(use_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 36)
	cancel_btn.pressed.connect(func(): c._safe_close("VitalityPillPrompt"))
	btn_box.add_child(cancel_btn)
	
	c.add_child(panel)

func _on_use_vitality_pill(spin: SpinBox):
	var count = clamp(int(spin.value), 1, data.items.get("vitality_pill", 0))
	if data.use_vitality_pill(_vitality_target_slot, count):
		c._safe_close("VitalityPillPrompt")
		c._show_stage_hint("活力 +%d！" % (5 * count))
		update_apprentice_page()
		c.update_bag_list()
	_vitality_target_slot = -1

func _show_marriage_proposal(slot: int):
	c._safe_close("MarriagePanel")
	_proposing_slot = slot
	_proposed_spouse = data.generate_spouse(slot)
	if _proposed_spouse.is_empty(): return
	
	var a = data.graduated_apprentices[slot]
	var panel = c._create_base_popup("提亲", Vector2(420, 300), Vector2(366, 140))
	panel.name = "MarriagePanel"
	var vbox = panel.get_child(0)
	
	var info = Label.new()
	info.text = "徒弟【%s】\n\n联姻对象：【%s】%s | %s\n赚速：%s/秒\n\n联姻后获得对方赚速" % [
		a.name,
		_proposed_spouse.name, _proposed_spouse.gender, _proposed_spouse.career,
		c.format_number(_proposed_spouse.income)
	]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	var marry_btn = Button.new()
	marry_btn.text = "联姻"
	marry_btn.custom_minimum_size = Vector2(100, 40)
	marry_btn.pressed.connect(_on_marry_apprentice)
	btn_box.add_child(marry_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "再想想"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(func(): c._safe_close("MarriagePanel"))
	btn_box.add_child(cancel_btn)
	
	c.add_child(panel)

func _on_marry_apprentice():
	if data.marry_apprentice(_proposing_slot, _proposed_spouse):
		c._safe_close("MarriagePanel")
		c._show_stage_hint("联姻成功！徒弟已进入已婚")
		update_apprentice_page()
		c.update_all_ui()
		_proposing_slot = -1
		_proposed_spouse = {}
