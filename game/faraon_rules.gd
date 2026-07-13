class_name FaraonRules
extends RefCounted
## Authoritative rules engine for Faraón (source: rules/faraon.pdf, Piri 2009).
## Pure logic: no scene tree, no nodes, no networking — unit-testable headless.
## The server (or the in-process local server) is the only place apply() runs;
## clients merely propose actions and render broadcast state.
##
## Documented interpretations of ambiguous PDF spots (flagged to Simon in the
## rules-engine checkpoint; adjust here if he rules otherwise):
## 1. Eso chain with 3+ players: countering with m esos clears your own stop,
##    makes you the chain owner and extends the chain by m stops
##    (pending = pending - 1 + m). When the chain dies out by passes, the
##    owner gets the free continuation turn. Matches both PDF examples.
## 2. Spálená (four of a kind) grants the extra turn only for non-eso,
##    non-sedma ranks: eso quads already continue via the chain mechanics,
##    sedma quads pass the penalty on — an extra turn would force the player
##    to answer their own sevens.
## 3. Faraón is fully neutral (PDF p.4, confirmed by Simon): it lands on
##    anything and anything lands on it — no suit declaration. Only horník
##    declares a suit.
## 4. Start card eso/sedma is validated against the deck's bottom card; a
##    horník at the bottom never validates it. Start horník takes its suit
##    from the lowest non-horník card of the deck.
## 5. Červená sedma return window: a finished player can be returned while
##    turn_counter - finished_at <= number of seated players ("same round").
##    Finishing with an eso protects from return only in a 2-player game
##    (PDF: auto-win, "výnimka pri troch a viac hráčoch").

const Status := GameState.PlayerStatus
const Phase := GameState.Phase

var state: GameState


## Starts a new round. Returns the events produced by setup.
func start(player_ids: Array, variant: RulesVariant, seed_value: int) -> Array:
	assert(player_ids.size() >= 2 and player_ids.size() <= 5)
	state = GameState.new()
	state.variant = variant
	for id in player_ids:
		var p := GameState.PlayerState.new()
		p.id = id
		state.players.append(p)

	state.rng_seed = seed_value
	state.draw_pile = FaraonDeck.shuffled(seed_value)
	var events: Array = []
	for _i in variant.initial_hand_size:
		for p in state.players:
			p.hand.append(state.draw_pile.pop_back())
	events.append({"type": "DEALT", "hand_size": variant.initial_hand_size})

	var start_card: String = state.draw_pile.pop_back()
	state.discard_pile.append(start_card)
	events.append({"type": "START_CARD", "card": start_card})
	_apply_start_card_effects(start_card, events)
	return events


func _apply_start_card_effects(card: String, events: Array) -> void:
	var bottom: String = state.draw_pile[0]
	if FaraonCard.is_eso(card) or FaraonCard.is_sedma(card):
		# Valid only when the deck's bottom card has the same rank and is not
		# a horník (a bottom horník never counts).
		if not FaraonCard.is_hornik(bottom) \
				and FaraonCard.rank_of(bottom) == FaraonCard.rank_of(card):
			if FaraonCard.is_eso(card):
				state.pending_aces = 1
				state.ace_owner_index = -1
				events.append({"type": "START_ESO_VALID"})
			else:
				state.pending_sevens_draw = 3
				events.append({"type": "START_SEDMA_VALID"})
	elif FaraonCard.is_hornik(card):
		var suit := -1
		for c in state.draw_pile: # index 0 = bottom, scan upwards
			if not FaraonCard.is_hornik(c):
				suit = FaraonCard.suit_of(c)
				break
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

	if state.pending_aces > 0:
		return _apply_eso_counter(idx, cards)

	# Červená sedma: whenever a returnable player exists, the return fires
	# automatically and deterministically (latest eliminated this round) and
	# takes priority over the plain seven penalty. Only when nobody is
	# returnable does 7C fall through to standard seven behaviour.
	if FaraonCard.rank_of(cards[0]) == FaraonCard.Rank.R7 and cards.has("7C"):
		var victim_idx := _latest_returnable_index()
		if victim_idx != -1:
			return _apply_red_seven_return(idx, cards, victim_idx)

	if state.pending_sevens_draw > 0:
		return _apply_sevens_defense(idx, cards, declared)

	# Normal play: first card must sit on the pile.
	if not _first_card_legal(cards[0]):
		return _fail("card_does_not_match")

	return _place_and_resolve(idx, cards, declared)


func _validate_cards_owned(player: GameState.PlayerState, cards: Array) -> String:
	if cards.is_empty():
		return "no_cards"
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
	if FaraonCard.is_faraon(card):
		return true # faraón lands on anything
	if FaraonCard.is_faraon(top):
		return true # ...and anything lands on the faraón (PDF p.4)
	if FaraonCard.is_hornik(card) and not state.variant.hornik_strict:
		return true
	if FaraonCard.rank_of(card) == FaraonCard.rank_of(top):
		return true
	var required_suit := state.declared_suit if state.declared_suit != -1 \
			else FaraonCard.suit_of(top)
	return FaraonCard.suit_of(card) == required_suit


func _apply_eso_counter(idx: int, cards: Array) -> Dictionary:
	# House rule: faraón cancels the whole ace chain.
	if state.variant.faraon_blocks_eso and cards.size() == 1 \
			and FaraonCard.is_faraon(cards[0]):
		state.pending_aces = 0
		state.ace_owner_index = -1
		return _place_and_resolve(idx, cards, -1)
	for c in cards:
		if not FaraonCard.is_eso(c):
			return _fail("must_answer_with_eso") # faraón is unusable vs eso
	# Countering clears the counterer's own stop, extends the chain and takes
	# over its ownership (interpretation 1 in the header).
	state.pending_aces = state.pending_aces - 1 + cards.size()
	state.ace_owner_index = -1 if state.variant.eso_round_robin else idx
	return _place_and_resolve(idx, cards, -1, true)


func _apply_sevens_defense(idx: int, cards: Array, _declared: int) -> Dictionary:
	if cards.size() == 1 and FaraonCard.is_faraon(cards[0]):
		state.pending_sevens_draw = 0 # faraón kills the whole seven chain
		return _place_and_resolve(idx, cards, -1)
	for c in cards:
		if not FaraonCard.is_sedma(c):
			return _fail("must_answer_with_sedma_or_faraon")
	return _place_and_resolve(idx, cards, -1)


## Caller guarantees: cards are all sevens including 7C, victim is returnable.
## The return ignores suit/rank matching entirely (PDF p.4).
func _apply_red_seven_return(idx: int, cards: Array, victim_idx: int) -> Dictionary:
	var victim := state.players[victim_idx]
	var player := state.players[idx]
	for c in cards:
		player.hand.erase(c)
		state.discard_pile.append(c)
	state.declared_suit = -1

	var total := state.pending_sevens_draw + 3 * cards.size()
	state.pending_sevens_draw = 0
	victim.status = Status.ACTIVE
	victim.finished_at = -1
	victim.finished_with_eso = false
	victim.finish_position = -1
	var events: Array = [{"type": "CARDS_PLAYED", "player": player.id, "cards": cards}]
	var drawn := _draw_cards(victim, total, events)
	events.append({"type": "PLAYER_RETURNED", "player": victim.id,
			"by": player.id, "drew": drawn})
	_handle_possible_finish(idx, cards, events)
	if state.phase == Phase.PLAYING:
		# Turn continues after the victim's seat (PDF: "je na ťahu hráč a až
		# potom súper" — in 2p that is the returner again).
		_advance_turn(victim_idx)
	return {"ok": true, "error": "", "events": events}


func _is_returnable(p: GameState.PlayerState) -> bool:
	if p.status != Status.FINISHED:
		return false
	if p.finished_with_eso and state.players.size() == 2:
		return false # eso finish is an untouchable win in a 2-player game
	return state.turn_counter - p.finished_at <= state.players.size()


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
		is_eso_counter: bool = false) -> Dictionary:
	var player := state.players[idx]
	var last: String = cards.back()
	var needs_declaration := FaraonCard.is_hornik(last)
	if needs_declaration and (declared < 0 or declared > 3):
		return _fail("declared_suit_required")

	for c in cards:
		player.hand.erase(c)
		state.discard_pile.append(c)
	state.declared_suit = declared if needs_declaration else -1

	var events: Array = [{"type": "CARDS_PLAYED", "player": player.id, "cards": cards}]
	if needs_declaration:
		events.append({"type": "SUIT_DECLARED", "suit": declared})

	var rank := FaraonCard.rank_of(cards[0])
	if not is_eso_counter and rank == FaraonCard.Rank.ESO:
		state.pending_aces = cards.size()
		state.ace_owner_index = -1 if state.variant.eso_round_robin else idx
	elif rank == FaraonCard.Rank.R7:
		state.pending_sevens_draw += 3 * cards.size()

	var finished := _handle_possible_finish(idx, cards, events)
	if state.phase != Phase.PLAYING:
		return {"ok": true, "error": "", "events": events}

	var spalena := cards.size() == 4 \
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
		state.extra_turns -= 1 # banked spálená move consumed, stay on turn
	else:
		_advance_turn(idx)
	return {"ok": true, "error": "", "events": events}


## Moves the turn to the next active player and clears per-streak state.
func _advance_turn(from_idx: int) -> void:
	state.extra_turns = 0
	state.spalena_chain = 0
	state.current_index = state.next_active_index(from_idx)


## Marks the player finished when their hand emptied. Returns true if so.
func _handle_possible_finish(idx: int, cards: Array, events: Array) -> bool:
	var player := state.players[idx]
	if not player.hand.is_empty():
		return false
	player.status = Status.FINISHED
	player.finished_at = state.turn_counter
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
	var amount: int = state.pending_sevens_draw if state.pending_sevens_draw > 0 else 1
	state.pending_sevens_draw = 0
	var events: Array = []
	var drawn := _draw_cards(player, amount, events)
	events.append({"type": "DREW", "player": player.id, "count": drawn,
			"penalty": amount > 1})
	if drawn == 0:
		events.append({"type": "DECK_EXHAUSTED", "player": player.id})
	_advance_turn(idx)
	return {"ok": true, "error": "", "events": events}


func _apply_pass(idx: int) -> Dictionary:
	if state.pending_aces <= 0:
		return _fail("nothing_to_pass")
	state.pending_aces -= 1
	var events: Array = [{"type": "STOPPED", "player": state.players[idx].id}]
	if state.pending_aces == 0:
		var owner := state.ace_owner_index
		state.ace_owner_index = -1
		if owner != -1 and state.players[owner].status == Status.ACTIVE:
			_advance_turn(idx)
			state.current_index = owner # free continuation for the chain owner
			events.append({"type": "ESO_CONTINUATION", "player": state.players[owner].id})
		else:
			_advance_turn(idx)
	else:
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
