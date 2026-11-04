extends Node

# 临时验证：全视图弹窗巡检（第七章弹窗统一——内容超窗自检）
var game = null
var shot_i := 0
const VIEWS := ["exchange", "lottery", "charity", "travel", "haoyou", "manor", "courtyard", "war", "fishing", "fish_equip", "costume", "soul", "soulpower", "cuzhi", "collection", "bank", "mail", "inn", "clinic", "drugshop", "tavern", "winery", "miaoyin", "xiangfang", "zhaoshang"]
const METHODS := ["_show_medal_popup", "_show_rule_popup", "_show_help_popup", "_show_gallery_popup", "_show_tips_popup"]

func _ready() -> void:
	var main_scene: PackedScene = load("res://control.tscn")
	game = main_scene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in ["LoginGate", "LoginPopup", "OfflineHintPopup", "SyncMask"]:
		if game.has_node(n):
			game.get_node(n).queue_free()
	for ch in game.get_children():
		if ch is ColorRect and (ch as ColorRect).color.a >= 0.5:
			ch.queue_free()
	game._enter_game()
	for i in range(8):
		await get_tree().process_frame
	for key in VIEWS:
		game.show_view(key)
		for i in range(12):
			await get_tree().process_frame
		var node = game.get(key + "_view")
		if node == null:
			print("[tour2] ", key, " no view var")
			continue
		for m in METHODS:
			if not node.has_method(m):
				continue
			var cb := Callable(node, m)
			if cb.get_argument_count() != 0:
				continue
			cb.call()
			await _frames(8)
			var panels: Array = []
			for ch in game.get_children():
				if ch.has_meta("popup_mask"):   # 【改】窗根不再是 PanelContainer
					panels.append(ch)
			print("[tour2] ", key, ".", m, " popups=", panels.size())
			await _shot("res://tests/_tour2_%02d_%s%s.png" % [shot_i, key, m])
			shot_i += 1
			for p in panels:
				p.queue_free()
			await _frames(6)
		game.hide_view(key)
		await _frames(6)
	print("[tour2] done")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
