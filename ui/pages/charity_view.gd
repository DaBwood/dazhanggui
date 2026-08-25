# ============================================================
# 闯荡-行善子视图（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name CharityView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func show_charity_view():
	if not c.has_node("PageContainer/AdventurePage/CharityView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("AdventureVBox").visible = false
	if page.has_node("ExchangeView"): page.get_node("ExchangeView").visible = false
	page.get_node("CharityView").visible = true
	update_charity_view()

func hide_charity_view():
	if not c.has_node("PageContainer/AdventurePage/CharityView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("CharityView").visible = false
	page.get_node("AdventureVBox").visible = true

func update_charity_view():
	if not c.has_node("PageContainer/AdventurePage/CharityView"): return
	var view = c.get_node("PageContainer/AdventurePage/CharityView")
	var cost = data.get_charity_cost()   # 顺带触发跨天重置
	view.get_node("CharityInfo").text = "今日已行善 %d 次（消耗每天重置）" % data.charity_click_count
	var btn = view.find_child("CharityBtn", true, false)
	btn.text = "行善（-%s铜钱，随机地点）" % c.format_number(cost)
	btn.disabled = data.money < cost
	
	# 五个地点的进度和加成池
	var list = view.get_node("CharityScroll/CharityList")
	for child in list.get_children():
		child.queue_free()
	for loc in data.CHARITY_LOCATIONS:
		var p = data.charity_progress.get(loc.id, {"progress": 0, "tier": 0})
		var need = data.get_charity_tier_need(loc.id)
		var lbl = Label.new()
		lbl.text = "【%s】%s类徒弟赚速加成池 +%d（%d档）  |  进度 %d/%d" % [
			loc.name, loc.career, p.tier * data.CHARITY_EFFECT_PER_TIER, p.tier, p.progress, need
		]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)

func _on_charity():
	var view = c.get_node("PageContainer/AdventurePage/CharityView")
	var batch = false
	var check = view.find_child("CharityBatchCheck", true, false)
	if check != null:
		batch = check.button_pressed
	
	if not batch:
		# 单次行善
		var result = data.do_charity()
		if not result.ok:
			c._show_stage_hint(result.reason)
			return
		var msg = "在【%s】行善！\n获得：%s" % [result.location, "、".join(result.rewards)]
		if result.completed:
			msg += "\n\n第%d档完成！%s类徒弟赚速加成池 +%d（结业时生效）" % [result.tier, result.career, data.CHARITY_EFFECT_PER_TIER]
		c._show_stage_hint(msg, 4.0)
	else:
		# 十连：逐次结算（每次消耗按当时次数×1.5递增），失败即停
		var done = 0
		var total_cost = 0
		var loc_counts = {}
		var reward_counts = {}
		var tier_msgs = []
		for i in range(10):
			var r = data.do_charity()
			if not r.ok: break
			done += 1
			total_cost += r.cost
			loc_counts[r.location] = loc_counts.get(r.location, 0) + 1
			for rw in r.rewards:
				reward_counts[rw] = reward_counts.get(rw, 0) + 1
			if r.completed:
				tier_msgs.append("【%s】第%d档（%s类+%d）" % [r.location, r.tier, r.career, data.CHARITY_EFFECT_PER_TIER])
		if done == 0:
			c._show_stage_hint("铜钱不足")
			return
		var loc_parts = []
		for k in loc_counts.keys():
			loc_parts.append("%s×%d" % [k, loc_counts[k]])
		var rw_parts = []
		for k in reward_counts.keys():
			rw_parts.append("%s×%d" % [k, reward_counts[k]])
		var msg = "行善 ×%d（共 -%s 铜钱）\n地点：%s\n奖励：%s" % [done, c.format_number(total_cost), "、".join(loc_parts), "、".join(rw_parts)]
		if not tier_msgs.is_empty():
			msg += "\n\n满档：\n" + "\n".join(tier_msgs)
		if done < 10:
			msg += "\n（铜钱不足，提前结束）"
		c._show_stage_hint(msg, 5.0)
	
	update_charity_view()
	c.update_all_ui()
	c.update_bag_list()
	c.update_friend_page()
