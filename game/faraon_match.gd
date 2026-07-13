class_name FaraonMatch
extends RefCounted
## Meta-game layer above single rounds for the Olympic modes. The rules
## engine stays strictly per-round — this class only decides who plays the
## next round and with how many cards.
##
## OLYMPIC (rules/faraon.pdf): the round loser starts the next round with one
## card fewer; at 0 cards the player drops out of the match. The last player
## still holding an allotment wins the match.
## REVERSE_OLYMPIC (Simon's house mode): the round WINNER sheds one card
## instead; the first player whose allotment reaches 0 wins the match.

enum Mode { NORMAL, OLYMPIC, REVERSE_OLYMPIC }

const START_SIZE := 5

var mode: int = Mode.OLYMPIC
## player id -> cards dealt to them next round; 0 = out of the match
## (OLYMPIC) or already victorious (REVERSE_OLYMPIC).
var allotments := {}
var round_number := 1
var finished := false
## Winner of the whole match ("" while running).
var champion := ""


func _init(p_mode: int, player_ids: Array) -> void:
	mode = p_mode
	for id in player_ids:
		allotments[id] = START_SIZE


## Ids that play the next round (allotment above zero).
func participants() -> Array:
	var out: Array = []
	for id in allotments:
		if allotments[id] > 0:
			out.append(id)
	return out


## Per-player hand sizes for FaraonRules.start().
func hand_sizes() -> Dictionary:
	var out := {}
	for id in participants():
		out[id] = allotments[id]
	return out


## Applies one finished round. Returns {loser/winner id, eliminated: Array,
## champion: String} describing what changed for the result screen.
func apply_round_result(state: GameState) -> Dictionary:
	round_number += 1
	var result := {"eliminated": [], "champion": ""}
	match mode:
		Mode.OLYMPIC:
			var last := state.players.size()
			for p in state.players:
				if p.finish_position == last:
					result["loser"] = p.id
					allotments[p.id] -= 1
					if allotments[p.id] <= 0:
						result["eliminated"].append(p.id)
			if participants().size() <= 1:
				finished = true
				champion = participants()[0] if participants().size() == 1 else ""
		Mode.REVERSE_OLYMPIC:
			for p in state.players:
				if p.finish_position == 1:
					result["winner"] = p.id
					allotments[p.id] -= 1
					if allotments[p.id] <= 0:
						finished = true
						champion = p.id
	result["champion"] = champion
	return result
