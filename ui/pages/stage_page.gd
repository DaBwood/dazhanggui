# ============================================================
# 关卡页（第3批重构：从 game_controller.gd 拆分而来；最近批次见档案 §十一）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# data = GameData 数据中枢
# 2026-10-06 场景化改版：骨架=stage_page.tscn（布局唯一真相源），本脚本只管灌内容与数值
# ============================================================
class_name StagePage
extends RefCounted

var c
var data

const STAGE_SCENE := preload("res://ui/pages/stage_page.tscn")
const SCENE_ROOT := "PageContainer/StagePage/StageScene"
# 素材契约：正式图放 res://assets/stage/ 下同名文件；缺图时对应节点自动隐藏，布局不塌
const BG_PATH := "res://assets/stage/bg.png"
const GATE_PATH := "res://assets/stage/gate.png"
const CARRIAGE_PATH := "res://assets/stage/carriage.png"
const BOSS_PATH := "res://assets/stage/boss.png"
const BOSS_CARRIAGE_PATH := "res://assets/stage/boss_carriage.png"
# 按钮皮肤契约（用户供图）：议价=头目态，贸易=常规，一键贸易=左下
const BTN_BARGAIN_PATH := "res://assets/stage/btn_bargain.png"
const BTN_TRADE_PATH := "res://assets/stage/btn_trade.png"
const BTN_AUTO_PATH := "res://assets/stage/btn_auto.png"

var _tex_bargain: Texture2D = null
var _tex_trade: Texture2D = null
var _tex_auto: Texture2D = null

func _init(p_c):
	c = p_c
	data = p_c.data
	_tex_bargain = _load_tex(BTN_BARGAIN_PATH)
	_tex_trade = _load_tex(BTN_TRADE_PATH)
	_tex_auto = _load_tex(BTN_AUTO_PATH)

func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path)

func generate_stage_page():
	if not c.has_node("PageContainer/StagePage"): return
	var page: Control = c.get_node("PageContainer/StagePage")

	# 用 free() 立即释放而非 queue_free：延迟到帧末会让同名新实例被自动改名（StageScene2），按名查找路径断裂
	for child in page.get_children():
		child.free()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)

	var inst: Control = STAGE_SCENE.instantiate()
	inst.name = "StageScene"
	page.add_child(inst)

	var back := inst.get_node_or_null("TopRow/BackButton") as Button
	if back: back.pressed.connect(func(): c.switch_page("adventure"))
	var help := inst.get_node_or_null("TopRow/HelpButton") as Button
	if help: help.pressed.connect(func(): c._show_rule_popup("关卡", "挑战关卡获得闯荡币与道具；章节通关解锁下一章，失败会给出战力提示。"))

	# 背景图：正式底图就位前先用商铺街道图占位，别留空底（素材就位后删 elif 分支）
	var bg := inst.get_node_or_null("BgImage") as TextureRect
	if bg:
		if ResourceLoader.exists(BG_PATH):
			bg.texture = load(BG_PATH)
		elif ResourceLoader.exists("res://assets/shops/map_bg.png"):
			bg.texture = load("res://assets/shops/map_bg.png")

	# 关卡行（用户拍板⑧⑨）：城门徽章（图标+关卡数上下）+ 进度条，一行横排
	var head: HBoxContainer = _ensure_child(inst, "StageHead", func():
		var hb := HBoxContainer.new()
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_theme_constant_override("separation", 10)
		return hb)
	var badge: VBoxContainer = _ensure_child(head, "StageBadge", func():
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		return v)
	var gate := _ensure_child(badge, "GateIcon", func():
		var t := TextureRect.new()
		t.custom_minimum_size = Vector2(48, 48)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t) as TextureRect
	if gate and ResourceLoader.exists(GATE_PATH):
		gate.texture = load(GATE_PATH)
	_ensure_child(badge, "StageTitle", func():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color("#ffd700"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l)
	_ensure_child(head, "ProgressTrack", func():
		var t := Control.new()
		t.custom_minimum_size = Vector2(80, 36)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t)

	# 进度条皮肤（轨道/填充/5 节点）=动态内容，灌进 tscn 占位容器
	var track := inst.get_node_or_null("StageHead/ProgressTrack") as Control
	if track:
		# 无暗板后可见性口径（用户拍板⑪）：深青轨道打底+亮金填充，衬在浅色街景上
		var track_bg := ColorRect.new()
		track_bg.name = "TrackBg"
		track_bg.color = Color(0.16, 0.32, 0.28)
		track.add_child(track_bg)
		var fill := ColorRect.new()
		fill.name = "TrackFill"
		fill.color = Color(0.95, 0.78, 0.15)
		track.add_child(fill)
		for i in range(6):
			var dot := Panel.new()
			dot.name = "Dot%d" % i
			var st := StyleBoxFlat.new()
			st.set_corner_radius_all(7)
			st.bg_color = Color(0.4, 0.4, 0.4)
			dot.add_theme_stylebox_override("panel", st)
			track.add_child(dot)
		# 构建当帧容器未排序（尺寸=0），布局落定后靠 resized 补一次刷新
		track.resized.connect(func(): update_stage_page())

	var carriage := inst.get_node_or_null("Carriage") as TextureRect
	if carriage:
		if ResourceLoader.exists(CARRIAGE_PATH):
			carriage.texture = load(CARRIAGE_PATH)
		else:
			carriage.visible = false

	var boss_avatar := inst.get_node_or_null("StageHead/BossSlot/BossAvatar") as TextureRect
	if boss_avatar:
		if ResourceLoader.exists(BOSS_PATH):
			boss_avatar.texture = load(BOSS_PATH)
		else:
			boss_avatar.visible = false

	var auto_btn := inst.get_node_or_null("AutoTradeBtn") as Button
	if auto_btn:
		auto_btn.set_pressed_no_signal(data.stage_auto_trade)
		auto_btn.toggled.connect(_on_stage_auto_toggled)
		var auto_icon := auto_btn.get_node_or_null("AutoTradeIcon") as TextureRect
		if auto_icon and _tex_auto:
			auto_icon.texture = _tex_auto
	var trade_btn := inst.get_node_or_null("TradeBtn") as Button
	if trade_btn:
		trade_btn.pressed.connect(_on_trade_pressed)

func update_stage_page():
	var inst := c.get_node_or_null(SCENE_ROOT) as Control
	if inst == null: return

	# 一键贸易停止原因：进页/刷新时消费弹出（停止当下不弹，点进关卡页才弹）
	if data.stage_auto_stop_reason != "":
		c._show_success_popup("一键贸易已停止：%s" % data.stage_auto_stop_reason, 4.0, "ok")
		data.stage_auto_stop_reason = ""

	# 章-关简称口径（用户拍板⑧）："38-4"；铜钱/阅历挪顶排「闯关」两侧，跟随实时数据
	var title := inst.get_node_or_null("StageHead/StageBadge/StageTitle") as Label
	if title: title.text = "%d-%d" % [data.stage_main, data.stage_sub]
	var top_money := inst.get_node_or_null("TopRow/TopMoney") as Label
	if top_money: top_money.text = "铜钱：%s" % c.format_number(data.money)
	var top_exp := inst.get_node_or_null("TopRow/TopExp") as Label
	if top_exp: top_exp.text = "阅历：%s" % c.format_number(data.items.experience)

	var carriage_label := inst.get_node_or_null("CarriageLabel") as Label
	if carriage_label:
		carriage_label.text = "门客赚钱：%s" % c.format_number(data.get_heroes_total_income())
		# 黑底只包文字不溢出（用户拍板⑧）：按内容最小宽度收窄并水平居中
		var ms: Vector2 = carriage_label.get_minimum_size()
		carriage_label.size.x = ms.x
		carriage_label.position.x = (c.size.x - ms.x) * 0.5

	_update_progress(inst)

	var boss_ready: bool = data.is_stage_boss_ready()
	# 钮下只挂铜钱花费（用户拍板：口径=折后实际花费）；皮肤随头目态切换
	var trade_label := inst.get_node_or_null("TradeLabel") as Label
	var trade_btn := inst.get_node_or_null("TradeBtn") as Button
	var discount: float = clampf(float(data.get_stage_boss_income()) / float(maxi(data.get_heroes_total_income(), 1)), 0.1, 1.0)
	var actual_cost := int(data.get_stage_trade_cost() * discount)
	if trade_label:
		trade_label.text = "铜钱：%s" % c.format_number(actual_cost)
		if trade_btn:
			_hug_label(trade_label, trade_btn.position.x + trade_btn.size.x * 0.5)
	if trade_btn:
		var trade_icon := trade_btn.get_node_or_null("TradeIcon") as TextureRect
		if trade_icon:
			trade_icon.texture = _tex_bargain if boss_ready else _tex_trade
	# 头目头像含自带"头目"红幅（用户供图 2026-10-06），文字标签退役
	# 头目头像常驻进度条右端（用户拍板⑱：不用隐藏，非 Boss 关也候场）
	var boss_avatar := inst.get_node_or_null("StageHead/BossSlot/BossAvatar") as TextureRect
	if boss_avatar: boss_avatar.visible = boss_avatar.texture != null
	# Boss 关街面出现头目轿子+赚钱标签（用户拍板⑫），非 Boss 关常隐
	var boss_carriage := inst.get_node_or_null("BossCarriage") as TextureRect
	if boss_carriage:
		boss_carriage.visible = boss_ready
		if boss_carriage.texture == null and ResourceLoader.exists(BOSS_CARRIAGE_PATH):
			boss_carriage.texture = load(BOSS_CARRIAGE_PATH)
	var boss_carriage_label := inst.get_node_or_null("BossCarriageLabel") as Label
	if boss_carriage_label:
		boss_carriage_label.visible = boss_ready
		if boss_ready:
			boss_carriage_label.text = "头目赚钱：%s" % c.format_number(data.get_stage_boss_income())
			_hug_label(boss_carriage_label, c.size.x * 0.5)

	# 勾选状态与数据层同步（自动停止后回弹按钮；no_signal 避免触发回写）
	var auto_btn := inst.get_node_or_null("AutoTradeBtn") as Button
	if auto_btn:
		auto_btn.set_pressed_no_signal(data.stage_auto_trade)
		auto_btn.modulate = Color(1.35, 1.2, 0.75) if data.stage_auto_trade else Color(1, 1, 1)
		var auto_label := inst.get_node_or_null("AutoTradeLabel") as Label
		if auto_label:
			_hug_label(auto_label, auto_btn.position.x + auto_btn.size.x * 0.5)

func _update_progress(inst: Control):
	var track := inst.get_node_or_null("StageHead/ProgressTrack") as Control
	if track == null or track.size.x <= 0: return
	var w := track.size.x
	var h := track.size.y
	var bg := track.get_node_or_null("TrackBg") as ColorRect
	if bg:
		bg.position = Vector2(0, (h - 8) * 0.5)
		bg.size = Vector2(w, 8)
	# 口径（修订⑰）：6 节点 5 段=5 小关+头目终点。第 k 小关起点落第 k 节点，头目出现拉满到第 6 节点
	var done := (float(data.stage_sub - 1) + float(mini(data.stage_trade_count, 3)) / 3.0) / 5.0
	if data.is_stage_boss_ready(): done = 1.0
	var fill := track.get_node_or_null("TrackFill") as ColorRect
	if fill:
		fill.position = Vector2(0, (h - 8) * 0.5)
		fill.size = Vector2(w * done, 8)
	for i in range(6):
		var dot := track.get_node_or_null("Dot%d" % i) as Panel
		if dot == null: continue
		dot.position = Vector2(w * float(i) / 5.0 - 7, (h - 14) * 0.5)
		dot.size = Vector2(14, 14)
		if i == 5:
			# 第 6 节点=头目位：平时灰，头目出现转红
			dot.modulate = Color(0.9, 0.3, 0.3) if data.is_stage_boss_ready() else Color(0.4, 0.4, 0.4)
		elif data.is_stage_boss_ready() or i < data.stage_sub - 1:
			dot.modulate = Color("#ffd700")
		elif i == data.stage_sub - 1:
			dot.modulate = Color("#ffffff")
		else:
			dot.modulate = Color(0.4, 0.4, 0.4)

# 暗牌贴合文字并水平居中到参照点（钮下标签/轿面标签共用，拍板：底不溢出文字）
func _hug_label(label: Label, center_x: float):
	var ms: Vector2 = label.get_minimum_size()
	label.size.x = ms.x
	label.position.x = center_x - ms.x * 0.5

# 骨架缺件兜底：tscn 节点被误删时自建并标好容器标志，不阻断运行
func _ensure_child(parent: Node, node_name: String, make: Callable):
	if parent.has_node(node_name):
		return parent.get_node(node_name)
	var n: Node = make.call()
	n.name = node_name
	parent.add_child(n)
	return n

# 【改】头目出现=右侧钮变议价（用户拍板 2026-10-06 关卡改版）：谈判与贸易合并同一入口
func _on_trade_pressed():
	if data.is_stage_boss_ready():
		on_stage_boss()
	else:
		on_stage_trade()

func _on_stage_auto_toggled(pressed: bool):
	data.stage_auto_trade = pressed

func on_stage_trade():
	var result: Dictionary = data.do_stage_trade()
	if not result.ok:
		c.flash_red(SCENE_ROOT + "/TradeBtn")
		return

	update_stage_page()
	c.update_all_ui()
	c.update_bag_list()

	# 普通贸易静默，只有关键节点才提示（口径同 main 原版）
	if result.type == "next_sub":
		c._show_success_popup("通关！宝箱×1  阅历+%d" % result.get("exp_reward", 0), 0.0, "ok")
	elif result.type == "boss_ready":
		c._show_success_popup("贸易完成，Boss 已出现！", 0.0, "ok")
func on_stage_boss():
	var result: Dictionary = data.do_stage_boss()
	if not result.ok:
		c.flash_red(SCENE_ROOT + "/TradeBtn")
		return

	if result.win:
		c._show_success_popup("谈判成功\n声望 +10　抽奖券 +1")
	else:
		c.flash_red(SCENE_ROOT + "/TradeBtn")
		c._show_success_popup("谈判失败！Boss 赚速 %s，我方仅 %s" % [
			c.format_number(result.boss_income),
			c.format_number(result.hero_power)
		], 0.0, "warn")

	update_stage_page()
	c.update_all_ui()
	c.update_bag_list()
	c.update_entry_buttons()
