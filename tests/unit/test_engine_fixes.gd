extends GutTest
## Regression tests for the engine/bot/progression review fixes. Each test
## reproduces a concrete failure of the previous code (crash, state corruption,
## hidden-information leak, illegal bot move or wrong statistics).

const R := FaraonCard.Rank


func make_rules(hands: Array, top: String, draw: Array = []) -> FaraonRules:
	var r := FaraonRules.new()
	var s := GameState.new()
	s.variant = RulesVariant.classic()
	for i in hands.size():
		var p := GameState.PlayerState.new()
		p.id = "P%d" % i
		p.hand.assign(hands[i])
		s.players.append(p)
	s.discard_pile.assign([top])
	s.draw_pile.assign(draw)
	r.state = s
	return r


func play(r: FaraonRules, pid: String, cards: Array, declared := -1,
		declared_rank := -1) -> Dictionary:
	return r.apply(pid, FaraonActions.play(cards, declared, declared_rank))


func _finish(r: FaraonRules, i: int, handover: int, position: int) -> void:
	var p := r.state.players[i]
	p.hand.clear()
	p.status = GameState.PlayerStatus.FINISHED
	p.finished_at = handover
	p.finished_at_handover = handover
	p.finish_position = position


# --- #1 deal never overdraws the deck ----------------------------------------

func test_start_caps_the_deal_so_the_deck_is_never_overdrawn() -> void:
	var v := RulesVariant.classic()
	v.initial_hand_size = 7 # 5 x 7 = 35 > 32
	var r := FaraonRules.new()
	var events := r.start(["A", "B", "C", "D", "E"], v, 1)
	assert_not_null(events, "start() must not abort")
	for p in r.state.players:
		assert_eq(p.hand.size(), 6, "cap = (32 - 2) / 5")
	assert_eq(r.state.discard_pile.size(), 1, "start card is on the pile")
	assert_gte(r.state.draw_pile.size(), 1, "a bottom card always remains")


func test_start_caps_oversized_per_player_hand_sizes() -> void:
	var r := FaraonRules.new()
	r.start(["A", "B"], RulesVariant.classic(), 7, {"A": 20, "B": 3})
	assert_eq(r.state.players[0].hand.size(), 15, "(32 - 2) / 2")
	assert_eq(r.state.players[1].hand.size(), 3)
	assert_gte(r.state.draw_pile.size(), 1)


func test_variant_from_dict_clamps_hand_size_to_slider_range() -> void:
	assert_eq(RulesVariant.from_dict({"initial_hand_size": 20}).initial_hand_size, 7)
	assert_eq(RulesVariant.from_dict({"initial_hand_size": 1}).initial_hand_size, 4)
	assert_eq(RulesVariant.from_dict({"initial_hand_size": 6}).initial_hand_size, 6)


# --- #2 censored view ----------------------------------------------------------

func test_view_does_not_leak_the_shuffle_seed() -> void:
	var r := FaraonRules.new()
	r.start(["A", "B", "C"], RulesVariant.classic(), 424242)
	for id in ["A", "B", "C"]:
		assert_false(r.state.view_for(id).has("rng_seed"),
				"with the seed a client could replay the whole deal")


func test_view_shows_interrupt_card_only_to_its_owner() -> void:
	var r := make_rules([["9G", "DE"], ["8G"], ["XG"]], "7Z", ["8Z"])
	r.state.current_index = 0
	r.state.penalty_interrupt = true
	r.state.interrupt_card = "DE"
	r.state.pending_sevens_draw = 2
	assert_eq(r.state.view_for("P0")["interrupt_card"], "DE")
	assert_true(r.state.view_for("P0")["penalty_interrupt"])
	assert_eq(r.state.view_for("P1")["interrupt_card"], "")
	assert_eq(r.state.view_for("P2")["interrupt_card"], "")
	assert_true(r.state.view_for("P1")["penalty_interrupt"],
			"the pause itself stays public")


# --- #3 a rejected move changes nothing -----------------------------------------

func test_rejected_faraon_defense_keeps_the_penalty() -> void:
	var r := make_rules([["DE", "DZ", "9G"], ["8G", "9Z"]], "7Z",
			["8Z", "8C", "XC", "XE"])
	r.state.variant.unter_announcer = true
	r.state.pending_sevens_draw = 3
	var res := play(r, "P0", ["DE", "DZ"]) # missing D11 rank
	assert_eq(res.error, "declared_rank_required")
	assert_eq(r.state.pending_sevens_draw, 3, "penalty must survive a rejected move")
	assert_eq(r.state.players[0].hand.size(), 3)
	assert_true(play(r, "P0", ["DE", "DZ"], -1, R.R9).ok,
			"with the rank the same defense works")
	assert_eq(r.state.pending_sevens_draw, 0)


func test_rejected_faraon_eso_block_keeps_the_eso_chain() -> void:
	var r := make_rules([["DE", "DZ", "9G"], ["8G", "9Z"]], "AZ", ["8Z", "8C"])
	r.state.variant.unter_announcer = true
	r.state.variant.faraon_blocks_eso = true
	r.state.pending_aces = 1
	assert_eq(play(r, "P0", ["DE", "DZ"]).error, "declared_rank_required")
	assert_eq(r.state.pending_aces, 1, "eso chain must survive a rejected move")


func test_rejected_interrupt_play_keeps_the_pause_and_penalty() -> void:
	var r := make_rules([["DE", "DZ", "9G"], ["8G", "9Z"]], "7Z", ["8Z", "8C"])
	r.state.variant.unter_announcer = true
	r.state.penalty_interrupt = true
	r.state.interrupt_card = "DE"
	r.state.pending_sevens_draw = 2
	assert_eq(play(r, "P0", ["DE", "DZ"]).error, "declared_rank_required")
	assert_true(r.state.penalty_interrupt)
	assert_eq(r.state.interrupt_card, "DE")
	assert_eq(r.state.pending_sevens_draw, 2)
	assert_true(r.apply("P0", FaraonActions.draw()).ok)
	assert_eq(r.state.players[0].hand.size(), 3 + 2, "the remaining 2 are drawn")


# --- #4 dry deck mid-penalty ------------------------------------------------------

func test_dry_deck_forfeits_the_rest_of_the_penalty() -> void:
	var r := make_rules([["9G"], ["8G", "9Z"], ["XG"]], "7Z", ["8Z"])
	r.state.pending_sevens_draw = 3
	assert_true(r.apply("P0", FaraonActions.draw()).ok)
	assert_eq(r.state.players[0].hand.size(), 2, "only one card was left")
	assert_eq(r.state.current_index, 1)
	assert_eq(r.state.pending_sevens_draw, 0,
			"the unpaid rest never passes to the next player")


# --- #5 red-ten seal ------------------------------------------------------------------

func test_sealed_penalty_offers_no_pause() -> void:
	var r := make_rules([["9G", "8Z"], ["7Z", "8G"], ["7E", "KG"]], "XC",
			["8C", "9E", "8E", "DE"])
	r.state.variant.red_ten = true
	r.state.variant.seven_interrupt = true
	r.state.pending_sevens_draw = 4
	r.state.pending_hard_penalty = true
	assert_true(r.apply("P0", FaraonActions.draw()).ok)
	assert_false(r.state.penalty_interrupt, "a sealed penalty cannot be escaped")
	assert_eq(r.state.players[0].hand.size(), 2 + 4, "the whole sealed penalty drawn")
	assert_false(r.state.pending_hard_penalty)


func test_red_seven_return_over_a_sealed_penalty_clears_the_seal() -> void:
	var r := make_rules([["7C", "8Z"], ["9C"], ["7E", "KG", "9Z"]], "XC",
			["8C", "9E", "DE", "9G", "AC", "AZ", "8E", "XZ"])
	r.state.variant.red_ten = true
	r.state.variant.red7_return_scope = "anyone"
	_finish(r, 1, 0, 1)
	r.state.pending_sevens_draw = 4
	r.state.pending_hard_penalty = true
	assert_true(play(r, "P0", ["7C"]).ok)
	assert_eq(r.state.players[1].status, GameState.PlayerStatus.ACTIVE, "P1 returned")
	assert_false(r.state.pending_hard_penalty, "the consumed penalty leaves no seal")
	# A brand-new seven chain must be defendable again.
	r.state.current_index = 2
	r.state.discard_pile.assign(["7Z"])
	r.state.pending_sevens_draw = 3
	assert_true(play(r, "P2", ["7E"]).ok, "fresh chain is not sealed")


# --- #6 Olympic allotments ----------------------------------------------------------

func test_match_allotments_start_from_the_rule_hand_size() -> void:
	var m := FaraonMatch.new(FaraonMatch.Mode.OLYMPIC, ["A", "B", "C"], "A", 4)
	assert_eq(m.hand_sizes(), {"A": 4, "B": 4, "C": 4})
	var d := FaraonMatch.new(FaraonMatch.Mode.OLYMPIC, ["A", "B"])
	assert_eq(d.hand_sizes(), {"A": FaraonMatch.START_SIZE, "B": FaraonMatch.START_SIZE})


func test_olympic_first_round_and_shootout_deal_the_same_size() -> void:
	var srv := LocalGameServer.new()
	srv.bot_delay = 100.0 # no bot timer may fire during the test
	add_child_autofree(srv)
	var v := RulesVariant.classic()
	v.initial_hand_size = 4
	srv.start_game(2, v, 123, BotStrategy.Difficulty.EASY, FaraonMatch.Mode.OLYMPIC)
	for p in srv.rules.state.players:
		assert_eq(p.hand.size(), 4, "first sub-round uses D2 hand size")
	srv.rules.state.players[0].finish_position = 1
	srv.match_state.on_sub_round_over(srv.rules.state)
	srv.next_round()
	assert_eq(srv.rules.state.players.size(), 2, "shootout of the remaining two")
	for p in srv.rules.state.players:
		assert_eq(p.hand.size(), 4, "shootout deals the same allotment")


# --- #7 challenge payout is points only ----------------------------------------------

func test_challenge_payout_does_not_count_as_a_played_game() -> void:
	var path := ProjectSettings.globalize_path(ProgressionStore.PATH)
	var backup := FileAccess.get_file_as_bytes(ProgressionStore.PATH) \
			if FileAccess.file_exists(ProgressionStore.PATH) else PackedByteArray()
	var had_file := FileAccess.file_exists(ProgressionStore.PATH)
	DirAccess.remove_absolute(path)
	ConfigCache.invalidate(ProgressionStore.PATH)

	# Complete every pool challenge, whichever three are active today.
	for _i in 3:
		Challenges.on_game_finished(5, 1, "hard", "olympic")
	Challenges.observe_event({"type": "SPALENA_EXTRA_TURN", "player": "YOU"}, "YOU")
	Challenges.observe_event({"type": "PLAYER_RETURNED", "by": "YOU"}, "YOU")
	Challenges.observe_event({"type": "CARDS_PLAYED", "player": "YOU",
			"cards": ["AZ", "AC"]}, "YOU")
	var total := ProgressionStore.total_points()
	var played := ProgressionStore.games_played()
	var medium := ProgressionStore.counter("games_medium")
	var normal := ProgressionStore.counter("mode_normal")

	# Restore the player's save exactly as it was.
	DirAccess.remove_absolute(path)
	if had_file:
		var f := FileAccess.open(ProgressionStore.PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	ConfigCache.invalidate(ProgressionStore.PATH)

	assert_eq(total, Challenges.ACTIVE_PER_DAY * Challenges.CHALLENGE_POINTS,
			"every active challenge paid out once")
	assert_eq(played, 0, "challenge points are not a played game")
	assert_eq(medium, 0, "no phantom 'medium' game slice")
	assert_eq(normal, 0, "no phantom 'normal' mode slice")


# --- #8 bots never propose illegal moves -----------------------------------------------

func _bot_move_is_legal(r: FaraonRules, pid: String) -> Dictionary:
	var bot := BotStrategy.new(BotStrategy.Difficulty.HARD, 1)
	var action := bot.choose(r.state, pid)
	var res := r.apply(pid, action)
	assert_true(res.ok, "bot action %s rejected: %s" % [action, res.error])
	return action


func test_bot_declares_suit_when_the_announced_rank_is_hornik() -> void:
	var r := make_rules([["HZ", "9G", "8C"], ["8G", "9Z"]], "DZ", ["8Z", "8C"])
	r.state.variant.unter_announcer = true
	r.state.announced_rank = R.HORNIK
	var action := _bot_move_is_legal(r, "P0")
	assert_eq(action.cards, ["HZ"])


func test_bot_declares_rank_when_the_announced_rank_is_dolnik() -> void:
	var r := make_rules([["DZ", "9G", "8C"], ["8G", "9Z"]], "DC", ["8Z", "8C"])
	r.state.variant.unter_announcer = true
	r.state.announced_rank = R.DOLNIK
	var action := _bot_move_is_legal(r, "P0")
	assert_eq(action.cards, ["DZ"])


func test_bot_declares_rank_for_a_non_wild_green_unter() -> void:
	# Prší + D11: zelený spodok nie je faraón, takže je to bežný spodok-menič.
	var r := make_rules([["DE", "9G"], ["8G", "9Z"]], "DC", ["8Z", "8C"])
	r.state.variant = RulesVariant.prsi()
	r.state.variant.unter_announcer = true
	r.state.announced_rank = R.DOLNIK
	var action := _bot_move_is_legal(r, "P0")
	assert_eq(action.cards, ["DE"])


func test_bot_respects_the_finish_rule() -> void:
	var r := make_rules([["9Z"], ["8G", "9C"]], "8Z", ["8E", "8C"])
	r.state.variant.finish_rule = "hornik_only"
	var action := _bot_move_is_legal(r, "P0")
	assert_eq(action.action, FaraonActions.DRAW, "9Z may not be the last card")
	# Multi-card: the group keeps one card back instead of finishing illegally.
	r = make_rules([["7Z", "7C"], ["8G", "XG"]], "8Z", ["8E", "8C"])
	r.state.variant.finish_rule = "no_seven"
	action = _bot_move_is_legal(r, "P0")
	assert_eq(action.action, FaraonActions.PLAY_CARDS)
	assert_eq(action.cards, ["7Z"], "one seven stays in hand")


func test_bot_draws_a_sealed_penalty() -> void:
	var r := make_rules([["7Z", "9G"], ["8G", "9Z"]], "XC",
			["8E", "8C", "9C", "9E"])
	r.state.variant.red_ten = true
	r.state.pending_sevens_draw = 4
	r.state.pending_hard_penalty = true
	var action := _bot_move_is_legal(r, "P0")
	assert_eq(action.action, FaraonActions.DRAW)


func test_bot_does_not_answer_a_green_king_with_a_plain_seven() -> void:
	var r := make_rules([["7Z", "9G"], ["8G", "9Z"]], "KE",
			["8E", "8C", "9C", "9E"])
	r.state.variant.green_king = true
	r.state.pending_sevens_draw = 4
	var action := _bot_move_is_legal(r, "P0")
	assert_eq(action.action, FaraonActions.DRAW)


func test_bot_sole_survivor_leads_with_the_red_seven_in_single_card_mode() -> void:
	var r := make_rules([["7Z", "7C", "9G"], [], []], "8C", ["8E", "9E"])
	r.state.variant.multi_card_play = false
	_finish(r, 2, 1, 1)
	_finish(r, 1, 3, 2)
	r.state.handovers = 3
	var action := _bot_move_is_legal(r, "P0")
	assert_eq(action.cards, ["7C"])
	assert_eq(r.state.players[1].status, GameState.PlayerStatus.ACTIVE,
			"the latest finisher was returned")


# --- #9 start horník ignores the Tanečnica --------------------------------------------

func test_start_hornik_skips_a_bottom_reverse_card() -> void:
	var r := make_rules([["9Z"], ["8G"]], "HZ", ["RV", "9E", "8C"])
	var events: Array = []
	r._apply_start_card_effects("HZ", events)
	assert_eq(r.state.declared_suit, FaraonCard.Suit.ZELEN, "suit of 9E, not -1")
	var flips: Array = events.filter(func(e): return e.type == "START_DECK_FLIP")
	assert_eq(flips[0].bottom, "9E")


# --- #10 the Tanečnica has no rank or suit ---------------------------------------------

func test_card_memory_does_not_count_the_reverse_card_as_an_eso() -> void:
	var r := make_rules([["9Z"], ["8G"]], "RV")
	var mem := CardMemory.new()
	mem.update(r.state)
	assert_eq(mem.seen_by_rank[R.ESO], 0)


func test_best_suit_ignores_the_reverse_card() -> void:
	var bot := BotStrategy.new(BotStrategy.Difficulty.HARD, 1)
	assert_eq(bot._best_suit(["RV", "9Z"], []), FaraonCard.Suit.ZALUD)
	assert_eq(bot._best_suit(["RV", "HC"], ["HC"]), FaraonCard.Suit.ZALUD,
			"nothing left = default suit, not guľa via index -1")


# --- #12 stale bot timers ------------------------------------------------------------------

func test_bot_timer_from_a_previous_round_does_nothing() -> void:
	var srv := LocalGameServer.new()
	srv.bot_delay = 100.0
	add_child_autofree(srv)
	srv.start_game(1, RulesVariant.classic(), 11, BotStrategy.Difficulty.EASY)
	var stale_gen: int = srv._round_gen
	srv.start_game(1, RulesVariant.classic(), 12, BotStrategy.Difficulty.EASY)
	srv.rules.state.current_index = 1 # BOT1's turn in the new game
	await srv._bot_move("BOT1", stale_gen)
	assert_eq(srv.rules.state.turn_counter, 0, "stale timer must not move the bot")
	assert_eq(srv.rules.state.current_index, 1)
	srv.fast_forward = true
	await srv._bot_move("BOT1", srv._round_gen)
	assert_eq(srv.rules.state.turn_counter, 1, "the current timer still works")
