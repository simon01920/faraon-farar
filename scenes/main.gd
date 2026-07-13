extends Control
## App root / screen router: menu <-> table. Owns the LocalGameServer node so
## a game survives table rebuilds (new game reuses the same server).

var _current_screen: Control
var _server: LocalGameServer
var _last_bot_count := 1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	TranslationServer.set_locale(GameSettings.get_locale())
	_show_menu()


func _show_menu() -> void:
	_clear_screen()
	var menu := MainMenu.new()
	menu.local_game_requested.connect(_start_local_game)
	_current_screen = menu
	add_child(menu)


func _start_local_game(bot_count: int) -> void:
	_last_bot_count = bot_count
	_clear_screen()
	if _server == null:
		_server = LocalGameServer.new()
		add_child(_server)
	var table := GameTable.new()
	table.setup(_server)
	table.exit_to_menu_requested.connect(_show_menu)
	table.new_game_requested.connect(func(): _start_local_game(_last_bot_count))
	_current_screen = table
	add_child(table)
	_server.start_game(bot_count, GameSettings.build_variant())


func _clear_screen() -> void:
	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null
