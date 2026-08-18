extends SceneTree
## Dev-only probe: overí českú lokalizáciu (menu, pravidlá, tutoriál a stôl)
## a detekciu jazyka zo systémového locale. Run:
##   godot --path . -s res://tools/czech_probe.gd


var _saved_locale := "sk"
var _had_explicit_locale := false


func _find_option_button(node: Node) -> OptionButton:
	if node is OptionButton:
		return node
	for c in node.get_children():
		var found := _find_option_button(c)
		if found != null:
			return found
	return null


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/%s.png" % name))
	print("saved ", name)


func _initialize() -> void:
	# Detekcia jazyka zariadenia (sekcia 3): kontrola bez UI.
	for pair in [["cs_CZ", "cs"], ["cs", "cs"], ["sk_SK", "sk"], ["en-US", "en"],
			["de_DE", "en"], ["", "en"]]:
		var got := GameSettings.detect_locale(pair[0])
		print("detect_locale(%s) = %s %s" % [pair[0], got,
				"OK" if got == pair[1] else "ZLE (cakane %s)" % pair[1]])
	# main.gd si jazyk načíta z nastavení, takže ho treba prepnúť ešte pred
	# vytvorením scény; pôvodnú hodnotu vrátime na konci.
	_had_explicit_locale = GameSettings.locale_is_explicit()
	_saved_locale = GameSettings.get_locale()
	GameSettings.set_locale("cs")
	TranslationServer.set_locale("cs")
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _run() -> void:
	while current_scene == null:
		await process_frame
	TranslationServer.set_locale("cs")
	root.size = Vector2i(1280, 720)
	await create_timer(0.5).timeout
	var menu: MainMenu = current_scene._current_screen
	await create_timer(0.3).timeout
	_snap("probe_cs_menu")

	# Chýbajúce preklady by sa prejavili holým kľúčom (VEĽKÉ_PÍSMENÁ).
	var keys := ["MENU_PLAY", "MENU_RULES", "RULES_EXPLAINER", "GAME_DRAW_CARD",
			"ERR_FARAON_MUST_BE_FIRST", "TUT_5_TITLE", "SUIT_GULA",
			"RULE_PUB_MODE_DESC", "STATS_LONGEST_STREAK", "MENU_ALT_NAMES"]
	for k in keys:
		var t := TranslationServer.translate(k)
		print("%s -> %s%s" % [k, t, "  <== CHYBA: nepreložené" if t == k else ""])

	print("APP_NAME=%s | MENU_ALT_NAMES=%s" % [
			TranslationServer.translate("APP_NAME"),
			TranslationServer.translate("MENU_ALT_NAMES")])
	menu._menu_screen.visible = false
	menu._settings_screen.visible = true
	await create_timer(0.3).timeout
	_snap("probe_cs_settings")
	var picker := _find_option_button(menu._settings_screen)
	if picker != null:
		var names: Array = []
		for i in picker.item_count:
			names.append(picker.get_item_text(i))
		print("jazyky v dropdowne: ", ", ".join(names),
				" | vybraný: ", picker.get_item_text(picker.selected))
		picker.show_popup()
		await create_timer(0.4).timeout
		_snap("probe_cs_lang_popup")
		picker.get_popup().hide()
		await create_timer(0.2).timeout
	menu._settings_screen.visible = false
	menu._menu_screen.visible = true

	GameSettings.set_game_mode("normal")
	current_scene._start_local_game(2)
	await create_timer(5.0).timeout
	var table: GameTable = current_scene._current_screen
	while table._busy:
		await create_timer(0.2).timeout
	_snap("probe_cs_table")
	# Nechaj nastavenia presne tak, ako boli — vrátane stavu „bez voľby".
	if _had_explicit_locale:
		GameSettings.set_locale(_saved_locale)
	else:
		GameSettings.clear_locale()
	quit()
