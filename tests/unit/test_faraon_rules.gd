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

func test_eso_skips_opponent_in_two_players() -> void:
	# A2: v 2-hráčovej hre preskočenie súpera znamená, že ten istý hráč
	# ťahá znova.
	var r := make_rules([["AZ", "KC"], ["9Z", "8G"]], "8Z")
	assert_true(play(r, "P0", ["AZ"]).ok)
	assert_eq(r.state.pending_aces, 1)
	assert_eq(play(r, "P1", ["9Z"]).error, "must_answer_with_eso",
			"zastavený hráč smie len prebiť esom alebo stáť")
	assert_eq(r.apply("P1", FaraonActions.draw()).error, "must_answer_eso_or_pass")
	assert_true(r.apply("P1", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 0, "2p: preskočenie = P0 hrá znova")
	assert_eq(r.state.pending_aces, 0)


func test_eso_counter_extends_skip_chain() -> void:
	var r := make_rules([["AZ", "KC"], ["AG", "8G"]], "8Z")
	play(r, "P0", ["AZ"])
	assert_true(play(r, "P1", ["AG"]).ok, "prebitie vlastným esom je legálne")
	assert_eq(r.state.pending_aces, 1)
	assert_eq(r.state.current_index, 0, "stop sa vracia pôvodnému útočníkovi")
	r.apply("P0", FaraonActions.pass_turn())
	assert_eq(r.state.current_index, 1, "po stopke hrá ďalší v poradí")


func test_three_esos_skip_three_players() -> void:
	var r := make_rules(
		[["AZ", "AC", "AE", "KC"], ["8G"], ["9G"], ["XG"]], "XZ")
	assert_true(play(r, "P0", ["AZ", "AC", "AE"]).ok)
	assert_eq(r.state.pending_aces, 3)
	r.apply("P1", FaraonActions.pass_turn())
	r.apply("P2", FaraonActions.pass_turn())
	r.apply("P3", FaraonActions.pass_turn())
	assert_eq(r.state.current_index, 0,
			"po troch stopkách je na rade ďalší v poradí = P0")


func test_counter_pushes_both_skips_past_the_counterer() -> void:
	# A2 akceptačný scenár: A položí eso, B prebije druhým esom →
	# preskakujú sa DVAJA hráči (C aj D... tu A a C), potom hrá ďalší.
	var r := make_rules(
		[["AZ", "AC", "AE", "KC"], ["AG", "8G"], ["9G"], ["XG"]], "XZ")
	play(r, "P0", ["AZ", "AC", "AE"])
	assert_true(play(r, "P1", ["AG"]).ok)
	assert_eq(r.state.pending_aces, 3, "B ruší vlastný stop, pridáva jeden")
	r.apply("P2", FaraonActions.pass_turn())
	r.apply("P3", FaraonActions.pass_turn())
	r.apply("P0", FaraonActions.pass_turn())
	assert_eq(r.state.current_index, 1,
			"po spotrebovaní stopov hrá ďalší v poradí = P1")


func test_single_eso_in_three_players_skips_exactly_one() -> void:
	# A2 akceptačné kritérium: A položí 1 eso → B sa preskočí a na rade je
	# C (hráč dva miesta od pokladajúceho). Žiadne voľné pokračovanie.
	var r := make_rules([["AZ", "8Z", "KC"], ["9Z", "8G"], ["XZ", "9G"]], "XZ")
	assert_true(play(r, "P0", ["AZ"]).ok)
	assert_eq(r.state.current_index, 1, "stop padá na najbližšieho hráča")
	assert_true(r.apply("P1", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 2,
			"po B-čkovej stopke je na rade C — presne 1 preskočený hráč")
	assert_true(play(r, "P2", ["XZ"]).ok)
	assert_eq(r.state.current_index, 0, "poradie pokračuje normálne")


func test_single_eso_with_finished_player_reaches_the_survivor() -> void:
	# 3p hra s dohratým hráčom: zostávajúci bot položí eso, človek stojí —
	# keďže aktívni sú už len dvaja, „ďalší v poradí" je opäť bot (to je
	# ekvivalent 2-hráčovej hry), ale hneď po jeho ťahu MUSÍ hrať človek.
	var r := make_rules([["9G"], ["AG", "XG", "7G"], ["XC", "9C", "8C"]], "9Z",
			["KZ", "KG", "KE", "XG"])
	assert_true(play(r, "P0", ["9G"]).ok) # P0 dohral
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED)
	assert_eq(r.state.current_index, 1)
	assert_true(play(r, "P1", ["AG"]).ok)
	assert_eq(r.state.current_index, 2, "stopnutý je človek (P2)")
	assert_true(r.apply("P2", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 1, "2 aktívni: ďalší v poradí je bot")
	assert_true(play(r, "P1", ["XG"]).ok)
	assert_eq(r.state.current_index, 2, "po ťahu bota má človek garantovaný ťah")


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
	assert_eq(r.state.current_index, 1,
			"B3.4 (2 hráči): obeť minula ťah vzatím kariet — hrá pokladajúci")


func test_red_seven_return_takes_only_the_base_even_after_a_chain() -> void:
	# B3.3 (B4 scenár 2): žaltová 7 → červená 7 → vracajúci sa hráč berie
	# LEN 3 karty (základ), nie 6 — reťaz pred návratom sa nepočíta a
	# návratom sa spotrebuje.
	var draw := ["8Z", "8C", "8E", "8G", "9Z", "9C", "9E", "9G", "XC"]
	var r := make_rules([["7Z"], ["7C", "7G", "8G"]], "XZ", draw)
	assert_true(play(r, "P0", ["7Z"]).ok)
	assert_eq(r.state.pending_sevens_draw, 3)
	var res := play(r, "P1", ["7C", "7G"])
	assert_true(res.ok)
	assert_eq(r.state.players[0].hand.size(), 3,
			"obeť berie len základ (3), nie súčet reťaze")
	assert_eq(r.state.pending_sevens_draw, 0, "reťaz je návratom spotrebovaná")
	# A1: obeť musí dostať DREW event, inak sa neprehrá animácia vzatia.
	var drew: Array = res.events.filter(
			func(e): return e.type == "DREW" and e.player == "P0")
	assert_eq(drew.size(), 1, "DREW event pre obeť (animácia vzatia kariet)")
	assert_eq(drew[0].count, 3)


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
	assert_eq(r.state.current_index, 2,
			"B3.4 (viac hráčov): na rade je ďalší v poradí za pokladajúcim")


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
	assert_eq(play(r, "P0", ["9Z"]).error, "interrupt_card_or_draw")


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


func test_two_esos_in_two_players_wrap_the_second_stop_to_the_attacker() -> void:
	# A2: stopky sa spotrebúvajú v poradí sedenia — pri dvoch esách v
	# 2-hráčovej hre stojí súper, potom aj útočník, a hrá súper.
	var r := make_rules([["AZ", "AC", "KC"], ["9Z", "8G"]], "XZ")
	play(r, "P0", ["AZ", "AC"])
	assert_eq(r.state.pending_aces, 2)
	assert_true(r.apply("P1", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 0, "druhá stopka padá na útočníka")
	assert_true(r.apply("P0", FaraonActions.pass_turn()).ok)
	assert_eq(r.state.current_index, 1, "po oboch stopkách hrá súper")


# --- D pravidlá -------------------------------------------------------------

func test_d3_eso_cannot_be_countered_and_resolves_instantly() -> void:
	var r := make_rules([["AZ", "8Z"], ["AG", "9Z"], ["XZ", "9G"]], "XZ")
	r.state.variant.eso_no_counter = true
	var res := play(r, "P0", ["AZ"])
	assert_true(res.ok)
	assert_eq(r.state.pending_aces, 0, "stopka sa vyhodnotí okamžite")
	assert_eq(r.state.current_index, 2,
			"P1 je preskočený bez PASS akcie, hrá P2")
	var stops: Array = res.events.filter(func(e): return e.type == "STOPPED")
	assert_eq(stops.size(), 1)
	assert_eq(stops[0].player, "P1")


func test_d4_seven_drawn_mid_penalty_can_be_played_on() -> void:
	# Ťahá 6, druhá vytiahnutá karta je sedma → pauza; vyloženie pošle
	# krok trestu ďalej a vytiahnuté karty ostávajú.
	var r := make_rules([["9C"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "7G", "XE"])
	r.state.variant.seven_interrupt = true
	r.state.pending_sevens_draw = 6
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_true(r.state.penalty_interrupt)
	assert_eq(r.state.interrupt_card, "7G")
	var res2 := play(r, "P0", ["7G"])
	assert_true(res2.ok, "vyloženie vytiahnutej sedmy musí byť povolené")
	assert_eq(r.state.pending_sevens_draw, 3,
			"ďalší hráč čelí kroku novej sedmy; zvyšok vlastného trestu padá")
	assert_eq(r.state.players[0].hand.size(), 2, "9C + XE ostávajú (7G odišla)")
	assert_eq(r.state.current_index, 1)


func test_d5_faraon_interrupt_can_be_disabled() -> void:
	var r := make_rules([["9C"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "DE", "XE"])
	r.state.variant.faraon_interrupt = false
	r.state.pending_sevens_draw = 6
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_false(r.state.penalty_interrupt,
			"s vypnutým D5 sa trest doťahá bez pauzy")
	assert_eq(r.state.players[0].hand.size(), 7)


func test_d6_penalty_step_changes_the_scale() -> void:
	var r := make_rules([["7Z", "9C"], ["7G", "8G"], ["KZ", "KE"]], "7E",
			["8Z", "8C", "8E", "8G", "9Z"])
	r.state.variant.seven_penalty_step = 2
	assert_true(play(r, "P0", ["7Z"]).ok)
	assert_eq(r.state.pending_sevens_draw, 2, "krok 2: prvá sedma = 2")
	assert_true(play(r, "P1", ["7G"]).ok)
	assert_eq(r.state.pending_sevens_draw, 4, "krok 2: dve sedmy = 4")
	assert_true(r.apply("P2", FaraonActions.draw()).ok)
	assert_eq(r.state.players[2].hand.size(), 2 + 4)


func test_d8_round_scope_expires_after_a_full_circuit() -> void:
	var r := make_rules([["9C"], ["7C", "8G", "8C", "9G"], ["KZ", "KE", "XG"]],
			"8C", ["XZ", "XC", "XE"])
	r.state.variant.red7_return_scope = "round"
	play(r, "P0", ["9C"]) # P0 dohral; vrch kôpky je 9C (červeň)
	# Umelo posuň počítadlo ťahov za okno jedného obehu stola.
	r.state.turn_counter += r.state.players.size() + 1
	var res := play(r, "P1", ["7C"])
	assert_true(res.ok, "7C na červeň je legálna ako bežná sedma")
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED,
			"po uzavretí kola už červená sedma hráča nevracia")
	assert_eq(r.state.pending_sevens_draw, 3, "7C padla ako obyčajná sedma")


func test_d10_purista_disables_specials() -> void:
	var r := make_rules(
			[["7C", "DE", "8Z"], ["8G", "9G", "KC"], ["8C", "KE", "XG"]], "8Z",
			["XZ", "XC", "XE", "9C"])
	r.state.variant.purista = true
	# Faraón nie je divoký: DE na 8Z nejde (dolník, iná farba/znak).
	assert_eq(play(r, "P0", ["DE"]).error, "card_does_not_match")
	# Sedma funguje ako trest, ale 7C nikoho nevracia.
	assert_true(play(r, "P0", ["8Z"]).ok)
	assert_true(play(r, "P1", ["8G"]).ok)
	assert_true(play(r, "P2", ["8C"]).ok) # vrch je 8C — červeň pre 7C
	assert_true(play(r, "P0", ["7C"]).ok, "7C je v Puristovi obyčajná sedma")
	assert_eq(r.state.pending_sevens_draw, 3)


func test_d12_green_king_adds_four() -> void:
	var r := make_rules([["KE", "9C"], ["8E", "8G"], ["KZ", "XG"]], "9E",
			["8Z", "8C", "XC", "XE", "9Z"])
	r.state.variant.green_king = true
	assert_true(play(r, "P0", ["KE"]).ok)
	assert_eq(r.state.pending_sevens_draw, 4, "zelený kráľ = +4")
	assert_true(r.apply("P1", FaraonActions.draw()).ok)
	assert_eq(r.state.players[1].hand.size(), 2 + 4)


func test_d13_red_ten_seals_the_seven_chain() -> void:
	var r := make_rules([["7C", "9C"], ["XC", "8G"], ["7Z", "KZ", "XG"]], "9C",
			["8Z", "8C", "8E", "XE", "9Z"])
	r.state.variant.red_ten = true
	assert_true(play(r, "P0", ["7C"]).ok, "7C tu nikoho nevracia (nikto nedohral)")
	assert_eq(r.state.pending_sevens_draw, 3)
	var res := play(r, "P1", ["XC"])
	assert_true(res.ok, "červená desiatka je obrana na červenú sedmu")
	assert_eq(r.state.pending_sevens_draw, 4, "reťaz + 1 za desiatku")
	assert_eq(play(r, "P2", ["7Z"]).error, "penalty_sealed_must_draw",
			"po desiatke už žiadna obrana")
	assert_true(r.apply("P2", FaraonActions.draw()).ok)
	assert_eq(r.state.players[2].hand.size(), 3 + 4)
	assert_false(r.state.pending_hard_penalty, "pečať sa ťahaním vybaví")


func test_d14_cannot_finish_with_a_seven() -> void:
	var r := make_rules([["7Z"], ["8G", "9G"]], "7E", ["XZ", "XC"])
	r.state.variant.finish_rule = "no_seven"
	assert_eq(play(r, "P0", ["7Z"]).error, "cannot_finish_with_seven")
	assert_true(r.apply("P0", FaraonActions.draw()).ok,
			"hráč musí namiesto toho ťahať")


func test_d14_hornik_only_finish() -> void:
	var r := make_rules([["9E"], ["8G", "9G"]], "9C", ["XZ", "XC"])
	r.state.variant.finish_rule = "hornik_only"
	assert_eq(play(r, "P0", ["9E"]).error, "must_finish_with_hornik")


func test_d2_hand_size_is_dealt() -> void:
	var r := FaraonRules.new()
	var v := RulesVariant.classic()
	v.initial_hand_size = 7
	r.start(["A", "B"], v, 4242)
	assert_eq(r.state.players[0].hand.size(), 7)
	assert_eq(r.state.players[1].hand.size(), 7)


func test_b1_start_index_sets_the_first_player() -> void:
	var r := FaraonRules.new()
	r.start(["A", "B", "C"], RulesVariant.classic(), 4242, {}, 2)
	assert_eq(r.state.current_index, 2, "štartéra určuje volajúci (B1)")


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
