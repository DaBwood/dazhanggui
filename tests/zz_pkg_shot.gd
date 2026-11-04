extends Node
# 单独渲染三个新包的主组件，确认它们长什么样（不接数据）
const PKGS := ["Basic", "Basic2", "Basic3", "Items", "Patrons", "Beauty", "Common2", "BeautySkill", "BeautyBook", "BeautyLooks"]
const CASES := [["BeautySkill", "Skill"], ["BeautyBook", "Book"], ["BeautyLooks", "Main"]]

func _run() -> void:
	for p in PKGS:
		FGUIPackage.add_package("res://assets/fgui/%s.fui" % p)
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(stage)
	await get_tree().process_frame
	await get_tree().process_frame
	for c in CASES:
		var pkg := FGUIPackage.get_by_name(str(c[0]))
		if pkg == null:
			print("[probe] no pkg ", c[0])
			continue
		var obj := pkg.create_object(str(c[1])) as FGUIComponent
		if obj == null:
			print("[probe] no comp ", c[0], "/", c[1])
			continue
		stage.add_child(obj.node)
		obj.node.position = Vector2.ZERO
		for i in range(12):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "res://tests/_pkg_%s_%s.png" % [c[0], c[1]]
		img.save_png(path)
		print("[probe] saved ", path)
		stage.remove_child(obj.node)
		obj.node.queue_free()
		for i in range(4):
			await get_tree().process_frame
	get_tree().quit()

func _ready() -> void:
	await _run()
