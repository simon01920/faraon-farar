extends SceneTree
## Dev-only probe: appearance screen + a photo table look in game. Run:
##   godot --path . -s res://tools/appearance_probe.gd


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
	await create_timer(0.4).timeout

	var menu: MainMenu = current_scene._current_screen
	menu._menu_screen.visible = false
	menu._appearance_screen.visible = true
	await create_timer(0.3).timeout
	_snap("probe_appearance")

	ProgressionStore.grant("wood_table")
	GameSettings.set_table_look("wood_table")
	GameSettings.set_game_mode("normal")
	current_scene._start_local_game(2)
	current_scene._server.bot_delay = 120.0
	await create_timer(3.0).timeout
	_snap("probe_table_wood")

	GameSettings.set_table_look("felt_green")
	quit()
