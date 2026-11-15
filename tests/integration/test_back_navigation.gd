extends GutTest
## Android back button / Escape: every screen's handle_back(). The app root
## (scenes/main.gd) quits only when the current screen returns false, so the
## important property is "true everywhere except the main menu itself".


func _menu() -> MainMenu:
	var menu := MainMenu.new()
	menu.size = Vector2(1280, 720)
	add_child_autofree(menu)
	return menu


func test_menu_root_does_not_handle_back() -> void:
	var menu := _menu()
	assert_false(menu.handle_back(), "main menu: back is left to the app (quit)")
	assert_true(menu._menu_screen.visible)


func test_menu_sub_screens_return_to_main_menu() -> void:
	var menu := _menu()
	for screen in ["settings", "appearance", "challenges", "stats"]:
		menu.show_screen(screen)
		assert_false(menu._menu_screen.visible, "%s is open" % screen)
		assert_true(menu.handle_back(), "%s handles back" % screen)
		assert_true(menu._menu_screen.visible, "%s -> main menu" % screen)
	for scr in [menu._settings_screen, menu._appearance_screen,
			menu._challenges_screen, menu._stats_screen, menu._mp_screen]:
		assert_false(scr.visible)


func test_menu_multiplayer_screen_returns_to_main_menu() -> void:
	var menu := _menu()
	# Not via show_screen("multiplayer"): that would start a server connection.
	menu._swap_screen(menu._mp_screen)
	assert_true(menu.handle_back())
	assert_true(menu._menu_screen.visible)
	assert_false(menu._mp_screen.visible)


func test_menu_back_closes_dialog_before_leaving_screen() -> void:
	var menu := _menu()
	menu.show_screen("settings")
	var dialog := UIKit.confirm(menu, "", "?", "yes", "no", func(): pass)
	assert_true(menu.handle_back())
	assert_true(dialog.is_queued_for_deletion(), "first back closes the dialog")
	assert_true(menu._settings_screen.visible, "and stays on the settings screen")
	assert_true(menu.handle_back())
	assert_true(menu._menu_screen.visible, "second back -> main menu")


func test_dismiss_modal_without_dialog_is_false() -> void:
	var host := Control.new()
	add_child_autofree(host)
	host.add_child(Control.new())
	assert_false(UIKit.dismiss_modal(host))


func test_table_back_toggles_pause_and_never_leaves_mid_game() -> void:
	var server := LocalGameServer.new()
	server.bot_delay = 0.02
	add_child_autofree(server)
	var table := GameTable.new()
	table.setup(server)
	table.size = Vector2(1280, 720)
	add_child_autofree(table)
	server.start_game(1, RulesVariant.classic(), 77)
	await wait_seconds(0.1)
	watch_signals(table)

	assert_false(table._pause_layer.visible)
	assert_true(table.handle_back())
	assert_true(table._pause_layer.visible, "back opens the pause menu")
	assert_true(table.handle_back())
	assert_false(table._pause_layer.visible, "back again closes it")
	assert_signal_not_emitted(table, "exit_to_menu_requested")


func test_table_back_on_results_goes_to_menu() -> void:
	var server := LocalGameServer.new()
	add_child_autofree(server)
	var table := GameTable.new()
	table.setup(server)
	table.size = Vector2(1280, 720)
	add_child_autofree(table)
	watch_signals(table)
	table._game_over_layer.visible = true
	table._pause_layer.visible = true
	assert_true(table.handle_back())
	assert_false(table._pause_layer.visible, "an open pause menu closes first")
	assert_signal_not_emitted(table, "exit_to_menu_requested")
	assert_true(table.handle_back())
	assert_signal_emitted(table, "exit_to_menu_requested")


func test_tutorial_back_acts_like_skip() -> void:
	# _finish() persists the seen-flag: keep the real settings file intact.
	var path := GameSettings.PATH
	var had := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()

	var tut := TutorialScreen.new()
	tut.size = Vector2(1280, 720)
	add_child_autofree(tut)
	watch_signals(tut)
	assert_true(tut.handle_back())
	assert_signal_emitted(tut, "finished")
	assert_true(GameSettings.tutorial_seen(), "back marks it seen (no reopen loop)")

	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ConfigCache.invalidate(path)
