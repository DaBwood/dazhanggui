extends SceneTree
# 临时探针：背包 FGUI 每帧开销随「格子数量」的变化（判断是不是节点数导致的固定开销）

func _init() -> void:
	var ps: PackedScene = load("uid://ppwrhv7ag3ag")
	var game: Node = ps.instantiate()
	root.add_child(game)
	_run(game)


func _idle(tag: String) -> void:
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		await process_frame
	print("[idle:%s] %.2fms/frame" % [tag, (Time.get_ticks_usec() - t0) / 20.0 / 1000.0])


func _run(game: Node) -> void:
	for i in range(10):
		await process_frame
	game._enter_game()
	for i in range(5):
		await process_frame

	game.switch_page("bag")
	for i in range(12):
		await process_frame
	var fv = game.bag_page.get("_fgui")
	var lst = fv.get("_lists")[0]
	print("[nodes] list children=", lst.num_children, " total FGUI nodes=", _count(ftv_tree_root(fv)))
	await _idle("bag-36")

	# 清空数据 → 0 格
	fv.set("_tab_data", [[], [], []])
	fv.call("refresh_items")
	for i in range(6):
		await process_frame
	print("[nodes] after clear children=", lst.num_children)
	await _idle("bag-0")

	# 隐藏整窗
	fv.call("set_visible", false)
	for i in range(6):
		await process_frame
	await _idle("hidden")
	quit()


func ftv_tree_root(fv) -> Node:
	var n = fv.get("_node")
	return n if n != null else fv


func _count(n: Node) -> int:
	if n == null:
		return 0
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
