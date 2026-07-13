extends SceneTree
## Dev-only probe: verifies the menu and settings screens center correctly
## across window sizes (desktop / tablet / portrait phone). Run:
##   godot --path . -s res://tools/settings_probe.gd


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/%s.png" % name))
	print("saved ", name)


func _run() -> void:
	while current_scene == null:
		await process_frame
	var sizes := {
		"desktop": Vector2i(1280, 720),
		"tablet": Vector2i(1024, 768),
		"phone_portrait": Vector2i(540, 1170),
	}
	for label in sizes:
		root.size = sizes[label]
		await create_timer(0.3).timeout
		var menu: MainMenu = current_scene._current_screen
		menu._menu_screen.visible = true
		menu._settings_screen.visible = false
		await create_timer(0.2).timeout
		_snap("probe_menu_%s" % label)
		menu._menu_screen.visible = false
		menu._settings_screen.visible = true
		await create_timer(0.2).timeout
		_snap("probe_settings_%s" % label)
	quit()
