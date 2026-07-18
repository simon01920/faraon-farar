extends SceneTree
## Regresný probe na pád pauzy: REÁLNE stlačí ☰ (emit pressed) v hre bez
## dev režimu aj s ním a overí, že sa pauza otvorí a zavrie bez pádu. Run:
##   godot --path . -s res://tools/pause_probe.gd


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/%s.png" % name))
	print("saved ", name)


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _find_burger(table: GameTable) -> Button:
	for c in table.get_children():
		if c is Button and c.text == "☰":
			return c
	return null


func _run() -> void:
	while current_scene == null:
		await process_frame
	GameSettings.set_game_mode("normal")

	for dev in [false, true]:
		GameSettings.set_dev_mode(dev)
		current_scene._start_local_game(2)
		current_scene._server.bot_delay = 120.0
		await create_timer(2.0).timeout
		var table: GameTable = current_scene._current_screen
		var burger := _find_burger(table)
		if burger == null:
			print("FAIL: burger button not found (dev=%s)" % dev)
			quit(1)
			return
		burger.pressed.emit()
		await create_timer(0.3).timeout
		if table._pause_layer == null or not table._pause_layer.visible:
			print("FAIL: pause layer not visible after burger (dev=%s)" % dev)
			quit(1)
			return
		print("OK: pause opens (dev=%s)" % dev)
		if dev:
			_snap("probe_pause_devmode")
		table._pause_layer.visible = false
		await create_timer(0.2).timeout

	GameSettings.set_dev_mode(false)
	print("ALL OK")
	quit()
