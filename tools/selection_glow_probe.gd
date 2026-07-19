extends SceneTree
## Dev-only probe: zlatá žiara na vlastných vybraných kartách + nadvihnuté
## žiariace ruby súpera (cez server signál, t. j. celá wiring cesta). Run:
##   godot --path . -s res://tools/selection_glow_probe.gd


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
	GameSettings.set_game_mode("normal")
	current_scene._start_local_game(2)
	var server: LocalGameServer = current_scene._server
	server.bot_delay = 120.0
	await create_timer(6.0).timeout
	var table: GameTable = current_scene._current_screen
	while table._busy:
		await create_timer(0.2).timeout

	# Vlastný výber: 3 karty rovnakého znaku ak sa dá, inak prvé tri.
	var s: GameState = server.rules.state
	var me: GameState.PlayerState = s.player_by_id("YOU")
	for i in mini(3, me.hand.size()):
		table._selected.append(me.hand[i])
	table._refresh_hand(s)

	# Súperov výber cez server signál — presne cesta bot preview/multiplayer.
	server.selection_updated.emit("BOT1", 3)
	server.selection_updated.emit("BOT2", 1)
	await create_timer(0.4).timeout
	_snap("probe_selection_glow")

	# Zrušenie výberu musí ruby vrátiť do vejára.
	server.selection_updated.emit("BOT1", 0)
	await create_timer(0.3).timeout
	var seat: PlayerSeat = table._seats.get("BOT1")
	print("BOT1 raised after clear: ", seat._selected_shown)
	quit()
