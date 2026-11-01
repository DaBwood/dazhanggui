extends SceneTree
# 临时诊断脚本：无头跑主场景 → 切到背包页 → 打印 FGUI 整窗实际几何（宿主尺寸/缩放/屏幕矩形/格子数）。
# 用法：Godot --headless --path . --script res://tools/probe_bag_layout.gd

var _frame := 0
var _main: Node = null


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_main = load("uid://ppwrhv7ag3ag").instantiate()
		root.add_child(_main)
		return false
	if _frame == 6:
		var vs: Vector2 = root.get_visible_rect().size
		print("[viewport] ", vs)
		if _main.has_node("PageContainer"):
			print("[PageContainer] pos=", _main.get_node("PageContainer").position, " size=", _main.get_node("PageContainer").size)
		if _main.has_node("PageContainer/BagPage"):
			var bp: Control = _main.get_node("PageContainer/BagPage")
			print("[BagPage] pos=", bp.position, " size=", bp.size, " visible=", bp.visible)
		_main.switch_page("bag")
		return false
	if _frame == 12:
		var bp2: Control = _main.get_node("PageContainer/BagPage")
		print("[after switch] BagPage size=", bp2.size)
		var win: Node = _main.get_node_or_null("BagFguiMain")
		if win == null:
			print("[err] BagFguiMain 未创建")
			return true
		var wc := win as Control
		print("[window] pos=", wc.position, " size=", wc.size, " scale=", wc.scale, " global_rect=", wc.get_global_rect())
		var lst: Node = wc.get_node_or_null("list1")
		if lst != null:
			print("[list1] rect=", (lst as Control).get_global_rect())
		print("[cells] skip")
		var lst2: Node = wc.get_node_or_null("list1")
		if lst2 != null:
			var cell: Node = _find_cell(lst2)
			if cell == null:
				print("[cell] not found")
			else:
				print("[cell] ", cell.get_class(), " name=", cell.name, " children=", cell.get_child_count())
				for ch in cell.get_children():
					print("   - child ", ch.name, " ", ch.get_class())
				var bg: Node = cell.get_node_or_null("bgItem")
				if bg != null:
					var ctl: Variant = bg.get_controller("c1")
					print("[bgItem c1] ", "null" if ctl == null else str((ctl as Object).get("selected_index")))
				var ic: Node = cell.get_node_or_null("icon")
				if ic != null:
					print("[icon] url=", str(ic.get("url")))
		return true
	return false

func _find_cell(n: Node) -> Node:
	if n.name.begins_with("BagItem") or n.name.begins_with("BagMainItem"):
		return n
	for ch in n.get_children():
		var r: Node = _find_cell(ch)
		if r != null:
			return r
	return null
