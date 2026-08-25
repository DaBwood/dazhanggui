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
	view.get_node("TravelInfo").text = "体力：%d/%d  |  声望：%s" % [stamina_now, data.STAMINA_MAX, c.format_number(data.reputation)]
	view.get_node("TravelBuffInfo").text = "月老祝福：%d层（谈心对象变为友好最高挚友）  |  观音祝福：%d层（谈心必双胞胎）" % [data.yuelao_count, data.guanyin_count]
	var btn = view.find_child("TravelBtn", true, false)
	if btn:
		btn.disabled = stamina_now < 1
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

func _refresh_travel_header():
	if not c.has_node("PageContainer/AdventurePage/TravelView"): return
	var view = c.get_node("PageContainer/AdventurePage/TravelView")
	if not view.visible: return
	var stamina_now = data.get_stamina()   # 懒结算体力恢复
	view.get_node("TravelInfo").text = "体力：%d/%d  |  声望：%s" % [stamina_now, data.STAMINA_MAX, c.format_number(data.reputation)]
	var btn = view.find_child("TravelBtn", true, false)
	if btn:
		btn.disabled = stamina_now < 1

