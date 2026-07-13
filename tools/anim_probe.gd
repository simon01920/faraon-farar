extends SceneTree
## Dev-only probe: captures the shuffle mid-motion and the spálená burn
## overlay. Run:
##   godot --path . -s res://tools/anim_probe.gd


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
	# The deal starts with the shuffle — catch it mid-riffle.
	await create_timer(0.75).timeout
	_snap("probe_shuffle_mid")
	await create_timer(3.0).timeout
	var table: GameTable = current_scene._current_screen
	table._anim_spalena()
	await create_timer(0.55).timeout
	_snap("probe_spalena")
	await create_timer(1.5).timeout
	quit()
