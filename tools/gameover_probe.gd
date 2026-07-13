extends SceneTree
## Dev-only probe: forces a finished 4-player game and snapshots the
## game-over standings screen. Run:
##   godot --path . -s res://tools/gameover_probe.gd


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
	current_scene._start_local_game(3)
	var server: LocalGameServer = current_scene._server
	server.bot_delay = 60.0
	await create_timer(3.5).timeout
	var s: GameState = server.rules.state
	s.phase = GameState.Phase.GAME_OVER
	var places := [2, 1, 3, 4]
	for i in s.players.size():
		s.players[i].finish_position = places[i]
		if places[i] < s.players.size():
			s.players[i].status = GameState.PlayerStatus.FINISHED
	var table: GameTable = current_scene._current_screen
	table._show_game_over(s.players[3].id)
	await create_timer(0.3).timeout
	_snap("probe_game_over")
	quit()
