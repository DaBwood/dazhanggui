# ============================================================
# 药铺玩法全屏页（商铺地图 药铺「▶」入口，层级：DrugshopPage z35，弹窗 z40，同医馆/客栈惯例）
# 2026-09-16 按药铺设计方案 v1.3 定稿；当日 6 项修复批次：
#   ①存档：game_data save 数组补登记 drugshop_system（此前状态不落盘，每次打开全新）
#   ②勋章%接入 shop_system 百分比层（此前漏接，升级勋章无加成无飘字）
#   ③一键接待新交互（用户拍板）：勾选框只切换营业按钮模式，不消耗病人；
#     勾选后点【营业】=当前病人全部转入计算队列，后台批处理结算
#   ④领取按钮失效修复：收益罐内容由后台队列结算产生，按钮 disabled 须在定时器节拍里刷新
#   ⑤新增道具【药铺招牌】：病人计数后「＋」按钮→数量选择器（滑动条+输入框，同医馆病人手册），
#     每个招牌 +3 病人，不受自然上限限制
#   ⑥玩家口径统一为"病人"（"体力"是开发口径，UI 一律不显示）
#   主页 = 勋章卡 + 收益罐(红点) + 病人行(＋招牌/营业/一键接待勾选) + 三入口(打理/本草秘籍/成就，带各自红点)
#   红点口径（2026-09-16 用户拍板）：三入口红点只在药铺页内显示（工艺可升/药方可升/成就可领）；
#   外面地图「▶」只认"病人满"一个红点，互不穿透。顶部资源行已删（铜板/经验各使用处自显）
#   打理 = 7工艺卡片（点卡片弹详情升级；顶部"全部升级"一次各升1级）
#   本草秘籍 = 29药方卡片网格（锁定卡显示解锁条件；点卡片弹详情：配方/收益/升级+一键升级/解锁）
#   成就 = 3条线 × 进度 + 4档领取
# 后台节拍：页面定时器 0.5s 调 background_tick 推进队列并刷文本（不重建保流畅）；页面关闭后由
#           game_controller 每秒节拍续推（队列进存档，离线暂停，上线续算）
# 重建刷新模式：操作后整页重建（同医馆惯例）
# ============================================================
class_name DrugshopView
extends BaseView   # 【改】公共层下沉 ui/base_view.gd（2026-09-18 架构重构批次④）

# c/data 引用由基类持有，此处不再声明

var _tab: String = "main"        # 当前视图 main/craft/recipe/ach
var _timer: Timer = null         # 后台节拍定时器（0.5s）
var _stamina_lbl: Label = null   # 病人计数文本
var _cd_lbl: Label = null        # 病人恢复倒计时文本
var _queue_lbl: Label = null     # 计算队列状态文本
var _jar_lbl: Label = null       # 收益罐文本
var _jar_dot: Label = null       # 收益罐红点
var _collect_btn: Button = null  # 【新增】领取按钮引用（节拍里刷新 disabled，修复"入队结算后不可点"）
var _serve_btn: Button = null    # 【新增】营业按钮引用（节拍里刷新 disabled，病人恢复后即时可点）
var _popup_rid: String = ""      # 当前打开的药方弹窗 id（升级后重建用）

func _init(p_c):
	super(p_c)   # 【改】基类注入 c/data（2026-09-18 架构重构批次④）
	_page_name = "DrugshopPage"
	_popup_node_name = "DrugshopPopup"

func _sys() -> DrugshopSystem:
	return data.drugshop_system

# ---------- 页面开关（公共页骨架在 base_view.gd；薄封装保留 show_<key>_view 命名，controller VIEW_LIST 按 key 分发） ----------
func show_drugshop_view():
	show_view()

func hide_drugshop_view():
	hide_view()

# 【新增】批次②③④-B2：玩法说明弹窗（DrugshopRulePopup）是独立节点名，基类只认 _popup_node_name，需显式清理
# 注意：勋章弹窗（DrugshopMedalPopup）不能在 show_view 里关——_refresh 重建链依赖它存活；hide 时才连带关闭
func show_view():
	_close_node("DrugshopRulePopup")
	super()

func hide_view():
	_close_node("DrugshopRulePopup")
	_close_node("DrugshopMedalPopup")
	super()

# 【改】后台节拍挂在基类建页后的钩子（原 show_drugshop_view 尾部，2026-09-18 批次④）；
# Timer 挂在 page 上，随关页 queue_free 自动销毁，hide 无需手动停
func _after_build(page: Panel):
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	page.add_child(_timer)

func _on_tick():
	# 推进计算队列（时间盒 2ms；病人恢复与结算解耦，互不阻塞）
	_sys().background_tick(2)
	if _stamina_lbl:
		_stamina_lbl.text = "病人：%d / %d" % [_sys().get_stamina(), _sys().get_stamina_cap()]
	if _cd_lbl:
		_cd_lbl.text = _cd_text()
	if _queue_lbl:
		_queue_lbl.text = _queue_text()
	if _jar_lbl:
		_jar_lbl.text = _jar_text()
	if _jar_dot:
		_jar_dot.visible = _sys().has_pot()
	# 【修】2026-09-16 收益罐内容由后台队列结算产生，按钮 disabled 必须在节拍里跟着刷新
	# （此前只在建页时设一次：一键接待结算出收益后按钮仍 disabled+红点，须重进才能领）
	if _collect_btn:
		_collect_btn.disabled = not _sys().has_pot()
	# 病人自然恢复后营业按钮即时可用（同上的失效类问题，一并修）
	if _serve_btn:
		_serve_btn.disabled = _sys().get_stamina() <= 0

func _cd_text() -> String:
	var sec := _sys().get_next_stamina_seconds()
	if sec <= 0:
		return "病人已满" if _sys().get_stamina() >= _sys().get_stamina_cap() else "病人即将恢复"
	return "下位病人：%d分%02d秒" % [int(sec / 60.0), sec % 60]

func _queue_text() -> String:
	var n := _sys().get_settle_queue()
	if n > 0:
		return "接待队列：%d（结算中…）" % n
	return "接待队列：0"

func _jar_text() -> String:
	var pot := _sys().get_pot()
	var parts := ["铜板 %s" % c.format_number(int(pot.get("coins", 0))),
		"药铺经验 %s" % c.format_number(int(pot.get("exp", 0)))]
	var prof_total := 0
	for rid in pot.get("prof", {}):
		prof_total += int(pot["prof"][rid])
	if prof_total > 0:
		parts.append("熟练度 %s" % c.format_number(prof_total))
	return "收益罐：" + "　".join(parts)

# ---------- 页面构建 ----------
func _build(page: Panel):
	var vb := VBoxContainer.new()
	vb.position = Vector2.ZERO
	vb.size = page.size
	vb.add_theme_constant_override("separation", 8)
	page.add_child(vb)
	# 顶栏：返回 + 标题（子页返回=回主页，主页返回=退出药铺）
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 48)
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var back_btn := Button.new()
	back_btn.text = "< 返回"
	back_btn.custom_minimum_size = Vector2(90, 42)
	back_btn.pressed.connect(_on_back)
	top.add_child(back_btn)
	var title := Label.new()
	title.text = "药铺" if _tab == "main" else ("药铺 · 打理" if _tab == "craft" else ("药铺 · 本草秘籍" if _tab == "recipe" else "药铺 · 成就"))
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	# 【新增】批次②③④-B2：玩法说明入口"?"（只在玩法主标题旁，说明流程/规则/后台计算）
	var rule_btn := Button.new()
	rule_btn.text = "?"
	rule_btn.custom_minimum_size = Vector2(30, 30)
	rule_btn.add_theme_font_size_override("font_size", 16)
	rule_btn.pressed.connect(_show_rule_popup)
	top.add_child(rule_btn)
	# 【改】2026-09-18 勋章统一样式：右上角入口+弹窗（同酒坊模板），替代原主页内嵌勋章卡
	var medal_sp := Control.new()
	medal_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(medal_sp)
	var medal_btn := Button.new()
	medal_btn.text = "勋章"
	medal_btn.custom_minimum_size = Vector2(84, 42)
	medal_btn.pressed.connect(_show_medal_popup)
	top.add_child(medal_btn)
	_add_btn_dot(medal_btn, _sys().can_upgrade_medal().get("ok", false))   # 内部红点：勋章可升
	# 【删】2026-09-16 资源行（铜板/累计药铺经验）移除：用到它们的地方（收益罐/勋章卡/秘籍页）各自有显示
	# 内容体
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	match _tab:
		"craft":
			_fill_craft(body)
		"recipe":
			_fill_recipe(body)
		"ach":
			_fill_ach(body)
		_:
			_fill_main(body)

func _on_back():
	if _tab == "main":
		hide_drugshop_view()
	else:
		_switch_tab("main")

func _switch_tab(t: String):
	_tab = t
	_close_node("DrugshopPage")
	show_drugshop_view()

# 操作后统一刷新：重建页面；仅当弹窗节点真实存在（未按确定关闭）才重建弹窗
func _refresh():
	_close_node("DrugshopPage")
	show_drugshop_view()
	if _popup_rid != "" and c.get_node_or_null("DrugshopPopup") != null:
		_close_node("DrugshopPopup")
		_show_recipe_popup(_popup_rid)
	# 勋章弹窗重建（独立节点名，与秘籍弹窗互不干扰）
	if c.get_node_or_null("DrugshopMedalPopup") != null:
		_close_node("DrugshopMedalPopup")
		_show_medal_popup()

# 【新增】批次②③④-B2：药铺玩法说明弹窗（只从主标题旁"?"进入；长说明不进画面）
func _show_rule_popup():
	_close_node("DrugshopRulePopup")
	var popup: PanelContainer = c._create_base_popup("药铺说明", Vector2(380, 300))
	popup.name = "DrugshopRulePopup"
	popup.get_meta("popup_mask").z_index = 39
	popup.z_index = 40
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child
	var vb: VBoxContainer = popup.get_child(0)
	for line in [
		"病人随时间恢复；营业接待后收益先入收益罐，领取后入账。",
		"一键接待只切换模式：勾选后点【营业】，才把当前病人全部转入结算队列。",
		"药铺经验只作解锁/勋章门槛，不消耗；工艺升级消耗铜板，药方升级消耗对应熟练度。",
	]:
		var body := Label.new()
		body.text = line
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(body)

# ---------- 主页：收益罐 + 病人行 + 三入口（勋章已改右上角弹窗，2026-09-18 统一样式） ----------
func _fill_main(body: VBoxContainer):
	# 收益罐（铜板/药铺经验/熟练度，领取统一入账）
	var jar_row := HBoxContainer.new()
	jar_row.add_theme_constant_override("separation", 8)
	body.add_child(jar_row)
	_jar_lbl = Label.new()
	_jar_lbl.text = _jar_text()
	_jar_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jar_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jar_row.add_child(_jar_lbl)
	_jar_dot = Label.new()
	_jar_dot.text = "●"
	_jar_dot.add_theme_color_override("font_color", Color("#e74c3c"))
	_jar_dot.visible = _sys().has_pot()
	jar_row.add_child(_jar_dot)
	_collect_btn = Button.new()   # 【改】登记引用，节拍里刷新 disabled
	_collect_btn.text = "领取"
	_collect_btn.custom_minimum_size = Vector2(90, 36)
	_collect_btn.disabled = not _sys().has_pot()
	_collect_btn.pressed.connect(_on_collect)
	jar_row.add_child(_collect_btn)
	# 病人行：计数 + 招牌加号（药铺招牌，仅限此处）+ 营业按钮
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 6)
	body.add_child(count_row)
	_stamina_lbl = Label.new()
	_stamina_lbl.text = "病人：%d / %d" % [_sys().get_stamina(), _sys().get_stamina_cap()]
	_stamina_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(_stamina_lbl)
	# 【新增】药铺招牌加号：弹出数量选择器批量恢复病人（不受自然上限限制，背包不开放，同医馆病人手册）
	var sign_btn := Button.new()
	sign_btn.text = "＋"
	sign_btn.custom_minimum_size = Vector2(40, 32)
	sign_btn.tooltip_text = "使用【药铺招牌】+3 病人"
	sign_btn.pressed.connect(_on_use_sign)
	count_row.add_child(sign_btn)
	_serve_btn = Button.new()   # 【改】登记引用，节拍里刷新 disabled
	_serve_btn.text = "营业"
	_serve_btn.custom_minimum_size = Vector2(110, 38)
	_serve_btn.disabled = _sys().get_stamina() <= 0
	_serve_btn.pressed.connect(_on_serve)
	count_row.add_child(_serve_btn)
	_cd_lbl = Label.new()
	_cd_lbl.text = _cd_text()
	_cd_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
	body.add_child(_cd_lbl)
	# 一键接待勾选（【改】2026-09-16：勾选只切换营业模式，不消耗病人；勾选后点营业=全部转入队列）
	# 勾选框放营业下面；队列状态跟随显示
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 6)
	body.add_child(auto_row)
	var auto_check := CheckBox.new()
	auto_check.text = "一键接待"
	auto_check.button_pressed = _sys().get_auto_settle()
	auto_check.toggled.connect(_on_auto_toggled)   # 【改】命名方法直连（原 lambda 多语句改绑）
	auto_row.add_child(auto_check)
	_queue_lbl = Label.new()
	_queue_lbl.text = _queue_text()
	_queue_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	auto_row.add_child(_queue_lbl)
	# 三入口按钮（【新增】各自红点：工艺可升/药方可升/成就可领，仅药铺页内显示，不透到地图）
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for t in [["craft", "打理", _sys().has_upgradeable_craft()],
			["recipe", "本草秘籍", _sys().has_upgradeable_recipe()],
			["ach", "成就", _sys().has_claimable_ach()]]:
		var wrap_node := Control.new()
		wrap_node.custom_minimum_size = Vector2(170, 56)   # 显式尺寸：红点按常量定位（新建 Button 当帧 size 为 0）
		grid.add_child(wrap_node)
		var b := Button.new()
		b.text = t[1]
		b.position = Vector2.ZERO
		b.size = Vector2(170, 56)
		b.pressed.connect(func(): _switch_tab(t[0]))
		wrap_node.add_child(b)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#e74c3c"))
		dot.add_theme_font_size_override("font_size", 16)
		dot.position = Vector2(148, -6)   # 按钮右上角
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 红点不拦截触摸
		dot.visible = t[2]
		wrap_node.add_child(dot)

# 勋章固定样式（2026-09-19 用户拍板）：主页右上角【勋章】入口 -> 460×420「勋章」弹窗 -> #2a2640/#6a5f9e 勋章卡 -> 等级旁[?]规则 -> 当前效果 -> 下一级进度条 -> 升级按钮 -> 关闭。后续新玩法照此模板，不再另起样式。
func _show_medal_popup():
	_close_node("DrugshopMedalPopup")
	var popup: PanelContainer = c._create_base_popup("勋章", Vector2(460, 420))
	popup.name = "DrugshopMedalPopup"
	popup.z_index = 40
	c.add_child(popup)
	var pvb: VBoxContainer = popup.get_child(0)
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2a2640")
	style.border_color = Color("#6a5f9e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	pvb.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var head_row := HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_theme_constant_override("separation", 6)
	vb.add_child(head_row)
	var head := Label.new()
	head.text = "勋章：%s（%d级）" % [_sys().get_medal_name(), _sys().get_medal_lv()]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	head_row.add_child(head)
	var help_btn := Button.new()
	help_btn.text = "i"   # 【改】批次②③④-B2：面板内补充信息入口统一用"i"（"?"只留玩法主标题旁）
	help_btn.custom_minimum_size = Vector2(24, 24)
	help_btn.tooltip_text = "点击查看勋章规则"
	help_btn.pressed.connect(_on_medal_help)
	head_row.add_child(help_btn)
	var effect := Label.new()
	effect.text = "全体商铺赚速 +%d%%　精进技能等级上限 +%d" % [int(_sys().get_medal_shop_pct() * 100), _sys().get_refine_cap_bonus()]
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(effect)
	var nxt := _sys().get_next_medal_cfg()
	if nxt.is_empty():
		var max_lbl := Label.new()
		max_lbl.text = "已达满级"
		max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		max_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
		vb.add_child(max_lbl)
	else:
		var need: int = int(nxt.get("need_exp", 0))
		# 【改】批次②③④-B10：门槛进度统一（当前/需求）格式，保留达到/未达到红绿提示
		c._add_cost_row(vb, "下一级【%s】需累计药铺经验" % str(nxt.get("name", "")), int(_sys().exp_total), need)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = maxf(1.0, float(need))
		bar.value = minf(float(_sys().exp_total), float(need))
		bar.show_percentage = true
		bar.custom_minimum_size = Vector2(410, 18)
		vb.add_child(bar)
		var next_effect := Label.new()
		next_effect.text = "下级效果：全体商铺赚速 +%d%%　精进上限 +%d" % [int(float(nxt.get("shop_pct", 0.0)) * 100.0), int(nxt.get("refine_cap", 0))]
		next_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next_effect.add_theme_color_override("font_color", Color("#7ee787"))
		vb.add_child(next_effect)
		var btn := Button.new()
		btn.text = "升级勋章"
		btn.custom_minimum_size = Vector2(130, 38)
		btn.disabled = not _sys().can_upgrade_medal().get("ok", false)
		btn.pressed.connect(_on_medal_upgrade)
		vb.add_child(btn)

func _on_medal_help():
	c._show_stage_hint("药铺勋章：累计药铺经验只作门槛不消耗；全体商铺赚速+100%×等级，并提高精进技能等级上限。")

func _on_medal_upgrade():
	var r := _sys().upgrade_medal()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()   # 勋章%入账→全体商铺赚速变化→全局飘字
	_refresh()

# 一键接待勾选切换：【改】2026-09-16 只记录模式开关，不消耗病人（消耗唯一入口=营业按钮）
func _on_auto_toggled(on: bool):
	_sys().set_auto_settle(on)
	_refresh()

# 【新增】药铺招牌：数量选择器（滑动条+输入框联动，项目惯例，同医馆病人手册/客栈食材包）
# 每个招牌 +sign_give 病人，道具恢复不受自然上限限制（2026-09-15 体力类资源规则）
func _on_use_sign():
	var sign_item: String = data._drugshop_configs.get("settings", {}).get("sign_item", "drugshop_sign")
	var owned: int = int(data.items.get(sign_item, 0))
	if owned <= 0:
		c._show_stage_hint("没有【药铺招牌】")
		return
	_close_node("DrugshopPopup")
	var give: int = int(data._drugshop_configs.get("settings", {}).get("sign_give", 3))
	var popup: PanelContainer = c._create_base_popup("使用药铺招牌", Vector2(400, 240), Vector2.ZERO, false)   # 【改】UI统一批次①：确认弹窗不带右上✕
	popup.name = "DrugshopPopup"
	popup.z_index = 40   # 盖过 DrugshopPage(z35)，同 clinic/inn 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child（同 clinic/inn 惯例）
	var vb: VBoxContainer = popup.get_child(0)
	var info := Label.new()
	info.text = "拥有 %d 个，每个 +%d 病人" % [owned, give]
	vb.add_child(info)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vb.add_child(hbox)
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = owned
	slider.value = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(140, 24)
	hbox.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = owned
	spin.value = 1
	hbox.add_child(spin)
	slider.value_changed.connect(spin.set_value)
	spin.value_changed.connect(slider.set_value)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)
	# 【改】UI统一批次①：确认弹窗双钮统一【取消】左【确定】右
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(90, 34)
	cancel_btn.pressed.connect(func(): _close_node("DrugshopPopup"))
	btn_row.add_child(cancel_btn)
	var ok_btn := Button.new()
	ok_btn.text = "确定"
	ok_btn.custom_minimum_size = Vector2(90, 34)
	ok_btn.pressed.connect(func():
		var n: int = int(spin.value)
		data.items[sign_item] = int(data.items.get(sign_item, 0)) - n
		_sys().add_stamina(n * give)
		_close_node("DrugshopPopup")
		c._show_stage_hint("病人 +%d" % (n * give))
		_refresh())
	btn_row.add_child(ok_btn)

func _on_collect():
	var r := _sys().collect_pot()
	c._show_stage_hint("领取：铜板+%s 药铺经验+%s" % [
		c.format_number(int(r["coins"])), c.format_number(int(r["exp"]))])
	_refresh()

# 营业：未勾选一键接待=立即结算1个病人；勾选=当前全部病人转入计算队列（后台批处理）
# 【改】2026-09-16 原勾选即消耗改为点营业才消耗（勾选只切换模式）
func _on_serve():
	if _sys().get_auto_settle():
		var ra := _sys().settle_all()
		if not ra.get("ok", false):
			c._show_stage_hint(str(ra.get("msg", "")))
			return
		c._show_stage_hint("%d 位病人已转入接待队列，结算中…" % int(ra.get("n", 0)))
		_refresh()
		return
	var r := _sys().serve_one()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("接待完成，收益已入罐")
	_refresh()

# ---------- 子页：打理（7工艺卡片 + 全部升级） ----------
func _fill_craft(body: VBoxContainer):
	# 顶部：全部升级（7项各升1级，铜板不足跳过）
	var all_btn := Button.new()
	all_btn.text = "全部升级（铜板 %s）" % c.format_number(_sys().coins)
	all_btn.custom_minimum_size = Vector2(0, 42)
	all_btn.pressed.connect(_on_craft_all)
	body.add_child(all_btn)
	var head := Label.new()
	head.text = "工艺（伙计赚速固定加成）"
	head.add_theme_color_override("font_color", Color("#9a93b8"))
	body.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for cdef in _sys().get_craft_list():
		var cid: String = str(cdef.get("id", ""))
		if cid == "":
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 64)
		b.text = "【%s】\nLv.%d" % [cdef.get("name", cid), _sys().get_craft_level(cid)]
		var cid_c: String = cid
		b.pressed.connect(func(): _show_craft_popup(cid_c))
		grid.add_child(b)

# 全部升级：一次把7项各升1级，铜板不足的项跳过
func _on_craft_all():
	var r := _sys().upgrade_all_crafts()
	if int(r.get("up", 0)) <= 0:
		c._show_stage_hint("铜板不足")
		return
	c.update_all_ui()   # 工艺固定值入账→伙计赚速变化→全局飘字
	_refresh()

func _show_craft_popup(cid: String):
	_close_node("DrugshopPopup")
	var cdef: Dictionary = {}
	for cd in _sys().get_craft_list():
		if str(cd.get("id", "")) == cid:
			cdef = cd
			break
	if cdef.is_empty():
		return
	var popup: PanelContainer = c._create_base_popup(str(cdef.get("name", cid)), Vector2(420, 260))
	popup.name = "DrugshopPopup"
	popup.z_index = 40   # 盖过 DrugshopPage(z35)，同 clinic/inn 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child（同 clinic/inn 惯例）
	var vb: VBoxContainer = popup.get_child(0)
	var lv := _sys().get_craft_level(cid)
	var target: String = str(cdef.get("target", "all"))
	# 加成对象文案（玩家可见：全体商铺或某职业店铺）
	var target_txt := "全体商铺" if target == "all" else "%s类店铺" % target
	var info := Label.new()
	info.text = "Lv.%d　%s伙计赚速 +%s/级×%d" % [lv, target_txt,
		str(cdef.get("per_level", 0)), lv]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	# 【改】批次②③④-B10：伙计技艺升级消耗统一（拥有/消耗），道具名默认色、数字红绿
	c._add_cost_row(vb, "下级消耗：铜板", int(_sys().coins), _sys().get_craft_cost(cid))
	var btn := Button.new()
	btn.text = "升级"
	btn.disabled = not _sys().can_upgrade_craft(cid).get("ok", false)
	btn.pressed.connect(func(): _on_craft_upgrade(cid))
	vb.add_child(btn)

func _on_craft_upgrade(cid: String):
	var r := _sys().upgrade_craft(cid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c.update_all_ui()   # 工艺固定值入账→伙计赚速变化→全局飘字
	_refresh()

# ---------- 子页：本草秘籍（29药方卡片网格） ----------
func _fill_recipe(body: VBoxContainer):
	var head := Label.new()
	# 【改】批次②③④-B2：括号说明迁入主标题旁"?"玩法说明，画面只留数值
	head.text = "累计药铺经验 %s" % c.format_number(_sys().exp_total)
	head.add_theme_color_override("font_color", Color("#9a93b8"))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for rc in _sys().get_recipe_list():
		var rid: String = str(rc.get("id", ""))
		# 【新增】2026-09-16 可升级药方红点（同医馆病症页模式）：外套 Control 显式尺寸
		var wrap_node := Control.new()
		wrap_node.custom_minimum_size = Vector2(170, 52)
		grid.add_child(wrap_node)
		var b := Button.new()
		if _sys().is_recipe_unlocked(rid):
			b.text = "%s\nLv.%d" % [rc.get("name", rid), _sys().get_recipe_level(rid)]
		else:
			b.text = "%s\n需经验 %s" % [rc.get("name", rid), c.format_number(_sys().get_recipe_unlock_need(rid))]
			b.add_theme_color_override("font_color", Color("#666080"))
		b.position = Vector2.ZERO
		b.size = Vector2(170, 52)
		var rid_c: String = rid
		b.pressed.connect(func(): _show_recipe_popup(rid_c))
		wrap_node.add_child(b)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color("#e74c3c"))
		dot.add_theme_font_size_override("font_size", 15)
		dot.position = Vector2(148, -6)   # 170宽按钮右上角
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = _sys().can_upgrade_recipe(rid)
		wrap_node.add_child(dot)

# 药方详情弹窗：配方/收益/升级+一键升级（未解锁则显示解锁条件+解锁按钮）
func _show_recipe_popup(rid: String):
	_popup_rid = rid
	_close_node("DrugshopPopup")
	var rc := _sys().get_recipe_cfg(rid)
	if rc.is_empty():
		return
	var popup: PanelContainer = c._create_base_popup(str(rc.get("name", rid)), Vector2(420, 360))
	popup.name = "DrugshopPopup"
	popup.z_index = 40   # 盖过 DrugshopPage(z35)，同 clinic/inn 弹窗惯例
	c.add_child(popup)   # 弹窗工厂只创建不挂载，必须调用方 add_child（同 clinic/inn 惯例）
	var vb: VBoxContainer = popup.get_child(0)
	if not _sys().is_recipe_unlocked(rid):
		# 未解锁：显示累计经验门槛 + 手动解锁（不消耗经验）
		# 【改】批次②③④-B10：配方解锁门槛统一（当前/需求）格式，保留达到/未达到红绿提示
		c._add_cost_row(vb, "解锁需求：累计药铺经验", int(_sys().exp_total), _sys().get_recipe_unlock_need(rid))
		var unlock_btn := Button.new()
		unlock_btn.text = "解锁"
		unlock_btn.disabled = not _sys().can_unlock_recipe(rid).get("ok", false)
		unlock_btn.pressed.connect(func(): _on_recipe_unlock(rid))
		vb.add_child(unlock_btn)
		return
	# 功效主治难度 + 配方（仅展示，药材不做库存）
	var diff := Label.new()
	diff.text = "难度：%s（售价+%d%%）" % [rc.get("difficulty", ""), int(rc.get("difficulty_pct", 0))]
	vb.add_child(diff)
	var formula := Label.new()
	formula.text = "配方：%s" % rc.get("formula", "")
	formula.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(formula)
	# 接待收益（当前等级）
	var gain := Label.new()
	gain.text = "接待收益：铜板 %s　药铺经验 %d　熟练度 %d" % [
		c.format_number(_sys().get_recipe_price(rid)),
		int(rc.get("exp", 0)),
		int(data._drugshop_configs.get("settings", {}).get("prof_per_serve", 100))]
	vb.add_child(gain)
	# 当前等级/熟练度池
	var lv := _sys().get_recipe_level(rid)
	var max_lv: int = _sys().get_recipe_max_level()
	var wallet := Label.new()
	wallet.text = "Lv.%d/%d　熟练度 %s" % [lv, max_lv, c.format_number(_sys().get_recipe_prof(rid))]
	wallet.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(wallet)
	if lv < max_lv:
		# 【改】批次②③④-B10：配方升级消耗统一（当前熟练度/消耗），数字红绿
		c._add_cost_row(vb, "下级消耗：熟练度", int(_sys().get_recipe_prof(rid)), _sys().get_recipe_upgrade_cost(rid))
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)
		vb.add_child(btn_row)
		var up_btn := Button.new()
		up_btn.text = "升级"
		up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		up_btn.disabled = _sys().get_recipe_prof(rid) < _sys().get_recipe_upgrade_cost(rid)
		up_btn.pressed.connect(func(): _on_recipe_upgrade(rid, false))
		btn_row.add_child(up_btn)
		var up_all_btn := Button.new()
		up_all_btn.text = "一键升级"
		up_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		up_all_btn.disabled = _sys().get_recipe_prof(rid) < _sys().get_recipe_upgrade_cost(rid)
		up_all_btn.pressed.connect(func(): _on_recipe_upgrade(rid, true))
		btn_row.add_child(up_all_btn)

func _on_recipe_unlock(rid: String):
	var r := _sys().unlock_recipe(rid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

func _on_recipe_upgrade(rid: String, batch: bool):
	var r := _sys().upgrade_recipe(rid, batch)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	_refresh()

# ---------- 子页：成就（3条线；已领取不显示，只显示最上面一档未领取，【改】2026-09-16 用户拍板） ----------
func _fill_ach(body: VBoxContainer):
	for line in _sys().get_ach_list():
		var lid: String = str(line.get("id", ""))
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#2a2640")
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		card.add_theme_stylebox_override("panel", style)
		body.add_child(card)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		card.add_child(vb)
		var progress := _sys().get_ach_progress(lid)
		var head := Label.new()
		head.text = "%s（%s）　当前 %s" % [line.get("name", lid), line.get("desc", ""), c.format_number(progress)]
		head.add_theme_font_size_override("font_size", 16)
		vb.add_child(head)
		var tiers: Array = line.get("tiers", [])
		var claimed: int = _sys().get_ach_claimed(lid)
		if claimed < tiers.size():
			# 只显示当前最低未领取档（上面的档已领完不再显示）
			_add_ach_tier_row(vb, lid, claimed, tiers[claimed])
		elif lid == "patients":
			# 病人线32档领满：封顶后每多接待 step 病人可再领一次末档奖励（可重复）
			_add_repeat_row(vb)

# 单个档位行：门槛 + 四道具奖励文案 + 领取按钮（未达成禁用）
func _add_ach_tier_row(vb: VBoxContainer, lid: String, tier_idx: int, tier: Dictionary):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	# 奖励文案（道具名走 ITEM_CONFIG，不臆测）
	var parts := []
	for r in tier.get("rewards", []):
		var iid: String = str(r.get("item", ""))
		var iname: String = data.ITEM_CONFIG.get(iid, {}).get("name", iid)
		parts.append("%s×%d" % [iname, int(r.get("count", 0))])
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "第%d档 %s　%s" % [tier_idx + 1, c.format_number(int(tier.get("need", 0))), "、".join(parts)]
	row.add_child(info)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(72, 30)
	btn.text = "领取"
	btn.disabled = not _sys().can_claim_ach(lid, tier_idx)
	var lid_c: String = lid
	var i_c: int = tier_idx
	btn.pressed.connect(func(): _on_ach_claim(lid_c, i_c))
	row.add_child(btn)

# 病人线满档后重复领取行：进度 X/10000 + 领取按钮
func _add_repeat_row(vb: VBoxContainer):
	var rp: Dictionary = _sys().get_repeat_progress()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	# 末档四道具文案
	var tiers: Array = []
	for line in _sys().get_ach_list():
		if str(line.get("id", "")) == "patients":
			tiers = line.get("tiers", [])
	var parts := []
	if not tiers.is_empty():
		for r in tiers[tiers.size() - 1].get("rewards", []):
			var iid: String = str(r.get("item", ""))
			var iname: String = data.ITEM_CONFIG.get(iid, {}).get("name", iid)
			parts.append("%s×%d" % [iname, int(r.get("count", 0))])
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "已领满32档，每多接待 %s 病人可再领：%s（进度 %s/%s）" % [
		c.format_number(int(rp.get("need", 10000))), "、".join(parts),
		c.format_number(int(rp.get("have", 0))), c.format_number(int(rp.get("need", 10000)))]
	row.add_child(info)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(72, 30)
	btn.text = "领取"
	btn.disabled = not _sys().can_claim_repeat()
	btn.pressed.connect(_on_repeat_claim)
	row.add_child(btn)

func _on_ach_claim(lid: String, tier_idx: int):
	var r := _sys().claim_ach(lid, tier_idx)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("获得 %s" % str(r.get("rewards", "")))
	_refresh()

# 【新增】病人线满档后重复领取末档奖励
func _on_repeat_claim():
	var r := _sys().claim_repeat()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "")))
		return
	c._show_stage_hint("获得 %s" % str(r.get("rewards", "")))
	_refresh()
