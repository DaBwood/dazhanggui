extends SceneTree
# 临时诊断脚本：导出 Items 包 BagItem1/BagItem2/GoodsShowItem 三个格子的控件结构。
# 用法：Godot --headless --path . --script res://tools/dump_bag_cell.gd

const PKG_DIR := "res://assets/fgui"
const PKG_NAMES: Array = ["Basic", "Basic2", "Basic3", "Items", "Bag"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	for pkg_name in PKG_NAMES:
		if FGUIPackage.get_by_name(pkg_name) == null:
			FGUIPackage.add_package(PKG_DIR + "/" + pkg_name)
	var items_pkg: FGUIPackage = FGUIPackage.get_by_name("Items")
	if items_pkg == null:
		print("[err] Items 包未注册")
		return true
	for comp_name in ["BagItem1", "BagItem2", "GoodsShowItem"]:
		var obj: FGUIObject = items_pkg.create_object(comp_name)
		if obj == null:
			print("[err] ", comp_name, " 创建失败")
			continue
		print("[cell] ", comp_name, " ", obj.width, "x", obj.height)
		_dump(obj, 1)
	return true


func _dump(obj: FGUIObject, depth: int) -> void:
	var pad := ""
	for i in range(depth):
		pad += "  "
	var line := pad + str(obj.name) + " <" + obj.get_class() + "> xy=(" + str(obj.x) + "," + str(obj.y) + ") wh=(" + str(obj.width) + "x" + str(obj.height) + ")"
	if obj is FGUITextField:
		line += " fontSize=" + str((obj as FGUITextField).font_size) + " color=" + str((obj as FGUITextField).color)
	elif obj is FGUILoader:
		line += " url='" + str((obj as FGUILoader).url) + "'"
	elif obj is FGUIButton:
		line += " title='" + str((obj as FGUIButton).title) + "'"
	print(line)
	if obj is FGUIComponent:
		var gc0 := obj as FGUIComponent
		for ci in range(gc0.controllers.size()):
			var ctrl := gc0.get_controller_at(ci)
			print(pad + "  [ctrl] name=" + str(ctrl.name) + " index=" + str(ctrl.selected_index))
	if obj is FGUIComponent:
		var gc := obj as FGUIComponent
		for i in range(gc.num_children):
			_dump(gc.get_child_at(i), depth + 1)
