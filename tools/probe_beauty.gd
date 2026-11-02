extends SceneTree
# 诊断：DestinyBeautyItem 子节点默认可见性 + Basic3.BeautyNameItem 结构

const DIR := "res://assets/fgui/"


func _init() -> void:
	for n in ["Basic", "Basic2", "Basic3", "Items", "Patrons"]:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	var obj: FGUIObject = pkg.create_object("DestinyBeautyItem")
	var comp := obj as FGUIComponent
	print("== DestinyBeautyItem ", comp.width, "x", comp.height, " children=", comp.num_children)
	for i in comp.num_children:
		var g: FGUIObject = comp.get_child_at(i)
		print("  - ", g.name, " ", g.get_script().resource_path.get_file(), " ", g.width, "x", g.height,
			" xy=", g.x, ",", g.y, " visible=", g.visible)
	var b3: FGUIPackage = FGUIPackage.get_by_name("Basic3")
	var nm: FGUIObject = b3.create_object("BeautyNameItem")
	if nm != null:
		var nc := nm as FGUIComponent
		print("== BeautyNameItem ", nc.width, "x", nc.height, " children=", nc.num_children)
		for i in nc.num_children:
			var g2: FGUIObject = nc.get_child_at(i)
			print("  - ", g2.name, " ", g2.get_script().resource_path.get_file(), " ", g2.width, "x", g2.height, " xy=", g2.x, ",", g2.y)
			if g2 is FGUITextField:
				print("      text='", (g2 as FGUITextField).text, "'")
	quit()
