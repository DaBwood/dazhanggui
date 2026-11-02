extends Node


func _ready() -> void:
	for p in ["Bag", "Basic", "Basic2", "Basic3", "Items", "Patrons", "Beauty"]:
		if FGUIPackage.get_by_name(p) == null:
			FGUIPackage.add_package("res://assets/fgui/%s.fui" % p)
	var pkg := FGUIPackage.get_by_name("Beauty")
	var obj: FGUIObject = pkg.create_object("Info")
	for i in range(obj.num_children):
		var n: FGUIObject = obj.get_child_at(i)
		var t := ""
		if n is FGUITextField:
			t = " text='" + (n as FGUITextField).text + "'"
		print("%2d %-18s %-14s %dx%d @%s,%s%s" % [i, n.name, n.get_class(), n.width, n.height, n.x, n.y, t])
	get_tree().quit()


func _dump(n: FGUIObject, depth: int) -> void:
	for i in range(n.num_children):
		var ch: FGUIObject = n.get_child_at(i)
		var txt := ""
		if ch is FGUITextField:
			txt = " text='" + (ch as FGUITextField).text + "'"
		print("%s%-20s %-16s %dx%d @%s,%s%s" % ["  ".repeat(depth), ch.name, ch.get_class(), ch.width, ch.height, ch.x, ch.y, txt])
		if depth < 2:
			_dump(ch, depth + 1)
