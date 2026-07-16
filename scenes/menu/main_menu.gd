class_name MainMenu
extends Control
## Main menu + settings screen, built in code. Local play works today;
## multiplayer entries are visible but disabled until the networking
## milestone. The settings screen holds the app preferences (language) and
## the house-rule toggles that persist via GameSettings and will become the
## room creator's authoritative ruleset in multiplayer.

signal local_game_requested(bot_count: int)

## Injected by the app root; shared with the table when an online game runs.
var room_client: RoomClient

## Full-rect CenterContainers so both screens re-center themselves on any
## window size/aspect — never PRESET_CENTER on a container whose minimum
## size grows after the preset is applied (that leaves content offset
## toward the bottom-right and possibly off-screen/unclickable).
var _menu_screen: ScrollContainer
var _settings_screen: ScrollContainer
var _appearance_screen: ScrollContainer
var _mp_screen: ScrollContainer
var _mp_status: Label
var _mp_join_box: VBoxContainer
var _mp_lobby_box: VBoxContainer
var _mp_code_value: Label
var _mp_members: VBoxContainer
var _mp_start: Button
var _mp_code_input: LineEdit


## Runtime autoload lookup (compiles under -s tool runs too).
func _hub() -> Node:
	return get_node("/root/NetHub")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UIKit.TABLE_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(UIKit.TABLE_GLOW, 0.6), Color(UIKit.TABLE_DARK, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.4)
	gt.fill_to = Vector2(0.5, 1.1)
	gt.width = 640
	gt.height = 640
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var back_art := TextureRect.new()
	back_art.texture = load(CardSkin.active().back_path())
	back_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back_art.modulate = Color(1, 1, 1, 0.10)
	back_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back_art)

	_build_menu()
	_build_settings_screen()
	_build_appearance_screen()
	_build_mp_screen()


func _build_menu() -> void:
	_menu_screen = ScrollContainer.new()
	_menu_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_screen.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(380, 0)
	center.add_child(box)

	var title := UIKit.heading(tr("APP_NAME"), 60, UIKit.GOLD)
	box.add_child(title)
	var subtitle := UIKit.heading(tr("MENU_SUBTITLE"), 18, UIKit.CREAM.darkened(0.1))
	box.add_child(subtitle)
	box.add_child(_spacer(10))
	box.add_child(_profile_row())
	box.add_child(_spacer(10))

	box.add_child(_mode_row())

	var play_label := UIKit.heading(tr("MENU_OPPONENTS"), 19)
	box.add_child(play_label)
	box.add_child(_opponents_row())
	box.add_child(_difficulty_row())
	box.add_child(_spacer(6))

	# Explicit start button — picking a player count must never launch the
	# game by itself (too easy to fat-finger).
	var start := UIKit.pill_button(tr("MENU_START"), Color("2e7d4f"), Vector2(340, 60), 24)
	start.pressed.connect(func(): local_game_requested.emit(GameSettings.get_opponents()))
	box.add_child(start)
	box.add_child(_spacer(8))

	var mp := UIKit.pill_button(tr("MENU_MULTIPLAYER"), UIKit.BLUE, Vector2(340, 52))
	mp.pressed.connect(_open_mp_screen)
	box.add_child(mp)

	var appearance := UIKit.pill_button(tr("MENU_APPEARANCE"),
			Color("55617a"), Vector2(340, 52))
	appearance.pressed.connect(func():
		_appearance_screen.visible = true
		_menu_screen.visible = false)
	box.add_child(appearance)

	# Settings sits last in the menu by design.
	var settings := UIKit.pill_button(tr("MENU_SETTINGS"),
			UIKit.GOLD.darkened(0.25), Vector2(340, 52))
	settings.pressed.connect(func():
		_settings_screen.visible = true
		_menu_screen.visible = false)
	box.add_child(settings)


func _build_settings_screen() -> void:
	# Scroll wrapper so a panel taller than the window scrolls instead of
	# getting clipped (Späť must stay reachable on short screens).
	_settings_screen = ScrollContainer.new()
	_settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_screen.visible = false
	add_child(_settings_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_screen.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(620, 0)
	panel.add_child(box)

	box.add_child(UIKit.heading(tr("MENU_SETTINGS"), 30, UIKit.GOLD))

	box.add_child(_language_row())
	box.add_child(_spacer(6))

	box.add_child(UIKit.heading(tr("MENU_RULES"), 21, UIKit.CREAM))
	var hint := UIKit.heading(tr("MENU_RULES_HINT"), 15, UIKit.CREAM.darkened(0.15))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	for key in GameSettings.RULE_TOGGLES:
		box.add_child(_toggle_row(key, GameSettings.RULE_TOGGLES[key]))

	box.add_child(_spacer(10))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func():
		_settings_screen.visible = false
		_menu_screen.visible = true)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	box.add_child(back_row)


## Multiplayer lobby: connect, create/join a room by code, see who is
## seated, invite a friend, and (as host) start the game.
func _build_mp_screen() -> void:
	_mp_screen = ScrollContainer.new()
	_mp_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mp_screen.visible = false
	add_child(_mp_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mp_screen.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(520, 0)
	panel.add_child(box)

	box.add_child(UIKit.heading(tr("MENU_MULTIPLAYER"), 30, UIKit.GOLD))
	_mp_status = UIKit.heading("", 16, UIKit.CREAM.darkened(0.15))
	_mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_mp_status)

	# --- not in a room yet: create / join by code
	_mp_join_box = VBoxContainer.new()
	_mp_join_box.add_theme_constant_override("separation", 10)
	box.add_child(_mp_join_box)

	var create := UIKit.pill_button(tr("MP_CREATE"), Color("2e7d4f"), Vector2(340, 52))
	create.pressed.connect(func():
		_mp_status.text = tr("MP_CONNECTING")
		_hub().rpc_id(1, "sv_create_room", _player_display_name()))
	var create_row := HBoxContainer.new()
	create_row.alignment = BoxContainer.ALIGNMENT_CENTER
	create_row.add_child(create)
	_mp_join_box.add_child(create_row)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 10)
	_mp_code_input = LineEdit.new()
	_mp_code_input.placeholder_text = tr("MP_CODE_HINT")
	_mp_code_input.max_length = NetProtocol.ROOM_CODE_LEN
	_mp_code_input.custom_minimum_size = Vector2(180, 48)
	join_row.add_child(_mp_code_input)
	var join := UIKit.pill_button(tr("MP_JOIN"), UIKit.BLUE, Vector2(170, 48), 18)
	join.pressed.connect(func():
		_mp_status.text = tr("MP_CONNECTING")
		_hub().rpc_id(1, "sv_join_room",
				_mp_code_input.text.strip_edges().to_upper(),
				_player_display_name(), ""))
	join_row.add_child(join)
	_mp_join_box.add_child(join_row)

	# --- seated in a room: code, members, invite, start (host)
	_mp_lobby_box = VBoxContainer.new()
	_mp_lobby_box.add_theme_constant_override("separation", 10)
	_mp_lobby_box.visible = false
	box.add_child(_mp_lobby_box)

	_mp_code_value = UIKit.heading("", 44, UIKit.GOLD)
	_mp_lobby_box.add_child(_mp_code_value)
	_mp_members = VBoxContainer.new()
	_mp_members.add_theme_constant_override("separation", 4)
	_mp_lobby_box.add_child(_mp_members)

	var invite := UIKit.pill_button(tr("MP_INVITE"), Color("55617a"), Vector2(340, 48), 18)
	invite.pressed.connect(func():
		DisplayServer.clipboard_set(tr("MP_INVITE_TEXT") % room_client.room_code)
		_mp_status.text = tr("MP_INVITE_COPIED"))
	var invite_row := HBoxContainer.new()
	invite_row.alignment = BoxContainer.ALIGNMENT_CENTER
	invite_row.add_child(invite)
	_mp_lobby_box.add_child(invite_row)

	_mp_start = UIKit.pill_button(tr("MENU_START"), Color("2e7d4f"), Vector2(340, 56), 22)
	_mp_start.visible = false
	_mp_start.pressed.connect(func():
		_hub().rpc_id(1, "sv_start_game", GameSettings.build_variant().to_dict()))
	var start_row := HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	start_row.add_child(_mp_start)
	_mp_lobby_box.add_child(start_row)

	var leave := UIKit.pill_button(tr("MP_LEAVE"), UIKit.RED, Vector2(240, 44), 16)
	leave.pressed.connect(func():
		_hub().rpc_id(1, "sv_leave")
		_mp_lobby_box.visible = false
		_mp_join_box.visible = true
		_mp_status.text = "")
	var leave_row := HBoxContainer.new()
	leave_row.alignment = BoxContainer.ALIGNMENT_CENTER
	leave_row.add_child(leave)
	_mp_lobby_box.add_child(leave_row)

	box.add_child(_spacer(6))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func():
		_mp_screen.visible = false
		_menu_screen.visible = true)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	box.add_child(back_row)

	_hub().connected_to_server.connect(func(): _mp_status.text = tr("MP_WAITING_INPUT"))
	_hub().connection_failed_or_lost.connect(func():
		_mp_status.text = tr("MP_CONN_FAILED"))
	_hub().joined.connect(func(code, _seat, _token):
		_mp_join_box.visible = false
		_mp_lobby_box.visible = true
		_mp_code_value.text = code
		_mp_status.text = tr("MP_WAITING"))
	_hub().join_failed.connect(func(reason):
		_mp_status.text = tr("MP_ERR_" + reason.to_upper()) \
				if tr("MP_ERR_" + reason.to_upper()) != "MP_ERR_" + reason.to_upper() \
				else tr("MP_CONN_FAILED"))
	_hub().room_updated.connect(_on_mp_room_update)


func _open_mp_screen() -> void:
	_menu_screen.visible = false
	_mp_screen.visible = true
	if not _hub().is_connected_client:
		_mp_status.text = tr("MP_CONNECTING")
		_hub().connect_to_server(GameSettings.get_server_url())
	if room_client != null and room_client.room_code != "":
		_mp_join_box.visible = false
		_mp_lobby_box.visible = true
		_mp_code_value.text = room_client.room_code


func _on_mp_room_update(info: Dictionary) -> void:
	for c in _mp_members.get_children():
		c.queue_free()
	var members: Array = info.get("members", [])
	for m in members:
		var line := "%s%s" % [m.get("name", "?"),
				"" if m.get("connected", true) else "  (offline)"]
		_mp_members.add_child(UIKit.heading(line, 18, UIKit.CREAM))
	# The first seat is the host — only they see the start button.
	_mp_start.visible = room_client != null and not members.is_empty() \
			and members[0].get("seat", "") == room_client.my_seat \
			and not info.get("playing", false)


func _player_display_name() -> String:
	var custom := GameSettings.get_player_name()
	return custom if custom != "" else tr("PLAYER_YOU")


## Player chip: name, level and the progress toward the next one. The ✎
## button opens a small popup to change the display name.
func _profile_row() -> Control:
	var row := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.30), 12)
	sb.shadow_size = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var name_value := GameSettings.get_player_name()
	if name_value == "":
		name_value = tr("PLAYER_YOU")
	var prog := Progression.progress_for(ProgressionStore.total_points())
	var name_label := Label.new()
	name_label.text = "%s  ·  %s" % [name_value, tr("PROFILE_LEVEL") % prog.level]
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", UIKit.CREAM)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name_label)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = prog.needed
	bar.value = prog.into
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)

	var edit := UIKit.pill_button("✎", Color("55617a"), Vector2(44, 36), 16)
	edit.pressed.connect(_open_name_popup)
	h.add_child(edit)
	return row


func _open_name_popup() -> void:
	var popup := PopupPanel.new()
	var sb := UIKit.panel_style(UIKit.TABLE_MID, 16, UIKit.GOLD, 2)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(UIKit.heading(tr("PROFILE_NAME"), 20))
	var input := LineEdit.new()
	input.text = GameSettings.get_player_name()
	input.placeholder_text = tr("PLAYER_YOU")
	input.max_length = 16
	input.custom_minimum_size = Vector2(240, 40)
	box.add_child(input)
	var save := UIKit.pill_button(tr("MENU_BACK_SHORT"), Color("2e7d4f"), Vector2(160, 44), 17)
	var commit := func():
		GameSettings.set_player_name(input.text)
		popup.hide()
		get_tree().reload_current_scene()
	save.pressed.connect(commit)
	input.text_submitted.connect(func(_t): commit.call())
	var save_row := HBoxContainer.new()
	save_row.alignment = BoxContainer.ALIGNMENT_CENTER
	save_row.add_child(save)
	box.add_child(save_row)
	popup.add_child(box)
	add_child(popup)
	popup.popup_centered()
	input.grab_focus()


## Appearance screen: pick the card skin and the table look. Locked table
## looks (level rewards) show their required level and stay disabled.
func _build_appearance_screen() -> void:
	_appearance_screen = ScrollContainer.new()
	_appearance_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_appearance_screen.visible = false
	add_child(_appearance_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_appearance_screen.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)

	box.add_child(UIKit.heading(tr("MENU_APPEARANCE"), 30, UIKit.GOLD))

	box.add_child(UIKit.heading(tr("APPEARANCE_CARDS"), 20, UIKit.CREAM))
	var skin_row := HBoxContainer.new()
	skin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skin_row.add_theme_constant_override("separation", 10)
	box.add_child(skin_row)
	var refresh_skins := func():
		for c in skin_row.get_children():
			c.queue_free()
		for skin in CardSkin.selectable():
			var b := UIKit.pill_button(tr(skin.name_key), Color("2e7d4f"),
					Vector2(240, 46), 17)
			b.modulate.a = 1.0 if GameSettings.get_card_skin() == skin.id else 0.5
			skin_row.add_child(b)
			b.pressed.connect(func():
				GameSettings.set_card_skin(skin.id)
				for s in skin_row.get_children():
					s.modulate.a = 0.5
				b.modulate.a = 1.0)
	refresh_skins.call()

	box.add_child(UIKit.heading(tr("APPEARANCE_TABLE"), 20, UIKit.CREAM))
	var table_grid := VBoxContainer.new()
	table_grid.add_theme_constant_override("separation", 8)
	box.add_child(table_grid)
	for look in TableLook.all():
		var unlocked := look.is_unlocked()
		var label := tr(look.name_key) if unlocked \
				else "%s  —  %s" % [tr(look.name_key),
						tr("LOCKED_LEVEL") % Rewards.level_required(look.id)]
		var b := UIKit.pill_button(label, Color("386a50") if unlocked
				else Color("3a3f45"), Vector2(460, 46), 17)
		b.disabled = not unlocked
		b.modulate.a = 1.0 if GameSettings.get_table_look() == look.id else 0.55
		table_grid.add_child(b)
		if unlocked:
			b.pressed.connect(func():
				GameSettings.set_table_look(look.id)
				for row in table_grid.get_children():
					row.modulate.a = 0.55
				b.modulate.a = 1.0)

	box.add_child(_spacer(8))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func():
		_appearance_screen.visible = false
		_menu_screen.visible = true)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	box.add_child(back_row)


## Generic segmented picker row: [[value, label_key], ...] with a persisted
## getter/setter pair; the active segment renders at full opacity.
func _segmented_row(options: Array, get_current: Callable, set_current: Callable,
		btn_size: Vector2, font_size: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var buttons := {}
	var recolor := func():
		for key in buttons:
			var b: Button = buttons[key]
			b.modulate = Color(1, 1, 1, 1.0 if get_current.call() == key else 0.45)
	for opt in options:
		var b := UIKit.pill_button(tr(opt[1]) if opt[1] is String and tr(opt[1]) != opt[1]
				else str(opt[1]), color, btn_size, font_size)
		b.pressed.connect(func():
			set_current.call(opt[0])
			recolor.call())
		buttons[opt[0]] = b
		row.add_child(b)
	recolor.call()
	return row


## Klasický / Olympijský / Reverzný game-mode picker.
func _mode_row() -> Control:
	return _segmented_row(
			[["normal", "MODE_NORMAL"], ["olympic", "MODE_OLYMPIC"],
					["reverse", "MODE_REVERSE"]],
			func(): return GameSettings.get_game_mode(),
			func(m): GameSettings.set_game_mode(m),
			Vector2(122, 44), 15, Color("55617a"))


## 1 / 2 / 3 opponent selector — selection only, the start button launches.
func _opponents_row() -> Control:
	return _segmented_row(
			[[1, "1"], [2, "2"], [3, "3"]],
			func(): return GameSettings.get_opponents(),
			func(n): GameSettings.set_opponents(n),
			Vector2(96, 52), 24, Color("386a50"))


## Easy/Medium/Hard segmented picker; persists via GameSettings and colors
## the active segment gold. Cosmetic only for the menu — the difficulty is
## applied when the next local game starts.
func _difficulty_row() -> Control:
	return _segmented_row(
			[["easy", "DIFF_EASY"], ["medium", "DIFF_MEDIUM"], ["hard", "DIFF_HARD"]],
			func(): return GameSettings.get_bot_difficulty(),
			func(d): GameSettings.set_bot_difficulty(d),
			Vector2(104, 40), 16, UIKit.GOLD.darkened(0.35))


func _language_row() -> Control:
	var row := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.22), 12)
	sb.shadow_size = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	var title := Label.new()
	title.text = tr("SETTINGS_LANGUAGE")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIKit.CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(title)

	var lang := UIKit.pill_button(
			"SK" if TranslationServer.get_locale().begins_with("sk") else "EN",
			Color("6b5a3e"), Vector2(110, 44), 18)
	lang.pressed.connect(func():
		var next := "en" if TranslationServer.get_locale().begins_with("sk") else "sk"
		GameSettings.set_locale(next)
		TranslationServer.set_locale(next)
		get_tree().reload_current_scene())
	h.add_child(lang)
	return row


func _toggle_row(key: String, label_key: String) -> Control:
	var row := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.22), 12)
	sb.shadow_size = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = tr(label_key)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIKit.CREAM)
	texts.add_child(title)
	var desc := Label.new()
	desc.text = tr(label_key + "_DESC")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UIKit.CREAM.darkened(0.3))
	texts.add_child(desc)
	h.add_child(texts)

	var toggle := CheckButton.new()
	toggle.button_pressed = GameSettings.get_rule(key)
	toggle.toggled.connect(func(on: bool): GameSettings.set_rule(key, on))
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(toggle)
	return row


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
