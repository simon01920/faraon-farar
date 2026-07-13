extends SceneTree
## Dev-only probe: boots the real main scene, jumps into a seeded 4-player
## game, auto-draws for the human so the game flows, and saves PNGs at a few
## moments (menu, mid-deal, mid-game). Run:
##   godot --path . -s res://tools/screenshot_probe.gd


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
	var main := current_scene
	await create_timer(0.4).timeout
	_snap("ui_menu")

	main._start_local_game(3)
	var server: LocalGameServer = main._server
	await create_timer(2.0).timeout
	_snap("ui_deal")

	var elapsed := 0.0
	while elapsed < 11.0:
		await create_timer(0.5).timeout
		elapsed += 0.5
		var s: GameState = server.rules.state
		if s.phase == GameState.Phase.PLAYING \
				and s.players[s.current_index].id == "YOU" \
				and not main._current_screen._busy:
			if s.pending_aces > 0:
				server.propose("YOU", FaraonActions.pass_turn())
			else:
				server.propose("YOU", FaraonActions.draw())
	_snap("ui_screenshot")
	quit()
