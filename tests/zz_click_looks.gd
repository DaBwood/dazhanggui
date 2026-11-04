extends Node
# 真实鼠标点击「仪容技能」按钮，验证能否进入
func _run() -> void:
	var game: Node = load("res://control.tscn").instantiate()
	add_child(game)
	for i in range(8):
		await get_tree().process_frame
	for nm in ["LoginGate", "LoginPopup", "SyncMask"]:
		var n: Node = game.get_node_or_null(nm)
		if n != null:
			n.queue_free()
	game._enter_game()
	for i in range(10):
		await get_tree().process_frame
	var fid := "qing_ning"
	game.data.unlock_friend(fid)
	game.switch_page("friend")
	for i in range(12):
		await get_tree().process_frame
	game.friend_page.show_friend_detail(fid)
	for i in range(12):
		await get_tree().process_frame
	var fd = game.friend_page.get("_friend_detail_fgui")
	var info = fd.get("_info") if fd != null else null
	var looks_btn: FGUIObject = info.get_child("btnLooks") if info != null else null
	if looks_btn == null:
		print("[test] no btnLooks")
		get_tree().quit()
		return
	var ctrl := looks_btn.node as Control
	var c := get_viewport().get_canvas_transform()
	var pos: Vector2 = c * ctrl.get_global_rect().get_center()
	print("[test] btnLooks screen=", pos, " rect=", ctrl.get_global_rect())
	var hit := game.get_node_or_null("PageContainer/FriendPage/FriendDetailFgui")
	var hit_node: Node = null
	if fd != null:
		var root: Node = fd.get("_root")
		if root != null:
			hit_node = root.get_node_or_null("Overlay/Hit_btnLooks")
	if hit_node != null:
		print("[test] hitbtn rect=", (hit_node as Control).get_global_rect())
	else:
		print("[test] hitbtn NOT FOUND")
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var hov := get_viewport().gui_get_hovered_control()
	print("[test] hovered=", (hov.name if hov != null else "null"))

	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev)
	await get_tree().process_frame
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	ev2.position = pos
	ev2.global_position = pos
	get_viewport().push_input(ev2)
	for i in range(14):
		await get_tree().process_frame
	var lv = game.friend_page.get("_friend_looks")
	print("[test] looks_visible=", (lv.visible if lv != null else false))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_click_looks.png")
	get_tree().quit()

func _ready() -> void:
	await _run()
