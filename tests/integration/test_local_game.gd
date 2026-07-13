extends GutTest
## Integration: BotStrategy vs BotStrategy driving the full rules engine to
## game over across many seeds, player counts and difficulties. Catches
## deadlocks, illegal-move loops and unreachable game ends that unit tests
## cannot.

const MAX_ACTIONS := 3000


func _play_full_game(player_count: int, seed_value: int,
		diff: int = BotStrategy.Difficulty.MEDIUM) -> GameState:
	var rules := FaraonRules.new()
	var bot := BotStrategy.new(diff, seed_value)
	var ids: Array = []
	for i in player_count:
		ids.append("B%d" % i)
	rules.start(ids, RulesVariant.classic(), seed_value)

	var actions := 0
	while rules.state.phase == GameState.Phase.PLAYING and actions < MAX_ACTIONS:
		var cur := rules.state.players[rules.state.current_index]
		var action := bot.choose(rules.state, cur.id)
		var res := rules.apply(cur.id, action)
		if not res.ok:
			# The bot must produce legal moves; fall back like LocalGameServer
			# does, but count it as a failure signal.
			assert_true(false, "bot illegal move %s -> %s (seed %d)" %
					[action, res.error, seed_value])
			if rules.state.pending_aces > 0:
				rules.apply(cur.id, FaraonActions.pass_turn())
			else:
				rules.apply(cur.id, FaraonActions.draw())
		actions += 1
	return rules.state


func test_two_bots_finish_every_game() -> void:
	for seed_value in range(1, 21):
		var s := _play_full_game(2, seed_value)
		assert_eq(s.phase, GameState.Phase.GAME_OVER,
				"2p game with seed %d must end" % seed_value)
		assert_true(s.loser_index >= 0, "a loser must exist (seed %d)" % seed_value)


func test_four_bots_finish_every_game() -> void:
	for seed_value in range(100, 115):
		var s := _play_full_game(4, seed_value)
		assert_eq(s.phase, GameState.Phase.GAME_OVER,
				"4p game with seed %d must end" % seed_value)


func test_every_difficulty_finishes_games() -> void:
	for diff in [BotStrategy.Difficulty.EASY, BotStrategy.Difficulty.MEDIUM,
			BotStrategy.Difficulty.HARD]:
		for seed_value in range(200, 208):
			var s := _play_full_game(3, seed_value, diff)
			assert_eq(s.phase, GameState.Phase.GAME_OVER,
					"difficulty %d seed %d must end" % [diff, seed_value])


func test_card_conservation_holds_all_game() -> void:
	var rules := FaraonRules.new()
	var bot := BotStrategy.new(BotStrategy.Difficulty.MEDIUM, 777)
	rules.start(["B0", "B1", "B2"], RulesVariant.classic(), 777)
	var actions := 0
	while rules.state.phase == GameState.Phase.PLAYING and actions < MAX_ACTIONS:
		var total := rules.state.draw_pile.size() + rules.state.discard_pile.size()
		for p in rules.state.players:
			total += p.hand.size()
		assert_eq(total, 32, "all 32 cards must always be accounted for")
		if rules.state.phase != GameState.Phase.PLAYING:
			break
		var cur := rules.state.players[rules.state.current_index]
		rules.apply(cur.id, bot.choose(rules.state, cur.id))
		actions += 1
	assert_eq(rules.state.phase, GameState.Phase.GAME_OVER)
