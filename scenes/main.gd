extends Control
## App root / screen router: menu <-> table. Owns the LocalGameServer node so
## a game survives table rebuilds (new game reuses the same server).

var _current_screen: Control
var _server: LocalGameServer
var _room_client: RoomClient
var _last_bot_count := 1
## Monetizácia: rozhoduje kedy sa smie zobraziť reklama (mock sieť, kým nie je
## nainštalovaný reálny AdMob plugin — pozri monetization/STORE_SETUP.md).
var _ads: AdsController
var _banner: CanvasLayer


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
	# Monetizácia: reklamné okno sa resetuje po >=6h neprítomnosti (rieši sa
	# pri štarte, žiadny časovač na pozadí). Reálny AdMob/StoreKit plugin sa
	# napojí sem cez AdsController.new(<sieť>); default je mock.
	_ads = AdsController.new()
	_ads.on_app_open()
	Iap.refresh_entitlements()
	_build_banner()
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
	menu.remove_ads_changed.connect(_refresh_banner)
	_current_screen = menu
	add_child(menu)
	_refresh_banner() # banner len v menu a len pre free hráča
	# Prvý štart: keď herný mód vybral jazyk zariadenia (čeština → Prší),
	# nechaj hráča potvrdiť. Pri Faraónovi sa nepýtame.
	if GameSettings.preset_needs_confirmation():
		_ask_rule_preset()
		return
	if not GameSettings.tutorial_seen():
		_show_tutorial() # first launch: walk the newcomer through the rules


## Uvítacia otázka pri prvom spustení — vlastný panel v štýle hry (systémový
## AcceptDialog vyzerá ako cudzie okno). Objaví sa len vtedy, keď mód vybral
## jazyk zariadenia; obe možnosti sú rovnocenné tlačidlá.
func _ask_rule_preset() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color("14342a"), 18)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	sb.border_color = UIKit.GOLD.darkened(0.2)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(UIKit.heading(tr("PRESET_ASK_TITLE"), 24, UIKit.GOLD))
	var text := Label.new()
	text.text = tr("PRESET_ASK_BODY")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(500, 0)
	text.add_theme_font_size_override("font_size", 16)
	text.add_theme_color_override("font_color", UIKit.CREAM)
	box.add_child(text)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var b_prsi := UIKit.pill_button(tr("PRESET_PRSI"), UIKit.BLUE,
			Vector2(210, 56), 19)
	b_prsi.pressed.connect(_pick_rule_preset.bind("prsi", layer))
	row.add_child(b_prsi)
	var b_faraon := UIKit.pill_button(tr("PRESET_FARAON"), Color("2e7d4f"),
			Vector2(210, 56), 19)
	b_faraon.pressed.connect(_pick_rule_preset.bind("faraon", layer))
	row.add_child(b_faraon)
	box.add_child(row)
	add_child(layer)


func _pick_rule_preset(preset: String, dialog: Node) -> void:
	GameSettings.set_rule_preset(preset)
	if is_instance_valid(dialog):
		dialog.queue_free()
	# Menu sa postavilo ešte pred voľbou — prestav ho, nech sedia predvolené
	# hodnoty pravidiel. Tutoriál sa spustí odtiaľ (voľba je už uložená).
	_show_menu()


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
	_refresh_banner() # v hre žiadny banner
	var table := GameTable.new()
	table.setup(_room_client)
	table.game_finished.connect(func(): _ads.on_game_completed())
	# rematch goes via the lobby; interstitial (ak dozrela) až po výsledkoch
	table.exit_to_menu_requested.connect(func(): _ads.run_after_results(_show_menu))
	table.new_game_requested.connect(func(): _ads.run_after_results(_show_menu))
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
	_refresh_banner() # v hre žiadny banner
	var table := GameTable.new()
	table.setup(_server)
	table.game_finished.connect(func(): _ads.on_game_completed())
	# Odchod z výsledkov cez reklamnú bránu; medzikolo/Reštart neukáže nič,
	# lebo interstitial sa nazbrojí len keď sa session naozaj skončí.
	table.exit_to_menu_requested.connect(func(): _ads.run_after_results(_show_menu))
	table.new_game_requested.connect(func(): _ads.run_after_results(_on_new_game))
	table.restart_requested.connect(func():
		_ads.run_after_results(func(): _start_local_game(_last_bot_count)))
	_current_screen = table
	add_child(table)


# --- reklamný banner v menu ------------------------------------------------

## Vyhradený priestor pre banner na spodku obrazovky. Mock verzia zobrazuje
## nenápadný placeholder, aby bolo vidno umiestnenie; reálny AdMob banner ho
## nahradí (network.show_banner cez AdsController). Prázdny pre premium.
func _build_banner() -> void:
	_banner = CanvasLayer.new()
	_banner.layer = 5
	var strip := PanelContainer.new()
	strip.name = "Strip"
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -58
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.panel_style(Color("0d241d"), 0)
	sb.border_color = UIKit.GOLD.darkened(0.55)
	sb.border_width_top = 1
	strip.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = tr("AD_BANNER_PLACEHOLDER")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UIKit.CREAM.darkened(0.4))
	strip.add_child(label)
	_banner.add_child(strip)
	add_child(_banner)
	_banner.visible = false


## Banner sa ukáže len v menu a len free hráčovi. Menu sa zároveň o výšku
## bannera skráti, takže obsah pod ním nikdy nie je prekrytý — banner má
## vlastný vyhradený pruh, nie vrstvu cez tlačidlá.
func _refresh_banner() -> void:
	if _banner == null:
		return
	var in_menu := _current_screen is MainMenu
	var free := _ads != null and not _ads.is_premium()
	_banner.visible = in_menu and free
	if in_menu:
		_current_screen.offset_bottom = -58 if _banner.visible else 0
	if _ads != null:
		if _banner.visible:
			_ads.show_menu_banner() # reálny SDK banner (mock = no-op)
		else:
			_ads.hide_banner()


func _clear_screen() -> void:
	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null
