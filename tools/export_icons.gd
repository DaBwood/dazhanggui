extends Node

const OUT_DIR := "C:\\Users\\林\\Documents\\大掌柜_assets\\clean\\icons_for_upgrade\\"
const TARGETS := {
	"icon_skill": "BtnSkill",
	"icon_fame": "BtnPromotion",
	"icon_play": "BtnPatronize",
	"icon_cos": "btnSkin",
	"icon_peerless": "btnPeerless",
	"icon_looks": "btnLooks",
}
const SCALE := 4.0


func _ready() -> void:
	await _run()


func _run() -> void:
	for p in ["Bag", "Basic", "Basic2", "Basic3", "Items", "Patrons", "Beauty", "Common2"]:
		if FGUIPackage.get_by_name(p) == null:
			FGUIPackage.add_package("res://assets/fgui/%s.fui" % p)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var pkg := FGUIPackage.get_by_name("Beauty")
	for out_name in TARGETS.keys():
		var comp_name := str(TARGETS[out_name])
		var obj: FGUIObject = pkg.create_object(comp_name)
		if obj == null:
			print("ERR create ", comp_name)
			continue
		var rp: FGUIObject = obj.get_child("imgRedPoint")
		if rp != null:
			rp.visible = false
		obj.node.position = Vector2.ZERO
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.size = Vector2i(int(obj.width * SCALE), int(obj.height * SCALE))
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var holder := Control.new()
		holder.scale = Vector2(SCALE, SCALE)
		holder.add_child(obj.node)
		vp.add_child(holder)
		add_child(vp)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path: String = OUT_DIR + str(out_name) + ".png"
		img.save_png(path)
		print("saved ", path, " ", img.get_width(), "x", img.get_height())
		vp.queue_free()
	get_tree().quit()
