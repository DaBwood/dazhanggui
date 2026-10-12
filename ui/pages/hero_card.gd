# ============================================================
# 门客卡片模板（hero_card.tscn 的脚本）：只负责数据绑定与外观刷新
# 点击/信号接线由 hero_page.gd 统一持有（bind_data 不接信号）
# ============================================================
extends Button

const ICON_DIR := "res://assets/heroes/"
const CAREER_ICON := {"士": "career_shi", "农": "career_nong", "工": "career_gong", "商": "career_shang", "侠": "career_xia"}

@onready var portrait: TextureRect = $Portrait
@onready var bg_panel: Panel = $BgPanel
@onready var lv_label: Label = $LvLabel
@onready var name_label: Label = $NameLabel
@onready var career_icon: TextureRect = $CareerIcon
@onready var career_fb: Label = $CareerFallback
@onready var status_label: Label = $StarStrip/StatusLabel

func bind_data(hero_id: String, data, locked: bool) -> void:
	set_meta("hero_id", hero_id)
	set_meta("locked", locked)
	var cfg = data.get_hero_config(hero_id)
	# 卡片=免抠立绘（heroes_card 优先）+ 当前品质纯色底
	var p_card := "res://assets/portraits/heroes_card/%s.png" % hero_id
	var p_full := "res://assets/portraits/heroes/%s.png" % hero_id
	portrait.texture = null
	if ResourceLoader.exists(p_card):
		portrait.texture = load(p_card)
	elif ResourceLoader.exists(p_full):
		portrait.texture = load(p_full)
	var q_col = Color(HeroData.get_quality_color(int(data.heroes[hero_id].get("quality", 0)) if data.heroes.has(hero_id) else 0))
	var bg_sty := StyleBoxFlat.new()
	bg_sty.bg_color = q_col
	bg_sty.set_corner_radius_all(6)
	bg_panel.add_theme_stylebox_override("panel", bg_sty)
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
	# 职业图标（缺图退化职业字）
	var cat := ""
	if cfg:
		cat = str(cfg.get("category", ""))
	var has_icon := CAREER_ICON.has(cat) and ResourceLoader.exists(ICON_DIR + str(CAREER_ICON.get(cat, "")) + ".png")
	career_icon.visible = has_icon
	if has_icon:
		career_icon.texture = load(ICON_DIR + str(CAREER_ICON[cat]) + ".png")
	career_fb.visible = not has_icon
	career_fb.text = cat
	# 精进星条 / VIP 解锁
	if locked:
		status_label.text = "VIP%d解锁" % data.get_hero_unlock_vip(hero_id)
		status_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.88))
	else:
		status_label.text = data.talent_system.get_star_text(hero_id)
		status_label.add_theme_color_override("font_color", Color(1, 0.84, 0.3))
	# 品质边框（每次新建 stylebox，防跨卡共享被覆盖）
	var quality := 0
	if data.heroes.has(hero_id):
		quality = int(data.heroes[hero_id].get("quality", 0))
	elif cfg:
		quality = int(cfg.get("quality", 0))
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color("#232035")
	sty.border_color = Color(HeroData.get_quality_color(quality))
	sty.set_border_width_all(2)
	sty.set_corner_radius_all(8)
	for k in ["normal", "hover", "pressed"]:
		add_theme_stylebox_override(k, sty)
