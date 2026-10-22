extends SceneTree

func _init():
	print("has load_pkm: ", ClassDB.class_has_method("Image", "load_pkm"))
	print("has load_ktx: ", ClassDB.class_has_method("Image", "load_ktx"))
	var p := "C:/Users/林/AppData/Local/Temp/dsh-0cH5q1/dzg_sample.pkm"
	var img := Image.new()
	var err := img.load(p)
	print("load err: ", err, " size: ", img.get_size())
	if err == OK:
		var out := "C:/Users/林/AppData/Local/Temp/dsh-0cH5q1/dzg_sample_from_pkm.png"
		print("save: ", img.save_png(out))
	quit()
