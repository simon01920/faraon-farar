extends SceneTree
## Dev-only probe pre kombinovanú obranu proti trestu (sekcia 1):
##   A) faraón vedie skupinu dolníkov priamo z ruky,
##   B) pauza trestného ťahania + priložené karty rovnakého znaku.
## Run: godot --path . -s res://tools/penalty_combo_probe.gd


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/%s.png" % name))
	print("saved ", name)


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _settle(table) -> void:
	while table._busy:
		await create_timer(0.2).timeout


func _run() -> void:
	while current_scene == null:
		await process_frame
	GameSettings.set_game_mode("normal")
	current_scene._start_local_game(2)
	var server: LocalGameServer = current_scene._server
	server.bot_delay = 120.0
	await create_timer(6.0).timeout
	var table: GameTable = current_scene._current_screen
	await _settle(table)

	# --- A) faraón + dolník ako jeden obranný ťah --------------------------
	var s: GameState = server.rules.state
	var me: GameState.PlayerState = s.player_by_id("YOU")
	for card in ["DE", "DZ"]:
		s.draw_pile.erase(card)
		for p in s.players:
			p.hand.erase(card)
		me.hand.append(card)
	s.current_index = s.index_of("YOU")
	s.pending_aces = 0
	s.pending_sevens_draw = 6
	table._refresh_all()
	await create_timer(0.3).timeout
	table._on_card_tapped(table._find_hand_card("DE"))
	table._on_card_tapped(table._find_hand_card("DZ"))
	await create_timer(0.3).timeout
	_snap("probe_combo_selected")
	table._do_play()
	await create_timer(1.5).timeout
	await _settle(table)
	print("A) trest po faraónovi s dolníkom: ", s.pending_sevens_draw,
			" (očakávané 0), vrch kôpky: ", s.top_card(), " (očakávané DZ)")
	_snap("probe_combo_after")

	# --- B) pauza trestu + priložená sedma ---------------------------------
	s.current_index = s.index_of("YOU")
	s.variant.seven_interrupt = true
	s.pending_sevens_draw = 6
	for card in ["7Z", "7E"]:
		s.draw_pile.erase(card)
		for p in s.players:
			p.hand.erase(card)
	me.hand.append("7E") # druhá sedma ostáva v ruke
	s.draw_pile.insert(s.draw_pile.size() - 1, "7Z") # druhá ťahaná = pauza
	table._refresh_all()
	server.propose("YOU", FaraonActions.draw())
	await create_timer(2.0).timeout
	await _settle(table)
	print("B) pauza: ", s.penalty_interrupt, " karta: ", s.interrupt_card,
			" zvyšok trestu: ", s.pending_sevens_draw)
	table._on_card_tapped(table._find_hand_card("7E"))
	await create_timer(0.3).timeout
	_snap("probe_combo_interrupt")
	print("B) text tlačidla: ", table._btn_interrupt_play.text)
	table._do_interrupt_play()
	await create_timer(1.5).timeout
	await _settle(table)
	print("B) trest pre ďalšieho hráča: ", s.pending_sevens_draw,
			" (očakávané 6 = 2 × 3)")
	quit()
