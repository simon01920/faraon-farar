extends GutTest
## Kombinovanie trestných kariet pri obrane proti nahromadenému trestu
## (zadanie „penalty_cards_czech_modes", sekcia 1) + rozsah návratu červenou
## sedmou (sekcia 2). Karty: znak (7 8 9 X D H K A) + farba (Z C E G);
## "DE" = zelený dolník = faraón, "7C" = červená sedma.


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


# --- sekcia 1: obrana sedmami (eskalácia trestu) ----------------------------

func test_scenario_1_two_sevens_stack_on_top_of_the_inherited_penalty() -> void:
	# Scenár 1: trest 3 (sedma predošlého hráča) + dve sedmy naraz = 9 pre
	# ďalšieho hráča v poradí.
	var r := make_rules([["7Z", "8G"], ["7E", "7G", "9G"], ["KZ", "KE"]], "XZ",
			["8Z", "8C", "8E", "9Z", "9C", "9E", "XC", "XE", "XG"])
	assert_true(play(r, "P0", ["7Z"]).ok)
	assert_eq(r.state.pending_sevens_draw, 3, "jedna sedma = základný trest")
	assert_true(play(r, "P1", ["7E", "7G"]).ok,
			"obranca smie položiť ľubovoľný počet sediem naraz")
	assert_eq(r.state.pending_sevens_draw, 9,
			"3 zdedené + 2 × 3 nové = 9 kariet pre ďalšieho hráča")
	assert_eq(r.state.current_index, 2, "trest čelí ďalší hráč, nie obranca")
	assert_true(r.apply("P2", FaraonActions.draw()).ok)
	assert_eq(r.state.players[2].hand.size(), 2 + 9,
			"neubránený hráč si vezme celý nahromadený trest")


func test_escalation_is_uncapped_with_three_sevens() -> void:
	var draw: Array = []
	for c in ["8Z", "8C", "8E", "8G", "9Z", "9C", "9E", "9G", "XC", "XE",
			"XG", "KZ", "KC", "KE", "KG"]:
		draw.append(c)
	# P0 si necháva kartu v ruke — nikto nevypadne, takže 7C nie je návratová.
	var r := make_rules([["7Z", "8G"], ["7C", "7E", "7G", "9G"], ["HZ", "HE"]],
			"XZ", draw)
	assert_true(play(r, "P0", ["7Z"]).ok)
	# Nikto nevypadol, takže 7C tu nie je návratová karta, len ďalšia sedma.
	assert_true(play(r, "P1", ["7C", "7E", "7G"]).ok)
	assert_eq(r.state.pending_sevens_draw, 12, "3 + 3 × 3 = 12")


# --- sekcia 1: obrana faraónom (zrušenie trestu) ----------------------------

func test_scenario_2_single_faraon_cancels_the_whole_penalty() -> void:
	# Scenár 2: trest 6, jeden faraón → trest 0, ťah pokračuje ďalším hráčom.
	var r := make_rules([["7Z", "7G"], ["DE", "9G"], ["KZ", "KE"]], "XZ",
			["8Z", "8C", "8E", "9Z", "9C", "9E"])
	assert_true(play(r, "P0", ["7Z", "7G"]).ok)
	assert_eq(r.state.pending_sevens_draw, 6)
	assert_true(play(r, "P1", ["DE"]).ok, "faraón je platná obrana")
	assert_eq(r.state.pending_sevens_draw, 0, "faraón ruší celý trest")
	assert_eq(r.state.top_card(), "DE")
	assert_eq(r.state.current_index, 2, "ťah pokračuje ďalším hráčom v poradí")


func test_scenario_3_faraon_leading_a_dolnik_group_cancels_exactly_once() -> void:
	# Scenár 3: viac kariet rovnakého znaku (dolníky) vedených faraónom —
	# trest padne na nulu rovnako ako pri jednom faraónovi, žiadny dvojnásobný
	# efekt, a hráč sa zbaví viac kariet naraz.
	var r := make_rules([["7Z", "7G"], ["DE", "DZ", "9G"], ["KZ", "KE"]], "XZ",
			["8Z", "8C", "8E", "9Z", "9C", "9E"])
	assert_true(play(r, "P0", ["7Z", "7G"]).ok)
	assert_eq(r.state.pending_sevens_draw, 6)
	assert_true(play(r, "P1", ["DE", "DZ"]).ok,
			"faraón smie viesť skupinu dolníkov")
	assert_eq(r.state.pending_sevens_draw, 0, "zrušenie trestu je jednorazové")
	assert_eq(r.state.players[1].hand.size(), 1, "obe karty odišli z ruky")
	assert_true(r.state.players[1].hand.has("9G"))
	assert_eq(r.state.top_card(), "DZ", "posledná položená karta je na vrchu")
	assert_eq(r.state.current_index, 2)


func test_faraon_must_lead_the_defensive_group() -> void:
	var r := make_rules([["7Z", "7G"], ["DE", "DZ", "9G"], ["KZ", "KE"]], "XZ",
			["8Z", "8C", "8E", "9Z", "9C", "9E"])
	assert_true(play(r, "P0", ["7Z", "7G"]).ok)
	var res := play(r, "P1", ["DZ", "DE"])
	assert_false(res.ok, "faraón nesmie prísť až za inou kartou")
	assert_eq(res.error, "faraon_must_be_first")
	assert_eq(r.state.pending_sevens_draw, 6, "odmietnutý ťah nič nemení")
	assert_eq(r.state.players[1].hand.size(), 3)


func test_dolniks_without_the_faraon_are_not_a_defense() -> void:
	var r := make_rules([["7Z"], ["DZ", "DG", "9G"], ["KZ", "KE"]], "XZ",
			["8Z", "8C", "8E", "9Z", "9C", "9E"])
	assert_true(play(r, "P0", ["7Z"]).ok)
	var res := play(r, "P1", ["DZ", "DG"])
	assert_false(res.ok, "obyčajné dolníky trest nerušia")
	assert_eq(res.error, "must_answer_with_sedma_or_faraon")


func test_scenario_5_seven_and_faraon_together_is_rejected() -> void:
	# Scenár 5: zmiešaná kombinácia sedma + faraón nie je platný ťah —
	# odmietnutie s chybou, žiadna tichá oprava.
	var r := make_rules([["7Z"], ["7E", "DE", "9G"], ["KZ", "KE"]], "XZ",
			["8Z", "8C", "8E", "9Z", "9C", "9E"])
	assert_true(play(r, "P0", ["7Z"]).ok)
	var res := play(r, "P1", ["7E", "DE"])
	assert_false(res.ok)
	assert_eq(res.error, "cards_not_same_rank")
	assert_eq(r.state.pending_sevens_draw, 3, "stav ostáva nedotknutý")
	assert_eq(r.state.players[1].hand.size(), 3)
	var res2 := play(r, "P1", ["DE", "7E"])
	assert_false(res2.ok, "ani v opačnom poradí")
	assert_eq(res2.error, "cards_not_same_rank")


# --- sekcia 1, scenár 4: faraón vytiahnutý počas trestného ťahania ----------

func test_scenario_4_drawn_faraon_offers_the_pause_and_stops_the_draw() -> void:
	# Ťahá sa karta po karte; faraón medzi ťahanými kartami ponúkne pauzu
	# (nie povinnosť) a jeho vyložením zvyšné ťahanie končí.
	var r := make_rules([["9C"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "DE", "XE"])
	r.state.pending_sevens_draw = 6
	var res := r.apply("P0", FaraonActions.draw())
	assert_true(res.ok)
	assert_true(r.state.penalty_interrupt, "vytiahnutý faraón ponúka pauzu")
	assert_eq(r.state.interrupt_card, "DE")
	assert_eq(r.state.pending_sevens_draw, 4, "zvyšok trestu čaká na rozhodnutie")
	assert_eq(r.state.current_index, 0, "ťah ostáva hráčovi")
	assert_true(play(r, "P0", ["DE"]).ok)
	assert_eq(r.state.pending_sevens_draw, 0, "zvyšné ťahanie končí")
	assert_eq(r.state.players[0].hand.size(), 2, "9C + prvá vytiahnutá karta")
	assert_eq(r.state.current_index, 1)


func test_interrupt_play_must_be_led_by_the_drawn_card() -> void:
	var r := make_rules([["9C", "DZ"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "DE", "XE"])
	r.state.pending_sevens_draw = 6
	assert_true(r.apply("P0", FaraonActions.draw()).ok)
	var res := play(r, "P0", ["DZ"])
	assert_false(res.ok, "pauzu možno využiť len kartou, ktorá ju vyvolala")
	assert_eq(res.error, "interrupt_card_or_draw")
	assert_true(r.state.penalty_interrupt, "pauza trvá ďalej")


func test_interrupt_seven_may_take_more_sevens_from_the_hand() -> void:
	# Rovnaká kombinačná logika ako pri obrane mimo pauzy: sedmy priložené
	# k vytiahnutej sedme zvyšujú trest, ktorý ide na ďalšieho hráča.
	var r := make_rules([["9C", "7E"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "7Z", "XE"])
	r.state.variant.seven_interrupt = true # D4 (default OFF)
	r.state.pending_sevens_draw = 6
	assert_true(r.apply("P0", FaraonActions.draw()).ok)
	assert_eq(r.state.interrupt_card, "7Z")
	assert_true(play(r, "P0", ["7Z", "7E"]).ok)
	assert_eq(r.state.pending_sevens_draw, 6,
			"zvyšok vlastného trestu padá; 2 × 3 ide na ďalšieho hráča")
	assert_eq(r.state.current_index, 1)


func test_interrupt_single_seven_passes_only_the_base_step() -> void:
	# Simonovo rozhodnutie D4/D5: žiadny trest sa neprenáša — jedna sedma
	# znamená pre ďalšieho hráča presne základný krok (3).
	var r := make_rules([["9C"], ["8G"]], "8Z",
			["KZ", "KG", "KE", "XC", "7Z", "XE"])
	r.state.variant.seven_interrupt = true
	r.state.pending_sevens_draw = 6
	assert_true(r.apply("P0", FaraonActions.draw()).ok)
	assert_true(play(r, "P0", ["7Z"]).ok)
	assert_eq(r.state.pending_sevens_draw, 3)


# --- sekcia 2: rozsah návratu červenou sedmou (default = aktuálne kolo) -----

func test_default_variant_limits_the_return_to_the_current_round() -> void:
	assert_eq(RulesVariant.classic().red7_return_scope, "round",
			"predvolená hra vracia len hráča z aktuálneho kola")
	assert_eq(RulesVariant.DEFAULTS["red7_return_scope"], "round",
			"UI badge predvolenej hodnoty musí ukazovať to isté")
	assert_eq(RulesVariant.olympic().red7_return_scope, "round",
			"rovnaký default aj v olympijskom režime")


func test_player_eliminated_in_the_current_round_is_returned() -> void:
	var r := make_rules([["9Z"], ["7C", "8G"], ["KZ", "KE"]], "8Z",
			["XZ", "XC", "XE", "XG"])
	assert_true(play(r, "P0", ["9Z"]).ok, "P0 dohral v tomto kole")
	assert_true(play(r, "P1", ["7C"]).ok)
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.ACTIVE,
			"vypadnutý v aktuálnom kole sa vracia")
	assert_eq(r.state.players[0].hand.size(), 3)


func test_player_eliminated_in_the_previous_round_is_not_returned() -> void:
	# Regresia k sekcii 2: po uzavretí kola je červená sedma obyčajná sedma.
	var r := make_rules([["9C"], ["7C", "8G", "8C", "9G"], ["KZ", "KE", "XG"]],
			"8C", ["XZ", "XC", "XE"])
	assert_true(play(r, "P0", ["9C"]).ok) # P0 dohral, vrch kôpky je 9C
	# Celý obeh stola: obaja zostávajúci hráči odohrali svoj ťah.
	assert_true(r.apply("P1", FaraonActions.draw()).ok)
	assert_true(r.apply("P2", FaraonActions.draw()).ok)
	assert_true(r.apply("P1", FaraonActions.draw()).ok)
	assert_true(r.apply("P2", FaraonActions.draw()).ok)
	assert_false(r.state.is_returnable(r.state.players[0]),
			"okno návratu sa po obehu stola zatvorilo")
	assert_true(play(r, "P1", ["7C"]).ok, "7C na červeň je legálna ako sedma")
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.FINISHED,
			"hráč z predošlého kola sa už nevracia")
	assert_eq(r.state.pending_sevens_draw, 3, "7C padla ako obyčajná sedma")


func test_anyone_scope_still_returns_an_old_elimination() -> void:
	var r := make_rules([["9C"], ["7C", "8G", "8C", "9G"], ["KZ", "KE", "XG"]],
			"8C", ["XZ", "XC", "XE", "XG", "9Z", "9E"])
	r.state.variant.red7_return_scope = "anyone" # domáce pravidlo, opt-in
	assert_true(play(r, "P0", ["9C"]).ok)
	r.state.handovers += r.state.active_count() + 5
	assert_true(play(r, "P1", ["7C"]).ok)
	assert_eq(r.state.players[0].status, GameState.PlayerStatus.ACTIVE,
			"pri rozsahu hocikto ostáva návrat otvorený aj po kole")


func test_round_window_is_measured_in_handovers_not_actions() -> void:
	# Trestné ťahanie s pauzou minie viac akcií na jeden ťah — okno kola
	# sa tým nesmie predčasne zatvoriť.
	var r := make_rules([["9Z"], ["8G", "7C"], ["KZ", "KE"]], "8Z",
			["XZ", "XC", "XE", "XG", "9C", "9E"])
	assert_true(play(r, "P0", ["9Z"]).ok)
	var finished := r.state.players[0]
	r.state.turn_counter += 50 # veľa akcií, ale žiadne odovzdanie ťahu
	assert_true(r.state.is_returnable(finished),
			"počet akcií nesmie ovplyvniť dĺžku kola")
	r.state.handovers += r.state.active_count() + 1
	assert_false(r.state.is_returnable(finished),
			"až obeh stola okno zatvorí")
