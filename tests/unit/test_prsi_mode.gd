extends GutTest
## Herný mód „Prší" (schválené: 4 karty, bez návratu červenou sedmou).
## Preset len prestaví hodnoty RulesVariant — engine ostáva jeden jediný.


func make_rules(hands: Array, top: String, draw: Array = [],
		preset: String = "prsi") -> FaraonRules:
	var r := FaraonRules.new()
	var s := GameState.new()
	s.variant = RulesVariant.from_preset(preset)
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


# --- preset ----------------------------------------------------------------

func test_prsi_preset_matches_the_approved_decisions() -> void:
	var v := RulesVariant.prsi()
	assert_eq(v.initial_hand_size, 4, "Q1: rozdávajú sa 4 karty")
	assert_eq(v.seven_penalty_step, 2, "P1: sedma = ber 2")
	assert_eq(v.seven_penalty_cap, 8, "P2: reťaz stropuje na 8")
	assert_false(v.faraon_is_wild(), "P3: faraón v Prší neexistuje")
	assert_false(v.allows_spalena(), "P4: spálená sa nehrá")
	assert_false(v.multi_card_play, "P6: kladie sa po jednej karte")
	assert_false(v.allows_red7_return(), "Q2: bez návratu červenou sedmou")
	assert_true(v.changer_blocked_on_specials, "P5: svršek nejde na eso/sedmu")


func test_faraon_preset_is_unchanged_by_the_new_switches() -> void:
	var v := RulesVariant.from_preset("faraon")
	assert_eq(v.initial_hand_size, 5)
	assert_eq(v.seven_penalty_step, 3)
	assert_eq(v.seven_penalty_cap, 0, "Faraón je bez stropu")
	assert_true(v.faraon_is_wild())
	assert_true(v.allows_spalena())
	assert_true(v.multi_card_play)
	assert_true(v.allows_red7_return())
	assert_true(RulesVariant.classic().matches_preset("faraon"))
	assert_true(RulesVariant.prsi().matches_preset("prsi"))


func test_prsi_deals_four_cards() -> void:
	var r := FaraonRules.new()
	r.start(["A", "B", "C"], RulesVariant.prsi(), 4242)
	for p in r.state.players:
		assert_eq(p.hand.size(), 4)


# --- trest za sedmu: krok 2 so stropom 8 -----------------------------------

func test_seven_penalty_is_two_and_caps_at_eight() -> void:
	var draw: Array = []
	for c in ["8Z", "8C", "8E", "8G", "9Z", "9C", "9E", "9G", "XC", "XE"]:
		draw.append(c)
	# Vrch je žaluďová desiatka, takže žaluďová sedma je legálny otvárač.
	var r := make_rules([["7Z", "KZ"], ["7C", "KC"], ["7E", "KE"], ["7G", "KG"]],
			"XZ", draw)
	assert_true(play(r, "P0", ["7Z"]).ok)
	assert_eq(r.state.pending_sevens_draw, 2)
	assert_true(play(r, "P1", ["7C"]).ok)
	assert_eq(r.state.pending_sevens_draw, 4)
	assert_true(play(r, "P2", ["7E"]).ok)
	assert_eq(r.state.pending_sevens_draw, 6)
	assert_true(play(r, "P3", ["7G"]).ok)
	assert_eq(r.state.pending_sevens_draw, 8, "štvrtá sedma dorazí na strop 8")
	assert_true(r.apply("P0", FaraonActions.draw()).ok)
	assert_eq(r.state.players[0].hand.size(), 1 + 8, "strop platí aj pri ťahaní")


func test_faraon_mode_penalty_stays_uncapped() -> void:
	var draw: Array = []
	for c in ["8Z", "8C", "8E", "8G", "9Z", "9C", "9E", "9G", "XC", "XE", "XG"]:
		draw.append(c)
	var r := make_rules([["7Z", "KZ"], ["7C", "7E", "7G", "KC"]], "XZ", draw,
			"faraon")
	assert_true(play(r, "P0", ["7Z"]).ok)
	assert_true(play(r, "P1", ["7C", "7E", "7G"]).ok)
	assert_eq(r.state.pending_sevens_draw, 12, "Faraón strop nemá")


# --- P3: zelený spodok je v Prší bežná karta -------------------------------

func test_green_unter_is_an_ordinary_card_in_prsi() -> void:
	var r := make_rules([["DE", "9G"], ["KZ", "KE"]], "8Z", ["XZ", "XC", "XE"])
	var res := play(r, "P0", ["DE"])
	assert_false(res.ok, "zelený spodok nesmie padnúť na osmičku inej farby")
	assert_eq(res.error, "card_does_not_match")


func test_green_unter_does_not_cancel_the_penalty_in_prsi() -> void:
	var r := make_rules([["7Z", "9G"], ["DE", "KE"]], "XZ",
			["8Z", "8C", "8E", "9Z", "9C"])
	assert_true(play(r, "P0", ["7Z"]).ok)
	var res := play(r, "P1", ["DE"])
	assert_false(res.ok, "bez faraóna sa trest spodkom nezruší")
	assert_eq(res.error, "must_answer_with_sedma_or_faraon")


# --- P5: svršek nejde na eso ani na sedmu ----------------------------------

func test_changer_cannot_land_on_ace_or_seven_in_prsi() -> void:
	var r := make_rules([["HZ", "9G"], ["KZ", "KE"]], "AC",
			["XZ", "XC", "XE", "8Z"])
	var res := play(r, "P0", ["HZ"], FaraonCard.Suit.ZALUD)
	assert_false(res.ok, "svršek nepadne na eso")
	assert_eq(res.error, "card_does_not_match")
	r.state.discard_pile.assign(["7C"])
	r.state.pending_sevens_draw = 0 # sedma už bola vyriešená, ostala na vrchu
	assert_false(play(r, "P0", ["HZ"], FaraonCard.Suit.ZALUD).ok,
			"svršek nepadne ani na sedmu")
	r.state.discard_pile.assign(["9C"])
	assert_true(play(r, "P0", ["HZ"], FaraonCard.Suit.ZALUD).ok,
			"na bežnú kartu svršek ide a mení farbu")


func test_changer_lands_on_specials_in_faraon_mode() -> void:
	var r := make_rules([["HZ", "9G"], ["KZ", "KE"]], "9C",
			["XZ", "XC", "XE"], "faraon")
	r.state.discard_pile.assign(["AC"])
	r.state.pending_aces = 0 # stopka je vyriešená, eso ostalo na vrchu
	assert_true(play(r, "P0", ["HZ"], FaraonCard.Suit.ZALUD).ok,
			"vo Faraóne horník padne aj na eso")


# --- P6: jedna karta na ťah ------------------------------------------------

func test_only_one_card_per_move_in_prsi() -> void:
	var r := make_rules([["9Z", "9G", "KZ"], ["KE", "KC"]], "8Z",
			["XZ", "XC", "XE"])
	var res := play(r, "P0", ["9Z", "9G"])
	assert_false(res.ok)
	assert_eq(res.error, "single_card_only")
	assert_true(play(r, "P0", ["9Z"]).ok, "po jednej to ide")


func test_four_of_a_kind_gives_no_extra_turn_in_prsi() -> void:
	# Aj keby sa viackartový ťah zapol ručne, spálená v Prší neexistuje.
	var r := make_rules([["9Z", "9G", "9C", "9E", "KZ"], ["KE", "KC"]], "8Z",
			["XZ", "XC", "XE"])
	r.state.variant.multi_card_play = true
	assert_true(play(r, "P0", ["9Z", "9G", "9C", "9E"]).ok)
	assert_eq(r.state.current_index, 1, "žiadny ťah navyše")


# --- Q2: bez návratu červenou sedmou ---------------------------------------

func test_red_seven_is_an_ordinary_seven_in_prsi() -> void:
	var r := make_rules([["9C"], ["7C", "8G"], ["KZ", "KE"]], "8C",
			["XZ", "XC", "XE", "9Z"])
	assert_true(play(r, "P0", ["9C"]).ok, "P0 dohral v tomto kole")
	assert_true(play(r, "P1", ["7C"]).ok)
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED,
			"v Prší červená sedma nikoho nevracia")
	assert_eq(r.state.pending_sevens_draw, 2, "je to bežná sedma za 2 karty")


# --- boti musia v Prší navrhovať len legálne ťahy ---------------------------

func test_bots_only_propose_legal_moves_in_prsi() -> void:
	for seed_value in range(1, 25):
		var r := FaraonRules.new()
		r.start(["P0", "P1", "P2"], RulesVariant.prsi(), seed_value * 977)
		var bots := {}
		for id in ["P0", "P1", "P2"]:
			bots[id] = BotStrategy.new(BotStrategy.Difficulty.HARD, seed_value)
		var guard := 0
		while r.state.phase == GameState.Phase.PLAYING and guard < 300:
			guard += 1
			var id: String = r.state.players[r.state.current_index].id
			var action: Dictionary = bots[id].choose(r.state, id)
			var res := r.apply(id, action)
			assert_true(res.ok, "bot navrhol nelegálny ťah (%s): %s" % [
					res.error, str(action)])
			if not res.ok:
				return
			if action.get("action", "") == FaraonActions.PLAY_CARDS:
				assert_eq(action.cards.size(), 1,
						"v Prší bot kladie po jednej karte")
