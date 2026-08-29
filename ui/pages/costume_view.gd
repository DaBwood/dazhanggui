# ============================================================
# 服装视图（门客/挚友服装弹窗 + 兑换页-服装兑换子视图）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本；data = GameData 数据中枢）
# ============================================================
class_name CostumeView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 通用 ============
# 品质颜色：素装白 / 锦衣蓝 / 华服金
func _quality_color(quality: String) -> Color:
	match quality:
		"华服": return Color("#ffd700")
		"锦衣": return Color("#66aaff")
	return Color("#ffffff")

# 关闭指定名字的弹窗
func _close_popup(pname: String):
	if c.has_node(pname):
		c.get_node(pname).queue_free()

# ============================================================
# 门客服装弹窗（门客面板【服装】按钮）
# ============================================================
func show_hero_costume_popup(hero_id: String):
	_close_popup("HeroCostumePopup")
	var popup = c._create_base_popup("门客服装", Vector2(640, 500))
	popup.name = "HeroCostumePopup"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 380)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	list.name = "CosList"
	scroll.add_child(list)
	_fill_hero_costume_list(list, hero_id)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 填充门客服装列表：
#   已解锁=亮（显示总等级；有库存则显示"升级"按钮）
#   有库存未解锁=显示"解锁"按钮
#   无库存=灰（显示兑换按钮或暂未开放）
func _fill_hero_costume_list(list: VBoxContainer, hero_id: String):
	for child in list.get_children():
		child.queue_free()
	var cfs = data.costume_system.get_hero_costume_cfgs(hero_id)
	if cfs.is_empty():
		var lbl = Label.new()
		lbl.text = "该门客暂无服装"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)
		return
	for cfg in cfs:
		var cos_id = cfg.get("id", "")
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		var quality = cfg.get("quality", "素装")
		var series = cfg.get("series", "")
		var st = data.costume_system.get_hero_cos_state(hero_id, cos_id)
		var is_unlocked = data.costume_system.is_hero_cos_unlocked(hero_id, cos_id)
		var stock = int(st.get("stock", 0))
		
		if is_unlocked:
			# 已解锁：显示服装技能总等级（基础+额外）
			lbl.text = "【%s】%s Lv.%d" % [quality, cfg.get("name", cos_id), data.costume_system.get_cos_skill_level(hero_id, cos_id)]
			lbl.add_theme_color_override("font_color", _quality_color(quality))
			row.add_child(lbl)
			# 已解锁且有库存：显示"升级"按钮（消耗1库存，加额外等级）
			if stock > 0:
				var up_btn = Button.new()
				up_btn.text = "升级（库存%d）" % stock
				up_btn.custom_minimum_size = Vector2(100, 32)
				up_btn.add_theme_font_size_override("font_size", 12)
				up_btn.pressed.connect(_on_cos_extra_upgrade.bind(hero_id, cos_id))
				row.add_child(up_btn)
		else:
			# 未解锁
			lbl.text = "【%s】%s" % [quality, cfg.get("name", cos_id)]
			row.add_child(lbl)
			if stock > 0:
				# 有库存但未解锁：显示"解锁"按钮
				var unlock_btn = Button.new()
				unlock_btn.text = "解锁（库存%d）" % stock
				unlock_btn.custom_minimum_size = Vector2(100, 32)
				unlock_btn.add_theme_font_size_override("font_size", 12)
				unlock_btn.pressed.connect(_on_cos_unlock.bind(hero_id, cos_id))
				row.add_child(unlock_btn)
				lbl.add_theme_color_override("font_color", Color("#aaaaaa"))   # 有库存但待解锁，淡灰
			else:
				# 无库存
				lbl.add_theme_color_override("font_color", Color("#777777"))   # 未拥有置灰
				if series == "":
					var lock_lbl = Label.new()
					lock_lbl.text = "暂未开放"
					lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					lock_lbl.add_theme_font_size_override("font_size", 12)
					lock_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
					row.add_child(lock_lbl)
				else:
					# 可兑换：显示价格（100个系列道具），不足禁用
					var s = data.costume_system._get_series_cfg(series)
					var cost = int(data.costume_system._settings().get("exchange_cost", 100))
					var have = int(data.items.get(s.get("cost_item", ""), 0))
					var buy_btn = Button.new()
					buy_btn.text = "%s %d/%d" % [s.get("item_name", ""), have, cost]
					buy_btn.custom_minimum_size = Vector2(130, 32)
					buy_btn.add_theme_font_size_override("font_size", 12)
					buy_btn.disabled = have < cost
					buy_btn.pressed.connect(_on_exchange_hero_cos.bind(hero_id, cos_id))
					row.add_child(buy_btn)
		list.add_child(row)

# 门客服装兑换回调：兑换后原地刷新列表 + 门客面板（资质/赚速变化）
func _on_exchange_hero_cos(hero_id: String, cos_id: String):
	var res = data.costume_system.exchange_hero_costume(hero_id, cos_id)
	c._show_stage_hint(res.get("msg", ""))
	if res.get("ok", false):
		var popup = c.get_node_or_null("HeroCostumePopup")
		if popup:
			_fill_hero_costume_list(popup.find_child("CosList", true, false), hero_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# 【新增】手动解锁服装回调：消耗1库存，创建服装状态
func _on_cos_unlock(hero_id: String, cos_id: String):
	var res = data.costume_system.unlock_hero_cos(hero_id, cos_id)
	c._show_stage_hint(res.get("msg", ""))
	if res.get("ok", false):
		var popup = c.get_node_or_null("HeroCostumePopup")
		if popup:
			_fill_hero_costume_list(popup.find_child("CosList", true, false), hero_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# 【新增】手动升级服装（消耗库存加额外等级）回调
func _on_cos_extra_upgrade(hero_id: String, cos_id: String):
	var res = data.costume_system.upgrade_hero_cos_extra(hero_id, cos_id)
	c._show_stage_hint(res.get("msg", ""))
	if res.get("ok", false):
		var popup = c.get_node_or_null("HeroCostumePopup")
		if popup:
			_fill_hero_costume_list(popup.find_child("CosList", true, false), hero_id)
		c.hero_page.update_hero_panel()
		c.update_all_ui()

# ============================================================
# 挚友服装弹窗（挚友详情【服装】按钮）
# ============================================================
func show_friend_costume_popup(friend_id: String):
	_close_popup("FriendCostumePopup")
	var popup = c._create_base_popup("挚友服装", Vector2(640, 500))
	popup.name = "FriendCostumePopup"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 380)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	list.name = "CosList"
	scroll.add_child(list)
	_fill_friend_costume_list(list, friend_id)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 填充挚友服装列表：已兑换次数 + 下次兑换收益；挚友服装无技能无光环
func _fill_friend_costume_list(list: VBoxContainer, friend_id: String):
	for child in list.get_children():
		child.queue_free()
	var cfs = data.costume_system.get_friend_costume_cfgs(friend_id)
	if cfs.is_empty():
		var lbl = Label.new()
		lbl.text = "该挚友暂无服装"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)
		return
	var st = data.costume_system._settings()
	for cfg in cfs:
		var cos_id = cfg.get("id", "")
		var quality = cfg.get("quality", "素装")
		var series = cfg.get("series", "")
		var copies = data.costume_system.get_friend_cos_copies(friend_id, cos_id)
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		# 下次兑换的收益档位：首次 unlock 档，重复 dup 档
		var gain = st.get("friend_unlock" if copies == 0 else "friend_dup", {}).get(quality, [300, 300])
		lbl.text = "【%s】%s%s（下次：友好+%d 才华+%d）" % [quality, cfg.get("name", cos_id), " x%d" % copies if copies > 0 else "", int(gain[0]), int(gain[1])]
		lbl.add_theme_color_override("font_color", _quality_color(quality) if copies > 0 else Color("#777777"))
		row.add_child(lbl)
		if series == "":
			var lock_lbl = Label.new()
			lock_lbl.text = "暂未开放"
			lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lock_lbl.add_theme_font_size_override("font_size", 12)
			lock_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
			row.add_child(lock_lbl)
		else:
			var s = data.costume_system._get_series_cfg(series)
			var cost = int(st.get("exchange_cost", 100))
			var have = int(data.items.get(s.get("cost_item", ""), 0))
			var buy_btn = Button.new()
			buy_btn.text = "%s %d/%d" % [s.get("item_name", ""), have, cost]
			buy_btn.custom_minimum_size = Vector2(130, 32)
			buy_btn.add_theme_font_size_override("font_size", 12)
			buy_btn.disabled = have < cost
			buy_btn.pressed.connect(_on_exchange_friend_cos.bind(friend_id, cos_id))
			row.add_child(buy_btn)
		list.add_child(row)

# 挚友服装兑换回调：兑换后原地刷新列表 + 挚友详情（友好/才华变化）
func _on_exchange_friend_cos(friend_id: String, cos_id: String):
	var res = data.costume_system.exchange_friend_costume(friend_id, cos_id)
	c._show_stage_hint(res.get("msg", ""))
	if res.get("ok", false):
		var popup = c.get_node_or_null("FriendCostumePopup")
		if popup:
			_fill_friend_costume_list(popup.find_child("CosList", true, false), friend_id)
		c.friend_page._update_friend_page_detail()
		c.update_all_ui()

# ============================================================
# 兑换页-服装兑换子视图（代码构建，挂在场景 ExchangeView 下）
# ============================================================
# 确保 CostumeExchangeView 存在（首次进入兑换页时构建）
func ensure_costume_exchange_view():
	var ev_path = "PageContainer/AdventurePage/ExchangeView"
	if not c.has_node(ev_path): return
	var ev = c.get_node(ev_path)
	if ev.has_node("CostumeExchangeView"): return
	var vw = c.get_viewport_rect().size
	# 全尺寸子视图：标题 + 滚动列表
	var view = VBoxContainer.new()
	view.name = "CostumeExchangeView"
	view.visible = false
	view.position = Vector2.ZERO
	view.size = vw
	view.add_theme_constant_override("separation", 8)
	ev.add_child(view)
	var title = Label.new()
	title.name = "CosExTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	view.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.name = "CosExScroll"
	scroll.custom_minimum_size = Vector2(vw.x - 40, vw.y - 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "CosExList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

# 显示服装兑换子视图（从兑换目录进入）
func show_costume_exchange_view():
	ensure_costume_exchange_view()
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	# 隐藏目录与其他子视图，只留服装兑换
	if ev.has_node("ExchangeEntryBox"): ev.get_node("ExchangeEntryBox").visible = false
	if ev.has_node("TokenExchangeView"): ev.get_node("TokenExchangeView").visible = false
	if ev.has_node("BeastExchangeView"): ev.get_node("BeastExchangeView").visible = false
	if ev.has_node("SeriesExchangeView"): ev.get_node("SeriesExchangeView").visible = false
	ev.get_node("CostumeExchangeView").visible = true
	update_costume_exchange_view()

# 隐藏服装兑换子视图（返回目录）
func hide_costume_exchange_view():
	var ev = c.get_node("PageContainer/AdventurePage/ExchangeView")
	ev.get_node("CostumeExchangeView").visible = false
	ev.get_node("ExchangeEntryBox").visible = true

# 刷新服装兑换列表：8个系列分区，每区5件服装卡片
func update_costume_exchange_view():
	var view = c.get_node_or_null("PageContainer/AdventurePage/ExchangeView/CostumeExchangeView")
	if view == null or not view.visible: return
	view.get_node("CosExTitle").text = "—— 服装兑换 ——"
	var list = view.get_node("CosExScroll/CosExList")
	for child in list.get_children():
		child.queue_free()
	for series in data.costume_system._cfgs().get("series", []):
		_add_series_section(list, series)

# 单系列分区：标题（含消耗道具）+ 5件服装行
func _add_series_section(list: VBoxContainer, series: Dictionary):
	var st = data.costume_system._settings()
	var cost = int(st.get("exchange_cost", 100))
	var item_id = series.get("cost_item", "")
	var have = int(data.items.get(item_id, 0))
	# 分区标题：系列名 + 消耗道具拥有/单价
	var title = Label.new()
	var unlocked_cnt = data.costume_system.count_series_unlocked(series.get("name", ""))
	title.text = "【%s】%d/%d 件  （%s：%d/%d）" % [series.get("name", ""), unlocked_cnt, series.get("members", []).size(), series.get("item_name", ""), have, cost]
	title.add_theme_color_override("font_color", Color("#ffd700"))
	list.add_child(title)
	# 服装行
	for m in series.get("members", []):
		var is_friend = series.get("owner_type", "hero") == "friend"
		var owner_id = m.get("owner", "")
		var cfg = data.costume_system._find_cos_cfg_by_name(owner_id, m.get("costume", ""), is_friend)
		if cfg.is_empty(): continue
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		# 拥有者名字（门客/挚友都可能未拥有，未拥有也可查看但不可兑换）
		var owner_name = ""
		var owner_owned = false
		if is_friend:
			owner_owned = data.friends.has(owner_id)
			owner_name = data.friends[owner_id].name if owner_owned else data.get_friend_config(owner_id).get("name", owner_id)
		else:
			owner_owned = data.heroes.has(owner_id)
			owner_name = data.heroes[owner_id].name if owner_owned else data.get_hero_config(owner_id).get("name", owner_id)
		var quality = cfg.get("quality", "素装")
		var state_txt = ""
		if is_friend:
			var copies = data.costume_system.get_friend_cos_copies(owner_id, cfg.get("id", ""))
			if copies > 0:
				state_txt = "（已兑换x%d）" % copies
			else:
				state_txt = "（未拥有挚友）"
		elif owner_owned:
			var cos_st = data.costume_system.get_hero_cos_state(owner_id, cfg.get("id", ""))
			var is_unlocked = data.costume_system.is_hero_cos_unlocked(owner_id, cfg.get("id", ""))
			var stock = int(cos_st.get("stock", 0))
			if is_unlocked:
				state_txt = "（已解锁"
				if stock > 0:
					state_txt += "，库存%d" % stock
				state_txt += "）"
			elif stock > 0:
				state_txt = "（未解锁，库存%d）" % stock
			else:
				state_txt = "（未拥有）"
		else:
			state_txt = "（未拥有门客）"
		lbl.text = "【%s】%s - %s%s" % [quality, cfg.get("name", ""), owner_name, state_txt]
		# 颜色判断：挚友已兑换 / 门客已解锁或有库存 → 品质色；否则白色
		var use_quality_color = false
		if is_friend:
			use_quality_color = data.costume_system.get_friend_cos_copies(owner_id, cfg.get("id", "")) > 0
		elif owner_owned:
			var cos_st2 = data.costume_system.get_hero_cos_state(owner_id, cfg.get("id", ""))
			use_quality_color = data.costume_system.is_hero_cos_unlocked(owner_id, cfg.get("id", "")) or int(cos_st2.get("stock", 0)) > 0
		lbl.add_theme_color_override("font_color", _quality_color(quality) if use_quality_color else Color("#ffffff"))
		row.add_child(lbl)
		var buy_btn = Button.new()
		buy_btn.text = "兑换"
		buy_btn.custom_minimum_size = Vector2(80, 32)
		buy_btn.add_theme_font_size_override("font_size", 12)
		buy_btn.disabled = (not owner_owned) or have < cost
		buy_btn.pressed.connect(_on_exchange_from_view.bind(owner_id, cfg.get("id", ""), is_friend))
		row.add_child(buy_btn)
		list.add_child(row)

# 兑换页里的兑换回调：兑换后原地刷新服装兑换列表
func _on_exchange_from_view(owner_id: String, cos_id: String, is_friend: bool):
	var res = data.costume_system.exchange_friend_costume(owner_id, cos_id) if is_friend else data.costume_system.exchange_hero_costume(owner_id, cos_id)
	c._show_stage_hint(res.get("msg", ""))
	if res.get("ok", false):
		update_costume_exchange_view()
		c.update_all_ui()
