extends SceneTree
## Dev-only probe: the running table re-laid out across landscape, portrait
## (sensor rotation) and a desktop-ish window size. Run:
##   godot --path . -s res://tools/orientation_probe.gd


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/%s.png" % name))
	print("saved ", name)


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _run() -> void:
	while current_scene == null:
		await process_frame
	GameSettings.set_game_mode("normal")
	current_scene._start_local_game(3)
	current_scene._server.bot_delay = 120.0
	await create_timer(4.0).timeout
	var sizes := {
		"landscape": Vector2i(1280, 720),
		"portrait": Vector2i(540, 1170),
		"desktop_wide": Vector2i(1720, 900),
	}
	for label in sizes:
		root.size = sizes[label]
		await create_timer(0.4).timeout
		_snap("probe_table_%s" % label)
	quit()
