class_name CardMemory
extends RefCounted
## Public-information card counting for the HARD bot. What is provably out of
## circulation is exactly the discard pile, so the memory is recomputed from
## the state before every decision — a reflip (discard shuffled back into the
## draw pile) then "forgets" those cards automatically, which is correct:
## they are back in play. Never reads hidden information (no hands, no draw
## pile order), so the same brain can run server-side in multiplayer.

## Cards visible in the discard pile right now, by rank (index = FaraonCard.Rank).
var seen_by_rank: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]


func update(state: GameState) -> void:
	for i in seen_by_rank.size():
		seen_by_rank[i] = 0
	for c in state.discard_pile:
		seen_by_rank[FaraonCard.rank_of(c)] += 1


## How many cards of `rank` could still be in opponents' hands or the draw
## pile: 4 per rank, minus the visible discard, minus my own.
func unseen_of_rank(rank: int, my_hand: Array) -> int:
	var mine := 0
	for c in my_hand:
		if FaraonCard.rank_of(c) == rank:
			mine += 1
	return 4 - seen_by_rank[rank] - mine
