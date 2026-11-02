extends Node


func _ready() -> void:
	for p in ["Bag", "Basic", "Basic2", "Basic3", "Items", "Patrons", "Beauty"]:
		if FGUIPackage.get_by_name(p) == null:
			FGUIPackage.add_package("res://assets/fgui/%s.fui" % p)
	var info: FGUIObject = FGUIPackage.get_by_name("Beauty").create_object("Info")
	for nm in ["nameItem", "identityItem"]:
		var n: FGUIObject = info.get_child(nm)
		print("== ", nm, " size=", n.width, "x", n.height)
		for i in n.num_children:
			var ch: FGUIObject = n.get_child_at(i)
			print("   ", ch.name, " ", ch.get_class(), " vis=", ch.visible, " ", ch.width, "x", ch.height, " @", ch.x, ",", ch.y)
		var ctrl = n.get_controller("c1")
		print("   ctrl c1 = ", ctrl)
	for eff in ["intimacyEffect", "glamourEffect"]:
		var e: FGUIObject = info.get_child(eff)
		print(eff, " = ", e, " class=", e.get_class() if e != null else "-")
	get_tree().quit()
