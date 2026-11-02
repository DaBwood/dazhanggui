extends SceneTree
# 找出挚友「友好 / 才华」两个小图标：把候选原件排一排截图

const DIR := "res://assets/fgui/"


func _init() -> void:
	for n in ["Basic", "Basic2", "Basic3", "Items", "Patrons"]:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var cands := [
		["Basic", "imgIntimacy"],
		["Basic2", "imgIntimacy1"],
		["Basic2", "imgIntimacy2"],
		["Basic3", "bgAttribute"],
		["Basic3", "talentSkillBg"],
	]
	var x := 20
	for c in cands:
		var pkg: FGUIPackage = FGUIPackage.get_by_name(c[0])
		var o: FGUIObject = pkg.create_object(c[1])
		if o == null:
			print("miss ", c[0], "/", c[1])
			continue
		o.node.position = Vector2(x, 40)
		root.add_child(o.node)
		print(c[0], "/", c[1], " ", o.width, "x", o.height)
		x += 120
	for i in range(6):
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/_attr_icons.png")
	print("shot")
	quit()
