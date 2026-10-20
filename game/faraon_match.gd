class_name FaraonMatch
extends RefCounted
## Meta-vrstva nad jednotlivými kolami pre olympijské režimy. Rules engine
## ostáva striktne per-kolo — táto trieda rozhoduje, kto hrá, s koľkými
## kartami a kto začína.
##
## B2 — rozstrely: jedno bodovacie KOLO sa skladá zo série sub-kôl. Prvé
## sub-kolo hrajú všetci účastníci a končí prvým dohratým hráčom (1. miesto
## kola); zvyšní hrajú rozstrelové sub-kolá o ďalšie miesta, až kým neostane
## posledný (posledné miesto). Až potom sa kolo boduje:
##   OLYMPIC: posledný v kole začína ďalšie kolo s kartou menej; na nule
##   vypadáva zo zápasu; vyhráva posledný s prídelom.
##   REVERSE_OLYMPIC: víťaz kola zhadzuje kartu; kto prvý dosiahne nulu,
##   vyhráva zápas.
## B1 — štartér: prvé kolo určí RNG (meta podľa obtiažnosti/multiplayer
## ekviprobabilne — rieši volajúci), ďalšie kolá rotujú v smere hodinových
## ručičiek podľa poradia sedenia. Rozstrelové sub-kolá rotujú tiež.

enum Mode { NORMAL, OLYMPIC, REVERSE_OLYMPIC }

## Predvolený prídel, keď volajúci nedá veľkosť ruky z pravidiel (D2).
const START_SIZE := 5

var mode: int = Mode.OLYMPIC
## id -> prídel kariet do ďalšieho kola; 0 = mimo zápasu (OLYMPIC) alebo
## už víťaz (REVERSE_OLYMPIC).
var allotments := {}
var round_number := 1
var finished := false
var champion := ""
## Pevné poradie sedenia z prvého kola (základ rotácie).
var seat_order: Array = []
## Štartér aktuálneho kola (prvého sub-kola).
var starter_id := ""
## Štartér najbližšieho sub-kola (rotuje v rámci rozstrelov).
var sub_starter_id := ""
## Umiestnenia zbierané v prebiehajúcom kole (idčka v poradí dohrania).
var kolo_placements: Array = []


## `start_size` = prídel prvého kola; volajúci odovzdáva
## variant.initial_hand_size (D2), aby prvé sub-kolo, rozstrely aj ďalšie
## kolá vychádzali z rovnakej veľkosti ruky.
func _init(p_mode: int, player_ids: Array, first_starter := "",
		start_size: int = START_SIZE) -> void:
	mode = p_mode
	seat_order = player_ids.duplicate()
	for id in player_ids:
		allotments[id] = start_size
	starter_id = first_starter if player_ids.has(first_starter) else player_ids[0]
	sub_starter_id = starter_id


## Účastníci zápasu (prídel > 0).
func participants() -> Array:
	var out: Array = []
	for id in seat_order:
		if allotments.get(id, 0) > 0:
			out.append(id)
	return out


## Hráči najbližšieho sub-kola: účastníci bez už umiestnených v tomto kole.
func sub_round_players() -> Array:
	var out: Array = []
	for id in participants():
		if not kolo_placements.has(id):
			out.append(id)
	return out


## Per-hráč veľkosti rúk pre FaraonRules.start().
func hand_sizes() -> Dictionary:
	var out := {}
	for id in sub_round_players():
		out[id] = allotments[id]
	return out


## Index štartéra sub-kola v poli sub_round_players().
func sub_start_index() -> int:
	var players := sub_round_players()
	var i := players.find(sub_starter_id)
	return maxi(i, 0)


## Ďalší v smere hodinových ručičiek od `from_id` v rámci `pool`.
func _next_clockwise(from_id: String, pool: Array) -> String:
	if pool.is_empty():
		return from_id
	var start := seat_order.find(from_id)
	for step in range(1, seat_order.size() + 1):
		var cand: String = seat_order[(start + step) % seat_order.size()]
		if pool.has(cand):
			return cand
	return pool[0]


## Spracuje dohrané sub-kolo. Vracia {kolo_done, shootout: Array (hráči
## ďalšieho rozstrelu), eliminated, champion, placements}.
func on_sub_round_over(state: GameState) -> Dictionary:
	# Prvý dohratý hráč sub-kola berie najbližšie voľné miesto kola.
	var order := state.players.duplicate()
	order.sort_custom(func(a, b):
		var pa: int = a.finish_position if a.finish_position != -1 else 99
		var pb: int = b.finish_position if b.finish_position != -1 else 99
		return pa < pb)
	for p in order:
		if p.finish_position != -1 and not kolo_placements.has(p.id):
			kolo_placements.append(p.id)
	var left := sub_round_players()
	var result := {"kolo_done": false, "shootout": [], "eliminated": [],
			"champion": "", "placements": kolo_placements.duplicate()}
	if left.size() >= 2:
		# Rozstrel o ďalšie miesto; štartér rotuje v rámci zvyšku.
		sub_starter_id = _next_clockwise(sub_starter_id, left)
		result["shootout"] = left
		return result
	if left.size() == 1:
		kolo_placements.append(left[0]) # posledné miesto bez hrania
	result["placements"] = kolo_placements.duplicate()
	result["kolo_done"] = true
	_score_kolo(result)
	return result


func _score_kolo(result: Dictionary) -> void:
	round_number += 1
	match mode:
		Mode.OLYMPIC:
			var loser: String = kolo_placements.back()
			result["loser"] = loser
			allotments[loser] -= 1
			if allotments[loser] <= 0:
				result["eliminated"].append(loser)
			if participants().size() <= 1:
				finished = true
				champion = participants()[0] if participants().size() == 1 else ""
		Mode.REVERSE_OLYMPIC:
			var winner: String = kolo_placements.front()
			result["winner"] = winner
			allotments[winner] -= 1
			if allotments[winner] <= 0:
				finished = true
				champion = winner
	# B1: štartér ďalšieho kola rotuje v smere hodinových ručičiek.
	starter_id = _next_clockwise(starter_id, participants())
	sub_starter_id = starter_id
	kolo_placements.clear()
	result["champion"] = champion
