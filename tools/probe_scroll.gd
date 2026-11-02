extends SceneTree
# 临时探针：对比「背包页每帧开销」与「庄园页每帧开销」，定位固定开销来源

func _init() -> void:
	var ps: PackedScene = load("uid://ppwrhv7ag3ag")
	var game: Node = ps.instantiate()
	root.add_child(game)
	_run(game)


func _measure(tag: String) -> void:
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		await process_frame
	print("[idle:%s] %.2fms/frame" % [tag, (Time.get_ticks_usec() - t0) / 20.0 / 1000.0])


func _run(game: Node) -> void:
	for i in range(10):
		await process_frame
	if game.has_method("_enter_game"):
		game._enter_game()
	for i in range(5):
		await process_frame

	game.switch_page("bag")
	for i in range(12):
		await process_frame
	await _measure("bag")

	game.switch_page("mansion")
	for i in range(10):
		await process_frame
	await _measure("mansion")

	game.switch_page("bag")
	for i in range(10):
		await process_frame
	var bp = game.get("bag_page")
	var fv = bp.get("_fgui")
	var lst = fv.get("_lists")[0]
	var sp = lst.scroll_pane
	var total := 0
	var n := 30
	for step in range(n):
		var s0 := Time.get_ticks_usec()
		sp.set_pos(sp.pos_x, sp.pos_y + 14.0, false)
		await process_frame
		total += Time.get_ticks_usec() - s0
	print("[scroll] %.2fms/step children=%d" % [total / float(n) / 1000.0, lst.num_children])
	quit()
