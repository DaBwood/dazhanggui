extends SceneTree
# 临时诊断：Bag/Main 三个列表（list1/2/3）各自的格子组件是什么、字段有哪些

const PKG_DIR := "res://assets/fgui"


func _init() -> void:
	for n in ["Basic", "Basic2", "Basic3", "Items", "Bag"]:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(PKG_DIR + "/" + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Bag")
	var view: FGUIObject = pkg.create_object("Main")
	var comp := view as FGUIComponent
	for nm in ["list1", "list2", "list3"]:
		var lst := comp.get_child(nm)
		print("== ", nm, " type=", (lst.get_script().resource_path if lst != null and lst.get_script() != null else "null"))
		if lst == null:
			continue
		var gl := lst as FGUIList
		print("   num_items=", gl.num_items)
		gl.num_items = 1
		print("   after set num_items=", gl.num_items)
		var cell: FGUIObject = gl.get_child_at(0)
		if cell == null:
			print("   cell=null")
			continue
		var cc := cell as FGUIComponent
		print("   cell children=", cc.num_children if cc != null else -1)
		if cc != null:
			for i in cc.num_children:
				var ch := cc.get_child_at(i)
				print("     - ", ch.name, " ", (ch.get_script().resource_path.get_file() if ch.get_script() != null else "?"))
	quit()
