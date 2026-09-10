class_name MailView
extends RefCounted

# ============================================================
# 邮件全屏页（2026-09-10 商会第二批，骨架版）
# 层级：MailPage z35（同藏品页惯例）；府邸【邮件】入口进入
# 骨架功能：列表（标题/时间/内容/奖励明细）+ 单封领取 + 顶部一键领取，领取即删
# ============================================================

var c      # game_controller 根脚本引用
var data   # GameData 中枢引用

func _init(p_c):
	c = p_c
	data = p_c.data

# ---------- 页面开关 ----------
func show_mail_view():
	_close_node("MailPage")
	var page = Panel.new()
	page.name = "MailPage"
	page.z_index = 35
	page.position = Vector2.ZERO
	page.size = c.get_viewport_rect().size
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color("#1e1b2e")
	page.add_theme_stylebox_override("panel", bg)
	var vb = VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
	# 顶栏：返回 + 标题 + 一键领取
	var top = HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 52)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var back_btn = Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(90, 44)
	back_btn.pressed.connect(hide_mail_view)
	top.add_child(back_btn)
	var title = Label.new()
	title.text = "邮件（%d）" % data.mail_system.get_unclaimed_count()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var claim_all_btn = Button.new()
	claim_all_btn.text = "一键领取"
	claim_all_btn.custom_minimum_size = Vector2(90, 44)
	claim_all_btn.pressed.connect(_on_claim_all)
	top.add_child(claim_all_btn)
	# 动态内容区
	var body = VBoxContainer.new()
	body.name = "MailBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	vb.add_child(body)
	c.add_child(page)
	_fill(body)

func hide_mail_view():
	_close_node("MailPage")

func _close_node(node_name: String):
	var n = c.get_node_or_null(node_name)
	if n:
		c.remove_child(n)
		n.queue_free()

# ---------- 内容填充 ----------
func _fill(body: VBoxContainer):
	for child in body.get_children():
		child.queue_free()
	var mails: Array = data.mail_system.mails
	if mails.is_empty():
		var empty = Label.new()
		empty.text = "暂无邮件"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(empty)
		return
	# 新的在前
	for i in range(mails.size() - 1, -1, -1):
		body.add_child(_make_mail_card(mails[i]))

# 单封邮件卡片：标题+时间 / 内容 / 奖励明细 / 领取按钮
func _make_mail_card(m: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#2a2640")
	style.border_color = Color("#5a5470")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", style)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	# 标题 + 领取按钮一行
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var title = Label.new()
	title.text = str(m.get("title", "邮件"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	head.add_child(title)
	var claim_btn = Button.new()
	claim_btn.text = "领取"
	claim_btn.custom_minimum_size = Vector2(80, 36)
	claim_btn.pressed.connect(_on_claim.bind(str(m.get("id", ""))))
	head.add_child(claim_btn)
	# 时间
	var ts = int(m.get("ts", 0))
	if ts > 0:
		var time_lbl = Label.new()
		time_lbl.text = Time.get_datetime_string_from_unix_time(ts + 8 * 3600, true)
		time_lbl.add_theme_color_override("font_color", Color("#888888"))
		time_lbl.add_theme_font_size_override("font_size", 12)
		vb.add_child(time_lbl)
	# 内容
	var content = str(m.get("content", ""))
	if content != "":
		var content_lbl = Label.new()
		content_lbl.text = content
		content_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(content_lbl)
	# 奖励明细（玩家可见实际数值，踩坑13：不贴后台公式）
	var rewards: Dictionary = m.get("rewards", {})
	if not rewards.is_empty():
		var parts := []
		for item_id in rewards.keys():
			parts.append("%s×%d" % [data.ITEM_CONFIG.get(item_id, {}).get("name", item_id), int(rewards[item_id])])
		var reward_lbl = Label.new()
		reward_lbl.text = "奖励：" + "、".join(parts)
		reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_lbl.add_theme_color_override("font_color", Color("#66ff66"))
		vb.add_child(reward_lbl)
	return card

# ---------- 领取 ----------
func _on_claim(mail_id: String):
	var r = data.mail_system.claim(mail_id)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "领取失败")))
		return
	c._show_stage_hint("已领取，奖励进背包")
	_refresh()

func _on_claim_all():
	var r = data.mail_system.claim_all()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "")))
		return
	# 汇总明细弹窗（复用关卡宝箱结果弹窗套路：背包页有 _show_item_gains_popup）
	var bag_page = c.get_node_or_null("PageContainer/BagPage")
	if bag_page and bag_page.has_method("_show_item_gains_popup"):
		bag_page._show_item_gains_popup("一键领取", r.gains)
	_refresh()

# 领取后整页重建（数量少，直接重建最简单）
func _refresh():
	var page = c.get_node_or_null("MailPage")
	if page == null:
		return
	# 刷新标题数量 + 重建列表
	var vb = page.get_child(0)
	var top = vb.get_child(0)
	var title = top.get_child(1)
	title.text = "邮件（%d）" % data.mail_system.get_unclaimed_count()
	_fill(vb.get_node("MailBody"))
