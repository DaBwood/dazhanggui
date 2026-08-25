# ============================================================
# 庄园视图（第4批新增：农场+牧场挂机产出，入口在闯荡页）
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
var _manor_tab: String = "crops"   # crops=农场 / animals=牧场

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
	
	# 仓库总览（独立仓库，产物留给后续宅院消耗）
	var goods_lbl = Label.new()
	goods_lbl.name = "ManorGoods"
	goods_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goods_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goods_lbl.add_theme_font_size_override("font_size", 14)
	goods_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	view.add_child(goods_lbl)
	
	# 农场/牧场 分页切换
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
	
	# 等级十连勾选（勾选后点"等级↑"一次连升10级，铜钱逐次结算，满级/钱不够即停）
	var batch_check = CheckBox.new()
	batch_check.name = "ManorBatchCheck"
	batch_check.text = "等级十连"
	tab_box.add_child(batch_check)
	
	# 品种卡片列表（scroll双向填充，内容只横向填充）
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

# 返回闯荡主页
func hide_manor_view():
	if not c.has_node("PageContainer/AdventurePage/ManorView"): return
	var page = c.get_node("PageContainer/AdventurePage")
	page.get_node("ManorView").visible = false
	page.get_node("AdventureVBox").visible = true

# ============ 刷新 ============
# 重绘仓库总览 + 当前分页的品种卡片
func update_manor_view():
	if not c.has_node("PageContainer/AdventurePage/ManorView"): return
	var view = c.get_node("PageContainer/AdventurePage/ManorView")
	
	# 仓库总览
	var parts = []
	for product in data.manor_goods.keys():
		parts.append("%s×%d" % [product, int(data.manor_goods[product])])
	view.get_node("ManorGoods").text = "仓库：" + ("、".join(parts) if parts.size() > 0 else "（空）")
	
	# 品种卡片（农场叫"块地/土地"，牧场叫"个圈/血统"）
	var list = view.get_node("ManorScroll/ManorList")
	for child in list.get_children():
		child.queue_free()
	var plot_word = "块地" if _manor_tab == "crops" else "个圈"
	var land_word = "土地" if _manor_tab == "crops" else "血统"
	for cfg in data.get_manor_species_list(_manor_tab):
		list.add_child(_build_species_card(cfg, plot_word, land_word))

# 构建单个品种卡片：标题行 + 每块地/圈一行（未解锁的显示身份要求）
func _build_species_card(cfg: Dictionary, plot_word: String, land_word: String) -> PanelContainer:
	var sid = cfg.get("id", "")
	var card = PanelContainer.new()
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	
	var unlocked_cnt = data.get_manor_unlocked_plots(sid)
	# 标题行：名称/产物/总产量（品种未解锁则显示解锁条件）
	var title = Label.new()
	if unlocked_cnt <= 0:
		title.text = "【%s】身份%d级解锁" % [cfg.get("name", sid), int(cfg.get("unlock_identity", 1))]
		title.add_theme_color_override("font_color", Color("#888888"))
	else:
		title.text = "【%s】产物：%s ｜ 总产量 %.1f/分" % [
			cfg.get("name", sid), cfg.get("product", ""), data.get_manor_species_rate(sid)]
		title.add_theme_color_override("font_color", Color("#ffd700"))
	box.add_child(title)
	
	# 每块地/圈一行
	for i in range(data.get_manor_plots_per_species()):
		if i < unlocked_cnt:
			box.add_child(_build_plot_row(sid, i, land_word))
		else:
			var lock_lbl = Label.new()
			lock_lbl.text = "  第%d%s：身份%d级解锁" % [i + 1, plot_word, data.get_manor_plot_need_identity(sid, i)]
			lock_lbl.add_theme_color_override("font_color", Color("#888888"))
			box.add_child(lock_lbl)
	return card

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
# 切换 农场/牧场 分页
func _on_tab(kind: String):
	_manor_tab = kind
	update_manor_view()

# 升级某块的品种等级（勾选"等级十连"时一次连升10级；失败弹原因）
func _on_upgrade_level(species_id: String, plot_index: int):
	var view = c.get_node("PageContainer/AdventurePage/ManorView")
	var check = view.find_child("ManorBatchCheck", true, false)
	var r
	if check != null and check.button_pressed:
		r = data.upgrade_manor_plot_level_batch(species_id, plot_index)   # 十连：逐次结算，失败即停
	else:
		r = data.upgrade_manor_plot_level(species_id, plot_index)
	if not r.ok:
		c._show_stage_hint(r.reason)
	update_manor_view()

# 升级某块的土地/血统（耗商铺图纸，失败弹原因）
func _on_upgrade_land(species_id: String, plot_index: int):
	var r = data.upgrade_manor_plot_land(species_id, plot_index)
	if not r.ok:
		c._show_stage_hint(r.reason)
	update_manor_view()
