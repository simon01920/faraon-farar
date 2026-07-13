extends SceneTree
## Dev-only probe: menu -> olympic match -> pause menu -> round end (match
## standings + points) -> next round with a shrunken hand. Run:
##   godot --path . -s res://tools/flow_probe.gd


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
	_snap("probe_flow_menu")

	GameSettings.set_game_mode("olympic")
	current_scene._start_local_game(1)
	var server: LocalGameServer = current_scene._server
	server.bot_delay = 120.0
	await create_timer(3.0).timeout

	var table: GameTable = current_scene._current_screen
	table._pause_layer.visible = true
	await create_timer(0.3).timeout
	_snap("probe_flow_pause")
	table._pause_layer.visible = false

	# Force the human to win the round: single matching card, then play it.
	var s: GameState = server.rules.state
	s.current_index = s.index_of("YOU")
	s.pending_sevens_draw = 0
	s.pending_aces = 0
	s.declared_suit = -1
	var me: GameState.PlayerState = s.player_by_id("YOU")
	var top_suit := FaraonCard.suit_of(s.top_card())
	var winner_card := FaraonCard.make_id(FaraonCard.Rank.KRAL, top_suit)
	# steal the card from wherever it is so hands stay consistent; also take
	# the bot's 7C so no rescue keeps the round alive after the win
	for p in s.players:
		p.hand.erase(winner_card)
		if p != me:
			p.hand.erase("7C")
	s.draw_pile.erase(winner_card)
	me.hand.assign([winner_card])
	table._refresh_all()
	server.propose("YOU", FaraonActions.play([winner_card]))
	await create_timer(2.5).timeout
	_snap("probe_flow_round_over")
	print("match allotments: ", server.match_state.allotments)
	print("round: ", server.match_state.round_number,
			" finished: ", server.match_state.finished)

	current_scene._on_new_game()
	await create_timer(4.0).timeout
	_snap("probe_flow_next_round")
	print("hands round 2: ", server.rules.state.players.map(
			func(p): return "%s:%d" % [p.id, p.hand.size()]))
	quit()
