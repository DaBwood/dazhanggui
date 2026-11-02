extends SceneTree
# 诊断：背包整窗与顶/底栏的实际矩形（在给定窗口尺寸下）

var _main: Node = null
var _frame := 0


func _initialize() -> void:
	_main = load("uid://ppwrhv7ag3ag").instantiate()
	root.add_child(_main)


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame == 3:
		print("[viewport] ", root.get_visible_rect().size, " win=", DisplayServer.window_get_size())
		for n in ["TopBar", "BottomNav"]:
			if _main.has_node(n):
				var c: Control = _main.get_node(n)
				print("  ", n, " pos=", c.position, " size=", c.size, " visible=", c.visible)
			else:
				print("  ", n, " MISSING")
	if _frame == 5:
		_main.call("switch_page", "bag")
	if _frame == 12:
		var clip: Control = _main.get_node_or_null("BagFguiClip")
		var win: Control = _main.get_node_or_null("BagFguiClip/BagFguiMain")
		print("[clip] ", "null" if clip == null else str(clip.position) + " size=" + str(clip.size))
		print("[win ] ", "null" if win == null else str(win.position) + " scale=" + str(win.scale) + " size=" + str(win.size))
		var list: Node = null
		if win != null:
			list = win.find_child("list1", true, false)
		if list is Control:
			var lc: Control = list
			print("[list1] local=", lc.position, " size=", lc.size, " global=", lc.get_global_rect())
		if _main.has_node("BottomNav"):
			var nav: Control = _main.get_node("BottomNav")
			print("[nav global] ", nav.get_global_rect())
		return true
	return false
