# ============================================================
# 商会视图（第一期：入会/总览/议事厅/建设/商店/管理）
# 全屏覆盖层挂在闯荡页上（随页面切换自动隐藏），GuildView 自管理开闭，controller 零改动
# 网络读写在本文件驱动：拉记录 → set_record(做人机补结算) → 操作 → guild_save 回写
# 【修】网络层实例是 controller 的 var net: NetSystem（c.net），不是 net_system 名字
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
	# 【修】net_system 在 GameData 上；未登录（token 空）不让进
	if c.net == null or c.net.token == "":
		c._show_stage_hint("请先在设置页登录账号，再使用商会")
		return
	# 【改】未入会：弹窗创建/加入；已入会：直接进入商会主界面（两者不再杂糅）
	if data.guild_system.guild_id == "":
		_show_join_popup()
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
	# 【改】全屏不透明背景：商会是一个独立页面，不再透出底下的闯荡
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#161616")
	_overlay.add_theme_stylebox_override("panel", style)
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
	for t in [["overview", "总览"], ["council", "议事厅"], ["build", "建设"], ["trade", "商贸"], ["shop", "商店"], ["manage", "管理"]]:   # 【改】加商贸页签
		var b = Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(88, 40)   # 【改】6页签收窄防溢出（600宽）
		b.pressed.connect(_on_tab.bind(t[0]))
		tab_box.add_child(b)
	var scroll = ScrollContainer.new()
	scroll.name = "GuildScroll"   # 【修】命名，否则按名取列表会隔一层匿名滚动容器
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
	if _overlay == null: return
	var list = _overlay.get_child(0).get_node("GuildScroll/GuildList")   # 【修】漏了VBox层：覆盖层结构 Overlay→VBox(child0)→…
	for ch in list.get_children(): ch.queue_free()
	var lbl = Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(lbl)

# ============ 刷新：拉记录 → 补结算 → 回写 → 渲染 ============
func _refresh():
	if data.guild_system.guild_id == "":
		close()   # 保险：主界面状态下不应未入会
		return
	_set_hint("商会加载中……")
	c.net.guild_get(data.guild_system.guild_id, func(_code, d):
		if not d.get("ok", false):
			_update_header(null)
			_set_hint("商会加载失败：" + str(d.get("msg", "网络错误")) + "\n点左上角返回后重新进入商会重试")
			return
		data.guild_system.set_record(d.get("record", {}), c.net.username)
		# 【新增】商贸到期惰性结算（发邮件/入经验，幂等），随后与人机补结算一起回写（后存覆盖先存）
		data.guild_system.settle_due_trades()
		c.net.guild_save(data.guild_system.guild_id, data.guild_system.cache, func(_c2, _d2): pass)
		_update_header(data.guild_system.cache)
		_render())

func _update_header(record):
	var header = _overlay.get_child(0).get_node("GuildHeader")   # 【修】漏了VBox层
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
	return _overlay.get_child(0).get_node("GuildScroll/GuildList")   # 【修】漏了VBox层

func _render():
	for ch in _list().get_children(): ch.queue_free()
	match _tab:
		"council": _render_council()
		"build": _render_build()
		"trade": _render_trade()   # 【新增】商贸
		"shop": _render_shop()
		"manage": _render_manage()
		_: _render_overview()

# ============ 未入会：创建/加入 ============
# 未入会弹窗：创建 / 加入（成功后才打开商会主界面）
func _show_join_popup():
	var popup = c._create_base_popup("加入商会", Vector2(480, 520))
	popup.name = "GuildJoinPopup"
	var vb = popup.get_child(0)
	var tip = Label.new()
	tip.text = "创建商会（%d 元宝），或输入邀请码加入好友的商会" % int(data.guild_system.get_settings().get("create_cost", 500))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tip)
	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "输入商会名（2~16字）"
	vb.add_child(name_edit)
	var create_btn = Button.new()
	create_btn.text = "创建商会"
	create_btn.pressed.connect(_on_create.bind(name_edit, popup))
	vb.add_child(create_btn)
	var sep = Label.new()
	sep.text = "———— 或 ————"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sep)
	var id_edit = LineEdit.new()
	id_edit.placeholder_text = "输入16位邀请码"
	vb.add_child(id_edit)
	var join_btn = Button.new()
	join_btn.text = "加入商会"
	join_btn.pressed.connect(_on_join.bind(id_edit, popup))
	vb.add_child(join_btn)
	c._add_ok_button(vb, func(): popup.queue_free(), "取消")
	c.add_child(popup)

func _on_create(name_edit: LineEdit, popup):
	var cost = int(data.guild_system.get_settings().get("create_cost", 500))
	if data.yuanbao < cost:
		c._show_stage_hint("元宝不足（需要%d）" % cost)
		return
	c.net.guild_create(name_edit.text.strip_edges(), func(_code, d):
		if not d.get("ok", false):
			c._show_stage_hint(str(d.get("msg", "创建失败")))
			return
		data.yuanbao -= cost
		data.guild_system.guild_id = str(d.get("guild_id", ""))
		data.save_game()
		popup.queue_free()
		c._show_stage_hint("商会创建成功！去「管理」页招募人机填充商会吧")
		_build_shell()
		_refresh())

func _on_join(id_edit: LineEdit, popup):
	var gid = id_edit.text.strip_edges()
	if gid == "":
		return
	c.net.guild_get(gid, func(_code, d):
		if not d.get("ok", false):
			c._show_stage_hint("邀请码无效：" + str(d.get("msg", "商会不存在")))
			return
		var record = d.get("record", {})
		var gs = data.guild_system
		if record.get("members", []).size() >= gs.get_member_cap(int(record.get("level", 1))):
			c._show_stage_hint("该商会已满员")
			return
		for m in record.get("members", []):
			if not m.get("bot", false) and m.get("user", "") == c.net.username:
				c._show_stage_hint("你已在该商会中")
				return
		record["members"].append({"user": c.net.username, "name": c.net.username, "role": ""})
		c.net.guild_save(gid, record, func(_c2, d2):
			if not d2.get("ok", false):
				c._show_stage_hint("加入失败，请重试")
				return
			data.guild_system.guild_id = gid
			data.save_game()
			popup.queue_free()
			c._show_stage_hint("加入商会成功！")
			_build_shell()
			_refresh()))

# ============ 总览 ============
func _render_overview():
	var list = _list()
	var record = data.guild_system.cache
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "商会等级解锁：成员上限 / 商贸路线 / 商店商品（等级不提供赚速加成）"
	list.add_child(info)
	var code = Label.new()
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code.text = "邀请码：%s（发给好友，在商会入口输入即可加入）" % data.guild_system.guild_id
	list.add_child(code)
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
	# 移除人机：一次只移除一名（防误操作清空）
	var remove_bot = Button.new()
	remove_bot.text = "移除一名人机"
	remove_bot.disabled = bots <= 0
	remove_bot.pressed.connect(_on_remove_bot)
	list.add_child(remove_bot)
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

func _on_remove_bot():
	var members = data.guild_system.cache.get("members", [])
	for i in range(members.size() - 1, -1, -1):
		if members[i].get("bot", false):
			c._show_stage_hint("已移除人机：%s" % members[i].get("name", ""))
			members.remove_at(i)
			break
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
	ok.pressed.connect(func():
		var members = data.guild_system.cache.get("members", [])
		for i in range(members.size()):
			if members[i].get("user", "") == username:
				members.remove_at(i)
				break
		data.guild_system.cache.get("council", {}).erase(username)
		popup.queue_free()
		_save_and_render())
	row.add_child(ok)
	c._add_ok_button(vb, func(): popup.queue_free(), "取消")
	c.add_child(popup)

# 操作后统一：回写服务器 + 重渲染
func _save_and_render():
	c.net.guild_save(data.guild_system.guild_id, data.guild_system.cache, func(_c2, d2):
		if not d2.get("ok", false):
			c._show_stage_hint("同步失败：" + str(d2.get("msg", "网络错误")) + "（下次进入商会会自动补齐）")
		_update_header(data.guild_system.cache)
		_render())


# ============ 商贸（2026-09-10 商会第二批） ============
# 规则（用户拍板）：会长/副会长耗财富开启（可全开）→ 成员委任门客（可多条路线、可多个门客）
# → 全队委任赚速总和≥要求即锁定（不可撤回）→ 倒计时结束发邮件（贡献按占比分，随机池人人平等抽）
# 每天刷新：今天开启第二天没走完也清空；锁定后不可再加人；开启者无额外奖励；人机不参与
func _render_trade():
	var list = _list()
	var gs = data.guild_system
	var record = gs.cache
	var now := Time.get_unix_time_from_system()
	var tip = Label.new()
	tip.text = "商贸：会长/副会长耗财富开启 → 成员委任门客 → 全队赚速达标锁定 → 倒计时结束奖励发邮件（邮件在府邸【邮件】领取）"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color("#aaaaaa"))
	list.add_child(tip)
	for conf in gs.get_trade_list():
		@warning_ignore("narrowing_conversion")
		list.add_child(_make_trade_card(conf, record, now))

func _make_trade_card(conf: Dictionary, record: Dictionary, now: int) -> PanelContainer:
	var gs = data.guild_system
	var tid := str(conf.get("id", ""))
	var status: String = gs.get_trade_status(tid)   # 【修】动态类型变量返回值显式标注，:=推断不出
	var active: Dictionary = gs._trades_of(record).get("active", {}).get(tid, {})
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#2a2640")
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", style)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	# 标题行：名称 + 状态
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var name_lbl = Label.new()
	name_lbl.text = str(conf.get("name", tid))
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	head.add_child(name_lbl)
	var st_lbl = Label.new()
	match status:
		"assigning": st_lbl.text = "委任中"
		"running": st_lbl.text = "已锁定"
		"done": st_lbl.text = "已完成"
		_: st_lbl.text = "未开启"
	st_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	match status:
		"assigning": st_lbl.add_theme_color_override("font_color", Color("#66ccff"))
		"running": st_lbl.add_theme_color_override("font_color", Color("#66ff66"))
		"done": st_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	head.add_child(st_lbl)
	# 信息行
	var info = Label.new()   # 【修】Godot4 的 Label 没有 bbcode_enabled（那是 RichTextLabel 的），不用颜色标签
	var total := 0.0
	var mine := 0.0
	var my_heroes := ""
	if status != "closed":
		for u in active.get("assigns", {}).keys():
			total += float(active["assigns"][u].get("total", 0))
		var my_entry: Dictionary = active.get("assigns", {}).get(c.net.username, {})
		mine = float(my_entry.get("total", 0))
		var parts := []
		for hid in my_entry.get("heroes", {}).keys():
			parts.append(str(data.heroes.get(hid, {}).get("name", hid)))
		my_heroes = "、".join(parts)
	var req := float(conf.get("require", 0))
	info.text = "耗时%s小时 ｜ 要求赚速 %s ｜ 当前 %s ｜ 固定贡献 %d + 经验 %d" % [
		str(conf.get("hours", 0)), c.format_number(req), c.format_number(total),
		int(conf.get("contrib", 0)), int(conf.get("exp", 0))]
	info.add_theme_font_size_override("font_size", 13)
	vb.add_child(info)
	# 我的委任情况
	if status == "assigning" and my_heroes != "":
		var my_lbl = Label.new()
		my_lbl.text = "我的委任：%s（赚速 %s）" % [my_heroes, c.format_number(mine)]
		my_lbl.add_theme_font_size_override("font_size", 13)
		my_lbl.add_theme_color_override("font_color", Color("#66ccff"))
		vb.add_child(my_lbl)
	# 进行中：剩余时间 / 完成提示
	if status == "running":
		var remain := int(active.get("end_ts", 0)) - now
		if remain < 0: remain = 0
		var t_lbl = Label.new()
		@warning_ignore("integer_division")
		t_lbl.text = "剩余 %d小时%02d分（锁定后不可撤回，倒计时结束自动发邮件）" % [remain / 3600, (remain % 3600) / 60]
		t_lbl.add_theme_font_size_override("font_size", 13)
		t_lbl.add_theme_color_override("font_color", Color("#66ff66"))
		vb.add_child(t_lbl)
	elif status == "done":
		var d_lbl = Label.new()
		d_lbl.text = "贸易完成，奖励已发邮件（府邸【邮件】领取）"
		d_lbl.add_theme_font_size_override("font_size", 13)
		d_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
		vb.add_child(d_lbl)
	# 按钮行
	var btns = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	vb.add_child(btns)
	var lv := int(record.get("level", 1))
	var lv_need := int(conf.get("level", 1))
	if status == "closed":
		if lv < lv_need:
			var lock_lbl = Label.new()
			lock_lbl.text = "商会%d级解锁" % lv_need
			lock_lbl.add_theme_color_override("font_color", Color("#888888"))
			btns.add_child(lock_lbl)
		elif gs.is_officer(record):
			var open_btn = Button.new()
			open_btn.text = "开启（财富 %s）" % c.format_number(float(conf.get("cost", 0)))
			open_btn.pressed.connect(_on_trade_open.bind(tid))
			btns.add_child(open_btn)
		else:
			var wait_lbl = Label.new()
			wait_lbl.text = "待会长/副会长开启"
			wait_lbl.add_theme_color_override("font_color", Color("#888888"))
			btns.add_child(wait_lbl)
	elif status == "assigning":
		var assign_btn = Button.new()
		assign_btn.text = "委任门客"
		assign_btn.pressed.connect(_on_trade_assign.bind(tid))
		btns.add_child(assign_btn)
		if mine > 0:
			var wd_btn = Button.new()
			wd_btn.text = "撤回委任"
			wd_btn.pressed.connect(_on_trade_withdraw.bind(tid))
			btns.add_child(wd_btn)
	return card

# ---------- 商贸操作 ----------
func _on_trade_open(trade_id: String):
	var r = data.guild_system.open_trade(trade_id)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "开启失败")))
		return
	c._show_stage_hint("已开启：%s" % str(r.conf.get("name", trade_id)))
	_save_and_render()

func _on_trade_withdraw(trade_id: String):
	var r = data.guild_system.withdraw_trade(trade_id)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "撤回失败")))
		return
	c._show_stage_hint("已撤回委任")
	_save_and_render()

# 委任弹窗：多选门客（CheckBox+meta 读回，避开闭包捕获坑），确认时整体替换我的委任
func _on_trade_assign(trade_id: String):
	var gs = data.guild_system
	var conf = gs.get_trade_conf(trade_id)
	var popup = c._create_base_popup("委任门客·%s" % str(conf.get("name", trade_id)), Vector2(540, 560))
	popup.name = "GuildTradeAssign"
	var vb: VBoxContainer = popup.get_child(0)
	var tip = Label.new()
	tip.text = "勾选门客后点确认；全队赚速达标即锁定，锁定后不可撤回。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color("#aaaaaa"))
	vb.add_child(tip)
	# 当前已委任（回显勾选）
	var cur_heroes: Dictionary = gs._trades_of(gs.cache).get("active", {}).get(trade_id, {}).get("assigns", {}).get(c.net.username, {}).get("heroes", {})
	# 列表（按赚速降序）
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var lst = VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.add_theme_constant_override("separation", 2)
	scroll.add_child(lst)
	var hero_ids: Array = data.heroes.keys()   # 【修】动态类型变量返回值显式标注，:=推断不出
	hero_ids.sort_custom(func(a, b): return HeroData.get_income(data, str(a)) > HeroData.get_income(data, str(b)))
	for hid in hero_ids:
		var s := str(hid)
		var cb = CheckBox.new()
		cb.text = "%s ｜ 赚速 %s" % [str(data.heroes.get(s, {}).get("name", s)), c.format_number(float(HeroData.get_income(data, s)))]
		cb.button_pressed = cur_heroes.has(s)
		cb.set_meta("hid", s)
		lst.add_child(cb)
	# 确认/取消
	var btns = HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	var ok_btn = Button.new()
	ok_btn.text = "确认委任"
	ok_btn.custom_minimum_size = Vector2(120, 40)
	ok_btn.pressed.connect(func():
		var picked: Array = []
		for child in lst.get_children():
			if child is CheckBox and child.button_pressed:
				picked.append(str(child.get_meta("hid")))
		var r = gs.assign_trade(trade_id, picked)
		if not r.get("ok", false):
			c._show_stage_hint(str(r.get("reason", "委任失败")))
			return
		popup.queue_free()
		if r.get("locked", false):
			c._show_stage_hint("全队赚速达标，路线已锁定！")
		else:
			c._show_stage_hint("已委任 %d 名门客（全队赚速还差 %s 达标）" % [picked.size(), c.format_number(float(conf.get("require", 0)) - float(r.get("total", 0)))])
		_save_and_render())
	btns.add_child(ok_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(120, 40)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	btns.add_child(cancel_btn)
	c.add_child(popup)
