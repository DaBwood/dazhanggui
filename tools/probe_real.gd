extends SceneTree
# 临时探针（要带渲染跑）：对比「背包 FGUI 列表滚动」与「门客原生滚动」的每帧耗时

var game: Node


func _init() -> void:
	var ps: PackedScene = load("uid://ppwrhv7ag3ag")
	game = ps.instantiate()
	root.add_child(game)
	_run()


func _run() -> void:
	for i in range(10):
		await process_frame
	game._enter_game()
	for i in range(6):
		await process_frame

	# A. 背包 FGUI
	game.switch_page("bag")
	for i in range(14):
		await process_frame
	var fv = game.bag_page.get("_fgui")
	var lst = fv.get("_lists")[0]
	var sp = lst.scroll_pane
	await _scroll_cost("bag-fgui", func(dy: float): sp.set_pos(sp.pos_x, sp.pos_y + dy, false))

	# B. 门客原生滚动
	game.switch_page("hero")
	for i in range(14):
		await process_frame
	var page = game.get_node_or_null("PageContainer/HeroPage")
	var sc: ScrollContainer = null
	if page != null:
		for ch in page.find_children("*", "ScrollContainer", true, false):
			sc = ch
			break
	if sc == null:
		print("[warn] 找不到门客 ScrollContainer")
	else:
		await _scroll_cost("hero-native", func(dy: float): sc.scroll_vertical = int(sc.scroll_vertical + int(dy)))
	quit()


func _scroll_cost(tag: String, apply: Callable) -> void:
	var total := 0.0
	var worst := 0.0
	var n := 60
	for i in range(n):
		apply.call(12.0)
		var t0 := Time.get_ticks_usec()
		await process_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		total += dt
		worst = maxf(worst, dt)
	print("[cost:%s] avg=%.2fms worst=%.2fms  fps=%.1f" % [tag, total / float(n), worst, Performance.get_monitor(Performance.TIME_FPS)])
