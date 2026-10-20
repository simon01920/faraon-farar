class_name FaraonRules
extends RefCounted
## Authoritative rules engine for Faraón (source: rules/faraon.pdf, Piri 2009).
## Pure logic: no scene tree, no nodes, no networking — unit-testable headless.
## The server (or the in-process local server) is the only place apply() runs;
## clients merely propose actions and render broadcast state.
##
## Rozhodnutia podľa zadania „fix-polish-featureadd" (A2, B3, D pravidlá):
## 1. Eso = čistý skip: 1 eso preskočí presne 1 hráča a na rade je ďalší
##    v poradí. ŽIADNE voľné pokračovanie pre vlastníka reťaze (staré
##    ESO_CONTINUATION odstránené). Prebitie esa predlžuje reťaz o počet
##    priložených es (pokiaľ to D3/D9 nezakazujú).
## 2. Spálená dáva extra ťah len pre ne-eso/ne-sedma štvorice.
## 3. Faraón je plne neutrálny (padne na čokoľvek, čokoľvek padne naň);
##    farbu hlási len horník. V Purista režime (D10) je obyčajný dolník.
## 4. Štartové eso/sedma sa validujú spodnou kartou balíka; horník na
##    spodku sa nepočíta. Štartový horník berie farbu z najnižšej
##    ne-horníkovej karty.
## 5. Návrat červenou sedmou (B3): obeť si berie VŽDY len základ trestu
##    (krok z D6, default 3) bez ohľadu na dĺžku reťaze; reťaz sa tým
##    spotrebuje; „ťah" vráteného hráča je vzatie kariet — na rade je
##    hráč nasledujúci za pokladajúcim (v 2-hráčovej hre teda znovu on).
##    Rozsah vrátiteľnosti riadi D8 (DEFAULT: len hráč vypadnutý v aktuálnom
##    kole — meria sa cez GameState.handovers, jeden obeh stola).
## 6. Obrana proti trestu je atomický ťah kariet rovnakého znaku: buď 1..N
##    sediem (každá pridá krok trestu ďalšiemu hráčovi), alebo faraón —
##    voliteľne s ďalšími dolníkmi — ktorý trest zruší na nulu. Zmiešaná
##    kombinácia sedma+faraón je neplatná (rôzny znak) a faraón musí byť
##    prvou kartou ťahu. Rovnako to platí pri pauze trestného ťahania: ťah
##    musí viesť karta, ktorá pauzu vyvolala.

const Status := GameState.PlayerStatus
const Phase := GameState.Phase

var state: GameState


## Starts a new round. `hand_sizes` optionally overrides the dealt hand size
## per player id (Olympic modes deal shrinking hands); players without an
## entry get variant.initial_hand_size. `start_index` = kto začína (B1 —
## rotáciu a prvé RNG určenie rieši meta-vrstva). Returns the setup events.
func start(player_ids: Array, variant: RulesVariant, seed_value: int,
		hand_sizes: Dictionary = {}, start_index: int = 0) -> Array:
	assert(player_ids.size() >= 2 and player_ids.size() <= 5)
	state = GameState.new()
	state.variant = variant
	for id in player_ids:
		var p := GameState.PlayerState.new()
		p.id = id
		state.players.append(p)
	state.current_index = clampi(start_index, 0, player_ids.size() - 1)

	state.rng_seed = seed_value
	state.draw_pile = FaraonDeck.shuffled(seed_value, variant.reverse_card)
	var events: Array = []
	var dealt := {}
	var max_size := 0
	# Deal cap: the deal must always leave the start card plus at least one
	# card in the draw pile (the bottom card the start rules inspect). Without
	# it 5 players x 7 cards (or a host-supplied size) overdraws the 32-card
	# deck and start() aborts half-way with an empty discard pile.
	var cap: int = (state.draw_pile.size() - 2) / state.players.size()
	for p in state.players:
		dealt[p.id] = clampi(int(hand_sizes.get(p.id, variant.initial_hand_size)),
				0, cap)
		max_size = maxi(max_size, dealt[p.id])
	for _i in max_size:
		for p in state.players:
			if p.hand.size() < dealt[p.id]:
				p.hand.append(state.draw_pile.pop_back())
	events.append({"type": "DEALT", "hands": dealt})

	var start_card: String = state.draw_pile.pop_back()
	state.discard_pile.append(start_card)
	events.append({"type": "START_CARD", "card": start_card})
	_apply_start_card_effects(start_card, events)
	return events


func _apply_start_card_effects(card: String, events: Array) -> void:
	var bottom: String = state.draw_pile[0]
	if FaraonCard.is_eso(card) or FaraonCard.is_sedma(card):
		# The deck is physically flipped to check the bottom card — the
		# client animates this via START_DECK_FLIP regardless of validity.
		events.append({"type": "START_DECK_FLIP", "bottom": bottom})
		# Valid only when the deck's bottom card has the same rank and is not
		# a horník (a bottom horník never counts).
		if not FaraonCard.is_hornik(bottom) \
				and FaraonCard.rank_of(bottom) == FaraonCard.rank_of(card):
			if FaraonCard.is_eso(card):
				state.pending_aces = 1
				events.append({"type": "START_ESO_VALID"})
			else:
				state.pending_sevens_draw = state.variant.capped_penalty(
						state.variant.seven_penalty_step)
				events.append({"type": "START_SEDMA_VALID"})
	elif FaraonCard.is_hornik(card):
		var suit := -1
		var source := bottom
		for c in state.draw_pile: # index 0 = bottom, scan upwards
			# Tanečnica (D7a) nemá farbu — preskakuje sa rovnako ako horník.
			if not FaraonCard.is_hornik(c) and not FaraonCard.is_reverse(c):
				suit = FaraonCard.suit_of(c)
				source = c
				break
		events.append({"type": "START_DECK_FLIP", "bottom": source})
		state.declared_suit = suit
		events.append({"type": "SUIT_DECLARED", "suit": suit})
	# Start faraón: neutral, no declaration — anything can be played on it.


## Validates and applies one atomic action from player_id.
## Returns {ok: bool, error: String, events: Array}.
func apply(player_id: String, action: Dictionary) -> Dictionary:
	if state == null or state.phase != Phase.PLAYING:
		return _fail("game_not_running")
	var idx := state.index_of(player_id)
	if idx == -1:
		return _fail("unknown_player")
	if idx != state.current_index:
		return _fail("not_your_turn")

	var result: Dictionary
	match action.get("action", ""):
		FaraonActions.PLAY_CARDS:
			result = _apply_play(idx, action)
		FaraonActions.DRAW:
			result = _apply_draw(idx)
		FaraonActions.PASS:
			result = _apply_pass(idx)
		_:
			return _fail("unknown_action")

	if result.ok:
		state.turn_counter += 1
		_check_game_over(result.events)
	return result


# --- PLAY_CARDS ---------------------------------------------------------

func _apply_play(idx: int, action: Dictionary) -> Dictionary:
	var player := state.players[idx]
	var cards: Array = action.get("cards", [])
	var declared: int = action.get("declared_suit", -1)

	var err := _validate_cards_owned(player, cards)
	if err != "":
		return _fail(err)

	# D14: obmedzenie poslednej karty — ťah, ktorý by vyprázdnil ruku
	# zakázanou kartou, je neplatný (platí pre všetky vetvy vrátane obrán).
	if cards.size() == player.hand.size():
		var last_rank := FaraonCard.rank_of(cards.back())
		if state.variant.finish_rule == "no_seven" \
				and last_rank == FaraonCard.Rank.R7:
			return _fail("cannot_finish_with_seven")
		if state.variant.finish_rule == "hornik_only" \
				and last_rank != FaraonCard.Rank.HORNIK:
			return _fail("must_finish_with_hornik")

	# Pauza počas trestného ťahania (D4/D5): ťah musí VIESŤ karta, ktorá pauzu
	# vyvolala. K nej sa smú priložiť ďalšie karty rovnakého znaku z ruky —
	# rovnaká obranná kombinácia ako mimo pauzy (sedmy trest ďalej zvyšujú).
	if state.penalty_interrupt:
		if cards[0] != state.interrupt_card:
			return _fail("interrupt_card_or_draw")
		# Zamietnutý ťah nesmie nič zmeniť — hlásenia sa overia PRED zrušením
		# pauzy a trestu.
		var decl_err := _declaration_error(cards, declared,
				action.get("declared_rank", -1))
		if decl_err != "":
			return _fail(decl_err)
		state.penalty_interrupt = false
		state.interrupt_card = ""
		# Zvyšok VLASTNÉHO trestu padá v oboch prípadoch: faraón ho ruší,
		# sedma ho posúva ďalej (nový trest pripočíta _place_and_resolve).
		state.pending_sevens_draw = 0
		state.pending_hard_penalty = false
		return _place_and_resolve(idx, cards, declared, false,
				action.get("declared_rank", -1))

	if state.pending_aces > 0:
		return _apply_eso_counter(idx, cards, declared,
				action.get("declared_rank", -1))

	# Červená sedma: keď existuje vrátiteľný hráč, návrat sa spustí
	# automaticky a deterministicky (naposledy vypadnutý). Purista (D10)
	# návrat vypína — 7C je potom obyčajná sedma.
	if state.variant.allows_red7_return() \
			and FaraonCard.rank_of(cards[0]) == FaraonCard.Rank.R7 \
			and cards.has("7C"):
		var victim_idx := _latest_returnable_index()
		if victim_idx != -1:
			return _apply_red_seven_return(idx, cards, victim_idx)

	if state.pending_sevens_draw > 0:
		return _apply_sevens_defense(idx, cards, declared,
				action.get("declared_rank", -1))

	# D11: kým je ohlásená hodnota, hrá sa len ona alebo ďalší spodok.
	if state.announced_rank != -1:
		var is_rank_match: bool = not FaraonCard.is_reverse(cards[0]) \
				and int(FaraonCard.rank_of(cards[0])) == state.announced_rank
		var is_trump := cards.size() >= 1 and _is_announcer(cards.back())
		if not (is_rank_match or is_trump):
			return _fail("must_play_announced_rank")
		return _place_and_resolve(idx, cards,
				action.get("declared_suit", -1), false,
				action.get("declared_rank", -1))

	# Bežný ťah: prvá karta musí sedieť na kôpku.
	if not _first_card_legal(cards[0]):
		return _fail("card_does_not_match")

	return _place_and_resolve(idx, cards, declared, false,
			action.get("declared_rank", -1))


## Je medzi kartami faraón? (Skupina je vždy rovnakého znaku, takže faraón sa
## môže objaviť len v skupine dolníkov.)
func _contains_faraon(cards: Array) -> bool:
	for c in cards:
		if FaraonCard.is_faraon(c):
			return true
	return false


## Hlásenia, ktoré vyžaduje POSLEDNÁ karta ťahu: horník → farba, D11
## spodok-menič → znak. Vetvy, ktoré pred položením menia stav (rušia trest,
## eso-reťaz či pauzu), to musia overiť VOPRED — zamietnutý ťah nesmie nič
## zmeniť (inak by chýbajúce hlásenie zrušilo trest bez položenia kariet).
func _declaration_error(cards: Array, declared: int, declared_rank: int) -> String:
	var last: String = cards.back()
	if FaraonCard.is_hornik(last) and (declared < 0 or declared > 3):
		return "declared_suit_required"
	if state.variant.unter_announcer_active() and _is_announcer(last) \
			and (declared_rank < 0 or declared_rank > 7):
		return "declared_rank_required"
	return ""


## D11: spodky-meniče sú dolníky OKREM zeleného (ten ostáva faraónom).
func _is_announcer(card: String) -> bool:
	return not FaraonCard.is_reverse(card) \
			and FaraonCard.rank_of(card) == FaraonCard.Rank.DOLNIK \
			and not (FaraonCard.is_faraon(card) and state.variant.faraon_is_wild())


func _validate_cards_owned(player: GameState.PlayerState, cards: Array) -> String:
	if cards.is_empty():
		return "no_cards"
	# P6: v Prší sa kladie vždy len jedna karta.
	if cards.size() > 1 and not state.variant.multi_card_play:
		return "single_card_only"
	var seen := {}
	var rank := FaraonCard.rank_of(cards[0]) if FaraonCard.is_valid_id(cards[0]) else -1
	for c in cards:
		if not (c is String) or not FaraonCard.is_valid_id(c):
			return "invalid_card_id"
		if seen.has(c):
			return "duplicate_card"
		seen[c] = true
		if not player.hand.has(c):
			return "card_not_in_hand"
		if FaraonCard.rank_of(c) != rank:
			return "cards_not_same_rank" # multi-card play must share the rank
	return ""


func _first_card_legal(card: String) -> bool:
	var top := state.top_card()
	# D7: Tanečnica padne na čokoľvek a čokoľvek padne na ňu.
	if FaraonCard.is_reverse(card) or FaraonCard.is_reverse(top):
		return true
	if state.variant.faraon_is_wild():
		if FaraonCard.is_faraon(card):
			return true # faraón padne na čokoľvek
		if FaraonCard.is_faraon(top):
			return true # ...a čokoľvek padne na faraóna
	# D11: spodok-menič sa odhadzuje voľne (ako voľný horník).
	if state.variant.unter_announcer_active() and _is_announcer(card):
		return true
	# P5: v Prší svršek nepadne na eso ani na sedmu (inak mení farbu voľne).
	if FaraonCard.is_hornik(card) and not state.variant.hornik_strict \
			and state.variant.changer_allowed_on(top):
		return true
	if FaraonCard.rank_of(card) == FaraonCard.rank_of(top):
		return true
	var required_suit := state.declared_suit if state.declared_suit != -1 \
			else FaraonCard.suit_of(top)
	return FaraonCard.suit_of(card) == required_suit


func _apply_eso_counter(idx: int, cards: Array, declared: int = -1,
		declared_rank: int = -1) -> Dictionary:
	# Domáce pravidlo: faraón ruší celú eso-reťaz. Ako pri sedmovej obrane
	# smie viesť skupinu dolníkov — zrušenie je jednorazové.
	if state.variant.faraon_blocks_eso and state.variant.faraon_is_wild() \
			and _contains_faraon(cards):
		if not FaraonCard.is_faraon(cards[0]):
			return _fail("faraon_must_be_first")
		var decl_err := _declaration_error(cards, declared, declared_rank)
		if decl_err != "":
			return _fail(decl_err) # pred zrušením reťaze — nič sa nezmení
		state.pending_aces = 0
		return _place_and_resolve(idx, cards, declared, false, declared_rank)
	# D1: návrat červenou sedmou položený priamo na aktívnu stopku — hráčov
	# stop sa touto reakciou spotrebuje, zvyšok reťaze beží ďalej.
	if state.variant.red7_on_active_eso \
			and FaraonCard.rank_of(cards[0]) == FaraonCard.Rank.R7 \
			and cards.has("7C"):
		var victim_idx := _latest_returnable_index()
		if victim_idx != -1:
			state.pending_aces -= 1
			return _apply_red_seven_return(idx, cards, victim_idx)
	# D3 / D9-off: eso sa nedá prebiť — jediná odpoveď je stáť.
	if state.variant.eso_no_counter:
		return _fail("must_answer_with_eso")
	for c in cards:
		if not FaraonCard.is_eso(c):
			return _fail("must_answer_with_eso") # faraón na eso nejde
	# Prebitie: zruší vlastný stop hráča a predĺži reťaz o priložené esá.
	state.pending_aces = state.pending_aces - 1 + cards.size()
	return _place_and_resolve(idx, cards, -1, true)


## Obrana proti nahromadenému trestu. Dva atomické typy ťahu (nikdy zmiešané —
## rovnaký znak vynucuje už _validate_cards_owned):
##   1. jedna alebo viac SEDIEM — každá pridá krok trestu ďalšiemu hráčovi,
##   2. FARAÓN (voliteľne s ďalšími dolníkmi) — ruší celý trest na nulu.
## Faraón musí byť prvá karta ťahu; zrušenie trestu je jednorazové, počet
## priložených dolníkov ho nenásobí.
func _apply_sevens_defense(idx: int, cards: Array, declared: int,
		declared_rank: int = -1) -> Dictionary:
	# D13: trest zapečatený červenou desiatkou sa už nedá odraziť.
	if state.pending_hard_penalty:
		return _fail("penalty_sealed_must_draw")
	if state.variant.faraon_is_wild() and _contains_faraon(cards):
		if not FaraonCard.is_faraon(cards[0]):
			return _fail("faraon_must_be_first")
		var decl_err := _declaration_error(cards, declared, declared_rank)
		if decl_err != "":
			return _fail(decl_err) # pred zrušením trestu — nič sa nezmení
		state.pending_sevens_draw = 0 # faraón ruší celú sedmičkovú reťaz
		state.pending_hard_penalty = false
		return _place_and_resolve(idx, cards, declared, false, declared_rank)
	# D13: červená desiatka ako obrana na červenú sedmu — trest sa zapečatí.
	if state.variant.red_ten_active() and cards.size() == 1 and cards[0] == "XC" \
			and state.top_card() == "7C":
		return _place_and_resolve(idx, cards, -1)
	# D12 prebíjacia varianta: zelený kráľ sa dá položiť na zelenú sedmu
	# a zelená sedma na kráľa (reťaz pokračuje).
	if state.variant.green_king_counter_active() \
			and cards.size() == 1 and cards[0] == "KE" \
			and state.top_card() == "7E":
		return _place_and_resolve(idx, cards, -1)
	if state.variant.green_king_active() and state.top_card() == "KE":
		if state.variant.green_king_counter_active() \
				and cards.size() == 1 and cards[0] == "7E":
			return _place_and_resolve(idx, cards, -1)
		# Kráľov trest sa bez prebíjacej varianty nedá odraziť.
		return _fail("penalty_sealed_must_draw")
	for c in cards:
		if not FaraonCard.is_sedma(c):
			return _fail("must_answer_with_sedma_or_faraon")
	return _place_and_resolve(idx, cards, -1)


## Volajúci garantuje: cards sú samé sedmy vrátane 7C, obeť je vrátiteľná.
## Návrat ignoruje farbu/znak. B3: obeť si berie VŽDY len základ (krok D6,
## default 3) — dĺžka predchádzajúcej reťaze sa nepočíta a reťaz sa návratom
## spotrebuje. Vzatie kariet je obetin „ťah", takže na rade je hráč
## nasledujúci za POKLADAJÚCIM (obeť sa preskočí, ak by sedela hneď za ním
## — v 2-hráčovej hre je tak na rade znovu pokladajúci).
func _apply_red_seven_return(idx: int, cards: Array, victim_idx: int) -> Dictionary:
	var victim := state.players[victim_idx]
	var player := state.players[idx]
	for c in cards:
		player.hand.erase(c)
		state.discard_pile.append(c)
	state.declared_suit = -1

	# Simonova oprava: PREDCHÁDZAJÚCA reťaz sa neráta, ale sedmy priložené
	# SPOLU s červenou v tomto ťahu áno — 7C + ďalšia sedma = 2 × krok (6).
	var total: int = state.variant.seven_penalty_step * cards.size()
	state.pending_sevens_draw = 0
	# Spotrebovaný trest nesmie nechať visieť pečať D13 — inak by sa ďalšia,
	# úplne nová sedmičková reťaz nedala odraziť.
	state.pending_hard_penalty = false
	victim.status = Status.ACTIVE
	victim.finished_at = -1
	victim.finished_at_handover = -1
	victim.finished_with_eso = false
	victim.finish_position = -1
	var events: Array = [{"type": "CARDS_PLAYED", "player": player.id, "cards": cards}]
	var drawn := _draw_cards(victim, total, events)
	# A1: bez DREW eventu klient neprehrá animáciu vzatia kariet — rovnaký
	# event ako pri každom inom ťahaní, len pre obeť.
	events.append({"type": "DREW", "player": victim.id, "count": drawn,
			"penalty": true})
	events.append({"type": "PLAYER_RETURNED", "player": victim.id,
			"by": player.id, "drew": drawn})
	_handle_possible_finish(idx, cards, events)
	if state.phase == Phase.PLAYING:
		_advance_turn(idx)
		if state.current_index == victim_idx:
			# Obeť práve minula svoj ťah vzatím kariet.
			_advance_turn(victim_idx)
	return {"ok": true, "error": "", "events": events}


## D8 — jediná implementácia žije v GameState, aby ju engine aj boti čítali
## rovnako (default: len hráč vypadnutý v aktuálnom kole).
func _is_returnable(p: GameState.PlayerState) -> bool:
	return state.is_returnable(p)


## The deterministic červená-sedma target: the player who was eliminated most
## recently within the current round ("last eliminated"), -1 when nobody is
## returnable. finished_at values are unique (one finish per applied action),
## so the maximum identifies the newest elimination unambiguously.
func _latest_returnable_index() -> int:
	var best := -1
	for i in state.players.size():
		var p := state.players[i]
		if not _is_returnable(p):
			continue
		if best == -1 or p.finished_at > state.players[best].finished_at:
			best = i
	return best


## Common tail of every successful card placement: move cards to the pile,
## resolve declarations, eso/sedma effects, spálená, finishing and advancing.
func _place_and_resolve(idx: int, cards: Array, declared: int,
		is_eso_counter: bool = false, declared_rank: int = -1) -> Dictionary:
	var player := state.players[idx]
	var last: String = cards.back()
	var decl_err := _declaration_error(cards, declared, declared_rank)
	if decl_err != "":
		return _fail(decl_err)
	var needs_declaration := FaraonCard.is_hornik(last)
	# D11: spodok-menič vyžaduje ohlásenie hodnoty (znaku).
	var needs_rank := state.variant.unter_announcer_active() and _is_announcer(last)

	for c in cards:
		player.hand.erase(c)
		state.discard_pile.append(c)
	state.declared_suit = declared if needs_declaration else -1

	var events: Array = [{"type": "CARDS_PLAYED", "player": player.id, "cards": cards}]
	if needs_declaration:
		events.append({"type": "SUIT_DECLARED", "suit": declared})

	var rank := FaraonCard.rank_of(cards[0]) if not FaraonCard.is_reverse(cards[0]) \
			else -1 as FaraonCard.Rank
	# D11: položenie ohlásenej hodnoty ruší hlásenie; nový spodok prehlási.
	if state.announced_rank != -1 and int(rank) == state.announced_rank:
		state.announced_rank = -1
		events.append({"type": "RANK_ANNOUNCED", "rank": -1})
	if needs_rank:
		state.announced_rank = declared_rank
		events.append({"type": "RANK_ANNOUNCED", "rank": declared_rank})

	if FaraonCard.is_reverse(last):
		# D7: Tanečnica otáča smer hry.
		state.direction *= -1
		events.append({"type": "DIRECTION_REVERSED"})
	elif state.variant.tens_reverse_active() and rank == FaraonCard.Rank.R10:
		# D15: v Hospodskom prší každá desiatka obracia smer.
		state.direction *= -1
		events.append({"type": "DIRECTION_REVERSED"})

	if not is_eso_counter and rank == FaraonCard.Rank.ESO:
		state.pending_aces = cards.size()
	elif rank == FaraonCard.Rank.R7:
		# P2: Prší reťaz stropuje (2/4/6/8), Faraón je bez stropu.
		state.pending_sevens_draw = state.variant.capped_penalty(
				state.pending_sevens_draw
				+ state.variant.seven_penalty_step * cards.size())
	elif state.variant.green_king_active() and last == "KE":
		# D12: zelený kráľ = +4 pre ďalšieho hráča (nezávislé od kroku sedmy).
		state.pending_sevens_draw += 4
	elif state.variant.red_ten_active() and last == "XC":
		# D13: červená desiatka = ďalší hráč ťahá 1 kartu (bez obrany).
		state.pending_sevens_draw += 1
		state.pending_hard_penalty = true

	var finished := _handle_possible_finish(idx, cards, events)
	if state.phase != Phase.PLAYING:
		return {"ok": true, "error": "", "events": events}

	var spalena := cards.size() == 4 and state.variant.allows_spalena() \
			and rank != FaraonCard.Rank.ESO and rank != FaraonCard.Rank.R7
	if spalena and not finished:
		# Guaranteed extra move; the multiply house rule banks one additional
		# move per consecutive spálená (2nd in a row = two moves, ...).
		state.spalena_chain += 1
		if state.variant.spalena_multiply:
			state.extra_turns += state.spalena_chain - 1
		events.append({"type": "SPALENA_EXTRA_TURN", "player": player.id})
		# current_index stays — the guaranteed double move.
	elif state.extra_turns > 0 and not finished:
		state.extra_turns -= 1 # nabankovaný spálená ťah, hráč ostáva
	else:
		_advance_turn(idx)
		# D3/D9-off: eso má okamžitý efekt — stopky sa spotrebujú hneď bez
		# PASS akcií (nikto ich aj tak nemôže prebiť).
		if state.pending_aces > 0 and not state.variant.counter_allowed():
			while state.pending_aces > 0 and state.active_count() > 1:
				events.append({"type": "STOPPED",
						"player": state.players[state.current_index].id})
				state.pending_aces -= 1
				_advance_turn(state.current_index)
	return {"ok": true, "error": "", "events": events}


## Moves the turn to the next active player and clears per-streak state.
func _advance_turn(from_idx: int) -> void:
	state.extra_turns = 0
	state.spalena_chain = 0
	state.handovers += 1 # meria „kolo" pre rozsah návratu (D8)
	state.current_index = state.next_active_index(from_idx)


## Marks the player finished when their hand emptied. Returns true if so.
func _handle_possible_finish(idx: int, cards: Array, events: Array) -> bool:
	var player := state.players[idx]
	if not player.hand.is_empty():
		return false
	player.status = Status.FINISHED
	player.finished_at = state.turn_counter
	player.finished_at_handover = state.handovers
	player.finished_with_eso = FaraonCard.rank_of(cards[0]) == FaraonCard.Rank.ESO
	player.finish_position = _next_finish_position()
	events.append({"type": "PLAYER_FINISHED", "player": player.id,
			"with_eso": player.finished_with_eso,
			"position": player.finish_position})
	if player.finished_with_eso and state.players.size() == 2:
		# Auto-win: the opponent loses immediately, no return possible.
		state.phase = Phase.GAME_OVER
		state.loser_index = state.next_active_index(idx)
		state.players[state.loser_index].finish_position = state.players.size()
		events.append({"type": "GAME_OVER", "loser": state.players[state.loser_index].id})
	elif state.variant.end_on_first_finish:
		# B2: olympijské sub-kolo končí prvým dohratým — zvyšok pokračuje
		# v rozstrele, ktorý pripraví meta-vrstva (FaraonMatch).
		state.phase = Phase.GAME_OVER
		state.loser_index = -1
		events.append({"type": "GAME_OVER", "loser": ""})
	return true


## 1-based placement for the player finishing right now: one past the number
## of placements already handed out. Deterministic even across červená-sedma
## returns — the returned player is always the latest finisher, so clearing
## their position never leaves a gap.
func _next_finish_position() -> int:
	var taken := 0
	for p in state.players:
		if p.finish_position != -1:
			taken += 1
	return taken + 1


# --- DRAW / PASS ---------------------------------------------------------

func _apply_draw(idx: int) -> Dictionary:
	if state.pending_aces > 0:
		return _fail("must_answer_eso_or_pass")
	var player := state.players[idx]
	var events: Array = []
	var drawn := 0
	if state.pending_sevens_draw > 0 or state.penalty_interrupt:
		# Trestné ťahanie beží karta po karte: faraón (D5) alebo sedma (D4)
		# vytiahnuté uprostred trestu ponúknu pauzu — hráč MÔŽE kartu vyložiť
		# alebo ťahať ďalej. Nikdy nie povinnosť.
		state.penalty_interrupt = false
		state.interrupt_card = ""
		while state.pending_sevens_draw > 0:
			if _draw_cards(player, 1, events) == 0:
				break # všetky karty sú v rukách — fyzicky sa nedá ťahať
			drawn += 1
			state.pending_sevens_draw -= 1
			var got: String = player.hand.back()
			var offer := false
			# Zapečatený trest (D13) sa už nedá odraziť — ani vytiahnutou
			# kartou, preto sa pauza pri pečati neponúka.
			if state.pending_sevens_draw > 0 and not state.pending_hard_penalty:
				if state.variant.faraon_interrupt and FaraonCard.is_faraon(got) \
						and state.variant.faraon_is_wild():
					offer = true
				elif state.variant.seven_interrupt and FaraonCard.is_sedma(got):
					offer = true
			if offer:
				state.penalty_interrupt = true
				state.interrupt_card = got
				events.append({"type": "DREW", "player": player.id,
						"count": drawn, "penalty": true})
				events.append({"type": "PENALTY_INTERRUPT", "player": player.id,
						"card": got, "remaining": state.pending_sevens_draw})
				# Ťah ostáva hráčovi, kým sa nerozhodne.
				return {"ok": true, "error": "", "events": events}
		# PREDPOKLAD (Simon to môže prehodnotiť): keď balík aj odhadzovacia
		# kôpka vyschnú uprostred trestu (break vyššie), zvyšok trestu
		# ťahajúceho PREPADÁ — nikdy neprechádza na ďalšieho hráča.
		state.pending_sevens_draw = 0
		state.pending_hard_penalty = false # D13: zapečatený trest je vybavený
		events.append({"type": "DREW", "player": player.id, "count": drawn,
				"penalty": true})
	else:
		drawn = _draw_cards(player, 1, events)
		events.append({"type": "DREW", "player": player.id, "count": drawn,
				"penalty": false})
	if drawn == 0:
		events.append({"type": "DECK_EXHAUSTED", "player": player.id})
	_advance_turn(idx)
	return {"ok": true, "error": "", "events": events}


## A2: zastavený hráč jednoducho stojí a hra ide ďalej v poradí — jedno eso
## preskočí presne jedného hráča, žiadne voľné pokračovanie pre vlastníka.
func _apply_pass(idx: int) -> Dictionary:
	if state.pending_aces <= 0:
		return _fail("nothing_to_pass")
	state.pending_aces -= 1
	var events: Array = [{"type": "STOPPED", "player": state.players[idx].id}]
	_advance_turn(idx)
	return {"ok": true, "error": "", "events": events}


## Draws up to `amount` cards, recycling the discard pile when the draw pile
## runs out (top card stays, the rest is shuffled face-down — house-standard,
## keeps card order unpredictable). A successful recycle appends a
## PILE_REFLIPPED event to `events` so the client can animate it. Returns how
## many cards could actually be drawn; 0 means every other card is in hands
## and drawing is physically impossible.
func _draw_cards(player: GameState.PlayerState, amount: int,
		events: Array = []) -> int:
	var drawn := 0
	for _i in amount:
		if state.draw_pile.is_empty():
			_reflip_discard()
			if not state.draw_pile.is_empty():
				events.append({"type": "PILE_REFLIPPED",
						"top": state.top_card(),
						"remaining": state.draw_pile.size()})
		if state.draw_pile.is_empty():
			break # every card is in hands — physically impossible to draw
		player.hand.append(state.draw_pile.pop_back())
		drawn += 1
	return drawn


func _reflip_discard() -> void:
	if state.discard_pile.size() <= 1:
		return
	var top: String = state.discard_pile.pop_back()
	# Shuffle deterministically from the round seed so server and any replay
	# agree on the order.
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + state.turn_counter * 7919 + state.discard_pile.size()
	for i in range(state.discard_pile.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := state.discard_pile[i]
		state.discard_pile[i] = state.discard_pile[j]
		state.discard_pile[j] = tmp
	state.draw_pile = state.discard_pile
	var new_discard: Array[String] = [top]
	state.discard_pile = new_discard


# --- game over -----------------------------------------------------------

func _check_game_over(events: Array) -> void:
	if state.phase != Phase.PLAYING:
		return
	if state.active_count() > 1:
		return
	if state.active_count() == 0:
		state.phase = Phase.GAME_OVER
		state.loser_index = -1
		events.append({"type": "GAME_OVER", "loser": ""})
		return
	# One player left holding cards. They lose — unless a červená-sedma
	# rescue is still open to them (then the game stays alive so they can
	# play it; drawing instead forfeits nothing but time, the window expires
	# via turn_counter).
	var sole_idx := state.next_active_index(state.current_index - 1)
	var sole := state.players[sole_idx]
	var rescue := sole.hand.has("7C")
	if rescue:
		rescue = false
		for p in state.players:
			if p != sole and _is_returnable(p):
				rescue = true
				break
	if not rescue:
		state.phase = Phase.GAME_OVER
		state.loser_index = sole_idx
		sole.finish_position = state.players.size()
		events.append({"type": "GAME_OVER", "loser": sole.id})
	else:
		state.current_index = sole_idx


func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "events": []}
