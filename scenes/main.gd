extends Control
## App root / screen router: menu <-> table. Owns the LocalGameServer node so
## a game survives table rebuilds (new game reuses the same server).

var _current_screen: Control
var _server: LocalGameServer
var _room_client: RoomClient
var _last_bot_count := 1


## The NetHub autoload, looked up at runtime so scripts also compile under
## `-s` tool runs where autoload identifiers are not resolvable.
func _hub() -> Node:
	return get_node("/root/NetHub")


func _ready() -> void:
	# Dedicated server build (or --server): headless room host, no UI at all.
	if OS.has_feature("dedicated_server") \
			or OS.get_cmdline_user_args().has("--server"):
		_hub().start_server(_parse_port())
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	TranslationServer.set_locale(GameSettings.get_locale())
	GameSettings.apply_audio()
	add_child(GameAudio.new())
	_room_client = RoomClient.new()
	add_child(_room_client)
	_hub().game_started.connect(_on_mp_game_started)
	_show_menu()
	# Invite deep link MVP: `faraon://join/KOD` or `--join=KOD` on the
	# command line pre-fills and auto-joins the room. (Registering the URL
	# scheme on Android needs the gradle build + manifest intent-filter —
	# documented in deployment/README.md as the follow-up step.)
	var join_code := _parse_join_code()
	if join_code != "" and _current_screen is MainMenu:
		_current_screen.auto_join(join_code)


## Port servera: `--port=N` za `--`, inak env FARAON_PORT, inak default 9000.
func _parse_port() -> int:
	for arg in OS.get_cmdline_user_args():
		var s := str(arg)
		if s.begins_with("--port="):
			var p := s.trim_prefix("--port=").to_int()
			if p > 0 and p < 65536:
				return p
	var env := OS.get_environment("FARAON_PORT")
	if env.is_valid_int() and env.to_int() > 0 and env.to_int() < 65536:
		return env.to_int()
	return NetProtocol.DEFAULT_PORT


func _parse_join_code() -> String:
	for arg in Array(OS.get_cmdline_user_args()) + Array(OS.get_cmdline_args()):
		var s := str(arg)
		if s.begins_with("faraon://join/"):
			return s.trim_prefix("faraon://join/").to_upper()
		if s.begins_with("--join="):
			return s.trim_prefix("--join=").to_upper()
	return ""


func _show_menu() -> void:
	_clear_screen()
	var menu := MainMenu.new()
	menu.room_client = _room_client
	menu.local_game_requested.connect(_start_local_game)
	menu.tutorial_requested.connect(_show_tutorial)
	_current_screen = menu
	add_child(menu)
	if not GameSettings.tutorial_seen():
		_show_tutorial() # first launch: walk the newcomer through the rules


func _show_tutorial() -> void:
	_clear_screen()
	var tut := TutorialScreen.new()
	tut.finished.connect(_show_menu)
	_current_screen = tut
	add_child(tut)


## The server started an online round (also fires on mid-game reconnect).
func _on_mp_game_started(_view: Dictionary) -> void:
	if _current_screen is GameTable and _current_screen.server == _room_client:
		return
	_clear_screen()
	var table := GameTable.new()
	table.setup(_room_client)
	table.exit_to_menu_requested.connect(_show_menu)
	table.new_game_requested.connect(_show_menu) # rematch goes via the lobby
	_current_screen = table
	add_child(table)


func _start_local_game(bot_count: int) -> void:
	_last_bot_count = bot_count
	if _server == null:
		_server = LocalGameServer.new()
		add_child(_server)
	_build_table()
	var mode := FaraonMatch.Mode.NORMAL
	match GameSettings.get_game_mode():
		"olympic": mode = FaraonMatch.Mode.OLYMPIC
		"reverse": mode = FaraonMatch.Mode.REVERSE_OLYMPIC
	_server.start_game(bot_count, GameSettings.build_variant(), 0,
			BotStrategy.difficulty_from_string(GameSettings.get_bot_difficulty()),
			mode)


## "Play again" from the table: the next round of a running Olympic match,
## otherwise a brand-new game with the same setup.
func _on_new_game() -> void:
	if _server != null and _server.match_state != null \
			and not _server.match_state.finished:
		_build_table()
		_server.next_round()
	else:
		_start_local_game(_last_bot_count)


func _build_table() -> void:
	_clear_screen()
	var table := GameTable.new()
	table.setup(_server)
	table.exit_to_menu_requested.connect(_show_menu)
	table.new_game_requested.connect(_on_new_game)
	table.restart_requested.connect(func(): _start_local_game(_last_bot_count))
	_current_screen = table
	add_child(table)


func _clear_screen() -> void:
	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null
