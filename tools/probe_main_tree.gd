extends SceneTree
# 找 Main 的背景与标题条原件，并列出大图资源

const DIR := "res://assets/fgui/"
const ORDER := ["Basic", "Basic2", "Basic3", "Items", "Patrons"]


func _init() -> void:
	for n in ORDER:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	var main: FGUIComponent = pkg.create_object("Main") as FGUIComponent
	print("== Main ", main.width, "x", main.height, " children=", main.num_children)
	for i in main.num_children:
		var ch: FGUIObject = main.get_child_at(i)
		var extra := ""
		if ch is FGUILoader:
			extra = " url='" + str((ch as FGUILoader).url) + "'"
		if ch is FGUITextField:
			extra = " text='" + str((ch as FGUITextField).text) + "'"
		print("  %-14s %-22s %6.1f,%6.1f %6.1fx%-6.1f%s" % [ch.name, ch.get_script().resource_path.get_file(),
			ch.x, ch.y, ch.width, ch.height, extra])
	print("== Patrons images >= 500 wide")
	for it in pkg.get_item_names() if pkg.has_method("get_item_names") else []:
		pass
	quit()
