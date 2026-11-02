extends SceneTree
# 打印 DestinyBeautyItem 内部各件的坐标，用于对齐圆形区域

const DIR := "res://assets/fgui/"


func _init() -> void:
	for n in ["Basic", "Basic2", "Basic3", "Items", "Patrons"]:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	var o: FGUIObject = pkg.create_object("DestinyBeautyItem")
	var comp := o as FGUIComponent
	print("cell ", comp.width, "x", comp.height)
	for i in comp.num_children:
		var ch: FGUIObject = comp.get_child_at(i)
		print("  %-14s %-8s %6.1f,%6.1f %6.1fx%-6.1f" % [ch.name, ch.get_script().resource_path.get_file(),
			ch.x, ch.y, ch.width, ch.height])
	var icon := comp.get_child("iconItem") as FGUIComponent
	if icon != null:
		print("iconItem children:")
		for i in icon.num_children:
			var c2: FGUIObject = icon.get_child_at(i)
			print("  %-14s %-8s %6.1f,%6.1f %6.1fx%-6.1f" % [c2.name, c2.get_script().resource_path.get_file(),
				c2.x, c2.y, c2.width, c2.height])
	quit()
