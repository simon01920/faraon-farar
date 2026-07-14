extends SceneTree
## Dev-only probe: captures the start-card deck flip mid-hold (bottom card
## face up on the flipped pile). Run:
##   godot --path . -s res://tools/startflip_probe.gd


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
	current_scene._server.bot_delay = 120.0
	await create_timer(6.5).timeout
	var table: GameTable = current_scene._current_screen
	while table._busy:
		await create_timer(0.2).timeout
	table._anim_start_deck_flip("9C")
	await create_timer(0.75).timeout
	_snap("probe_start_flip")
	await create_timer(1.2).timeout
	quit()
