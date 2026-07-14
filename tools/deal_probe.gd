extends SceneTree
## Dev-only probe: catches the deal mid-flight (hand building up card by
## card) and a large multi-card penalty draw (9 cards, uncapped). Run:
##   godot --path . -s res://tools/deal_probe.gd


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
	current_scene._start_local_game(2)
	var server: LocalGameServer = current_scene._server
	server.bot_delay = 120.0
	# Shuffle ~0.9s, then cards start; catch the hand half-built.
	await create_timer(2.6).timeout
	_snap("probe_deal_mid")
	await create_timer(3.5).timeout

	# Force a 9-card penalty draw for the human and watch all nine fly.
	var s: GameState = server.rules.state
	var table: GameTable = current_scene._current_screen
	while table._busy:
		await create_timer(0.2).timeout
	s.current_index = s.index_of("YOU")
	s.pending_aces = 0
	s.pending_sevens_draw = 9
	table._refresh_all()
	server.propose("YOU", FaraonActions.draw())
	await create_timer(1.0).timeout
	_snap("probe_draw9_mid")
	await create_timer(2.5).timeout
	_snap("probe_draw9_after")
	print("hand size after: ", s.player_by_id("YOU").hand.size())
	quit()
