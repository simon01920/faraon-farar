extends SceneTree
## Dev-only probe: a 12-card hand across common phone portrait resolutions
## (two-row fan) and landscape (single row), with selection badges active.
## Run: godot --path . -s res://tools/tworow_probe.gd


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

	# Force a 12-card hand and number three cards across both rows.
	var s: GameState = server.rules.state
	var me: GameState.PlayerState = s.player_by_id("YOU")
	while me.hand.size() < 12 and not s.draw_pile.is_empty():
		me.hand.append(s.draw_pile.pop_back())
	table._selected.assign([me.hand[0], me.hand[6], me.hand[10]])

	var sizes := {
		"tworow_540x1170": Vector2i(540, 1170),   # tall modern phone
		"tworow_720x1280": Vector2i(720, 1280),   # 16:9 phone
		"tworow_1080x2340": Vector2i(1080, 2340), # flagship
		"tworow_landscape": Vector2i(1280, 720),
	}
	for label in sizes:
		root.size = sizes[label]
		await create_timer(0.4).timeout
		table._refresh_hand(s)
		await create_timer(0.2).timeout
		_snap("probe_%s" % label)
	quit()
