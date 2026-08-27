# ============================================================
# 庄园视图（第4批新增：农场+牧场挂机产出，入口在闯荡页；【第7批新增】宅院页签）
# 【第8批改】农场/牧场/宅院主列表全部改为“按钮 + 弹窗”：
#   主列表只显示品种按钮（名称+产物），点击弹窗内再升级该地块/卷轴，避免长列表滚动
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
	manor_btn.custom_minimum_size = Vector2(240, 60)
	manor_btn.pressed.connect(c.show_manor_view)
	vbox.get_node("AdventureEntryGrid").add_child(manor_btn)
	
	# --- 庄园子页面 ---
	var view = VBoxContainer.new()
	view.name = "ManorView"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.add_theme_constant_override("separation", 10)
	page.add_child(view)
	
	var back_btn = Button.new()
	back_btn.text = "< 返回闯荡"
	back_btn.pressed.connect(c.hide_manor_view)
	view.add_child(back_btn)
	
	# 仓库总览（独立仓库，产物用于宅院技艺卷轴升级）
	var goods_lbl = Label.new()
	goods_lbl.name = "ManorGoods"
	goods_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goods_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goods_lbl.add_theme_font_size_override("font_size", 14)
	goods_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	view.add_child(goods_lbl)
	
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
# 重绘仓库总览 + 当前分页的品种按钮
func update_manor_view():
	if not c.has_node("PageContainer/AdventurePage/ManorView"): return
	var view = c.get_node("PageContainer/AdventurePage/ManorView")
	
	# 仓库总览
	var parts = []
	for product in data.manor_goods.keys():
		parts.append("%s×%d" % [product, int(data.manor_goods[product])])
	view.get_node("ManorGoods").text = "仓库：" + ("、".join(parts) if parts.size() > 0 else "（空）")
	
	# 主列表（宅院页签交给 CourtyardView 重绘，农场/牧场显示品种按钮）
	var list = view.get_node("ManorScroll/ManorList")
	for child in list.get_children():
		child.queue_free()
	if _manor_tab == "courtyard":
		c.update_courtyard_view(list)
		return
	
	# 【改】农场/牧场主列表改为两列品种按钮，点击按钮才打开该地块的升级弹窗
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	list.add_child(grid)
	for cfg in data.get_manor_species_list(_manor_tab):
		grid.add_child(_build_species_button(cfg))

# 构建品种入口按钮：名称+产物；未解锁品种置灰并显示身份要求
func _build_species_button(cfg: Dictionary) -> Button:
	var sid = String(cfg.get("id", ""))
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(160, 58)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	if data.get_manor_unlocked_plots(sid) <= 0:
		btn.text = "%s\n身份%d级解锁" % [cfg.get("name", sid), int(cfg.get("unlock_identity", 1))]
		btn.disabled = true
	else:
		# 附带总产量，不打开弹窗也能看到该品种当前收益
		btn.text = "%s\n产物：%s（%.1f/分）" % [
			cfg.get("name", sid), cfg.get("product", ""), data.get_manor_species_rate(sid)]
		btn.pressed.connect(_on_species_button.bind(sid))
	return btn

# ============ 品种升级弹窗 ============
# 打开某个品种的升级弹窗；重复打开时先关闭旧弹窗，避免叠加
func _on_species_button(species_id: String):
	c._safe_close("ManorSpeciesPopup")
	var panel = c._create_base_popup("", Vector2(360, 430))
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
	for child in vbox.get_children():
		child.queue_free()
	
	var title = Label.new()
	title.text = "【%s】产物：%s ｜ 总产量 %.1f/分" % [
		cfg.get("name", sid), cfg.get("product", ""), data.get_manor_species_rate(sid)]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(title)
	# 【新增】等级十连勾选放在弹窗内：升级按钮在哪，开关就在哪；勾选状态记在 _batch_checked
	var batch_check = CheckBox.new()
	batch_check.text = "等级十连"
	batch_check.button_pressed = _batch_checked
	batch_check.toggled.connect(_on_batch_toggled)
	vbox.add_child(batch_check)
	
	# 每块地/圈一行：已解锁显示升级按钮，未解锁显示身份要求
	var unlocked_cnt = data.get_manor_unlocked_plots(sid)
	for i in range(data.get_manor_plots_per_species()):
		if i < unlocked_cnt:
			vbox.add_child(_build_plot_row(sid, i, land_word))
		else:
			var lock_lbl = Label.new()
			lock_lbl.text = "第%d%s：身份%d级解锁" % [i + 1, plot_word, data.get_manor_plot_need_identity(sid, i)]
			lock_lbl.add_theme_color_override("font_color", Color("#888888"))
			vbox.add_child(lock_lbl)
	
	c._add_ok_button(vbox, func(): c._safe_close("ManorSpeciesPopup"), "关闭")

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

# 构建单个已解锁地块的行：等级信息 + 两个升级按钮
func _build_plot_row(sid: String, plot_index: int, land_word: String) -> HBoxContainer:
	var plot = data.get_manor_plot(sid, plot_index)
	var lv = int(plot.level)
	var land = int(plot.land)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	
	var info = Label.new()
	info.text = "  品种Lv%d/%d %sLv%d ｜ %.1f/分" % [
		lv, data.get_manor_plot_level_cap(land), land_word, land, data.get_manor_plot_rate(sid, plot_index)]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	
	# 品种升级（耗铜钱，费用随等级平方增长）
	var lv_btn = Button.new()
	lv_btn.text = "等级↑ %s" % c.format_number(data.get_manor_level_up_cost(lv))
	lv_btn.pressed.connect(_on_upgrade_level.bind(sid, plot_index))
	row.add_child(lv_btn)
	
	# 土地/血统升级（耗商铺图纸）
	var land_btn = Button.new()
	land_btn.text = "%s↑ %d图纸" % [land_word, data.get_manor_land_up_cost(land)]
	land_btn.pressed.connect(_on_upgrade_land.bind(sid, plot_index))
	row.add_child(land_btn)
	return row

# ============ 交互回调 ============
# 切换 农场/牧场/宅院 分页（【新增】切页时关闭品种弹窗，避免弹窗残留）
func _on_tab(kind: String):
	c._safe_close("ManorSpeciesPopup")
	_manor_tab = kind
	update_manor_view()

# 【新增】弹窗内“等级十连”勾选变化时记录状态，重开弹窗保持上次选择
func _on_batch_toggled(pressed: bool):
	_batch_checked = pressed


# 升级某块的品种等级（勾选"等级十连"时一次连升10级；失败弹原因）
func _on_upgrade_level(species_id: String, plot_index: int):
	# 【改】十连状态读模块变量（勾选框在弹窗内），不再按节点名查找
	var r
	if _batch_checked:
		r = data.upgrade_manor_plot_level_batch(species_id, plot_index)   # 十连：逐次结算，失败即停
	else:
		r = data.upgrade_manor_plot_level(species_id, plot_index)
	if not r.ok:
		c._show_stage_hint(r.reason)
	update_manor_view()
	_refresh_species_popup()   # 【新增】刷新弹窗内等级/费用显示

# 升级某块的土地/血统（耗商铺图纸，失败弹原因）
func _on_upgrade_land(species_id: String, plot_index: int):
	var r = data.upgrade_manor_plot_land(species_id, plot_index)
	if not r.ok:
		c._show_stage_hint(r.reason)
	update_manor_view()
	_refresh_species_popup()   # 【新增】刷新弹窗内土地/血统显示
