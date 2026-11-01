extends SceneTree
# 临时诊断脚本：加载背包 FGUI 五包，把 Bag/Main 的节点树（名称/类型/矩形/文本）打到标准输出。
# 用法：Godot --headless --path . --script res://tools/dump_bag_fgui.gd
# 说明：FGUIObject 用 width/height/x/y（没有 size/position），首帧再干活。核对完可删。

const PKG_DIR := "res://assets/fgui"
const PKG_NAMES: Array = ["Basic", "Basic2", "Basic3", "Items", "Bag"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	for pkg_name in PKG_NAMES:
		if FGUIPackage.get_by_name(pkg_name) != null:
			continue
		var pkg: FGUIPackage = FGUIPackage.add_package(PKG_DIR + "/" + pkg_name)
		print("[pkg] ", pkg_name, " -> ", "ok" if pkg != null else "FAIL")
	var bag_pkg: FGUIPackage = FGUIPackage.get_by_name("Bag")
	if bag_pkg == null:
		print("[err] Bag 包未注册")
		return true
	var view: FGUIObject = bag_pkg.create_object("Main")
	if view == null:
		print("[err] Main 创建失败")
		return true
	print("[root] Main ", view.width, "x", view.height, " class=", view.get_class())
	_dump(view, 1)
	return true


func _rect(obj: FGUIObject) -> String:
	return "xy=(" + str(obj.x) + "," + str(obj.y) + ") wh=(" + str(obj.width) + "x" + str(obj.height) + ")"


func _dump(obj: FGUIObject, depth: int) -> void:
	var pad := ""
	for i in range(depth):
		pad += "  "
	var line := pad + str(obj.name) + " <" + obj.get_class() + "> " + _rect(obj)
	if obj is FGUITextField:
		line += " fontSize=" + str((obj as FGUITextField).font_size) + " text='" + str((obj as FGUITextField).text) + "'"
	elif obj is FGUILoader:
		line += " url='" + str((obj as FGUILoader).url) + "'"
	elif obj is FGUIButton:
		line += " title='" + str((obj as FGUIButton).title) + "'"
	print(line)
	if obj is FGUIComponent:
		var gc := obj as FGUIComponent
		for i in range(gc.num_children):
			_dump(gc.get_child_at(i), depth + 1)
