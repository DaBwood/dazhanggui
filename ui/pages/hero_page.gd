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

# ── 子模块（2026-09-25 架构批次B：面板拆分，防单文件膨胀）──
var promo   # HeroPanelPromo：晋升全家桶（赋诗/简单晋升/金兰/亲和/拜师/凤魁/转移/三家光环卡）
var token   # HeroPanelToken：信物+风姿面板

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var current_hero_id: String = ""

# 【v4新增】技能栏当前标签页："skill"技能 / "shop"副业 / "costume"服装 / "halo"光环（后两者待开发）
var current_skill_tab: String = "skill"

var _cuzhi_last_use_jinghua: bool = false   # 【促织装备】上次升级用的促织精华（true）还是珍兽果（false）
var _guardian_batch: bool = false   # 【新增】守护灵注灵十连勾选状态（面板生命周期内保持）
var _talent_tab: String = "talent"   # 【新增】天赋面板当前页签（类变量记忆：重建刷新/精进后不跳页）
# 【第35节】吃资质丹的技能统一抵扣勾选：true=百业经验（300×每级丹数/级），false=资质丹；四个页签共享记忆
var _use_baiye: bool = false
var _cos_chk_syncing: bool = false   # 【新增】2026-09-25 双货币勾选框互设守卫：true 时屏蔽 toggled 重入，防两回调纠偏死循环
# 【第35节】各页签当前选中技能索引（重建面板不清；满级沉底/技能数变化后自动回退）
var _sel_idx: Dictionary = {"skill": 0, "shop": 0, "costume": 0, "halo": 0}
# 【第35节】各页签按钮排滚动位置记忆（点按钮/升级触发重建时不跳回最左）
var _btn_scroll: Dictionary = {"skill": 0, "shop": 0, "costume": 0, "halo": 0}


# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data
	# 子模块实例化（回传本页引用：共享状态/渲染件经 hp.xxx 访问）
	promo = preload("res://ui/pages/hero_panel_promo.gd").new(self)
	token = preload("res://ui/pages/hero_panel_token.gd").new(self)

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
	# 【改】改 HBox 行：资质文本后加"?"小钮（门客属性构成弹窗入口，2026-09-25 用户拍板）
	var income_row = HBoxContainer.new()
	income_row.name = "HeroIncomeRow"
	income_row.position = Vector2(0, 50)
	income_row.size = Vector2(vw.x, 26)
	income_row.alignment = BoxContainer.ALIGNMENT_CENTER
	income_row.add_theme_constant_override("separation", 6)
	panel.add_child(income_row)
	var income_lbl = Label.new()
	income_lbl.name = "HeroIncome"
	income_row.add_child(income_lbl)
	var attr_btn = Button.new()
	attr_btn.name = "AttrInfoBtn"
	attr_btn.text = "?"
	attr_btn.custom_minimum_size = Vector2(26, 24)
	attr_btn.add_theme_font_size_override("font_size", 14)
	attr_btn.pressed.connect(_show_attr_breakdown)
	income_row.add_child(attr_btn)

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
	# 【改】品质四档全显示徽标（含优秀蓝档；条件 quality>0 → has("quality")）
	var quality_tag = ""
	if h.has("quality"):
		quality_tag = "[%s]" % HeroData.get_quality_name(h.quality)
	
	if c.has_node("HeroPanel/HeroName"):
		# 【新增】标题追加天赋星级（★×N；0星不显示）
		var star_txt = data.talent_system.get_star_text(current_hero_id)
		# 【改】copy_max_level 持有者（王昭君·宁胡和议/花木兰·替父从军）：显示有效等级=max(自身, 复制等级)，与赚钱口径一致
		var show_lv = int(h.level)
		var copy_lv = data.talent_system.get_copy_level(current_hero_id)
		if copy_lv > 0:
			show_lv = maxi(show_lv, copy_lv)
		c.get_node("HeroPanel/HeroName").text = "【%s】%s %s Lv.%d%s" % [h.name, h.category, quality_tag, show_lv, (" " + star_txt) if star_txt != "" else ""]
		# 【改】2026-09-24 门客名按品质着色（原为固定金色）：优秀蓝/卓越紫/传奇橙/无双红，与列表卡/图鉴同款
		c.get_node("HeroPanel/HeroName").add_theme_color_override("font_color", Color(HeroData.get_quality_color(int(h.get("quality", 0)))))
	if c.has_node("HeroPanel/HeroIncomeRow/HeroIncome"):   # 【改】资质行已改 HBox（带"?"钮），路径同步加层
		# 【改】口径对齐：门客个体=赚钱（全局汇总才叫赚速）
		c.get_node("HeroPanel/HeroIncomeRow/HeroIncome").text = "赚钱：%s/秒  资质：%d" % [c.format_number(income), total_aptitude]
	
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
		# 【改】2026-09-24 绑定兽（魅影兔）显示形态名+有效等级（自动满级兽=当前珍兽上限）
		beast_btn.text = "【%s】Lv.%d" % [data.beast_system.get_beast_display_name(beast_id), data.beast_system.get_beast_level(beast_id, beast_idx)]
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
	fish_btn.pressed.connect(c.show_view.bind("fish_equip", [current_hero_id]))
	
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
	# 【改】品质四档改造：无双档 2→3
	var is_wushuang = h.get("quality", 0) == 3
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
			token_btn.pressed.connect(token._on_token_btn_clicked)
		else:
			token_btn.visible = false
	
	# 【v3新增】赋诗/晋升按钮（右列上方）：有晋升内容的门客才显示，点击弹窗升级
	# 【改】2026-09-24 服装一键晋升（simple_promotion，解鲁/四郎）：集齐任一已解锁服装→红点，点击直接晋升，晋升后按钮消失
	var promo_btn = c.get_node("HeroPanel").get_node_or_null("PromoBtn")
	if promo_btn:
		for conn in promo_btn.pressed.get_connections():
			promo_btn.pressed.disconnect(conn.callable)
		var sp_cfg: Dictionary = h.get("simple_promotion", {})
		# 【改】2026-09-24 stages 道具分档（兰飞鸿）：还有未晋档位才显示；legacy 服装形式维持原判断
		var simple_ready: bool = false
		if not sp_cfg.is_empty():
			if sp_cfg.has("stages"):
				simple_ready = not data.hero_system.get_simple_promote_stage(current_hero_id).is_empty()
			else:
				simple_ready = int(h.get("quality", 0)) < int(sp_cfg.get("target_quality", 2))
		# 【新增】2026-09-25 凤魁（秦淮五艳）：选定前五人各出"凤魁"钮（确认选定）；选定后仅凤魁保留钮→凤魁页面
		var fk_now: bool = data.hero_system.get_fengkui_id() == current_hero_id
		var fk_candidate: bool = (not fk_now) and data.hero_system.is_wuyan(current_hero_id) \
			and int(h.get("quality", 0)) == 2 and data.hero_system.get_fengkui_id() == ""
		if fk_now or fk_candidate:
			promo_btn.text = "凤魁"
			promo_btn.visible = true
			promo_btn.pressed.connect(promo._on_fengkui_btn_clicked)
		elif simple_ready or h.has("promotion"):
			var promo_name: String = str(sp_cfg.get("name", "晋升")) if simple_ready else str(h.promotion.get("name", "晋升"))
			promo_btn.text = promo_name   # 【改】2026-09-24 按钮名=晋升玩法名（赋诗/落雁/军旅），去"赋诗晋升"特判
			promo_btn.visible = true
			# 红点：服装一键晋升条件满足才亮（● Label 节点查重复用，防 update_hero_panel 高频重入叠点）；赋诗分支维持原无红点
			var dot: Label = null
			for ch2 in promo_btn.get_children():
				if ch2 is Label and str(ch2.text) == "●":
					dot = ch2 as Label   # 【修】Node→Label 显式收窄（静态类型安全）
			if dot == null:
				dot = Label.new()
				dot.text = "●"
				promo_btn.add_child(dot)
			dot.visible = data.hero_system.can_simple_promote(current_hero_id) if simple_ready else false
			dot.anchor_left = 1.0
			dot.anchor_right = 1.0
			dot.anchor_top = 0.0
			dot.anchor_bottom = 0.0
			dot.offset_left = -18
			dot.offset_right = -2
			dot.offset_top = 2
			dot.offset_bottom = 18
			dot.add_theme_color_override("font_color", Color("#e74c3c"))
			dot.add_theme_font_size_override("font_size", 14)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if simple_ready:
				promo_btn.pressed.connect(promo._on_simple_promote_clicked)
			else:
				promo_btn.pressed.connect(promo._on_promo_btn_clicked)
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
	
	# 【新增】copy_max_level 持有者：真实等级不用手动升（等级随全门客最高复制），整个升级区隐藏
	# （突破按钮一并隐藏：突破要求真实等级到节点 50+突破×50，复制档升不了级永远点不亮，留死按钮更糟）
	var is_copy_holder = data.talent_system.get_copy_level(current_hero_id) > 0
	# 【改】复制档（王昭君宁胡和议/花木兰替父从军等）：升级位改天赋名按钮，点击弹天赋详情（2026-09-24 用户拍板）
	level_box.visible = true
	if is_copy_holder:
		batch_check.visible = false
		var ct: Dictionary = promo._get_copy_talent_info(current_hero_id)
		lv_btn.text = ct.get("name", "天赋详情")
		lv_btn.visible = true
		lv_btn.disabled = false
		for conn in lv_btn.pressed.get_connections():
			lv_btn.pressed.disconnect(conn.callable)
		lv_btn.pressed.connect(promo._on_copy_talent_btn_clicked)
	elif need_bt:
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
	# 【新增】2026-09-24 绑定兽（魅影兔）：隐藏替换/卸下按钮，只留培养（用户拍板）
	if data.get_beast_config(beast_id).get("locked", false):
		replace_btn.visible = false
		unequip_btn.visible = false
	
	
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
			# 【新增】2026-09-24 绑定兽双向锁死：非小舞门客不可选魅影兔；小舞已带绑定兽不可再选其他兽
			if cfg.get("locked", false) and str(cfg.get("bound_hero", "")) != current_hero_id:
				status = " [小舞专属]"
				btn.disabled = true
			elif data.heroes[current_hero_id].get("equipped_beast", "") != "" and data.get_beast_config(data.heroes[current_hero_id].get("equipped_beast", "")).get("locked", false):
				status = " [专属绑定]"
				btn.disabled = true
			
			# 【改】2026-09-24 绑定兽显示形态名+有效等级
			btn.text = "【%s】Lv.%d 资质+%d 加成+%.0f%%%s" % [data.beast_system.get_beast_display_name(beast_id), data.beast_system.get_beast_level(beast_id, i), apt, bonus * 100, status]
			
			if not btn.disabled:
				btn.pressed.connect(_on_equip_beast_to_hero.bind(beast_id, i))
			list.add_child(btn)
			has_beast = true
	
	if not has_beast:
		var empty = Label.new()
		empty.text = "暂无可装备珍兽"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	
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

# 【改】升级资质技能（勾选「百业经验」时从该门客个人池抵扣，每级=300×每级丹数；否则吃资质丹）
# 【第35节】bulk 语义=升级10次：最多10级，资源/上限不够时升剩余可升级数
func on_aptitude_skill_upgrade(skill_index: int, mode: String = "single"):
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	var hero = data.heroes[current_hero_id]
	var skill = hero.aptitude_skills[skill_index]

	# 已满级
	if skill.level >= skill.max_level:
		return

	# 【新增】2026-09-25 极·XX之道：技能带 cost_item 只吃对应职业之道书（不吃资质丹/百业经验）
	if skill.has("cost_item") and str(skill.get("cost_item", "")) != "":
		var book_id: String = str(skill.get("cost_item", ""))
		var cost_num: int = int(skill.get("cost_num", 300))
		var stock: int = int(data.items.get(book_id, 0))
		var can_up: int = 1 if mode == "single" else min(mini(floori(stock / float(cost_num)), skill.max_level - skill.level), 10)
		if can_up > 0:
			data.items[book_id] = stock - can_up * cost_num
			skill.level += can_up
			update_hero_panel()
			c.update_all_ui()
			c.update_bag_list()
		return

	var cost_per_level = int(skill.get("aptitude_per_level", 1))  # 每级固定消耗=每级加的资质数
	var remaining = skill.max_level - skill.level
	var levels_to_upgrade: int = 1 if mode == "single" else 0

	# 百业经验抵扣路径：池够升多少升多少（single=1级，bulk 封顶10级）
	if _use_baiye:
		var baiye_per_level: int = cost_per_level * data.hero_system.get_baiye_per_pill()
		if mode != "single":
			levels_to_upgrade = min(mini(floori(data.hero_system.get_baiye(current_hero_id) / float(baiye_per_level)), remaining), 10)
		if levels_to_upgrade > 0 and data.hero_system.spend_baiye_for_pills(current_hero_id, levels_to_upgrade * cost_per_level):
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
	else:  # bulk=升级10次：按每级N丹折算可升级数（float 除法防整数除法告警）
		levels_to_upgrade = min(mini(floori(pill_count / float(cost_per_level)), remaining), 10)

	if levels_to_upgrade > 0:
		data.items.aptitude_pill -= levels_to_upgrade * cost_per_level  # 扣 级数×每级N丹
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

# 【新增】虫师副业技能升级（促织园体系走 cuzhi_system；single=升1级，bulk=升级10次）
# 【第35节】支持百业经验抵扣（勾选状态共享 _use_baiye）
func on_side_skill_upgrade(skill_idx: int, mode: String = "single"):
	if data.cuzhi_system.upgrade_side_skill(current_hero_id, skill_idx, mode == "bulk", _use_baiye):
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

# 【新增】副业资质技能升级（side_skill_system；single=升1级，bulk=升级10次）【第35节】
func on_side_sys_upgrade(key: String, mode: String = "single"):
	if data.side_skill_system.upgrade(current_hero_id, key, mode) > 0:
		update_hero_panel()
		c.update_all_ui()
		c.update_bag_list()

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
			# 【改】copy_max_level 持有者列表同步显示有效等级（未拥有门客按配置原等级）
			var show_lv2 = int(h.level)
			if data.heroes.has(hero_id):
				var copy_lv2 = data.talent_system.get_copy_level(hero_id)
				if copy_lv2 > 0:
					show_lv2 = maxi(show_lv2, copy_lv2)
			name_lbl.text = "【%s】Lv.%d | %s" % [h.name, show_lv2, h.category]
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
	var unlocked = []   # 已解锁：[cell, 品质, 实时赚速]
	var locked = []     # 未解锁VIP门客：保持原相对顺序
	for cell in grid.get_children():
		if not cell is Button: continue
		# 与 update_hero_list 相同的 id 解析方式：去掉 _hero_locked / _hero 后缀
		var hero_id = cell.name.replace("_hero_locked", "").replace("_hero", "")
		if data.heroes.has(hero_id):
			var h: Dictionary = data.heroes[hero_id]
			unlocked.append([cell, int(h.get("quality", 0)), data.get_hero_income(hero_id)])
		else:
			locked.append(cell)
	# 【改】2026-09-24 排序口径：品质降序优先，同品质按实时赚速降序
	unlocked.sort_custom(func(a, b):
		if a[1] != b[1]: return a[1] > b[1]
		return a[2] > b[2])
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
	c.add_child(popup)

# 【v4新增】技能栏标签点击：记录当前标签页并刷新面板
func _on_skill_tab_clicked(tab_id: String):
	current_skill_tab = tab_id
	update_hero_panel()

# ============ 【第35节】技能栏统一框架：按钮排 + 详情区 ============
# 条目结构：{name, stars, is_max, info, pill(每级资质丹消耗,>0出抵扣勾选框对),
#           own_name+own=[消耗,库存](单一勾选框文案与数值，只用自身货币的技能),
#           on_single/on_bulk(Callable，构建时预绑定参数与模式，按钮直连)}

# 星级行：星级=每级增加的资质（非资质类技能默认1星）；最多显示5颗，超出部分从最左边开始变红
func _build_star_row(stars: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	var shown: int = clampi(stars, 1, 5)
	var overflow: int = maxi(stars - 5, 0)
	for i in range(shown):
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 11)
		if i < overflow:
			star.add_theme_color_override("font_color", Color("#e74c3c"))   # 溢出星级：从最左起红色
		else:
			star.add_theme_color_override("font_color", Color("#ffd700"))   # 金色
		box.add_child(star)
	return box

# 技能按钮：矩形，上=技能名，下=星级；已满级金色边框，选中蓝色边框
func _build_skill_button(sname: String, stars: int, is_max: bool, is_sel: bool, on_click: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 58)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS   # 穿透触摸滑动
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2c2844")
	style.set_corner_radius_all(4)
	if is_max:
		style.border_color = Color("#ffd700")
		style.set_border_width_all(2)
	elif is_sel:
		style.border_color = Color("#5aa9e6")
		style.set_border_width_all(2)
	else:
		style.border_color = Color("#4a4468")
		style.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = Color("#38325a")
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", style)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	btn.add_child(vb)
	var name_lbl := Label.new()
	name_lbl.text = sname
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(name_lbl)
	vb.add_child(_build_star_row(stars))
	btn.pressed.connect(on_click)
	return btn

# 按钮排：ScrollContainer 只包裹按钮排（横向滑动不影响下方详情区）
# 【热修】4.7 已移除 HScrollContainer/VScrollContainer，用 ScrollContainer + 滚动模式（同 game_controller 商铺地图先例）
func _render_skill_buttons(list: VBoxContainer, items: Array, sel: int, tab_id: String) -> void:
	var hscroll := ScrollContainer.new()
	hscroll.custom_minimum_size = Vector2(0, 66)
	hscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 【修】SHOW_NEVER=可滑动但永不显示滚动条（visible=false 会被 ScrollContainer 每次布局强制覆盖，无效）
	hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED      # 纵向锁死
	list.add_child(hscroll)   # 先入树（滚动条仍正常运作，value_changed 存档不受影响）
	# 滚动进度按页签记忆：滑动的每一帧都存档，重建（点按钮/升级）后 deferred 恢复，不跳回最左
	hscroll.get_h_scroll_bar().value_changed.connect(func(v):
		_btn_scroll[tab_id] = int(v))
	hscroll.set_deferred("scroll_horizontal", int(_btn_scroll.get(tab_id, 0)))
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	hscroll.add_child(btn_row)
	for i in range(items.size()):
		var it: Dictionary = items[i]
		btn_row.add_child(_build_skill_button(it["name"], it["stars"], it["is_max"], i == sel,
			_on_skill_btn_clicked.bind(tab_id, i)))

func _on_skill_btn_clicked(tab_id: String, idx: int):
	_sel_idx[tab_id] = idx
	update_hero_panel()
	# 【修】2026-09-25 凤魁弹窗技能卡点击：update_hero_panel 只重建门客面板层，凤魁弹窗需同步重建（否则点卡片详情区不刷新，未解锁卡看似无反应）
	if tab_id == "fengkui_skill" and c.has_node("FengkuiPanel"):
		promo._show_fengkui_panel("skill")
	if tab_id == "fengkui_wuyue" and c.has_node("FengkuiPanel"):
		promo._show_fengkui_panel("wuyue")

# 详情区：左=信息（技能名/等级/当前加成/下级数值），右=勾选框+升级+升级10次；已满级右侧全藏只盖红章
func _render_skill_detail(list: VBoxContainer, item: Dictionary) -> void:
	var detail_wrap := Control.new()
	detail_wrap.custom_minimum_size = Vector2(0, 108)
	detail_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 底色面板
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#232035")
	style.set_corner_radius_all(6)
	style.border_color = Color("#4a4468")
	style.set_border_width_all(1)
	bg.add_theme_stylebox_override("panel", style)
	detail_wrap.add_child(bg)
	# 内容行
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_top = 6
	row.offset_right = -10
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 12)
	detail_wrap.add_child(row)
	var info := Label.new()
	info.text = item["info"]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(info)
	var is_max: bool = bool(item["is_max"])
	# 已满级、或纯展示条目（no_action）：右侧什么都不显示，只盖红章（见底部）
	if not is_max and not item.get("no_action", false):
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 4)
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 【改】右侧整体垂直居中（道具文本+按钮不再偏上）
		row.add_child(right)
		# 勾选框：吃资质丹的技能=资质丹/百业经验互斥对（格式：货币名(消耗/库存)）
		# 单一货币技能不做勾选框，直接纯文本，避免灰框看起来像没选中
		if int(item.get("pill", 0)) > 0:
			var chk_col := VBoxContainer.new()   # 【改】两个勾选框竖向排列
			chk_col.add_theme_constant_override("separation", 2)
			right.add_child(chk_col)
			var per_level: int = int(item["pill"])
			var pill_stock: int = int(data.items.get("aptitude_pill", 0))
			var pool_stock: int = int(data.hero_system.get_baiye(current_hero_id))
			var chk_pill := CheckBox.new()
			var chk_baiye := CheckBox.new()   # 【修】2026-09-25 声明前置：GDScript lambda 不得引用后声明变量（parse error），原顺序 pill 回调引用 chk_baiye 报错
			chk_pill.text = "资质丹"   # 【改】数字拆独立 Label 后同排显示（2026-09-24）
			chk_pill.button_pressed = not _use_baiye
			chk_pill.add_theme_font_size_override("font_size", 12)
			chk_pill.toggled.connect(func(pressed):
				if _cos_chk_syncing: return   # 【修】2026-09-25 同步守卫：互设 button_pressed 会重入对端回调，无守卫则两回调互相纠偏死循环（栈溢出）
				if pressed:
					_use_baiye = false
					_cos_chk_syncing = true
					chk_baiye.button_pressed = false   # 真互斥：取消兄弟勾选（原实现只靠 update_hero_panel 重建同步，弹窗内不重建会双勾/脱节）
					_cos_chk_syncing = false
					update_hero_panel()
				elif _use_baiye:   # 互斥：不允许全不选
					_cos_chk_syncing = true
					chk_pill.button_pressed = true
					_cos_chk_syncing = false
			)
			chk_baiye.text = "百业经验"
			chk_baiye.button_pressed = _use_baiye
			chk_baiye.add_theme_font_size_override("font_size", 12)
			chk_baiye.toggled.connect(func(pressed):
				if _cos_chk_syncing: return   # 同步守卫（同上）
				if pressed:
					_use_baiye = true
					_cos_chk_syncing = true
					chk_pill.button_pressed = false   # 真互斥（同上）
					_cos_chk_syncing = false
					update_hero_panel()
				elif not _use_baiye:
					_cos_chk_syncing = true
					chk_baiye.button_pressed = true
					_cos_chk_syncing = false
			)
			# 【改】2026-09-24 勾选框与消耗数字同排：名字随选中变色，数字保持 _cost_color 红绿色
			var pill_row := HBoxContainer.new()
			pill_row.add_theme_constant_override("separation", 2)
			var pill_num_lbl := Label.new()
			pill_num_lbl.text = "(%d/%d)" % [per_level, pill_stock]
			pill_num_lbl.add_theme_color_override("font_color", _cost_color(pill_stock, per_level))
			pill_num_lbl.add_theme_font_size_override("font_size", 12)
			pill_row.add_child(chk_pill)
			pill_row.add_child(pill_num_lbl)
			chk_col.add_child(pill_row)
			var baiye_row := HBoxContainer.new()
			baiye_row.add_theme_constant_override("separation", 2)
			var baiye_num_lbl := Label.new()
			baiye_num_lbl.text = "(%d/%d)" % [per_level * data.hero_system.get_baiye_per_pill(), pool_stock]
			baiye_num_lbl.add_theme_color_override("font_color", _cost_color(pool_stock, per_level * data.hero_system.get_baiye_per_pill()))
			baiye_num_lbl.add_theme_font_size_override("font_size", 12)
			baiye_row.add_child(chk_baiye)
			baiye_row.add_child(baiye_num_lbl)
			chk_col.add_child(baiye_row)
		elif item.has("own"):
			var own: Array = item["own"]
			var own_lbl := Label.new()
			own_lbl.text = "%s %d/%d" % [item["own_name"], own[0], own[1]]
			own_lbl.add_theme_color_override("font_color", _cost_color(int(own[1]), int(own[0])))   # 【改】够升级绿/不够红（own=[消耗,库存]）
			own_lbl.add_theme_font_size_override("font_size", 13)
			own_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			right.add_child(own_lbl)
		# 【新增】可选"?"说明钮（光环.极档：升级钮上方，点击显示各门客对应技能等级需求）
		if item.has("on_hint"):
			var hbtn := Button.new()
			hbtn.text = "？"
			hbtn.custom_minimum_size = Vector2(84, 20)
			hbtn.add_theme_font_size_override("font_size", 12)
			hbtn.pressed.connect(item["on_hint"])
			right.add_child(hbtn)
		# 升级按钮：升级 / 升级10次（bulk 语义=最多10级）
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)
		right.add_child(btn_row)
		# 【新增】2026-09-24 免费门槛卡（师徒光环广结良缘/日进斗金）：无消耗，仅单个升级钮
		if item.get("free_action", false):
			var up_free := Button.new()
			up_free.text = "升级"
			up_free.custom_minimum_size = Vector2(84, 34)
			up_free.pressed.connect(item["on_single"])
			btn_row.add_child(up_free)
		else:
			# 【修】4.x bind 参数追加在调用参数后，链式 bind 顺序不可控；
			#       条目构建时预绑定 on_single/on_bulk（单 bind 顺序稳定），按钮直连
			var up1 := Button.new()
			up1.text = "升级"
			up1.custom_minimum_size = Vector2(84, 34)
			up1.pressed.connect(item["on_single"])
			btn_row.add_child(up1)
			var up10 := Button.new()
			up10.text = "升级10次"
			up10.custom_minimum_size = Vector2(84, 34)
			up10.pressed.connect(item["on_bulk"])
			btn_row.add_child(up10)
	# 已满级红章：盖在详情区上
	if is_max:
		var stamp := Label.new()
		stamp.text = "已满级"
		stamp.set_anchors_preset(Control.PRESET_CENTER_RIGHT)   # 【改】右侧中间
		stamp.offset_left = -28
		stamp.offset_right = -28
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.add_theme_font_size_override("font_size", 30)
		stamp.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 0.7))
		detail_wrap.add_child(stamp)
	list.add_child(detail_wrap)

# 页签渲染入口：满级技能沉底 + 选中索引回退 + 按钮排 + 详情区
func _render_skill_tab(list: VBoxContainer, items: Array, tab_id: String) -> void:
	if items.is_empty():
		var empty := Label.new()
		empty.text = "暂无可升级技能"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
		return
	# 满级沉底（稳定排序：不满级在前保持原相对顺序）
	items.sort_custom(func(a, b): return (1 if a["is_max"] else 0) < (1 if b["is_max"] else 0))
	# 选中索引回退（技能数变化/满级沉底后防越界）
	var sel: int = clampi(int(_sel_idx.get(tab_id, 0)), 0, items.size() - 1)
	_sel_idx[tab_id] = sel
	_render_skill_buttons(list, items, sel, tab_id)
	_render_skill_detail(list, items[sel])

# 【新增】消耗数字着色通用件（2026-09-24 用户拍板）：够升级绿 #7ee787 / 不够红 #ff6666
# 风姿/晋升/技能栏（资质丹·百业经验·副业货币·算盘·筹算值·伙伴币）所有"消耗/库存"文本共用
func _cost_color(have: int, need: int) -> Color:
	return Color("#7ee787") if have >= need else Color("#ff6666")

# 【第35节】填充「技能」页：资质技能 + 守护灵技能，统一按钮排+详情区（资质类格式：资质+X（下级+Y））
func _fill_skill_tab(list):
	var h = data.heroes[current_hero_id]
	var items: Array = []
	for i in range(h.aptitude_skills.size()):
		var skill = h.aptitude_skills[i]
		var per: int = int(skill.get("aptitude_per_level", 1))
		var is_max: bool = skill.level >= skill.max_level
		var info: String = "【%s】  Lv.%d/%d\n资质+%d" % [skill.name, skill.level, skill.max_level, skill.level * per]
		if is_max:
			info += "（已满级）"
		else:
			info += "（下级+%d）" % [(skill.level + 1) * per]
		if skill.has("cost_item") and str(skill.get("cost_item", "")) != "":
			# 【新增】2026-09-25 极·XX之道：只吃对应职业之道书，走 own 单货币显示（自动红绿着色；无资质丹/百业经验勾选对）
			var bid: String = str(skill.get("cost_item", ""))
			var cnum: int = int(skill.get("cost_num", 300))
			items.append({
				"name": skill.name, "stars": per, "is_max": is_max, "info": info,
				"own": [cnum, int(data.items.get(bid, 0))], "own_name": str(data.ITEM_CONFIG.get(bid, {}).get("name", bid)),
				"on_single": on_aptitude_skill_upgrade.bind(i, "single"), "on_bulk": on_aptitude_skill_upgrade.bind(i, "bulk")
			})
		else:
			items.append({
				"name": skill.name, "stars": per, "is_max": is_max, "info": info,
				"pill": per, "on_single": on_aptitude_skill_upgrade.bind(i, "single"), "on_bulk": on_aptitude_skill_upgrade.bind(i, "bulk")
			})

	# 守护灵技能（仅无双门客，阶段注满才显示；同样吃资质丹→抵扣勾选框对）
	# 【改】品质四档改造：无双档 2→3
	if h.get("quality", 0) == 3:
		data.guardian_system.init_guardian(current_hero_id)
		var gs = data.guardian_system.get_guardian(current_hero_id)
		if not gs.is_empty():
			for i in range(data.guardian_system.PHASES.size()):
				if not data.guardian_system.is_phase_full(current_hero_id, i):
					continue
				var skill = gs.skills[i]
				var per: int = int(skill.aptitude_per_level)
				var is_max: bool = skill.level >= skill.max_level
				var info: String = "【%s】  Lv.%d/%d\n资质+%d" % [skill.name, skill.level, skill.max_level, skill.level * per]
				if is_max:
					info += "（已满级）"
				else:
					info += "（下级+%d）" % [(skill.level + 1) * per]
				items.append({
					"name": skill.name, "stars": per, "is_max": is_max, "info": info,
					"pill": per, "on_single": _on_guardian_skill_upgrade.bind(i, "single"), "on_bulk": _on_guardian_skill_upgrade.bind(i, "bulk")
				})
	# 【批次④】信物伴生技能（全信物通用；星级=每级资质；未解锁纯展示）
	for d in data.token_system.get_token_skills(current_hero_id):
		# 【改】2026-09-24 拍板：技能栏只显示已解锁伴生技能；锁定状态只在信物页展示
		if int(d["token_lv"]) < int(d["unlock"]):
			continue
		var t_name: String = str(d["name"])
		var t_star: int = int(d["star"])
		var t_lv: int = int(d["level"])
		var t_cap: int = int(d["cap"])
		var is_lock: bool = false
		var t_info: String
		if is_lock:
			t_info = "【%s】\n信物达到%d级解锁（当前信物Lv.%d）" % [t_name, int(d["unlock"]), int(d["token_lv"])]
		elif t_lv >= t_cap:
			t_info = "【%s】  Lv.%d/%d\n资质+%d（已满级）" % [t_name, t_lv, t_cap, t_lv * t_star]
		else:
			t_info = "【%s】  Lv.%d/%d\n资质+%d（下级+%d）" % [t_name, t_lv, t_cap, t_lv * t_star, (t_lv + 1) * t_star]
		items.append({
			"name": t_name, "stars": t_star, "is_max": (not is_lock and t_lv >= t_cap), "info": t_info,
			"no_action": is_lock,
			"pill": t_star, "on_single": token._on_token_skill_upgrade.bind(t_name, "single"), "on_bulk": token._on_token_skill_upgrade.bind(t_name, "bulk")
		})
	_render_skill_tab(list, items, "skill")

# 【第35节】填充「副业」页：店铺技能/财源广进/副业资质技能/虫师副业技能，统一按钮排+详情区
# 店铺类格式：店铺赚速+X%（下级+Y%）；副业资质技能=单一勾选框（只用自身货币）
func _fill_shop_tab(list):
	var h = data.heroes[current_hero_id]
	data.bank_system.ensure_caiyuan_skill(current_hero_id)
	var items: Array = []
	for i in range(h.shop_skills.size()):
		var skill = h.shop_skills[i]
		var is_caiyuan := str(skill.get("name", "")) == "财源广进"
		var current_percent = skill.base_percent + (skill.level - 1) * skill.percent_per_level
		var is_max: bool = skill.level >= skill.max_level
		# 店铺类显示格式：店铺赚速+X%（下级+Y%）
		var info: String = "【%s】  Lv.%d/%d\n店铺赚速+%.0f%%" % [skill.name, skill.level, skill.max_level, current_percent * 100]
		if is_max:
			info += "（已满级）"
		else:
			info += "（下级+%.0f%%）" % [(current_percent + skill.percent_per_level) * 100]
		if is_caiyuan:
			# 货币(消耗/库存) 由勾选框显示，信息区不再写每级消耗
			items.append({"name": skill.name, "stars": 1, "is_max": is_max, "info": info,
				"own_name": "筹算值", "own": [data.bank_system.get_chousuan_cost(skill.level), data.bank_system.get_chousuan(current_hero_id)],
				"on_single": on_shop_skill_chousuan_upgrade.bind("single"), "on_bulk": on_shop_skill_chousuan_upgrade.bind("bulk")})
		else:
			var abacus_cost: int = max(1, int(ceil(pow(1.05, skill.level - 1))))
			items.append({"name": skill.name, "stars": 1, "is_max": is_max, "info": info,
				"own_name": "算盘", "own": [abacus_cost, int(data.items.get("abacus", 0))],
				"on_single": on_shop_skill_upgrade.bind(i, "single"), "on_bulk": on_shop_skill_upgrade.bind(i, "bulk")})

	# 副业资质技能（side_skill_system：只用自身货币→单一勾选框，货币(消耗/库存)）
	for r in data.side_skill_system.get_hero_skill_rows(current_hero_id):
		var is_max: bool = int(r["cost"]) < 0
		var lv: int = int(r["level"])
		var info: String = "【%s】  Lv.%d/%d\n资质+%d" % [r["name"], lv, int(r["max"]), lv]
		var it := {"name": r["name"], "stars": 1, "is_max": is_max, "info": info,
			"on_single": on_side_sys_upgrade.bind(str(r["key"]), "single"), "on_bulk": on_side_sys_upgrade.bind(str(r["key"]), "bulk")}
		if is_max:
			info += "（已满级）"
		else:
			info += "（下级+%d）" % (lv + 1)
			it["own_name"] = str(r["currency"])
			it["own"] = [int(r["cost"]), data.side_skill_system.get_stock(current_hero_id, str(r["key"]))]
		items.append(it)

	# 虫师副业技能（促织园；吃资质丹→抵扣勾选框对，上限=虫书等级×10）
	for s in data.cuzhi_system.get_hero_side_skills(current_hero_id):
		var lv: int = int(s.level)
		var star: int = int(s.star)
		var is_max: bool = lv >= int(s.max_level)
		var info: String = "【虫师】%s  Lv.%d/%d\n资质+%d" % [s.name, lv, int(s.max_level), lv * star]
		if is_max:
			info += "（已满级）"
		else:
			info += "（下级+%d）" % [(lv + 1) * star]
		items.append({"name": s.name, "stars": star, "is_max": is_max, "info": info,
			"pill": star, "on_single": on_side_skill_upgrade.bind(int(s.idx), "single"), "on_bulk": on_side_skill_upgrade.bind(int(s.idx), "bulk")})
	_render_skill_tab(list, items, "shop")

# 【v4新增】填充占位页（服装/光环待开发，后续做功能时换成对应的 _fill_xxx_tab）
func _fill_placeholder_tab(list):
	var lbl = Label.new()
	lbl.text = "敬请期待"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(lbl)

# 【第35节·改】填充「服装」页签：base 部分（解锁服装附带的门客技能，固定200级，资质丹/百业经验升级）
# extra 部分（重复兑换提升）在服装按钮弹窗里展示
func _fill_costume_tab(list):
	var cs = data.costume_system
	var items: Array = []
	for cfg in cs.get_hero_costume_cfgs(current_hero_id):
		var cos_id = cfg.get("id", "")
		if str(cfg.get("series", "")) == "山河五岳": continue   # 【凤魁】山河五岳集中到凤魁晋升页面，门客服装页签不再显示（光环页签保留，2026-09-25）
		if not cs.is_hero_cos_unlocked(current_hero_id, cos_id): continue
		var st = cs.get_hero_cos_state(current_hero_id, cos_id)
		var base = int(st.get("base", 1))
		var max_lv = int(cs._settings().get("skill_max_level", 200))
		var per = int(cs._settings().get("apt_per_level", {}).get(cfg.get("quality", "素装"), 2))
		var is_max: bool = base >= max_lv
		var info: String = "【%s】%s  Lv.%d/%d\n资质+%d" % [cfg.get("quality", ""), cfg.get("name", cos_id), base, max_lv, base * per]
		if is_max:
			info += "（已满级）"
		else:
			info += "（下级+%d）" % [(base + 1) * per]
		items.append({"name": cfg.get("name", cos_id), "stars": per, "is_max": is_max, "info": info,
			"pill": per, "on_single": _on_cos_skill_upgrade.bind(cos_id, "single"), "on_bulk": _on_cos_skill_upgrade.bind(cos_id, "bulk")})
	if items.is_empty():
		var lbl = Label.new()
		lbl.text = "暂未解锁服装（点左侧【服装】按钮兑换）"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)
		return
	_render_skill_tab(list, items, "costume")

# 【服装系统】服装技能升级回调
func _on_cos_skill_upgrade(cos_id: String, mode: String):
	var res = data.costume_system.upgrade_cos_skill(current_hero_id, cos_id, mode, _use_baiye)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "无法升级"))
		return
	update_hero_panel()   # 资质变化，面板对账
	c.update_all_ui()
	c.update_bag_list()

# 【第35节】填充「光环」页：光环类格式=【类】门客资质+X，上限=min(100, 服装总等级×10)
# 【改】光环页签（批次②重构）：服装光环+系列光环全部并入卡片按钮排，上排技能按钮+下栏固定升级区；
# 人数档/flat 为只读卡片（无升级交互）；不再单独渲染系列段
func _fill_halo_tab(list):
	var cs = data.costume_system
	var my_cat = data.heroes[current_hero_id].get("category", "")
	var items: Array = []
	for cfg in cs.get_hero_costume_cfgs(current_hero_id):
		var cos_id = cfg.get("id", "")
		if not cs.is_hero_cos_unlocked(current_hero_id, cos_id): continue
		var st = cs.get_hero_cos_state(current_hero_id, cos_id)
		var lv = int(st.get("halo", 0))
		var cap = cs.get_halo_cap(current_hero_id, cos_id)
		var per = int(cs._settings().get("halo_apt_per_level", 1))
		var is_max: bool = lv >= cap
		# 光环类显示格式：【类】门客资质+X
		var info: String = "【%s】  Lv.%d/%d\n【%s】类门客资质+%d" % [cfg.get("name", cos_id), lv, cap, my_cat, lv * per]
		if is_max:
			info += "（已满级）"
		items.append({"name": cfg.get("name", cos_id), "stars": per, "is_max": is_max, "info": info,
			"own_name": "玉璜", "own": [cs.get_halo_cost(lv + 1), int(data.items.get("yu_huang", 0))],
			"on_single": _on_halo_upgrade.bind(cos_id, "single"), "on_bulk": _on_halo_upgrade.bind(cos_id, "bulk")})
	# 系列光环：全部技能并入卡片（与服装光环同排同详情区）
	var ts = data.talent_system
	var acfg = ts.get_hero_aura_cfg(current_hero_id)
	if not acfg.is_empty():
		for skill in acfg.get("skills", []):
			items.append(_build_aura_card(skill))
	# 【新增】2026-09-24 师徒光环（小八）：四张卡追加在服装/系列光环之后
	for aura in data.hero_system.get_master_aura_cfgs(current_hero_id):
		items.append(promo._build_master_aura_card(aura))
	# 【新增】2026-09-24 双人光环（小舞）：两张卡追加在师徒光环之后；
	# 仅配置主（小舞）面板显示；效果对 partner（杨戬）同生生效，杨戬面板不加卡
	for aura in data.hero_system.get_pair_aura_cfgs(current_hero_id):
		items.append(promo._build_pair_aura_card(aura))
	# 【新增】2026-09-25 自带光环（小柒）：三张卡追加在双人光环之后（闸门=五艳对应光环总等级，free_action 无消耗）
	for aura in data.hero_system.get_self_aura_cfgs(current_hero_id):
		items.append(promo._build_self_aura_card(aura))
	if items.is_empty():
		var lbl = Label.new()
		lbl.text = "暂未解锁光环（解锁服装后获得同名光环技能）"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(lbl)
	else:
		_render_skill_tab(list, items, "halo")

# 【新增】系列光环卡片条目（接 _render_skill_tab 协议）：
# item 档=消耗+升级/十连；.极档=总和需求+"？"钮+手动逐级升级；人数档/flat=只读卡片（no_action，无右侧交互）
func _build_aura_card(skill: Dictionary) -> Dictionary:
	var ts = data.talent_system
	var mode: String = str(skill.get("mode", "item"))
	var sname: String = str(skill.get("name", ""))
	var lv = ts.get_aura_level(current_hero_id, skill)
	var effect: Dictionary = skill.get("effect", {})
	if effect == null: effect = {}
	var per = int(effect.get("per", 0))
	var max_lv = int(skill.get("max_level", 1))
	var series_key = str(ts.get_hero_aura_cfg(current_hero_id).get("series", ""))
	var eff: String = ""
	match str(effect.get("kind", "")):
		"self_pct":
			eff = "自身赚钱+%d%%" % (per * lv)
		"career_pct":
			eff = "同职业门客赚钱+%d%%" % (per * lv)
		"series_aptitude":
			eff = "全系列资质+%d" % (per * lv)
	var card := {"name": sname, "stars": per, "is_max": false, "info": "", "no_action": false,
		"on_single": Callable(), "on_bulk": Callable()}
	match mode:
		"series_count":
			# 人数档：等级=已招募系列门客数（实时），只读
			max_lv = ts.get_series_recruited_count(series_key)
			card["info"] = "【%s】  Lv.%d/%d\n%s（已招募 %d 名系列门客）" % [sname, lv, max_lv, eff, max_lv]
			card["no_action"] = true
		"flat":
			card["info"] = "【%s】  Lv.%d/%d\n%s\n（固定效果，不可升级）" % [sname, lv, max_lv, eff]
			card["no_action"] = true
		"item":
			card["info"] = "【%s】  Lv.%d/%d\n%s" % [sname, lv, max_lv, eff]
			card["is_max"] = lv >= max_lv
			var check = ts.get_aura_upgrade_check(current_hero_id, skill)
			var iname = str(data.ITEM_CONFIG.get(str(check.get("item_id", "")), {}).get("name", ""))
			card["own_name"] = iname
			card["own"] = [int(check.get("cost", 0)), int(data.items.get(str(check.get("item_id", "")), 0))]
			card["on_single"] = _on_aura_upgrade.bind(sname, "single")
			card["on_bulk"] = _on_aura_upgrade.bind(sname, "bulk")
		"series_total_level":
			# .极档：等级存 hero_aura_levels，手动逐级升；右侧=对应技能等级总和 现有/下级需求 +"？"钮
			card["info"] = "【%s】  Lv.%d/%d\n%s" % [sname, lv, max_lv, eff]
			var p = ts.get_aura_extreme_progress(current_hero_id, skill)
			card["own_name"] = "对应技能等级总和"
			card["own"] = [p.total, maxi(p.next_need, 0)]
			card["on_hint"] = _on_aura_extreme_hint.bind(sname)
			card["is_max"] = p.next_need < 0
			card["on_single"] = _on_aura_upgrade.bind(sname, "single")
			card["on_bulk"] = _on_aura_upgrade.bind(sname, "bulk")
	return card

# 【新增】.极档"？"说明弹窗：各特级厨师对应技能等级明细 + 总和/下级需求（固定尺寸面板，防过长）
func _on_aura_extreme_hint(skill_name: String):
	var lines = data.talent_system.get_aura_extreme_detail(current_hero_id, skill_name)
	if lines.is_empty(): return
	if c.has_node("AuraHintPanel"):
		var old = c.get_node("AuraHintPanel")
		c.remove_child(old)
		old.queue_free()
	var popup = c._create_base_popup("【%s】升级需求" % skill_name, Vector2(380, 300))
	popup.name = "AuraHintPanel"
	popup.z_index = 30
	c.add_child(popup)
	var vb = popup.get_child(0)
	for ln in lines:
		var l = Label.new()
		l.text = ln
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(l)

# 【新增】系列光环升级回调：扣道具/写 hero_aura_levels → 原地重建光环页 + 全局对账
func _on_aura_upgrade(skill_name: String, mode: String):
	var res = data.talent_system.upgrade_aura(current_hero_id, skill_name, mode)
	if not res.get("ok", false):
		c._show_stage_hint(res.get("msg", "无法升级"))
		return
	update_hero_panel()   # 光环页 SkillList 原地重建（等级行即时刷新）
	c.update_all_ui()     # 全局对账（光环效果批次③接线后此处产生真实 diff）
	c.update_bag_list()

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
	
	# 【改】UI统一批次①：底部关闭钮移除（右上✕接管）

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
		c.flash_red("GuardianAvatarPopup")   # 【新增】闪红审计：操作失败反馈（2026-09-19）
		c._show_stage_hint("道具不足，无法解锁")

# 【新增】守护灵技能升级回调
func _on_guardian_skill_upgrade(skill_idx: int, mode: String):
	var upgraded = data.guardian_system.upgrade_skill(current_hero_id, skill_idx, mode == "bulk", _use_baiye)
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
	


func _on_talent_btn_clicked():
	_show_talent_panel("talent")

# 【新增】天赋面板标签切换：关掉当前面板按新标签重建（按钮经 bind 传参，避开 GDScript 闭包捕获循环变量坑）
func _on_talent_tab_clicked(tab_id: String):
	_talent_tab = tab_id   # 【新增】页签类变量记忆（重建刷新不跳页）
	if c.has_node("TalentPanel"):
		var old = c.get_node("TalentPanel")
		c.remove_child(old)
		old.queue_free()
	_show_talent_panel(tab_id)

# 【改】天赋面板（批次①）：顶部=精进区（公共）；下部标签页【独有天赋】/【精进技能】
# 重建刷新模式沿用信物/风姿面板惯例（remove_child+queue_free 防同名冲突）
func _show_talent_panel(tab_id: String = "talent"):
	_talent_tab = tab_id   # 【新增】重建前先记忆页签（精进刷新沿用当前页）
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
	# 【改】页签重命名（批次①）：原"天赋"占位页=独有天赋，"技能"页=精进技能
	for t in [["talent", "独有天赋"], ["skill", "精进技能"]]:
		var tbtn = Button.new()
		tbtn.text = t[1]
		tbtn.custom_minimum_size = Vector2(140, 36)
		if t[0] == tab_id:
			tbtn.add_theme_color_override("font_color", Color("#ffd700"))
		tbtn.pressed.connect(_on_talent_tab_clicked.bind(t[0]))
		tab_box.add_child(tbtn)
	
	if tab_id == "talent":
		# ── 独有天赋页：品质天赋三段式（批次①实装）──
		_fill_unique_talent_tab(vb)
	else:
		_fill_talent_skill_tab(vb)
	

# 【改】天赋精进区（2026-09-24 用户拍板精简）：当前星级生效值一行 + 精进按钮；未满足仅红字原因
func _fill_talent_refine_area(vb):
	var ts = data.talent_system
	var star = ts.get_star(current_hero_id)
	var max_star = ts.get_max_star()
	var item_name = data.ITEM_CONFIG.get(ts.get_cost_item(), {}).get("name", ts.get_cost_item())

	# ── 当前星级生效值（替换制一行带过）──
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if star > 0:
		var cur = ts.get_star_cfg(star)
		info_lbl.text = "【鬼斧神工】%d星/%d星 · 固定赚钱+%s/秒 · 百分比赚钱+%d%%（替换制）" % [
			star, max_star,
			c.format_number(int(cur.get("flat_income", 0))),
			int(float(cur.get("income_pct", 0.0)) * 100)
		]
	else:
		info_lbl.text = "【鬼斧神工】未精进（0星）"
	vb.add_child(info_lbl)

	# ── 精进按钮（消耗在按钮上；未满足只红字原因，要求明细不再罗列——2026-09-24 用户拍板精简）──
	if star < max_star:
		var check = ts.get_refine_check(current_hero_id)
		if not check.ok:
			var reason_lbl = Label.new()
			reason_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reason_lbl.add_theme_color_override("font_color", Color("#ff6666"))
			reason_lbl.text = "未满足：" + "；".join(check.reasons)
			vb.add_child(reason_lbl)
		var cfg = ts.get_star_cfg(star + 1)
		var refine_btn = Button.new()
		refine_btn.custom_minimum_size = Vector2(130, 48)
		refine_btn.text = "精进%d星\n%d【%s】" % [star + 1, int(cfg.get("cost", 0)), item_name]
		refine_btn.disabled = not check.ok
		refine_btn.pressed.connect(func():
			var res = ts.refine(current_hero_id)
			if res.get("ok", false):
				_show_talent_panel(_talent_tab)   # 原地页签重建刷新
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

# 【改】独有天赋页（2026-09-24 用户拍板精简）：只显示当前品质档效果，其余档不再展示；
# 未实装活动向效果维持灰显"后续版本开放"（口径不变）；玩家只看精进后当前实际数值（批次⑤渲染）
func _fill_unique_talent_tab(vb):
	var ts = data.talent_system
	var cfg = ts.get_hero_talent_cfg(current_hero_id)
	var cur_tier = ts.get_current_tier(current_hero_id)
	if cfg.is_empty() or cur_tier == "" or not cfg.get("tiers", {}).has(cur_tier):
		var tip = Label.new()
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.add_theme_color_override("font_color", Color("#888888"))
		tip.text = "该门客没有天赋"
		vb.add_child(tip)
		return
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 260)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for t in cfg.get("tiers", {}).get(cur_tier, []):
		var row = Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# 未实装活动向效果灰显"后续版本开放"，不显示数值文案（批次④收口口径不变）
		if ts.is_unwired_talent_kind(str(t.get("kind", ""))):
			row.add_theme_color_override("font_color", Color("#888888"))
			row.text = "【%s】后续版本开放" % str(t.get("name", ""))
		else:
			row.add_theme_color_override("font_color", Color("#7ee787"))
			row.text = "【%s】%s" % [str(t.get("name", "")), ts.get_effect_desc(t, current_hero_id)]
		list.add_child(row)

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
	hint_lbl.text = "按当前星级替换（不累加）；解锁技能在门客【技能】页用资质丹升级"
	vb.add_child(hint_lbl)

# ============ 【新增】门客属性构成弹窗（2026-09-25 用户拍板） ============
# 入口=面板资质行"?"小钮；资质/等级/赚钱三段全来源构成，零值行也显示（主要供测试对账，玩家同可见）。
# 数据=HeroData.get_attr_breakdown 打开时现场重算（单门客毫秒级，显示打开瞬间精确值，与生效口径同源）。
func _show_attr_breakdown():
	if current_hero_id == "" or not data.heroes.has(current_hero_id): return
	c._safe_close("AttrBreakdownPopup")
	var bd: Dictionary = HeroData.get_attr_breakdown(data, current_hero_id)
	var popup = c._create_base_popup("门客属性", Vector2(560, 920))
	popup.name = "AttrBreakdownPopup"
	c.add_child(popup)   # 弹窗工厂只创建不挂树，必须自行 add_child
	var vb = popup.get_child(0)
	# 长列表自加滚动区（弹窗工厂只给标题+VBox）
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 780)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	# 资质段
	_bd_section(list, "资质 %d" % int(bd.get("apt_total", 0)))
	_bd_grid(list, bd.get("apt_rows", []), false)
	# 等级段（上限公式=50+突破×50，与 hero_system 升级处一致）
	_bd_section(list, "门客等级 %d" % int(bd.get("level", 0)))
	_bd_grid(list, [["等级", int(bd.get("level", 0))], ["突破次数", int(bd.get("bt", 0))]], false)
	_bd_section(list, "等级上限 %d" % int(bd.get("level_cap", 0)))
	_bd_grid(list, [["基础", 50], ["突破", int(bd.get("bt", 0)) * 50]], false)
	# 赚钱段：基础（资质×等级×突破）+ 固定组 + 百分比组
	_bd_section(list, "赚钱 %s/秒" % c.format_number(int(bd.get("income_total", 0))))
	_bd_grid(list, [["基础", int(bd.get("income_base", 0))]], false)
	_bd_grid(list, bd.get("flat_rows", []), false)
	_bd_grid(list, bd.get("pct_rows", []), true)

# 构成弹窗段标题（金色居中）
func _bd_section(parent: VBoxContainer, text: String):
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color("#ffd700"))
	parent.add_child(lbl)

# 构成弹窗三列行格：rows=[[名, 值]…]；is_pct=true 时值按小数制百分比显示（0.02→+2.0%）
# 单元格钉死 160 宽（ScrollContainer 不把宽度分给子控件，3×160+缝=504 不超滚动区 520）
func _bd_grid(parent: VBoxContainer, rows: Array, is_pct: bool):
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for r in rows:
		var cell = Label.new()
		if is_pct:
			cell.text = "%s +%.1f%%" % [str(r[0]), float(r[1]) * 100.0]
		else:
			cell.text = "%s +%s" % [str(r[0]), c.format_number(int(r[1]))]
		cell.add_theme_font_size_override("font_size", 14)
		cell.add_theme_color_override("font_color", Color("#e8e4f3"))
		cell.custom_minimum_size = Vector2(160, 0)
		grid.add_child(cell)
