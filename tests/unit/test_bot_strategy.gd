extends GutTest
## Unit tests for BotStrategy (game/bot_strategy.gd) and CardMemory. HARD has
## zero noise, so its choices are asserted deterministically; EASY is only
## required to be legal.

const Diff := BotStrategy.Difficulty


func make_state(hands: Array, top: String, draw: Array = []) -> GameState:
	var s := GameState.new()
	s.variant = RulesVariant.classic()
	for i in hands.size():
		var p := GameState.PlayerState.new()
		p.id = "P%d" % i
		p.hand.assign(hands[i])
		s.players.append(p)
	s.discard_pile.assign([top])
	s.draw_pile.assign(draw)
	return s


# --- legality across difficulties ------------------------------------------

func test_easy_always_produces_legal_moves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for round_seed in range(1, 15):
		var rules := FaraonRules.new()
		var bot := BotStrategy.new(Diff.EASY, round_seed)
		rules.start(["P0", "P1", "P2"], RulesVariant.classic(), round_seed)
		for _i in 40:
			if rules.state.phase != GameState.Phase.PLAYING:
				break
			var cur := rules.state.players[rules.state.current_index]
			var res := rules.apply(cur.id, bot.choose(rules.state, cur.id))
			assert_true(res.ok, "EASY illegal move (seed %d): %s" %
					[round_seed, res.error])


# --- forced answers ---------------------------------------------------------

func test_counters_eso_chain_with_all_esos() -> void:
	var s := make_state([["AZ", "AC", "9G"], ["8G"]], "8Z")
	s.pending_aces = 1
	var action := BotStrategy.new(Diff.HARD).choose(s, "P0")
	assert_eq(action.action, FaraonActions.PLAY_CARDS)
	assert_eq(action.cards.size(), 2, "both esos go out in the counter")


func test_passes_eso_chain_without_esos() -> void:
	var s := make_state([["9Z", "9G"], ["8G"]], "8Z")
	s.pending_aces = 1
	assert_eq(BotStrategy.new(Diff.HARD).choose(s, "P0").action, FaraonActions.PASS)


func test_answers_sevens_with_own_sevens() -> void:
	var s := make_state([["7Z", "9G"], ["8G"]], "7C")
	s.pending_sevens_draw = 3
	var action := BotStrategy.new(Diff.HARD).choose(s, "P0")
	assert_eq(action.cards, ["7Z"])


# --- strategic holding (HARD) ----------------------------------------------

func test_hard_prefers_plain_card_over_special_when_no_threat() -> void:
	# Both the eso and the nine are playable; nobody is close to winning, so
	# HARD sheds the plain nine and keeps the eso for a key moment.
	var s := make_state([["AZ", "9Z"], ["8G", "8C", "8E", "9C", "XC"]], "XZ")
	var action := BotStrategy.new(Diff.HARD).choose(s, "P0")
	assert_eq(action.cards, ["9Z"], "HARD holds the eso back")


func test_hard_spends_eso_to_block_opponent_close_to_winning() -> void:
	# The opponent is one card from going out — stopping them now is worth
	# more than the saved eso.
	var s := make_state([["AZ", "9Z"], ["8G"]], "XZ")
	var action := BotStrategy.new(Diff.HARD).choose(s, "P0")
	assert_eq(action.cards, ["AZ"], "HARD blocks the leader with the eso")


func test_hard_holds_faraon_out_of_dolnik_group_when_possible() -> void:
	# DZ opens legally, so the wild DE stays in hand for later.
	var s := make_state([["DZ", "DE"], ["8G", "8C", "8E", "9C", "XC"]], "XZ")
	var action := BotStrategy.new(Diff.HARD).choose(s, "P0")
	assert_eq(action.cards, ["DZ"], "the faraón is held back")


func test_easy_plays_specials_without_hesitation() -> void:
	# EASY has no save weight: with only the eso playable it just plays it.
	var s := make_state([["AZ", "9C"], ["8G", "8C", "8E"]], "XZ")
	var action := BotStrategy.new(Diff.EASY, 7).choose(s, "P0")
	assert_eq(action.action, FaraonActions.PLAY_CARDS)


# --- sole-survivor rescue ----------------------------------------------------

func test_sole_survivor_plays_red_seven_rescue() -> void:
	var s := make_state([["7C", "9Z"], []], "8Z", ["KZ", "KG", "KE"])
	s.players[1].status = GameState.PlayerStatus.FINISHED
	s.players[1].finished_at = 0
	s.turn_counter = 1
	var action := BotStrategy.new(Diff.EASY, 3).choose(s, "P0")
	assert_true(action.cards.has("7C"), "the rescue must be taken at any difficulty")


# --- card memory -------------------------------------------------------------

func test_card_memory_counts_discard_and_forgets_after_reflip() -> void:
	var s := make_state([["9Z"], ["8G"]], "AZ")
	s.discard_pile.assign(["AZ", "AC", "7G"])
	var mem := CardMemory.new()
	mem.update(s)
	assert_eq(mem.seen_by_rank[FaraonCard.Rank.ESO], 2)
	assert_eq(mem.unseen_of_rank(FaraonCard.Rank.ESO, ["AG"]), 1,
			"2 seen + 1 mine -> 1 possibly with opponents")
	# Reflip: the discard collapses to just the top card; the memory must
	# forget the recycled cards because they are back in circulation.
	var top: Array[String] = ["7G"]
	s.discard_pile = top
	mem.update(s)
	assert_eq(mem.seen_by_rank[FaraonCard.Rank.ESO], 0)


func test_hard_choice_is_deterministic() -> void:
	for _i in 5:
		var s := make_state([["AZ", "9Z", "KC"], ["8G", "9C", "XC"]], "XZ")
		var action := BotStrategy.new(Diff.HARD).choose(s, "P0")
		assert_eq(action.cards, ["9Z"], "zero-noise HARD must repeat its choice")
