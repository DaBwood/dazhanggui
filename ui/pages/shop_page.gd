# ============================================================
# 商铺页（含钱庄面板/店员分配）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name ShopPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用
var _batch_hire: bool = false   # 【新增】批A：十连招募勾选类变量记忆（商铺面板改工厂弹窗后节点每次重建，状态不能存节点上）
var _assign_selector_open: bool = false   # 【新增】批A：派遣选择器开着标记——ShopPanel 销毁回调据此区分"✕关闭清店铺id"与"选派派遣流程主动销毁"

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

# ============ 场景化批次2：商铺页骨架化（2026-10-07，模板=闯荡页批次1/3 v2 范式） ============
# 布局唯一真相源=shop_page.tscn（骨架/底图/入口层/帮助钮），本脚本只实例化+灌内容（21 栋建筑）
# 底图契约：res://assets/shops/map_bg.png（3630×1155 新街市图，2026-10-07 用户重绘），
#   按 1067 设计高零变形铺宽 3353≈5.6 屏横滑，点击/竖牌坐标全部走 SHOP_POS 比例对位表
const SHOP_SCENE := preload("res://ui/pages/shop_page.tscn")
const BUILDING_IMG_DIR := "res://assets/shops/"
const MAP_BG_IMG := "res://assets/shops/map_bg.png"
const MAP_SIZE := Vector2(3353, 1067)   # 设计尺寸=MapContent 最小尺寸（新图比例按 1067 高推导）
# 特色玩法七店（钱庄=总部 hq 在地图"最左最中间"；其余 6 店挂 24×24 玩法入口占位钮，批次2+ 逐个接通）
const PLAY_SHOPS := ["hq", "ke_zhan", "yi_guan", "yao_pu", "jiu_fang", "jiu_si", "miaoyin_fang"]

# 【新增】批次C（2026-09-19 重构）：特色玩法「▶」入口的视图映射——表驱动替代 7 段 if/elif 链，
# 新增带入口的店铺=这里加一行。红点哪些店铺有（PLAY_SHOP_DOTS）与可见条件（_play_dot_visible）集中管理
const PLAY_SHOP_VIEWS := {
	"hq": "bank",               # 钱庄：柜台委任/百业经验/筹算值/信誉值
	"ke_zhan": "inn",           # 客栈：营业/菜谱/庖丁解牛/兑换商店
	"yi_guan": "clinic",        # 医馆：病人队列/科室升级/病症图鉴
	"yao_pu": "drugshop",       # 药铺：体力接待/收益罐/工艺/药方/勋章/成就
	"jiu_fang": "winery",       # 酒坊：三作坊/酿酒/采买/勋章/名酒记/品酒/酒客故事
	"miaoyin_fang": "miaoyin",  # 妙音坊：主页/收益罐/加速卡/勋章/新秀/选秀
	"jiu_si": "tavern",         # 酒肆：叫号接待/收益罐/餐饮娱乐设施
}
# 地图侧有红点的店铺（红点 Label 恒创建、visible 随条件切，update_entry_buttons 靠 has_node("PlayBtn/PlayDot") 找到它）
const PLAY_SHOP_DOTS := ["yi_guan", "yao_pu", "jiu_si"]
const DEFAULT_PLATE := Vector2(170, 92)   # 默认横牌（固定设计尺寸下不再随窗口缩放）
# 画中建筑对位表（比例坐标 0~1，店块中心）：新图 21 店全量覆盖，无网格回退——
# 2026-10-07 AI 按新图目测填首版，沿用老约定"用户圈图报店名，逐步迭代修正"
const SHOP_POS := {
	"hq": Vector2(0.116, 0.216),   # 钱庄：左区主楼（ grand 门脸+灯笼 ）
	"jiu_si": Vector2(0.207, 0.104),   # 酒肆：红枫酒楼
	"miaoyin_fang": Vector2(0.283, 0.176),   # 妙音坊：鼓面亭阁
	"ke_zhan": Vector2(0.198, 0.371),   # 客栈：左区大宅
	"yao_pu": Vector2(0.075, 0.431),   # 药铺：左区沿街铺面
	"shuoshu_tan": Vector2(0.088, 0.526),   # 说书摊：铺前空场
	"yi_guan": Vector2(0.148, 0.721),   # 医馆：左下院落
	"biao_ju": Vector2(0.247, 0.90),   # 镖局：台阶大宅（深门大院）
	"xiangliao_pu": Vector2(0.306, 0.792),   # 香料铺： Pagoda 塔楼
	"xi_lou": Vector2(0.471, 0.372),   # 戏楼：中区大红楼
	"changle_fang": Vector2(0.375, 0.363),   # 长乐坊：红楼左栋
	"jiu_fang": Vector2(0.503, 0.110),   # 酒坊：水畔石塔（地标）
	"chuan_wu": Vector2(0.628, 0.187),   # 船坞：水上吊脚仓
	"cha_si": Vector2(0.685, 0.155),   # 茶肆：水岸青瓦茶屋
	"chengyi_pu": Vector2(0.940, 0.130),   # 成衣铺：右上宅院
	"yao_chang": Vector2(0.858, 0.662),   # 窑厂：带烟囱作坊
	"zao_tang": Vector2(0.955, 0.78),   # 澡堂：右下独院
	"suanming_tan": Vector2(0.435, 0.65),   # 算命摊：集市伞摊群中
	"dang_pu": Vector2(0.495, 0.835),   # 当铺：下区蓝瓦宅（高门挡户）
	"yi_zhan": Vector2(0.70, 0.735),   # 驿站：右区大棚客舍
	"chema_hang": Vector2(0.40, 0.80),   # 车马行：下区街面小宅
}
# 店块形状覆盖表（默认横牌 170×92）：塔楼/竖长画建筑用竖牌贴合楼形
const SHOP_SIZE := {
	"jiu_fang": Vector2(100, 150),   # 酒坊：石塔竖牌
	"xiangliao_pu": Vector2(100, 150),   # 香料铺：塔楼竖牌
	"miaoyin_fang": Vector2(105, 140),   # 妙音坊：亭阁竖牌
	"hq": Vector2(165, 95),   # 钱庄：门脸横牌（压主楼入口）
	"ke_zhan": Vector2(170, 95),   # 客栈：宅门横牌
	"jiu_si": Vector2(160, 90),   # 酒肆：酒楼横牌
}

func generate_shop_list():
	if not c.has_node("PageContainer/ShopPage"): return
	var page = c.get_node("PageContainer/ShopPage")

	for child in page.get_children():
		child.free()

	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)

	var inst: Control = SHOP_SCENE.instantiate()
	page.add_child(inst)

	# 结构硬校验：缺件即报错中断（废兜底自愈，口径同闯荡页批次1——结构正确时冗余、错误时掩盖真因）
	var vbox := inst.get_node("ShopVBox") as VBoxContainer
	var map_scroll := vbox.get_node("MapScroll") as ScrollContainer
	# 编辑器里 clip_contents=false 全图可视可拖（tscn 设置）；运行时必须恢复裁剪，否则地图溢出视口
	map_scroll.clip_contents = true
	var map_content := map_scroll.get_node("MapContent") as Control
	var entry_grid := map_content.get_node("ShopEntryGrid") as Control
	_map_scroll = map_scroll

	# 帮助钮在 tscn 右上角锚定（口径同闯荡页），脚本只接管信号
	var main_help := inst.get_node("MainHelpButton") as Button
	main_help.pressed.connect(func(): _show_shop_help())

	# 拖动条隐身（用户拍板不要拖动条）：主题清空 HScrollBar 全部样式+图标，跨版本免 API 依赖
	#（get_h_scrollbar 在 4.7.1 报 Nonexistent function，不纠缠节点 API）
	var th := Theme.new()
	var empty := StyleBoxEmpty.new()
	for st in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed",
			"increment", "increment_highlight", "decrement", "decrement_highlight"]:
		th.set_stylebox(st, "HScrollBar", empty)
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	var transparent: Texture2D = ImageTexture.create_from_image(img)
	th.set_icon("increment_icon", "HScrollBar", transparent)
	th.set_icon("decrement_icon", "HScrollBar", transparent)
	map_scroll.theme = th

	# 底图契约见 MAP_BG_IMG 注释：缺图不渲染、布局不塌
	var bg := map_content.get_node("BgImage") as TextureRect
	if ResourceLoader.exists(MAP_BG_IMG):
		bg.texture = load(MAP_BG_IMG)

	# 滑动吸附（口径同闯荡页）：scroll_ended 只在用户滚动停时发，补间改值不重入
	map_scroll.scroll_ended.connect(_on_map_scroll_ended)

	# 21 栋建筑：SHOP_POS 比例对位 × 设计尺寸（新图全量覆盖，无网格回退）；
	# 建筑是状态驱动的动态牌（解锁态/红点/文字板随刷新变），按 v2 范式留在脚本侧灌内容
	for shop_id in ["hq"] + data.SHOP_ORDER:
		var sz: Vector2 = SHOP_SIZE.get(shop_id, DEFAULT_PLATE)
		var pos := Vector2(SHOP_POS[shop_id].x * MAP_SIZE.x - sz.x * 0.5, SHOP_POS[shop_id].y * MAP_SIZE.y - sz.y * 0.5)
		_add_building(entry_grid, shop_id, pos, sz)

	# 结构自检：输出面板打印一次关键事实（布局争议先看这里，定位是结构问题还是坐标问题）
	print("[ShopMap] 建筑=%d 横向滚动余量=%d MapContent=%s" % [
		entry_grid.get_child_count(),
		int(map_scroll.get_h_scroll_bar().max_value - map_scroll.get_h_scroll_bar().page),
		str(map_content.size)])


# 【新增】店名文字板文案：板宽按字数估算、店块内居中（Label 尺寸当帧不可知，显式定）
func _set_plate_text(bld: Panel, txt: String):
	var plate: Label = bld.get_node("NamePlate")
	plate.text = txt
	var w := float(txt.length()) * 15.0 + 24.0
	plate.size = Vector2(w, 30)
	plate.position = Vector2((bld.size.x - w) * 0.5, (bld.size.y - 30) * 0.5)

# 【新增】单栋建筑：半透明底（图/色块，压在街景图上保证文字可读）+ 全幅 Button（点击进店铺/解锁）+ 玩法入口小钮（24×24，特色店才有）
func _add_building(content: Control, shop_id: String, pos: Vector2, bld_size: Vector2):
	var bld := Panel.new()
	bld.name = "bld_" + shop_id
	bld.position = pos
	bld.size = bld_size   # 固定设计尺寸牌面（MAP_SIZE 常量表推导，窗口变化不重建）
	bld.set_meta("shop_id", shop_id)   # 刷新文字按 meta 取，不解析节点名（新规：引用先验证）
	# 底图：丢图即用；默认透明底——只显示名字（用户 09-12 拍板：黑框压画不好看），
	# 文字可读性靠 Button 侧黑描边（见下）
	var img_path: String = BUILDING_IMG_DIR + shop_id + ".png"
	if ResourceLoader.exists(img_path):
		var st := StyleBoxTexture.new()
		st.texture = load(img_path)
		bld.add_theme_stylebox_override("panel", st)
	else:
		bld.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	content.add_child(bld)
	# 全幅透明点击区（flat 无底色无字，专职点按）
	var btn := Button.new()
	btn.name = "BuildingBtn"
	btn.flat = true
	btn.position = Vector2.ZERO
	btn.size = bld_size
	# 【新增】NamePlate 文字板：字底一块小圆角半透明底板（不是整片黑框），居中托名字
	var plate := Label.new()
	plate.name = "NamePlate"
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_theme_font_size_override("font_size", 15)
	plate.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	plate.add_theme_constant_override("outline_size", 3)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.09, 0.07, 0.05, 0.72)   # 深褐半透明：压花画可读又不遮建筑
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 10
	ps.content_margin_right = 10
	ps.content_margin_top = 3
	ps.content_margin_bottom = 3
	plate.add_theme_stylebox_override("normal", ps)
	bld.add_child(plate)
	# 生成即写名字（不再依赖 update_entry_buttons 兜底）
	if shop_id == "hq":
		_set_plate_text(bld, "【钱庄】")
	else:
		var cfg0: Dictionary = data.get_shop_config(shop_id)
		_set_plate_text(bld, "【%s】" % cfg0.get("name", shop_id))
	if shop_id == "hq":
		btn.pressed.connect(c.open_hq_panel)
	else:
		btn.pressed.connect(on_shop_entry_pressed.bind(shop_id))
	bld.add_child(btn)
	# 特色玩法入口占位钮：批次2+ 逐个接通玩法页，现在点击提示开发中
	if PLAY_SHOPS.has(shop_id):
		var play := Button.new()
		play.name = "PlayBtn"
		play.text = "▶"
		play.position = Vector2(bld_size.x - 30, 6)
		play.size = Vector2(24, 24)
		var play_shop_name: String = "钱庄"
		if shop_id != "hq":
			play_shop_name = str(data.get_shop_config(shop_id).get("name", ""))
		if PLAY_SHOP_VIEWS.has(shop_id):
			# 【改】批次C：if/elif 链 → 表驱动；红点 Label 对 PLAY_SHOP_DOTS 内店铺恒创建（visible 随条件），
			# 与旧行为一致——update_entry_buttons 靠 has_node("PlayBtn/PlayDot") 找它做后续刷新
			play.pressed.connect(c.show_view.bind(PLAY_SHOP_VIEWS[shop_id]))
			if PLAY_SHOP_DOTS.has(shop_id):
				var dot := Label.new()
				dot.name = "PlayDot"
				dot.text = "●"
				dot.add_theme_color_override("font_color", Color("#e74c3c"))
				dot.add_theme_font_size_override("font_size", 14)
				dot.position = Vector2(14, -7)   # 「▶」钮右上角（父钮 24×24，红点按常量定位）
				dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				dot.visible = _play_dot_visible(shop_id)
				play.add_child(dot)
		else:
			play.pressed.connect(func(): c._show_success_popup("【%s】特色玩法开发中，敬请期待" % play_shop_name, 0.0, "ok"))   # 【改】飘字退休→ok 弹窗
		bld.add_child(play)

# 【新增】批次C：地图侧「▶」红点唯一条件（各玩法内部红点互不穿透，2026-09-16 口径）——
# 医馆/药铺=病人满；酒肆=有可升级或可解锁设施；其余玩法无地图侧红点（页内展示）
func _play_dot_visible(shop_id: String) -> bool:
	match shop_id:
		"yi_guan":
			return data.clinic_system.is_patients_full()
		"yao_pu":
			return data.drugshop_system.is_patients_full()
		"jiu_si":
			return data.tavern_system.has_upgradeable_facility() or data.tavern_system.has_unlockable_facility()
	return false


func on_shop_entry_pressed(shop_id: String):
	if data.shops.has(shop_id):
		open_shop_panel(shop_id)
	elif data.can_unlock_shop(shop_id):
		if data.unlock_shop(shop_id):
			c.update_all_ui()
			# 【改】成功反馈铺开：解锁成功弹窗
			c._show_success_popup("解锁成功\n【%s】" % data.get_shop_config(shop_id).name)
			open_shop_panel(shop_id)
	else:
		var need = data.get_shop_unlock_chapter(shop_id)
		c._show_success_popup("【%s】通关第%d章解锁" % [data.get_shop_config(shop_id).name, need], 0.0, "ok")   # 【改】飘字退休→ok 弹窗

func _show_hero_assign_selector(slot: int):
	if c.current_shop_id == "": return
	# 【改】UI统一批A：店铺面板已是工厂弹窗，按名销毁（原 close_popup 持久面板方案作废）；
	#  标记置真——ShopPanel 销毁回调据此不清 current_shop_id（本流程还要用）
	_assign_selector_open = true
	c._safe_close("ShopPanel")

	# 【改】迁弹窗工厂：遮罩/✕/居中/竖屏钳制全接管（原手动 Overlay+自建样式+【取消】钮作废）
	var panel = c._create_base_popup("选择门客派遣到【%s】" % data.shops[c.current_shop_id].name, Vector2(500, 400))
	panel.name = "AssignSelector"
	# 任何关闭路径（✕/遮罩点击/选派完成）销毁后都重开店铺面板
	panel.tree_exiting.connect(_on_assign_selector_closed)
	var vbox = panel.get_child(0)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 300)
	vbox.add_child(scroll)

	var list = VBoxContainer.new()
	scroll.add_child(list)

	# 显示所有"闲置"门客
	var has_idle = false
	for hero_id in data.heroes.keys():
		var h = data.heroes[hero_id]
		if h.assigned_shop != "": continue  # 已派遣的跳过

		has_idle = true
		var btn = Button.new()
		var income = data.get_hero_income(hero_id)
		btn.text = "【%s】%s Lv.%d | %s/秒" % [h.name, h.category, h.level, c.format_number(income)]
		# 手机端：按钮默认 STOP 拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.pressed.connect(_on_hero_assigned.bind(hero_id, slot))
		list.add_child(btn)

	if not has_idle:
		var empty = Label.new()
		empty.text = "暂无可派遣门客"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)

	c.add_child(panel)

# 【新增】批A：派遣选择器销毁回调（tree_exiting）——复位标记并重开店铺面板
func _on_assign_selector_closed():
	_assign_selector_open = false
	if c.current_shop_id != "":
		# 【修】tree_exiting 回调内引擎正处理节点删除，父节点 busy 禁止 add_child（报 Parent node is busy
		#  setting up children，面板建不出来→update_shop_panel 连环 null），重开推迟一帧出回调再执行
		call_deferred("_reopen_shop_panel_deferred")

# 【新增】批A：推迟一帧的店铺面板重开（配合 _on_assign_selector_closed）
func _reopen_shop_panel_deferred():
	# 防御：延迟期间店铺 id 被清/面板已被别的路径重建则不动作
	if c.current_shop_id == "" or c.has_node("ShopPanel"): return
	_build_shop_panel_popup()
	update_shop_panel()

# 【新增】批A：商铺面板销毁回调（tree_exiting）——✕/遮罩点击关闭时清店铺 id；
#  派遣选择器流程主动销毁时标记为真，保留 id 供选择器与重开使用
func _on_shop_panel_closed():
	if not _assign_selector_open:
		c.current_shop_id = ""

func _close_assign_selector():
	# 【改】批A：只负责销毁；重开店铺面板由 tree_exiting（_on_assign_selector_closed）接管
	c._safe_close("AssignSelector")

func _on_hero_assigned(hero_id: String, _slot: int):
	data.heroes[hero_id].assigned_shop = c.current_shop_id
	_close_assign_selector()
	# 【改】批A：不再此处 update_shop_panel——店铺面板由 tree_exiting 重开并刷新
	c.update_all_ui()
	c.update_hero_list()

func _on_hero_unassign(hero_id: String):
	data.heroes[hero_id].assigned_shop = ""
	update_shop_panel()
	c.update_all_ui()
	c.update_hero_list()

# 【新增】批A：总部面板构建器（迁弹窗工厂——打开时创建、关闭即销毁，原 controller 持久场景面板作废）
func _build_hq_panel_popup():
	var panel = c._create_base_popup("总部", Vector2(480, 320))
	panel.name = "HQPanel"
	# ✕/遮罩点击关闭后刷新门客列表（原 close_hq_panel 语义，挂 tree_exiting 覆盖一切关闭路径）
	panel.tree_exiting.connect(func(): c.update_hero_list())
	var hb = panel.get_child(0)
	hb.name = "VBoxContainer"   # 【新增】命名对齐既有节点路径（update_hq_panel/flash_red 按此取值）
	var hq_info = Label.new()
	hq_info.name = "HQInfo"
	hb.add_child(hq_info)
	var hq_row = HBoxContainer.new()
	hq_row.name = "HBoxContainer"
	hb.add_child(hq_row)
	var hq_click = Button.new()
	hq_click.name = "HQClickBtn"
	# 【改】批次B13：工厂点击钮放大（默认小钮 → 120×44 主操作钮）
	hq_click.custom_minimum_size = Vector2(120, 44)
	hq_click.add_theme_font_size_override("font_size", 13)
	hq_click.text = c.TXT_HQ_CLICK
	hq_click.pressed.connect(on_hq_click)   # 【改】启动期 connect 挪入构建器（面板随建随连）
	hq_row.add_child(hq_click)
	var hq_up = Button.new()
	hq_up.name = "HQUpgradeBtn"
	# 【改】批次B13：工厂升级钮放大（默认小钮 → 120×44 主操作钮）
	hq_up.custom_minimum_size = Vector2(120, 44)
	hq_up.add_theme_font_size_override("font_size", 13)
	hq_up.pressed.connect(on_hq_upgrade)
	hq_row.add_child(hq_up)
	c.add_child(panel)

# 【新增】批A：商铺面板构建器（同总部迁工厂）
func _build_shop_panel_popup():
	var panel = c._create_base_popup("商铺", Vector2(560, 640))
	panel.name = "ShopPanel"
	# ✕/遮罩点击关闭时清 current_shop_id；派遣选择器流程主动销毁（标记为真）则保留
	panel.tree_exiting.connect(_on_shop_panel_closed)
	var sb = panel.get_child(0)
	sb.name = "VBoxContainer"   # 【新增】命名对齐既有节点路径
	var s_info = Label.new()
	s_info.name = "ShopInfo"
	sb.add_child(s_info)
	var s_row = HBoxContainer.new()
	s_row.name = "HBoxContainer"
	sb.add_child(s_row)
	var s_up = Button.new()
	s_up.name = "ShopUpgradeBtn"
	# 【改】批次B13：商铺升级钮放大（默认小钮 → 120×44 主操作钮）
	s_up.custom_minimum_size = Vector2(120, 44)
	s_up.add_theme_font_size_override("font_size", 13)
	s_up.pressed.connect(on_current_shop_upgrade)
	s_row.add_child(s_up)
	var s_hire = Button.new()
	s_hire.name = "ShopHireBtn"
	# 【改】批次B13：商铺招募钮放大（默认小钮 → 120×44 主操作钮）
	s_hire.custom_minimum_size = Vector2(120, 44)
	s_hire.add_theme_font_size_override("font_size", 13)
	s_hire.pressed.connect(on_current_shop_hire)
	s_row.add_child(s_hire)
	var s_batch = CheckBox.new()
	s_batch.name = "BatchHireCheck"
	s_batch.text = c.TXT_BATCH_HIRE
	s_batch.button_pressed = _batch_hire   # 【改】勾选状态从类变量回灌（connect 前赋值不触发 toggled）
	s_batch.toggled.connect(_on_batch_hire_toggled)
	s_row.add_child(s_batch)
	var assign_box = VBoxContainer.new()
	assign_box.name = "AssignContainer"
	assign_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sb.add_child(assign_box)
	for i in 5:
		var slot = HBoxContainer.new()
		slot.name = "AssignSlot_%d" % i
		assign_box.add_child(slot)
		var lbl = Label.new()
		lbl.name = "AssignLabel"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.add_child(lbl)
		var btn = Button.new()
		btn.name = "AssignBtn"
		# 【改】批次B13：派遣槽钮放大（默认小钮 → 120×44，5 槽循环一并生效）
		btn.custom_minimum_size = Vector2(120, 44)
		btn.add_theme_font_size_override("font_size", 13)
		slot.add_child(btn)
	c.add_child(panel)

func open_hq_panel():
	# 【改】批A：工厂弹窗，未开才建（原 open_popup 显隐持久面板作废）
	if not c.has_node("HQPanel"):
		_build_hq_panel_popup()
	update_hq_panel()

func close_hq_panel():
	# 【改】批A：按名销毁（连带遮罩）；update_hero_list 由 tree_exiting 接管
	c._safe_close("HQPanel")

func open_shop_panel(shop_id: String):
	c.current_shop_id = shop_id
	# 【改】批A：工厂弹窗，未开才建
	if not c.has_node("ShopPanel"):
		_build_shop_panel_popup()
	update_shop_panel()

func close_shop_panel():
	# 【改】批A：按名销毁（连带遮罩）；current_shop_id 清理由 tree_exiting 接管
	c._safe_close("ShopPanel")



func on_hq_click():
	data.money += data.hq.click_income
	c.update_all_ui()
	c.animate_button("HQPanel/HQClickBtn")

func on_hq_upgrade():
	if data.upgrade_hq():
		c.update_all_ui()
		c.update_bag_list()
	else:
		c.flash_red("HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn")   # 【修】路径缺 VBoxContainer/HBoxContainer 中段，has_node 恒 false 永不闪红（2026-09-19 用户实测）

func on_current_shop_upgrade():
	if data.upgrade_shop(c.current_shop_id):
		c.update_all_ui()
		c.update_bag_list()
	else:
		c.flash_red("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn")

func on_current_shop_hire():
	var batch = false
	if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck"):
		batch = c.get_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck").button_pressed
	
	var count = 10 if batch else 1
	var success = 0
	for i in range(count):
		if data.hire_staff(c.current_shop_id):
			success += 1
		else:
			break
	
	if success > 0:
		c.update_all_ui()
	else:
		c.flash_red("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn")

func _on_batch_hire_toggled(_pressed: bool):
	_batch_hire = _pressed   # 【改】批A：勾选状态进类变量（面板重建后回灌）
	if c.current_shop_id != "" and c.has_node("ShopPanel"):
		update_shop_panel()

func update_entry_buttons():
	if not c.has_node("PageContainer/ShopPage/ShopScene/ShopVBox/MapScroll/MapContent/ShopEntryGrid"): return
	var content = c.get_node("PageContainer/ShopPage/ShopScene/ShopVBox/MapScroll/MapContent/ShopEntryGrid")
	for bld in content.get_children():
		if not (bld is Panel) or not bld.has_meta("shop_id"): continue
		var shop_id: String = bld.get_meta("shop_id")
		var btn: Button = bld.get_node("BuildingBtn")
		# 【新增】2026-09-16 药铺「▶」病人满红点随 UI 刷新（自然恢复满/用药超出后，任意 update_all_ui 汇流时点亮）
		if shop_id == "yao_pu" and bld.has_node("PlayBtn/PlayDot"):
			bld.get_node("PlayBtn/PlayDot").visible = data.drugshop_system.is_patients_full()
		# 【新增】2026-09-16 医馆「▶」病人满红点随 UI 刷新
		if shop_id == "yi_guan" and bld.has_node("PlayBtn/PlayDot"):
			bld.get_node("PlayBtn/PlayDot").visible = data.clinic_system.is_patients_full()
			# 【新增】2026-09-16 酒肆「▶」红点随 UI 刷新（设施可升级/可解锁点亮）
		if shop_id == "jiu_si" and bld.has_node("PlayBtn/PlayDot"):
			bld.get_node("PlayBtn/PlayDot").visible = data.tavern_system.has_upgradeable_facility() or data.tavern_system.has_unlockable_facility()
		if shop_id == "hq":
			_set_plate_text(bld, "【钱庄】")   # 【改】纯名字牌（用户 09-12 拍板不显示信息）
			btn.modulate = Color.WHITE
			btn.disabled = false
			continue
		var cfg = data.get_shop_config(shop_id)
		if cfg.is_empty(): continue
		# 文字两行，单行太长会撑出视口
		if data.shops.has(shop_id):
			# 【改】纯名字牌（用户 09-12 拍板）：详细收益信息在店铺面板里看，地图只导航
			_set_plate_text(bld, "【%s】" % data.shops[shop_id].get("name", cfg.get("name", "?")))
			btn.modulate = Color.WHITE
			btn.disabled = false
		elif data.can_unlock_shop(shop_id):
			_set_plate_text(bld, "【%s】" % cfg.name)
			btn.modulate = Color("#e0c070")   # 可解锁：金色
			btn.disabled = false
		else:
			_set_plate_text(bld, "【%s】🔒" % cfg.name)   # 【改】加锁标+亮灰（2026-09-12）
			btn.modulate = Color(0.85, 0.85, 0.85, 0.95)
			btn.disabled = false   # 【改】锁定也可点：点击弹"通关第X章解锁"提示（on_shop_entry_pressed else 分支），disabled 会让玩家点不动、条件无处可查

func update_hq_panel():
	if c.has_node("HQPanel/VBoxContainer/PopupTitle"):
		# 【改】批A：名字行并入工厂标题（原 HQName 内层 Label 删除）
		c.get_node("HQPanel/VBoxContainer/PopupTitle").text = "【%s】Lv.%d" % [data.hq.name, data.hq.level]
	if c.has_node("HQPanel/VBoxContainer/HQInfo"):
		var auto = data.get_hq_auto_income()
		var bonus = data.get_global_bonus_percent() * 100
		c.get_node("HQPanel/VBoxContainer/HQInfo").text = "挂机 %s/秒  |  点击 +%s  |  全局加成 +%d%%" % [c.format_number(auto), c.format_number(data.hq.click_income), bonus]
	if c.has_node("HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn"):
		c.get_node("HQPanel/VBoxContainer/HBoxContainer/HQUpgradeBtn").text = "🔨 升级（%d图纸）" % data.hq.upgrade_cost

func update_shop_panel():
	if c.current_shop_id == "": return
	var s = data.shops[c.current_shop_id]
	var cost = s.hire_cost
	
	if c.has_node("ShopPanel/VBoxContainer/PopupTitle"):
		# 【改】批A：名字行并入工厂标题（原 ShopName 内层 Label 删除）
		c.get_node("ShopPanel/VBoxContainer/PopupTitle").text = "【%s】Lv.%d" % [s.name, s.level]
	if c.has_node("ShopPanel/VBoxContainer/ShopInfo"):
		var income = data.get_shop_auto_income(c.current_shop_id)
		c.get_node("ShopPanel/VBoxContainer/ShopInfo").text = "赚速 %s/秒  |  店员 %d人" % [c.format_number(income), s.staff]
	if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn"):
		c.get_node("ShopPanel/VBoxContainer/HBoxContainer/ShopUpgradeBtn").text = "🔨 升级（%d道具）" % s.upgrade_cost
	if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn"):
		var batch = false
		if c.has_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck"):
			batch = c.get_node("ShopPanel/VBoxContainer/HBoxContainer/BatchHireCheck").button_pressed
		
		if batch:
			var total_cost = 0
			var temp_cost = cost
			for i in range(10):
				total_cost += temp_cost
				temp_cost = int(ceil(temp_cost * 1.01))
			c.get_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn").text = "👤 招募（%s铜钱）" % c.format_number(total_cost)
		else:
			c.get_node("ShopPanel/VBoxContainer/HBoxContainer/ShopHireBtn").text = "👤 招募（%s铜钱）" % c.format_number(cost)
	
	
	# 更新槽位内容
	var assign_box = c.get_node("ShopPanel/VBoxContainer/AssignContainer")
	
	# 收集当前店铺已派遣的门客
	var assigned_heroes: Array = []
	for hero_id in data.heroes.keys():
		if data.heroes[hero_id].assigned_shop == c.current_shop_id:
			assigned_heroes.append(hero_id)
	
	for slot in range(5):
		var row = assign_box.get_node("AssignSlot_" + str(slot))
		var label = row.get_node("AssignLabel")
		var btn = row.get_node("AssignBtn")
		
		# 断开旧信号
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)
		
		if slot == 4:
			label.text = "【派遣位5】任务解锁"
			btn.text = "封禁"
			btn.disabled = true
			continue
		
		var assigned_id = assigned_heroes[slot] if slot < assigned_heroes.size() else ""
		
		if assigned_id != "":
			var h = data.heroes[assigned_id]
			label.text = "【%s】%s | %s/秒" % [h.name, h.category, c.format_number(data.get_hero_income(assigned_id))]
			btn.text = "撤下"
			btn.disabled = false
			btn.pressed.connect(_on_hero_unassign.bind(assigned_id))
		else:
			label.text = "【派遣位%d】空闲" % (slot + 1)
			btn.text = "派遣"
			btn.disabled = false
			btn.pressed.connect(_show_hero_assign_selector.bind(slot))

var _map_snapping := false
var _map_scroll: ScrollContainer = null

# 横向地图按屏吸附：页宽=滚动视口宽（运行时实际像素，不吃设计尺寸）；滚动器引用由 generate 注入
func _on_map_scroll_ended() -> void:
	if _map_snapping or _map_scroll == null:
		return
	var page_w := _map_scroll.size.x
	if page_w <= 0:
		return
	var target := int(roundf(_map_scroll.scroll_horizontal / page_w) * page_w)
	if abs(target - _map_scroll.scroll_horizontal) < 2:
		return
	_map_snapping = true
	var tw := _map_scroll.create_tween()
	tw.tween_property(_map_scroll, "scroll_horizontal", target, 0.25)
	tw.finished.connect(func(): _map_snapping = false)

func _show_shop_help():
	var popup = c._create_base_popup("玩法说明", Vector2(440, 0), Vector2.ZERO, false)
	var vb = popup.get_child(0)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = "商铺是赚钱主力：21 家店通关章节依次解锁，点击建筑打开店铺面板分配门客；店名金色=可解锁、亮灰加锁=未解锁（点击看条件）；「▶」进特色玩法（钱庄/客栈/医馆/药铺/酒坊/妙音坊/酒肆），红点=店内有事待办。左右滑动地图逛全城。"
	vb.add_child(lbl)
	c.add_child(popup)
