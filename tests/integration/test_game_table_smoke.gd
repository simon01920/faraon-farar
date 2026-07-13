extends GutTest
## Smoke test: the real table UI + LocalGameServer wired together in the
## scene tree. Catches script/runtime errors in the UI layer that pure
## engine tests cannot (headless — no rendering assertions, only structure).


func test_table_builds_and_plays_against_bots() -> void:
	var server := LocalGameServer.new()
	server.bot_delay = 0.02
	add_child_autofree(server)

	var table := GameTable.new()
	table.setup(server)
	table.size = Vector2(1280, 720)
	add_child_autofree(table)

	server.start_game(2, RulesVariant.classic(), 4242)
	await wait_seconds(0.3)

	var s := server.rules.state
	assert_not_null(s)
	assert_eq(s.players.size(), 3)
	var me := s.player_by_id(LocalGameServer.HUMAN_ID)
	assert_true(me.hand.size() >= 5, "human keeps at least the dealt hand")

	# Drive a few human turns programmatically (draw is almost always legal).
	for _i in 6:
		if s.phase != GameState.Phase.PLAYING:
			break
		if s.players[s.current_index].id == LocalGameServer.HUMAN_ID:
			if s.pending_aces > 0:
				server.propose(LocalGameServer.HUMAN_ID, FaraonActions.pass_turn())
			else:
				server.propose(LocalGameServer.HUMAN_ID, FaraonActions.draw())
		await wait_seconds(0.15)

	assert_true(table.get_child_count() > 5, "table UI must have been built")
	assert_true(is_instance_valid(table), "table survived several turns")
