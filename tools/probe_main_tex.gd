extends SceneTree
# 检查 Main 各件是否真的拿到了贴图（bgIcon / n16 / n15 / n25）

const DIR := "res://assets/fgui/"
const ORDER := ["Basic", "Basic2", "Basic3", "Items", "Patrons"]


func _init() -> void:
	for n in ORDER:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	var main: FGUIComponent = pkg.create_object("Main") as FGUIComponent
	root.add_child(main.node)
	for i in main.num_children:
		var ch: FGUIObject = main.get_child_at(i)
		var tex := "-"
		if ch is FGUILoader:
			var url := str((ch as FGUILoader).url)
			var tr: Node = (ch as FGUILoader).get_node_or_null("TextureRect")
			tex = "url=%s tex=%s" % [url, "yes" if tr != null else "no"]
		print("%-14s vis=%-5s %s" % [ch.name, str(ch.visible), tex])
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/_main_only.png")
	print("shot")
	quit()
