extends Node

# 临时验证：重内容弹窗巡检（2026-11-04 固定窗 576×625 + 上下滚动批次）
var game = null
var shot_i := 0

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
	await _frames(10)

	await _run(game.hero_page, "_show_attr_breakdown", "hero_attr")
	await _run(game.hero_page, "_show_talent_panel", "hero_talent")
	await _run(game.cuzhi_view, "show_wushuang_box_selector", "cuzhi_wushuang")
	await _run(game.war_view, "_show_battle_popup", "war_battle")
	await _run(game.mall_panel, "_build_vip_panel", "mall_vip")
	await _run(game.mall_panel, "_build_recharge_page", "mall_recharge")
	await _run(game.shop_page, "_build_shop_panel_popup", "shop_panel")
	await _run(game.get("hero_panel_promo"), "_show_fengkui_panel", "promo_fengkui")
	print("[tour3] done")
	get_tree().quit()

func _run(obj, m: String, tag: String) -> void:
	if obj == null or not is_instance_valid(obj):
		print("[tour3] ", tag, " 对象为空（页面未实例化），跳过")
		return
	if not obj.has_method(m):
		print("[tour3] ", tag, " 无方法 ", m)
		return
	var cb := Callable(obj, m)
	if cb.get_argument_count() != 0:
		print("[tour3] ", tag, " 需要参数，跳过")
		return
	cb.call()
	await _frames(10)
	var panels: Array = []
	for ch in game.get_children():
		if ch.has_meta("popup_mask"):
			panels.append(ch)
	if panels.is_empty():
		print("[tour3] ", tag, " 未弹出")
		return
	var p = panels[panels.size() - 1]
	var title := ""
	var body = p.get_child(0)
	if body != null and body.get_child_count() > 0 and body.get_child(0) is Label:
		title = (body.get_child(0) as Label).text
	print("[tour3] ", tag, " title=", title, " size=", p.size, " avail=", Vector2(p.avail_w, p.avail_h), " body=", body.size, " overflow=", p.overflow, " band=", p.band_mask.visible if p.band_mask != null else false)
	await _shot("res://tests/_tour3_%02d_%s.png" % [shot_i, tag])
	shot_i += 1
	for pp in panels:
		pp.queue_free()
	# 【测试用】顺带清掉 warn/成功弹窗（SuccessPopup 不会自动消失，会糊住后续截图）
	var sp = game.get_node_or_null("SuccessPopup")
	if sp != null:
		sp.queue_free()
	await _frames(8)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[tour3] saved ", path)
