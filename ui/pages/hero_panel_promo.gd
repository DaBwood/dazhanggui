# ============================================================
# 门客面板·晋升子模块（2026-09-25 架构批次B：从 hero_page.gd 拆分）
# 覆盖：赋诗晋升 / 服装一键晋升 / 金兰（花木兰）/ 亲和（沉香）/ 拜师（小八）/ 复制天赋 /
#       凤魁全家桶（秦淮五艳晋升+五岳服装+转移）/ 三家光环卡（小八师徒·小舞双人·小柒自带）
# hp = HeroPage 本页引用：共享状态（current_hero_id/_use_baiye/_sel_idx）与
# 通用渲染件（update_hero_panel/_render_skill_tab）一律经 hp.xxx 访问；独立消耗/门槛行走 c._add_cost_row 统一范式（批次②③④-B9）；
# 信物/风姿面板入口经 hp.token.xxx（模块互调只走 hp 中转，不直接互引用）
# ============================================================
class_name HeroPanelPromo
extends RefCounted

var hp     # HeroPage 本页引用
var c      # game_controller 根脚本引用（= hp.c，图省事缓存）
var data   # GameData 数据中枢引用（= hp.data）

# ── 本模块 UI 状态（从 hero_page 迁入）──
var _promo_batch: bool = false   # 赋诗十连勾选状态（面板生命周期内保持）
var _fengkui_tab: String = "skill"   # 凤魁页面当前页签（skill=凤魁技能/wuyue=山河五岳）

# 由 HeroPage._init 创建本模块时注入本页引用
func _init(p_hp):
	hp = p_hp
	c = p_hp.c
	data = p_hp.data

func on_promotion_upgrade(mode: String = "single"):
	var upgraded = data.upgrade_promotion(hp.current_hero_id, mode == "bulk")
	if upgraded > 0:
		hp.update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()
	else:
		# 【新增】批次②③④-B4：失败反馈（晋升耗对应道具，道具名读配置）
		var promo_cfg: Dictionary = data.heroes[hp.current_hero_id].get("promotion", {})
		var iname: String = str(data.ITEM_CONFIG.get(str(promo_cfg.get("cost_item", "")), {}).get("name", "晋升道具"))
		c._show_stage_hint("%s不足" % iname)


# 【改】晋升面板参数化 v3：标题/资质技能名/解锁列表/按钮文案全部读 promotion 配置
# （李白=赋诗·天生我材，白月初=续缘·仙缘梦绕）；【新增】苦情契约按钮（白月初独有，位置同风姿按钮）
func _on_promo_btn_clicked():
	if hp.current_hero_id == "" or not data.heroes.has(hp.current_hero_id): return
	var h = data.heroes[hp.current_hero_id]
	if not h.has("promotion"): return
	var promo = h.promotion
	var promo_name: String = promo.get("name", "晋升")
	var skill_name: String = promo.get("skill_name", promo_name)
	var item_name = data.ITEM_CONFIG[promo.cost_item].name
	
	# 【改】标题参数化："赋诗等级"/"续缘等级"
	var popup = c._create_base_popup("%s等级" % promo_name, Vector2(460, 620))
	popup.name = "PromoPopup"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	# 【改】2026-09-24 风姿/金兰改为小按钮置顶右上角（与升级区同排，靠右对齐）
	var top_bar = HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	top_bar.add_theme_constant_override("separation", 6)
	vb.add_child(top_bar)
	
	# ── 升级区（2026-09-24 改：模仿金兰光环卡布局——左列等级信息，右列消耗+晋升/十次按钮）──
	var up_row = HBoxContainer.new()
	up_row.add_theme_constant_override("separation", 16)
	vb.add_child(up_row)
	var up_left = VBoxContainer.new()
	up_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_left.alignment = BoxContainer.ALIGNMENT_CENTER   # 【改】与右列垂直居中对齐
	up_left.add_theme_constant_override("separation", 2)
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 【改】技能名参数化（李白=天生我材，白月初=仙缘梦绕）
	info_lbl.text = "%s %d级 +%d资质\n（下级+%d资质）" % [
		skill_name, int(promo.level), int(promo.level) * int(promo.aptitude_per_level),
		int(promo.aptitude_per_level)
	]
	up_left.add_child(info_lbl)
	up_row.add_child(up_left)
	var up_right = VBoxContainer.new()
	up_right.alignment = BoxContainer.ALIGNMENT_CENTER   # 【改】与左列垂直居中对齐
	up_right.add_theme_constant_override("separation", 2)
	var promo_have: int = data.items.get(promo.cost_item, 0)
	var promo_need: int = int(promo.cost_amount)
	# 【改】批次②③④-B9：消耗统一（拥有/消耗），道具名默认色、数字红绿
	c._add_cost_row(up_right, item_name, promo_have, promo_need)
	var up_box = HBoxContainer.new()
	up_box.alignment = BoxContainer.ALIGNMENT_CENTER
	up_right.add_child(up_box)
	up_row.add_child(up_right)
	var up_btn = Button.new()
	up_btn.custom_minimum_size = Vector2(130, 48)
	up_btn.pressed.connect(func():
		var before = promo.level
		on_promotion_upgrade("single" if not _promo_batch else "bulk")
		if promo.level > before:
			# 重建刷新（解锁列表高亮同步更新）
			if is_instance_valid(popup): popup.queue_free()
			_on_promo_btn_clicked()
	)
	up_box.add_child(up_btn)
	var batch_check = CheckBox.new()
	batch_check.text = "十次"
	batch_check.button_pressed = _promo_batch   # 恢复上次勾选状态
	# 【改】勾选切换刷新按钮文字（参数化：赋诗/赋诗十次、续缘/续缘十次）
	batch_check.toggled.connect(func(pressed):
		_promo_batch = pressed   # 记录勾选变化
		if _promo_batch:
			up_btn.text = "%s十次" % promo_name
		else:
			up_btn.text = promo_name
	)
	up_box.add_child(batch_check)
	if _promo_batch:
		up_btn.text = "%s十次" % promo_name
	else:
		up_btn.text = promo_name
	
	# 风姿按钮（无双解锁风姿的门客显示，点击切到风姿面板）
	var fengzi_btn = Button.new()
	fengzi_btn.custom_minimum_size = Vector2(64, 30)
	if data.fengzi_system.has_fengzi(hp.current_hero_id):
		fengzi_btn.text = "风姿"
	else:
		fengzi_btn.visible = false
	fengzi_btn.pressed.connect(func():
		if is_instance_valid(popup): popup.queue_free()   # 先关晋升面板再开风姿面板，避免弹窗堆叠
		hp.token._show_fengzi_panel()
	)
	top_bar.add_child(fengzi_btn)

	# 【新增】金兰按钮（花木兰，2026-09-24）：风姿按钮下方；晋升无双后解锁，未满灰显
	var jinlan_btn = Button.new()
	jinlan_btn.custom_minimum_size = Vector2(64, 30)
	if data.hero_system.get_jinlan_cfg(hp.current_hero_id).is_empty():
		jinlan_btn.visible = false
	elif data.hero_system.is_jinlan_unlocked(hp.current_hero_id):
		jinlan_btn.text = "金兰"
		jinlan_btn.pressed.connect(func():
			if is_instance_valid(popup): popup.queue_free()
			_show_jinlan_panel()
		)
	else:
		jinlan_btn.text = "金兰"
		jinlan_btn.disabled = true
	top_bar.add_child(jinlan_btn)

	# 【新增】亲和按钮（沉香，2026-09-25）：金兰按钮同款位；晋升无双（历练80级）后解锁，未满灰显
	var qinhe_btn = Button.new()
	qinhe_btn.custom_minimum_size = Vector2(64, 30)
	if data.hero_system.get_qinhe_cfg(hp.current_hero_id).is_empty():
		qinhe_btn.visible = false
	elif data.hero_system.is_qinhe_unlocked(hp.current_hero_id):
		qinhe_btn.text = "亲和"
		qinhe_btn.pressed.connect(func():
			if is_instance_valid(popup): popup.queue_free()
			_show_qinhe_panel()
		)
	else:
		qinhe_btn.text = "亲和"
		qinhe_btn.disabled = true
	top_bar.add_child(qinhe_btn)

	# 【新增】2026-09-24 拜师按钮：师徒光环门客（小八）晋升面板顶栏显示，点击选师傅
	if data.hero_system.get_master_aura_cfgs(hp.current_hero_id).size() > 0:
		var master_btn = Button.new()
		# 【改】2026-09-25 已拜师显示"易师"（可更换师傅），未拜师显示"拜师"（小八/小柒统一）
		master_btn.text = "易师" if data.hero_system.get_master_hero_id(hp.current_hero_id) != "" else "拜师"
		master_btn.custom_minimum_size = Vector2(64, 30)
		master_btn.add_theme_font_size_override("font_size", 13)
		master_btn.pressed.connect(_on_master_btn_clicked)
		top_bar.add_child(master_btn)

	# 【新增】苦情契约按钮：仅白月初显示（与风姿同位置，两者不会同时出现）
	var contract_btn = Button.new()
	contract_btn.custom_minimum_size = Vector2(64, 30)
	# 【新增】2026-09-25 天资按钮（heroes.json tianzi 配置驱动，现仅小柒）：与小柒活动玩法相关，本轮次挂起——点击提示后续版本开放
	if bool(h.get("tianzi", false)):
		var tianzi_btn = Button.new()
		tianzi_btn.text = "天资"
		tianzi_btn.custom_minimum_size = Vector2(64, 30)
		tianzi_btn.add_theme_font_size_override("font_size", 13)
		tianzi_btn.pressed.connect(func(): c._show_stage_hint("后续版本开放"))
		top_bar.add_child(tianzi_btn)
	if hp.current_hero_id == data.token_system.CONTRACT_HERO:
		contract_btn.text = "契约"   # 【改】2026-09-24 只显示"契约"
	else:
		contract_btn.visible = false
	contract_btn.pressed.connect(func():
		if is_instance_valid(popup): popup.queue_free()
		hp.token._show_contract_panel()
	)
	top_bar.add_child(contract_btn)
	
	# ── 晋升解锁列表：不写初始资质变化，统一"X级晋升XX，解锁技能【XX】"，已解锁金色、未解锁灰色 ──
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 220)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for tier in promo.tiers:
		var lv_req = int(tier.get("threshold", 0))
		var reached = promo.level >= lv_req
		# 同档内容合并：晋升品质和解锁技能都作为该档的后续片段，一行写完
		var parts = []
		if tier.has("quality"):
			parts.append("晋升%s" % HeroData.get_quality_name(int(tier.quality)))
		for ns in tier.get("new_skills", []):
			parts.append("解锁技能【%s】" % ns.get("name", "?"))
		if parts.is_empty():
			continue   # 该档无展示内容（如只调初始资质的档位）直接跳过
		var row = Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 【改】文案参数化："续缘5级晋升传奇，解锁技能【前世回忆】"
		row.text = "%s%d级%s" % [promo_name, lv_req, "，".join(parts)]
		if reached:
			row.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			row.add_theme_color_override("font_color", Color("#888888"))
		list.add_child(row)
	



# 【新增】服装一键晋升（解鲁/四郎）：点击直接升品质+送技能；晋升后本按钮由 update_hero_panel 按品质自动隐藏
# 条件未满足点击：弹数据驱动提示"收集N款服装晋升X"（2026-09-24 用户拍板）
func _on_simple_promote_clicked():
	# 【改】2026-09-24 简单晋升也开面板（解鲁/四郎/兰飞鸿/杨戬）：展示各档条件+解锁技能，面板内执行晋升
	_show_simple_promo_panel()


# 【新增】简单晋升面板（解鲁/四郎/兰飞鸿/杨戬）：只显示下一档条件+解锁技能，面板内执行晋升
func _simple_cond_text(hero_id: String, stage: Dictionary) -> String:
	if stage.has("cost_item"):
		var iid: String = stage.get("cost_item", "")
		var iname: String = data.ITEM_CONFIG.get(iid, {}).get("name", iid)
		return "%s×%d（拥有%d）" % [iname, int(stage.get("cost_amount", 0)), int(data.items.get(iid, 0))]
	var cond: Dictionary = stage.get("condition", {})
	match str(cond.get("type", "")):
		"costume_any":
			return "集齐任意%d件已解锁服装（已解锁%d件）" % [int(cond.get("count", 1)), data.hero_system.get_unlocked_costume_count(hero_id)]
		"costume_mix":
			return "集齐素装×%d+华服×%d（已解锁 素装%d/华服%d）" % [
				int(cond.get("suzhuang", 0)), int(cond.get("huafu", 0)),
				data.costume_system.get_unlocked_cos_count_by_q(hero_id, "素装"),
				data.costume_system.get_unlocked_cos_count_by_q(hero_id, "华服")]
	return "无条件"


func _show_simple_promo_panel():
	if not data.heroes.has(hp.current_hero_id): return
	var h: Dictionary = data.heroes[hp.current_hero_id]
	var sp_cfg: Dictionary = data.hero_system.get_simple_promotion_cfg(hp.current_hero_id)
	if sp_cfg.is_empty(): return
	# 档位归一：stages 形式原样；legacy 服装形式（解鲁/四郎）合成单档
	var stages: Array = sp_cfg.get("stages", [])
	if stages.is_empty():
		stages = [{"quality": int(sp_cfg.get("target_quality", 2)),
			"condition": {"type": "costume_any", "count": int(sp_cfg.get("costume_need", 1))},
			"skills": sp_cfg.get("skills", [])}]
	# 【改】2026-09-24 用户拍板：只显示下一个品质档（已解锁档不再显示）
	var cur_q: int = int(h.get("quality", 0))
	var q_names: Dictionary = {0: "优秀", 1: "卓越", 2: "传奇", 3: "无双"}
	var popup = c._create_base_popup("晋升", Vector2(460, 320))
	popup.name = "SimplePromoPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	for st in stages:
		if cur_q >= int(st.get("quality", 2)): continue
		var cond_lbl = Label.new()
		cond_lbl.add_theme_font_size_override("font_size", 15)
		cond_lbl.text = "晋升%s：%s" % [q_names.get(int(st.get("quality", 2)), "传奇"), _simple_cond_text(hp.current_hero_id, st)]
		# 【新增】批次②③④-B4：条件行按是否可晋升着色（够绿不够红；面板只显示下一档，与 can_simple_promote 同口径）
		cond_lbl.add_theme_color_override("font_color", Color("#7ee787") if data.hero_system.can_simple_promote(hp.current_hero_id) else Color("#ff6666"))
		vb.add_child(cond_lbl)
		for sk in st.get("skills", []):
			var sk_lbl = Label.new()
			sk_lbl.add_theme_font_size_override("font_size", 14)
			sk_lbl.text = "　解锁【%s】每级+%d资质" % [sk.get("name", ""), int(sk.get("aptitude_per_level", 3))]
			vb.add_child(sk_lbl)
		break   # 只显示下一档
	# 晋升钮：放大独占一行（置灰=条件未满足）
	var go_btn = Button.new()
	go_btn.text = "晋升"
	go_btn.custom_minimum_size = Vector2(240, 52)
	go_btn.add_theme_font_size_override("font_size", 20)
	go_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go_btn.disabled = not data.hero_system.can_simple_promote(hp.current_hero_id)
	go_btn.pressed.connect(func():
		var res: Dictionary = data.hero_system.do_simple_promote(hp.current_hero_id)
		if res.get("ok", false):
			hp.update_hero_panel()   # 品质/技能变化，门客面板对账
			c.update_all_ui()
			if is_instance_valid(popup): popup.queue_free()
			_show_simple_promo_panel()   # 重建显示下一档
	)
	vb.add_child(go_btn)


func _show_jinlan_panel():
	var hs = data.hero_system
	var popup = c._create_base_popup("金兰", Vector2(560, 560))
	c.add_child(popup)
	var vb = popup.get_child(0)
	var st = hs.get_jinlan_state(hp.current_hero_id)
	var partner_id: String = str(st.get("partner", ""))

	# ── 说明行 ──
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_color_override("font_color", Color("#d4af37"))
	info_lbl.text = "花木兰的风姿属性100%附加给金兰门客"
	vb.add_child(info_lbl)

	# ── 金兰双方行：左花木兰（风姿属性值）/ 右金兰门客（实时获得加成，含光环）──
	var attr: Dictionary = hs.get_fengzi_attr(hp.current_hero_id)
	var duo = HBoxContainer.new()
	duo.alignment = BoxContainer.ALIGNMENT_CENTER
	duo.add_theme_constant_override("separation", 60)
	vb.add_child(duo)
	var left_lbl = Label.new()
	left_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_lbl.text = "花木兰\n风姿资质 +%d\n赚钱 +%d%%" % [int(attr.get("aptitude", 0)), int(float(attr.get("income_pct", 0.0)) * 100)]
	duo.add_child(left_lbl)
	var right_lbl = Label.new()
	right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if partner_id != "" and data.heroes.has(partner_id):
		right_lbl.add_theme_color_override("font_color", Color("#7ee787"))
		right_lbl.text = "%s\n资质: +%d\n赚钱: +%d%%" % [
			str(data.heroes[partner_id].get("name", partner_id)),
			hs.get_jinlan_partner_aptitude(partner_id),
			int(hs.get_jinlan_partner_income_pct(partner_id) * 100)   # getter 返回小数，显示转%
		]
	else:
		right_lbl.add_theme_color_override("font_color", Color("#888888"))
		right_lbl.text = "金兰门客\n未选择\n "
	duo.add_child(right_lbl)

	# ── 选择/更换/解除（无冷却，随时可换——2026-09-24 用户拍板）──
	var op_row = HBoxContainer.new()
	op_row.alignment = BoxContainer.ALIGNMENT_CENTER
	op_row.add_theme_constant_override("separation", 20)
	vb.add_child(op_row)
	var pick_btn = Button.new()
	pick_btn.text = "更换门客" if partner_id != "" else "选择门客"
	pick_btn.pressed.connect(func():
		if is_instance_valid(popup): popup.queue_free()
		_show_jinlan_pick_popup()
	)
	op_row.add_child(pick_btn)
	if partner_id != "":
		var clear_btn = Button.new()
		clear_btn.text = "解除金兰"
		clear_btn.pressed.connect(func():
			hs.clear_jinlan_partner(hp.current_hero_id)
			if is_instance_valid(popup): popup.queue_free()
			_show_jinlan_panel()
			hp.update_hero_panel()
			c.update_all_ui()
		)
		op_row.add_child(clear_btn)

	# ── 金兰光环 ──
	var halo_lbl = Label.new()
	halo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	halo_lbl.add_theme_color_override("font_color", Color("#d4af37"))
	halo_lbl.text = "金兰光环"
	vb.add_child(halo_lbl)
	var fz_lv: int = data.fengzi_system.get_level(hp.current_hero_id)   # 【修】风姿等级走 fengzi_system getter
	var cap: int = hs.get_jinlan_cap(hp.current_hero_id)
	var per4: int = max(1, int(hs.get_jinlan_cfg(hp.current_hero_id).get("fengzi_per_level", 4)))
	for sk in hs.get_jinlan_cfg(hp.current_hero_id).get("skills", []):
		var sk_name: String = str(sk.get("name", ""))
		var lv: int = int(st.get("levels", {}).get(sk_name, 0))
		var per: int = int(sk.get("self_income_pct", sk.get("both_aptitude", sk.get("both_income_pct", 0))))
		var desc_t: String = str(sk.get("desc", "+%d"))
		# 下级预览只写数值：赚钱类 +N%%，资质类 +N（2026-09-24 用户拍板，不重复效果名）
		var next_val: String = ("+%d%%" % ((lv + 1) * per)) if sk.has("both_aptitude") == false else ("+%d" % ((lv + 1) * per))
		# 升下级所需风姿等级 = (lv+1) × fengzi_per_level；当前风姿等级 >= 所需→绿，否则红
		var req: int = (lv + 1) * per4
		var card = HBoxContainer.new()
		card.add_theme_constant_override("separation", 16)
		# 左列两行：第一行技能名称+等级，第二行当前数值+下级数值（左列拉伸把右列顶到最右）
		var left_v = VBoxContainer.new()
		left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_v.add_theme_constant_override("separation", 2)
		var line1 = Label.new()
		line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		line1.text = "【%s】%d级" % [sk_name, lv]
		left_v.add_child(line1)
		var line2 = Label.new()
		line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		line2.add_theme_color_override("font_color", Color("#888888"))
		line2.text = "%s（下级：%s）" % [desc_t % (lv * per), next_val]
		left_v.add_child(line2)
		card.add_child(left_v)
		var right_v = VBoxContainer.new()
		right_v.add_theme_constant_override("separation", 2)
		# 【改】批次②③④-B9：门槛进度统一（当前/需求）格式，保留达到/未达到红绿提示
		c._add_cost_row(right_v, "【红妆缭乱】", int(fz_lv), int(req))
		var up_btn = Button.new()
		up_btn.text = "升级"
		up_btn.disabled = lv >= cap
		var captured: String = sk_name
		up_btn.pressed.connect(func():
			if hs.upgrade_jinlan_skill(hp.current_hero_id, captured).get("ok", false):
				if is_instance_valid(popup): popup.queue_free()
				_show_jinlan_panel()
				hp.update_hero_panel()
				c.update_all_ui()
		)
		right_v.add_child(up_btn)
		card.add_child(right_v)
		vb.add_child(card)
	
	var close_btn = Button.new()
	close_btn.text = "返回"   # 【改】2026-09-24 返回晋升页面
	close_btn.pressed.connect(func():
		popup.queue_free()
		_on_promo_btn_clicked()
	)
	vb.add_child(close_btn)


# 【新增】金兰门客选择弹窗（已拥有门客列表，排除自身，可重复选/无冷却——2026-09-24 用户拍板）
func _show_jinlan_pick_popup():
	var hs = data.hero_system
	var popup = c._create_base_popup("选择金兰门客", Vector2(460, 520))
	c.add_child(popup)
	var vb = popup.get_child(0)
	var st = hs.get_jinlan_state(hp.current_hero_id)
	var cur: String = str(st.get("partner", ""))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 360)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for hid in data.heroes.keys():
		if hid == hp.current_hero_id: continue
		var is_cur: bool = cur == hid
		var pb = Button.new()
		pb.text = ("● " if is_cur else "") + str(data.heroes[hid].get("name", hid)) + ("（当前）" if is_cur else "")
		var captured: String = hid
		pb.pressed.connect(func():
			if hs.set_jinlan_partner(hp.current_hero_id, captured).get("ok", false):
				if is_instance_valid(popup): popup.queue_free()
				_show_jinlan_panel()
				hp.update_hero_panel()
				c.update_all_ui()
		)
		list.add_child(pb)
	var close_btn = Button.new()
	close_btn.text = "返回"   # 返回金兰面板
	close_btn.pressed.connect(func():
		popup.queue_free()
		_show_jinlan_panel()
	)
	vb.add_child(close_btn)


# 【新增】亲和面板（沉香，2026-09-25）：光环①动物亲和（转化比例）+ 光环②珍兽亲和（转移数值，无独立等级）
func _show_qinhe_panel():
	var hs = data.hero_system
	var popup = c._create_base_popup("亲和", Vector2(560, 560))
	c.add_child(popup)
	var vb = popup.get_child(0)
	var st = hs.get_qinhe_state(hp.current_hero_id)
	var partner_id: String = str(st.get("partner", ""))
	var aura_lv: int = int(st.get("aura_level", 1))
	var cfg: Dictionary = hs.get_qinhe_cfg(hp.current_hero_id)
	var ratio_base_pct: int = int(float(cfg.get("ratio_base", 0.4)) * 100)
	var ratio_pct: int = aura_lv * ratio_base_pct
	var contrib: int = HeroData.get_beast_income_contribution(data, hp.current_hero_id)

	# ── 说明行 ──
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_color_override("font_color", Color("#d4af37"))
	info_lbl.text = "沉香装备珍兽提升的赚钱，按转化比例加成给亲和门客"
	vb.add_child(info_lbl)

	# ── 亲和双方行：左沉香（珍兽贡献/转化比例）/ 右亲和门客（实时获得数值）──
	var duo = HBoxContainer.new()
	duo.alignment = BoxContainer.ALIGNMENT_CENTER
	duo.add_theme_constant_override("separation", 60)
	vb.add_child(duo)
	var left_lbl = Label.new()
	left_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_lbl.text = "沉香\n珍兽贡献 +%s/秒\n转化比例 %d%%" % [c.format_number(contrib), ratio_pct]
	duo.add_child(left_lbl)
	var right_lbl = Label.new()
	right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if partner_id != "" and data.heroes.has(partner_id):
		right_lbl.add_theme_color_override("font_color", Color("#7ee787"))
		right_lbl.text = "%s\n赚钱: +%s/秒" % [
			str(data.heroes[partner_id].get("name", partner_id)),
			c.format_number(hs.get_qinhe_income_bonus(partner_id))
		]
	else:
		right_lbl.add_theme_color_override("font_color", Color("#888888"))
		right_lbl.text = "亲和门客\n未选择\n "
	duo.add_child(right_lbl)

	# ── 选择/更换/解除（无冷却，随时可换——照金兰）──
	var op_row = HBoxContainer.new()
	op_row.alignment = BoxContainer.ALIGNMENT_CENTER
	op_row.add_theme_constant_override("separation", 20)
	vb.add_child(op_row)
	var pick_btn = Button.new()
	pick_btn.text = "更换门客" if partner_id != "" else "选择门客"
	pick_btn.pressed.connect(func():
		if is_instance_valid(popup): popup.queue_free()
		_show_qinhe_pick_popup()
	)
	op_row.add_child(pick_btn)
	if partner_id != "":
		var clear_btn = Button.new()
		clear_btn.text = "解除亲和"
		clear_btn.pressed.connect(func():
			hs.clear_qinhe_partner(hp.current_hero_id)
			if is_instance_valid(popup): popup.queue_free()
			_show_qinhe_panel()
			hp.update_hero_panel()
			c.update_all_ui()
		)
		op_row.add_child(clear_btn)

	# ── 亲和光环 ──
	var halo_lbl = Label.new()
	halo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	halo_lbl.add_theme_color_override("font_color", Color("#d4af37"))
	halo_lbl.text = "亲和光环"
	vb.add_child(halo_lbl)

	# 光环①动物亲和：只定义转化比例（对沉香自身无独立效果）；无消耗手动升级
	# 等级上限 = 1 + floor((开山斧决等级-80)/10)；升下一级需开山斧决 80+10×当前等级
	var cap: int = hs.get_qinhe_aura_cap(hp.current_hero_id)
	var req: int = 80 + 10 * aura_lv
	var promo_lv: int = int(data.heroes[hp.current_hero_id].get("promotion", {}).get("level", 0))
	var card1 = HBoxContainer.new()
	card1.add_theme_constant_override("separation", 16)
	var left_v = VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 2)
	var line1 = Label.new()
	line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line1.text = "【%s】%d级" % [str(cfg.get("aura_name", "动物亲和")), aura_lv]
	left_v.add_child(line1)
	var line2 = Label.new()
	line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line2.add_theme_color_override("font_color", Color("#888888"))
	line2.text = "转化比例 %d%%（下级：%d%%）" % [ratio_pct, (aura_lv + 1) * ratio_base_pct]
	left_v.add_child(line2)
	card1.add_child(left_v)
	var right_v = VBoxContainer.new()
	right_v.add_theme_constant_override("separation", 2)
	# 【改】批次②③④-B9：门槛进度统一（当前/需求）格式，保留达到/未达到红绿提示
	c._add_cost_row(right_v, "【开山斧决】", int(promo_lv), int(req))
	var up_btn = Button.new()
	up_btn.text = "升级"
	up_btn.disabled = aura_lv >= cap
	up_btn.pressed.connect(func():
		if hs.upgrade_qinhe_aura(hp.current_hero_id).get("ok", false):
			if is_instance_valid(popup): popup.queue_free()
			_show_qinhe_panel()
			hp.update_hero_panel()
			c.update_all_ui()
	)
	right_v.add_child(up_btn)
	card1.add_child(right_v)
	vb.add_child(card1)

	# 光环②珍兽亲和：效果承接光环①比例，自身无等级（两个合起来是一个光环——2026-09-25 用户拍板）
	var card2 = HBoxContainer.new()
	card2.add_theme_constant_override("separation", 16)
	var left2 = VBoxContainer.new()
	left2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left2.add_theme_constant_override("separation", 2)
	var l21 = Label.new()
	l21.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l21.text = "【%s】" % str(cfg.get("aura2_name", "珍兽亲和"))
	left2.add_child(l21)
	var l22 = Label.new()
	l22.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l22.add_theme_color_override("font_color", Color("#888888"))
	if partner_id != "":
		l22.text = "亲和门客获得珍兽贡献的%d%%（当前 +%s/秒）" % [ratio_pct, c.format_number(hs.get_qinhe_income_bonus(partner_id))]
	else:
		l22.text = "选择亲和门客后，其获得珍兽贡献的%d%%" % ratio_pct
	left2.add_child(l22)
	card2.add_child(left2)
	vb.add_child(card2)

	var close_btn = Button.new()
	close_btn.text = "返回"   # 【改】返回晋升页面
	close_btn.pressed.connect(func():
		popup.queue_free()
		_on_promo_btn_clicked()
	)
	vb.add_child(close_btn)


# 【新增】亲和门客选择弹窗（已拥有门客列表，排除自身，可重复选/无冷却——照金兰）
func _show_qinhe_pick_popup():
	var hs = data.hero_system
	var popup = c._create_base_popup("选择亲和门客", Vector2(460, 520))
	c.add_child(popup)
	var vb = popup.get_child(0)
	var st = hs.get_qinhe_state(hp.current_hero_id)
	var cur: String = str(st.get("partner", ""))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 360)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for hid in data.heroes.keys():
		if hid == hp.current_hero_id: continue
		var is_cur: bool = cur == hid
		var pb = Button.new()
		pb.text = ("● " if is_cur else "") + str(data.heroes[hid].get("name", hid)) + ("（当前）" if is_cur else "")
		var captured: String = hid
		pb.pressed.connect(func():
			if hs.set_qinhe_partner(hp.current_hero_id, captured).get("ok", false):
				if is_instance_valid(popup): popup.queue_free()
				_show_qinhe_panel()
				hp.update_hero_panel()
				c.update_all_ui()
		)
		list.add_child(pb)
	var close_btn = Button.new()
	close_btn.text = "返回"   # 返回亲和面板
	close_btn.pressed.connect(func():
		popup.queue_free()
		_show_qinhe_panel()
	)
	vb.add_child(close_btn)


# 【新增】2026-09-24 拜师：选择已拥有门客作为师傅（可更换；广结良缘按师傅职业实时切换）
func _on_master_btn_clicked():
	_show_master_selector()


func _show_master_selector():
	if not data.heroes.has(hp.current_hero_id): return
	c._safe_close("MasterSelector")
	var cur_master: String = data.hero_system.get_master_hero_id(hp.current_hero_id)
	var title := "选择师傅"
	if cur_master != "" and data.heroes.has(cur_master):
		title = "选择师傅（当前：%s）" % str(data.heroes[cur_master].get("name", cur_master))
	var popup = c._create_base_popup(title, Vector2(360, 380))
	popup.name = "MasterSelector"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	# 已拥有门客列表（排除自己），按品质→赚速排序，与门客页排序口径一致
	var ids: Array = data.heroes.keys()
	ids.sort_custom(func(a, b):
		var ha: Dictionary = data.heroes[a]
		var hb: Dictionary = data.heroes[b]
		if int(ha.get("quality", 0)) != int(hb.get("quality", 0)):
			return int(ha.get("quality", 0)) > int(hb.get("quality", 0))
		return data.get_hero_income(a) > data.get_hero_income(b))
	# 【新增】2026-09-25 拜师池限定（小柒 master_pool="wuyan"）：候选只列秦淮五艳
	var pool_wuyan: bool = str(data.talent_system.get_hero_talent_cfg(hp.current_hero_id).get("master_pool", "")) == "wuyan"
	for hid in ids:
		if hid == hp.current_hero_id: continue
		if pool_wuyan and not data.hero_system.is_wuyan(hid): continue
		var h: Dictionary = data.heroes[hid]
		var b := Button.new()
		b.text = "%s（%s）" % [str(h.get("name", hid)), _quality_name(int(h.get("quality", 0)))]
		if hid == cur_master:
			b.text = "【师傅】" + b.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			var res: Dictionary = data.hero_system.set_master_hero_id(hp.current_hero_id, hid)
			c._safe_close("MasterSelector")
			if res.get("ok", false):
				c._show_stage_hint("已拜师 %s" % str(data.heroes[hid].get("name", hid)))
			else:
				c._show_stage_hint(res.get("msg", "拜师失败"))
			hp.update_hero_panel()   # 师傅变化影响师徒光环效果显示
			c.update_all_ui()
		)
		vb.add_child(b)


func _get_copy_talent_info(hero_id: String) -> Dictionary:
	var ts = data.talent_system
	var cfg = ts.get_hero_talent_cfg(hero_id)
	var cur_tier = ts.get_current_tier(hero_id)
	if cfg.is_empty() or cur_tier == "":
		return {}
	for t in cfg.get("tiers", {}).get(cur_tier, []):
		if str(t.get("kind", "")) == "copy_max_level":
			return {"name": str(t.get("name", "")), "desc": ts.get_effect_desc(t, hero_id)}
	return {}


# 【新增】复制档天赋详情弹窗：升级位天赋名按钮点击（2026-09-24 用户拍板）
func _on_copy_talent_btn_clicked():
	var ct = _get_copy_talent_info(hp.current_hero_id)
	if ct.is_empty():
		c._show_stage_hint("未找到天赋信息")   # 【新增】批次②③④-B4：空信息反馈
		return
	var popup = c._create_base_popup(ct.get("name", "天赋"), Vector2(460, 260))
	c.add_child(popup)   # 【修】panel 需自行入树（helper 只挂遮罩），否则只有遮罩无窗体
	var vb = popup.get_child(0)   # 【修】内容挂到面板自带的内容容器（PanelContainer 只排布首个子节点）
	var desc_lbl = Label.new()
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color("#7ee787"))
	desc_lbl.text = ct.get("desc", "")
	vb.add_child(desc_lbl)


# ============ 凤魁（秦淮五艳晋升，2026-09-25） ============

# 凤魁按钮：已是凤魁→打开凤魁页面；未选定（五艳全传奇）→确认弹窗选定
func _on_fengkui_btn_clicked():
	if hp.current_hero_id == "" or not data.heroes.has(hp.current_hero_id): return
	if data.hero_system.get_fengkui_id() == hp.current_hero_id:
		_show_fengkui_panel(_fengkui_tab)
		return
	if not data.hero_system.can_choose_fengkui(hp.current_hero_id): return
	c._safe_close("FengkuiConfirmPopup")
	var popup = c._create_base_popup("选定凤魁", Vector2(440, 220), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
	popup.name = "FengkuiConfirmPopup"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "是否确定选择【%s】作为凤魁？\n（凤魁获得金凤玲珑信物与凤临乐宴晋升，其余五艳保持传奇）" % data.heroes[hp.current_hero_id].get("name", "")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(func(): c._safe_close("FengkuiConfirmPopup"))
	row.add_child(cancel)
	var ok = Button.new()
	ok.text = "确定"
	ok.custom_minimum_size = Vector2(120, 40)
	ok.pressed.connect(_on_fengkui_confirmed)
	row.add_child(ok)


func _on_fengkui_confirmed():
	c._safe_close("FengkuiConfirmPopup")
	var res = data.hero_system.choose_fengkui(hp.current_hero_id)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "选定失败"), 2.0)
		return
	c._show_stage_hint("【%s】已成为凤魁！" % data.heroes[hp.current_hero_id].get("name", ""), 2.5)
	hp.update_hero_panel()


# 凤魁页面：凤魁技能（凤临乐宴+解锁技能）/ 山河五岳（五艳服装集中）两页签
# 凤魁页面：凤魁技能（凤临乐宴+解锁技能）/ 山河五岳（五艳已解锁服装集中）两页签；
# 页签置底、样式照面板技能栏（技能/副业/服装/光环），选中金字高亮（2026-09-25 布局改版：照晋升弹窗+页签置底）
func _show_fengkui_panel(tab_id: String = "skill"):
	_fengkui_tab = tab_id
	if data.hero_system.get_fengkui_id() != hp.current_hero_id: return
	if c.has_node("FengkuiPanel"):
		var old = c.get_node("FengkuiPanel")
		c.remove_child(old)
		old.queue_free()
	var popup = c._create_base_popup("【凤魁】%s" % data.heroes[hp.current_hero_id].get("name", ""), Vector2(560, 640))
	popup.name = "FengkuiPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	# 转移按钮（置顶右上角，位置同其他晋升页面的风姿按钮 64×30）
	var fk_top_bar = HBoxContainer.new()
	fk_top_bar.alignment = BoxContainer.ALIGNMENT_END
	fk_top_bar.add_theme_constant_override("separation", 6)
	vb.add_child(fk_top_bar)
	var transfer_btn = Button.new()
	transfer_btn.text = "转移"
	transfer_btn.custom_minimum_size = Vector2(64, 30)
	transfer_btn.pressed.connect(_on_fengkui_transfer_clicked)
	fk_top_bar.add_child(transfer_btn)
	if tab_id == "skill":
		_fill_fengkui_skill_tab(vb)
	else:
		_fill_fengkui_wuyue_tab(vb)
	# 页签栏置底（照技能栏 TabSkill 格式：110×36、separation 8、meta tab_id 金字高亮）
	var tab_bar = HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 8)
	vb.add_child(tab_bar)
	for t in [["skill", "凤魁技能"], ["wuyue", "山河五岳"]]:
		var tbtn = Button.new()
		tbtn.text = t[1]
		tbtn.custom_minimum_size = Vector2(110, 36)
		tbtn.set_meta("tab_id", t[0])
		tbtn.pressed.connect(_on_fengkui_tab_clicked.bind(t[0]))
		tab_bar.add_child(tbtn)
	for tab_btn in tab_bar.get_children():
		if tab_btn.get_meta("tab_id", "") == tab_id:
			tab_btn.add_theme_color_override("font_color", Color("#ffd700"))

func _on_fengkui_tab_clicked(tab_id: String):
	_show_fengkui_panel(tab_id)


# 凤临乐宴升级回调：batch=false 升1级 / true 升10级（凤临十次）
func _on_fengkui_upgrade(batch: bool):
	if data.hero_system.upgrade_fengkui(hp.current_hero_id, batch) > 0:
		_show_fengkui_panel("skill")
		hp.update_hero_panel()
	else:
		# 【新增】批次②③④-B4：失败反馈（凤临乐宴耗对应道具，道具名读配置）
		var fk_cfg: Dictionary = data.heroes[hp.current_hero_id].get("fengkui", {})
		var iname: String = str(data.ITEM_CONFIG.get(str(fk_cfg.get("cost_item", "")), {}).get("name", "凤游宴图"))
		c._show_stage_hint("%s不足" % iname)


func _on_fengkui_skill_upgrade(mode: String):
	var sname = _get_fengkui_sel_skill()
	if sname == "": return
	var res = data.hero_system.upgrade_fengkui_skill(hp.current_hero_id, sname, mode, hp._use_baiye)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "升级失败"), 2.0)
		return
	_show_fengkui_panel("skill")
	hp.update_hero_panel()

func _fill_fengkui_skill_tab(vb):
	var promo = data.heroes[hp.current_hero_id].get("fengkui", {})
	var lv = int(promo.get("level", 0))
	var max_lv = int(promo.get("max_level", 80))
	var per = int(promo.get("aptitude_per_level", 6))
	# 上行：左=凤临乐宴信息，右=消耗+升级钮（赋诗式）
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 40)
	vb.add_child(top)
	var left = VBoxContainer.new()
	top.add_child(left)
	var title = Label.new()
	title.text = "凤临乐宴  Lv.%d/%d（每级资质+%d）" % [lv, max_lv, per]
	left.add_child(title)
	var apt_lbl = Label.new()
	apt_lbl.text = "资质+%d（下级+%d）" % [lv * per, (lv + 1) * per]
	left.add_child(apt_lbl)
	var right = VBoxContainer.new()
	top.add_child(right)
	var cost: int = int(promo.get("cost_amount", 600))
	var have: int = int(data.items.get(str(promo.get("cost_item", "")), 0))
	# 【改】批次②③④-B9：消耗统一（拥有/消耗），道具名默认色、数字红绿
	c._add_cost_row(right, "凤游宴图", have, cost)
	var btns = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	right.add_child(btns)
	var up1 = Button.new()
	up1.text = "升级"
	up1.pressed.connect(_on_fengkui_upgrade.bind(false))
	btns.add_child(up1)
	var up10 = Button.new()
	up10.text = "凤临十次"
	up10.pressed.connect(_on_fengkui_upgrade.bind(true))
	btns.add_child(up10)
	# 【改】2026-09-25 解锁信息不再逐行展示：点击技能卡片后在技能栏详情区显示（未解锁=纯展示条目"凤临乐宴X级解锁"，解锁后=升级信息），见 _fengkui_skill_items
	vb.add_child(HSeparator.new())
	# 解锁技能区：复用技能栏渲染件（_render_skill_tab=满级沉底+卡片行+详情区，tab_id 独立记忆选中）
	hp._render_skill_tab(vb, _fengkui_skill_items(), "fengkui_skill")


# 凤魁解锁技能条目构建（供渲染与选中解析共用；未解锁=纯展示条目 no_action）
func _fengkui_skill_items() -> Array:
	var items: Array = []
	var promo = data.heroes[hp.current_hero_id].get("fengkui", {})
	for sk in promo.get("unlock_skills", []):
		var sname: String = sk.get("name", "")
		var stars: int = int(sk.get("stars", 3))
		if not promo.get("skills", {}).has(sname):
			# 未解锁：卡片可点看说明，右侧无操作
			items.append({"name": sname, "stars": stars, "is_max": false, "no_action": true,
				"info": "【%s】\n凤临乐宴%d级解锁" % [sname, int(sk.get("threshold", 0))]})
			continue
		var slv: int = int(promo["skills"][sname])
		var smax: int = int(sk.get("max_level", 200))
		var is_max: bool = slv >= smax
		var info: String = "【%s】  Lv.%d/%d\n资质+%d" % [sname, slv, smax, slv * stars]
		if is_max:
			info += "（已满级）"
		else:
			info += "（下级+%d）" % [(slv + 1) * stars]
		items.append({"name": sname, "stars": stars, "is_max": is_max, "info": info,
			"pill": stars,
			"on_single": _on_fengkui_skill_upgrade.bind("single"),
			"on_bulk": _on_fengkui_skill_upgrade.bind("bulk")})
	return items


# 技能栏当前选中技能名（hp._sel_idx["fengkui_skill"] 索引回退解析）
func _get_fengkui_sel_skill() -> String:
	var items = _fengkui_skill_items()
	if items.is_empty(): return ""
	var sel: int = clampi(int(hp._sel_idx.get("fengkui_skill", 0)), 0, items.size() - 1)
	return items[sel].get("name", "")

# 山河五岳页：已解锁的五艳服装集中于此（未解锁不出现，兑换/解锁走服装图鉴页），
# 布局=复用技能栏渲染件（与门客服装页签同一套：卡片行+双货币详情区），底部资质合计计入凤魁
func _fill_fengkui_wuyue_tab(vb):
	var cs = data.costume_system
	var items: Array = []
	for it in data.hero_system.get_wuyue_cos_items():
		if not it.get("unlocked", false): continue
		var base: int = int(it.get("base", 1))
		var max_lv: int = int(cs._settings().get("skill_max_level", 200))
		var per: int = int(it.get("pill_cost", 2))
		var is_max: bool = base >= max_lv
		var info: String = "【%s】%s（属主：%s）  Lv.%d/%d\n资质+%d" % [it.get("quality", ""), it.get("name", ""), it.get("owner_name", ""), base, max_lv, base * per]
		if is_max:
			info += "（已满级）"
		else:
			info += "（下级+%d）" % [(base + 1) * per]
		items.append({"name": it.get("name", ""), "stars": per, "is_max": is_max, "info": info,
			"pill": per,
			"on_single": _on_wuyue_cos_skill.bind(it.get("owner", ""), it.get("cos_id", ""), "single"),
			"on_bulk": _on_wuyue_cos_skill.bind(it.get("owner", ""), it.get("cos_id", ""), "bulk")})
	if items.is_empty():
		var lbl = Label.new()
		lbl.text = "暂未解锁山河五岳服装（在服装图鉴页兑换解锁）"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lbl)
	else:
		hp._render_skill_tab(vb, items, "fengkui_wuyue")
	# 底部：资质合计计入凤魁 + 光环归属说明
	var total_lbl = Label.new()
	total_lbl.text = "资质合计：+%d（计入凤魁【%s】）" % [data.hero_system.get_wuyue_aptitude(hp.current_hero_id), data.heroes[hp.current_hero_id].get("name", "")]
	total_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(total_lbl)
	var note = Label.new()
	note.text = "服装光环仍在各属门客的光环页签升级生效"
	note.add_theme_font_size_override("font_size", 12)
	vb.add_child(note)

func _on_wuyue_cos_skill(owner: String, cos_id: String, mode: String):
	var res = data.costume_system.upgrade_cos_skill(owner, cos_id, mode, hp._use_baiye)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "升级失败"), 2.0)
		return
	_show_fengkui_panel("wuyue")
	hp.update_hero_panel()


# ============ 凤魁转移（2026-09-25） ============

# 转移按钮：弹出其余四艳选择列表（hero_system.transfer_fengkui 执行搬迁）
func _on_fengkui_transfer_clicked():
	c._safe_close("FengkuiTransferPopup")
	var popup = c._create_base_popup("凤魁转移", Vector2(380, 320))
	popup.name = "FengkuiTransferPopup"
	popup.z_index = 35
	c.add_child(popup)
	var vb = popup.get_child(0)
	var tip = Label.new()
	tip.text = "选择新的凤魁：\n信物/凤临乐宴等级/解锁技能等级/绑定一并转移，原门客退回传奇"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tip)
	for hid in data.hero_system.get_wuyan_heroes():
		if hid == hp.current_hero_id or not data.heroes.has(hid): continue
		var h = data.heroes[hid]
		var b = Button.new()
		b.text = "%s（%s）" % [h.get("name", ""), HeroData.get_quality_name(int(h.get("quality", 2)))]
		b.pressed.connect(_on_fengkui_transfer_target.bind(hid))
		vb.add_child(b)


func _on_fengkui_transfer_target(hid: String):
	c._safe_close("FengkuiTransferPopup")
	c._safe_close("FengkuiTransferConfirm")
	var popup = c._create_base_popup("确认转移", Vector2(420, 200), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
	popup.name = "FengkuiTransferConfirm"
	popup.z_index = 36
	c.add_child(popup)
	var vb = popup.get_child(0)
	var lbl = Label.new()
	lbl.text = "是否确定将凤魁转移给【%s】？\n（信物/凤临乐宴/技能等级/绑定一并转移，原门客退回传奇）" % data.heroes[hid].get("name", "")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(func(): c._safe_close("FengkuiTransferConfirm"))
	row.add_child(cancel)
	var ok = Button.new()
	ok.text = "确定"
	ok.custom_minimum_size = Vector2(120, 40)
	ok.pressed.connect(_on_fengkui_transfer_confirmed.bind(hid))
	row.add_child(ok)


func _on_fengkui_transfer_confirmed(hid: String):
	c._safe_close("FengkuiTransferConfirm")
	var res = data.hero_system.transfer_fengkui(hid)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "转移失败"), 2.0)
		return
	c._show_stage_hint("凤魁已转移给【%s】！" % data.heroes[hid].get("name", ""), 2.5)
	# 原门客不再是凤魁：关闭凤魁页面，面板刷新（凤魁钮/信物随之消失）
	if c.has_node("FengkuiPanel"):
		var old = c.get_node("FengkuiPanel")
		c.remove_child(old)
		old.queue_free()
	hp.update_hero_panel()

# 【新增】2026-09-24 师徒光环卡片（小八）：道具消耗型走 own 消耗协议；门槛型走 free_action 无消耗升级
func _build_master_aura_card(aura: Dictionary) -> Dictionary:
	var aid: String = aura.get("id", "")
	var lv: int = data.hero_system.get_master_aura_level(hp.current_hero_id, aid)
	var cap: int = data.hero_system.get_master_aura_cap(hp.current_hero_id, aura)
	var per: float = float(aura.get("per", 0))
	var is_apt: bool = aura.get("type", "") == "aptitude"
	# 【改】2026-09-24 按卡片规范显示"当前总数值（下级+下级数值）"，原静态每级值不随等级涨（用户实测抓包）
	var unit: String
	if is_apt:
		unit = "资质+%d（下级+%d）" % [int(per) * lv, int(per) * (lv + 1)]
	else:
		unit = "赚钱+%.1f%%（下级+%.1f%%）" % [per * lv, per * (lv + 1)]
	var scope := "自身"
	if aura.get("target", "") == "self_master": scope = "自身与师傅"
	elif aura.get("target", "") == "master_career": scope = "师傅职业门客"
	var cap_txt: String = str(cap) if cap < 9000 else "—"
	var info: String = "【%s】 Lv.%d/%s\n%s（%s）" % [aura.get("name", ""), lv, cap_txt, unit, scope]
	var card := {"name": aura.get("name", ""), "stars": int(per), "is_max": lv >= cap, "info": info}
	if aura.has("cost_item"):
		var cost: int = data.hero_system.get_master_aura_cost(hp.current_hero_id, aura)
		var iid: String = aura.get("cost_item", "")
		var iname: String = data.ITEM_CONFIG.get(iid, {}).get("name", iid)
		card["own_name"] = iname
		card["own"] = [cost, int(data.items.get(iid, 0))]
		card["on_single"] = func(): _on_master_aura_up(aid, 1)
		card["on_bulk"] = func(): _on_master_aura_up(aid, 10)
	else:
		# 门槛型（财商通达每10级可升1级）：无道具消耗，free_action 分支渲染单个升级钮
		info += "\n财商通达每10级可升1级"
		card["info"] = info
		card["free_action"] = true
		card["on_single"] = func(): _on_master_aura_up(aid, 1)
	return card


func _on_master_aura_up(aura_id: String, times: int):
	var res: Dictionary = data.hero_system.upgrade_master_aura(hp.current_hero_id, aura_id, times)
	c._show_stage_hint("【%s】升至 %d 级" % [_aura_name(aura_id), res.get("level", 0)] if res.get("ok", false) else res.get("msg", "升级失败"))
	hp.update_hero_panel()   # 光环变化影响资质/赚钱，整面板对账
	c.update_all_ui()


func _aura_name(aura_id: String) -> String:
	for a in data.hero_system.get_master_aura_cfgs(hp.current_hero_id):
		if a.get("id", "") == aura_id: return str(a.get("name", aura_id))
	return aura_id


# 【新增】2026-09-24 双人光环卡片（小舞）：道具消耗型，走 own 消耗协议（升级/十连）；无上限显示 "—"
func _build_pair_aura_card(aura: Dictionary) -> Dictionary:
	var aid: String = aura.get("id", "")
	var lv: int = data.hero_system.get_pair_aura_level(hp.current_hero_id, aid)
	var per: float = float(aura.get("per", 0))
	var is_apt: bool = aura.get("type", "") == "aptitude"
	# 【改】2026-09-24 按卡片规范显示"当前总数值（下级+下级数值）"（同师徒光环卡修复）
	var unit: String
	if is_apt:
		unit = "资质+%d（下级+%d）" % [int(per) * lv, int(per) * (lv + 1)]
	else:
		unit = "赚钱+%.1f%%（下级+%.1f%%）" % [per * lv, per * (lv + 1)]
	var partner_id: String = str(aura.get("partner", ""))
	var partner_name: String = data.get_hero_config(partner_id).get("name", partner_id)
	var info: String = "【%s】 Lv.%d/—\n%s（自身与%s）" % [aura.get("name", ""), lv, unit, partner_name]
	var cost: int = data.hero_system.get_pair_aura_cost(hp.current_hero_id, aid)
	var iid: String = aura.get("cost_item", "")
	var iname: String = data.ITEM_CONFIG.get(iid, {}).get("name", iid)
	var card := {"name": aura.get("name", ""), "stars": int(per), "is_max": false, "info": info,
		"own_name": iname, "own": [cost, int(data.items.get(iid, 0))],
		"on_single": func(): _on_pair_aura_up(aid, 1),
		"on_bulk": func(): _on_pair_aura_up(aid, 10)}
	return card


# 【新增】2026-09-25 自带光环卡片（小柒）：无道具消耗（闸门=五艳对应光环总等级），free_action 单钮分支（卡协议同师徒光环卡）
func _build_self_aura_card(aura: Dictionary) -> Dictionary:
	var aid: String = aura.get("id", "")
	var lv: int = data.hero_system.get_self_aura_level(hp.current_hero_id, aid)
	var per: float = float(aura.get("per", 0))
	var is_apt: bool = aura.get("type", "") == "aptitude"
	# 卡片规范："当前总数值（下级+下级数值）"（同师徒光环卡）
	var unit: String
	if is_apt:
		unit = "资质+%d（下级+%d）" % [int(per) * lv, int(per) * (lv + 1)]
	else:
		unit = "赚钱+%.1f%%（下级+%.1f%%）" % [per * lv, per * (lv + 1)]
	var scope := "自身"
	if aura.get("target", "") == "career": scope = "同职业门客"
	elif aura.get("target", "") == "self_wuyan": scope = "小柒与秦淮五艳"
	var gate: Dictionary = data.hero_system.get_self_aura_gate(hp.current_hero_id, aura)
	var info: String = "【%s】 Lv.%d\n%s（%s）\n需五艳【%s】总等级 %d/%d" % [
		aura.get("name", ""), lv, unit, scope,
		str(aura.get("gate", {}).get("aura", "")), int(gate.get("total", 0)), int(gate.get("need", 0))]
	# 无等级上限（闸门即上限）：is_max=false 恒显示升级钮，闸门不满足时点击弹失败原因
	return {"name": aura.get("name", ""), "stars": int(per), "is_max": false, "info": info,
		"free_action": true, "on_single": func(): _on_self_aura_up(aid)}


func _on_self_aura_up(aura_id: String):
	var res: Dictionary = data.hero_system.upgrade_self_aura(hp.current_hero_id, aura_id)
	if res.get("ok", false):
		c._show_stage_hint("【%s】升至 %d 级" % [_self_aura_name(aura_id), int(res.get("level", 0))])
	else:
		c._show_stage_hint(str(res.get("msg", "升级失败")))
	hp.update_hero_panel()
	c.update_all_ui()


func _self_aura_name(aura_id: String) -> String:
	for a in data.hero_system.get_self_aura_cfgs(hp.current_hero_id):
		if a.get("id", "") == aura_id: return str(a.get("name", aura_id))
	return aura_id


func _on_pair_aura_up(aura_id: String, times: int):
	var res: Dictionary = data.hero_system.upgrade_pair_aura(hp.current_hero_id, aura_id, times)
	c._show_stage_hint("【%s】升至 %d 级" % [_pair_aura_name(aura_id), res.get("level", 0)] if res.get("ok", false) else res.get("msg", "升级失败"))
	hp.update_hero_panel()   # 光环变化影响资质/赚钱，整面板对账
	c.update_all_ui()


func _pair_aura_name(aura_id: String) -> String:
	for a in data.hero_system.get_pair_aura_cfgs(hp.current_hero_id):
		if a.get("id", "") == aura_id: return str(a.get("name", aura_id))
	return aura_id


# 品质名（拜师选择器等小处复用）
func _quality_name(q: int) -> String:
	return {0: "优秀", 1: "卓越", 2: "传奇", 3: "无双"}.get(q, "优秀")

