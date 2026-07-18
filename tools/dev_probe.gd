extends SceneTree
## Dev-only probe: zapne dev režim, otvorí DevPanel a odfotí ho; potom
## overí otočenie balíčka (skrytý DeckStack pod blokom). Run:
##   godot --path . -s res://tools/dev_probe.gd


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
	GameSettings.set_dev_mode(true)
	GameSettings.set_game_mode("normal")
	current_scene._start_local_game(2)
	current_scene._server.bot_delay = 120.0
	await create_timer(6.0).timeout
	var table: GameTable = current_scene._current_screen
	while table._busy:
		await create_timer(0.2).timeout
	table._open_dev_panel()
	await create_timer(0.4).timeout
	_snap("probe_dev_panel")
	for c in table.get_children():
		if c is DevPanel:
			c.queue_free()
	await create_timer(0.3).timeout
	table._anim_start_deck_flip("9C")
	await create_timer(1.1).timeout
	_snap("probe_flip_no_deck_under")
	await create_timer(1.6).timeout
	GameSettings.set_dev_mode(false)
	quit()
