class_name FaraonActions
extends RefCounted
## Action vocabulary shared by engine and networking. A move travels as one
## atomic Dictionary; the server feeds it to FaraonRules.apply() and
## broadcasts the resulting state. Clients only ever *propose* these.

const PLAY_CARDS := "PLAY_CARDS"
const DRAW := "DRAW"
const PASS := "PASS" # only legal answer to an open eso chain besides playing esos


static func play(cards: Array, declared_suit: int = -1, return_player: String = "") -> Dictionary:
	return {
		"action": PLAY_CARDS,
		"cards": cards,
		"declared_suit": declared_suit,
		"return_player": return_player,
	}


static func draw() -> Dictionary:
	return {"action": DRAW}


static func pass_turn() -> Dictionary:
	return {"action": PASS}
