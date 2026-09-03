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

var _token_batch: bool = false   # 【新增】信物十连勾选状态（面板生命周期内保持）

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
		c.get_node("HeroPanel/HeroName").text = "【%s】%s %s Lv.%d" % [h.name, h.category, quality_tag, h.level]
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
			token_btn.text = "【信物】%s" % t_cfg.get("token_name", "信物")
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
			promo_btn.text = "【%s】%d/%d" % [promo.get("name", "晋升"), promo.level, promo.max_level]
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
		return "升级\n%d" % int(ceil(100 * pow(1.05, h.level)))
	var max_lv = 50 + h.breakthrough_count * 50
	var total = 0
	for lv in range(h.level, min(h.level + 10, max_lv)):
		total += int(ceil(100 * pow(1.05, lv)))
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

func on_aptitude_skill_upgrade(skill_index: int, mode: String = "single"):
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var hero = data.heroes[current_hero_id]
	var skill = hero.aptitude_skills[skill_index]
	
	# 已满级
	if skill.level >= skill.max_level:
		return
	
	var cost_per_level = int(skill.get("aptitude_per_level", 1))  # 【新增】每级固定消耗=每级加的资质数
	var pill_count = data.items.get("aptitude_pill", 0)
	if pill_count < cost_per_level:
		return
	
	var levels_to_upgrade: int
	if mode == "single":
		levels_to_upgrade = 1
	else:  # bulk 一键升满
		var remaining = skill.max_level - skill.level
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

func on_promotion_upgrade(mode: String = "single"):
	var upgraded = data.upgrade_promotion(current_hero_id, mode == "bulk")
	if upgraded > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【v3新增】赋诗/晋升按钮点击：弹窗内进行升级（升级/一键），弹窗内数值随升级即时刷新
func _on_promo_btn_clicked():
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var h = data.heroes[current_hero_id]
	if not h.has("promotion"): return
	var promo = h.promotion
	var item_name = data.ITEM_CONFIG[promo.cost_item].name
	var popup = c._create_base_popup(promo.get("name", "晋升"), Vector2(360, 240), Vector2(396, 200))
	popup.name = "PromoPopup"
	var vb = popup.get_child(0)
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info_lbl)
	# 刷新弹窗内 进度/材料 文本（每次升级后调用；promo 是字典引用，值已随升级更新）
	var refresh = func():
		info_lbl.text = "进度：%d/%d\n%s：%d/%d" % [promo.level, promo.max_level, item_name, data.items.get(promo.cost_item, 0), promo.cost_amount]
	refresh.call()
	var single_btn = Button.new()
	single_btn.text = "升级"
	single_btn.pressed.connect(func():
		on_promotion_upgrade("single")   # 内部已调 update_hero_panel，会同步刷新 PromoBtn 文本
		refresh.call()
	)
	vb.add_child(single_btn)
	var bulk_btn = Button.new()
	bulk_btn.text = "一键升级"
	bulk_btn.pressed.connect(func():
		on_promotion_upgrade("bulk")
		refresh.call()
	)
	vb.add_child(bulk_btn)
	c._add_ok_button(vb, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

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
			income = data.get_hero_income(hero_id)
			status = "闲置"
			if h.assigned_shop != "" and data.shops.has(h.assigned_shop):
				status = "在【" + data.shops[h.assigned_shop].name + "】"
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
		if income_lbl:
			income_lbl.text = "%s/秒" % c.format_number(income)
		if status_lbl:
			status_lbl.text = status
	
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
func _fill_skill_tab(list):
	var h = data.heroes[current_hero_id]
	for i in range(h.aptitude_skills.size()):
		var skill = h.aptitude_skills[i]
		var apt_cost = int(skill.get("aptitude_per_level", 1))  # 【改】固定消耗=每级资质增量，替换原 1.05^(lv-1) 曲线
		
		var apt_row = HBoxContainer.new()
		apt_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var apt_info = Label.new()
		apt_info.text = "【资质】%s  Lv.%d/%d  需%d资质丹" % [skill.name, skill.level, skill.max_level, apt_cost]
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
	for i in range(h.shop_skills.size()):
		var skill = h.shop_skills[i]
		var current_percent = skill.base_percent + (skill.level - 1) * skill.percent_per_level
		var shop_cost = max(1, int(ceil(pow(1.05, skill.level - 1))))
		
		var shop_row = HBoxContainer.new()
		shop_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var shop_info = Label.new()
		shop_info.text = "【店铺】%s  Lv.%d/%d  (+%.0f%%)  需%d算盘" % [skill.name, skill.level, skill.max_level, current_percent * 100, shop_cost]
		shop_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shop_info.clip_text = true
		shop_info.custom_minimum_size.x = 80
		shop_row.add_child(shop_info)
		
		var shop_btn_box = VBoxContainer.new()
		shop_btn_box.custom_minimum_size = Vector2(70, 0)
		shop_btn_box.add_theme_constant_override("separation", 3)
		
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
