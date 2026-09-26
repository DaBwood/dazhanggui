# ============================================================
# 门客面板·信物风姿子模块（2026-09-25 架构批次B：从 hero_page.gd 拆分）
# 覆盖：信物面板（绑定/伴生技能/十连）/ 苦情契约（白月初）/ 风姿面板（醉墨挥毫）
# hp = HeroPage 本页引用：共享状态与通用渲染件经 hp.xxx 访问；
# 晋升面板入口经 hp.promo.xxx（模块互调只走 hp 中转，不直接互引用）
# ============================================================
class_name HeroPanelToken
extends RefCounted

var hp     # HeroPage 本页引用
var c      # game_controller 根脚本引用（= hp.c，图省事缓存）
var data   # GameData 数据中枢引用（= hp.data）

# ── 本模块 UI 状态（从 hero_page 迁入）──
var _token_batch: bool = false   # 信物十连勾选状态（面板生命周期内保持）
var _fengzi_batch: bool = false   # 风姿十连勾选状态（面板生命周期内保持）

# 由 HeroPage._init 创建本模块时注入本页引用
func _init(p_hp):
	hp = p_hp
	c = p_hp.c
	data = p_hp.data

# 【批次④】信物伴生技能升级（资质丹，每级消耗=星级；single=1级，bulk=最多10级；上限随信物等级扩容）
func _on_token_skill_upgrade(skill_name: String, mode: String) -> void:
	if hp.current_hero_id == "" or not data.heroes.has(hp.current_hero_id): return
	if data.token_system.upgrade_token_skill(hp.current_hero_id, skill_name, mode != "single") > 0:
		hp.update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()
	else:
		c._show_stage_hint("资质丹不足")   # 【新增】批次②③④-B4：失败反馈（伴生技能耗资质丹）


# ============ 【新增】信物面板 ============

# 【新增】信物按钮点击：打开信物面板
func _on_token_btn_clicked():
	_show_token_panel()


# 【新增】打开信物面板（弹窗；同位置刷新重建模式：remove_child+queue_free 防同名冲突）
func _show_token_panel():
	# 关闭旧面板防同名冲突
	if c.has_node("TokenPanel"):
		var old = c.get_node("TokenPanel")
		c.remove_child(old)
		old.queue_free()
	
	var t_cfg = data.token_system.get_token_cfg(hp.current_hero_id)
	if t_cfg.is_empty(): return
	
	var popup = c._create_base_popup("【信物】%s" % t_cfg.get("token_name", "信物"), Vector2(440, 560))
	popup.name = "TokenPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	
	# ── 信物技能信息（等级/效果）──【改】消耗/拥有移到升级钮上方资源行（2026-09-22 拍板）
	var skill_lbl = Label.new()
	skill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_lbl.text = "【%s】Lv.%d（无上限）\n每级+%d资质（%s与羁绊门客）" % [
		t_cfg.get("skill_name", "信物技能"), data.token_system.get_level(hp.current_hero_id),
		int(t_cfg.get("aptitude_per_level", 3)), data.heroes[hp.current_hero_id].name
	]
	vb.add_child(skill_lbl)

	# 【新增】2026-09-24 倾心共赢（小八信物被动）：动态显示当前百分比/生效状态
	if t_cfg.has("share_passive"):
		var share_lbl = Label.new()
		share_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		share_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var sp_cfg: Dictionary = t_cfg.get("share_passive", {})
		var pct: float = data.token_system.get_share_passive_pct(hp.current_hero_id)
		# 【新增】2026-09-25 投桃报李（小柒）：绑定门客为秦淮五艳时效果翻倍、独立上限（图六规则2文案）
		var double_txt: String = ""
		if sp_cfg.get("wuyan_double", false):
			double_txt = "，羁绊门客为秦淮五艳时效果翻倍（上限%d%%）" % int(sp_cfg.get("wuyan_cap_pct", 30))
		if pct > 0:
			share_lbl.text = "【%s】为绑定门客提供自身资质 %d%%（上限%d%%）%s" % [sp_cfg.get("name", "倾心共赢"), int(pct), int(sp_cfg.get("cap_pct", 30)), double_txt]
		else:
			share_lbl.text = "【%s】晋升无双后生效：为绑定门客提供自身资质（上限%d%%）%s" % [sp_cfg.get("name", "倾心共赢"), int(sp_cfg.get("cap_pct", 30)), double_txt]
		vb.add_child(share_lbl)

	# ── 伴生技能（全信物通用三件套，2026-09-24 用户拍板：信物页展示解锁条件/上限；技能页只显示已解锁）──
	var tsk_lbl = Label.new()
	tsk_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tsk_lbl.add_theme_color_override("font_color", Color("#d4af37"))
	tsk_lbl.text = "伴生技能"
	vb.add_child(tsk_lbl)
	for d in data.token_system.get_token_skills(hp.current_hero_id):
		var trow = Label.new()
		trow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		trow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if int(d["token_lv"]) < int(d["unlock"]):
			trow.add_theme_color_override("font_color", Color("#888888"))
			trow.text = "【%s】信物%d级解锁（每级资质+%d，上限%d）" % [d["name"], int(d["unlock"]), int(d["star"]), int(d["cap"])]
		else:
			trow.add_theme_color_override("font_color", Color("#7ee787"))
			trow.text = "【%s】Lv.%d/%d 资质+%d" % [d["name"], int(d["level"]), int(d["cap"]), int(d["level"]) * int(d["star"])]
		vb.add_child(trow)

	# ── 升级区（十连勾选记忆在类变量 _token_batch，升级/重建不清）──
	# 【改】资源行=【道具名】拥有/消耗（不足整体变红）；token_shared 共享方（刘昴星）无升级区，改显金色共享标注
	var shared_partner: String = data.talent_system.get_token_shared_partner(hp.current_hero_id)
	if shared_partner == "":
		var cost_item: String = t_cfg.get("cost_item", "")
		var cost_need: int = int(t_cfg.get("cost_per_level", 600)) * (10 if _token_batch else 1)	# 十连时消耗×10
		var cost_have: int = int(data.items.get(cost_item, 0))
		var res_lbl = Label.new()
		res_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		res_lbl.text = "【%s】%d/%d" % [data.ITEM_CONFIG.get(cost_item, {}).get("name", cost_item), cost_have, cost_need]
		# 【改】批次②③④-B4：资源行统一 _cost_color 公共件（够绿不够红；原仅不足时红）
		res_lbl.add_theme_color_override("font_color", c._cost_color(cost_have, cost_need))
		vb.add_child(res_lbl)
		var up_box = HBoxContainer.new()
		up_box.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(up_box)
		var up_btn = Button.new()
		up_btn.custom_minimum_size = Vector2(130, 48)
		up_btn.pressed.connect(func():
			var lv = data.token_system.get_level(hp.current_hero_id)
			data.token_system.upgrade(hp.current_hero_id, _token_batch)
			if data.token_system.get_level(hp.current_hero_id) > lv:
				_show_token_panel()   # 重建刷新面板（勾选状态存类变量，不会丢）
				hp.update_hero_panel()   # 资质变化，门客面板对账
				c.update_all_ui()
				c.update_bag_list()
			else:
				c._show_stage_hint("%s不足" % str(data.ITEM_CONFIG.get(cost_item, {}).get("name", cost_item)))   # 【新增】批次②③④-B4：失败反馈
		)
		up_box.add_child(up_btn)
		var batch_check = CheckBox.new()
		batch_check.text = "十连"
		batch_check.button_pressed = _token_batch   # 【新增】恢复上次勾选状态
		batch_check.toggled.connect(func(pressed):
			_token_batch = pressed   # 【新增】记录勾选变化
			up_btn.text = data.token_system.get_upgrade_btn_text(hp.current_hero_id, _token_batch)
			# 【改】十连时资源行消耗×10（批次②③④-B4：统一 _cost_color 着色，够绿不够红）
			var need10 = int(t_cfg.get("cost_per_level", 600)) * (10 if pressed else 1)
			res_lbl.text = "【%s】%d/%d" % [data.ITEM_CONFIG.get(cost_item, {}).get("name", cost_item), cost_have, need10]
			res_lbl.add_theme_color_override("font_color", c._cost_color(cost_have, need10))
		)
		up_box.add_child(batch_check)
		up_btn.text = data.token_system.get_upgrade_btn_text(hp.current_hero_id, _token_batch)
	else:
		var partner_name = data.heroes[shared_partner].name if data.heroes.has(shared_partner) else shared_partner
		var share_lbl = Label.new()
		share_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		share_lbl.text = "共享%s信物等级" % partner_name
		share_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		vb.add_child(share_lbl)
	
	# ── 羁绊绑定区：每格显示 未解锁(灰)/未绑定/已绑定，按解锁等级排序展示 ──
	var binds = data.token_system.get_binds(hp.current_hero_id)
	var unlocks: Array = t_cfg.get("bind_unlock_levels", [0])
	for idx in range(unlocks.size()):
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(row)
		var info = Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.clip_text = true
		row.add_child(info)
		if not data.token_system.is_bind_unlocked(hp.current_hero_id, idx):
			# 未解锁格：灰字显示解锁条件
			info.text = "【锁定】%s Lv.%d 解锁第%d个羁绊" % [t_cfg.get("skill_name", ""), int(unlocks[idx]), idx + 1]
			info.add_theme_color_override("font_color", Color("#888888"))
			continue
		var bind_id = binds[idx]
		if bind_id == "":
			info.text = "第%d个羁绊：未绑定" % (idx + 1)
			var pick_btn = Button.new()
			pick_btn.text = "绑定"
			pick_btn.custom_minimum_size = Vector2(80, 32)
			pick_btn.pressed.connect(func(): _show_token_bind_selector(idx))
			row.add_child(pick_btn)
		else:
			var bh = data.heroes.get(bind_id, {})
			info.text = "第%d个羁绊：【%s】Lv.%d" % [idx + 1, bh.get("name", bind_id), bh.get("level", 1)]
			info.add_theme_color_override("font_color", Color("#ffd700"))
			var rebind_btn = Button.new()
			rebind_btn.text = "换绑"
			rebind_btn.custom_minimum_size = Vector2(70, 32)
			rebind_btn.pressed.connect(func(): _show_token_bind_selector(idx))
			row.add_child(rebind_btn)
			var unbind_btn = Button.new()
			unbind_btn.text = "解绑"
			unbind_btn.custom_minimum_size = Vector2(70, 32)
			unbind_btn.pressed.connect(func():
				data.token_system.unbind(hp.current_hero_id, idx)
				_show_token_panel()   # 重建刷新
				hp.update_hero_panel()
				c.update_all_ui()
			)
			row.add_child(unbind_btn)
	
	# 羁绊效果说明（读配置，不写死数值）
	var hint_lbl = Label.new()
	hint_lbl.text = "绑定后：该门客赚钱+%d%%\n%s资质+其总资质%d%%" % [
		int(float(t_cfg.get("bind_income_pct", 0.10)) * 100),
		data.heroes[hp.current_hero_id].name,
		int(float(t_cfg.get("owner_aptitude_share", 0.01)) * 100)
	]
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_color_override("font_color", Color("#a89ec7"))
	vb.add_child(hint_lbl)
	


# 【新增】苦情契约面板（白月初独有）：契约等级/当前转化赚速/升级（看技能栏资质）/指定挚友列表
func _show_contract_panel():
	# 关闭旧面板防同名冲突（沿用信物/风姿重建惯例）
	if c.has_node("ContractPanel"):
		var old = c.get_node("ContractPanel")
		c.remove_child(old)
		old.queue_free()
	
	var tsys = data.token_system
	var lv = tsys.get_contract_level()
	var slots = tsys.get_contract_slot_count()
	var friends = tsys.get_contract_friends()
	var apt = tsys.get_contract_skill_bar_aptitude()
	var next_req = tsys.get_contract_apt_req(lv + 1)
	
	var popup = c._create_base_popup("【契约】苦情契约", Vector2(440, 620))
	popup.name = "ContractPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	
	# ── 契约信息：等级/转化%/当前赚速（下级需求拆独立行着色；名额与算法说明迁入"i"入口）──
	var info_row = HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 6)
	vb.add_child(info_row)
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "契约 %d级（转化挚友提供赚钱的%d%%）\n当前：+%s赚速" % [
		lv, int(lv * 0.1),
		c.format_number(tsys.get_contract_income(hp.current_hero_id))
	]
	info_row.add_child(info)
	# 【新增】批次②③④-B4：面板内补充信息入口用 i（用户 2026-09-26 约定：玩法规则"?"只在主标题旁）
	var i_btn = Button.new()
	i_btn.text = "i"
	i_btn.custom_minimum_size = Vector2(28, 28)
	i_btn.pressed.connect(_show_contract_hint)
	info_row.add_child(i_btn)
	# 【改】批次②③④-B4：下级需求拆独立行，按 技能栏资质拥有/需求 着色（够绿不够红）
	var req_lbl = Label.new()
	req_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	req_lbl.text = "下级需求：技能栏资质 %d / %d" % [apt, next_req]
	req_lbl.add_theme_color_override("font_color", c._cost_color(apt, next_req))
	vb.add_child(req_lbl)
	
	# ── 升级按钮：不耗道具，技能栏资质够累计需求才可升 ──
	var up_btn = Button.new()
	up_btn.custom_minimum_size = Vector2(140, 40)
	up_btn.text = "契约升级"
	up_btn.disabled = apt < next_req   # 资质不够按钮置灰
	up_btn.pressed.connect(func():
		if data.token_system.upgrade_contract():
			_show_contract_panel()   # 重建刷新
			hp.update_hero_panel()
			c.update_all_ui()
	)
	vb.add_child(up_btn)
	
	# ── 指定挚友列表：每格 未指定(可指定)/已指定(显示提供赚钱+解除) ──
	for i in range(slots):
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(row)
		var row_lbl = Label.new()
		row_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row_lbl.clip_text = true
		row.add_child(row_lbl)
		if i < friends.size() and data.friends.has(friends[i]):
			var fid = friends[i]
			row_lbl.text = "第%d位：【%s】提供赚钱 %s" % [i + 1, data.friends[fid].get("name", fid), c.format_number(tsys.get_friend_contribution(fid))]
			row_lbl.add_theme_color_override("font_color", Color("#ffd700"))
			var un_btn = Button.new()
			un_btn.text = "解除"
			un_btn.custom_minimum_size = Vector2(70, 32)
			un_btn.pressed.connect(func():
				data.token_system.unassign_friend(fid)
				_show_contract_panel()   # 重建刷新
				hp.update_hero_panel()
				c.update_all_ui()
			)
			row.add_child(un_btn)
		else:
			row_lbl.text = "第%d位：未指定" % (i + 1)
			var pick_btn = Button.new()
			pick_btn.text = "指定"
			pick_btn.custom_minimum_size = Vector2(80, 32)
			pick_btn.pressed.connect(func(): _show_contract_friend_selector())
			row.add_child(pick_btn)
	
	# 【删】批次②③④-B4：名额与算法说明迁入"i"入口弹窗 _show_contract_hint（长说明不进画面）
	


# 【新增】批次②③④-B4：契约补充信息弹窗（名额规则+提供赚钱算法；从面板迁入，长说明不进画面）
func _show_contract_hint():
	if c.has_node("ContractHintPopup"):
		var old = c.get_node("ContractHintPopup")
		c.remove_child(old)
		old.queue_free()
	var popup = c._create_base_popup("契约说明", Vector2(420, 220))
	popup.name = "ContractHintPopup"
	popup.z_index = 36   # 高于契约面板(30)与挚友选择器(35)
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child
	var vb = popup.get_child(0)
	for line in [
		"仙缘梦绕达到5/80/200/400级各+1个指定名额（共5个）。",
		"挚友提供赚钱=对每个绑定门客的（固定值+门客基础赚速×百分比）之和。",
	]:
		var body = Label.new()
		body.text = line
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(body)


# 【新增】契约挚友选择器：已拥有且未指定的挚友，按提供赚钱降序，显示具体贡献值
func _show_contract_friend_selector():
	# 关闭旧选择器防同名冲突
	if c.has_node("ContractFriendSelector"):
		var old = c.get_node("ContractFriendSelector")
		c.remove_child(old)
		old.queue_free()
	
	var popup = c._create_base_popup("选择指定挚友", Vector2(440, 480))
	popup.name = "ContractFriendSelector"
	popup.z_index = 35   # 高于契约面板(30)
	c.add_child(popup)
	var vb = popup.get_child(0)
	
	# 候选：已拥有、未指定的挚友，按提供赚钱降序
	var assigned = data.token_system.get_contract_friends()
	var candidates = []
	for fid in data.friends.keys():
		if assigned.has(fid): continue
		candidates.append({"id": fid, "val": data.token_system.get_friend_contribution(fid)})
	candidates.sort_custom(func(a, b): return a.val > b.val)
	if candidates.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "暂无可指定的挚友"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(empty_lbl)
	for cdd in candidates:
		var fdata = data.friends[cdd.id]
		var btn = Button.new()
		btn.text = "【%s】提供赚钱 %s" % [fdata.get("name", cdd.id), c.format_number(cdd.val)]
		btn.pressed.connect(func():
			data.token_system.assign_friend(cdd.id)
			# 关闭选择器并重建契约面板
			if c.has_node("ContractFriendSelector"):
				var old2 = c.get_node("ContractFriendSelector")
				c.remove_child(old2)
				old2.queue_free()
			_show_contract_panel()
			hp.update_hero_panel()
			c.update_all_ui()
		)
		vb.add_child(btn)


# 【新增】羁绊门客选择器：已拥有门客（排除自己与已绑定者），按实时赚速降序
func _show_token_bind_selector(idx: int):
	# 关闭旧选择器防同名冲突
	if c.has_node("TokenBindSelector"):
		var old = c.get_node("TokenBindSelector")
		c.remove_child(old)
		old.queue_free()
	
	var popup = c._create_base_popup("选择羁绊门客", Vector2(440, 480))
	popup.name = "TokenBindSelector"
	popup.z_index = 35   # 高于信物面板(30)
	c.add_child(popup)
	var vb = popup.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 320)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	
	# 候选按实时赚速降序（项目排序惯例）
	var ids = data.token_system.get_bindable_heroes(hp.current_hero_id)
	ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hid in ids:
		var btn = Button.new()
		# 【修】手机端：按钮改 PASS 让触摸滑动穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		var h = data.heroes[hid]
		btn.text = "【%s】Lv.%d  %s/秒" % [h.get("name", hid), h.get("level", 1), c.format_number(data.get_hero_income(hid))]
		btn.pressed.connect(func():
			var res = data.token_system.bind_hero(hp.current_hero_id, idx, hid)
			if res.get("ok", false):
				_close_token_bind_selector()
				_show_token_panel()   # 重建信物面板显示新绑定
				hp.update_hero_panel()
				c.update_all_ui()
			else:
				c.flash_red(btn.get_path())   # 【新增】闪红审计：操作失败反馈（2026-09-19）
				c._show_stage_hint(res.get("msg", "绑定失败"))
		)
		list.add_child(btn)
	
	if ids.is_empty():
		var empty = Label.new()
		empty.text = "暂无可绑定门客"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	


# 【新增】关闭羁绊选择器（remove_child+queue_free 防同名冲突）
func _close_token_bind_selector():
	if c.has_node("TokenBindSelector"):
		var old = c.get_node("TokenBindSelector")
		c.remove_child(old)
		old.queue_free()



# ============ 【新增】风姿面板 ============

# 【新增】打开风姿面板（弹窗；同位置刷新重建：remove_child+queue_free 防同名冲突）
func _show_fengzi_panel():
	if c.has_node("FengziPanel"):
		var old = c.get_node("FengziPanel")
		c.remove_child(old)
		old.queue_free()

	var f_cfg = data.fengzi_system.get_fengzi_cfg(hp.current_hero_id)
	if f_cfg.is_empty(): return
	data.fengzi_system.sync_skills(hp.current_hero_id)   # 打开前幂等同步一次技能/上限

	var popup = c._create_base_popup("【风姿】%s" % f_cfg.get("fengzi_name", "风姿"), Vector2(460, 620))
	popup.name = "FengziPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	var lv = data.fengzi_system.get_level(hp.current_hero_id)
	var h = data.heroes[hp.current_hero_id]
	var every = int(f_cfg.get("skill_unlock_every", 5))
	var skills: Array = f_cfg.get("skills", [])
	var unlock_all = skills.size() * every   # 全部解锁等级（8技能×5级=40）
	var per_level = int(f_cfg.get("aptitude_per_level", 6))

		# ── 升级区（2026-09-24 拍板：等级行与资质行并列一行——等级+问号 | 资质/赚钱信息 | 消耗+按钮）──
	var up_row = HBoxContainer.new()
	up_row.add_theme_constant_override("separation", 14)
	up_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(up_row)
	var up_left = VBoxContainer.new()
	up_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 【改】2026-09-24 拉伸并把内容顶到右侧，与消耗列贴齐
	up_left.alignment = BoxContainer.ALIGNMENT_CENTER
	up_left.add_theme_constant_override("separation", 2)
	var lv_row = HBoxContainer.new()
	lv_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 【改】等级行占满并右对齐
	lv_row.add_theme_constant_override("separation", 6)
	lv_row.alignment = BoxContainer.ALIGNMENT_END
	var lv_lbl = Label.new()
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.text = "【%s】Lv.%d（无上限）" % [f_cfg.get("fengzi_name", "风姿"), lv]
	lv_row.add_child(lv_lbl)
	var q_btn = Button.new()
	q_btn.text = "i"   # 【改】2026-09-26 用户约定：门客面板补充信息入口用 i，"?"只用于玩法主标题规则说明
	q_btn.custom_minimum_size = Vector2(28, 28)
	q_btn.pressed.connect(func(): _show_fengzi_hint(f_cfg, every, unlock_all))
	lv_row.add_child(q_btn)
	up_left.add_child(lv_row)
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT   # 【改】与等级行同右对齐
	info_lbl.text = "资质+%d（下级+%d）  当前赚钱+%d%%" % [
		lv * per_level, (lv + 1) * per_level,
		int(data.fengzi_system.get_income_pct(hp.current_hero_id) * 100)
	]
	up_left.add_child(info_lbl)
	up_row.add_child(up_left)
	var up_right = VBoxContainer.new()
	up_right.alignment = BoxContainer.ALIGNMENT_CENTER   # 【改】2026-09-24 与左列垂直居中对齐
	up_right.add_theme_constant_override("separation", 2)
	var cost_lbl = Label.new()
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fz_have: int = data.items.get(f_cfg.get("cost_item", ""), 0)
	var fz_need: int = int(f_cfg.get("cost_per_level", 600))
	cost_lbl.text = "%s %d/%d" % [
		data.ITEM_CONFIG.get(f_cfg.get("cost_item", ""), {}).get("name", f_cfg.get("cost_item", "")),
		fz_have, fz_need
	]
	cost_lbl.add_theme_color_override("font_color", c._cost_color(fz_have, fz_need))   # 【改】批次②③④-B4：统一走 c._cost_color 公共委托
	up_right.add_child(cost_lbl)
	var up_box = HBoxContainer.new()
	up_box.alignment = BoxContainer.ALIGNMENT_CENTER
	up_right.add_child(up_box)
	up_row.add_child(up_right)
	var up_btn = Button.new()
	up_btn.custom_minimum_size = Vector2(130, 48)
	up_btn.pressed.connect(func():
		var before = data.fengzi_system.get_level(hp.current_hero_id)
		data.fengzi_system.upgrade(hp.current_hero_id, _fengzi_batch)
		if data.fengzi_system.get_level(hp.current_hero_id) > before:
			_show_fengzi_panel()   # 重建刷新（勾选状态存类变量，不会丢）
			hp.update_hero_panel()    # 资质/赚速变化，门客面板对账
			c.update_all_ui()
			c.update_bag_list()
		else:
			c._show_stage_hint("%s不足" % str(data.ITEM_CONFIG.get(f_cfg.get("cost_item", ""), {}).get("name", f_cfg.get("cost_item", ""))))   # 【新增】批次②③④-B4：失败反馈
	)
	up_box.add_child(up_btn)
	var batch_check = CheckBox.new()
	batch_check.text = "十连"
	batch_check.button_pressed = _fengzi_batch   # 【新增】恢复上次勾选状态
	batch_check.toggled.connect(func(pressed):
		_fengzi_batch = pressed   # 【新增】记录勾选变化（钮内不显示消耗，无需刷新文案）
	)
	up_box.add_child(batch_check)
	up_btn.text = "升级"   # 【改】2026-09-24 消耗数字在上行，钮内不重复

	# ── 风姿技能列表：解锁状态 / 当前等级与上限（上限含风姿加成）──
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 240)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for i in range(skills.size()):
		var sname: String = skills[i]
		# 在门客技能栏里按名字找该风姿技能
		var found = null
		for sk in h.aptitude_skills:
			if sk.name == sname:
				found = sk
				break
		var row = Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if found == null:
			# 未解锁：灰字显示解锁所需风姿等级
			row.text = "【%s】未解锁（%s Lv.%d）" % [sname, f_cfg.get("fengzi_name", ""), (i + 1) * every]
			row.add_theme_color_override("font_color", Color("#888888"))
		else:
			# 已解锁：Lv.当前/上限（上限被风姿加成过时金色提示）
			row.text = "【%s】Lv.%d/%d  每级%d资质·%d资质丹" % [
				sname, int(found.level), int(found.max_level),
				int(f_cfg.get("skill_aptitude_per_level", 2)), int(f_cfg.get("skill_aptitude_per_level", 2))
			]
			if int(found.max_level) > int(f_cfg.get("skill_max_level", 200)):
				row.add_theme_color_override("font_color", Color("#ffd700"))
		list.add_child(row)

	c._add_ok_button(vb, func():
		if c.has_node("FengziPanel"):
			var old = c.get_node("FengziPanel")
			c.remove_child(old)
			old.queue_free()
		# 【改】2026-09-24 返回晋升页面，不直接关闭
		hp.promo._on_promo_btn_clicked()
	, "返回")


# 【新增】风姿规则说明弹窗（问号钮，2026-09-24 拍板：读配置不写死数值）
func _show_fengzi_hint(f_cfg: Dictionary, every: int, unlock_all: int):
	var popup = c._create_base_popup("说明", Vector2(420, 200))
	c.add_child(popup)
	var vb = popup.get_child(0)
	var hint_lbl = Label.new()
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_color_override("font_color", Color("#a89ec7"))
	hint_lbl.text = "每%d级解锁1个技能并+%d%%赚钱（%d级全部解锁）\n%d级后每%d级按顺序提升1个技能上限+%d（不再加赚钱）\n技能在门客面板【技能】页消耗资质丹升级" % [
		every, int(float(f_cfg.get("income_pct_per_unlock", 0.05)) * 100), unlock_all,
		unlock_all, int(f_cfg.get("cap_bonus_every", 5)), int(f_cfg.get("cap_bonus_amount", 10))
	]
	vb.add_child(hint_lbl)

