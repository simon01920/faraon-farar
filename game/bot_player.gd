class_name BotPlayer
extends RefCounted
## Simple legal-move AI used for local play. Pure logic (unit-testable).
## It only reads its own hand plus public state — never other hands — so the
## same brain can later run server-side for "fill with bots" in multiplayer.


## Picks an action Dictionary (FaraonActions.*) for player `id`.
func choose(state: GameState, id: String) -> Dictionary:
	var me := state.player_by_id(id)

	if state.pending_aces > 0:
		var esos := _cards_of_rank(me.hand, FaraonCard.Rank.ESO)
		if not esos.is_empty():
			return FaraonActions.play(esos)
		if state.variant.faraon_blocks_eso and me.hand.has("DE"):
			return FaraonActions.play(["DE"])
		return FaraonActions.pass_turn()

	if state.pending_sevens_draw > 0:
		var sevens := _cards_of_rank(me.hand, FaraonCard.Rank.R7)
		if not sevens.is_empty():
			return FaraonActions.play(sevens)
		if me.hand.has("DE"):
			return FaraonActions.play(["DE"])
		return FaraonActions.draw()

	# Sole survivor: burn the červená sedma rescue if it exists — the engine
	# returns the latest eliminated player automatically.
	if state.active_count() == 1 and me.hand.has("7C") \
			and _has_returnable_target(state, me):
		var sevens := _cards_of_rank(me.hand, FaraonCard.Rank.R7)
		return FaraonActions.play(sevens)

	var group := _best_playable_group(state, me.hand)
	if not group.is_empty():
		var last: String = group.back()
		var declared := -1
		if FaraonCard.is_hornik(last):
			declared = _best_suit(me.hand, group)
		return FaraonActions.play(group, declared)

	return FaraonActions.draw()


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


## Largest same-rank group that can legally open on the current top card,
## ordered so the first card matches and specials sit last only when needed.
## Saves faraón/horník for when nothing plain is playable.
func _best_playable_group(state: GameState, hand: Array) -> Array:
	var top := state.top_card()
	var required_suit := state.declared_suit if state.declared_suit != -1 \
			else FaraonCard.suit_of(top)
	var top_is_neutral := FaraonCard.is_faraon(top)

	var by_rank := {}
	for c in hand:
		var r := FaraonCard.rank_of(c)
		if not by_rank.has(r):
			by_rank[r] = []
		by_rank[r].append(c)

	var best: Array = []
	for r in by_rank:
		var group: Array = by_rank[r]
		if r == FaraonCard.Rank.HORNIK and not state.variant.hornik_strict:
			continue # loose horník is the fallback below, don't waste a group
		var opener := ""
		for c in group:
			if FaraonCard.is_faraon(c):
				continue # prefer opening with a plain card
			if top_is_neutral or r == FaraonCard.rank_of(top) \
					or FaraonCard.suit_of(c) == required_suit:
				opener = c
				break
		if opener == "" and group.any(func(c): return FaraonCard.is_faraon(c)):
			opener = "DE" # wild opener admits the rest of the dolník group
		if opener == "":
			continue
		var ordered: Array = [opener]
		for c in group:
			if c != opener:
				ordered.append(c)
		if ordered.size() > best.size():
			best = ordered

	if best.is_empty():
		if not state.variant.hornik_strict:
			for c in hand:
				if FaraonCard.is_hornik(c):
					return [c]
		if hand.has("DE"):
			return ["DE"]
	return best


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
