extends SceneTree
## Dev-only probe: forces a 6-card penalty with the faraón buried in the
## draw pile and snapshots the pause/choice UI. Run:
##   godot --path . -s res://tools/interrupt_probe.gd


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
	await create_timer(6.0).timeout
	var table: GameTable = current_scene._current_screen
	while table._busy:
		await create_timer(0.2).timeout

	var s: GameState = server.rules.state
	s.current_index = s.index_of("YOU")
	s.pending_aces = 0
	s.pending_sevens_draw = 6
	# Make DE the second card to be drawn (pop_back draws from the end).
	s.draw_pile.erase("DE")
	for p in s.players:
		p.hand.erase("DE")
	s.draw_pile.insert(s.draw_pile.size() - 1, "DE")
	table._refresh_all()
	server.propose("YOU", FaraonActions.draw())
	await create_timer(2.0).timeout
	while table._busy:
		await create_timer(0.2).timeout
	await create_timer(0.3).timeout
	_snap("probe_interrupt_choice")
	print("interrupt: ", s.penalty_interrupt, " remaining: ", s.pending_sevens_draw)
	quit()
