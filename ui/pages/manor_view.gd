# ============================================================
# 庄园视图（第4批新增：农场+牧场挂机产出，入口在闯荡页；【第7批新增】宅院页签）
# 【第8批改】农场/牧场/宅院主列表全部改为“按钮 + 弹窗”：
#   主列表只显示品种按钮（名称+产物），点击弹窗内再升级该地块/卷轴，避免长列表滚动
# 【B14改】农场/牧场内部再分"分组页签"：牧场=杂食/草食/肉食、农场=北田/南田/灌木/东林/西林，
#   每组固定4个品种（2×2 卡片网格）；品种弹窗内 4 个地块改成页签，选中哪个块就单独升哪个块
# 【B14-2改】弹窗升级面板完善（2026-10-02 用户实测反馈）：作物名居中标题+产物速率行；
#   品种等级/土地血统 双卡片（当前→下级效果预览+大号按钮）；新增"同步升级"开关
# 【B14-3改】升级钮回归全仓惯例：消耗走 _add_cost_row（铜钱/图纸 拥有/需要 红绿着色）+普通"升级"钮；
#   "等级十连/同步升级"开关挪到弹窗底部（双卡腾出空间，2026-10-02 用户实测反馈）
# 【B14-4改】升级钮挪卡片右侧、"铜钱/图纸（拥有/需要）"放钮下方（去"升级消耗："前缀）；
#   返回按钮下的"仓库：××"总览行整排删除（2026-10-02 用户实测反馈）
# 【B14-5改】卡片左侧信息一行写不完拆两行（单块产量/每级增量 分开；产量加成/品种上限 分开）
# 【B14-6改】新增"该类商铺赚速"（每品种映射士农工商侠一类商铺，manor.json shop_category，
#   土地/血统每级+25% 读取式接入 shop_system 赚速链，每块独立累计只算已解锁块）；取消土地/血统等级上限
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# UI 全部代码生成：入口按钮与子视图跟随闯荡页重建，零场景改动
# ============================================================
class_name ManorView
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

# 本页 UI 状态变量
var _manor_tab: String = "crops"   # crops=农场 / animals=牧场 / courtyard=宅院
var _batch_checked: bool = false   # 【新增】等级十连状态（勾选框已移入弹窗，这里记住上次选择）
var _manor_group: Dictionary = {"crops": "", "animals": ""}   # 【新增】B14 分组页签当前选择（空=该组第一个）
var _plot_sel: int = 0   # 【新增】B14 品种弹窗内当前选中的地块页签下标（0~3，类变量记忆）
var _sync_checked: bool = false   # 【新增】B14-2 同步升级勾选（全部已解锁地块一起升）

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 构建（由 adventure_page.generate_adventure_page 经中枢转发调用） ============
# 在闯荡页注入"庄园"入口按钮和庄园子视图（模式同行善/游历）
func build_manor_view(page, vbox):
	# --- 庄园入口（与行善/游历并列） ---
	var manor_btn = Button.new()
	manor_btn.text = "庄园"
	manor_btn.custom_minimum_size = Vector2(180, 60)
	manor_btn.pressed.connect(c.show_view.bind("manor"))
	vbox.get_node("AdventureEntryGrid").add_child(manor_btn)
	
	# --- 庄园子页面 ---
	var view = VBoxContainer.new()
	view.name = "ManorView"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.add_theme_constant_override("separation", 10)
	page.add_child(view)
	
	var back_btn = Button.new()
	back_btn.text = "< 返回"   # 【改】UI统一批次①：返回文案统一 < 返回
	back_btn.pressed.connect(c.hide_view.bind("manor"))
	view.add_child(back_btn)
	
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
	
	# 【新增】宅院页签：与农场/牧场并列，内容构建由 pages/courtyard_view.gd 负责
	var courtyard_tab = Button.new()
	courtyard_tab.text = "宅院"
	courtyard_tab.custom_minimum_size = Vector2(160, 44)
	courtyard_tab.pressed.connect(_on_tab.bind("courtyard"))
	tab_box.add_child(courtyard_tab)
	
	# 【改】等级十连勾选从页签栏移入升级弹窗（见 _fill_species_popup），
	# 否则玩家点开弹窗看不到开关，甚至不知道有十连
	
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

# 返回闯荡主页（【新增】同时关闭可能开着的品种升级弹窗）
func hide_manor_view():
	if not c.has_node("PageContainer/AdventurePage/ManorView"): return
	c._safe_close("ManorSpeciesPopup")
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("ManorView").visible = false
	page.get_node("AdventureVBox").visible = true

# ============ 刷新 ============
# 【改】B14-4 重绘当前分页的品种按钮（仓库总览行已按用户要求删除）
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
	
	# 【改】B14：农场/牧场主列表 = 分组页签行 + 当前组 4 个品种卡片（2×2 网格），点击卡片打开升级弹窗
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

# 【改】B14 构建品种入口卡片（2×2 大卡片）：名称+产物+总产量；未解锁品种置灰并显示身份要求
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

# 【新增】B14 构建分组页签行（牧场：杂食/草食/肉食；农场：北田/南田/灌木/东林/西林）
# 当前选中页签金色高亮；选中状态在 _manor_group 类变量记忆，节点重建不丢
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

# 【新增】B14 切换分组页签（同步关闭品种弹窗，避免残留旧组内容）
func _on_group_tab(group: String):
	_manor_group[_manor_tab] = group
	c._safe_close("ManorSpeciesPopup")
	update_manor_view()

# ============ 品种升级弹窗 ============
# 打开某个品种的升级弹窗；重复打开时先关闭旧弹窗，避免叠加
func _on_species_button(species_id: String):
	c._safe_close("ManorSpeciesPopup")
	_plot_sel = 0   # 【新增】B14 换品种时地块页签回到第1块
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
	# 【改】UI统一批次①补充：清空重建保留下标0标题 Label（✕已改悬浮层不占内容流），动态标题改写 PopupTitle、不再自建 Label
	for child in vbox.get_children():
		if child == vbox.get_child(0): continue
		child.queue_free()

	var title: Label = vbox.get_node("PopupTitle")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # 【改】B14-2 作物名居中做标题
	title.text = "%s" % cfg.get("name", sid)
	# 【改】B14-2 产物+速率合并一行（作物与产物同名，不再罗列"产物：xxx ｜ 总产量"）
	var rate_lbl = Label.new()
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_lbl.text = "%s %.1f/分" % [cfg.get("product", ""), data.get_manor_species_rate(sid)]
	rate_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(rate_lbl)
	
	# 【改】B14：4 个地块改成页签行（每块显示品种Lv+单块产量），选中哪块就单独升哪块
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
	# 【改】B14-3 开关行挪到弹窗底部（原来挤在标题下）；等级十连（选中块连升10级）+ 同步升级（全部已解锁地块逐块结算）
	var check_row = HBoxContainer.new()
	check_row.alignment = BoxContainer.ALIGNMENT_CENTER
	check_row.add_theme_constant_override("separation", 16)
	vbox.add_child(check_row)
	var batch_check = CheckBox.new()
	batch_check.text = "等级十连"
	batch_check.button_pressed = _batch_checked
	batch_check.toggled.connect(_on_batch_toggled)
	check_row.add_child(batch_check)
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

# 【新增】B14 构建单个地块页签：显示该块品种等级与单块产量；未解锁块显示身份要求
# 选中块金色高亮（_plot_sel 类变量记忆，弹窗原地重建不丢）
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

# 【新增】B14 选中地块页签：只切换选中下标并原地刷新弹窗（节点不动，符合同名弹窗禁删旧建新）
# 【改】B14-2 去掉未用的 sid 参数（编辑器 UNUSED_PARAMETER 告警：不用的参数不下传）
func _on_plot_tab(plot_index: int):
	_plot_sel = plot_index
	_refresh_species_popup()

# 【改】B14-2 原 _build_plot_panel 重构为双卡片：品种等级卡 + 土地/血统卡（卡片式，效果预览+大号按钮）
# 卡片底比弹窗底(#2a2640)深一档、淡紫描边，与全仓卡片惯例一致（见 courtyard_view._build_scroll_row）
func _make_upgrade_card_style() -> StyleBoxFlat:
	var card_sty := StyleBoxFlat.new()
	card_sty.bg_color = Color("#221d33")
	card_sty.border_color = Color("#6a5f9e")
	card_sty.set_border_width_all(1)
	card_sty.set_corner_radius_all(6)
	card_sty.set_content_margin_all(8)
	return card_sty

# 【改】B14-4 品种等级卡：左侧等级/产量构成，右侧"升级"钮，铜钱（拥有/需要 红绿）放钮下方（去"升级消耗："前缀）
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
	# 【改】B14-5 一行写不完拆两行（2026-10-02 用户实测反馈）
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

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	body.add_child(right)
	var lv_btn = Button.new()
	lv_btn.text = "升级"
	lv_btn.custom_minimum_size = Vector2(90, 44)
	right.add_child(lv_btn)
	lv_btn.pressed.connect(func(): _on_upgrade_level(sid, plot_index, lv_btn))
	c._add_cost_row(right, "铜钱", int(data.money), int(data.get_manor_level_up_cost(lv)))
	return card

# 【改】B14-4 土地/血统卡：左侧加成与品种上限 当前→下级 预览，右侧"升级"钮，图纸（拥有/需要）放钮下方
func _build_land_card(sid: String, plot_index: int, land_word: String) -> PanelContainer:
	var st = data.get_manor_settings()
	var plot = data.get_manor_plot(sid, plot_index)
	var land = int(plot.land)
	var per_land = int(st.get("level_per_land", 50))
	var pct_per = float(st.get("land_pct_per_level", 0.25))
	# 【改】B14-6 该品种映射的商铺类目（manor.json shop_category），土地每级给该类商铺赚速+25%
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
	title_lbl.text = "%s Lv%d" % [land_word, land]   # 【改】B14-6 取消等级上限，不显示 /上限
	title_lbl.add_theme_font_size_override("font_size", 15)
	left.add_child(title_lbl)
	# 【改】B14-5 拆两行：产量加成一行、品种上限一行；【新增】B14-6 中间加"该类商铺赚速"一行
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
# 切换 农场/牧场/宅院 分页（【新增】切页时关闭品种弹窗，避免弹窗残留）
func _on_tab(kind: String):
	c._safe_close("ManorSpeciesPopup")
	_manor_tab = kind
	update_manor_view()

# 【新增】弹窗内“等级十连”勾选变化时记录状态，重开弹窗保持上次选择
func _on_batch_toggled(pressed: bool):
	_batch_checked = pressed

# 【新增】B14-2 弹窗内“同步升级”勾选变化时记录状态，重开弹窗保持上次选择
func _on_sync_toggled(pressed: bool):
	_sync_checked = pressed


# 升级某块的品种等级（勾选"等级十连"时一次连升10级；失败弹原因）
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
		if lv_btn != null: c.flash_red(lv_btn.get_path())   # 【新增】闪红审计：操作失败反馈（2026-09-19）
		c._show_success_popup(r.reason, 0.0, "warn")   # 【改】B14 失败弹窗改 warn 红（成功才 ok 金）
	update_manor_view()
	_refresh_species_popup()   # 【新增】刷新弹窗内等级/费用显示

# 升级某块的土地/血统（耗商铺图纸，失败弹原因）
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
		c._show_success_popup(r.reason, 0.0, "warn")   # 【改】B14 失败弹窗改 warn 红（成功才 ok 金）
	update_manor_view()
	_refresh_species_popup()   # 【新增】刷新弹窗内土地/血统显示