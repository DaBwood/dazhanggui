extends Node
# 单独渲染 Beauty.Info（原作挚友培养页）看能否直接用

func _ready() -> void:
	await _run()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)


func _run() -> void:
	for p in ["Bag", "Basic", "Basic2", "Basic3", "Items", "Patrons", "Beauty", "Common2"]:
		if FGUIPackage.get_by_name(p) == null:
			FGUIPackage.add_package("res://assets/fgui/%s.fui" % p)
	var pkg := FGUIPackage.get_by_name("Beauty")
	if pkg == null:
		print("ERR 包没加载上")
		get_tree().quit()
		return
	var obj: FGUIObject = pkg.create_object("Info")
	if obj == null:
		print("ERR Info 创建失败")
		get_tree().quit()
		return
	print("[info] %dx%d children=%d" % [obj.width, obj.height, obj.num_children])
	for i in mini(obj.num_children, 24):
		var ch: FGUIObject = obj.get_child_at(i)
		print("   %-22s %-16s %sx%s @%s,%s" % [ch.name, ch.get_class(), ch.width, ch.height, ch.x, ch.y])
	await get_tree().process_frame
	var stage := Control.new()
	stage.size = Vector2(540, 960)
	get_tree().root.add_child.call_deferred(stage)
	await get_tree().process_frame
	await get_tree().process_frame
	stage.add_child(obj.node)
	var s: float = 540.0 / 750.0
	obj.node.scale = Vector2(s, s)
	for i in range(10):
		await get_tree().process_frame
	await _shot("res://tests/_beauty_info.png")
	print("DONE")
	get_tree().quit()
