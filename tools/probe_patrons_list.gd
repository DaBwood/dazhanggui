extends SceneTree
# 验证 Patrons.Main 的 list 是否用 DestinyBeautyItem 作格子，并截图

const DIR := "res://assets/fgui/"


func _init() -> void:
	for n in ["Basic", "Basic2", "Basic3", "Items", "Patrons"]:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	var comp := pkg.create_object("Main") as FGUIComponent
	var lst := comp.get_child("list") as FGUIList
	lst.num_items = 4
	print("list children=", lst.num_items)
	var cell: FGUIObject = lst.get_child_at(0)
	if cell != null:
		print("cell=", cell.get_script().resource_path.get_file(), " ", cell.width, "x", cell.height)
		var cc := cell as FGUIComponent
		if cc != null:
			print("  children=", cc.num_children)
			for i in cc.num_children:
				var g2: FGUIObject = cc.get_child_at(i)
				print("    - ", g2.name, " ", g2.get_script().resource_path.get_file(), " ", g2.width, "x", g2.height)
	# 灌一张图看效果
	if cell != null:
		var ic := (cell as FGUIComponent).get_child("iconItem") as FGUIComponent
		if ic != null:
			var ld := ic.get_child("icon") as FGUILoader
			if ld != null:
				ld.url = "res://assets/portraits/friends_half/qing_ning.png"
	root.add_child(comp.node)
	for i in range(8):
		await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/_patrons_list.png")
	print("shot")
	quit()
