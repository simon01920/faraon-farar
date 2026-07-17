extends GutTest
## Unit tests for the pure rules engine (game/faraon_rules.gd).
## Card ids: rank char (7 8 9 X D H K A) + suit char (Z=žaluď C=červeň
## E=zeleň G=guľa). "DE" = zelený dolník = faraón, "7C" = červená sedma.

const S := FaraonCard.Suit


## Builds an engine around a hand-crafted state: hands[i] -> player "P<i>",
## `top` is the visible discard top, `draw` the draw pile (last = top).
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


func play(r: FaraonRules, pid: String, cards: Array, declared := -1) -> Dictionary:
	return r.apply(pid, FaraonActions.play(cards, declared))


# --- deck & setup ---------------------------------------------------------

func test_deck_has_32_unique_cards() -> void:
	var deck := FaraonDeck.build()
	assert_eq(deck.size(), 32)
	var unique := {}
	for c in deck:
		unique[c] = true
	assert_eq(unique.size(), 32)


func test_start_deals_hands_and_flips_start_card() -> void:
	var r := FaraonRules.new()
	r.start(["A", "B", "C"], RulesVariant.classic(), 12345)
	for p in r.state.players:
		assert_eq(p.hand.size(), 5)
	assert_eq(r.state.discard_pile.size(), 1)
	assert_eq(r.state.draw_pile.size(), 32 - 3 * 5 - 1)


func test_start_hornik_flip_event_carries_the_deciding_card() -> void:
	var r := make_rules([["9Z"], ["8G"]], "HZ", ["9C", "HG", "8E"])
	# Bottom (index 0) is 9C — first non-horník from the bottom decides.
	var events: Array = []
	r._apply_start_card_effects("HZ", events)
	var flips: Array = events.filter(func(e): return e.type == "START_DECK_FLIP")
	assert_eq(flips.size(), 1)
	assert_eq(flips[0].bottom, "9C")
	assert_eq(r.state.declared_suit, FaraonCard.suit_of("9C"))


func test_start_hornik_skips_bottom_hornik() -> void:
	var r := make_rules([["9Z"], ["8G"]], "HZ", ["HG", "9E", "8C"])
	var events: Array = []
	r._apply_start_card_effects("HZ", events)
	var flips: Array = events.filter(func(e): return e.type == "START_DECK_FLIP")
	assert_eq(flips[0].bottom, "9E", "a bottom horník never counts")
	assert_eq(r.state.declared_suit, S.ZELEN)


func test_start_eso_flip_event_even_when_invalid() -> void:
	# The deck is physically checked either way; the event must fire so the
	# client can show the flip, but the stop only applies on a rank match.
	var r := make_rules([["9Z"], ["8G"]], "AZ", ["9C", "8E"])
	var events: Array = []
	r._apply_start_card_effects("AZ", events)
	assert_eq(events.filter(func(e): return e.type == "START_DECK_FLIP").size(), 1)
	assert_eq(r.state.pending_aces, 0, "9C at the bottom does not validate the eso")


# --- basic plays ----------------------------------------------------------

func test_play_matching_suit() -> void:
	var r := make_rules([["9Z", "KC"], ["8G"]], "8Z")
	var res := play(r, "P0", ["9Z"])
	assert_true(res.ok, "suit match must be legal")
	assert_eq(r.state.top_card(), "9Z")
	assert_eq(r.state.current_index, 1)


func test_play_matching_rank() -> void:
	var r := make_rules([["8C", "KC"], ["8G"]], "8Z")
	assert_true(play(r, "P0", ["8C"]).ok, "rank match must be legal")


func test_illegal_card_rejected_and_state_untouched() -> void:
	var r := make_rules([["9C", "KC"], ["8G"]], "8Z")
	var res := play(r, "P0", ["9C"])
	assert_false(res.ok)
	assert_eq(res.error, "card_does_not_match")
	assert_eq(r.state.players[0].hand.size(), 2)
	assert_eq(r.state.current_index, 0)


func test_cannot_play_out_of_turn() -> void:
	var r := make_rules([["9Z"], ["8G", "8C"]], "8Z")
	assert_eq(play(r, "P1", ["8G"]).error, "not_your_turn")


func test_multiple_cards_must_share_rank() -> void:
	var r := make_rules([["9Z", "XZ", "9G"], ["8G"]], "8Z")
	assert_eq(play(r, "P0", ["9Z", "XZ"]).error, "cards_not_same_rank")
	assert_true(play(r, "P0", ["9Z", "9G"]).ok)
	assert_eq(r.state.top_card(), "9G", "last played card becomes the top")


func test_draw_takes_one_card_and_passes_turn() -> void:
	var r := make_rules([["9C"], ["8G"]], "8Z", ["KZ", "KG"])
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_eq(r.state.players[0].hand.size(), 2)
	assert_eq(r.state.current_index, 1)


# --- horník ---------------------------------------------------------------

func test_hornik_plays_on_anything_and_changes_suit() -> void:
	var r := make_rules([["HZ", "KC"], ["9C", "9E"]], "8G")
	var res := play(r, "P0", ["HZ"], S.CERVEN)
	assert_true(res.ok, "horník must be playable on a non-matching top")
	assert_eq(r.state.declared_suit, S.CERVEN)
	assert_true(play(r, "P1", ["9C"]).ok, "declared suit must be accepted")


func test_hornik_requires_declared_suit() -> void:
	var r := make_rules([["HZ", "KC"], ["9C"]], "8G")
	assert_eq(play(r, "P0", ["HZ"]).error, "declared_suit_required")


func test_declared_suit_blocks_other_suits() -> void:
	var r := make_rules([["HZ", "KC"], ["9E", "9C"]], "8G")
	play(r, "P0", ["HZ"], S.CERVEN)
	assert_eq(play(r, "P1", ["9E"]).error, "card_does_not_match")


# --- faraón (zelený dolník) ----------------------------------------------

func test_faraon_is_fully_neutral() -> void:
	# PDF p.4: faraón lands on anything, anything lands on faraón — no suit
	# declaration involved.
	var r := make_rules([["DE", "KC"], ["9Z", "KZ"]], "8G")
	var res := play(r, "P0", ["DE"])
	assert_true(res.ok, "faraón must land on any top card")
	assert_eq(r.state.declared_suit, -1, "faraón never declares a suit")
	assert_true(play(r, "P1", ["9Z"]).ok, "any card must land on the faraón")


func test_faraon_clears_hornik_declaration() -> void:
	var r := make_rules([["HZ", "KC"], ["DE", "8G"], ["XG", "9E"]], "8G")
	play(r, "P0", ["HZ"], S.CERVEN)
	assert_true(play(r, "P1", ["DE"]).ok, "faraón must land even on a declared suit")
	assert_eq(r.state.declared_suit, -1)
	assert_true(play(r, "P2", ["XG"]).ok, "anything goes after the faraón")


func test_faraon_kills_pending_sevens() -> void:
	var r := make_rules([["7Z", "KC"], ["DE", "8G"]], "8Z")
	play(r, "P0", ["7Z"])
	assert_eq(r.state.pending_sevens_draw, 3)
	var res := play(r, "P1", ["DE"])
	assert_true(res.ok, "faraón must cancel the seven chain")
	assert_eq(r.state.pending_sevens_draw, 0)


func test_faraon_cannot_answer_eso() -> void:
	var r := make_rules([["AZ", "KC"], ["DE", "8G"]], "8Z")
	play(r, "P0", ["AZ"])
	assert_eq(play(r, "P1", ["DE"]).error, "must_answer_with_eso")


# --- eso chains -----------------------------------------------------------

func test_eso_stops_opponent_then_owner_continues() -> void:
	var r := make_rules([["AZ", "KC"], ["9Z", "8G"]], "8Z")
	assert_true(play(r, "P0", ["AZ"]).ok)
	assert_eq(r.state.pending_aces, 1)
	assert_eq(play(r, "P1", ["9Z"]).error, "must_answer_with_eso",
			"a stopped player may only answer with eso or pass")
	assert_eq(r.apply("P1", FaraonActions.draw()).error, "must_answer_eso_or_pass")
	assert_true(r.apply("P1", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 0, "chain owner gets the free continuation")
	assert_eq(r.state.pending_aces, 0)


func test_eso_counter_transfers_chain_ownership() -> void:
	var r := make_rules([["AZ", "KC"], ["AG", "8G"]], "8Z")
	play(r, "P0", ["AZ"])
	assert_true(play(r, "P1", ["AG"]).ok, "countering with own eso is legal")
	assert_eq(r.state.pending_aces, 1)
	assert_eq(r.state.current_index, 0, "original attacker must now answer")
	r.apply("P0", FaraonActions.pass_turn())
	assert_eq(r.state.current_index, 1, "counterer continues after the pass")


func test_three_esos_stop_three_players() -> void:
	var r := make_rules(
		[["AZ", "AC", "AE", "KC"], ["8G"], ["9G"], ["XG"]], "XZ")
	assert_true(play(r, "P0", ["AZ", "AC", "AE"]).ok)
	assert_eq(r.state.pending_aces, 3)
	r.apply("P1", FaraonActions.pass_turn())
	r.apply("P2", FaraonActions.pass_turn())
	r.apply("P3", FaraonActions.pass_turn())
	assert_eq(r.state.current_index, 0, "after all stops the attacker continues")


func test_counter_in_multiplayer_shifts_continuation_by_one() -> void:
	# PDF p.6: A plays three esos; if B counters, B ends up continuing.
	var r := make_rules(
		[["AZ", "AC", "AE", "KC"], ["AG", "8G"], ["9G"], ["XG"]], "XZ")
	play(r, "P0", ["AZ", "AC", "AE"])
	assert_true(play(r, "P1", ["AG"]).ok)
	assert_eq(r.state.pending_aces, 3, "B clears own stop, adds one for A")
	r.apply("P2", FaraonActions.pass_turn())
	r.apply("P3", FaraonActions.pass_turn())
	r.apply("P0", FaraonActions.pass_turn())
	assert_eq(r.state.current_index, 1, "B owns the chain and continues")


func test_single_eso_in_three_players_denies_exactly_one_turn() -> void:
	# Investigation of "I could not get a turn after one ace" reports:
	# P0 plays ONE eso -> P1 (and only P1) is stopped; P0 gets the free
	# continuation; afterwards the order resumes P1 -> P2. P2 is never
	# skipped, only delayed by P0's extra move.
	var r := make_rules([["AZ", "8Z", "KC"], ["9Z", "8G"], ["XZ", "9G"]], "XZ")
	assert_true(play(r, "P0", ["AZ"]).ok)
	assert_eq(r.state.current_index, 1, "the stop lands on the next player")
	assert_true(r.apply("P1", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 0, "owner's free continuation")
	assert_true(play(r, "P0", ["8Z"]).ok)
	assert_eq(r.state.current_index, 1,
			"after the continuation the order resumes at P1 — nobody is skipped")
	assert_true(play(r, "P1", ["8G"]).ok)
	assert_eq(r.state.current_index, 2, "P2 gets the next regular turn")


func test_single_eso_with_finished_player_still_reaches_the_survivor() -> void:
	# The screenshot scenario: 3p game, one player already finished. The
	# remaining bot plays ONE eso: the human stands, the bot double-moves
	# (continuation), then the human MUST be on turn.
	var r := make_rules([["9G"], ["AG", "XG", "7G"], ["XC", "9C", "8C"]], "9Z",
			["KZ", "KG", "KE", "XG"])
	assert_true(play(r, "P0", ["9G"]).ok) # P0 finishes and is out of the loop
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED)
	assert_eq(r.state.current_index, 1)
	assert_true(play(r, "P1", ["AG"]).ok)
	assert_eq(r.state.current_index, 2, "P2 (the human) is the stopped one")
	assert_true(r.apply("P2", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 1, "owner continuation for the bot")
	assert_true(play(r, "P1", ["XG"]).ok)
	assert_eq(r.state.current_index, 2,
			"after the double move the human is guaranteed the turn")


# --- sedmy ----------------------------------------------------------------

func test_sevens_accumulate_and_victim_draws_all() -> void:
	# PDF p.6: A plays two sevens, B answers with one, C draws nine.
	var draw := ["8Z", "8C", "8E", "8G", "9Z", "9C", "9E", "9G", "XC", "XE"]
	var r := make_rules(
		[["7Z", "7G", "KC"], ["7E", "8G"], ["KZ"], ["XG"]], "XZ", draw)
	assert_true(play(r, "P0", ["7Z", "7G"]).ok)
	assert_eq(r.state.pending_sevens_draw, 6)
	assert_true(play(r, "P1", ["7E"]).ok)
	assert_eq(r.state.pending_sevens_draw, 9)
	var res := r.apply("P2", FaraonActions.draw())
	assert_true(res.ok)
	assert_eq(r.state.players[2].hand.size(), 1 + 9)
	assert_eq(r.state.pending_sevens_draw, 0)
	assert_eq(r.state.current_index, 3, "play continues after the victim")


func test_seven_defense_ignores_suit() -> void:
	var r := make_rules([["7Z", "KC"], ["7G", "8G"]], "8Z", ["9C", "9E", "9G"])
	play(r, "P0", ["7Z"])
	assert_true(play(r, "P1", ["7G"]).ok, "any seven answers a seven")


# --- červená sedma: return to game ---------------------------------------

func test_red_seven_returns_finished_player() -> void:
	var r := make_rules([["9Z"], ["7C", "8G"]], "8Z", ["KZ", "KG", "KE", "XC"])
	assert_true(play(r, "P0", ["9Z"]).ok)
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED)
	assert_eq(r.state.phase, GameState.Phase.PLAYING,
			"game must stay open while a red-seven rescue exists")
	var res := play(r, "P1", ["7C"])
	assert_true(res.ok, "return must ignore suit/rank matching")
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.ACTIVE)
	assert_eq(r.state.players[0].hand.size(), 3, "returned player draws three")
	assert_eq(r.state.current_index, 1, "returner is on turn after the victim")


func test_red_seven_return_includes_victims_finishing_seven() -> void:
	# PDF p.5: victim finished with a seven; returner plays 7C + one more
	# seven -> victim draws nine in total.
	var draw := ["8Z", "8C", "8E", "8G", "9Z", "9C", "9E", "9G", "XC"]
	var r := make_rules([["7Z"], ["7C", "7G", "8G"]], "XZ", draw)
	assert_true(play(r, "P0", ["7Z"]).ok)
	assert_eq(r.state.pending_sevens_draw, 3)
	var res := play(r, "P1", ["7C", "7G"])
	assert_true(res.ok)
	assert_eq(r.state.players[0].hand.size(), 9)


func test_red_seven_returns_automatically_in_multiplayer() -> void:
	# Regression (fix prompt #1): a player finished during the round and the
	# red seven was played by someone else in that same round — the finished
	# player must come back; the next active player must NOT be forced to
	# draw three as if it were a plain seven.
	var r := make_rules([["9Z"], ["7C", "8G"], ["KZ", "KE"]], "8Z",
			["XZ", "XC", "XE", "XG"])
	assert_true(play(r, "P0", ["9Z"]).ok)
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED)
	var res := play(r, "P1", ["7C"])
	assert_true(res.ok)
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.ACTIVE,
			"the eliminated player must be returned")
	assert_eq(r.state.players[0].hand.size(), 3, "returned player draws three")
	assert_eq(r.state.pending_sevens_draw, 0,
			"no seven penalty may be left for the next player")
	assert_eq(r.state.players[2].hand.size(), 2, "P2 must not draw anything")


func test_red_seven_returns_latest_eliminated_of_several() -> void:
	# Rule change (fix prompt #2): with several players eliminated in the same
	# round the red seven deterministically returns the most recent one.
	var r := make_rules([["9Z"], ["9C"], ["7C", "8G"], ["KZ", "KE"]], "8Z",
			["XZ", "XC", "XE", "XG"])
	assert_true(play(r, "P0", ["9Z"]).ok)
	assert_true(play(r, "P1", ["9C"]).ok)
	assert_true(play(r, "P2", ["7C"]).ok)
	assert_eq(r.state.players[1].status, GameState.PlayerStatus.ACTIVE,
			"the latest eliminated player (P1) must be the one returned")
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED,
			"the earlier eliminated player (P0) stays out")
	assert_eq(r.state.players[1].hand.size(), 3)


func test_plain_seven_does_not_return_anyone() -> void:
	# Only the red seven returns; an ordinary seven keeps its penalty role
	# even while someone is returnable.
	var r := make_rules([["9Z"], ["7Z", "7C", "8G"]], "8Z", ["KZ", "KG", "KE"])
	play(r, "P0", ["9Z"])
	assert_true(play(r, "P1", ["7Z"]).ok)
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED,
			"a plain seven must not return the finished player")
	assert_eq(r.state.pending_sevens_draw, 3)


func test_red_seven_without_returnable_target_acts_as_plain_seven() -> void:
	# Fix prompt #1: only when NO returnable player exists may the red seven
	# fall back to standard seven behaviour.
	var r := make_rules([["7C", "8G"], ["KZ", "KE"]], "8C", ["XZ", "XC", "XE"])
	assert_true(play(r, "P0", ["7C"]).ok)
	assert_eq(r.state.pending_sevens_draw, 3,
			"with nobody to return, 7C is an ordinary seven")


# --- faraón interrupt during penalty drawing --------------------------------

func test_penalty_draw_pauses_when_faraon_is_drawn() -> void:
	# Draw order = pop_back: XE first, DE second -> pause after 2 of 6.
	var r := make_rules([["9C"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "DE", "XE"])
	r.state.pending_sevens_draw = 6
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_true(r.state.penalty_interrupt, "drawing the faraón pauses the penalty")
	assert_eq(r.state.pending_sevens_draw, 4, "four penalty cards remain")
	assert_eq(r.state.current_index, 0, "the player keeps the turn to decide")
	assert_true(r.state.players[0].hand.has("DE"))
	var offers: Array = res.events.filter(
			func(e): return e.type == "PENALTY_INTERRUPT")
	assert_eq(offers.size(), 1)
	assert_eq(offers[0].remaining, 4)


func test_interrupt_faraon_play_cancels_remaining_penalty() -> void:
	var r := make_rules([["9C"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "DE", "XE"])
	r.state.pending_sevens_draw = 6
	r.apply("P0", FaraonActions.draw())
	var res := play(r, "P0", ["DE"])
	assert_true(res.ok, "playing the drawn faraón must be allowed")
	assert_eq(r.state.pending_sevens_draw, 0, "the rest of the penalty is wiped")
	assert_false(r.state.penalty_interrupt)
	assert_eq(r.state.top_card(), "DE")
	assert_eq(r.state.players[0].hand.size(), 2, "9C + XE stay, DE was played")
	assert_eq(r.state.current_index, 1, "turn passes on")


func test_interrupt_resume_draw_finishes_the_penalty() -> void:
	# Optional rule: the player may decline and keep drawing instead.
	var r := make_rules([["9C"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "DE", "XE"])
	r.state.pending_sevens_draw = 6
	r.apply("P0", FaraonActions.draw())
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_eq(r.state.pending_sevens_draw, 0)
	assert_false(r.state.penalty_interrupt)
	assert_eq(r.state.players[0].hand.size(), 7, "1 + all 6 penalty cards")
	assert_eq(r.state.current_index, 1)


func test_interrupt_rejects_other_plays() -> void:
	var r := make_rules([["9Z"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "DE", "XE"])
	r.state.pending_sevens_draw = 6
	r.apply("P0", FaraonActions.draw())
	assert_eq(play(r, "P0", ["9Z"]).error, "interrupt_faraon_or_draw")


func test_faraon_as_last_penalty_card_offers_nothing() -> void:
	# Nothing left to cancel -> no pause, penalty just completes.
	var r := make_rules([["9C"], ["8G"]], "8Z", ["KZ", "KG", "DE", "XC", "XE"])
	r.state.pending_sevens_draw = 3
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_false(r.state.penalty_interrupt,
			"the faraón drawn as the final card pauses nothing")
	assert_eq(r.state.current_index, 1)


# --- spálená --------------------------------------------------------------

func test_spalena_grants_extra_turn() -> void:
	# First card must match the top (KC on XC), last card steers the suit
	# for the follow-up move (KZ -> 9Z), PDF p.5.
	var r := make_rules([["KZ", "KC", "KE", "KG", "9Z"], ["8G"]], "XC",
			["XZ", "XE"])
	var res := play(r, "P0", ["KC", "KG", "KE", "KZ"])
	assert_true(res.ok)
	assert_eq(r.state.current_index, 0, "four of a kind = guaranteed double move")
	assert_true(play(r, "P0", ["9Z"]).ok, "ordered so the last king allows continuing")


func test_spalena_first_card_must_still_match() -> void:
	var r := make_rules([["KZ", "KC", "KE", "KG", "9Z"], ["8G"]], "XC")
	var res := play(r, "P0", ["KZ", "KC", "KE", "KG"])
	assert_false(res.ok, "spálená must still be admitted by the top card")


# --- house-rule toggles ---------------------------------------------------

func test_toggle_faraon_blocks_eso() -> void:
	var r := make_rules([["AZ", "KC"], ["DE", "8G"]], "8Z")
	r.state.variant.faraon_blocks_eso = true
	play(r, "P0", ["AZ"])
	var res := play(r, "P1", ["DE"])
	assert_true(res.ok, "with the toggle ON the faraón must cancel the chain")
	assert_eq(r.state.pending_aces, 0)
	assert_eq(r.state.current_index, 0, "play continues normally after the block")


func test_toggle_hornik_strict() -> void:
	var r := make_rules([["HZ", "HG", "KC"], ["9C", "8G"]], "8G")
	r.state.variant.hornik_strict = true
	assert_eq(play(r, "P0", ["HZ"], S.CERVEN).error, "card_does_not_match",
			"strict horník must match suit or rank")
	var res := play(r, "P0", ["HG"], S.CERVEN)
	assert_true(res.ok, "matching horník is fine and still declares")
	assert_eq(r.state.declared_suit, S.CERVEN)


func test_toggle_eso_round_robin() -> void:
	# 2 aces head-to-head with the toggle: opponent stands, I stand, opponent
	# plays — no free continuation for the attacker.
	var r := make_rules([["AZ", "AC", "KC"], ["9Z", "8G"]], "XZ")
	r.state.variant.eso_round_robin = true
	play(r, "P0", ["AZ", "AC"])
	assert_eq(r.state.pending_aces, 2)
	assert_true(r.apply("P1", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 0, "second stop lands on the attacker")
	assert_true(r.apply("P0", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 1, "opponent plays after both stood")


func test_toggle_spalena_multiply_banks_extra_moves() -> void:
	var hand := ["KC", "KG", "KE", "KZ", "9Z", "9G", "9E", "9C", "8C", "8G"]
	var r := make_rules([hand, ["7G", "7E"]], "XC")
	r.state.variant.spalena_multiply = true
	assert_true(play(r, "P0", ["KC", "KG", "KE", "KZ"]).ok)
	assert_eq(r.state.current_index, 0, "first spálená: extra move")
	assert_true(play(r, "P0", ["9Z", "9G", "9E", "9C"]).ok)
	assert_eq(r.state.current_index, 0, "second spálená in a row")
	assert_true(play(r, "P0", ["8C"]).ok)
	assert_eq(r.state.current_index, 0, "multiplied: still my move")
	assert_true(play(r, "P0", ["8G"]).ok)
	assert_eq(r.state.current_index, 1, "banked moves used up, turn passes")


func test_spalena_without_multiply_gives_single_extra_move() -> void:
	var hand := ["KC", "KG", "KE", "KZ", "9Z", "9G", "9E", "9C", "8C", "8G"]
	var r := make_rules([hand, ["7G", "7E"]], "XC")
	assert_true(play(r, "P0", ["KC", "KG", "KE", "KZ"]).ok)
	assert_true(play(r, "P0", ["9Z", "9G", "9E", "9C"]).ok)
	assert_eq(r.state.current_index, 0, "second spálená grants its own extra move")
	assert_true(play(r, "P0", ["8C"]).ok)
	assert_eq(r.state.current_index, 1, "default: exactly one extra move")


# --- game end -------------------------------------------------------------

func test_last_player_with_cards_loses() -> void:
	var r := make_rules([["9Z"], ["8G", "8C"]], "8Z")
	var res := play(r, "P0", ["9Z"])
	assert_true(res.ok)
	assert_eq(r.state.phase, GameState.Phase.GAME_OVER,
			"no rescue available -> game over immediately")
	assert_eq(r.state.loser_index, 1)


func test_finishing_with_eso_wins_instantly_in_two_player() -> void:
	var r := make_rules([["AZ"], ["7C", "8G"]], "8Z")
	var res := play(r, "P0", ["AZ"])
	assert_true(res.ok)
	assert_eq(r.state.phase, GameState.Phase.GAME_OVER,
			"eso finish cannot be answered in a 2-player game")
	assert_eq(r.state.loser_index, 1)


func test_draw_pile_reflip_when_exhausted() -> void:
	var r := make_rules([["9C"], ["8G"]], "8Z")
	r.state.discard_pile.assign(["KZ", "KG", "8Z"]) # 8Z stays as top
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_eq(r.state.players[0].hand.size(), 2)
	assert_eq(r.state.discard_pile, ["8Z"] as Array[String],
			"top card must survive the reflip")
	assert_eq(r.state.draw_pile.size(), 1, "one flipped card left after drawing one")
	var reflips: Array = res.events.filter(
			func(e): return e.type == "PILE_REFLIPPED")
	assert_eq(reflips.size(), 1, "the recycle must announce itself for the UI")
	assert_eq(reflips[0].top, "8Z")
	assert_eq(reflips[0].remaining, 2, "both recycled cards before the draw")
	assert_eq(res.events.back().type, "DREW", "reflip precedes the draw event")


# --- finish positions -----------------------------------------------------

func test_finish_positions_recorded_in_order() -> void:
	# 3 players: first to finish = 1st place, second = 2nd, the one left
	# holding cards = last place. Only 1st counts as the win.
	var r := make_rules([["9Z"], ["9C"], ["8G", "8C"]], "8Z")
	assert_true(play(r, "P0", ["9Z"]).ok)
	assert_true(play(r, "P1", ["9C"]).ok)
	assert_eq(r.state.players[0].finish_position, 1)
	assert_eq(r.state.players[1].finish_position, 2)
	assert_eq(r.state.phase, GameState.Phase.GAME_OVER)
	assert_eq(r.state.players[2].finish_position, 3, "loser takes the last place")


func test_red_seven_return_clears_finish_position() -> void:
	var r := make_rules([["9Z"], ["7C", "8G"]], "8Z", ["KZ", "KG", "KE", "XC"])
	play(r, "P0", ["9Z"])
	assert_eq(r.state.players[0].finish_position, 1)
	play(r, "P1", ["7C"])
	assert_eq(r.state.players[0].finish_position, -1,
			"a returned player has no placement until finishing again")


func test_eso_auto_win_assigns_both_positions() -> void:
	var r := make_rules([["AZ"], ["7C", "8G"]], "8Z")
	play(r, "P0", ["AZ"])
	assert_eq(r.state.players[0].finish_position, 1)
	assert_eq(r.state.players[1].finish_position, 2)


# --- state snapshots ------------------------------------------------------

func test_view_hides_other_hands_and_draw_pile() -> void:
	var r := make_rules([["9Z", "KC"], ["8G"]], "8Z", ["XC", "XE"])
	var view := r.state.view_for("P0")
	assert_eq(view["draw_pile_count"], 2)
	assert_false(view.has("draw_pile"))
	assert_eq(view["players"][0]["hand"], ["9Z", "KC"])
	assert_false(view["players"][1].has("hand"))
	assert_eq(view["players"][1]["hand_count"], 1)


func test_state_roundtrip_serialization() -> void:
	var r := make_rules([["9Z", "KC"], ["8G"]], "8Z", ["XC"])
	play(r, "P0", ["9Z"])
	var restored := GameState.from_dict(r.state.to_dict())
	assert_eq(restored.to_dict(), r.state.to_dict())
