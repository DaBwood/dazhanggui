# ============================================================
# 商会视图（第一期：入会/总览/议事厅/建设/商店/管理）
# 全屏覆盖层挂在闯荡页上（随页面切换自动隐藏），GuildView 自管理开闭，controller 零改动
# 网络读写在本文件驱动：拉记录 → set_record(做人机补结算) → 操作 → guild_save 回写
# ============================================================
class_name GuildView
extends RefCounted

var c
var data
var _page            # 闯荡页节点（覆盖层父节点）
var _tab: String = "overview"   # overview/council/build/shop/manage
var _overlay: PanelContainer = null

func _init(p_c):
	c = p_c
	data = p_c.data

# 闯荡页入口网格加"商会"按钮
func build_entry(page, vbox):
	_page = page
	var btn = Button.new()
	btn.text = "商会"
	btn.custom_minimum_size = Vector2(180, 60)
	btn.pressed.connect(open)
	vbox.get_node("AdventureEntryGrid").add_child(btn)

# ============ 打开/关闭 ============
func open():
	if _overlay != null and is_instance_valid(_overlay):
		return
	if c.net_system == null or c.net_system.token == "":
		c._show_stage_hint("请先在设置页登录账号，再使用商会")
		return
	_build_shell()
	_refresh()

func close():
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null

# ============ 骨架 ============
func _build_shell():
	_overlay = PanelContainer.new()
	_overlay.name = "GuildOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.add_child(_overlay)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_overlay.add_child(vb)
	var back = Button.new()
	back.text = "< 返回闯荡"
	back.pressed.connect(close)
	vb.add_child(back)
	var header = Label.new()
	header.name = "GuildHeader"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(header)
	var tab_box = HBoxContainer.new()
	tab_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_box.add_theme_constant_override("separation", 8)
	vb.add_child(tab_box)
	for t in [["overview", "总览"], ["council", "议事厅"], ["build", "建设"], ["shop", "商店"], ["manage", "管理"]]:
		var b = Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(104, 40)
		b.pressed.connect(_on_tab.bind(t[0]))
		tab_box.add_child(b)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "GuildList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

func _on_tab(kind: String):
	_tab = kind
	_refresh()

func _set_hint(msg: String):
	var list = _overlay.get_node("GuildList") if _overlay else null
	if list == null: return
	for ch in list.get_children(): ch.queue_free()
	var lbl = Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(lbl)

# ============ 刷新：拉记录 → 补结算 → 回写 → 渲染 ============
func _refresh():
	if data.guild_system.guild_id == "":
		_update_header(null)
		_render_join()
		return
	_set_hint("商会加载中……")
	c.net_system.guild_get(data.guild_system.guild_id, func(_code, d):
		if not d.get("ok", false):
			_update_header(null)
			_set_hint("商会加载失败：" + str(d.get("msg", "网络错误")) + "\n点左上角返回后重新进入商会重试")
			return
		data.guild_system.set_record(d.get("record", {}), c.net_system.username)
		# 人机补结算可能有改动，顺手回写（幂等，重复写无害）
		c.net_system.guild_save(data.guild_system.guild_id, data.guild_system.cache, func(_c2, _d2): pass)
		_update_header(data.guild_system.cache)
		_render())

func _update_header(record):
	var header = _overlay.get_node("GuildHeader")
	if record == null or record.is_empty():
		header.text = "尚未加入商会"
		return
	var gs = data.guild_system
	var lv = int(record.get("level", 1))
	var exp_txt = "满级" if lv >= gs.get_max_level() else "经验 %d/%d" % [int(record.get("exp", 0)), gs.get_level_exp(lv)]
	header.text = "%s Lv%d ｜ 财富 %s ｜ %s ｜ 我的贡献 %d ｜ 成员 %d/%d" % [
		record.get("name", ""), lv, c.format_number(float(record.get("wealth", 0))),
		exp_txt, gs.guild_contribution, record.get("members", []).size(), gs.get_member_cap(lv)]

func _list():
	return _overlay.get_node("GuildList")

func _render():
	for ch in _list().get_children(): ch.queue_free()
	match _tab:
		"council": _render_council()
		"build": _render_build()
		"shop": _render_shop()
		"manage": _render_manage()
		_: _render_overview()

# ============ 未入会：创建/加入 ============
func _render_join():
	var list = _list()
	var tip = Label.new()
	tip.text = "创建商会（%d 元宝）或输入邀请码加入好友的商会" % int(data.guild_system.get_settings().get("create_cost", 500))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(tip)
	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "输入商会名（2~16字）"
	list.add_child(name_edit)
	var create_btn = Button.new()
	create_btn.text = "创建商会"
	create_btn.pressed.connect(_on_create.bind(name_edit))
	list.add_child(create_btn)
	var sep = Label.new()
	sep.text = "———— 或 ————"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(sep)
	var id_edit = LineEdit.new()
	id_edit.placeholder_text = "输入16位邀请码"
	list.add_child(id_edit)
	var join_btn = Button.new()
	join_btn.text = "加入商会"
	join_btn.pressed.connect(_on_join.bind(id_edit))
	list.add_child(join_btn)

func _on_create(name_edit: LineEdit):
	var cost = int(data.guild_system.get_settings().get("create_cost", 500))
	if data.yuanbao < cost:
		c._show_stage_hint("元宝不足（需要%d）" % cost)
		return
	c.net_system.guild_create(name_edit.text.strip_edges(), func(_code, d):
		if not d.get("ok", false):
			c._show_stage_hint(str(d.get("msg", "创建失败")))
			return
		data.yuanbao -= cost
		data.guild_system.guild_id = str(d.get("guild_id", ""))
		data.save_game()
		c._show_stage_hint("商会创建成功！去「管理」页招募人机填充商会吧")
		_refresh())

func _on_join(id_edit: LineEdit):
	var gid = id_edit.text.strip_edges()
	if gid == "":
		return
	c.net_system.guild_get(gid, func(_code, d):
		if not d.get("ok", false):
			c._show_stage_hint("邀请码无效：" + str(d.get("msg", "商会不存在")))
			return
		var record = d.get("record", {})
		var gs = data.guild_system
		if record.get("members", []).size() >= gs.get_member_cap(int(record.get("level", 1))):
			c._show_stage_hint("该商会已满员")
			return
		for m in record.get("members", []):
			if not m.get("bot", false) and m.get("user", "") == c.net_system.username:
				c._show_stage_hint("你已在该商会中")
				return
		record["members"].append({"user": c.net_system.username, "name": c.net_system.username, "role": ""})
		c.net_system.guild_save(gid, record, func(_c2, d2):
			if not d2.get("ok", false):
				c._show_stage_hint("加入失败，请重试")
				return
			data.guild_system.guild_id = gid
			data.save_game()
			c._show_stage_hint("加入商会成功！")
			_refresh()))

# ============ 总览 ============
func _render_overview():
	var list = _list()
	var record = data.guild_system.cache
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "商会等级解锁：成员上限 / 商贸路线 / 商店商品（等级不提供赚速加成）"
	list.add_child(info)
	var mem_title = Label.new()
	mem_title.text = "—— 成员 ——"
	mem_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(mem_title)
	for m in record.get("members", []):
		var row = Label.new()
		if m.get("bot", false):
			var career = data.guild_system.get_bot_career(int(m.get("seed", 0)))
			row.text = "%s（人机·%s）" % [m.get("name", ""), career]
		else:
			var mark = "会长" if record.get("owner", "") == m.get("user", "") else ("副会长" if m.get("role", "") == "vice" else "成员")
			row.text = "%s（%s）" % [m.get("name", ""), mark]
		list.add_child(row)

# ============ 议事厅 ============
func _render_council():
	var list = _list()
	var gs = data.guild_system
	var record = gs.cache
	var title = Label.new()
	title.text = "—— 各职业店铺加成（全体成员的委任按职业汇总，加法并入店铺赚速） ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(title)
	for career in gs.get_careers():
		var pct = gs.get_career_bonus(career)
		var lbl = Label.new()
		lbl.text = "%s类店铺 +%d%%" % [career, int(pct * 100)]
		list.add_child(lbl)
	# 明细
	var det = Label.new()
	det.add_theme_color_override("font_color", Color("#888888"))
	det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var lines := []
	for u in record.get("council", {}).keys():
		var e = record["council"][u]
		lines.append("%s：%s（%s +%d%%）" % [u, e.get("hero_name", ""), e.get("career", ""), int(float(e.get("pct", 0)) * 100)])
	for m in record.get("members", []):
		if m.get("bot", false):
			lines.append("%s（人机）：%s +%d%%" % [m.get("name", ""), gs.get_bot_career(int(m.get("seed", 0))), int(gs.get_bot_skill_pct(int(m.get("seed", 0)), record) * 100)])
	det.text = "委任明细：\n" + ("\n".join(lines) if lines.size() > 0 else "（暂无）")
	list.add_child(det)
	# 我的委任
	var my = Label.new()
	my.text = "我的委任：%s" % (data.get_hero_config(gs.guild_council_hero).get("name", "未委任") if gs.guild_council_hero != "" else "未委任")
	list.add_child(my)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	list.add_child(row)
	var pick = Button.new()
	pick.text = "委任/更换门客"
	pick.pressed.connect(_on_council_pick)
	row.add_child(pick)
	if gs.guild_council_hero != "":
		var clear = Button.new()
		clear.text = "撤回委任"
		clear.pressed.connect(_on_council_clear)
		row.add_child(clear)

func _on_council_pick():
	var popup = c._create_base_popup("选择委任门客", Vector2(520, 560))
	popup.name = "GuildCouncilPicker"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var lst = VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lst)
	var heroes = data.heroes.keys()
	heroes.sort_custom(func(a, b): return data.guild_system.get_hero_shop_pct(a) > data.guild_system.get_hero_shop_pct(b))
	for hid in heroes:
		var cfg = data.get_hero_config(hid)
		var b = Button.new()
		b.text = "%s（%s 店铺技能+%d%%）" % [cfg.get("name", hid), cfg.get("career", ""), int(data.guild_system.get_hero_shop_pct(hid) * 100)]
		b.pressed.connect(func():
			var r = data.guild_system.set_council_hero(hid)
			if not r.ok: c._show_stage_hint(r.reason)
			popup.queue_free()
			_save_and_render())
		lst.add_child(b)
	c._add_ok_button(vb, func(): popup.queue_free(), "取消")
	c.add_child(popup)

func _on_council_clear():
	var r = data.guild_system.set_council_hero("")
	if not r.ok: c._show_stage_hint(r.reason)
	_save_and_render()

# ============ 建设 ============
func _render_build():
	var list = _list()
	var gs = data.guild_system
	for kind in ["primary", "middle", "high", "item"]:
		var conf = gs.get_build_conf(kind)
		var used = gs.get_build_used(kind)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var info = Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cost_txt = "免费"
		if int(conf.get("yuanbao", 0)) > 0:
			cost_txt = "%d元宝" % int(conf.yuanbao)
		if str(conf.get("item", "")) != "":
			cost_txt = "消耗%s×%d" % [data.ITEM_CONFIG.get(str(conf.item), {}).get("name", conf.item), int(conf.get("item_count", 1))]
		info.text = "%s ｜ %s ｜ 今日 %d/%d\n财富+%s 贡献+%d 经验+%d" % [
			conf.get("name", kind), cost_txt, used, int(conf.get("daily", 0)),
			c.format_number(float(conf.get("wealth", 0))), int(conf.get("contribution", 0)), int(conf.get("exp", 0))]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var btn = Button.new()
		btn.text = "建设"
		btn.disabled = used >= int(conf.get("daily", 0))
		btn.pressed.connect(_on_build.bind(kind))
		row.add_child(btn)

func _on_build(kind: String):
	var r = data.guild_system.build(kind)
	if not r.ok:
		c._show_stage_hint(r.reason)
		return
	_save_and_render()

# ============ 商店 ============
func _render_shop():
	var list = _list()
	var gs = data.guild_system
	var record = gs.cache
	var lv = int(record.get("level", 1))
	_add_shop_section(list, "—— 每日限购 ——", gs.get_shop_daily(), lv)
	_add_shop_section(list, "—— 每月限购 ——", gs.get_shop_monthly(), lv)
	var tip = Label.new()
	tip.add_theme_color_override("font_color", Color("#888888"))
	tip.text = "货币：个人贡献（建设商会获得）"
	list.add_child(tip)

func _add_shop_section(list, section_name: String, entries: Array, guild_lv: int):
	var t = Label.new()
	t.text = section_name
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(t)
	for e in entries:
		var locked = guild_lv < int(e.get("level", 1))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var info = Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var used = data.guild_system._buy_used(str(e.row), e)
		var name_txt: String
		if str(e.get("beast", "")) != "":
			name_txt = str(data._beast_configs.get(str(e.beast), {}).get("name", e.beast))
		else:
			name_txt = str(data.ITEM_CONFIG.get(str(e.item), {}).get("name", e.item))
		info.text = "%s ｜ %d贡献 ｜ 已购 %d/%d%s" % [name_txt, int(e.cost), used, int(e.limit), "（%d级解锁）" % int(e.level) if locked else ""]
		row.add_child(info)
		var btn = Button.new()
		btn.text = "兑换"
		btn.disabled = locked
		btn.pressed.connect(_on_buy.bind(str(e.row)))
		row.add_child(btn)

func _on_buy(row_id: String):
	var r = data.guild_system.buy(row_id)
	if not r.ok:
		c._show_stage_hint(r.reason)
		return
	c._show_stage_hint("兑换成功！")
	_update_header(data.guild_system.cache)
	_render()

# ============ 管理（招募人机/任命副会长/踢人） ============
func _render_manage():
	var list = _list()
	var gs = data.guild_system
	var record = gs.cache
	if not gs.is_officer(record):
		var tip = Label.new()
		tip.text = "只有会长/副会长可以管理商会"
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(tip)
		return
	var bots = gs.get_bot_count(record)
	var room = gs.get_member_cap(int(record.get("level", 1))) - record.get("members", []).size()
	var info = Label.new()
	info.text = "人机 %d 名 ｜ 空位 %d ｜ 人机每天自动建设（财富+经验各%d）" % [bots, room, int(gs.get_settings().get("bot_daily_wealth", 600))]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(info)
	var recruit = Button.new()
	recruit.text = "招募人机填满空位"
	recruit.disabled = room <= 0
	recruit.pressed.connect(_on_recruit)
	list.add_child(recruit)
	# 会长特权：任命副会长 / 踢人（真人）
	if record.get("owner", "") == gs.my_user:
		var t2 = Label.new()
		t2.text = "—— 成员管理（会长） ——"
		t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(t2)
		for m in record.get("members", []):
			if m.get("bot", false): continue
			if m.get("user", "") == gs.my_user: continue
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			list.add_child(row)
			var lbl = Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.text = "%s（%s）" % [m.get("name", ""), "副会长" if m.get("role", "") == "vice" else "成员"]
			row.add_child(lbl)
			var vice = Button.new()
			vice.text = "取消副会长" if m.get("role", "") == "vice" else "设为副会长"
			vice.pressed.connect(_on_set_vice.bind(str(m.user)))
			row.add_child(vice)
			var kick = Button.new()
			kick.text = "踢出"
			kick.pressed.connect(_on_kick.bind(str(m.user), str(m.name)))
			row.add_child(kick)

func _on_recruit():
	var r = data.guild_system.recruit_bots()
	if not r.ok:
		c._show_stage_hint(r.reason)
		return
	c._show_stage_hint("已招募 %d 名人机" % int(r.count))
	_save_and_render()

func _on_set_vice(username: String):
	var record = data.guild_system.cache
	for m in record.get("members", []):
		if m.get("user", "") == username:
			m["role"] = "" if m.get("role", "") == "vice" else "vice"
	_save_and_render()

func _on_kick(username: String, disp_name: String):
	var popup = c._create_base_popup("踢出成员", Vector2(400, 220))
	popup.name = "GuildKickPopup"
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "确定把 %s 踢出商会？" % disp_name
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var ok = Button.new()
	ok.text = "确认踢出"
	ok.custom_minimum_size = Vector2(140, 44)
	var record = data.guild_system.cache
	ok.pressed.connect(func():
		var members = record.get("members", [])
		for i in range(members.size()):
			if members[i].get("user", "") == username:
				members.remove_at(i)
				break
		record.get("council", {}).erase(username)
		popup.queue_free()
		_save_and_render())
	row.add_child(ok)
	c._add_ok_button(vb, func(): popup.queue_free(), "取消")
	c.add_child(popup)

# 操作后统一：回写服务器 + 重渲染
func _save_and_render():
	c.net_system.guild_save(data.guild_system.guild_id, data.guild_system.cache, func(_c2, d2):
		if not d2.get("ok", false):
			c._show_stage_hint("同步失败：" + str(d2.get("msg", "网络错误")) + "（下次进入商会会自动补齐）")
		_update_header(data.guild_system.cache)
		_render())
