extends SceneTree
## Dev-only probe: starts a seeded game, selects three cards from the human
## hand and snapshots the numbered order badges. Run:
##   godot --path . -s res://tools/order_probe.gd


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
	server.bot_delay = 60.0 # keep bots quiet during the probe
	await create_timer(3.5).timeout
	var table: GameTable = current_scene._current_screen
	var me: GameState.PlayerState = server.rules.state.player_by_id("YOU")
	for i in mini(3, me.hand.size()):
		table._selected.append(me.hand[i])
	table._refresh_hand(server.rules.state)
	await create_timer(0.3).timeout
	_snap("probe_order_badges")
	quit()
