extends SceneTree
# 可行性验证：用 DestinyBeautyItem 装一张挚友半身图，看圆形裁切/框对不对

const DIR := "res://assets/fgui/"
const ORDER := ["Basic", "Basic2", "Basic3", "Items", "Patrons"]


func _init() -> void:
	for n in ORDER:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	var obj: FGUIObject = pkg.create_object("DestinyBeautyItem")
	var c := obj as FGUIComponent
	var holder := Control.new()
	holder.size = Vector2(900, 700)
	root.add_child(holder)
	var icon := c.get_child("iconItem") as FGUIComponent
	print("iconItem children=", icon.num_children)
	for i in icon.num_children:
		var g := icon.get_child_at(i)
		print("   - ", g.name, " ", g.get_script().resource_path.get_file(), " ", g.width, "x", g.height)
	# 试三种赋值方式
	var path := "res://assets/portraits/friends_half/qing_ning.png"
	print("exists=", ResourceLoader.exists(path))
	var loader := icon.get_child("loader") as FGUILoader
	if loader == null:
		for i in icon.num_children:
			var g2 := icon.get_child_at(i)
			if g2 is FGUILoader:
				loader = g2 as FGUILoader
				print("found loader: ", loader.name)
	if loader != null:
		loader.url = path
		print("set url -> ", loader.url)
	# 三份并排：不同尺寸
	for k in range(3):
		var obj2: FGUIObject = pkg.create_object("DestinyBeautyItem")
		var c2 := obj2 as FGUIComponent
		var ic2 := c2.get_child("iconItem") as FGUIComponent
		for i in ic2.num_children:
			var g3 := ic2.get_child_at(i)
			if g3 is FGUILoader:
				(g3 as FGUILoader).url = path
		holder.add_child(c2.node)
		c2.node.position = Vector2(30 + k * 240, 60)
		c2.node.scale = Vector2(1.0, 1.0)
		var nm := c2.get_child("txtAttr") as FGUITextField
		if nm != null:
			nm.text = "青凝"
	for i in range(6):
		await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/_beauty_cell.png")
	print("shot")
	quit()
