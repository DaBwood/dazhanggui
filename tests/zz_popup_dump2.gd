extends Node
func _run() -> void:
	var game: Node = load("res://control.tscn").instantiate()
	add_child(game)
	for i in range(10):
		await get_tree().process_frame
	for nm in ["LoginGate", "LoginPopup", "SyncMask"]:
		var n: Node = game.get_node_or_null(nm)
		if n != null:
			n.queue_free()
	game._enter_game()
	for i in range(8):
		await get_tree().process_frame
	game.switch_page("friend")
	for i in range(12):
		await get_tree().process_frame
	game.friend_page._on_locked_friend_clicked("zhen_xian_nv", 0)
	for i in range(12):
		await get_tree().process_frame
	print("[dump] viewport=", get_viewport().get_visible_rect().size)
	for ch in game.get_children():
		var ctl := ch as Control
		if ctl != null and ctl.visible:
			print("  %-24s rect=%s z=%d" % [ctl.name, str(ctl.get_global_rect()), ctl.z_index])
	var pop: Control = null
	for ch in game.get_children():
		if ch is PanelContainer and (ch as Control).visible:
			pop = ch as Control
	if pop != null:
		print("[popup] ", pop.name, " rect=", pop.get_global_rect(), " min=", pop.custom_minimum_size)
		var sb := pop.get_theme_stylebox("panel")
		print("[popup] stylebox=", sb, " tex=", (sb.texture if sb is StyleBoxTexture else null))
		for c2 in pop.get_children():
			var c2c := c2 as Control
			if c2c != null:
				print("   child %-20s rect=%s min=%s" % [c2c.name, str(c2c.get_global_rect()), str(c2c.custom_minimum_size)])
	get_tree().quit()

func _ready() -> void:
	await _run()
