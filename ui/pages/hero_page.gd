# ============================================================
# 门客页（含门客面板/珍兽装备选择）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name HeroPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var current_hero_id: String = ""

# 【v4新增】技能栏当前标签页："skill"技能 / "shop"副业 / "costume"服装 / "halo"光环（后两者待开发）
var current_skill_tab: String = "skill"

var _cuzhi_last_use_jinghua: bool = false   # 【促织装备】上次升级用的促织精华（true）还是珍兽果（false）
var _guardian_batch: bool = false   # 【新增】守护灵注灵十连勾选状态（面板生命周期内保持）
var _promo_batch: bool = false   # 【新增】赋诗十连勾选状态（面板生命周期内保持）
var _token_batch: bool = false   # 【新增】信物十连勾选状态（面板生命周期内保持）
var _fengzi_batch: bool = false   # 【新增】风姿十连勾选状态（面板生命周期内保持）
var _apt_use_baiye: bool = false   # 【钱庄】资质技能升级用百业经验（true）还是资质丹（false），勾选记忆


# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_hero_list():
	if data._hero_configs.is_empty():
		print("警告：门客配置为空，尝试重新加载...")
		data._load_all_configs()
	
	if not c.has_node("PageContainer/HeroPage"): return
	var scroll = c.get_node("PageContainer/HeroPage/HeroScroll")
	for child in scroll.get_children():
		scroll.remove_child(child) 
		child.queue_free()
	
	# 创建网格
	var grid = GridContainer.new()
	grid.name = "HeroGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	
	# 1. 已解锁门客
	for hero_id in data.heroes.keys():
		var cell = _create_hero_card(hero_id, false)
		grid.add_child(cell)
	
	# 2. 未解锁的VIP门客
	for hero_id in data.get_all_hero_ids():
		if not data.heroes.has(hero_id):
			var cell = _create_hero_card(hero_id, true)
			grid.add_child(cell)
	
	update_hero_list()

func _create_hero_card(hero_id: String, locked: bool) -> Button:
	var cell = Button.new()
	cell.name = hero_id + ("_hero_locked" if locked else "_hero")
	cell.custom_minimum_size = Vector2(180, 240)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 【修】手机端：按钮默认 STOP 拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	cell.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_lbl)
	
	var income_lbl = Label.new()
	income_lbl.name = "IncomeLabel"
	income_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	income_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(income_lbl)
	
	var status_lbl = Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(status_lbl)
	
	if locked:
		cell.modulate = Color(0.5, 0.5, 0.5, 0.7)
		cell.pressed.connect(_on_locked_hero_clicked.bind(hero_id))
	else:
		cell.pressed.connect(open_hero_detail.bind(hero_id))
	
	return cell

func _on_locked_hero_clicked(hero_id: String):
	var vip_level = data.get_hero_unlock_vip(hero_id)
	var cfg = data.get_hero_config(hero_id)
	var hero_name = cfg.get("name", "未知门客")
	c._show_unlock_hint("门客 " + hero_name, vip_level)

func open_hero_panel(hero_id: String):
	current_hero_id = hero_id
	current_skill_tab = "skill"   # 【v4】切换门客时标签重置回技能页，避免串数据误会
	_ensure_hero_panel_code()   # 【第8批新增】首次打开时把场景旧面板替换为代码构建的全屏面板
	if c.has_node("HeroPanel"):
		c.open_popup(c.get_node("HeroPanel"))
		update_hero_panel()

func close_hero_panel():
	c.close_popup()
	current_hero_id = ""
	update_hero_list()

# 【第8批新增】确保 HeroPanel 为代码构建的全屏版本
# 布局v3（2026-08-27 按手绘图重排）：
#   顶部居中：门客名 + 赚速/资质
#   左列：第1行 缘分；第2行 珍兽+渔获 并排（该行预留2个按钮位，后续扩展 x 依次+128）
#   右列：赋诗/晋升按钮（有才显示）在上，升级区在下，固定于技能栏上方
#   底部：全宽技能列表（资质/店铺技能）
# 所有子节点名与场景版一致，update_hero_panel 等逻辑零改动
func _ensure_hero_panel_code():
	# 已经是代码构建版则直接复用
	if c.has_node("HeroPanel") and c.get_node("HeroPanel").has_meta("code_built"):
		return
	# 移除场景旧面板（remove_child+free 立即生效，避免 queue_free 当帧重名冲突）
	if c.has_node("HeroPanel"):
		var old_panel = c.get_node("HeroPanel")
		c.remove_child(old_panel)
		old_panel.free()
	var vw = c.get_viewport_rect().size
	# 全屏面板
	var panel = Panel.new()
	panel.name = "HeroPanel"
	panel.set_meta("code_built", true)
	panel.visible = false
	# 【关键】z_index=10：压过 Overlay/BottomNav（默认0），又低于 _create_base_popup 弹窗的30
	panel.z_index = 10
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1b2e")
	panel.add_theme_stylebox_override("panel", style)
	c.add_child(panel)
	# 显式锚点+位置+尺寸三保险（先锚点再显式position/size，防止编辑器残留锚点干扰）
	panel.position = Vector2.ZERO
	panel.size = vw

	# 门客名（顶部整行居中）
	var name_lbl = Label.new()
	name_lbl.name = "HeroName"
	name_lbl.position = Vector2(0, 10)
	name_lbl.size = Vector2(vw.x, 30)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	panel.add_child(name_lbl)

	# 赚速/资质（名称下方，整行居中）
	var income_lbl = Label.new()
	income_lbl.name = "HeroIncome"
	income_lbl.position = Vector2(0, 50)
	income_lbl.size = Vector2(vw.x, 24)
	income_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(income_lbl)

	# 关闭按钮（右上；代码重建后需重新连接信号）
	var close_btn = Button.new()
	close_btn.name = "HeroCloseBtn"
	close_btn.text = "X"
	close_btn.position = Vector2(vw.x - 70, 10)
	close_btn.size = Vector2(50, 40)
	close_btn.pressed.connect(close_hero_panel)
	panel.add_child(close_btn)

	# 【v3新增】赋诗/晋升按钮（右列上方；默认隐藏，update_hero_panel 按门客有无晋升内容控制显隐和文本）
	var promo_btn = Button.new()
	promo_btn.name = "PromoBtn"
	promo_btn.position = Vector2(vw.x - 150, 120)
	promo_btn.size = Vector2(130, 44)
	promo_btn.visible = false
	promo_btn.add_theme_font_size_override("font_size", 16)
	panel.add_child(promo_btn)
	
	# 【新增】信物按钮（赋诗按钮上方；仅获得信物的门客显示，显隐由 update_hero_panel 控制）
	var token_btn = Button.new()
	token_btn.name = "TokenBtn"
	token_btn.position = Vector2(vw.x - 150, 62)
	token_btn.size = Vector2(130, 44)
	token_btn.add_theme_font_size_override("font_size", 16)
	token_btn.visible = false
	panel.add_child(token_btn)
	
	# 升级区（右列下方，固定在技能栏上方；无赋诗时上方留空，预留门客立绘位）
	var level_box = HBoxContainer.new()
	level_box.name = "LevelUpBox"
	level_box.position = Vector2(vw.x - 150, 180)
	level_box.add_theme_constant_override("separation", 12)
	panel.add_child(level_box)
	var lv_info = Label.new()
	lv_info.name = "LevelUpInfo"
	# 【v3】消耗数字改到升级按钮内部显示，文本标签隐藏（节点保留，防旧引用报错）
	lv_info.visible = false
	level_box.add_child(lv_info)
	var lv_btn_box = VBoxContainer.new()
	lv_btn_box.name = "LevelUpBtnBox"
	lv_btn_box.add_theme_constant_override("separation", 4)
	level_box.add_child(lv_btn_box)
	var lv_btn = Button.new()
	lv_btn.name = "LevelUpBtn"
	lv_btn.custom_minimum_size = Vector2(130, 48)
	lv_btn_box.add_child(lv_btn)
	var batch_check = CheckBox.new()
	batch_check.name = "BatchCheck"
	batch_check.text = "十连"
	lv_btn_box.add_child(batch_check)
	# 【新增】勾选/取消十连时刷新升级按钮上的消耗数字（单级↔十连总价）
	batch_check.toggled.connect(func(_on): update_hero_panel())

	# 【v4】技能栏标签页（技能/副业/服装/光环；服装光环待开发，先占位）
	var tab_bar = HBoxContainer.new()
	tab_bar.name = "SkillTabBar"
	tab_bar.position = Vector2(20, 310)
	tab_bar.add_theme_constant_override("separation", 8)
	panel.add_child(tab_bar)
	# 标签定义：[节点名, 显示文本, 标签id]；后续新增标签页在此追加一行即可
	var tabs = [["TabSkill", "技能", "skill"], ["TabShop", "副业", "shop"], ["TabCostume", "服装", "costume"], ["TabAura", "光环", "halo"]]
	for t in tabs:
		var tab_btn = Button.new()
		tab_btn.name = t[0]
		tab_btn.text = t[1]
		tab_btn.custom_minimum_size = Vector2(110, 36)
		tab_btn.set_meta("tab_id", t[2])   # 高亮时按 meta 识别当前页
		tab_btn.pressed.connect(_on_skill_tab_clicked.bind(t[2]))
		tab_bar.add_child(tab_btn)

	# 技能列表（底部全宽滚动区，内容随标签页切换）
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.position = Vector2(20, 350)
	scroll.size = Vector2(vw.x - 40, vw.y - 370)
	panel.add_child(scroll)
	var skill_list = VBoxContainer.new()
	skill_list.name = "SkillList"
	skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_list.add_theme_constant_override("separation", 8)
	scroll.add_child(skill_list)

func update_hero_panel():
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var h = data.heroes[current_hero_id]
	var income = data.get_hero_income(current_hero_id)
	var total_aptitude = HeroData.get_total_aptitude(data, current_hero_id)   # 面板资质 = 总资质（含珍兽），与赚速同口径
	var quality_tag = ""
	if h.has("quality") and h.quality > 0:
		quality_tag = "[%s]" % HeroData.get_quality_name(h.quality)
	
	if c.has_node("HeroPanel/HeroName"):
		# 【新增】标题追加天赋星级（★×N；0星不显示）
		var star_txt = data.talent_system.get_star_text(current_hero_id)
		c.get_node("HeroPanel/HeroName").text = "【%s】%s %s Lv.%d%s" % [h.name, h.category, quality_tag, h.level, (" " + star_txt) if star_txt != "" else ""]
	if c.has_node("HeroPanel/HeroIncome"):
		c.get_node("HeroPanel/HeroIncome").text = "赚速：%s/秒  资质：%d" % [c.format_number(income), total_aptitude]
	
	# 清理旧布局（如果有）
	if c.has_node("HeroPanel/BeastInfoBox"):
		c.get_node("HeroPanel/BeastInfoBox").queue_free()
	
# ========== 左列按钮：第1行 服装；第2行 缘分；第3行 珍兽+渔获 并排 ==========
	var beast_id = data.heroes[current_hero_id].get("equipped_beast", "")
	var beast_idx = data.heroes[current_hero_id].get("equipped_beast_index", 0)
	# 【修复】显式固定尺寸：新建 Button 当帧 size 为 (0,0)，不能用 size 做定位依据
	var btn_size = Vector2(120, 40)
	
	# 【服装系统】服装按钮（左列第1行）：点击打开该门客的服装弹窗
	var cos_btn = c.get_node("HeroPanel").get_node_or_null("CostumeBtn")
	if cos_btn == null:
		cos_btn = Button.new()
		cos_btn.name = "CostumeBtn"
		cos_btn.text = "服装"
		cos_btn.add_theme_font_size_override("font_size", 16)
		c.get_node("HeroPanel").add_child(cos_btn)
	cos_btn.size = btn_size
	cos_btn.position = Vector2(20, 100)   # 【改】移到缘分上方
	# 信号重连（先断后连，防止切换门客后串数据）
	for conn in cos_btn.pressed.get_connections():
		cos_btn.pressed.disconnect(conn.callable)
	cos_btn.pressed.connect(c.costume_view.show_hero_costume_popup.bind(current_hero_id))
	
	# 缘分按钮（左列第2行）：点击弹窗显示该门客的缘分挚友
	var fate_btn = c.get_node("HeroPanel").get_node_or_null("FateBtn")
	if fate_btn == null:
		fate_btn = Button.new()
		fate_btn.name = "FateBtn"
		fate_btn.text = "缘分"
		fate_btn.add_theme_font_size_override("font_size", 16)
		c.get_node("HeroPanel").add_child(fate_btn)
	fate_btn.size = btn_size
	fate_btn.position = Vector2(20, 148)   # 【改】下移一行
	# 信号重连（先断后连，防止切换门客后串数据）
	for conn in fate_btn.pressed.get_connections():
		fate_btn.pressed.disconnect(conn.callable)
	fate_btn.pressed.connect(_on_fate_btn_clicked.bind(current_hero_id))
	
		# 【新增】天赋按钮（左列缘分与珍兽行之间空位，即图中红框处）
	var talent_btn = c.get_node("HeroPanel").get_node_or_null("TalentBtn")
	if talent_btn == null:
		talent_btn = Button.new()
		talent_btn.name = "TalentBtn"
		talent_btn.text = "天赋"
		talent_btn.add_theme_font_size_override("font_size", 16)
		c.get_node("HeroPanel").add_child(talent_btn)
	talent_btn.size = btn_size
	talent_btn.position = Vector2(20, 196)   # 【新增】缘分(148)与珍兽行(265)之间的空位
	# 信号重连（先断后连，防止切换门客后串数据）
	for conn in talent_btn.pressed.get_connections():
		talent_btn.pressed.disconnect(conn.callable)
	talent_btn.pressed.connect(_on_talent_btn_clicked)
	
	# 珍兽按钮（左列第3行第1格）
	var beast_btn = c.get_node("HeroPanel").get_node_or_null("BeastEquipBtn")
	if beast_btn == null:
		beast_btn = Button.new()
		beast_btn.name = "BeastEquipBtn"
		beast_btn.add_theme_font_size_override("font_size", 16)
		c.get_node("HeroPanel").add_child(beast_btn)
	beast_btn.size = btn_size
	beast_btn.position = Vector2(20, 265)   # 【改】下移
	
	for conn in beast_btn.pressed.get_connections():
		beast_btn.pressed.disconnect(conn.callable)
	
	if beast_id != "":
		var b_cfg = data.get_beast_config(beast_id)
		var b_inst = data.get_beast_instance(beast_id, beast_idx)
		beast_btn.text = "【%s】Lv.%d" % [b_cfg.name, b_inst.level]
		beast_btn.pressed.connect(_on_hero_beast_btn_clicked.bind(beast_id, beast_idx))
	else:
		beast_btn.text = "珍兽"
		beast_btn.pressed.connect(_show_beast_selector_for_hero)
	
	# 渔获按钮（左列第3行第2格，与珍兽并排）
	var fish_btn = c.get_node("HeroPanel").get_node_or_null("FishEquipBtn")
	if fish_btn == null:
		fish_btn = Button.new()
		fish_btn.name = "FishEquipBtn"
		fish_btn.add_theme_font_size_override("font_size", 16)
		c.get_node("HeroPanel").add_child(fish_btn)
	fish_btn.size = btn_size
	fish_btn.position = Vector2(148, 265)   # 【改】下移
	# 信号重连（先断后连，防止切换门客后串数据）
	for conn in fish_btn.pressed.get_connections():
		fish_btn.pressed.disconnect(conn.callable)
	var equipped_fish = data.fishing_system.get_hero_fish(current_hero_id)
	if equipped_fish != "":
		fish_btn.text = "【%s】%d阶" % [data.fishing_system.get_fish_name(equipped_fish), data.fishing_system.get_fish_tier(equipped_fish)]
	else:
		fish_btn.text = "渔获"
	fish_btn.pressed.connect(c.show_fish_equip_view.bind(current_hero_id))
	
		# 【新增】促织装备按钮（左列第3行第3格，与珍兽/渔获并排）
	var cuzhi_btn = c.get_node("HeroPanel").get_node_or_null("CuzhiEquipBtn")
	if cuzhi_btn == null:
		cuzhi_btn = Button.new()
		cuzhi_btn.name = "CuzhiEquipBtn"
		cuzhi_btn.add_theme_font_size_override("font_size", 16)
		c.get_node("HeroPanel").add_child(cuzhi_btn)
	cuzhi_btn.size = btn_size
	cuzhi_btn.position = Vector2(276, 265)
	# 信号重连（先断后连，防止切换门客后串数据）
	for conn in cuzhi_btn.pressed.get_connections():
		cuzhi_btn.pressed.disconnect(conn.callable)
	var equipped_cuzhi = data.cuzhi_system.get_equipped_cricket(current_hero_id)
	if equipped_cuzhi != "":
		var cuzhi_name = data.cuzhi_system.get_cricket_data(equipped_cuzhi).get("name", "未知")
		var cuzhi_lv = data.cuzhi_system.get_equip_level(equipped_cuzhi)
		cuzhi_btn.text = "【%s】Lv.%d" % [cuzhi_name, cuzhi_lv]
	else:
		cuzhi_btn.text = "促织"
	cuzhi_btn.pressed.connect(_on_cuzhi_btn_clicked)
	
		# 【新增】守护灵按钮（左列第3行第4格，仅无双门客显示）
	var guardian_btn = c.get_node("HeroPanel").get_node_or_null("GuardianBtn")
	if guardian_btn == null:
		guardian_btn = Button.new()
		guardian_btn.name = "GuardianBtn"
		guardian_btn.add_theme_font_size_override("font_size", 16)
		c.get_node("HeroPanel").add_child(guardian_btn)
	guardian_btn.size = btn_size
	guardian_btn.position = Vector2(404, 265)  # 促织旁边（间距8px）
	# 信号重连（先断后连，防切换门客串数据）
	for conn in guardian_btn.pressed.get_connections():
		guardian_btn.pressed.disconnect(conn.callable)
	var is_wushuang = h.get("quality", 0) == 2
	guardian_btn.visible = is_wushuang
	if is_wushuang:
		# 确保守护灵已初始化（旧档兼容）
		data.guardian_system.init_guardian(current_hero_id)
		var gs = data.guardian_system.get_guardian(current_hero_id)
		var avatar_name = "溟灵"
		for av in data.guardian_system.AVATARS:
			if av.id == gs.get("avatar", "mingling"):
				avatar_name = av.name
				break
		guardian_btn.text = "【%s】Lv.%d" % [avatar_name, gs.level]
		guardian_btn.pressed.connect(_on_guardian_btn_clicked)
	else:
		guardian_btn.text = "守护灵"
	
	# 【改】技能列表下移到最后一个按钮（促织）下方，避免重叠
	if c.get_node("HeroPanel").has_node("ScrollContainer"):
		var scroll = c.get_node("HeroPanel/ScrollContainer")
		var skill_tab_bar = c.get_node("HeroPanel/SkillTabBar")
		var last_btn = fish_btn
		if c.get_node("HeroPanel").has_node("CuzhiEquipBtn"):
			last_btn = c.get_node("HeroPanel/CuzhiEquipBtn")
		# 守护灵存在且可见时，以它为最底
		if c.get_node("HeroPanel").has_node("GuardianBtn") and c.get_node("HeroPanel/GuardianBtn").visible:
			last_btn = c.get_node("HeroPanel/GuardianBtn")
		var needed_scroll_y = last_btn.position.y + last_btn.size.y + 20  # 【改】间距从8加大到20
		var needed_tab_y = needed_scroll_y - 40  # 标签栏在列表上方40px
		if scroll.position.y < needed_scroll_y:
			scroll.position.y = needed_scroll_y
		if skill_tab_bar.position.y < needed_tab_y:
			skill_tab_bar.position.y = needed_tab_y
	
	# 【新增】信物按钮：获得信物的门客显示（无信物直接隐藏），点击打开信物面板
	var token_btn = c.get_node("HeroPanel").get_node_or_null("TokenBtn")
	if token_btn:
		for conn in token_btn.pressed.get_connections():
			token_btn.pressed.disconnect(conn.callable)
		if data.token_system.has_token(current_hero_id):
			var t_cfg = data.token_system.get_token_cfg(current_hero_id)
			token_btn.text = t_cfg.get("token_name", "信物")
			token_btn.visible = true
			token_btn.pressed.connect(_on_token_btn_clicked)
		else:
			token_btn.visible = false
	
	# 【v3新增】赋诗/晋升按钮（右列上方）：有晋升内容的门客才显示，点击弹窗升级
	var promo_btn = c.get_node("HeroPanel").get_node_or_null("PromoBtn")
	if promo_btn:
		for conn in promo_btn.pressed.get_connections():
			promo_btn.pressed.disconnect(conn.callable)
		if h.has("promotion"):
			var promo = h.promotion
			promo_btn.text = promo.get("name", "晋升")
			promo_btn.visible = true
			promo_btn.pressed.connect(_on_promo_btn_clicked)
		else:
			# 无晋升内容：留空（上方区域预留门客立绘位）
			promo_btn.visible = false
	
	# ========== 升级区（右列下方；v3：消耗数字显示在按钮内部，不再用文本标签） ==========
	var level_box = c.get_node("HeroPanel").get_node("LevelUpBox")
	var max_lv = 50 + h.breakthrough_count * 50
	var need_bt = h.level >= max_lv
	var bt_cost = h.breakthrough_count * 10
	
	var lv_btn = level_box.get_node("LevelUpBtnBox/LevelUpBtn")
	var batch_check = level_box.get_node("LevelUpBtnBox/BatchCheck")
	
	if need_bt:
		# 到达突破节点：按钮显示 突破+风雅颂数量，隐藏勾选框
		lv_btn.text = "突破\n%d" % bt_cost
		batch_check.visible = false
		#关闭升级
		if lv_btn.pressed.is_connected(on_hero_level_upgrade):
			lv_btn.pressed.disconnect(on_hero_level_upgrade)
		#连接突破
		if not lv_btn.pressed.is_connected(on_hero_breakthrough):
			lv_btn.pressed.connect(on_hero_breakthrough)
	else:
		# 【改】消耗数字交给统一函数：未勾选显示下一级消耗，勾选十连显示十连总价
		lv_btn.text = _get_level_up_btn_text(h)
		batch_check.visible = true
		#关闭突破
		if lv_btn.pressed.is_connected(on_hero_breakthrough):
			lv_btn.pressed.disconnect(on_hero_breakthrough)
		#连接升级
		if not lv_btn.pressed.is_connected(on_hero_level_upgrade):
			lv_btn.pressed.connect(on_hero_level_upgrade)
	
	if not c.has_node("HeroPanel/ScrollContainer/SkillList"): return
	var list = c.get_node("HeroPanel/ScrollContainer/SkillList")
	
	# 清空
	for child in list.get_children():
		child.queue_free()
	
	# 【v4】按当前标签页填充列表（资质/店铺技能行移入独立填充函数，便于扩展服装/光环页）
	match current_skill_tab:
		"skill":
			_fill_skill_tab(list)
		"shop":
			_fill_shop_tab(list)
		"costume":
			_fill_costume_tab(list)   # 【服装系统】服装技能页
		"halo":
			_fill_halo_tab(list)      # 【服装系统】服装光环页
		_:
			# 预留占位（新标签页用）
			_fill_placeholder_tab(list)
	# 标签按钮高亮：选中页金色字，其余恢复默认色
	var tab_bar = c.get_node("HeroPanel").get_node_or_null("SkillTabBar")
	if tab_bar:
		for tab_btn in tab_bar.get_children():
			if tab_btn.get_meta("tab_id", "") == current_skill_tab:
				tab_btn.add_theme_color_override("font_color", Color("#ffd700"))
			else:
				tab_btn.remove_theme_color_override("font_color")

func on_hero_level_upgrade():
	var batch = false
	if c.has_node("HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck"):
		batch = c.get_node("HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck").button_pressed
	
	var upgraded = data.upgrade_hero_level(current_hero_id, batch)
	if upgraded > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【新增】升级按钮文本：未勾选十连显示下一级消耗；勾选十连显示接下来最多10级（不超突破上限）的总消耗
# 十连总价按 hero_system.upgrade_hero_level 的实际扣费公式 100*1.05^lv 逐级累加，保证显示多少扣多少
func _get_level_up_btn_text(h) -> String:
	if not c.has_node("HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck"):
		return "升级"
	var batch = c.get_node("HeroPanel/LevelUpBox/LevelUpBtnBox/BatchCheck").button_pressed
	if not batch:
		return "升级\n%d" % int(ceil(900 * pow(1.0158, h.level)))
	var max_lv = 50 + h.breakthrough_count * 50
	var total = 0
	for lv in range(h.level, min(h.level + 10, max_lv)):
		total += int(ceil(900 * pow(1.0158, lv))) * 10
	return "十连\n%d" % total

func on_hero_breakthrough():
	if data.breakthrough_hero(current_hero_id):
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func _on_hero_beast_btn_clicked(beast_id: String, beast_idx: int):
	var panel = c._create_base_popup("珍兽操作", Vector2(360, 240), Vector2(396, 200))
	panel.name = "BeastActionPanel"
	
	var vbox = panel.get_child(0)
	
	var replace_btn = Button.new()
	replace_btn.text = "替换珍兽"
	replace_btn.pressed.connect(func():
		c._safe_close("BeastActionPanel")
		_show_beast_selector_for_hero()
	)
	vbox.add_child(replace_btn)
	
	var detail_btn = Button.new()
	detail_btn.text = "培养珍兽"
	detail_btn.pressed.connect(func():
		c._safe_close("BeastActionPanel")
		c.open_beast_detail(beast_id, beast_idx)
	)
	vbox.add_child(detail_btn)
	
	var unequip_btn = Button.new()
	unequip_btn.text = "卸下珍兽"
	unequip_btn.pressed.connect(func():
		data.unequip_beast(current_hero_id)
		c._safe_close("BeastActionPanel")
		update_hero_panel()
		c.update_all_ui()
	)
	vbox.add_child(unequip_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(func(): c._safe_close("BeastActionPanel"))
	vbox.add_child(cancel_btn)
	
	c.add_child(panel)

func _show_beast_selector_for_hero():
	if current_hero_id == "": return
	
	var panel = c._create_base_popup("选择珍兽装备", Vector2(460, 400), Vector2(346, 120))
	panel.name = "BeastSelectForHero"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	var has_beast = false
	for beast_id in data.beasts.keys():
		var cfg = data.get_beast_config(beast_id)
		var count = data.get_beast_instance_count(beast_id)
		for i in range(count):
			var instance = data.get_beast_instance(beast_id, i)
			if instance == null: continue
			var btn = Button.new()
			# 【修】手机端：按钮默认 STOP 拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			var apt = data.get_beast_aptitude(beast_id, i)
			var bonus = data.get_beast_skill_bonus(beast_id, i) + data.get_beast_aura_bonus(beast_id, i)
			
			var equipped_hero = instance.get("equipped_hero", "")
			var status = ""
			if equipped_hero == current_hero_id:
				status = " [当前装备]"
				btn.disabled = true
			elif equipped_hero != "" and data.heroes.has(equipped_hero):
				status = " [%s已装备]" % data.heroes[equipped_hero].name
			
			btn.text = "【%s】Lv.%d 资质+%d 加成+%.0f%%%s" % [cfg.name, instance.level, apt, bonus * 100, status]
			
			if not btn.disabled:
				btn.pressed.connect(_on_equip_beast_to_hero.bind(beast_id, i))
			list.add_child(btn)
			has_beast = true
	
	if not has_beast:
		var empty = Label.new()
		empty.text = "暂无可装备珍兽"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("BeastSelectForHero"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

func _on_equip_beast_to_hero(beast_id: String, index: int):
	data.equip_beast(current_hero_id, beast_id, index)
	c._safe_close("BeastSelectForHero")
	update_hero_panel()
	c.update_all_ui()

func _on_hero_unequip_beast():
	data.unequip_beast(current_hero_id)
	update_hero_panel()
	c.update_all_ui()

# 【改】升级资质技能（钱庄：勾选「百业经验」时从该门客个人池抵扣，每级=300×每级丹数；否则吃资质丹）
func on_aptitude_skill_upgrade(skill_index: int, mode: String = "single"):
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var hero = data.heroes[current_hero_id]
	var skill = hero.aptitude_skills[skill_index]

	# 已满级
	if skill.level >= skill.max_level:
		return

	var cost_per_level = int(skill.get("aptitude_per_level", 1))  # 每级固定消耗=每级加的资质数
	var remaining = skill.max_level - skill.level
	var levels_to_upgrade: int = 1 if mode == "single" else 0

	# 【钱庄】百业经验抵扣路径：池够升多少升多少（single=1级，bulk=封顶剩余等级）
	if _apt_use_baiye:
		var baiye_per_level: int = cost_per_level * data.bank_system.get_baiye_per_pill()   # 显式标注（data 无类型，方法返回 Variant，:= 推断不出）
		if mode != "single":
			levels_to_upgrade = mini(floori(data.bank_system.get_baiye(current_hero_id) / float(baiye_per_level)), remaining)
		if levels_to_upgrade > 0 and data.bank_system.spend_baiye_for_pills(current_hero_id, levels_to_upgrade * cost_per_level):
			skill.level += levels_to_upgrade
			update_hero_panel()
			c.update_all_ui()
			c.update_bag_list()
		return

	var pill_count = data.items.get("aptitude_pill", 0)
	if pill_count < cost_per_level:
		return

	if mode == "single":
		levels_to_upgrade = 1
	else:  # bulk 一键升满
		levels_to_upgrade = min(pill_count / cost_per_level, remaining)  # 【改】按每级N丹折算可升级数

	if levels_to_upgrade > 0:
		data.items.aptitude_pill -= levels_to_upgrade * cost_per_level  # 【改】扣 级数×每级N丹（原扣级数×1）
		skill.level += levels_to_upgrade
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func on_shop_skill_upgrade(skill_index: int, mode: String = "single"):
	if data.upgrade_hero_shop_skill(current_hero_id, skill_index, mode):
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【新增】钱庄财源广进升级（独立技能，走筹算值；single=升1级，bulk=筹算值够升多少升多少）
func on_shop_skill_chousuan_upgrade(mode: String = "single"):
	if data.bank_system.upgrade_caiyuan_skill(current_hero_id, mode):
		update_hero_panel()
		c.update_all_ui()   # 店铺技能加成↑ → 派遣赚速/全局赚速飘字
		c.update_bag_list()

# 【新增】虫师副业技能升级（促织园体系走 cuzhi_system；single=升1级，bulk=一键升满）
func on_side_skill_upgrade(skill_idx: int, mode: String = "single"):
	if data.cuzhi_system.upgrade_side_skill(current_hero_id, skill_idx, mode == "bulk"):
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【新增】副业资质技能升级（side_skill_system；single=升1级，bulk=一键升满）
func on_side_sys_upgrade(key: String, mode: String = "single"):
	if data.side_skill_system.upgrade(current_hero_id, key, mode) > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

func on_promotion_upgrade(mode: String = "single"):
	var upgraded = data.upgrade_promotion(current_hero_id, mode == "bulk")
	if upgraded > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【改】晋升面板参数化 v3：标题/资质技能名/解锁列表/按钮文案全部读 promotion 配置
# （李白=赋诗·天生我材，白月初=续缘·仙缘梦绕）；【新增】苦情契约按钮（白月初独有，位置同风姿按钮）
func _on_promo_btn_clicked():
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var h = data.heroes[current_hero_id]
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
	
	# ── 技能信息：等级+总资质 /（下级资质）/ 消耗+拥有 ──
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 【改】技能名参数化（李白=天生我材，白月初=仙缘梦绕）
	info_lbl.text = "%s %d级 +%d资质\n（下级+%d资质）\n每级消耗%d【%s】  拥有：%d" % [
		skill_name, int(promo.level), int(promo.level) * int(promo.aptitude_per_level),
		int(promo.aptitude_per_level),
		int(promo.cost_amount), item_name,
		data.items.get(promo.cost_item, 0)
	]
	vb.add_child(info_lbl)
	
	# ── 升级区：晋升按钮 + 十次勾选（勾选状态存类变量 _promo_batch，升级/重建不清）──
	var up_box = HBoxContainer.new()
	up_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(up_box)
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
	fengzi_btn.custom_minimum_size = Vector2(140, 36)
	if data.fengzi_system.has_fengzi(current_hero_id):
		fengzi_btn.text = "【风姿】%s" % data.fengzi_system.get_fengzi_cfg(current_hero_id).get("fengzi_name", "风姿")
	else:
		fengzi_btn.visible = false
	fengzi_btn.pressed.connect(func():
		if is_instance_valid(popup): popup.queue_free()   # 先关晋升面板再开风姿面板，避免弹窗堆叠
		_show_fengzi_panel()
	)
	vb.add_child(fengzi_btn)
	
	# 【新增】苦情契约按钮：仅白月初显示（与风姿同位置，两者不会同时出现）
	var contract_btn = Button.new()
	contract_btn.custom_minimum_size = Vector2(140, 36)
	if current_hero_id == data.token_system.CONTRACT_HERO:
		contract_btn.text = "【契约】苦情契约"
	else:
		contract_btn.visible = false
	contract_btn.pressed.connect(func():
		if is_instance_valid(popup): popup.queue_free()
		_show_contract_panel()
	)
	vb.add_child(contract_btn)
	
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
	
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")

func open_hero_detail(hero_id: String):
	open_hero_panel(hero_id)

func update_hero_list():
	if not c.has_node("PageContainer/HeroPage/HeroScroll/HeroGrid"): return
	var grid = c.get_node("PageContainer/HeroPage/HeroScroll/HeroGrid")
	
	for cell in grid.get_children():
		if not cell is Button: continue
		
		var hero_id = cell.name.replace("_hero_locked", "").replace("_hero", "")
		
		var name_lbl = cell.find_child("NameLabel", true, false)
		var income_lbl = cell.find_child("IncomeLabel", true, false)
		var status_lbl = cell.find_child("StatusLabel", true, false)
		
		var h = null
		var income = 0
		var status = ""
		
		if data.heroes.has(hero_id):
			h = data.heroes[hero_id]
			status = data.talent_system.get_star_text(hero_id)
			income = data.get_hero_income(hero_id)
			cell.modulate = Color.WHITE
		elif not data.heroes.has(hero_id) and data.get_hero_config(hero_id) != null:
			h = data.get_hero_config(hero_id)
			var vip_level = data.get_hero_unlock_vip(hero_id)
			status = "VIP%d解锁" % vip_level
			cell.modulate = Color(0.5, 0.5, 0.5, 0.7)
		else:
			continue
		
		if name_lbl:
			name_lbl.text = "【%s】Lv.%d | %s" % [h.name, h.level, h.category]
			# 【新增】门客名字按品质着色（传奇橙#e67e22/无双红#e74c3c，普通白）
			name_lbl.add_theme_color_override("font_color", Color(HeroData.get_quality_color(int(h.get("quality", 0)))))
		if income_lbl:
			income_lbl.text = "%s/秒" % c.format_number(income)
		if status_lbl:
			status_lbl.text = status
		
		# 【新增】卡片边框按品质着色（普通/卓越紫、传奇橙、无双红；locked 卡整体灰显自然压暗）
		var q_col = Color(HeroData.get_quality_color(int(h.get("quality", 0))))
		var card_sty = StyleBoxFlat.new()
		card_sty.bg_color = Color("#232035")
		card_sty.border_color = q_col
		card_sty.set_border_width_all(2)
		card_sty.set_corner_radius_all(6)
		cell.add_theme_stylebox_override("normal", card_sty)
		cell.add_theme_stylebox_override("hover", card_sty)
		cell.add_theme_stylebox_override("pressed", card_sty)
	
	_sort_hero_grid(grid)   # 【新增】每次刷新后按实时赚速重排卡片顺序

# 【新增】门客网格按赚速降序重排：已解锁按实时赚速从高到低，未解锁VIP门客保持原相对顺序排在最后
# 赚速会随升级/今日新菜等变化，所以在 update_hero_list 每次刷新时调用，保证顺序始终最新
func _sort_hero_grid(grid):
	var unlocked = []   # 已解锁：[cell, 实时赚速]
	var locked = []     # 未解锁VIP门客：保持原相对顺序
	for cell in grid.get_children():
		if not cell is Button: continue
		# 与 update_hero_list 相同的 id 解析方式：去掉 _hero_locked / _hero 后缀
		var hero_id = cell.name.replace("_hero_locked", "").replace("_hero", "")
		if data.heroes.has(hero_id):
			unlocked.append([cell, data.get_hero_income(hero_id)])
		else:
			locked.append(cell)
	unlocked.sort_custom(func(a, b): return a[1] > b[1])   # 赚速降序
	# 用 move_child 原位重排：先排已解锁，未解锁依次排到末尾（不销毁重建，保留卡片信号连接）
	var idx = 0
	for pair in unlocked:
		grid.move_child(pair[0], idx)
		idx += 1
	for cell in locked:
		grid.move_child(cell, idx)
		idx += 1

# 【新增】获取指定门客的全部缘分挚友id（friends.json 中 bound_heroes 数组包含该门客的挚友）
func _get_fate_friends(hero_id: String) -> Array:
	var result = []
	for fid in data.get_all_friend_ids():
		var cfg = data.get_friend_config(fid)
		if cfg.get("bound_heroes", []).has(hero_id):
			result.append(fid)
	return result

# 【新增】缘分按钮点击：弹窗列出该门客全部缘分挚友
# 已拥有=金色（带友好度）；未拥有=灰色默认色，附获取途径（VIP解锁 / 游历好感进度 / 仅显示未拥有）
func _on_fate_btn_clicked(hero_id: String):
	var fate_ids = _get_fate_friends(hero_id)
	if fate_ids.is_empty():
		c._show_stage_hint("该门客没有缘分挚友")
		return
	var popup = c._create_base_popup("缘分挚友", Vector2(420, 400), Vector2(366, 120))
	popup.name = "FatePopup"
	var vb = popup.get_child(0)
	# 列表可滚动，挚友多时不超窗
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for fid in fate_ids:
		var cfg = data.get_friend_config(fid)
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if data.friends.has(fid):
			# 已拥有：金色 + 当前友好度
			lbl.text = "【%s】已拥有（友好%d）" % [cfg.get("name", fid), data.friends[fid].friendly]
			lbl.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			# 未拥有：按获取途径显示提示（VIP解锁 > 游历好感 > 仅标未拥有）
			var vip_lv = data.get_friend_unlock_vip(fid)
			if vip_lv > 0:
				lbl.text = "【%s】未拥有（VIP%d解锁）" % [cfg.get("name", fid), vip_lv]
			elif data.TRAVEL_AFFECTION.has(fid):
				lbl.text = "【%s】未拥有（游历好感%d/%d）" % [cfg.get("name", fid), data.friend_affection.get(fid, 0), data.TRAVEL_AFFECTION[fid]]
			else:
				lbl.text = "【%s】未拥有" % cfg.get("name", fid)
		list.add_child(lbl)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 【v4新增】技能栏标签点击：记录当前标签页并刷新面板
func _on_skill_tab_clicked(tab_id: String):
	current_skill_tab = tab_id
	update_hero_panel()

# 【v4新增】填充「技能」页：资质技能行（原 update_hero_panel 资质段迁出，逻辑不变）
# 【钱庄】行首加本门客百业经验个人池展示；每行加「百业经验」抵扣勾选框（勾选记忆）
func _fill_skill_tab(list):
	var h = data.heroes[current_hero_id]
	# 百业经验个人池（钱庄柜台产出，资质技能可勾选抵扣 300×每级丹数）
	var pool_lbl = Label.new()
	pool_lbl.text = "百业经验（本门客）：%d　——勾选「百业经验」后，升级改为从个人池抵扣（每级=300×每级丹数）" % data.bank_system.get_baiye(current_hero_id)
	pool_lbl.add_theme_font_size_override("font_size", 12)
	pool_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
	pool_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(pool_lbl)
	for i in range(h.aptitude_skills.size()):
		var skill = h.aptitude_skills[i]
		var apt_cost = int(skill.get("aptitude_per_level", 1))  # 【改】固定消耗=每级资质增量，替换原 1.05^(lv-1) 曲线

		var apt_row = HBoxContainer.new()
		apt_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var apt_info = Label.new()
		# 【钱庄】勾选百业经验时信息行显示抵扣价（300×每级丹数）
		if _apt_use_baiye:
			apt_info.text = "【资质】%s  Lv.%d/%d  需%d百业经验" % [skill.name, skill.level, skill.max_level, apt_cost * data.bank_system.get_baiye_per_pill()]
		else:
			apt_info.text = "【资质】%s  Lv.%d/%d  需%d资质丹" % [skill.name, skill.level, skill.max_level, apt_cost]
		apt_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apt_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		apt_info.clip_text = true
		apt_info.custom_minimum_size.x = 300
		apt_row.add_child(apt_info)

		# 【钱庄】百业经验抵扣勾选框（勾选记忆=促织装备先例；先赋值后连信号，防重建重入）
		var apt_chk = CheckBox.new()
		apt_chk.text = "百业经验"
		apt_chk.add_theme_font_size_override("font_size", 12)
		apt_chk.button_pressed = _apt_use_baiye
		apt_chk.toggled.connect(func(pressed):
			_apt_use_baiye = pressed
			update_hero_panel()   # 重建刷新：信息行切换显示对应货币消耗
		)
		apt_row.add_child(apt_chk)

		var apt_btn_box = VBoxContainer.new()
		apt_btn_box.custom_minimum_size = Vector2(70, 0)
		apt_btn_box.add_theme_constant_override("separation", 3)
		
		var apt_btn_single = Button.new()
		apt_btn_single.text = "升级"
		apt_btn_single.custom_minimum_size = Vector2(70, 24)
		apt_btn_single.add_theme_font_size_override("font_size", 12)
		apt_btn_single.pressed.connect(on_aptitude_skill_upgrade.bind(i, "single"))
		apt_btn_box.add_child(apt_btn_single)
		
		var apt_btn_bulk = Button.new()
		apt_btn_bulk.text = "一键升级"
		apt_btn_bulk.custom_minimum_size = Vector2(70, 24)
		apt_btn_bulk.add_theme_font_size_override("font_size", 12)
		apt_btn_bulk.pressed.connect(on_aptitude_skill_upgrade.bind(i, "bulk"))
		apt_btn_box.add_child(apt_btn_bulk)
		
		apt_row.add_child(apt_btn_box)
		list.add_child(apt_row)
		
	# 【新增】守护灵技能（仅无双门客，阶段解锁后才显示）
	if h.get("quality", 0) == 2:
		data.guardian_system.init_guardian(current_hero_id)
		var gs = data.guardian_system.get_guardian(current_hero_id)
		if not gs.is_empty():
			for i in range(data.guardian_system.PHASES.size()):
				if not data.guardian_system.is_phase_full(current_hero_id, i):
					continue
				var skill = gs.skills[i]
				var apt_cost = int(skill.aptitude_per_level)
				
				var apt_row = HBoxContainer.new()
				apt_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				
				var apt_info = Label.new()
				apt_info.text = "【守护灵】%s  Lv.%d/%d  需%d资质丹" % [skill.name, skill.level, skill.max_level, apt_cost]
				apt_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				apt_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				apt_info.clip_text = true
				apt_info.custom_minimum_size.x = 380
				apt_row.add_child(apt_info)
				
				var apt_btn_box = VBoxContainer.new()
				apt_btn_box.custom_minimum_size = Vector2(70, 0)
				apt_btn_box.add_theme_constant_override("separation", 3)
				
				var apt_btn_single = Button.new()
				apt_btn_single.text = "升级"
				apt_btn_single.custom_minimum_size = Vector2(70, 24)
				apt_btn_single.add_theme_font_size_override("font_size", 12)
				apt_btn_single.pressed.connect(_on_guardian_skill_upgrade.bind(i, "single"))
				apt_btn_box.add_child(apt_btn_single)
				
				var apt_btn_bulk = Button.new()
				apt_btn_bulk.text = "一键升级"
				apt_btn_bulk.custom_minimum_size = Vector2(70, 24)
				apt_btn_bulk.add_theme_font_size_override("font_size", 12)
				apt_btn_bulk.pressed.connect(_on_guardian_skill_upgrade.bind(i, "bulk"))
				apt_btn_box.add_child(apt_btn_bulk)
				
				apt_row.add_child(apt_btn_box)
				list.add_child(apt_row)

# 【v4新增】填充「副业」页：店铺技能行（原 update_hero_panel 店铺段迁出，逻辑不变）
func _fill_shop_tab(list):
	var h = data.heroes[current_hero_id]
	data.bank_system.ensure_caiyuan_skill(current_hero_id)   # 【钱庄】懒创建财源广进技能（独立技能，结构镜像第一个店铺技能）
	for i in range(h.shop_skills.size()):
		var skill = h.shop_skills[i]
		# 【钱庄】财源广进=筹算值独立技能，与门客委任分开两行（用户 2026-09-12 拍板：两个技能，不要合一）
		var is_caiyuan := str(skill.get("name", "")) == "财源广进"
		var current_percent = skill.base_percent + (skill.level - 1) * skill.percent_per_level
		var shop_cost = max(1, int(ceil(pow(1.05, skill.level - 1))))
		var ch_cost: int = data.bank_system.get_chousuan_cost(skill.level)   # 显式标注（Dictionary 下标 Variant）

		var shop_row = HBoxContainer.new()
		shop_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var shop_info = Label.new()
		if is_caiyuan:
			# 财源广进行：只显示筹算值消耗（6×1.008^(Lv-1)），不挂算盘按钮
			shop_info.text = "【财源广进】Lv.%d/%d  (+%.0f%%)  需%d筹算值" % [skill.level, skill.max_level, current_percent * 100, ch_cost]
		else:
			shop_info.text = "【店铺】%s  Lv.%d/%d  (+%.0f%%)  需%d算盘" % [skill.name, skill.level, skill.max_level, current_percent * 100, shop_cost]
		shop_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shop_info.clip_text = true
		shop_info.custom_minimum_size.x = 240
		shop_row.add_child(shop_info)

		var shop_btn_box = VBoxContainer.new()
		shop_btn_box.custom_minimum_size = Vector2(70, 0)
		shop_btn_box.add_theme_constant_override("separation", 3)

		if is_caiyuan:
			# 【钱庄】财源广进只挂筹算轨按钮
			var ch_btn_single = Button.new()
			ch_btn_single.text = "升级"
			ch_btn_single.custom_minimum_size = Vector2(70, 24)
			ch_btn_single.add_theme_font_size_override("font_size", 12)
			ch_btn_single.pressed.connect(on_shop_skill_chousuan_upgrade.bind("single"))
			shop_btn_box.add_child(ch_btn_single)

			var ch_btn_bulk = Button.new()
			ch_btn_bulk.text = "一键升级"
			ch_btn_bulk.custom_minimum_size = Vector2(70, 24)
			ch_btn_bulk.add_theme_font_size_override("font_size", 12)
			ch_btn_bulk.pressed.connect(on_shop_skill_chousuan_upgrade.bind("bulk"))
			shop_btn_box.add_child(ch_btn_bulk)
		else:
			var shop_btn_single = Button.new()
			shop_btn_single.text = "升级"
			shop_btn_single.custom_minimum_size = Vector2(70, 24)
			shop_btn_single.add_theme_font_size_override("font_size", 12)
			shop_btn_single.pressed.connect(on_shop_skill_upgrade.bind(i, "single"))
			shop_btn_box.add_child(shop_btn_single)

			var shop_btn_bulk = Button.new()
			shop_btn_bulk.text = "一键升级"
			shop_btn_bulk.custom_minimum_size = Vector2(70, 24)
			shop_btn_bulk.add_theme_font_size_override("font_size", 12)
			shop_btn_bulk.pressed.connect(on_shop_skill_upgrade.bind(i, "bulk"))
			shop_btn_box.add_child(shop_btn_bulk)

		shop_row.add_child(shop_btn_box)
		list.add_child(shop_row)
	
		# 【新增】副业资质技能（side_skill_system：市井百业/百工百业/物宝天华/庖丁解牛/XX之道，每级资质+1）
	for r in data.side_skill_system.get_hero_skill_rows(current_hero_id):
		var ss_row = HBoxContainer.new()
		ss_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ss_info = Label.new()
		if int(r["cost"]) < 0:
			ss_info.text = "【副业】%s  Lv.%d/%d  (资质+%d)  已满级" % [r["name"], r["level"], r["max"], r["level"]]
		else:
			ss_info.text = "【副业】%s  Lv.%d/%d  (资质+%d)  需%d%s" % [r["name"], r["level"], r["max"], r["level"], r["cost"], r["currency"]]
		ss_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ss_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ss_info.clip_text = true
		ss_info.custom_minimum_size.x = 240
		ss_row.add_child(ss_info)
		var ss_btn_box = VBoxContainer.new()
		ss_btn_box.custom_minimum_size = Vector2(70, 0)
		ss_btn_box.add_theme_constant_override("separation", 3)
		var ss_btn_single = Button.new()
		ss_btn_single.text = "升级"
		ss_btn_single.custom_minimum_size = Vector2(70, 24)
		ss_btn_single.add_theme_font_size_override("font_size", 12)
		ss_btn_single.disabled = int(r["cost"]) < 0
		ss_btn_single.pressed.connect(on_side_sys_upgrade.bind(str(r["key"]), "single"))
		ss_btn_box.add_child(ss_btn_single)
		var ss_btn_bulk = Button.new()
		ss_btn_bulk.text = "一键升级"
		ss_btn_bulk.custom_minimum_size = Vector2(70, 24)
		ss_btn_bulk.add_theme_font_size_override("font_size", 12)
		ss_btn_bulk.disabled = int(r["cost"]) < 0
		ss_btn_bulk.pressed.connect(on_side_sys_upgrade.bind(str(r["key"]), "bulk"))
		ss_btn_box.add_child(ss_btn_bulk)
		ss_row.add_child(ss_btn_box)
		list.add_child(ss_row)
	
	# 【新增】虫师副业技能（促织园虫书Lv≥1激活后获得同名技能，纯资质；上限=虫书等级×10，每级资质=消耗资质丹=星级）
	for s in data.cuzhi_system.get_hero_side_skills(current_hero_id):
		var side_row = HBoxContainer.new()
		side_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var side_info = Label.new()
		side_info.text = "【虫师】%s  Lv.%d/%d  (资质+%d)  需%d资质丹" % [s.name, s.level, s.max_level, s.level * s.star, s.star]
		side_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		side_info.clip_text = true
		side_info.custom_minimum_size.x = 80
		side_row.add_child(side_info)

		var side_btn_box = VBoxContainer.new()
		side_btn_box.custom_minimum_size = Vector2(70, 0)
		side_btn_box.add_theme_constant_override("separation", 3)

		var side_btn_single = Button.new()
		side_btn_single.text = "升级"
		side_btn_single.custom_minimum_size = Vector2(70, 24)
		side_btn_single.add_theme_font_size_override("font_size", 12)
		side_btn_single.pressed.connect(on_side_skill_upgrade.bind(s.idx, "single"))
		side_btn_box.add_child(side_btn_single)

		var side_btn_bulk = Button.new()
		side_btn_bulk.text = "一键升级"
		side_btn_bulk.custom_minimum_size = Vector2(70, 24)
		side_btn_bulk.add_theme_font_size_override("font_size", 12)
		side_btn_bulk.pressed.connect(on_side_skill_upgrade.bind(s.idx, "bulk"))
		side_btn_box.add_child(side_btn_bulk)

		side_row.add_child(side_btn_box)
		list.add_child(side_row)

# 【v4新增】填充占位页（服装/光环待开发，后续做功能时换成对应的 _fill_xxx_tab）
func _fill_placeholder_tab(list):
	var lbl = Label.new()
	lbl.text = "敬请期待"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(lbl)

# 【服装系统】填充「服装」页：已解锁服装的服装技能（资质丹升级，仅升基础等级，上限200；额外等级靠重复兑换）
func _fill_costume_tab(list):
	var cs = data.costume_system
	var has_any = false
	for cfg in cs.get_hero_costume_cfgs(current_hero_id):
		var cos_id = cfg.get("id", "")
		if not cs.is_hero_cos_unlocked(current_hero_id, cos_id): continue
		has_any = true
		var st = cs.get_hero_cos_state(current_hero_id, cos_id)
		var base = int(st.get("base", 1))
		var extra = int(st.get("extra", 0))
		var max_lv = int(cs._settings().get("skill_max_level", 200))
		var apt = cs.get_cos_skill_aptitude(current_hero_id, cos_id)
		var cost = cs.get_cos_skill_cost(cfg.get("quality", "素装"))  # 【改】传品质取固定消耗（原传 base 等级，永远显示2）

		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var info = Label.new()
		# 显示 基础+额外 两级：资质丹只能升基础（≤200），额外等级由重复兑换获得
		info.text = "【%s】%s  Lv.%d+%d  资质+%d  需%d资质丹" % [cfg.get("quality", ""), cfg.get("name", cos_id), base, extra, apt, cost]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.clip_text = true
		info.custom_minimum_size.x = 380
		row.add_child(info)

		var btn_box = VBoxContainer.new()
		btn_box.custom_minimum_size = Vector2(70, 0)
		btn_box.add_theme_constant_override("separation", 3)
		var single_btn = Button.new()
		single_btn.text = "升级"
		single_btn.custom_minimum_size = Vector2(70, 24)
		single_btn.add_theme_font_size_override("font_size", 12)
		single_btn.disabled = base >= max_lv
		single_btn.pressed.connect(_on_cos_skill_upgrade.bind(cos_id, "single"))
		btn_box.add_child(single_btn)
		var bulk_btn = Button.new()
		bulk_btn.text = "一键升级"
		bulk_btn.custom_minimum_size = Vector2(70, 24)
		bulk_btn.add_theme_font_size_override("font_size", 12)
		bulk_btn.disabled = base >= max_lv
		bulk_btn.pressed.connect(_on_cos_skill_upgrade.bind(cos_id, "bulk"))
		btn_box.add_child(bulk_btn)
		row.add_child(btn_box)
		list.add_child(row)
	if not has_any:
		var lbl = Label.new()
		lbl.text = "暂未解锁服装（点左侧【服装】按钮兑换）"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)

# 【服装系统】服装技能升级回调
func _on_cos_skill_upgrade(cos_id: String, mode: String):
	var res = data.costume_system.upgrade_cos_skill(current_hero_id, cos_id, mode)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "无法升级"))
		return
	update_hero_panel()   # 资质变化，面板对账
	c.update_all_ui()
	c.update_bag_list()

# 【服装系统】填充「光环」页：已解锁服装的同名光环技能（玉璜升级；上限=min(100, 服装总等级×10)）
func _fill_halo_tab(list):
	var cs = data.costume_system
	var my_cat = data.heroes[current_hero_id].get("category", "")
	var has_any = false
	for cfg in cs.get_hero_costume_cfgs(current_hero_id):
		var cos_id = cfg.get("id", "")
		if not cs.is_hero_cos_unlocked(current_hero_id, cos_id): continue
		has_any = true
		var st = cs.get_hero_cos_state(current_hero_id, cos_id)
		var lv = int(st.get("halo", 0))
		var cap = cs.get_halo_cap(current_hero_id, cos_id)
		var cost = cs.get_halo_cost(lv + 1)

		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var info = Label.new()
		# 效果：所有同类型门客资质+1/级（含自身）
		info.text = "【光环】%s  Lv.%d/%d  【%s】类门客资质+%d  需%d玉璜" % [cfg.get("name", cos_id), lv, cap, my_cat, lv, cost]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.clip_text = true
		info.custom_minimum_size.x = 380
		row.add_child(info)

		var btn_box = VBoxContainer.new()
		btn_box.custom_minimum_size = Vector2(70, 0)
		btn_box.add_theme_constant_override("separation", 3)
		var single_btn = Button.new()
		single_btn.text = "升级"
		single_btn.custom_minimum_size = Vector2(70, 24)
		single_btn.add_theme_font_size_override("font_size", 12)
		single_btn.disabled = lv >= cap
		single_btn.pressed.connect(_on_halo_upgrade.bind(cos_id, "single"))
		btn_box.add_child(single_btn)
		var bulk_btn = Button.new()
		bulk_btn.text = "一键升级"
		bulk_btn.custom_minimum_size = Vector2(70, 24)
		bulk_btn.add_theme_font_size_override("font_size", 12)
		bulk_btn.disabled = lv >= cap
		bulk_btn.pressed.connect(_on_halo_upgrade.bind(cos_id, "bulk"))
		btn_box.add_child(bulk_btn)
		row.add_child(btn_box)
		list.add_child(row)
	if not has_any:
		var lbl = Label.new()
		lbl.text = "暂未解锁光环（解锁服装后获得同名光环技能）"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)

# 【服装系统】光环升级回调（同类门客资质都变化，需全局对账）
func _on_halo_upgrade(cos_id: String, mode: String):
	var res = data.costume_system.upgrade_halo(current_hero_id, cos_id, mode)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "无法升级"))
		return
	update_hero_panel()
	c.update_all_ui()
	c.update_bag_list()

# 【新增】促织按钮点击：已装备弹操作面板，未装备弹选择器
func _on_cuzhi_btn_clicked():
	var equipped = data.cuzhi_system.get_equipped_cricket(current_hero_id)
	if equipped != "":
		_show_cuzhi_action_panel(equipped)
	else:
		_show_cuzhi_selector()

# 【新增】促织选择器：列出所有已拥有的无双/极无双促织
func _show_cuzhi_selector():
	# 【修复】立即删除旧选择器，避免同名冲突
	_close_cuzhi_selector()
	
	var panel = c._create_base_popup("选择促织装备", Vector2(460, 400))
	panel.name = "CuzhiSelector"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	var crickets = data.cuzhi_system.get_equipable_crickets()
	var has_any = false
	for info in crickets:
		var cid = info.id
		var cdata = info.data
		var btn = Button.new()
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var equip_level = info.equip_level
		var max_level = data.cuzhi_system.get_equip_max_level(cid)
		var equipped_hero = data.cuzhi_system.get_hero_by_cricket(cid)
		
		var status = ""
		if equipped_hero == current_hero_id:
			status = " [当前装备]"
			btn.disabled = true
		elif equipped_hero != "" and data.heroes.has(equipped_hero):
			status = " [%s已装备]" % data.heroes[equipped_hero].name
			btn.disabled = true
		
		var q_name = data.cuzhi_system.get_quality_name(int(cdata.quality))
		btn.text = "【%s】%s 装备Lv.%d/%d%s" % [cdata.name, q_name, equip_level, max_level, status]
		
		if not btn.disabled:
			btn.pressed.connect(_on_cuzhi_equipped.bind(cid))
		list.add_child(btn)
		has_any = true
	
	if not has_any:
		var empty = Label.new()
		empty.text = "暂无可装备促织（需拥有无双或极.无双促织）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): _close_cuzhi_selector())
	vbox.add_child(cancel)
	
	c.add_child(panel)

# 【新增】选择促织后装备
func _on_cuzhi_equipped(cid: String):
	data.cuzhi_system.equip_cricket(current_hero_id, cid)
	_close_cuzhi_selector()
	update_hero_panel()
	c.update_all_ui()

# 【新增】促织操作面板：显示信息 + 升级 + 替换/卸下/回收
func _show_cuzhi_action_panel(cid: String):
	var cdata = data.cuzhi_system.get_cricket_data(cid)
	if cdata.is_empty(): return
	
	# 【修复】立即删除旧面板，彻底避免同名节点冲突导致关闭按钮失效
	_close_cuzhi_panel()
	
	var panel = c._create_base_popup("促织装备", Vector2(420, 560))
	panel.name = "CuzhiActionPanel"
	var vb = panel.get_child(0)
	
	# 促织信息 + 当前材料数量
	var info_lbl = Label.new()
	info_lbl.name = "CuzhiInfoLbl"
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var q_name = data.cuzhi_system.get_quality_name(int(cdata.quality))
	var equip_level = data.cuzhi_system.get_equip_level(cid)
	var max_level = data.cuzhi_system.get_equip_max_level(cid)
	var apt = data.cuzhi_system.get_equip_aptitude_per_level(cid)
	# 【修复】显示当前拥有的材料数量
	var bf_have = data.items.get("beast_fruit", 0)
	var jh_have = data.items.get("cuzhi_jinghua", 0)
	info_lbl.text = "【%s】%s\n装备等级：Lv.%d / %d\n每级资质+%d\n拥有：珍兽果 %d  |  促织精华 %d" % [
		cdata.name, q_name, equip_level, max_level, apt, bf_have, jh_have
	]
	vb.add_child(info_lbl)
	
	# 升级区
	var can_up = data.cuzhi_system.can_upgrade_equip(cid)
	if can_up:
		var cost_bf = data.cuzhi_system.get_equip_cost_beast_fruit(cid)
		var cost_jh = data.cuzhi_system.get_equip_cost_jinghua(cid)
		
		# 勾选框（互斥）
		var check_box = HBoxContainer.new()
		check_box.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(check_box)
		
		var check_bf = CheckBox.new()
		check_bf.name = "CheckBeastFruit"
		check_bf.text = "珍兽果(%d)" % cost_bf
		# 【修复】根据上次选择恢复勾选状态
		check_bf.button_pressed = not _cuzhi_last_use_jinghua
		check_box.add_child(check_bf)
		
		var check_jh = CheckBox.new()
		check_jh.name = "CheckJinghua"
		check_jh.text = "促织精华(%d)" % cost_jh
		check_jh.button_pressed = _cuzhi_last_use_jinghua
		check_box.add_child(check_jh)
		
		# 互斥逻辑：必须勾选一个且只能勾选一个 + 记录选择
		check_bf.toggled.connect(func(pressed):
			if pressed:
				check_jh.button_pressed = false
				_cuzhi_last_use_jinghua = false
			elif not check_jh.button_pressed:
				check_bf.button_pressed = true
		)
		check_jh.toggled.connect(func(pressed):
			if pressed:
				check_bf.button_pressed = false
				_cuzhi_last_use_jinghua = true
			elif not check_bf.button_pressed:
				check_jh.button_pressed = true
		)
		
		# 升级按钮
		var up_btn = Button.new()
		up_btn.text = "升级"
		up_btn.custom_minimum_size = Vector2(100, 40)
		up_btn.pressed.connect(func():
			var use_jh = check_jh.button_pressed
			_do_cuzhi_upgrade(cid, use_jh)
		)
		vb.add_child(up_btn)
	else:
		var limit_lbl = Label.new()
		limit_lbl.text = "已达等级上限（需提升促织军衔以解锁更高等级）"
		limit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		limit_lbl.add_theme_color_override("font_color", Color("#ff6666"))
		vb.add_child(limit_lbl)
	
	# 操作按钮行
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)
	
	var replace_btn = Button.new()
	replace_btn.text = "替换"
	replace_btn.pressed.connect(func():
		_close_cuzhi_panel()
		_show_cuzhi_selector()
	)
	btn_row.add_child(replace_btn)
	
	var unequip_btn = Button.new()
	unequip_btn.text = "卸下"
	unequip_btn.pressed.connect(func():
		data.cuzhi_system.unequip_cricket(current_hero_id)
		_close_cuzhi_panel()
		update_hero_panel()
		c.update_all_ui()
	)
	btn_row.add_child(unequip_btn)
	
	var recycle_btn = Button.new()
	recycle_btn.text = "回收"
	recycle_btn.pressed.connect(func():
		_do_cuzhi_recycle(cid)
	)
	btn_row.add_child(recycle_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func(): _close_cuzhi_panel())
	btn_row.add_child(close_btn)
	
	c.add_child(panel)

# 【新增】执行促织装备升级
func _do_cuzhi_upgrade(cid: String, use_jinghua: bool):
	# 【修复】记录本次消耗类型，下次打开面板时保持勾选
	_cuzhi_last_use_jinghua = use_jinghua
	
	var res = data.cuzhi_system.upgrade_equip(cid, use_jinghua)
	if res.ok:
		c._show_stage_hint("升级成功！当前等级 Lv.%d" % res.new_level)
		_close_cuzhi_panel()
		_show_cuzhi_action_panel(cid)
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()
	else:
		c._show_stage_hint(res.get("reason", "升级失败"))

# 【新增】执行促织装备回收
func _do_cuzhi_recycle(cid: String):
	var res = data.cuzhi_system.recycle_equip(cid)
	if res.ok:
		c._show_stage_hint("回收成功！返还促织精华×%d" % res.return_jinghua)
		_close_cuzhi_panel()
		# 【修复】回收后促织仍装备但等级重置为1，刷新门客面板显示
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()
	else:
		c._show_stage_hint(res.get("reason", "回收失败"))

# 【促织装备】从场景树移除并延迟删除（避免信号中断+避免同名冲突）
func _close_cuzhi_panel():
	if c.has_node("CuzhiActionPanel"):
		var old = c.get_node("CuzhiActionPanel")
		c.remove_child(old)   # 立即从树移除：视觉上关闭+名字释放
		old.queue_free()      # 延迟释放内存：信号发完再死，不崩溃

func _close_cuzhi_selector():
	if c.has_node("CuzhiSelector"):
		var old = c.get_node("CuzhiSelector")
		c.remove_child(old)
		old.queue_free()


# ============ 【新增】守护灵面板 ============

func _on_guardian_btn_clicked():
	_show_guardian_panel()

# 【新增】打开守护灵操作面板（弹窗）
func _show_guardian_panel():
	# 关闭旧面板防同名冲突
	if c.has_node("GuardianPanel"):
		var old = c.get_node("GuardianPanel")
		c.remove_child(old)
		old.queue_free()
	
	var vw = c.get_viewport_rect().size
	var panel = c._create_base_popup("守护灵", Vector2(min(vw.x - 40, 560), min(vw.y - 80, 720)))
	panel.name = "GuardianPanel"
	panel.z_index = 30
	c.add_child(panel)
	
	var vb = panel.get_child(0)
	
	# 确保初始化
	data.guardian_system.init_guardian(current_hero_id)
	var gs = data.guardian_spirits.get(current_hero_id, {})
	if gs.is_empty():
		c._show_stage_hint("该门客没有守护灵")
		return
	
	# 等级与加成信息
	var level_lbl = Label.new()
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cap = data.guardian_system.get_level_cap(current_hero_id)
	if cap < 6000:
		level_lbl.text = "守护灵等级：Lv.%d / %d（阶段上限）" % [gs.level, cap]
	else:
		level_lbl.text = "守护灵等级：Lv.%d / 6000" % gs.level
	level_lbl.add_theme_font_size_override("font_size", 18)
	level_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	vb.add_child(level_lbl)
	
	var bonus_lbl = Label.new()
	bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var apt = data.get_hero_guardian_aptitude(current_hero_id)
	var pct = data.get_hero_guardian_percent(current_hero_id)
	bonus_lbl.text = "资质+%d  |  赚钱+%.0f%%" % [apt, pct * 100]
	vb.add_child(bonus_lbl)
	
	# 阶段列表（滚动）
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	
	for i in range(data.guardian_system.PHASES.size()):
		var phase = data.guardian_system.PHASES[i]
		var full = data.guardian_system.is_phase_full(current_hero_id, i)
		var unlocked = data.guardian_system.is_phase_unlocked(current_hero_id, i)
		
		
		var info = Label.new()
		var status_text = ""
		if full:
			status_text = "【已注满】"
			info.add_theme_color_override("font_color", Color("#ffd700"))   # 【新增】金色点亮
		elif unlocked:
			status_text = "【已解锁】"
		else:
			status_text = "【未解锁】"
			info.add_theme_color_override("font_color", Color("#888888"))   # 【新增】灰色未解锁
		
		info.text = "%s %s  赚钱+%.0f%%  技能：%s(+%d/级)" % [
			phase.name, status_text, phase.income_pct * 100, phase.skill_name, phase.skill_apt
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(info)
	
	# 注灵区
	var cost = data.guardian_system.get_level_up_cost(gs.level)
	var has_yulin = data.items.get("yulin_jue", 0)
	
	var up_box = HBoxContainer.new()
	up_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(up_box)
	
	var up_btn = Button.new()
	up_btn.text = "注灵\n%d/%d" % [has_yulin, cost]
	up_btn.custom_minimum_size = Vector2(120, 50)
	up_btn.pressed.connect(_on_guardian_level_up)
	up_box.add_child(up_btn)
	
	var batch_check = CheckBox.new()
	batch_check.text = "十连"
	batch_check.button_pressed = _guardian_batch   # 【新增】恢复上次勾选状态
	batch_check.toggled.connect(func(pressed): _guardian_batch = pressed)  # 【新增】记录变化
	up_box.add_child(batch_check)
	
	# 【改】幻化区：一个按钮打开独立弹窗，避免面板挤出去
	var avatar_btn = Button.new()
	avatar_btn.text = "幻化形象"
	avatar_btn.custom_minimum_size = Vector2(120, 40)
	avatar_btn.pressed.connect(_show_guardian_avatar_popup)
	vb.add_child(avatar_btn)
	
	# 关闭
	c._add_ok_button(vb, func():
		if c.has_node("GuardianPanel"):
			var old = c.get_node("GuardianPanel")
			c.remove_child(old)
			old.queue_free()
	, "关闭")

# 【新增】注灵升级
func _on_guardian_level_up():
	var batch = false
	if c.has_node("GuardianPanel"):
		var panel = c.get_node("GuardianPanel")
		# 在面板子节点中找十连勾选框
		for child in panel.get_child(0).get_children():
			if child is HBoxContainer:
				for c2 in child.get_children():
					if c2 is CheckBox and c2.text == "十连":
						batch = c2.button_pressed
						break
	
	var upgraded = data.guardian_system.level_up(current_hero_id, batch)
	if upgraded > 0:
		_show_guardian_panel()  # 刷新面板
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【改】切换幻化后同步刷新弹窗（如果打开着）
func _on_guardian_avatar_selected(avatar_id: String):
	data.guardian_system.set_avatar(current_hero_id, avatar_id)
	_show_guardian_panel()  # 刷新主面板
	if c.has_node("GuardianAvatarPopup"):
		_show_guardian_avatar_popup()  # 刷新幻化弹窗
	update_hero_panel()
	c.update_all_ui()

# 【改】解锁幻化后同步刷新弹窗
func _on_guardian_avatar_unlock(avatar_id: String):
	var res = data.guardian_system.unlock_avatar(current_hero_id, avatar_id)
	if res:
		_show_guardian_panel()
		if c.has_node("GuardianAvatarPopup"):
			_show_guardian_avatar_popup()
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()
	else:
		c._show_stage_hint("道具不足，无法解锁")

# 【新增】守护灵技能升级回调
func _on_guardian_skill_upgrade(skill_idx: int, mode: String):
	var upgraded = data.guardian_system.upgrade_skill(current_hero_id, skill_idx, mode == "bulk")
	if upgraded > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【新增】打开幻化形象选择弹窗（从守护灵面板独立出来，避免内容过多挤出去）
func _show_guardian_avatar_popup():
	if c.has_node("GuardianAvatarPopup"):
		var old = c.get_node("GuardianAvatarPopup")
		c.remove_child(old)
		old.queue_free()
	
	var vw = c.get_viewport_rect().size
	var popup = c._create_base_popup("幻化形象", Vector2(min(vw.x - 40, 480), min(vw.y - 80, 600)))
	popup.name = "GuardianAvatarPopup"
	popup.z_index = 35  # 高于 GuardianPanel(30)
	c.add_child(popup)
	
	var vb = popup.get_child(0)
	
	data.guardian_system.init_guardian(current_hero_id)
	var gs = data.guardian_spirits.get(current_hero_id, {})
	
	for av in data.guardian_system.AVATARS:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var info = Label.new()
		var has_unlocked = gs.avatars.get(av.id, false)
		var is_current = gs.get("avatar", "mingling") == av.id
		var item_name = ""
		if av.unlock_item != "" and data.ITEM_CONFIG.has(av.unlock_item):
			item_name = "（需%s）" % data.ITEM_CONFIG[av.unlock_item].name
		
		if is_current:
			info.text = "【%s】当前形象" % av.name
			info.add_theme_color_override("font_color", Color("#ffd700"))
		elif has_unlocked:
			info.text = "【%s】已解锁" % av.name
		else:
			var have = data.items.get(av.unlock_item, 0)
			info.text = "【%s】%s %d/100" % [av.name, item_name, have]   # 【改】显示拥有/需要
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(info)
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(80, 32)
		if is_current:
			btn.text = "使用中"
			btn.disabled = true
		elif has_unlocked:
			btn.text = "幻化"
			btn.pressed.connect(_on_guardian_avatar_selected.bind(av.id))
		else:
			btn.text = "解锁"
			btn.pressed.connect(_on_guardian_avatar_unlock.bind(av.id))
		row.add_child(btn)
		vb.add_child(row)
	
	c._add_ok_button(vb, func():
		if c.has_node("GuardianAvatarPopup"):
			var old = c.get_node("GuardianAvatarPopup")
			c.remove_child(old)
			old.queue_free()
	, "关闭")


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
	
	var t_cfg = data.token_system.get_token_cfg(current_hero_id)
	if t_cfg.is_empty(): return
	
	var popup = c._create_base_popup("【信物】%s" % t_cfg.get("token_name", "信物"), Vector2(440, 560))
	popup.name = "TokenPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	
	# ── 信物技能信息（等级/效果/消耗/拥有数）──
	var skill_lbl = Label.new()
	skill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_lbl.text = "【%s】Lv.%d（无上限）\n每级+%d资质（%s与羁绊门客）\n每级消耗%d【%s】\n拥有：%d" % [
		t_cfg.get("skill_name", "信物技能"), data.token_system.get_level(current_hero_id),
		int(t_cfg.get("aptitude_per_level", 3)), data.heroes[current_hero_id].name,
		int(t_cfg.get("cost_per_level", 600)), t_cfg.get("token_name", "信物"),
		data.items.get(t_cfg.get("cost_item", ""), 0)
	]
	vb.add_child(skill_lbl)
	
	# ── 升级区（十连勾选记忆在类变量 _token_batch，升级/重建不清）──
	var up_box = HBoxContainer.new()
	up_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(up_box)
	var up_btn = Button.new()
	up_btn.custom_minimum_size = Vector2(130, 48)
	up_btn.pressed.connect(func():
		var lv = data.token_system.get_level(current_hero_id)
		data.token_system.upgrade(current_hero_id, _token_batch)
		if data.token_system.get_level(current_hero_id) > lv:
			_show_token_panel()   # 重建刷新面板（勾选状态存类变量，不会丢）
			update_hero_panel()   # 资质变化，门客面板对账
			c.update_all_ui()
			c.update_bag_list()
	)
	up_box.add_child(up_btn)
	var batch_check = CheckBox.new()
	batch_check.text = "十连"
	batch_check.button_pressed = _token_batch   # 【新增】恢复上次勾选状态
	batch_check.toggled.connect(func(pressed):
		_token_batch = pressed   # 【新增】记录勾选变化
		# 勾选切换时刷新按钮上的消耗数字（单级↔十连总价）
		up_btn.text = data.token_system.get_upgrade_btn_text(current_hero_id, _token_batch)
	)
	up_box.add_child(batch_check)
	up_btn.text = data.token_system.get_upgrade_btn_text(current_hero_id, _token_batch)
	
	# ── 羁绊绑定区：每格显示 未解锁(灰)/未绑定/已绑定，按解锁等级排序展示 ──
	var binds = data.token_system.get_binds(current_hero_id)
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
		if not data.token_system.is_bind_unlocked(current_hero_id, idx):
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
				data.token_system.unbind(current_hero_id, idx)
				_show_token_panel()   # 重建刷新
				update_hero_panel()
				c.update_all_ui()
			)
			row.add_child(unbind_btn)
	
	# 羁绊效果说明（读配置，不写死数值）
	var hint_lbl = Label.new()
	hint_lbl.text = "绑定后：该门客赚钱+%d%%\n%s资质+其总资质%d%%" % [
		int(float(t_cfg.get("bind_income_pct", 0.10)) * 100),
		data.heroes[current_hero_id].name,
		int(float(t_cfg.get("owner_aptitude_share", 0.01)) * 100)
	]
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_color_override("font_color", Color("#a89ec7"))
	vb.add_child(hint_lbl)
	
	c._add_ok_button(vb, func():
		if c.has_node("TokenPanel"):
			var old = c.get_node("TokenPanel")
			c.remove_child(old)
			old.queue_free()
	, "关闭")

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
	
	# ── 契约信息：等级/转化%/当前赚速/下一级资质需求 ──
	var info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "契约 %d级（转化挚友提供赚钱的%d%%）\n当前：+%s赚速\n下级需求：技能栏资质 %d / %d" % [
		lv, int(lv * 0.1),
		c.format_number(tsys.get_contract_income(current_hero_id)),
		apt, next_req
	]
	vb.add_child(info)
	
	# ── 升级按钮：不耗道具，技能栏资质够累计需求才可升 ──
	var up_btn = Button.new()
	up_btn.custom_minimum_size = Vector2(140, 40)
	up_btn.text = "契约升级"
	up_btn.disabled = apt < next_req   # 资质不够按钮置灰
	up_btn.pressed.connect(func():
		if data.token_system.upgrade_contract():
			_show_contract_panel()   # 重建刷新
			update_hero_panel()
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
				update_hero_panel()
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
	
	# 名额与算法说明
	var hint = Label.new()
	hint.text = "仙缘梦绕达到5/80/200/400级各+1个指定名额（共5个）\n挚友提供赚钱=对每个绑定门客的（固定值+门客基础赚速×百分比）之和"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#a89ec7"))
	vb.add_child(hint)
	
	c._add_ok_button(vb, func():
		if c.has_node("ContractPanel"):
			var old2 = c.get_node("ContractPanel")
			c.remove_child(old2)
			old2.queue_free()
	, "关闭")

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
			update_hero_panel()
			c.update_all_ui()
		)
		vb.add_child(btn)
	c._add_ok_button(vb, func():
		if c.has_node("ContractFriendSelector"):
			var old = c.get_node("ContractFriendSelector")
			c.remove_child(old)
			old.queue_free()
	, "关闭")

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
	var ids = data.token_system.get_bindable_heroes(current_hero_id)
	ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hid in ids:
		var btn = Button.new()
		# 【修】手机端：按钮改 PASS 让触摸滑动穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		var h = data.heroes[hid]
		btn.text = "【%s】Lv.%d  %s/秒" % [h.get("name", hid), h.get("level", 1), c.format_number(data.get_hero_income(hid))]
		btn.pressed.connect(func():
			var res = data.token_system.bind_hero(current_hero_id, idx, hid)
			if res.get("ok", false):
				_close_token_bind_selector()
				_show_token_panel()   # 重建信物面板显示新绑定
				update_hero_panel()
				c.update_all_ui()
			else:
				c._show_stage_hint(res.get("msg", "绑定失败"))
		)
		list.add_child(btn)
	
	if ids.is_empty():
		var empty = Label.new()
		empty.text = "暂无可绑定门客"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	c._add_ok_button(vb, func(): _close_token_bind_selector(), "取消")

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
	
	var f_cfg = data.fengzi_system.get_fengzi_cfg(current_hero_id)
	if f_cfg.is_empty(): return
	data.fengzi_system.sync_skills(current_hero_id)   # 打开前幂等同步一次技能/上限
	
	var popup = c._create_base_popup("【风姿】%s" % f_cfg.get("fengzi_name", "风姿"), Vector2(460, 620))
	popup.name = "FengziPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	var lv = data.fengzi_system.get_level(current_hero_id)
	var h = data.heroes[current_hero_id]
	var every = int(f_cfg.get("skill_unlock_every", 5))
	var skills: Array = f_cfg.get("skills", [])
	var unlock_all = skills.size() * every   # 全部解锁等级（8技能×5级=40）
	
	# ── 风姿信息（等级/效果/消耗/当前赚钱加成）──
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.text = "【%s】Lv.%d（无上限）\n每级+%d资质（%s）  当前赚钱+%d%%\n每级消耗%d【%s】  拥有：%d" % [
		f_cfg.get("fengzi_name", "风姿"), lv,
		int(f_cfg.get("aptitude_per_level", 6)), h.name,
		int(data.fengzi_system.get_income_pct(current_hero_id) * 100),
		int(f_cfg.get("cost_per_level", 600)),
		data.ITEM_CONFIG.get(f_cfg.get("cost_item", ""), {}).get("name", f_cfg.get("cost_item", "")),
		data.items.get(f_cfg.get("cost_item", ""), 0)
	]
	vb.add_child(info_lbl)
	
	# ── 升级区（十连勾选记忆在类变量 _fengzi_batch，升级/重建不清）──
	var up_box = HBoxContainer.new()
	up_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(up_box)
	var up_btn = Button.new()
	up_btn.custom_minimum_size = Vector2(130, 48)
	up_btn.pressed.connect(func():
		var before = data.fengzi_system.get_level(current_hero_id)
		data.fengzi_system.upgrade(current_hero_id, _fengzi_batch)
		if data.fengzi_system.get_level(current_hero_id) > before:
			_show_fengzi_panel()   # 重建刷新（勾选状态存类变量，不会丢）
			update_hero_panel()    # 资质/赚速变化，门客面板对账
			c.update_all_ui()
			c.update_bag_list()
	)
	up_box.add_child(up_btn)
	var batch_check = CheckBox.new()
	batch_check.text = "十连"
	batch_check.button_pressed = _fengzi_batch   # 【新增】恢复上次勾选状态
	batch_check.toggled.connect(func(pressed):
		_fengzi_batch = pressed   # 【新增】记录勾选变化
		# 勾选切换时刷新按钮上的消耗数字（单级↔十连总价）
		up_btn.text = data.fengzi_system.get_upgrade_btn_text(current_hero_id, _fengzi_batch)
	)
	up_box.add_child(batch_check)
	up_btn.text = data.fengzi_system.get_upgrade_btn_text(current_hero_id, _fengzi_batch)
	
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
	
	# ── 规则说明（读配置，不写死数值）──
	var hint_lbl = Label.new()
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_color_override("font_color", Color("#a89ec7"))
	hint_lbl.text = "每%d级解锁1个技能并+%d%%赚钱（%d级全部解锁）\n%d级后每%d级按顺序提升1个技能上限+%d（不再加赚钱）\n技能在门客面板【技能】页消耗资质丹升级" % [
		every, int(float(f_cfg.get("income_pct_per_unlock", 0.05)) * 100), unlock_all,
		unlock_all, int(f_cfg.get("cap_bonus_every", 5)), int(f_cfg.get("cap_bonus_amount", 10))
	]
	vb.add_child(hint_lbl)
	
	c._add_ok_button(vb, func():
		if c.has_node("FengziPanel"):
			var old = c.get_node("FengziPanel")
			c.remove_child(old)
			old.queue_free()
	, "关闭")


# 【新增】天赋按钮点击：打开天赋面板（默认【技能】页）
func _on_talent_btn_clicked():
	_show_talent_panel("skill")

# 【新增】天赋面板标签切换：关掉当前面板按新标签重建（按钮经 bind 传参，避开 GDScript 闭包捕获循环变量坑）
func _on_talent_tab_clicked(tab_id: String):
	if c.has_node("TalentPanel"):
		var old = c.get_node("TalentPanel")
		c.remove_child(old)
		old.queue_free()
	_show_talent_panel(tab_id)

# 【新增】天赋面板：顶部=精进区（公共，不随标签切换，同时加成天赋与技能）；下部标签页【天赋】/【技能】
# 重建刷新模式沿用信物/风姿面板惯例（remove_child+queue_free 防同名冲突）
func _show_talent_panel(tab_id: String = "skill"):
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	if c.has_node("TalentPanel"):
		var old = c.get_node("TalentPanel")
		c.remove_child(old)
		old.queue_free()
	data.talent_system.sync_skills(current_hero_id)   # 打开前幂等同步已解锁技能
	
	var popup = c._create_base_popup("【天赋】鬼斧神工", Vector2(460, 600))
	popup.name = "TalentPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	
	# ── 精进区（公共置顶：精进同时加成天赋与技能，不属于任一标签页）──
	_fill_talent_refine_area(vb)
	
	# ── 标签页切换：天赋 / 技能（选中金色高亮）──
	var tab_box = HBoxContainer.new()
	tab_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_box.add_theme_constant_override("separation", 16)
	vb.add_child(tab_box)
	for t in [["talent", "天赋"], ["skill", "技能"]]:
		var tbtn = Button.new()
		tbtn.text = t[1]
		tbtn.custom_minimum_size = Vector2(140, 36)
		if t[0] == tab_id:
			tbtn.add_theme_color_override("font_color", Color("#ffd700"))
		tbtn.pressed.connect(_on_talent_tab_clicked.bind(t[0]))
		tab_box.add_child(tbtn)
	
	if tab_id == "talent":
		# ── 独有天赋页：配置表未做好，占位 ──
		var tip = Label.new()
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.add_theme_color_override("font_color", Color("#888888"))
		tip.text = "独有天赋敬请期待"
		vb.add_child(tip)
	else:
		_fill_talent_skill_tab(vb)
	
	c._add_ok_button(vb, func():
		if c.has_node("TalentPanel"):
			var old2 = c.get_node("TalentPanel")
			c.remove_child(old2)
			old2.queue_free()
	, "关闭")

# 【新增】天赋精进区（面板顶部公共区）：当前星级/替换制加成/下一星要求与精进按钮
func _fill_talent_refine_area(vb):
	var h = data.heroes[current_hero_id]
	var ts = data.talent_system
	var star = ts.get_star(current_hero_id)
	var max_star = ts.get_max_star()
	var item_name = data.ITEM_CONFIG.get(ts.get_cost_item(), {}).get("name", ts.get_cost_item())
	
	# ── 当前星级信息：替换制加成（当前星级生效值，不累加）──
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if star > 0:
		var cur = ts.get_star_cfg(star)
		info_lbl.text = "【鬼斧神工】%d星（共%d星）\n固定赚钱 +%s/秒（替换制）  百分比赚钱 +%d%%（替换制）" % [
			star, max_star,
			c.format_number(int(cur.get("flat_income", 0))),
			int(float(cur.get("income_pct", 0.0)) * 100)
		]
	else:
		info_lbl.text = "【鬼斧神工】未精进（0星）\n精进获得固定赚钱+百分比赚钱（按当前星级替换，不累加）"
	vb.add_child(info_lbl)
	
	# ── 下一星要求 + 未满足红字 + 精进按钮（无十连：限制下基本不可能连升）──
	if star < max_star:
		var next = star + 1
		var cfg = ts.get_star_cfg(next)
		var check = ts.get_refine_check(current_hero_id)
		var req_lbl = Label.new()
		req_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		req_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# 组合要求文案：门客等级 / N个门客M星（含本人） / 消耗门客帖
		var req_parts = ["门客达到%d级（当前%d）" % [int(cfg.get("require_level", 0)), int(h.level)]]
		var need_star = int(cfg.get("require_heroes_star", 0))
		var need_count = int(cfg.get("require_heroes_count", 0))
		if need_count > 0:
			req_parts.append("%d个门客达到%d星·含本人（当前%d）" % [need_count, need_star, ts.get_heroes_at_least_star(need_star)])
		req_parts.append("消耗%d【%s】（拥有%d）" % [int(cfg.get("cost", 0)), item_name, int(data.items.get(ts.get_cost_item(), 0))])
		req_lbl.text = "精进%d星要求：%s" % [next, "；".join(req_parts)]
		if not check.ok:
			req_lbl.add_theme_color_override("font_color", Color("#888888"))
		vb.add_child(req_lbl)
		if not check.ok:
			var reason_lbl = Label.new()
			reason_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reason_lbl.add_theme_color_override("font_color", Color("#ff6666"))
			reason_lbl.text = "未满足：" + "；".join(check.reasons)
			vb.add_child(reason_lbl)
		var refine_btn = Button.new()
		refine_btn.custom_minimum_size = Vector2(130, 48)
		refine_btn.text = "精进\n%d【%s】" % [int(cfg.get("cost", 0)), item_name]
		refine_btn.disabled = not check.ok
		refine_btn.pressed.connect(func():
			var res = ts.refine(current_hero_id)
			if res.get("ok", false):
				_show_talent_panel("skill")   # 重建刷新
				update_hero_panel()           # 星级/赚速变化，门客面板对账
				c.update_all_ui()
				c.update_bag_list()
		)
		vb.add_child(refine_btn)
	else:
		var full_lbl = Label.new()
		full_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		full_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		full_lbl.text = "已精进至满星（%d星）" % max_star
		vb.add_child(full_lbl)

# 【新增】天赋【技能】页内容：解锁技能列表 + 规则说明（精进区在面板顶部公共区）
func _fill_talent_skill_tab(vb):
	var h = data.heroes[current_hero_id]
	var ts = data.talent_system
	var star = ts.get_star(current_hero_id)
	var max_star = ts.get_max_star()
	
	# ── 解锁技能列表：已解锁显示当前等级（技能栏用资质丹升级），未解锁灰色显示星级门槛 ──
	var skill_title = Label.new()
	skill_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_title.text = "—— 解锁技能 ——"
	vb.add_child(skill_title)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 200)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for s in range(1, max_star + 1):
		var scfg = ts.get_star_cfg(s)
		var sname: String = scfg.get("skill_name", "")
		if sname == "": continue
		var apt = int(scfg.get("skill_aptitude_per_level", 1))
		var row = Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if s <= star:
			# 已解锁：在门客技能栏按名字找当前等级/上限
			var found = null
			for sk in h.aptitude_skills:
				if sk.name == sname:
					found = sk
					break
			var lv = int(found.level) if found != null else 0
			var cap = int(found.max_level) if found != null else 200
			row.text = "【%s】Lv.%d/%d  每级%d资质·%d资质丹" % [sname, lv, cap, apt, apt]
		else:
			row.text = "【%s】精进%d星解锁（每级%d资质）" % [sname, s, apt]
			row.add_theme_color_override("font_color", Color("#888888"))
		list.add_child(row)
	
	# ── 规则说明 ──
	var hint_lbl = Label.new()
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_color_override("font_color", Color("#a89ec7"))
	hint_lbl.text = "固定赚钱与百分比赚钱按当前星级替换（不累加）\n解锁技能在门客面板【技能】页消耗资质丹升级"
	vb.add_child(hint_lbl)
