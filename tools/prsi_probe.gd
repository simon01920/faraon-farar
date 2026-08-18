extends SceneTree
## Dev-only probe pre herný mód Prší: dialóg pri prvom spustení, voľba módu
## v nastaveniach a reálna hra podľa českých pravidiel (4 karty, po jednej).
## Run: godot --path . -s res://tools/prsi_probe.gd

var _saved_preset := ""


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/%s.png" % name))
	print("saved ", name)


func _initialize() -> void:
	# Detekcia módu podľa jazyka zariadenia (bez UI).
	for pair in [["cs_CZ", "prsi"], ["sk_SK", "faraon"], ["en_US", "faraon"],
			["de_DE", "faraon"]]:
		var got := GameSettings.detect_rule_preset(pair[0])
		print("detect_rule_preset(%s) = %s %s" % [pair[0], got,
				"OK" if got == pair[1] else "ZLE (cakane %s)" % pair[1]])
	_saved_preset = GameSettings.get_rule_preset()
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _run() -> void:
	while current_scene == null:
		await process_frame
	root.size = Vector2i(1280, 720)
	await create_timer(0.5).timeout

	# 1) Dialóg prvého spustenia (v reále ho spustí české locale zariadenia).
	current_scene._ask_rule_preset()
	await create_timer(0.6).timeout
	_snap("probe_prsi_ask")
	current_scene._pick_rule_preset("prsi", current_scene.get_children().back())
	await create_timer(0.6).timeout
	print("preset po voľbe: ", GameSettings.get_rule_preset(),
			" (očakávané prsi)")

	# 2) Voľba módu v nastaveniach + prestavené predvolené hodnoty pravidiel.
	var menu: MainMenu = current_scene._current_screen
	if menu is MainMenu:
		menu._menu_screen.visible = false
		menu._settings_screen.visible = true
		await create_timer(0.4).timeout
		_snap("probe_prsi_settings")
		menu._settings_screen.scroll_vertical = 1000
		await create_timer(0.3).timeout
		_snap("probe_prsi_rules")
		menu._settings_screen.visible = false
		menu._menu_screen.visible = true

	# 3) Skutočná hra v Prší.
	GameSettings.set_game_mode("normal")
	current_scene._start_local_game(2)
	await create_timer(5.0).timeout
	var table: GameTable = current_scene._current_screen
	while table._busy:
		await create_timer(0.2).timeout
	var s: GameState = table._state()
	print("rozdané karty: ", s.players[0].hand.size(), " (očakávané 4)")
	print("krok trestu: ", s.variant.seven_penalty_step, ", strop: ",
			s.variant.seven_penalty_cap, ", faraón žolík: ",
			s.variant.faraon_is_wild(), ", viac kariet: ",
			s.variant.multi_card_play)
	_snap("probe_prsi_table")

	# Výber sa v Prší nesmie hromadiť — druhé ťuknutie vymení kartu.
	var me: GameState.PlayerState = s.player_by_id("YOU")
	if s.current_index == s.index_of("YOU") and me.hand.size() >= 2:
		table._on_card_tapped(table._find_hand_card(me.hand[0]))
		table._on_card_tapped(table._find_hand_card(me.hand[1]))
		print("vybraných kariet po dvoch ťuknutiach: ", table._selected.size(),
				" (očakávané 1)")

	# Tutoriál sa v Prší nesmie pýtať na faraóna ani spálenú.
	var tut := TutorialScreen.new()
	root.add_child(tut)
	await create_timer(0.3).timeout
	var titles: Array = []
	for st in tut._steps:
		titles.append(st[0])
	print("kroky tutoriálu v Prší: ", ", ".join(titles))
	root.remove_child(tut)
	tut.free()
	await process_frame

	GameSettings.set_rule_preset(_saved_preset)
	quit()
