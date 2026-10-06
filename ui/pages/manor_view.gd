# ============================================================
# 庄园视图：农场/牧场/宅院三页签；农场/牧场=分组页签+品种卡片，点卡片弹窗升级（升级卡惯例见范式规范第九节）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# UI 全部代码生成：入口按钮与子视图跟随闯荡页重建，零场景改动
# 最近批次见档案 §十一
# ============================================================
class_name ManorView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 本页 UI 状态变量
var _manor_tab: String = "crops"   # crops=农场 / animals=牧场 / courtyard=宅院
var _batch_checked: bool = false   # 等级十连勾选状态（勾选框在弹窗内，类变量记忆、重建不丢）
var _manor_group: Dictionary = {"crops": "", "animals": ""}   # 分组页签当前选择（空=该组第一个）
var _plot_sel: int = 0   # 品种弹窗内当前选中的地块页签下标（0~3，类变量记忆）
var _sync_checked: bool = false   # 同步升级勾选（全部已解锁地块一起升）

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 构建（由 adventure_page.generate_adventure_page 经中枢转发调用） ============
# 在闯荡页注入"庄园"入口按钮和庄园子视图（模式同行善/游历）
func _show_manor_help():
	var popup = c._create_base_popup("玩法说明", Vector2(440, 0), Vector2.ZERO, false)
	var vb = popup.get_child(0)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = "庄园：农场种植作物、牧场养殖牲畜，成熟后收获资源；宅院可派驻门客提供加成。"
	vb.add_child(lbl)
	c.add_child(popup)

func build_manor_view(page, vbox):
	# --- 庄园入口（与行善/游历并列） ---
	var manor_btn = Button.new()
	manor_btn.text = "庄园"
	manor_btn.custom_minimum_size = Vector2(180, 60)
	manor_btn.pressed.connect(c.show_view.bind("manor"))
	vbox.get_node("MapScroll/MapContent/AdventureEntryGrid").add_child(manor_btn) # 【改】地图批次B：入口网格挪进 MapScroll/MapContent（随横版地图滑动），路径同步（规范 11.7）
	
	# --- 庄园子页面 ---
	var view = VBoxContainer.new()
	view.name = "ManorView"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.add_theme_constant_override("separation", 10)
	page.add_child(view)
	
	# 顶排统一规范（用户拍板 2026-10-06）：<返回(左)+标题(中)+？(右)
	var top := HBoxContainer.new()
	top.name = "TopRow"
	top.add_theme_constant_override("separation", 8)
	view.add_child(top)
	var back_btn = Button.new()
	back_btn.text = "< 返回"
	back_btn.pressed.connect(c.hide_view.bind("manor"))
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "庄园"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	var help := Button.new()
	help.text = "?"
	help.custom_minimum_size = Vector2(40, 36)
	help.add_theme_font_size_override("font_size", 16)
	help.pressed.connect(_show_manor_help)
	top.add_child(help)
	
	# 农场/牧场/宅院 分页切换
	var tab_box = HBoxContainer.new()
	tab_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_box.add_theme_constant_override("separation", 20)
	view.add_child(tab_box)
	
	var farm_tab = Button.new()
	farm_tab.text = "农场"
	farm_tab.custom_minimum_size = Vector2(160, 44)
	farm_tab.pressed.connect(_on_tab.bind("crops"))
	tab_box.add_child(farm_tab)
	
	var ranch_tab = Button.new()
	ranch_tab.text = "牧场"
	ranch_tab.custom_minimum_size = Vector2(160, 44)
	ranch_tab.pressed.connect(_on_tab.bind("animals"))
	tab_box.add_child(ranch_tab)
	
	# 宅院页签：与农场/牧场并列，内容构建由 pages/courtyard_view.gd 负责
	var courtyard_tab = Button.new()
	courtyard_tab.text = "宅院"
	courtyard_tab.custom_minimum_size = Vector2(160, 44)
	courtyard_tab.pressed.connect(_on_tab.bind("courtyard"))
	tab_box.add_child(courtyard_tab)
	
	# 等级十连勾选放升级弹窗内而非页签栏：
	# 开关必须挨着它控制的按钮，否则玩家不知道有十连
	
	# 品种按钮列表（scroll双向填充，内容只横向填充）
	var scroll = ScrollContainer.new()
	scroll.name = "ManorScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(scroll)
	
	var list = VBoxContainer.new()
	list.name = "ManorList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

# ============ 显示/隐藏 ============
# 打开庄园：隐藏闯荡主入口区和其他子视图，只留庄园视图
func show_manor_view():
	if not c.has_node("PageContainer/AdventurePage/ManorView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	for child in page.get_children():
		child.visible = (child.name == "ManorView")
	data.settle_manor()   # 打开时先结算一次在线产量
	update_manor_view()

# 返回闯荡主页（同时关闭可能开着的品种升级弹窗）
func hide_manor_view():
	if not c.has_node("PageContainer/AdventurePage/ManorView"): return
	c._safe_close("ManorSpeciesPopup")
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("ManorView").visible = false
	# 恢复整层场景实例而非只恢复 AdventureVBox：show 侧 blanket 循环把 AdventureScene 整层隐藏，
	# Godot 父节点不可见时子节点 visible=true 也不渲染（父隐子不现），只恢复子级会页面空白
	var scene = page.get_node_or_null("AdventureScene")
	if scene:
		scene.visible = true
	page.get_node("AdventureScene/AdventureVBox").visible = true

# ============ 刷新 ============
# 重绘当前分页的品种按钮（返回按钮下的仓库总览行已按需求删除）
func update_manor_view():
	if not c.has_node("PageContainer/AdventurePage/ManorView"): return
	var view = c.get_node("PageContainer/AdventurePage/ManorView")
	
	# 主列表（宅院页签交给 CourtyardView 重绘，农场/牧场显示品种按钮）
	var list = view.get_node("ManorScroll/ManorList")
	for child in list.get_children():
		child.queue_free()
	if _manor_tab == "courtyard":
		c.update_courtyard_view(list)
		return
	
	# 农场/牧场主列表 = 分组页签行 + 当前组 4 个品种卡片（2×2 网格），点击卡片打开升级弹窗
	var groups = data.get_manor_group_list(_manor_tab)
	if groups.is_empty(): return
	if not groups.has(String(_manor_group.get(_manor_tab, ""))):
		_manor_group[_manor_tab] = groups[0]
	list.add_child(_build_group_tab_row(groups))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	list.add_child(grid)
	for cfg in data.get_manor_species_list_by_group(_manor_tab, String(_manor_group[_manor_tab])):
		grid.add_child(_build_species_button(cfg))

# 品种入口卡片（2×2 大卡片）：名称+产物+总产量；未解锁品种置灰并显示身份要求
func _build_species_button(cfg: Dictionary) -> Button:
	var sid = String(cfg.get("id", ""))
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(240, 92)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 15)
	if data.get_manor_unlocked_plots(sid) <= 0:
		btn.text = "%s\n身份%d级解锁" % [cfg.get("name", sid), int(cfg.get("unlock_identity", 1))]
		btn.disabled = true
	else:
		# 附带总产量，不打开弹窗也能看到该品种当前收益
		btn.text = "%s\n%s　%d/分" % [
			cfg.get("name", sid), cfg.get("product", ""), int(data.get_manor_species_rate(sid))]
		btn.pressed.connect(_on_species_button.bind(sid))
	return btn

# 分组页签行（牧场：杂食/草食/肉食；农场：北田/南田/灌木/东林/西林）
# 当前选中页签金色高亮；选中状态在 _manor_group 记忆，节点重建不丢
func _build_group_tab_row(groups: Array) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for gname in groups:
		var btn = Button.new()
		btn.text = String(gname)
		btn.custom_minimum_size = Vector2(88, 40)
		btn.add_theme_font_size_override("font_size", 14)
		if String(gname) == String(_manor_group.get(_manor_tab, "")):
			btn.add_theme_color_override("font_color", Color("#ffd700"))
		btn.pressed.connect(_on_group_tab.bind(String(gname)))
		row.add_child(btn)
	return row

# 切换分组页签（同步关闭品种弹窗，避免残留旧组内容）
func _on_group_tab(group: String):
	_manor_group[_manor_tab] = group
	c._safe_close("ManorSpeciesPopup")
	update_manor_view()

# ============ 品种升级弹窗 ============
# 打开某个品种的升级弹窗；重复打开时先关闭旧弹窗，避免叠加
func _on_species_button(species_id: String):
	c._safe_close("ManorSpeciesPopup")
	_plot_sel = 0   # 换品种时地块页签回到第1块
	var panel = c._create_base_popup("", Vector2(400, 540))
	panel.name = "ManorSpeciesPopup"
	panel.set_meta("species_id", species_id)
	_fill_species_popup(panel)
	c.add_child(panel)

# 填充/刷新品种弹窗内容（升级后不关弹窗，只重建内部节点，方便连点）
func _fill_species_popup(panel: PanelContainer):
	var sid = String(panel.get_meta("species_id", ""))
	var cfg = _get_species_cfg(sid)
	if cfg.is_empty(): return
	
	# 农场叫"块地/土地"，牧场叫"个圈/血统"，按品种所属分页决定用词
	var is_crop = false
	for c_cfg in data.get_manor_species_list("crops"):
		if c_cfg.get("id", "") == sid:
			is_crop = true
			break
	var plot_word = "块地" if is_crop else "个圈"
	var land_word = "土地" if is_crop else "血统"
	
	var vbox: VBoxContainer = panel.get_child(0)
	# 清空重建保留下标0标题 Label（✕ 在悬浮层不占内容流），动态标题改写 PopupTitle
	for child in vbox.get_children():
		if child == vbox.get_child(0): continue
		child.queue_free()

	var title: Label = vbox.get_node("PopupTitle")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # 作物名居中做标题
	title.text = "%s" % cfg.get("name", sid)
	# 产物+速率合并一行（作物与产物同名，不重复罗列"产物/总产量"）
	var rate_lbl = Label.new()
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_lbl.text = "%s %.1f/分" % [cfg.get("product", ""), data.get_manor_species_rate(sid)]
	rate_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(rate_lbl)
	
	# 4 个地块页签行：每块显示品种Lv+单块产量，选中哪块就单独升哪块
	var unlocked_cnt = data.get_manor_unlocked_plots(sid)
	_plot_sel = clampi(_plot_sel, 0, data.get_manor_plots_per_species() - 1)
	var tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	vbox.add_child(tab_row)
	for i in range(data.get_manor_plots_per_species()):
		tab_row.add_child(_build_plot_tab(sid, i, unlocked_cnt, plot_word))
	if _plot_sel >= unlocked_cnt:
		# 选中未解锁地块：只显示解锁条件，不出现升级按钮
		var lock_lbl = Label.new()
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.text = "第%d%s尚未解锁：身份%d级解锁" % [
			_plot_sel + 1, plot_word, data.get_manor_plot_need_identity(sid, _plot_sel)]
		lock_lbl.add_theme_color_override("font_color", Color("#888888"))
		vbox.add_child(lock_lbl)
	else:
		vbox.add_child(_build_level_card(sid, _plot_sel))
		vbox.add_child(_build_land_card(sid, _plot_sel, land_word))
	# 底部开关行只留"同步升级"（等级十连勾选在等级卡内）
	var check_row = HBoxContainer.new()
	check_row.alignment = BoxContainer.ALIGNMENT_CENTER
	check_row.add_theme_constant_override("separation", 16)
	vbox.add_child(check_row)
	var sync_check = CheckBox.new()
	sync_check.text = "同步升级"
	sync_check.button_pressed = _sync_checked
	sync_check.toggled.connect(_on_sync_toggled)
	check_row.add_child(sync_check)

# 按 id 在农场/牧场配置里找品种，供弹窗刷新时使用
func _get_species_cfg(species_id: String) -> Dictionary:
	for kind in ["crops", "animals"]:
		for cfg in data.get_manor_species_list(kind):
			if cfg.get("id", "") == species_id:
				return cfg
	return {}

# 弹窗开着时刷新它（升级按钮回调里统一调用）
func _refresh_species_popup():
	var popup = c.get_node_or_null("ManorSpeciesPopup")
	if popup != null:
		_fill_species_popup(popup)

# 单个地块页签：显示该块品种Lv+单块产量；未解锁块显示身份要求
# 选中块金色高亮（_plot_sel 记忆，弹窗原地重建不丢）
func _build_plot_tab(sid: String, plot_index: int, unlocked_cnt: int, plot_word: String) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(80, 58)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 12)
	if plot_index < unlocked_cnt:
		var plot = data.get_manor_plot(sid, plot_index)
		btn.text = "第%d%s\nLv%d · %d/分" % [
			plot_index + 1, plot_word, int(plot.level), int(data.get_manor_plot_rate(sid, plot_index))]
		if plot_index == _plot_sel:
			btn.add_theme_color_override("font_color", Color("#ffd700"))
	else:
		btn.text = "第%d%s\n身份%d级" % [plot_index + 1, plot_word, data.get_manor_plot_need_identity(sid, plot_index)]
	btn.pressed.connect(_on_plot_tab.bind(plot_index))
	return btn

# 选中地块页签：切换下标并原地刷新弹窗（节点不动，符合同名弹窗禁删旧建新）
# 去掉未用的 sid 参数（UNUSED_PARAMETER 告警：不用的参数不下传）
func _on_plot_tab(plot_index: int):
	_plot_sel = plot_index
	_refresh_species_popup()

# 品种等级卡 + 土地/血统卡 共用建造器（卡片式，效果当前→下级预览+升级钮）
# 卡片底比弹窗底(#2a2640)深一档、淡紫描边（全仓卡片惯例）
func _make_upgrade_card_style() -> StyleBoxFlat:
	var card_sty := StyleBoxFlat.new()
	card_sty.bg_color = Color("#221d33")
	card_sty.border_color = Color("#6a5f9e")
	card_sty.set_border_width_all(1)
	card_sty.set_corner_radius_all(6)
	card_sty.set_content_margin_all(8)
	return card_sty

# 品种等级卡：左=等级/产量构成，右=升级钮+铜钱（拥有/需要 红绿）+十连勾选（消耗惯例见范式规范八.2）
func _build_level_card(sid: String, plot_index: int) -> PanelContainer:
	var st = data.get_manor_settings()
	var plot = data.get_manor_plot(sid, plot_index)
	var lv = int(plot.level)
	var cap = data.get_manor_plot_level_cap(int(plot.land))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_upgrade_card_style())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	card.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	var title_lbl = Label.new()
	title_lbl.text = "品种等级 Lv%d/%d" % [lv, cap]
	title_lbl.add_theme_font_size_override("font_size", 15)
	left.add_child(title_lbl)
	# 一行写不完就拆两行（不靠自动换行，用户拍板）
	var info = Label.new()
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color("#bbbbbb"))
	info.text = "单块产量 %d/分" % int(data.get_manor_plot_rate(sid, plot_index))
	left.add_child(info)
	var inc_lbl = Label.new()
	inc_lbl.add_theme_font_size_override("font_size", 13)
	inc_lbl.add_theme_color_override("font_color", Color("#bbbbbb"))
	inc_lbl.text = "每级+%s/分" % str(float(st.get("rate_per_level", 1)))
	left.add_child(inc_lbl)

	# 右列：当前铜钱（上）→ 升级钮 → 所需铜钱（红绿）→ 十连勾选（勾选后所需数=10级总价）
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	body.add_child(right)
	var have_lbl = Label.new()
	have_lbl.add_theme_font_size_override("font_size", 12)
	have_lbl.text = "铜钱 %s" % c.format_number(int(data.money))
	right.add_child(have_lbl)
	var lv_btn = Button.new()
	lv_btn.text = "升级"
	lv_btn.custom_minimum_size = Vector2(90, 44)
	right.add_child(lv_btn)
	lv_btn.pressed.connect(func(): _on_upgrade_level(sid, plot_index, lv_btn))
	var lv_cost = int(data.get_manor_level_up_cost(lv))
	if _batch_checked:
		for i in range(1, 10):   # 十连显示10级总价（逐次结算的预估和）
			lv_cost += int(data.get_manor_level_up_cost(lv + i))
	var need_lbl = Label.new()
	need_lbl.add_theme_font_size_override("font_size", 12)
	need_lbl.text = "需 %s" % c.format_number(lv_cost)
	need_lbl.add_theme_color_override("font_color", c._cost_color(int(data.money), lv_cost))
	right.add_child(need_lbl)
	var batch_check = CheckBox.new()
	batch_check.text = "等级十连"
	batch_check.button_pressed = _batch_checked
	batch_check.toggled.connect(_on_batch_toggled)
	right.add_child(batch_check)
	return card

# 土地/血统卡：左=加成/品种上限/该类商铺赚速 当前→下级 预览，右=升级钮+图纸（拥有/需要）
func _build_land_card(sid: String, plot_index: int, land_word: String) -> PanelContainer:
	var st = data.get_manor_settings()
	var plot = data.get_manor_plot(sid, plot_index)
	var land = int(plot.land)
	var per_land = int(st.get("level_per_land", 50))
	var pct_per = float(st.get("land_pct_per_level", 0.25))
	# 该品种映射的商铺类目（manor.json shop_category），每级给该类商铺赚速+25%
	var shop_cat = String(_get_species_cfg(sid).get("shop_category", ""))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_upgrade_card_style())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	card.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	var title_lbl = Label.new()
	title_lbl.text = "%s Lv%d" % [land_word, land]   # 土地/血统无等级上限，不显示 /上限
	title_lbl.add_theme_font_size_override("font_size", 15)
	left.add_child(title_lbl)
	# 三行分开：产量加成 / 该类商铺赚速 / 品种上限
	var info = Label.new()
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color("#bbbbbb"))
	info.text = "产量加成：+%d%% → +%d%%" % [
		roundi(land * pct_per * 100), roundi((land + 1) * pct_per * 100)]
	left.add_child(info)
	var shop_lbl = Label.new()
	shop_lbl.add_theme_font_size_override("font_size", 13)
	shop_lbl.add_theme_color_override("font_color", Color("#bbbbbb"))
	shop_lbl.text = "%s类商铺赚速：+%d%% → +%d%%" % [
		shop_cat, roundi(land * pct_per * 100), roundi((land + 1) * pct_per * 100)]
	left.add_child(shop_lbl)
	var cap_lbl = Label.new()
	cap_lbl.add_theme_font_size_override("font_size", 13)
	cap_lbl.add_theme_color_override("font_color", Color("#bbbbbb"))
	cap_lbl.text = "品种上限：%d → %d" % [land * per_land, (land + 1) * per_land]
	left.add_child(cap_lbl)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	body.add_child(right)
	var land_btn = Button.new()
	land_btn.text = "升级"
	land_btn.custom_minimum_size = Vector2(90, 44)
	right.add_child(land_btn)
	land_btn.pressed.connect(_on_upgrade_land.bind(sid, plot_index))
	c._add_cost_row(right, "图纸", int(data.items.get("shop_blueprint", 0)), int(data.get_manor_land_up_cost(land)))
	return card

# ============ 交互回调 ============
# 切换 农场/牧场/宅院 分页（切页时关闭品种弹窗，避免弹窗残留）
func _on_tab(kind: String):
	c._safe_close("ManorSpeciesPopup")
	_manor_tab = kind
	update_manor_view()

# 十连勾选变化：记状态
# 并原地刷新弹窗：等级卡"所需铜钱"随勾选显示 1级/10级总价
func _on_batch_toggled(pressed: bool):
	_batch_checked = pressed
	_refresh_species_popup()

# 同步升级勾选变化：记状态，重开弹窗保持
func _on_sync_toggled(pressed: bool):
	_sync_checked = pressed

# 升级品种等级（勾选"等级十连"=每块连升10级；勾选"同步升级"=全部已解锁地块一起升，逐块结算失败即停；失败弹原因）
func _on_upgrade_level(species_id: String, plot_index: int, lv_btn: Button = null):
	var targets: Array = [plot_index]
	if _sync_checked:
		targets.clear()
		for i in range(data.get_manor_unlocked_plots(species_id)):
			targets.append(i)
	var r = {"ok": true}
	for pi in targets:
		if _batch_checked:
			r = data.upgrade_manor_plot_level_batch(species_id, pi)   # 十连：逐次结算，失败即停
		else:
			r = data.upgrade_manor_plot_level(species_id, pi)
		if not r.ok:
			break
	if not r.ok:
		if lv_btn != null: c.flash_red(lv_btn.get_path())   # 操作失败反馈闪红
		c._show_success_popup(r.reason, 0.0, "warn")   # 失败弹窗 warn 红（成功才 ok 金，口径见范式规范四.6）
	update_manor_view()
	_refresh_species_popup()   # 刷新弹窗内等级/费用显示

# 升级土地/血统（耗商铺图纸；勾选"同步升级"=全部已解锁地块一起升，逐块结算失败即停；失败弹原因）
func _on_upgrade_land(species_id: String, plot_index: int):
	var targets: Array = [plot_index]
	if _sync_checked:
		targets.clear()
		for i in range(data.get_manor_unlocked_plots(species_id)):
			targets.append(i)
	var r = {"ok": true}
	for pi in targets:
		r = data.upgrade_manor_plot_land(species_id, pi)
		if not r.ok:
			break
	if not r.ok:
		c._show_success_popup(r.reason, 0.0, "warn")   # 失败弹窗 warn 红（成功才 ok 金，口径见范式规范四.6）
	update_manor_view()
	_refresh_species_popup()   # 刷新弹窗内土地/血统显示
