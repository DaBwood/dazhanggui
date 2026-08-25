# ============================================================
# 闯荡-游历子视图（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name TravelView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func show_travel_view():
	if not c.has_node("PageContainer/AdventurePage/TravelView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("AdventureVBox").visible = false
	if page.has_node("ExchangeView"): page.get_node("ExchangeView").visible = false
	if page.has_node("LotteryView"): page.get_node("LotteryView").visible = false
	if page.has_node("CharityView"): page.get_node("CharityView").visible = false
	page.get_node("TravelView").visible = true
	page.get_node("TravelView").visible = true
	_ensure_travel_all_check()   # 【新增】首次进入时创建"一键"勾选框
	update_travel_view()


func hide_travel_view():
	if not c.has_node("PageContainer/AdventurePage/TravelView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("TravelView").visible = false
	page.get_node("AdventureVBox").visible = true

func update_travel_view():
	if not c.has_node("PageContainer/AdventurePage/TravelView"): return
	var view = c.get_node("PageContainer/AdventurePage/TravelView")
	var stamina_now = data.get_stamina()   # 懒结算体力恢复
	
	# 体力行改造（只做一次）：体力文本 + “＋”按钮放同一行，点击弹出体力丹数量选择器
	if view.find_child("StaminaPlusBtn", true, false) == null:
		var info = view.find_child("TravelInfo", true, false)
		var parent = info.get_parent()
		var idx = info.get_index()
		parent.remove_child(info)
		var hbox = HBoxContainer.new()
		hbox.name = "StaminaRow"
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 8)
		parent.add_child(hbox)
		parent.move_child(hbox, idx)   # 保持在原位置
		var stamina_lbl = Label.new()   # 体力单独成 Label，“＋”才能紧挨体力显示
		stamina_lbl.name = "StaminaLabel"
		hbox.add_child(stamina_lbl)
		var plus_btn = Button.new()
		plus_btn.name = "StaminaPlusBtn"
		plus_btn.text = "＋"
		plus_btn.custom_minimum_size = Vector2(36, 32)
		plus_btn.tooltip_text = "使用体力丹"
		plus_btn.pressed.connect(_on_stamina_plus_pressed)
		hbox.add_child(plus_btn)
		hbox.add_child(info)   # TravelInfo 改作声望文本
	
	view.find_child("TravelInfo", true, false).text = "体力：%d/%d  |  声望：%s" % [stamina_now, data.STAMINA_MAX, c.format_number(data.reputation)]
	view.get_node("TravelBuffInfo").text = "月老祝福：%d层（谈心对象变为友好最高挚友）  |  观音祝福：%d层（谈心必双胞胎）" % [data.yuelao_count, data.guanyin_count]
	
	var btn = view.find_child("TravelBtn", true, false)
	if btn:
		btn.disabled = false   # 【改】不再禁用；体力不足时点击会弹体力丹数量选择器
	# 表2挚友：已获得标金色，未获得显示好感进度（重建前先移除再释放，避免残留）
	var list = view.get_node("TravelScroll/TravelList")
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for fid in data.TRAVEL_AFFECTION.keys():
		var cfg = data.get_friend_config(fid)
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if data.friends.has(fid):
			lbl.text = "【%s】已获得" % cfg.get("name", fid)
			lbl.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			lbl.text = "【%s】好感 %d/%d" % [cfg.get("name", fid), data.friend_affection.get(fid, 0), data.TRAVEL_AFFECTION[fid]]
		list.add_child(lbl)

func _on_travel():
	# 【新增】勾选了"一键"勾选框时，走一键游历（弹窗汇总）分支
	var check = null
	if c.has_node("PageContainer/AdventurePage/TravelView"):
		check = c.get_node("PageContainer/AdventurePage/TravelView").find_child("TravelAllCheck", true, false)
	if check and check.button_pressed:
		_on_travel_all()
		return
	var result = data.do_travel()
	if not result.ok:
		# 体力不够且有体力丹：直接弹数量选择器；其他情况只提示
		if result.msg == "体力不足" and int(data.items.get("stamina_pill", 0)) > 0:
			_on_stamina_plus_pressed()
		else:
			c._show_stage_hint(result.msg)
		update_travel_view()
		return
	if c.has_node("PageContainer/AdventurePage/TravelView/TravelResult"):
		c.get_node("PageContainer/AdventurePage/TravelView/TravelResult").text = result.msg
	# 若触发了好感解锁，额外提示
	if result.get("unlock_friend", "") != "":
		c._show_stage_hint("喜获挚友【%s】！" % data.friends[result.unlock_friend].name)
	update_travel_view()
	c.update_all_ui()
	c.update_bag_list()
	c.update_friend_page()

# 点击体力行“＋”：弹出体力丹数量选择器（复用全局通用选择器），可批量使用
func _on_stamina_plus_pressed():
	if int(data.items.get("stamina_pill", 0)) <= 0:
		c._show_stage_hint("没有体力丹，可前往元宝商城购买体力礼包")
		return
	c._show_quantity_selector("stamina_pill", "使用体力丹（每颗体力+1）", _on_stamina_pill_confirmed)

# 数量选择器确认回调：参数是选择器里的 SpinBox（与现有小时卡用法一致），批量使用体力丹
func _on_stamina_pill_confirmed(spin):
	var count = int(spin.value)
	c._close_quantity_selector()
	if count <= 0: return
	var result = data.use_item("stamina_pill", count)
	c._show_stage_hint(result.get("msg", ""))
	update_travel_view()
	c.update_bag_list()
	c.update_all_ui()

func _refresh_travel_header():
	if not c.has_node("PageContainer/AdventurePage/TravelView"): return
	var view = c.get_node("PageContainer/AdventurePage/TravelView")
	if not view.visible: return
	var stamina_now = data.get_stamina()   # 懒结算体力恢复
	view.find_child("TravelInfo", true, false).text = "体力：%d/%d  |  声望：%s" % [stamina_now, data.STAMINA_MAX, c.format_number(data.reputation)]
	var btn = view.find_child("TravelBtn", true, false)
	if btn:
		btn.disabled = false   # 【改】不再禁用；体力不足时点击会弹体力丹数量选择器

# 【新增】确保"一键"勾选框存在：把游历按钮缩小后包进居中 HBox，右侧放勾选框（只创建一次）
func _ensure_travel_all_check():
	if not c.has_node("PageContainer/AdventurePage/TravelView"): return
	var view = c.get_node("PageContainer/AdventurePage/TravelView")
	if view.find_child("TravelAllCheck", true, false): return   # 已创建过则跳过
	var btn = view.find_child("TravelBtn", true, false)
	if not btn: return
	var parent = btn.get_parent()
	if parent is Container:
		# 容器布局：建一个居中 HBox 包住按钮 + 勾选框，放回按钮原来的位置
		var idx = btn.get_index()                  # 记录按钮在原容器中的排序
		parent.remove_child(btn)
		var row = HBoxContainer.new()
		row.name = "TravelBtnRow"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		parent.add_child(row)
		parent.move_child(row, idx)                # 放回原位置，不打乱界面顺序
		btn.custom_minimum_size = Vector2(140, 40) # 【改动】按钮缩小
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
		row.add_child(_make_travel_all_check())
	else:
		# 绝对布局兜底：按钮缩小，勾选框直接放到按钮右侧
		btn.size.x = maxf(btn.size.x * 0.6, 120.0) # 【改动】按钮缩小
		var check = _make_travel_all_check()
		parent.add_child(check)
		check.position = btn.position + Vector2(btn.size.x + 12, (btn.size.y - 30) / 2.0)

# 【新增】创建"一键"勾选框（样式统一入口）
func _make_travel_all_check() -> CheckBox:
	var check = CheckBox.new()
	check.name = "TravelAllCheck"
	check.text = "一键"
	return check

# 【新增】一键游历：调用 data.do_travel_all()，结果弹窗展示（确定关闭）
func _on_travel_all():
	var summary = data.do_travel_all()
	if not summary.get("ok", false):
		c._show_stage_hint(summary.get("msg", "体力不足"))
		update_travel_view()
		return
	_show_travel_all_popup(summary)
	# 与单次游历相同的界面联动刷新
	update_travel_view()
	c.update_all_ui()
	c.update_bag_list()
	c.update_friend_page()

# 【新增】一键游历汇总弹窗：概览 + 类型统计 + 物品/挚友/事件收益明细（可滚动）
func _show_travel_all_popup(summary: Dictionary):
	var popup = c._create_base_popup("一键游历", Vector2(520, 600), Vector2(316, 60))
	popup.name = "TravelAllPopup"
	var vb = popup.get_child(0)
	# 概览：次数 + 声望
	var head = Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.text = "连续游历 %d 次，声望 +%s" % [summary.times, c.format_number(summary.reputation)]
	vb.add_child(head)
	# 类型统计：地点/物品/事件各多少次
	var tc = summary.type_count
	var stat = Label.new()
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.text = "地点 %d 次 ｜ 物品 %d 次 ｜ 事件 %d 次" % [tc.get("location", 0), tc.get("item", 0), tc.get("event", 0)]
	vb.add_child(stat)
	# 明细区（可滚动）
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# —— 物品明细（含珍兽果/奇香果独立货币） ——
	if not summary.items_gain.is_empty() or summary.beast_fruit_gain > 0 or summary.aroma_fruit_gain > 0:
		_add_summary_line(list, "—— 获得物品 ——", true)
		for item_id in summary.items_gain.keys():
			var item_name = data.ITEM_CONFIG.get(item_id, {}).get("name", item_id)
			_add_summary_line(list, "【%s】×%d" % [item_name, summary.items_gain[item_id]])
		if summary.beast_fruit_gain > 0:
			_add_summary_line(list, "【珍兽果】×%d" % summary.beast_fruit_gain)
		if summary.aroma_fruit_gain > 0:
			_add_summary_line(list, "【奇香果】×%d" % summary.aroma_fruit_gain)
	# —— 挚友：新解锁 / 友好提升 / 好感进度 ——
	if not summary.unlock_friends.is_empty() or not summary.friendly_gain.is_empty() or not summary.affection_gain.is_empty():
		_add_summary_line(list, "—— 挚友 ——", true)
		for fid in summary.unlock_friends:
			_add_summary_line(list, "喜获挚友【%s】！" % data.get_friend_config(fid).get("name", fid))
		for fid in summary.friendly_gain.keys():
			_add_summary_line(list, "【%s】友好 +%d" % [data.get_friend_config(fid).get("name", fid), summary.friendly_gain[fid]])
		for fid in summary.affection_gain.keys():
			var a = summary.affection_gain[fid]
			_add_summary_line(list, "【%s】好感 +%d（%d/%d）" % [data.get_friend_config(fid).get("name", fid), a.gain, a.now, a.need])
	# —— 事件收益：财神到/月老/观音/杜康/今日新菜 ——
	var has_event = summary.yuanbao_gain > 0 or summary.yuelao_gain > 0 or summary.guanyin_gain > 0 or summary.du_kang_gain > 0 or not summary.hero_income_gain.is_empty()
	if has_event:
		_add_summary_line(list, "—— 事件收益 ——", true)
		if summary.yuanbao_gain > 0:
			_add_summary_line(list, "财神到：元宝 +%s" % c.format_number(summary.yuanbao_gain))
		if summary.yuelao_gain > 0:
			_add_summary_line(list, "月老祝福 +%d 层（当前 %d 层）" % [summary.yuelao_gain, data.yuelao_count])
		if summary.guanyin_gain > 0:
			_add_summary_line(list, "观音祝福 +%d 层（当前 %d 层）" % [summary.guanyin_gain, data.guanyin_count])
		if summary.du_kang_gain > 0:
			_add_summary_line(list, "杜康赠酒：体力 +%d" % summary.du_kang_gain)
		for hid in summary.hero_income_gain.keys():
			_add_summary_line(list, "今日新菜：【%s】基础赚速 +%s" % [data.heroes[hid].name, c.format_number(summary.hero_income_gain[hid])])
	# 收尾：剩余体力（杜康回复的会体现在这里，可能不为0）
	_add_summary_line(list, "剩余体力：%d/%d" % [summary.stamina_after, data.STAMINA_MAX])
	c._add_ok_button(vb, func(): popup.queue_free(), "确定")
	c.add_child(popup)

# 【新增】汇总弹窗内添加一行文本（title=true 为小节标题，金色居中）
func _add_summary_line(parent: Node, text: String, title: bool = false):
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if title:
		lbl.add_theme_color_override("font_color", Color("#ffd700"))   # 小节标题金色，与"已获得"标色一致
	parent.add_child(lbl)
