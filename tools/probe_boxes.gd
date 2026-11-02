extends SceneTree
# 临时验证：五个素装盒/五个锦衣盒/一个锦盒是否都入库并能打开选择器

const BOXES := [
	"friend_cos_box_miao_jiang_shengnv", "friend_cos_box_qing_ning",
	"friend_cos_box_ning_yin", "friend_cos_box_bu_kuai", "friend_cos_box_zhou_meili",
	"friend_jinyi_box_miao_jiang_shengnv", "friend_jinyi_box_qing_ning",
	"friend_jinyi_box_ning_yin", "friend_jinyi_box_bu_kuai", "friend_jinyi_box_zhou_meili",
	"friend_multi_box",
]


func _init() -> void:
	var gd = load("res://game_data.gd")
	var d = gd.new()
	print("[items] 配置条数=", d.ITEM_CONFIG.size())
	for id in BOXES:
		var cfg: Dictionary = d.ITEM_CONFIG.get(id, {})
		print("  ", id, " name=", cfg.get("name", "MISSING"), " type=", cfg.get("use", {}).get("type", ""))
	# 重命名的八类
	for id in ["hero_box", "item_box", "friend_box", "cos_box", "manhuang_box", "hun_gu_box",
			"soul_wushuang_box", "wushuang_cuzhi_box"]:
		print("  rename ", id, " -> ", d.ITEM_CONFIG.get(id, {}).get("name", "MISSING"))
	# 五位挚友的素装/锦衣条目数量
	for fid in ["miao_jiang_shengnv", "qing_ning", "ning_yin", "bu_kuai", "zhou_meili"]:
		var cfgs: Array = d.costume_system.get_friend_costume_cfgs(fid)
		var su := 0
		var jin := 0
		for c in cfgs:
			if str(c.get("quality", "")) == "素装":
				su += 1
			elif str(c.get("quality", "")) == "锦衣":
				jin += 1
		print("  ", fid, " costumes=", cfgs.size(), " 素装=", su, " 锦衣=", jin)
	quit()
