class_name BotStrategy
extends RefCounted
## Difficulty-aware bot brain (implements architecture/bot_strategy_proposal.md,
## approved). Pure logic, unit-testable, architecturally separate from the
## rules engine: it reads only its own hand plus public state and proposes
## actions through the same FaraonActions interface as a human client — the
## engine never knows a bot is playing.
##
## Decision principle: every legal candidate move gets a score
##   score = w_size * cards shed
##         + w_block * blocking value (eso/sedma vs an opponent close to winning)
##         + w_save  * cost of spending a special card without need (negative)
##         + w_suit  * hand suit-balancing / continuation steering
##         + w_memory* card-counting estimate (HARD only)
##         + noise   * randf() (EASY high, HARD ~0)
## and the best one is played. Difficulty gates which components are active.

enum Difficulty { EASY, MEDIUM, HARD }

## Tuning knobs per difficulty — the only place to touch when adjusting how
## "smart" each level feels. noise >> other weights makes EASY effectively a
## random legal move. save is capped below DRAW_SCORE's magnitude so a bot
## never hoards specials when a special is its only playable card.
const WEIGHTS := {
	Difficulty.EASY: {
		"size": 1.0, "save": 0.0, "block": 0.0, "suit": 0.0,
		"memory": 0.0, "noise": 25.0,
	},
	Difficulty.MEDIUM: {
		"size": 1.0, "save": 1.2, "block": 3.0, "suit": 0.4,
		"memory": 0.0, "noise": 0.6,
	},
	Difficulty.HARD: {
		"size": 1.0, "save": 1.4, "block": 5.0, "suit": 0.6,
		"memory": 2.0, "noise": 0.0,
	},
}

## Score of drawing a card voluntarily; any playable group should normally
## beat it, but a HARD bot may draw to keep a lone special for a key moment.
const DRAW_SCORE := -2.0

var difficulty: int = Difficulty.MEDIUM
var memory := CardMemory.new() # only HARD weights it into scores
var _rng := RandomNumberGenerator.new()


func _init(diff: int = Difficulty.MEDIUM, seed_value: int = 0) -> void:
	difficulty = diff
	if seed_value != 0:
		_rng.seed = seed_value # deterministic runs for tests/replays


static func difficulty_from_string(s: String) -> int:
	match s:
		"easy": return Difficulty.EASY
		"hard": return Difficulty.HARD
		_: return Difficulty.MEDIUM


## Picks an action Dictionary (FaraonActions.*) for player `id`.
func choose(state: GameState, id: String) -> Dictionary:
	var me := state.player_by_id(id)
	var w: Dictionary = WEIGHTS[difficulty]
	memory.update(state)

	# Paused penalty draw with the faraón in hand: cancelling the rest of
	# the penalty is a clear tactical win — MEDIUM and HARD always take it;
	# EASY keeps grinding cards, consistent with its non-strategic profile.
	if state.penalty_interrupt:
		if difficulty == Difficulty.EASY:
			return FaraonActions.draw()
		return FaraonActions.play(["DE"])

	# Forced answers first: an open eso chain allows only eso/pass (faraón
	# with the house rule). Countering both clears our stop and passes it on
	# — strictly better than standing at every difficulty.
	if state.pending_aces > 0:
		var esos := _cards_of_rank(me.hand, FaraonCard.Rank.ESO)
		if not esos.is_empty():
			return FaraonActions.play(esos)
		if state.variant.faraon_blocks_eso and me.hand.has("DE"):
			return FaraonActions.play(["DE"])
		return FaraonActions.pass_turn()

	if state.pending_sevens_draw > 0:
		return _choose_sevens_defense(state, me, w)

	# Sole survivor: the červená sedma rescue is the only way not to lose on
	# the spot — every difficulty takes it (the engine picks the victim).
	if state.active_count() == 1 and me.hand.has("7C") \
			and _has_returnable_target(state, me):
		return FaraonActions.play(_cards_of_rank(me.hand, FaraonCard.Rank.R7))

	return _choose_normal_play(state, me, w)


# --- candidate scoring ------------------------------------------------------

func _choose_sevens_defense(state: GameState, me: GameState.PlayerState,
		w: Dictionary) -> Dictionary:
	var candidates: Array = []
	var sevens := _cards_of_rank(me.hand, FaraonCard.Rank.R7)
	if not sevens.is_empty():
		# Passing the grown penalty on is nearly always right.
		candidates.append({"action": FaraonActions.play(sevens),
				"score": 3.0 + w.size * sevens.size()
						+ _block_bonus(state, me, FaraonCard.Rank.R7, w)})
	if me.hand.has("DE"):
		# Killing the chain saves us the draw but burns the wild.
		candidates.append({"action": FaraonActions.play(["DE"]),
				"score": state.pending_sevens_draw * 0.4 - w.save * 1.0})
	candidates.append({"action": FaraonActions.draw(),
			"score": -0.2 * state.pending_sevens_draw})
	return _pick(candidates, w)


func _choose_normal_play(state: GameState, me: GameState.PlayerState,
		w: Dictionary) -> Dictionary:
	var candidates: Array = [{"action": FaraonActions.draw(), "score": DRAW_SCORE}]

	var by_rank := {}
	for c in me.hand:
		var r := FaraonCard.rank_of(c)
		if not by_rank.has(r):
			by_rank[r] = []
		by_rank[r].append(c)

	for r in by_rank:
		var group: Array = by_rank[r]
		if r == FaraonCard.Rank.HORNIK and not state.variant.hornik_strict:
			continue # loose horník handled as the wildcard fallback below
		var ordered := _ordered_group(state, me, group)
		if ordered.is_empty():
			continue
		_add_play_candidate(candidates, state, me, ordered, w)
		# HARD holds the faraón back when the dolník group works without it.
		if difficulty == Difficulty.HARD and ordered.has("DE") and ordered.size() > 1:
			var without: Array = ordered.filter(func(c): return c != "DE")
			if not without.is_empty() and _opener_legal(state, without[0]):
				_add_play_candidate(candidates, state, me, without, w)

	# Wildcard fallbacks: loose horník changes the suit, faraón lands anywhere.
	if not state.variant.hornik_strict:
		for c in me.hand:
			if FaraonCard.is_hornik(c) and not _has_group_of(candidates, c):
				candidates.append({"action": FaraonActions.play([c], _best_suit(me.hand, [c])),
						"score": w.size - w.save * 0.8 + _noise(w)})
				break
	if me.hand.has("DE") and not _has_group_of(candidates, "DE"):
		candidates.append({"action": FaraonActions.play(["DE"]),
				"score": w.size - w.save * 1.0 + _noise(w)})

	return _pick(candidates, w)


func _add_play_candidate(candidates: Array, state: GameState,
		me: GameState.PlayerState, ordered: Array, w: Dictionary) -> void:
	var r := FaraonCard.rank_of(ordered[0])
	var score: float = w.size * float(ordered.size())
	score += _special_save_penalty(ordered, w)
	score += _block_bonus(state, me, r, w) if _is_special_rank(r) else 0.0
	score += _memory_bonus(state, me, r, w)
	# Suit steering: keeping cards of the suit we leave on top helps the
	# follow-up turn (and empties the biggest suit stack first).
	var last: String = ordered.back()
	if not FaraonCard.is_hornik(last):
		var kept := 0
		for c in me.hand:
			if not ordered.has(c) and FaraonCard.suit_of(c) == FaraonCard.suit_of(last):
				kept += 1
		score += w.suit * kept
	var declared := -1
	if FaraonCard.is_hornik(last):
		declared = _best_suit(me.hand, ordered)
	candidates.append({"action": FaraonActions.play(ordered, declared),
			"score": score + _noise(w)})


## Negative score for spending esá/sedmy/faraón/7C without tactical need;
## the block/memory bonuses compensate when spending them IS the tactic.
func _special_save_penalty(cards: Array, w: Dictionary) -> float:
	var penalty := 0.0
	for c in cards:
		if FaraonCard.is_red_sedma(c):
			penalty -= w.save * 1.2 # the rescue card is the most precious
		elif FaraonCard.is_eso(c) or FaraonCard.is_sedma(c):
			penalty -= w.save * 0.8
		elif FaraonCard.is_faraon(c):
			penalty -= w.save * 1.0
	return penalty


## Bonus for aiming an eso stop / sedma penalty at an opponent who is close
## to going out. MEDIUM sees the obvious case; HARD weighs it stronger and
## only when the next active player really is the threat.
func _block_bonus(state: GameState, me: GameState.PlayerState, rank: int,
		w: Dictionary) -> float:
	if w.block == 0.0:
		return 0.0
	var next_idx := state.next_active_index(state.index_of(me.id))
	if next_idx == -1:
		return 0.0
	var next_hand := state.players[next_idx].hand.size()
	var threat := 99
	for p in state.players:
		if p != me and p.status == GameState.PlayerStatus.ACTIVE:
			threat = mini(threat, p.hand.size())
	if threat > 2:
		return 0.0
	if difficulty == Difficulty.HARD and next_hand > 2 \
			and rank == FaraonCard.Rank.R7:
		return 0.0 # the sedma penalty would land on the wrong player
	return w.block * float(3 - threat)


## HARD only: the fewer copies of the rank opponents can still hold, the
## safer it is to commit our own (an eso nobody can counter is a free stop).
func _memory_bonus(state: GameState, me: GameState.PlayerState, rank: int,
		w: Dictionary) -> float:
	if w.memory == 0.0 or not _is_special_rank(rank):
		return 0.0
	var unseen := memory.unseen_of_rank(rank, me.hand)
	return w.memory * (1.0 - clampf(unseen / 3.0, 0.0, 1.0))


func _is_special_rank(r: int) -> bool:
	return r == FaraonCard.Rank.ESO or r == FaraonCard.Rank.R7


func _noise(w: Dictionary) -> float:
	return _rng.randf() * w.noise


func _pick(candidates: Array, _w: Dictionary) -> Dictionary:
	var best: Dictionary = candidates[0]
	for c in candidates:
		if c.score > best.score:
			best = c
	return best.action


# --- move construction (shared legality helpers) ---------------------------

func _cards_of_rank(hand: Array, rank: int) -> Array:
	var out: Array = []
	for c in hand:
		if FaraonCard.rank_of(c) == rank:
			out.append(c)
	return out


func _has_returnable_target(state: GameState, me: GameState.PlayerState) -> bool:
	for p in state.players:
		if p == me or p.status != GameState.PlayerStatus.FINISHED:
			continue
		if p.finished_with_eso and state.players.size() == 2:
			continue
		if state.turn_counter - p.finished_at <= state.players.size():
			return true
	return false


func _opener_legal(state: GameState, card: String) -> bool:
	var top := state.top_card()
	if FaraonCard.is_faraon(card) or FaraonCard.is_faraon(top):
		return true
	if FaraonCard.is_hornik(card) and not state.variant.hornik_strict:
		return true
	if FaraonCard.rank_of(card) == FaraonCard.rank_of(top):
		return true
	var required := state.declared_suit if state.declared_suit != -1 \
			else FaraonCard.suit_of(top)
	return FaraonCard.suit_of(card) == required


## Orders one same-rank group so a legal card opens, the faraón stays off the
## last slot, and the closing card's suit is the one we hold most of (turn
## continuation steering). Empty result = the group cannot open on the pile.
func _ordered_group(state: GameState, me: GameState.PlayerState,
		group: Array) -> Array:
	var opener := ""
	for c in group:
		if FaraonCard.is_faraon(c):
			continue
		if _opener_legal(state, c):
			opener = c
			break
	if opener == "" and group.has("DE"):
		opener = "DE"
	if opener == "":
		return []
	var rest: Array = group.filter(func(c): return c != opener)
	# Close on the suit we keep the most of; keep DE away from the last slot.
	rest.sort_custom(func(a, b):
		if FaraonCard.is_faraon(a) != FaraonCard.is_faraon(b):
			return FaraonCard.is_faraon(a) # DE first among the rest
		return _suit_count(me.hand, group, a) < _suit_count(me.hand, group, b))
	return [opener] + rest


func _suit_count(hand: Array, played: Array, card: String) -> int:
	var n := 0
	for c in hand:
		if not played.has(c) and FaraonCard.suit_of(c) == FaraonCard.suit_of(card):
			n += 1
	return n


func _has_group_of(candidates: Array, card: String) -> bool:
	for c in candidates:
		var cards: Array = c.action.get("cards", [])
		if cards.has(card):
			return true
	return false


## Most common suit among the cards kept after playing `played`.
func _best_suit(hand: Array, played: Array) -> int:
	var counts := [0, 0, 0, 0]
	for c in hand:
		if not played.has(c):
			counts[FaraonCard.suit_of(c)] += 1
	var best := 0
	for s in 4:
		if counts[s] > counts[best]:
			best = s
	return best
