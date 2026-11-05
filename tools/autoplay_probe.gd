extends SceneTree
## Dev-only probe / smoke test: boots the real app and plays complete games
## through the real table (deal, every animation, game-over screen, "Nová hra"
## through the ad gate) in every match mode, the human seat driven by the bot
## AI. Fails on a stalled table. Also walks the tutorial and a language
## rebuild. Prints "AUTOPLAY OK <games>" or "AUTOPLAY FAIL <reason>" and quits
## with exit code 0/1. The user:// files are backed up and restored. Run:
##   godot --path . -s res://tools/autoplay_probe.gd [-- --phone]
## Grep the output for "SCRIPT ERROR" as well — those don't stop the run.

const FILES := ["user://settings.cfg", "user://progression.cfg",
		"user://monetization.cfg"]
## [game mode, rule preset] per game.
const PLAN := [
	["normal", "faraon"], ["normal", "faraon"], ["olympic", "faraon"],
	["reverse", "faraon"], ["normal", "prsi"],
]
const STALL_SEC := 40.0

var _backup := {}
var _human := BotStrategy.new(BotStrategy.Difficulty.MEDIUM)


func _initialize() -> void:
	for f in FILES:
		_backup[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) \
				else null
	GameSettings.set_tutorial_seen()
	GameSettings.set_rule_preset("faraon")
	Engine.time_scale = 4.0 # animations, bot pauses and timers all scale
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _run() -> void:
	while current_scene == null:
		await process_frame
	var main := current_scene
	await create_timer(0.5).timeout
	print("AUTOPLAY window ", root.size, " phone=", UIKit.phone_mode,
			" resizable=", not root.unresizable)

	# Tutorial: walk every step (interactive ones get the right tap).
	main._show_tutorial()
	await create_timer(0.5).timeout
	var tut: TutorialScreen = main._current_screen
	for _i in 12:
		if not is_instance_valid(tut) or main._current_screen != tut:
			break
		if tut._expected != "":
			for c in tut._stage.get_children():
				if c is CardVisual and c.card_id == tut._expected:
					tut._on_card_tapped(c)
		await create_timer(0.3).timeout
		tut._next_btn.pressed.emit()
		await create_timer(0.4).timeout
	if not (main._current_screen is MainMenu):
		return _fail("tutorial did not return to the menu")

	# Language rebuild (no scene reload) and back.
	var menu: MainMenu = main._current_screen
	var before := GameSettings.get_locale()
	GameSettings.set_locale("cs")
	TranslationServer.set_locale("cs")
	menu.rebuild_requested.emit("settings")
	await create_timer(0.3).timeout
	GameSettings.set_locale(before)
	TranslationServer.set_locale(before)
	main._current_screen.rebuild_requested.emit("")
	await create_timer(0.3).timeout

	var played := 0
	for step in PLAN:
		GameSettings.set_game_mode(step[0])
		GameSettings.set_rule_preset(step[1])
		if not await _play_session(main):
			return
		played += 1
		print("AUTOPLAY session done: ", step, " total=", played)
	_restore()
	print("AUTOPLAY OK ", played)
	quit(0)


## One session = one normal game, or a whole Olympic match (several rounds).
func _play_session(main: Node) -> bool:
	main._start_local_game(3)
	var server: LocalGameServer = main._server
	server.bot_delay = 0.3
	var last_change := Time.get_ticks_msec()
	var last_sig := ""
	while true:
		await create_timer(0.1).timeout
		var table: GameTable = main._current_screen as GameTable
		if table == null:
			continue
		var s: GameState = server.rules.state
		var sig := "%d|%d|%d|%s" % [s.turn_counter, s.discard_pile.size(),
				s.draw_pile.size(), str(table._busy)]
		if sig != last_sig:
			last_sig = sig
			last_change = Time.get_ticks_msec()
		elif (Time.get_ticks_msec() - last_change) / 1000.0 * Engine.time_scale > STALL_SEC:
			_fail("table stalled: %s phase=%d busy=%s queue=%d" % [sig, s.phase,
					table._busy, table._queue.size()])
			return false
		if s.phase == GameState.Phase.GAME_OVER:
			if table._busy or not table._game_over_layer.visible:
				continue
			var m: FaraonMatch = server.match_state
			if m != null and not m.finished:
				table._btn_again.pressed.emit() # next Olympic round
				await create_timer(0.5).timeout
				continue
			return true
		if s.players[s.current_index].id != "YOU" or table._busy:
			continue
		var action := _human.choose(s, "YOU")
		var res := server.propose("YOU", action)
		if not res.ok:
			_fail("human (bot AI) move rejected: %s %s" % [action, res.error])
			return false
	return true


func _fail(reason: String) -> void:
	_restore()
	print("AUTOPLAY FAIL ", reason)
	quit(1)


func _restore() -> void:
	Engine.time_scale = 1.0
	for f in _backup:
		if _backup[f] == null:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fa := FileAccess.open(f, FileAccess.WRITE)
			fa.store_buffer(_backup[f])
			fa.close()
	ConfigCache.invalidate()
