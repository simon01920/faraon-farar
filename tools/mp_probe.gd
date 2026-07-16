extends SceneTree
## Dev-only probe: spawns a real dedicated-server process, connects to it
## over ws://127.0.0.1:9000, creates a room through the lobby UI path and
## verifies the round-trip (room code + start-game rejection for a solo
## player). Run:
##   godot --path . -s res://tools/mp_probe.gd

var _server_pid := -1


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
	_server_pid = OS.create_process(OS.get_executable_path(),
			["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server"])
	print("server pid: ", _server_pid)
	await create_timer(3.0).timeout

	var hub := root.get_node("/root/NetHub")
	var menu: MainMenu = current_scene._current_screen
	menu._open_mp_screen()
	var deadline := 10.0
	while not hub.is_connected_client and deadline > 0.0:
		await create_timer(0.2).timeout
		deadline -= 0.2
	print("connected: ", hub.is_connected_client)

	var got_code := [""]
	hub.joined.connect(func(code, seat, _t):
		got_code[0] = code
		print("joined room ", code, " as ", seat))
	var rejected := [""]
	hub.move_rejected.connect(func(r): rejected[0] = r)

	hub.rpc_id(1, "sv_create_room", "Tester")
	deadline = 5.0
	while got_code[0] == "" and deadline > 0.0:
		await create_timer(0.2).timeout
		deadline -= 0.2
	print("room code: ", got_code[0], " valid: ",
			NetProtocol.valid_code(got_code[0]))

	# Solo start must be rejected server-side (need_players).
	hub.rpc_id(1, "sv_start_game", {})
	deadline = 5.0
	while rejected[0] == "" and deadline > 0.0:
		await create_timer(0.2).timeout
		deadline -= 0.2
	print("solo start rejected with: ", rejected[0])

	await create_timer(0.3).timeout
	_snap("probe_mp_lobby")
	if _server_pid > 0:
		OS.kill(_server_pid)
	quit()
