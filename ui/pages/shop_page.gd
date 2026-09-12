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

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

# ============ 三十六节批次1：商铺页地图化（横版三排街景） ============
# 地图底图=三排建筑街景（每排 7 栋 = 21 店铺，画中建筑与店铺块一一对应）；
# 布局 3 行 × 7 列网格（代码布局，禁锚点——本工程布局铁律），Z 字形阅读顺序（按解锁等级）；
# 钱庄(总部)按拍板固定"最左最中间"=第 2 行第 1 列；浏览=横向拖动（触屏原生支持），拖动条按拍板隐身
# 美术占位规范（零配置丢图即用）：
#   地图底图：res://assets/shops/map_bg.png（三排建筑街景长图，高宽比≈1:3 最佳），
#     代码会按图片真实比例反推内容高度保证零裁切；缺失兜底色块
#   单栋建筑图：res://assets/shops/<shop_id>.png（如 ke_zhan.png），缺失时半透明色块底
const BUILDING_IMG_DIR := "res://assets/shops/"
const MAP_BG_IMG := "res://assets/shops/map_bg.png"
# 特色玩法七店（钱庄=总部 hq 在地图"最左最中间"；其余 6 店挂 24×24 玩法入口占位钮，批次2+ 逐个接通）
const PLAY_SHOPS := ["hq", "ke_zhan", "yi_guan", "yao_pu", "jiu_fang", "jiu_si", "miaoyin_fang"]
const MAP_ROWS := 3   # 街景三排建筑
const MAP_COLS := 7   # 每排 7 栋 = 21 店铺
const MAP_PAD := 16
const MAP_GAP := 16   # 建筑间距
const MAP_BLD_SIZE := Vector2(276, 150)   # 单栋建筑占位块（≈画中单栋建筑大小）
# 【新增】画中建筑对位表（比例坐标 0~1，店块中心）：有 entry 的店精确压在画中建筑上，
# 未配置的店退回 7×3 网格。用户圈图报店名，AI 逐步填表迭代（2026-09-11 约定）
const SHOP_POS := {
	"hq": Vector2(0.123, 0.381),   # 钱庄（红圈·09-11）
	"ke_zhan": Vector2(0.114, 0.547),   # 客栈（蓝圈·09-11）
	"yi_guan": Vector2(0.097, 0.680),   # 医馆（粉圈·09-11）
	"xiangliao_pu": Vector2(0.257, 0.069),   # 香料铺（09-12 二调：左下挪）
	"shuoshu_tan": Vector2(0.230, 0.225),   # 说书摊（黑圈·09-11）
	"dang_pu": Vector2(0.365, 0.177),   # 当铺（蓝圈·09-12 重测：上一批截图拖动过坐标作废）
	"yi_zhan": Vector2(0.464, 0.391),   # 驿站（黑框·09-12 五调）
	"jiu_si": Vector2(0.347, 0.383),   # 酒肆（黑框·09-12 七调：往上提）
	"yao_pu": Vector2(0.241, 0.693),   # 药铺（黑圈·09-12 重测）
	"miaoyin_fang": Vector2(0.358, 0.517),   # 妙音坊（绿圈·09-12 重测）
	"biao_ju": Vector2(0.944, 0.191),   # 镖局（黄圈·09-12 最右端截图折算：fx=0.584+视口内比例×0.416）
	"yao_chang": Vector2(0.952, 0.406),   # 窑厂/药厂（黑圈·09-12 最右端）
	"zao_tang": Vector2(0.949, 0.720),   # 澡堂（红圈·09-12 最右端）
	"cha_si": Vector2(0.838, 0.565),   # 茶肆（绿圈·09-12 最右端）
	"xi_lou": Vector2(0.735, 0.713),   # 戏楼（蓝圈·09-12 最右端）
	"chengyi_pu": Vector2(0.472, 0.183),   # 成衣铺（黑圈·09-12 中间截图：用戏楼反推视口 0.353~0.769 折算）
	"chema_hang": Vector2(0.610, 0.185),   # 车马行（绿圈·09-12 中间）
	"changle_fang": Vector2(0.700, 0.426),   # 长乐坊（红圈·09-12 四调：再右半步压准圈内楼阁）
	"jiu_fang": Vector2(0.586, 0.704),   # 酒坊（蓝圈·09-12 中间）
	"chuan_wu": Vector2(0.439, 0.887),   # 船坞（粉圈·09-12 中间）
	"suanming_tan": Vector2(0.559, 0.564),   # 算命摊（绿框·09-12 二调：右挪）
}
# 【新增】店块形状覆盖表（默认横牌 187×100）：竖长画建筑用竖牌贴合楼形（用户 09-12 拍板）
const SHOP_SIZE := {
	"hq": Vector2(95, 150),   # 钱庄楼：竖楼（09-12 二调：原 115×185 偏大挤占客栈）
	"yi_guan": Vector2(95, 150),   # 医馆：竖楼（二调同上）
	"yao_pu": Vector2(100, 150),   # 药铺：竖楼（二调顺手收小）
	"shuoshu_tan": Vector2(95, 145),   # 说书摊：竖棚（二调顺手收小）
	"ke_zhan": Vector2(150, 80),   # 客栈：画中小楼，牌子稍小
	"dang_pu": Vector2(100, 150),   # 当铺：竖牌（09-12 三调：横牌与成衣铺/车马行重叠）
	"chengyi_pu": Vector2(100, 150),   # 成衣铺：竖牌（同上）
	"chuan_wu": Vector2(100, 150),   # 船坞：竖牌（用户指定）
	"jiu_si": Vector2(95, 120),   # 酒肆：竖牌降高 95×120（09-12 六调）
}

func generate_shop_list():
	if not c.has_node("PageContainer/ShopPage/ShopScroll/ShopList"): return
	var scroll: ScrollContainer = c.get_node("PageContainer/ShopPage/ShopScroll")
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
	scroll.theme = th
	var content: Control = scroll.get_node("ShopList")
	for child in content.get_children():
		child.queue_free()

	# 【修】内容高度直接取滚动容器实际分配的视口高度（地面真值）：
	# 竖向只容纳整幅图、零裁切——之前用 get_viewport_rect 推算与实际滚动区有出入，导致只显示图高约 1/3（2026-09-11 用户复现）
	var map_h := int(scroll.size.y)
	if map_h < 100:
		map_h = int(c.get_viewport_rect().size.y) - 118   # 回退：布局未就绪时用视口推算（顶栏50+留白8+底栏60）
	if map_h < 320:
		map_h = 320   # 保底，防启动瞬间视口异常

	# 按解锁等级（平手按 SHOP_ORDER 原序）排序，得阅读顺序
	var infos := []
	for i in range(data.SHOP_ORDER.size()):
		var sid: String = data.SHOP_ORDER[i]
		infos.append({"id": sid, "ch": data.get_shop_unlock_chapter(sid), "ord": i})
	infos.sort_custom(func(a, b): return a.ch < b.ch or (a.ch == b.ch and a.ord < b.ord))

	# 尺寸推导：有底图按图比例定宽（高已定死=可视高，零变形）；无底图用固定 7 列宽
	var bg_tex: Texture2D = null
	var map_w := 32 + MAP_COLS * (int(MAP_BLD_SIZE.x) + MAP_GAP) - MAP_GAP
	if ResourceLoader.exists(MAP_BG_IMG):
		bg_tex = load(MAP_BG_IMG) as Texture2D   # as 转型+空值守卫：JPEG 伪装 .png 时 load 返回 null（2026-09-11 用户踩坑）
		if bg_tex != null:
			var isz := bg_tex.get_size()
			if isz.y > 0:
				map_w = floori(map_h * isz.x / isz.y)
	# 建筑块尺寸：按内容尺寸塞进 7×3 网格（有图时随图缩放，保证一一对应画中建筑）
	var gap := MAP_GAP
	var bld_w := floori((map_w - MAP_PAD * 2 - (MAP_COLS - 1) * gap) / float(MAP_COLS))
	var row_h := floori((map_h - MAP_PAD * 2) / float(MAP_ROWS))
	var bld_h := mini(100, row_h - 20)   # 【改】100：纯名字牌无需高块（原 150 钱庄显大）；mini 返回 int：min() 返回 Variant 会被 := 推断成 Variant（项目把该警告当错误）
	var bld_size := Vector2(bld_w, bld_h)
	var hq_row := floori(MAP_ROWS * 0.5)   # 钱庄行：中间排；floori 返回 int（n/2 会被 := 推断成 float 报整数除法警告，且槽位匹配会失配）

	# 地图底图：铺满内容节点（高=可视高、宽=按比例，零裁切零变形），缺图兜底色块
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.name = "MapBg"
		bg.texture = bg_tex
		bg.expand = true   # 【修】Godot4 默认 false=最小尺寸锁死为贴图原始大小，set size 被顶回 2576×1696 只显示左上角 56%（调试牌实锤）
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.position = Vector2.ZERO
		bg.size = Vector2(map_w, map_h)
		content.add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.name = "MapBg"
		bg.color = Color("#2e2a26")
		bg.position = Vector2.ZERO
		bg.size = Vector2(map_w, map_h)
		content.add_child(bg)
		var tip := Label.new()
		tip.text = "地图底图缺失：把三排建筑街景长图存为 res://assets/shops/map_bg.png 即自动生效"
		tip.position = Vector2(MAP_PAD, 8)
		tip.add_theme_color_override("font_color", Color("#8a8178"))
		content.add_child(tip)

	# Z 字形槽位序列：偶数行左→右，奇数行右→左（阅读顺序按解锁等级）
	var slots := []
	for r in range(MAP_ROWS):
		for k in range(MAP_COLS):
			var col := k
			if r % 2 == 1:
				col = MAP_COLS - 1 - k
			slots.append({"row": r, "col": col})
	# 钱庄 C 位："最左最中间"=第 2 行第 1 列（视觉位）
	var hq_idx := -1
	for i in range(slots.size()):
		if slots[i]["row"] == hq_row and slots[i]["col"] == 0:
			hq_idx = i
			break
	# 行内垂直居中偏移
	var y_off := floori((row_h - bld_h) * 0.5)
	# 钱庄建筑（总部，点击开总部面板）——有对位表 entry 时精确压画中钱庄楼，否则退回"最左最中间"C 位；
	# 店块尺寸：形状覆盖表优先（竖牌/小牌按实际尺寸居中），默认横牌
	var hq_size: Vector2 = SHOP_SIZE.get("hq", bld_size)
	if SHOP_POS.has("hq"):
		_add_building(content, "hq", Vector2(SHOP_POS["hq"].x * map_w - hq_size.x * 0.5, SHOP_POS["hq"].y * map_h - hq_size.y * 0.5), hq_size)
	else:
		_add_building(content, "hq", Vector2(MAP_PAD, MAP_PAD + hq_row * row_h + y_off), hq_size)
	# 其余店铺按阅读顺序落位（跳过钱庄槽）
	var idx := 0
	for i in range(infos.size()):
		if idx == hq_idx:
			idx += 1
		var s: Dictionary = slots[idx]
		var sid: String = str(infos[i]["id"])
		var sz: Vector2 = SHOP_SIZE.get(sid, bld_size)   # 形状覆盖表优先
		var pos: Vector2
		if SHOP_POS.has(sid):
			# 对位表优先：店块中心精确压画中建筑（比例坐标 × 地图尺寸 - 实际半块）
			pos = Vector2(SHOP_POS[sid].x * map_w - sz.x * 0.5, SHOP_POS[sid].y * map_h - sz.y * 0.5)
		else:
			pos = Vector2(MAP_PAD + s["col"] * (bld_w + gap), MAP_PAD + s["row"] * row_h + y_off)
		_add_building(content, sid, pos, sz)
		idx += 1

	# 内容节点显式尺寸：宽高喂足 ScrollContainer 才有横滚（布局铁律：显式 position/size）
	content.custom_minimum_size = Vector2(map_w, map_h)
	content.size = Vector2(map_w, map_h)


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
	bld.size = bld_size   # 随地图缩放（窗口矮时建筑块同步缩小，保持与画中建筑一一对应）
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
		play.pressed.connect(func(): c._show_stage_hint("【%s】特色玩法开发中，敬请期待" % play_shop_name))
		bld.add_child(play)

func on_shop_entry_pressed(shop_id: String):
	if data.shops.has(shop_id):
		open_shop_panel(shop_id)
	elif data.can_unlock_shop(shop_id):
		if data.unlock_shop(shop_id):
			c.update_all_ui()
			c._show_stage_hint("解锁【%s】成功！" % data.get_shop_config(shop_id).name)
			open_shop_panel(shop_id)
	else:
		var need = data.get_shop_unlock_chapter(shop_id)
		c._show_stage_hint("【%s】通关第%d章解锁" % [data.get_shop_config(shop_id).name, need])

func _show_hero_assign_selector(slot: int):
	if c.current_shop_id == "": return
	c.close_popup()  # 先关闭店铺面板，防止遮挡
	c._current_popup = null  # 清空弹窗记录，避免全局点击误关
	
	var overlay = c.get_node("Overlay")
	overlay.show()
	
	var selector = PanelContainer.new()
	selector.name = "AssignSelector"
	selector.custom_minimum_size = Vector2(500, 400)
	 # 【修】原硬编码 Vector2(326,150) 在 600 宽基准分辨率下导致弹窗偏右出界，
	#       改按当前视口尺寸动态居中（与 _create_base_popup 居中逻辑一致）
	var vs = c.get_viewport_rect().size
	selector.position = Vector2((vs.x - 500) / 2, (vs.y - 400) / 2)
	selector.z_index = 20
	
	 # 【修】补弹窗背景样式，解决默认背景过淡与底层混淆
	var sel_style = StyleBoxFlat.new()
	sel_style.bg_color = Color("#1e1b2e")   # 弹窗统一底色；觉得不够深可改 #15121e
	sel_style.set_corner_radius_all(12)
	selector.add_theme_stylebox_override("panel", sel_style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	selector.add_child(vbox)
	
	var title = Label.new()
	title.text = "选择门客派遣到【%s】" % data.shops[c.current_shop_id].name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 280)
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
		# 【修】手机端：按钮默认 STOP 拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.pressed.connect(_on_hero_assigned.bind(hero_id, slot))
		list.add_child(btn)
	
	if not has_idle:
		var empty = Label.new()
		empty.text = "暂无可派遣门客"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_close_assign_selector)
	vbox.add_child(cancel_btn)
	
	c.add_child(selector)


func _close_assign_selector():
	if c.has_node("AssignSelector"):
		c._safe_close("AssignSelector")
	c.get_node("Overlay").hide()
	# 重新打开店铺面板
	if c.current_shop_id != "":
		c.open_popup(c.get_node("ShopPanel"))
		update_shop_panel()

func _on_hero_assigned(hero_id: String, _slot: int):
	data.heroes[hero_id].assigned_shop = c.current_shop_id
	_close_assign_selector()
	update_shop_panel()
	c.update_all_ui()
	c.update_hero_list()

func _on_hero_unassign(hero_id: String):
	data.heroes[hero_id].assigned_shop = ""
	update_shop_panel()
	c.update_all_ui()
	c.update_hero_list()

func open_hq_panel():
	if c.has_node("HQPanel"):
		c.open_popup(c.get_node("HQPanel"))
		update_hq_panel()

func close_hq_panel():
	c.close_popup()
	c.update_hero_list()

func open_shop_panel(shop_id: String):
	c.current_shop_id = shop_id
	if c.has_node("ShopPanel"):
		c.open_popup(c.get_node("ShopPanel"))
		update_shop_panel()

func close_shop_panel():
	c.close_popup()
	c.current_shop_id = ""



func on_hq_click():
	data.money += data.hq.click_income
	c.update_all_ui()
	c.animate_button("HQPanel/HQClickBtn")

func on_hq_upgrade():
	if data.upgrade_hq():
		c.update_all_ui()
		c.update_bag_list()
	else:
		c.flash_red("HQPanel/HQUpgradeBtn")

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
	if c.current_shop_id != "" and c.has_node("ShopPanel") and c.get_node("ShopPanel").visible:
		update_shop_panel()

func update_entry_buttons():
	if not c.has_node("PageContainer/ShopPage/ShopScroll/ShopList"): return
	var content = c.get_node("PageContainer/ShopPage/ShopScroll/ShopList")
	for bld in content.get_children():
		if not (bld is Panel) or not bld.has_meta("shop_id"): continue
		var shop_id: String = bld.get_meta("shop_id")
		var btn: Button = bld.get_node("BuildingBtn")
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
	if c.has_node("HQPanel/VBoxContainer/HQName"):
		c.get_node("HQPanel/VBoxContainer/HQName").text = "【%s】Lv.%d" % [data.hq.name, data.hq.level]
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
	
	if c.has_node("ShopPanel/VBoxContainer/ShopName"):
		c.get_node("ShopPanel/VBoxContainer/ShopName").text = "【%s】Lv.%d" % [s.name, s.level]
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
