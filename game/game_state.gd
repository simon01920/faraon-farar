class_name GameState
extends RefCounted
## Plain data container for one round of Faraón. No scene-tree, no networking
## — fully serializable so the server can snapshot/broadcast it and clients
## can rebuild a censored view ([method view_for]).

enum PlayerStatus { ACTIVE, FINISHED }
enum Phase { PLAYING, GAME_OVER }


class PlayerState:
	extends RefCounted
	var id: String
	var hand: Array[String] = []
	var status: int = PlayerStatus.ACTIVE
	## turn_counter value when this player emptied their hand (-1 = never).
	## Used for the červená-sedma "same round" return window.
	var finished_at: int = -1
	## Počet odovzdaní ťahu (handovers) v momente vypadnutia — meria
	## „aktuálne kolo" pre návrat červenou sedmou nezávisle od toho, koľko
	## akcií jeden ťah zabral (trestné ťahanie s pauzou = viac akcií).
	var finished_at_handover: int = -1
	## True when the hand was emptied with an eso as (part of) the last play.
	var finished_with_eso: bool = false
	## Final placement for this round: 1 = first to finish (the only win),
	## players.size() = the loser; -1 = still playing. Cleared again when a
	## červená sedma returns the player. Pure data output of one game —
	## groundwork for the future scoring system.
	var finish_position: int = -1

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"hand": hand.duplicate(),
			"status": status,
			"finished_at": finished_at,
			"finished_at_handover": finished_at_handover,
			"finished_with_eso": finished_with_eso,
			"finish_position": finish_position,
		}

	static func from_dict(d: Dictionary) -> PlayerState:
		var p := PlayerState.new()
		p.id = d.get("id", "")
		p.hand.assign(d.get("hand", []))
		p.status = d.get("status", PlayerStatus.ACTIVE)
		p.finished_at = d.get("finished_at", -1)
		p.finished_at_handover = d.get("finished_at_handover", -1)
		p.finished_with_eso = d.get("finished_with_eso", false)
		p.finish_position = d.get("finish_position", -1)
		return p


var players: Array[PlayerState] = []
## Draw pile; LAST element is the top (pop_back to draw), index 0 is the
## physical bottom card (used by the start-card rules).
var draw_pile: Array[String] = []
## Discard pile; LAST element is the visible top card.
var discard_pile: Array[String] = []
var current_index: int = 0
## Suit forced by horník/faraón declaration; -1 = none (top card's own suit
## applies). Also -1 after a start-card faraón, where anything is playable.
var declared_suit: int = -1
## Total penalty cards accumulated by unanswered sedmas (3 per sedma).
var pending_sevens_draw: int = 0
## True while a penalty draw is paused because the player just drew the
## faraón (D5) or a seven (D4): they may play that card or keep drawing.
var penalty_interrupt: bool = false
## The exact card that paused the penalty draw ("" = none).
var interrupt_card: String = ""
## D13: the pending draw was sealed by a red ten — no further defense.
var pending_hard_penalty: bool = false
## Remaining players to be stopped by the open eso chain (0 = no chain).
## A2: stops only skip players in seating order — no continuation owner.
var pending_aces: int = 0
## D7/D15: smer hry (1 = v smere hodinových ručičiek, -1 = proti).
var direction: int = 1
## D11: ohlásená hodnota po vyložení spodka-meniča (-1 = žiadna).
var announced_rank: int = -1
var phase: int = Phase.PLAYING
var loser_index: int = -1
## Increments after every completed action; timestamps player finishes.
var turn_counter: int = 0
## Increments každým odovzdaním ťahu ďalšiemu hráčovi. Na rozdiel od
## turn_counter je nezávislé od počtu akcií v jednom ťahu, takže z neho vieme
## presne zmerať „jedno kolo" = jeden obeh stola (D8 rozsah návratu).
var handovers: int = 0
## Extra moves banked by spálená that the current player may still take.
var extra_turns: int = 0
## Consecutive spálená count within the current player's streak (for the
## spalena_multiply house rule).
var spalena_chain: int = 0
## Seed captured at start(); reflip shuffles derive from it deterministically.
var rng_seed: int = 0
var variant: RulesVariant = RulesVariant.classic()


func player_by_id(id: String) -> PlayerState:
	for p in players:
		if p.id == id:
			return p
	return null


func index_of(id: String) -> int:
	for i in players.size():
		if players[i].id == id:
			return i
	return -1


func active_count() -> int:
	var n := 0
	for p in players:
		if p.status == PlayerStatus.ACTIVE:
			n += 1
	return n


## Next ACTIVE player index strictly after i in the current play direction
## (wraps). Returns i itself only if it is the sole active player; -1 when
## nobody is active.
func next_active_index(i: int) -> int:
	for step in range(1, players.size() + 1):
		var j := posmod(i + step * direction, players.size())
		if players[j].status == PlayerStatus.ACTIVE:
			return j
	return -1


## Môže červená sedma vrátiť tohto hráča do hry? Jediný zdroj pravdy pre
## engine aj botov (D8): „round" = vypadol v AKTUÁLNOM kole, teda od jeho
## vypadnutia ešte neprebehol celý obeh stola (každý zostávajúci aktívny hráč
## dostal nanajvýš jeden ťah); „anyone" = hocikto od začiatku hry.
func is_returnable(p: PlayerState) -> bool:
	if p.status != PlayerStatus.FINISHED:
		return false
	if p.finished_with_eso and players.size() == 2:
		return false # ukončenie esom je v 2-hráčovej hre nedotknuteľná výhra
	if variant.red7_return_scope != "round":
		return true
	if p.finished_at_handover == -1:
		return false # neznámy čas vypadnutia (starý snapshot) = mimo kola
	return handovers - p.finished_at_handover <= active_count()


func top_card() -> String:
	return discard_pile.back() if not discard_pile.is_empty() else ""


func to_dict() -> Dictionary:
	var ps: Array = []
	for p in players:
		ps.append(p.to_dict())
	return {
		"players": ps,
		"draw_pile": draw_pile.duplicate(),
		"discard_pile": discard_pile.duplicate(),
		"current_index": current_index,
		"declared_suit": declared_suit,
		"pending_sevens_draw": pending_sevens_draw,
		"penalty_interrupt": penalty_interrupt,
		"interrupt_card": interrupt_card,
		"pending_hard_penalty": pending_hard_penalty,
		"pending_aces": pending_aces,
		"direction": direction,
		"announced_rank": announced_rank,
		"phase": phase,
		"loser_index": loser_index,
		"turn_counter": turn_counter,
		"handovers": handovers,
		"extra_turns": extra_turns,
		"spalena_chain": spalena_chain,
		"rng_seed": rng_seed,
		"variant": variant.to_dict(),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	for pd in d.get("players", []):
		s.players.append(PlayerState.from_dict(pd))
	s.draw_pile.assign(d.get("draw_pile", []))
	s.discard_pile.assign(d.get("discard_pile", []))
	s.current_index = d.get("current_index", 0)
	s.declared_suit = d.get("declared_suit", -1)
	s.pending_sevens_draw = d.get("pending_sevens_draw", 0)
	s.penalty_interrupt = d.get("penalty_interrupt", false)
	s.interrupt_card = d.get("interrupt_card", "")
	s.pending_hard_penalty = d.get("pending_hard_penalty", false)
	s.pending_aces = d.get("pending_aces", 0)
	s.direction = d.get("direction", 1)
	s.announced_rank = d.get("announced_rank", -1)
	s.phase = d.get("phase", Phase.PLAYING)
	s.loser_index = d.get("loser_index", -1)
	s.turn_counter = d.get("turn_counter", 0)
	s.handovers = d.get("handovers", 0)
	s.extra_turns = d.get("extra_turns", 0)
	s.spalena_chain = d.get("spalena_chain", 0)
	s.rng_seed = d.get("rng_seed", 0)
	s.variant = RulesVariant.from_dict(d.get("variant", {}))
	return s


## Censored snapshot for one client: other hands become counts, the draw pile
## becomes a count. This is the ONLY form of state a client may ever receive.
func view_for(viewer_id: String) -> Dictionary:
	var d := to_dict()
	d["draw_pile_count"] = draw_pile.size()
	d.erase("draw_pile")
	for pd in d["players"]:
		pd["hand_count"] = pd["hand"].size()
		if pd["id"] != viewer_id:
			pd.erase("hand")
	return d
