extends SceneTree
# 校验：新指定的盒子图标在工程里能被 ResourceLoader 载入

const ICONS := [
	"124621", "124297", "119527", "124147", "124145",
]


func _init() -> void:
	var bad := 0
	for id in ICONS:
		var path := "res://assets/items/icons/%s.png" % id
		if not ResourceLoader.exists(path):
			print("[miss] ", path)
			bad += 1
			continue
		var tex: Texture2D = load(path)
		print("[ok] ", id, " ", tex.get_width(), "x", tex.get_height())
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/item_icon_map.json"))
	var m: Dictionary = data.get("map", {})
	for k in ["collection_box", "friend_box", "cos_box", "suitbox_礼遇"]:
		var e: Dictionary = m.get(k, {})
		print("[map] ", k, " -> ", e.get("icon", ""), " ", e.get("match", ""))
	print("bad=", bad)
	quit()
