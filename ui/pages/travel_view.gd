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
