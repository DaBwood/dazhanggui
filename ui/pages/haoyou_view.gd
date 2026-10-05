# ============================================================
# 好友系统界面（2026-10-05 真人版：管理/搜索/拜访/点赞，游历页与厢房页共用本模块）
# 层级跟随所属页：厢房全屏页(z35) → 弹窗/遮罩 z40/39；主页面 → z30/25（照妙音坊/厢房抬层模板）
# 逻辑全在 systems/haoyou_system.gd；真人接口走 systems/net_system.gd（未登录=人机功能全可用）
# ============================================================
class_name HaoyouView
extends RefCounted

var c
var data

func _init(p_c):
	c = p_c
	data = p_c.data

# ==================== 入口 ====================

func on_entry_pressed():
	if c.get_node_or_null("HaoyouPopup") != null:
		_refresh_popup()
		return
	_show_popup()
	_net_sync_on_open()

func _is_logged_in() -> bool:
	return c.net != null and str(c.net.token) != ""

# ==================== 弹窗骨架 ====================

func _show_popup():
	var popup = c._create_base_popup("好友", Vector2(560, 640))
	popup.name = "HaoyouPopup"
	if c.has_node("XiangfangPage") and c.get_node("XiangfangPage").visible:
		popup.get_meta("popup_mask").z_index = 39
		popup.z_index = 40
	var vb: VBoxContainer = popup.get_child(0)
	var head := HBoxContainer.new()
	head.name = "HaoyouHead"
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(head)
	var status := Label.new()
	status.name = "HaoyouStatus"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(status)
	var rule_btn := Button.new()
	rule_btn.text = "?"
	rule_btn.custom_minimum_size = Vector2(30, 30)
	rule_btn.pressed.connect(_on_rule)
	head.add_child(rule_btn)
	_build_search_row(vb)
	var scroll := ScrollContainer.new()
	scroll.name = "HaoyouScroll"
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "HaoyouList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	_build_bottom(vb)
	c.add_child(popup)
	_refresh_popup()

# 搜索行：已登录=输入框+搜索钮；未登录=登录提示（人机功能不受影响，用户拍板）
func _build_search_row(vb: VBoxContainer):
	if _is_logged_in():
		var row := HBoxContainer.new()
		row.name = "HaoyouSearchRow"
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		var edit := LineEdit.new()
		edit.name = "HaoyouSearchEdit"
		edit.placeholder_text = "输入角色名搜索真人玩家"
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.custom_minimum_size = Vector2(0, 40)
		edit.text_submitted.connect(_on_search_submitted)
		row.add_child(edit)
		c._hook_web_cjk_input(edit, "角色名")   # Web 端中文 IME 引擎级未修，聚焦弹原生 prompt
		var btn := Button.new()
		btn.text = "搜索"
		btn.custom_minimum_size = Vector2(80, 40)
		btn.pressed.connect(_on_search)
		row.add_child(btn)
		var hint := Label.new()
		hint.name = "HaoyouSearchHint"
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color("#bdb8d0"))
		vb.add_child(hint)
	else:
		var hint := Label.new()
		hint.name = "HaoyouSearchHint"
		hint.text = "登录云存档后可搜索/拜访真人玩家（人机好友功能不受影响）"
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color("#bdb8d0"))
		vb.add_child(hint)

func _build_bottom(vb: VBoxContainer):
	var bottom := HBoxContainer.new()
	bottom.name = "HaoyouBottom"
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	vb.add_child(bottom)
	for spec in [["一键赠礼", "_on_send_all"], ["一键领礼", "_on_claim_all"], ["一键点赞", "_on_like_all"], ["加人机", "_on_add_ai"]]:
		var btn := Button.new()
		btn.text = spec[0]
		btn.custom_minimum_size = Vector2(110, 46)
		btn.pressed.connect(Callable(self, spec[1]))
		bottom.add_child(btn)

# ==================== 刷新（原地重建，不删旧建新——关弹窗+立刻重建同名弹窗会踩自动改名雷） ====================

func _refresh_popup():
	var popup = c.get_node_or_null("HaoyouPopup")
	if popup == null:
		return
	var vb: VBoxContainer = popup.get_child(0)
	var status: Label = vb.get_node("HaoyouHead/HaoyouStatus")
	var friends = data.get_haoyou_friends()
	status.text = "可领礼 %d/%d（名额 %d/%d）｜ 可点赞 %d ｜ 好友 %d/%d" % [
		data.get_haoyou_claimable_count(), friends.size(),
		data.get_haoyou_claimed_count(), data.get_haoyou_claim_cap(),
		data.get_haoyou_likeable_count(),
		friends.size(), data.get_haoyou_friend_cap(),
	]
	var list: VBoxContainer = vb.get_node("HaoyouScroll/HaoyouList")
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for i in friends.size():
		_fill_card(list, i)
	c.update_travel_view()

# 好友卡片：左=名+类型+友好，右=赠礼/领礼/拜访/点赞 2×2 + 删除通栏
func _fill_card(list: VBoxContainer, i: int):
	var f: Dictionary = data.get_haoyou_friends()[i]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style())
	list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_row := HBoxContainer.new()
	info.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = str(f.get("name", ""))
	name_row.add_child(name_lbl)
	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color("#9b8fd4") if str(f.get("kind", "ai")) == "real" else Color("#7a7a8c"))
	tag.text = " 真人" if str(f.get("kind", "ai")) == "real" else " 人机"
	name_row.add_child(tag)
	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color("#bdb8d0"))
	sub.text = "友好 %d" % int(f.get("friendly", 0))
	info.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	_card_btn(grid, i, "赠礼", "已赠", data.haoyou_can_send(i), "_on_send")
	_card_btn(grid, i, "领礼", "已领", data.haoyou_can_claim(i), "_on_claim")
	var can_visit := true
	_card_btn(grid, i, "拜访", "拜访", can_visit, "_on_visit")
	_card_btn(grid, i, "点赞", "已赞", data.haoyou_can_like(i), "_on_like")
	var del := Button.new()
	del.text = "删除好友"
	del.custom_minimum_size = Vector2(0, 34)
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del.pressed.connect(_on_remove.bind(i))
	grid.add_child(del)
	var spacer := Control.new()
	grid.add_child(spacer)

func _card_btn(grid: GridContainer, i: int, on_text: String, off_text: String, enabled: bool, handler: String):
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(76, 44)
	if enabled:
		btn.text = on_text
		btn.pressed.connect(Callable(self, handler).bind(i))
	else:
		btn.text = off_text
		btn.disabled = true
	grid.add_child(btn)

func _make_card_style() -> StyleBoxFlat:
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color("#221d33")
	sty.border_color = Color("#6a5f9e")
	sty.set_border_width_all(1)
	sty.set_corner_radius_all(6)
	sty.set_content_margin_all(8)
	return sty

# ==================== 搜索（真人） ====================

func _on_search_submitted(_text: String):
	_on_search()

func _on_search():
	var popup = c.get_node_or_null("HaoyouPopup")
	if popup == null:
		return
	var edit: LineEdit = popup.get_child(0).get_node("HaoyouSearchRow/HaoyouSearchEdit")
	var kw := edit.text.strip_edges()
	if kw == "":
		c._show_success_popup("请输入角色名", 0.0, "warn")
		return
	var hint: Label = popup.get_child(0).get_node("HaoyouSearchHint")
	hint.text = "搜索中…"
	c.net.hy_search(kw, func(code: int, d: Dictionary):
		if c.get_node_or_null("HaoyouPopup") == null:
			return
		var h2: Label = popup.get_child(0).get_node("HaoyouSearchHint")
		if code != 200 or not d.get("ok", false):
			h2.text = "搜索失败，请稍后重试"
			return
		var list: Array = d.get("list", [])
		if list.is_empty():
			h2.text = "没有找到角色【%s】" % kw
			return
		var parts: Array = []
		for u in list:
			var uname := str(u.get("username", ""))
			var dname := str(u.get("display_name", ""))
			var label := dname if dname != "" else uname
			if data.haoyou_find_by_user(uname) >= 0:
				parts.append("%s（已是好友）" % label)
			else:
				parts.append("%s [添加]" % label)
		h2.text = "搜索结果：" + "、".join(parts)
		# 结果带添加动作：逐条挂按钮更直观，此处用第二行结果卡
		_show_search_results(list)
	)

func _show_search_results(users: Array):
	var popup = c.get_node_or_null("HaoyouPopup")
	if popup == null:
		return
	c._safe_close("HaoyouSearchPopup")
	var sp = c._create_base_popup("搜索结果", Vector2(480, 340))
	sp.name = "HaoyouSearchPopup"
	if c.has_node("XiangfangPage") and c.get_node("XiangfangPage").visible:
		sp.get_meta("popup_mask").z_index = 39
		sp.z_index = 40
	var vb: VBoxContainer = sp.get_child(0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for u in users:
		var uname := str(u.get("username", ""))
		var dname := str(u.get("display_name", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var lbl := Label.new()
		lbl.text = "%s（%s）" % [dname, uname]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		if data.haoyou_find_by_user(uname) >= 0:
			btn.text = "已是好友"
			btn.disabled = true
		else:
			btn.text = "添加"
			btn.custom_minimum_size = Vector2(72, 40)
			btn.pressed.connect(_on_add_real.bind(uname, dname))
		row.add_child(btn)
	c.add_child(sp)

func _on_add_real(user: String, p_name: String):
	var r: Dictionary = data.haoyou_add_real_friend(user, p_name)
	c._show_success_popup(r.get("msg", ""), 0.0, "ok" if r.get("ok", false) else "warn")
	if r.get("ok", false):
		c._safe_close("HaoyouSearchPopup")
		_refresh_popup()

# ==================== 好友操作 ====================

func _on_add_ai():
	var r: Dictionary = data.haoyou_add_ai_friend()
	c._show_success_popup(r.get("msg", ""), 0.0, "ok" if r.get("ok", false) else "warn")
	_refresh_popup()

func _on_remove(i: int):
	var r: Dictionary = data.haoyou_remove_friend(i)
	c._show_success_popup(r.get("msg", ""), 0.0, "ok" if r.get("ok", false) else "warn")
	_refresh_popup()

func _on_send(i: int):
	var r: Dictionary = data.haoyou_send_gift(i)
	if not r.get("ok", false):
		c._show_success_popup(r.get("msg", ""), 0.0, "warn")
		return
	_refresh_popup()

func _on_claim(i: int):
	var r: Dictionary = data.haoyou_claim_gift(i)
	if not r.get("ok", false):
		c._show_success_popup(r.get("msg", ""), 0.0, "warn")
		return
	_refresh_popup()
	c.update_bag_list()

func _on_send_all():
	var r: Dictionary = data.haoyou_send_all()
	if int(r.get("count", 0)) == 0:
		c._show_success_popup("今日已全部赠过礼", 0.0, "warn")
		return
	c._show_success_popup("已向 %d 位好友赠礼" % int(r.get("count", 0)), 0.0, "ok")
	_refresh_popup()

func _on_claim_all():
	var r: Dictionary = data.haoyou_claim_all()
	if int(r.get("count", 0)) == 0:
		c._show_success_popup("今日名额已领完或已全部领过", 0.0, "warn")
		return
	c._show_success_popup("领取 %d 位好友回礼：体力丹×%d" % [int(r.get("count", 0)), int(r.get("pills", 0))], 0.0, "ok")
	_refresh_popup()
	c.update_bag_list()

func _on_like(i: int):
	var r: Dictionary = data.haoyou_like_friend(i)
	if not r.get("ok", false):
		c._show_success_popup(r.get("msg", ""), 0.0, "warn")
		return
	_refresh_popup()
	c.update_bag_list()
	if str(r.get("kind", "")) == "real" and _is_logged_in():
		c.net.hy_like(str(r.get("user", "")), data.haoyou_today(), func(code: int, _d: Dictionary):
			if code == 409:
				data.haoyou_rollback_like_user(str(r.get("user", "")))
				c._show_success_popup("服务器记录今日已赞，奖励已回收", 0.0, "warn")
				_refresh_popup()
				c.update_bag_list()
		)

func _on_like_all():
	var r: Dictionary = data.haoyou_like_all()
	if int(r.get("count", 0)) == 0:
		c._show_success_popup("今日已全部赞过", 0.0, "warn")
		return
	c._show_success_popup("已赞 %d 位好友：家具币/风水符已入账" % int(r.get("count", 0)), 0.0, "ok")
	_refresh_popup()
	c.update_bag_list()
	if _is_logged_in():
		for u in r.get("real_users", []):
			c.net.hy_like(str(u), data.haoyou_today(), func(code: int, _d: Dictionary):
				if code == 409:
					data.haoyou_rollback_like_user(str(u))
					_refresh_popup()
					c.update_bag_list()
			)

# ==================== 拜访 ====================

func _on_visit(i: int):
	var f: Dictionary = data.get_haoyou_friends()[i]
	if str(f.get("kind", "ai")) == "real":
		if not _is_logged_in():
			c._show_success_popup("登录云存档后可拜访真人玩家", 0.0, "warn")
			return
		c.net.hy_profile_get(str(f.get("user", "")), func(code: int, d: Dictionary):
			if code == 404:
				c._show_success_popup("对方暂无拜访档案（对方进一次好友页即可生成）", 0.0, "warn")
				return
			if code != 200 or not d.get("ok", false):
				c._show_success_popup("读取失败，请稍后重试", 0.0, "warn")
				return
			_show_visit_popup(str(f.get("name", "")), d.get("profile", {}))
		)
	else:
		_show_visit_popup(str(f.get("name", "")), data.haoyou_make_ai_profile(str(f.get("name", ""))))

func _show_visit_popup(owner_name: String, profile: Dictionary):
	c._safe_close("HaoyouVisitPopup")
	var vp = c._create_base_popup("拜访·%s" % owner_name, Vector2(560, 620))
	vp.name = "HaoyouVisitPopup"
	if c.has_node("XiangfangPage") and c.get_node("XiangfangPage").visible:
		vp.get_meta("popup_mask").z_index = 39
		vp.z_index = 40
	var vb: VBoxContainer = vp.get_child(0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_visit_section_title(list, "总赚速：%s" % _fmt_num(int(profile.get("total_income", 0))))
	var heroes: Array = profile.get("heroes", [])
	_visit_section_title(list, "门客（%d）" % heroes.size())
	for h in heroes:
		var extras: Array = []
		if str(h.get("beast", "")) != "":
			extras.append("珍兽:%s" % h.beast)
		if str(h.get("fish", "")) != "":
			extras.append("渔获:%s" % h.fish)
		if str(h.get("cuzhi", "")) != "":
			extras.append("促织:%s" % h.cuzhi)
		var auras: Array = h.get("auras", [])
		if not auras.is_empty():
			extras.append("光环:%s" % "、".join(auras))
		var extra_text := ""
		if not extras.is_empty():
			extra_text = "\n  " + " ｜ ".join(extras)
		_visit_line(list, "【%s】%s Lv.%d ｜ 赚钱 %s%s" % [h.get("name", "?"), h.get("category", ""), int(h.get("level", 1)), _fmt_num(int(h.get("income", 0))), extra_text])
	var zhiyou: Array = profile.get("zhiyou", [])
	_visit_section_title(list, "挚友（%d）" % zhiyou.size())
	for z in zhiyou:
		_visit_line(list, "【%s】友好 %d ｜ 好感 %d" % [z.get("name", "?"), int(z.get("friendly", 0)), int(z.get("affection", 0))])
	var shops: Array = profile.get("shops", [])
	_visit_section_title(list, "商铺（%d）" % shops.size())
	for s in shops:
		_visit_line(list, "【%s】Lv.%d ｜ 赚速 %s" % [s.get("name", "?"), int(s.get("level", 1)), _fmt_num(int(s.get("income", 0)))])
	c.add_child(vp)

func _visit_section_title(list: VBoxContainer, text: String):
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color("#ffd700"))
	lbl.add_theme_font_size_override("font_size", 16)
	list.add_child(lbl)

func _visit_line(list: VBoxContainer, text: String):
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(lbl)

# 数值千分位缩写：与全站赚速显示口径一致（万/亿）
func _fmt_num(n: int) -> String:
	if n >= 100000000:
		return "%.2f亿" % (n / 100000000.0)
	if n >= 10000:
		return "%.2f万" % (n / 10000.0)
	return "%d" % n

# ==================== 打开时网络同步（登记角色名+自报拜访档案+对齐今日已赞） ====================

func _net_sync_on_open():
	if not _is_logged_in():
		return
	c.net.hy_name_register(str(data.player_name))
	c.net.hy_profile_save(data.haoyou_build_profile())
	c.net.hy_likes_today(data.haoyou_today(), func(code: int, d: Dictionary):
		if code == 200 and d.get("ok", false):
			data.haoyou_mark_liked(d.get("list", []))
			_refresh_popup()
	)

# ==================== 规则 ====================

# 规则弹窗：公式+叠加口径，不写状态词（勋章批次拍板口径）
func _on_rule():
	c._show_rule_popup("好友规则", "好友上限50（人机+真人）；体力丹每位好友固定1颗，每日限领%d名（基础20名，藏品【幽恒】每星+3名）；赠礼不耗资源友好+1；点赞每位好友每天1次（奖励家具币×5+风水符×1）；真人需登录云存档，拜访为快照制（对方进好友页时自报）。" % data.get_haoyou_claim_cap())
