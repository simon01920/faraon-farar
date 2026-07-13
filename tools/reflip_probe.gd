extends SceneTree
## Dev-only probe: forces a nearly-empty draw pile with a deep discard, has
## the human draw to trigger the reflip, and snapshots before / during /
## after the preshuffle animation. Run:
##   godot --path . -s res://tools/reflip_probe.gd


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
	server.bot_delay = 120.0
	await create_timer(3.5).timeout
	var table: GameTable = current_scene._current_screen
	var s: GameState = server.rules.state

	# Deep discard, one card left to draw, human on turn.
	while s.draw_pile.size() > 1:
		s.discard_pile.insert(0, s.draw_pile.pop_front())
	s.current_index = s.index_of("YOU")
	s.pending_aces = 0
	s.pending_sevens_draw = 0
	table._refresh_all()
	await create_timer(0.5).timeout
	_snap("probe_piles_before")

	server.propose("YOU", FaraonActions.draw())     # draws the last card
	await create_timer(0.4).timeout
	s.current_index = s.index_of("YOU")
	server.propose("YOU", FaraonActions.draw())     # empty pile -> reflip
	await create_timer(0.55).timeout
	_snap("probe_reflip_mid")
	await create_timer(1.6).timeout
	_snap("probe_reflip_after")
	print("draw pile after reflip: ", s.draw_pile.size(),
			", discard: ", s.discard_pile.size())
	quit()
