extends SceneTree
## Dev-only probe: loads every audio asset and prints its duration — the
## "listen check" substitute for headless QA (a 0-length or unloadable file
## fails loudly here). Run:
##   godot --headless --path . -s res://tools/audio_probe.gd


func _initialize() -> void:
	for dir_name in ["res://assets/audio/music", "res://assets/audio/sfx"]:
		var dir := DirAccess.open(dir_name)
		for f in dir.get_files():
			if f.ends_with(".import"):
				continue
			var stream: AudioStream = load(dir_name + "/" + f)
			if stream == null:
				print("FAILED TO LOAD: ", f)
			else:
				print("%s  ->  %.2f s" % [f, stream.get_length()])
	quit()
