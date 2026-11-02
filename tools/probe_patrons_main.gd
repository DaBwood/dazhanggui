extends SceneTree
# 渲染 Patrons.Main（750×1334），确认它是不是原作挚友页

const DIR := "res://assets/fgui/"


func _init() -> void:
	for n in ["Basic", "Basic2", "Basic3", "Items", "Patrons"]:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	var obj: FGUIObject = pkg.create_object("Destiny")
	if obj == null:
		print("create failed")
		quit()
		return
	var comp := obj as FGUIComponent
	print("Main ", comp.width, "x", comp.height, " children=", comp.num_children)
	for i in comp.num_children:
		var g: FGUIObject = comp.get_child_at(i)
		print("  - ", g.name, " ", g.get_script().resource_path.get_file(), " ", g.width, "x", g.height, " xy=", g.x, ",", g.y)
	var node: Control = comp.node
	root.add_child(node)
	for i in range(8):
		await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/_patrons_destiny.png")
	print("shot ", img.get_width(), "x", img.get_height())
	quit()
