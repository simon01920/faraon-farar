extends SceneTree
## Dev-only probe: marks the human as finished mid-game and checks the
## fast-forward button appears, then presses it. Run:
##   godot --path . -s res://tools/ff_probe.gd


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
	var table: GameTable = current_scene._current_screen
	var me: GameState.PlayerState = server.rules.state.player_by_id("YOU")
	me.status = GameState.PlayerStatus.FINISHED
	me.hand.clear()
	table._refresh_all()
	await create_timer(0.3).timeout
	print("ff visible after finish: ", table._btn_ff.visible)
	_snap("probe_fast_forward")
	table._btn_ff.pressed.emit()
	print("fast_forward active after press: ", server.fast_forward)
	print("ff hidden after press: ", not table._btn_ff.visible)
	quit()
