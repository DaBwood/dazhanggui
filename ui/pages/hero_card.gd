# ============================================================
# 门客卡片模板（hero_card.tscn 的脚本）：只负责数据绑定与外观刷新
# 点击/信号接线由 hero_page.gd 统一持有（bind_data 不接信号）
# ============================================================
extends Button

const ICON_DIR := "res://assets/common/"
const CAREER_ICON := {"士": "career_shi", "农": "career_nong", "工": "career_gong", "商": "career_shang", "侠": "career_xia"}

@onready var portrait: TextureRect = $Portrait
@onready var bg_panel: Panel = $BgPanel
@onready var lv_label: Label = $LvLabel
@onready var name_label: Label = $NameLabel
@onready var career_icon: TextureRect = $CareerIcon
@onready var career_fb: Label = $CareerFallback
@onready var status_label: Label = $StarStrip/StatusLabel

# ── 全列表共享缓存（只读，禁止在别处修改这些 StyleBox / Texture 实例）──
# 背景：109 张卡 × 每次重绑 = 218 个 StyleBoxFlat + 218 次 ResourceLoader.exists + 109 次 PNG 解码，
# 进门客页会明显卡一瞬；同品质样式/职业图标/立绘路径都是有限集合，缓存后每卡只查表。
static var _bg_styles: Dictionary = {}        # quality -> StyleBoxFlat
static var _border_styles: Dictionary = {}    # quality -> StyleBoxFlat
static var _career_tex: Dictionary = {}       # category -> Texture2D / null
static var _portrait_paths: Dictionary = {}   # hero_id -> 立绘路径（""=无图）

func bind_data(hero_id: String, data, locked: bool) -> void:
	set_meta("hero_id", hero_id)
	set_meta("locked", locked)
	var cfg = data.get_hero_config(hero_id)
	# 卡片=穿戴服装优先（非默认且有图）→免抠立绘（heroes_card 优先）→全幅立绘，+ 当前品质纯色底
	# 【性能】只在路径变化时换图：旧实现每轮先 texture=null 再 load，会释放并重新解码 PNG
	# （69 张缩略图实测约 184 ms/轮），且每轮都触发重绘。
	var cos_p: String = data.costume_system.get_worn_cos_path(hero_id)
	var p := cos_p if cos_p != "" else _resolve_portrait_path(hero_id)
	if not has_meta("portrait_path") or str(get_meta("portrait_path")) != p:
		set_meta("portrait_path", p)
		portrait.texture = load(p) if p != "" else null
	# 品质（样式缓存键；锁定卡无存档数据时回落到配置品质）
	var quality := 0
	if data.heroes.has(hero_id):
		quality = int(data.heroes[hero_id].get("quality", 0))
	elif cfg:
		quality = int(cfg.get("quality", 0))
	# 【性能】同品质共用一份样式；品质未变则跳过 add_theme_*_override（每次调用都会触发主题重建）
	if not has_meta("style_quality") or int(get_meta("style_quality")) != quality:
		set_meta("style_quality", quality)
		bg_panel.add_theme_stylebox_override("panel", _get_bg_style(quality))
		var sty := _get_border_style(quality)
		for k in ["normal", "hover", "pressed"]:
			add_theme_stylebox_override(k, sty)
	modulate = Color(0.5, 0.5, 0.5, 0.7) if locked else Color.WHITE
	# 等级（精进满级口径：copy_max_level 参与展示）
	var show_lv := 1
	if data.heroes.has(hero_id):
		show_lv = int(data.heroes[hero_id].level)
		var copy_lv = data.talent_system.get_copy_level(hero_id)
		if copy_lv > 0:
			show_lv = maxi(show_lv, copy_lv)
	elif cfg:
		show_lv = int(cfg.get("level", 1))
	lv_label.text = str(show_lv)
	# 名字竖排
	var parts := PackedStringArray()
	for ch in str(cfg.get("name", hero_id)) if cfg else hero_id:
		parts.append(ch)
	name_label.text = "\n".join(parts)
	# 职业图标（缺图退化职业字；图标只有 5 种，按职业缓存纹理与存在性）
	var cat := ""
	if cfg:
		cat = str(cfg.get("category", ""))
	var ctex: Texture2D = null
	if CAREER_ICON.has(cat):
		if not _career_tex.has(cat):
			var cp := ICON_DIR + str(CAREER_ICON[cat]) + ".png"
			_career_tex[cat] = load(cp) if ResourceLoader.exists(cp) else null
		ctex = _career_tex[cat]
	var has_icon := ctex != null
	career_icon.visible = has_icon
	if has_icon and career_icon.texture != ctex:
		career_icon.texture = ctex
	career_fb.visible = not has_icon
	career_fb.text = cat
	# 精进星条 / VIP 解锁（颜色只在锁定态切换时重设，避免每轮主题重建）
	if locked:
		status_label.text = "VIP%d解锁" % data.get_hero_unlock_vip(hero_id)
		if str(get_meta("status_kind", "")) != "locked":
			set_meta("status_kind", "locked")
			status_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.88))
	else:
		status_label.text = data.talent_system.get_star_text(hero_id)
		if str(get_meta("status_kind", "")) != "unlocked":
			set_meta("status_kind", "unlocked")
			status_label.add_theme_color_override("font_color", Color(1, 0.84, 0.3))

# 立绘路径只解析一次（heroes_card 优先，缺图回落全幅；负结果也缓存）
func _resolve_portrait_path(hero_id: String) -> String:
	if _portrait_paths.has(hero_id):
		return str(_portrait_paths[hero_id])
	var p := ""
	var p_card := "res://assets/portraits/heroes_card/%s.png" % hero_id
	if ResourceLoader.exists(p_card):
		p = p_card
	else:
		var p_full := "res://assets/portraits/heroes/%s.png" % hero_id
		if ResourceLoader.exists(p_full):
			p = p_full
	_portrait_paths[hero_id] = p
	return p

# 同品质共用背景样式（只读；原实现每卡新建，注释担心共享被覆盖，但全仓只有本文件写这两个槽）
static func _get_bg_style(quality: int) -> StyleBoxFlat:
	if not _bg_styles.has(quality):
		var s := StyleBoxFlat.new()
		s.bg_color = Color(HeroData.get_quality_color(quality))
		s.set_corner_radius_all(6)
		_bg_styles[quality] = s
	return _bg_styles[quality]

static func _get_border_style(quality: int) -> StyleBoxFlat:
	if not _border_styles.has(quality):
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#232035")
		s.border_color = Color(HeroData.get_quality_color(quality))
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		_border_styles[quality] = s
	return _border_styles[quality]
