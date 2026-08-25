# ============================================================
# 闯荡-抽奖子视图（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name LotteryView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func show_lottery_view():
	if not c.has_node("PageContainer/AdventurePage"): return
	var page = c.get_node("PageContainer/AdventurePage")
	if page.has_node("AdventureVBox"):
		page.get_node("AdventureVBox").visible = false
	if page.has_node("ExchangeView"):
		page.get_node("ExchangeView").visible = false
	if page.has_node("LotteryView"):
		page.get_node("LotteryView").visible = true
		update_lottery_view()

func hide_lottery_view():
	if not c.has_node("PageContainer/AdventurePage"): return
	var page = c.get_node("PageContainer/AdventurePage")
	if page.has_node("LotteryView"):
		page.get_node("LotteryView").visible = false
	if page.has_node("AdventureVBox"):
		page.get_node("AdventureVBox").visible = true

func update_lottery_view():
	if not c.has_node("PageContainer/AdventurePage/LotteryView"): return
	var view = c.get_node("PageContainer/AdventurePage/LotteryView")
	view.get_node("LotteryRes").text = "抽奖券：%d  |  元宝：%s  |  累计：%d/500" % [
		data.lottery_ticket, c.format_number(data.yuanbao), data.lottery_draw_count
	]
	
	var single = view.find_child("LotterySingleBtn", true, false)
	var ten = view.find_child("LotteryTenBtn", true, false)
	var hundred = view.find_child("LotteryHundredBtn", true, false)
	
	if single:
		single.disabled = data.lottery_ticket < 1 and data.yuanbao < 50
	if ten:
		ten.disabled = data.lottery_ticket < 9 and data.yuanbao < 450
	if hundred:
		hundred.disabled = data.lottery_ticket < 90 and data.yuanbao < 4500

func on_lottery_draw(draw_count: int, ticket_need: int):
	var ticket_have = data.lottery_ticket
	if ticket_have >= ticket_need:
		_do_lottery_draw(draw_count, ticket_need, false)
	else:
		var short = ticket_need - ticket_have
		var need_yuanbao = short * 50
		if data.yuanbao < need_yuanbao:
			c._show_stage_hint("抽奖券和元宝均不足！")
			return
		_show_lottery_confirm(draw_count, ticket_need, ticket_have)

func _do_lottery_draw(draw_count: int, ticket_need: int, use_yuanbao: bool):
	var result = data.do_lottery_draw(draw_count, ticket_need, use_yuanbao)
	if result.ok:
		_show_lottery_results(result.results)
		c.update_all_ui()
		c.update_bag_list()
		if c.has_node("PageContainer/AdventurePage/LotteryView"):
			update_lottery_view()
	else:
		c._show_stage_hint(result.reason)

func _show_lottery_confirm(draw_count: int, ticket_need: int, ticket_have: int):
	var short = ticket_need - ticket_have
	var need_yuanbao = short * 50
	
	var panel = c._create_base_popup("抽奖券不足", Vector2(420, 240), Vector2(366, 204))
	panel.name = "LotteryConfirmPanel"
	
	var vbox = panel.get_child(0)
	var info = Label.new()
	info.text = "抽奖券不足，是否消耗 %d 元宝补足 %d 张抽奖券？\n（拥有元宝：%s）" % [
		need_yuanbao, short, c.format_number(data.yuanbao)
	]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)
	
	var confirm = Button.new()
	confirm.text = "确认"
	confirm.pressed.connect(func():
		c._safe_close("LotteryConfirmPanel")
		_do_lottery_draw(draw_count, ticket_need, true)
	)
	btn_box.add_child(confirm)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func():
		c._safe_close("LotteryConfirmPanel")
		c.get_node("Overlay").hide()
		c._current_popup = null
	)
	btn_box.add_child(cancel)
	
	c.add_child(panel)
	c._current_popup = panel
	c.get_node("Overlay").show()

func _show_lottery_results(results: Array):
	if c.has_node("LotteryResultPanel"): return
	
	var panel = c._create_base_popup("抽奖结果", Vector2(480, 520), Vector2(336, 64))
	panel.name = "LotteryResultPanel"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 380)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	
	for r in results:
		var lbl = Label.new()
		var item_name = ""
		if r.get("is_beast", false):
			item_name = data.get_beast_config(r.item).name
		elif r.item == "money":
			item_name = "铜钱"
		else:
			item_name = data.ITEM_CONFIG.get(r.item, {}).get("name", r.item)
		lbl.text = "【%s】x%d" % [item_name, r.count]
		list.add_child(lbl)
	
	c._add_ok_button(vbox, func():
		c._safe_close("LotteryResultPanel")
		c.get_node("Overlay").hide()
		c._current_popup = null
	)
	
	c.add_child(panel)
	c._current_popup = panel
	c.get_node("Overlay").show()
