extends SceneTree
## Dev-only probe: mobile-first layout check. Boots the real app and walks the
## menu screens, the tutorial and a running table (hand, pause menu, game over)
## across phone portrait/landscape, tablet and desktop window sizes; saves
## tools/probe_layout_<screen>_<size>.png. The user:// config files are backed
## up first and restored at the end, so the probe leaves no trace. Run:
##   godot --path . -s res://tools/layout_probe.gd
## Optional: `-- --only=phone_portrait` limits the run to one size;
## `-- --insets=90,0,90,40` simulates a notch / home-indicator safe area
## (left, top, right, bottom in screen pixels) and tags the PNGs "_safe".

const FILES := ["user://settings.cfg", "user://progression.cfg",
		"user://monetization.cfg"]
const SIZES := {
	"phone_portrait": Vector2i(540, 1170),
	"phone_landscape": Vector2i(1170, 540),
	"tablet_portrait": Vector2i(768, 1024),
	"desktop": Vector2i(1280, 720),
	"desktop_wide": Vector2i(1920, 1080),
}

var _backup := {}
var _sizes := {}
var _tag := ""


func _initialize() -> void:
	for f in FILES:
		_backup[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) \
				else null
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--only="):
			only = str(arg).trim_prefix("--only=")
		if str(arg).begins_with("--insets="):
			var p := str(arg).trim_prefix("--insets=").split(",")
			if p.size() == 4:
				UIKit.simulated_insets = Vector4(float(p[0]), float(p[1]),
						float(p[2]), float(p[3]))
				_tag = "_safe"
	for label in SIZES:
		if only == "" or label == only:
			_sizes[label] = SIZES[label]
	GameSettings.set_tutorial_seen()
	GameSettings.set_rule_preset("faraon")
	GameSettings.set_bot_difficulty("easy") # človek začína -> stôl čaká na neho
	GameSettings.set_game_mode("normal")
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _snap(screen: String, size_label: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(
			"res://tools/probe_layout_%s_%s%s.png" % [screen, size_label, _tag]))
	print("saved ", screen, " ", size_label)


func _resize(label: String) -> void:
	root.size = _sizes[label]
	await create_timer(0.35).timeout


func _run() -> void:
	while current_scene == null:
		await process_frame
	var main := current_scene
	await create_timer(0.5).timeout

	# A: menu screens.
	for label in _sizes:
		await _resize(label)
		var menu: MainMenu = main._current_screen
		for screen in ["menu", "settings", "appearance", "challenges", "stats"]:
			var target: Control = {
				"menu": menu._menu_screen, "settings": menu._settings_screen,
				"appearance": menu._appearance_screen,
				"challenges": menu._challenges_screen, "stats": menu._stats_screen,
			}[screen]
			menu._swap_screen(target)
			await create_timer(0.15).timeout
			await _snap(screen, label)
		menu._swap_screen(menu._menu_screen)

	# B: tutorial (first step = interactive matching lesson).
	main._show_tutorial()
	for label in _sizes:
		await _resize(label)
		await create_timer(0.3).timeout
		await _snap("tutorial", label)

	# C: a running table, frozen on the human's turn after the deal.
	main._server = LocalGameServer.new()
	main.add_child(main._server)
	main._server.bot_delay = 9999.0
	main._start_local_game(3)
	await create_timer(7.0).timeout
	var table: GameTable = main._current_screen
	var hand := table._hand_area.get_children().filter(
			func(c): return c is CardVisual and not c.is_queued_for_deletion())
	if not hand.is_empty():
		table._on_card_tapped(hand[0])
	for label in _sizes:
		await _resize(label)
		await create_timer(0.3).timeout
		await _snap("table", label)
	# Veľká ruka: 14 kariet preverí dvojriadkový vejár na úzkych displejoch.
	var me: GameState.PlayerState = main._server.rules.state.player_by_id("YOU")
	var pile: Array = main._server.rules.state.draw_pile
	while me.hand.size() < 14 and not pile.is_empty():
		me.hand.append(pile.pop_back())
	table._refresh_all()
	for label in _sizes:
		await _resize(label)
		await create_timer(0.3).timeout
		await _snap("table_bighand", label)
	table._pause_layer.visible = true
	for label in _sizes:
		await _resize(label)
		await _snap("pause", label)
	table._pause_layer.visible = false
	table._suit_popup.popup_centered()
	for label in _sizes:
		await _resize(label)
		table._suit_popup.popup_centered()
		await _snap("suit", label)
	table._suit_popup.hide()
	table._show_game_over("")
	for label in _sizes:
		await _resize(label)
		await _snap("gameover", label)
	_restore()
	quit()


func _restore() -> void:
	for f in _backup:
		if _backup[f] == null:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fa := FileAccess.open(f, FileAccess.WRITE)
			fa.store_buffer(_backup[f])
			fa.close()
