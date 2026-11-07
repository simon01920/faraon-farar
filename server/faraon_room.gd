class_name FaraonRoom
extends RefCounted
## One multiplayer room: lobby membership, seats, the authoritative rules
## engine, reconnect grace and per-peer censored broadcasts. Deliberately
## TRANSPORT-FREE: instead of touching the multiplayer API it appends
## {peer, fn, args} entries to `outbox`, which the NetHub drains and sends —
## that keeps every room behaviour unit-testable without a socket.
##
## Identity: each member gets a random session token at join. A reconnecting
## client presents the token and the seat (hand, turn order) rebinds to the
## new peer id — the seat survives NetProtocol.RECONNECT_GRACE_SEC offline.

enum Phase { LOBBY, PLAYING }

## Safety net for the absent-seat autopilot: no single trigger may apply more
## engine actions than this (a draw-only table can never loop forever).
const MAX_AUTOPLAY_STEPS := 400

var code: String
var phase: int = Phase.LOBBY
## Seat records: {token, name, seat, peer, connected, disconnected_at}.
## Seat ids are "S1".."S5" and double as rules-engine player ids.
var members: Array = []
var rules: FaraonRules
var variant: RulesVariant
## Drained by the transport layer: {peer: int, fn: String, args: Array}.
var outbox: Array = []
## Živý stôl: seat -> počet práve označených kariet. Čisto kozmetický,
## efemérny stav MIMO rules enginu — nevaliduje sa, neukladá do GameState;
## čistí sa pri každej aplikovanej akcii, odpojení a štarte kola.
var selections := {}

var _rng := RandomNumberGenerator.new()
## Mená sediacich v bežiacej hre (seat -> meno) — hráč, ktorý počas hry
## odišiel, už nie je v `members`, no súperi ho musia stále vidieť po mene.
var _seat_names := {}
## Shared with the RoomManager: `_push` marks this room as having pending
## output so the hub drains only touched rooms (null for standalone rooms).
var _dirty_sink = null


func _init(p_code: String, seed_value: int = 0) -> void:
	code = p_code
	if seed_value != 0:
		_rng.seed = seed_value


func member_by_peer(peer: int) -> Dictionary:
	for m in members:
		if m.peer == peer and m.connected:
			return m
	return {}


func member_by_token(token: String) -> Dictionary:
	for m in members:
		if m.token == token:
			return m
	return {}


func member_by_seat(seat: String) -> Dictionary:
	for m in members:
		if m.seat == seat:
			return m
	return {}


## The host is the first CONNECTED member: a host who dropped (still inside
## the reconnect grace) must not block everybody else from starting.
func host_member() -> Dictionary:
	for m in members:
		if m.connected:
			return m
	return {}


func is_host(peer: int) -> bool:
	var h := host_member()
	return not h.is_empty() and h.peer == peer


## Adds a player (or rebinds a reconnecting one by token).
## Returns {ok, seat, token, error}.
func join(peer: int, p_name: String, token: String = "") -> Dictionary:
	if token != "":
		var back := member_by_token(token)
		if not back.is_empty():
			back.peer = peer
			back.connected = true
			back.disconnected_at = -1.0
			_push(peer, "cl_joined", [code, back.seat, back.token])
			# Snapshot len pre seat, ktorý v bežiacej hre naozaj sedí (kto bol
			# pri štarte odpojený, čaká v lobby na ďalšiu hru).
			if phase == Phase.PLAYING and _in_game(back.seat):
				_push(peer, "cl_game_started", [_view_for(back.seat)])
			_broadcast_lobby()
			return {"ok": true, "seat": back.seat, "token": back.token, "error": ""}
	# A repeated join from a peer that is already seated here (double tap)
	# must not create a second seat for the same connection.
	var already := member_by_peer(peer)
	if not already.is_empty():
		_push(peer, "cl_joined", [code, already.seat, already.token])
		_broadcast_lobby()
		return {"ok": true, "seat": already.seat, "token": already.token, "error": ""}
	if phase != Phase.LOBBY:
		return _fail("game_running")
	if members.size() >= NetProtocol.MAX_PLAYERS:
		return _fail("room_full")
	var seat := _free_seat()
	var new_token := "%08x%08x" % [_rng.randi(), _rng.randi()]
	members.append({"token": new_token, "name": p_name, "seat": seat,
			"peer": peer, "connected": true, "disconnected_at": -1.0})
	_push(peer, "cl_joined", [code, seat, new_token])
	_broadcast_lobby()
	return {"ok": true, "seat": seat, "token": new_token, "error": ""}


## Lowest seat id no current member holds. Seat ids must stay unique even
## after someone left the lobby (size+1 would hand out a duplicate).
func _free_seat() -> String:
	for i in range(1, NetProtocol.MAX_PLAYERS + 1):
		var seat := "S%d" % i
		if member_by_seat(seat).is_empty():
			return seat
	return "S%d" % (members.size() + 1) # unreachable: join checks MAX_PLAYERS


## Explicit leave. The seat is given up for good — in a running game the
## autopilot takes over its turns so the others can finish.
func leave(peer: int) -> void:
	for i in members.size():
		if members[i].peer == peer and members[i].connected:
			var seat: String = members[i].seat
			members.remove_at(i)
			if phase == Phase.PLAYING:
				_clear_selection(seat)
			_broadcast_lobby()
			if phase == Phase.PLAYING:
				_autoplay_absent()
			return


## Connection dropped (not an explicit leave): always keep the seat for the
## grace window so the player can come back mid-game.
func on_disconnect(peer: int, now: float) -> void:
	for m in members:
		if m.peer == peer and m.connected:
			m.connected = false
			m.disconnected_at = now
			# Rozpracovaný výber odpojeného hráča nesmie ostať „zaseknutý"
			# nadvihnutý na stole ostatných.
			_clear_selection(m.seat)
			_broadcast_lobby()
			return


## Priebežný výber hráča (počet označených kariet) — relay ostatným bez
## akejkoľvek hernej validácie (kozmetika); server len clampne rozsah.
func set_selection(peer: int, count: int) -> void:
	if phase != Phase.PLAYING:
		return
	var m := member_by_peer(peer)
	if m.is_empty():
		return
	count = clampi(count, 0, 8)
	if int(selections.get(m.seat, 0)) == count:
		return
	if count == 0:
		selections.erase(m.seat)
	else:
		selections[m.seat] = count
	for mm in members:
		if mm.connected and mm.peer != peer:
			_push(mm.peer, "cl_selection", [m.seat, count])


func _clear_selection(seat: String) -> void:
	if int(selections.get(seat, 0)) == 0:
		return
	selections.erase(seat)
	for mm in members:
		if mm.connected:
			_push(mm.peer, "cl_selection", [seat, 0])


## Removes members whose grace expired. Returns true when the room is empty
## and should be destroyed by the manager. Everyone left is told (the lobby
## list and the host can change), and a running game stops waiting for the
## purged seats.
func purge(now: float) -> bool:
	var removed := false
	for i in range(members.size() - 1, -1, -1):
		var m: Dictionary = members[i]
		if not m.connected \
				and now - m.disconnected_at > NetProtocol.RECONNECT_GRACE_SEC:
			members.remove_at(i)
			removed = true
	if removed and not members.is_empty():
		_broadcast_lobby()
		if phase == Phase.PLAYING:
			_autoplay_absent()
	return members.is_empty()


## Host starts the game for every CONNECTED seated player (a member still
## inside the reconnect grace sits this game out instead of stalling it).
func start_game(peer: int, variant_dict: Dictionary) -> Dictionary:
	if not is_host(peer):
		return _fail("host_only")
	if phase != Phase.LOBBY:
		return _fail("game_running")
	var seated: Array = members.filter(func(m): return m.connected)
	if seated.size() < 2:
		return _fail("need_players")
	# The variant comes from a client: shape/range-check it before it can
	# reach the deal (a huge hand size would freeze the whole server).
	var v := RulesVariant.from_dict(NetProtocol.sanitize_variant(variant_dict))
	if not NetProtocol.deck_fits(seated.size(), v.initial_hand_size, v.reverse_card):
		return _fail("too_many_cards")
	phase = Phase.PLAYING
	selections.clear() # čistý stôl — žiadne výbery z minulej hry
	variant = v
	rules = FaraonRules.new()
	var ids: Array = []
	_seat_names = {}
	for m in seated:
		ids.append(m.seat)
		_seat_names[m.seat] = m.name
	# B1 multiplayer: prvý štartér je určený plne náhodne (ekviprobabilne).
	var events := rules.start(ids, variant, int(_rng.randi()), {},
			_rng.randi_range(0, ids.size() - 1))
	for m in members:
		if m.connected and _in_game(m.seat):
			_push(m.peer, "cl_game_started", [_view_for(m.seat)])
			_push(m.peer, "cl_game_events", [events, _view_for(m.seat)])
	return {"ok": true, "error": ""}


## A proposed move from a peer: identity comes from the connection, never
## from the message. The engine remains the sole judge of legality.
func propose(peer: int, action: Dictionary) -> Dictionary:
	if phase != Phase.PLAYING:
		return _fail("game_not_running")
	var m := member_by_peer(peer)
	if m.is_empty():
		return _fail("not_in_room")
	var res := _apply_and_broadcast(m.seat, action)
	if res.ok:
		_autoplay_absent()
	else:
		_push(peer, "cl_action_rejected", [res.error])
	return res


## Applies one engine action and fans the censored result out to everyone.
func _apply_and_broadcast(seat: String, action: Dictionary) -> Dictionary:
	var res := rules.apply(seat, action)
	if res.ok:
		# Aplikovaná akcia zneplatňuje rozpracovaný výber daného hráča.
		_clear_selection(seat)
		for mm in members:
			if mm.connected and _in_game(mm.seat):
				_push(mm.peer, "cl_game_events", [res.events, _view_for(mm.seat)])
		if rules.state.phase == GameState.Phase.GAME_OVER:
			phase = Phase.LOBBY # room returns to lobby for a rematch
			_broadcast_lobby()
	return res


## Autopilot pre opustené miesta: hráč, ktorý počas hry odišiel alebo mu
## vypršala lehota na návrat, už nemá v roomke člena. Keď je na ťahu, room
## zaňho ťahá (vo vnútri eso-reťaze stojí), aby ostatní mohli dohrať.
## Ak už nehrá nikto prítomný, hra sa ukončí — samé ťahanie by nikdy neskončilo.
func _autoplay_absent() -> void:
	if phase != Phase.PLAYING or rules == null or members.is_empty():
		return
	for _i in MAX_AUTOPLAY_STEPS:
		if phase != Phase.PLAYING or rules.state.phase != GameState.Phase.PLAYING:
			return
		var seat: String = rules.state.players[rules.state.current_index].id
		if not _is_absent(seat):
			return
		if not _anyone_present_active():
			_abandon_game()
			return
		var action := FaraonActions.pass_turn() if rules.state.pending_aces > 0 \
				else FaraonActions.draw()
		if not _apply_and_broadcast(seat, action).ok:
			var other := FaraonActions.draw() \
					if action.get("action", "") == FaraonActions.PASS \
					else FaraonActions.pass_turn()
			if not _apply_and_broadcast(seat, other).ok:
				_abandon_game() # engine refuses both — never stall the table
				return
	_abandon_game() # step cap hit: something cycles, end it cleanly


func _is_absent(seat: String) -> bool:
	return member_by_seat(seat).is_empty()


func _anyone_present_active() -> bool:
	for p in rules.state.players:
		if p.status == GameState.PlayerStatus.ACTIVE and not _is_absent(p.id):
			return true
	return false


## Ends a game nobody present can finish: everyone still at the table gets a
## regular GAME_OVER (without a loser) and the room returns to the lobby.
func _abandon_game() -> void:
	if rules != null and rules.state.phase == GameState.Phase.PLAYING:
		rules.state.phase = GameState.Phase.GAME_OVER
		rules.state.loser_index = -1
		var events := [{"type": "GAME_OVER", "loser": "", "abandoned": true}]
		for mm in members:
			if mm.connected and _in_game(mm.seat):
				_push(mm.peer, "cl_game_events", [events, _view_for(mm.seat)])
	phase = Phase.LOBBY
	_broadcast_lobby()


func _in_game(seat: String) -> bool:
	return rules != null and rules.state != null \
			and rules.state.player_by_id(seat) != null


## Full censored snapshot for a resyncing client.
func snapshot_for(peer: int) -> void:
	var m := member_by_peer(peer)
	if m.is_empty() or not _in_game(m.seat):
		return
	_push(peer, "cl_game_started", [_view_for(m.seat)])


## `host` is the seat that may start the game (first connected member) —
## the UI should use it instead of assuming members[0].
func lobby_info() -> Dictionary:
	var names: Array = []
	for m in members:
		names.append({"name": m.name, "seat": m.seat, "connected": m.connected})
	var host := host_member()
	return {"code": code, "members": names, "playing": phase == Phase.PLAYING,
			"host": host.get("seat", "")}


func _view_for(seat: String) -> Dictionary:
	var view := rules.state.view_for(seat)
	view["you"] = seat
	var names := _seat_names.duplicate()
	for m in members:
		names[m.seat] = m.name
	view["names"] = names
	# Reconnect/late-join dostane aj aktuálne výbery — žiadny „zaseknutý"
	# alebo chýbajúci nadvihnutý stav.
	view["selections"] = selections.duplicate()
	return view


func _broadcast_lobby() -> void:
	var info := lobby_info()
	for m in members:
		if m.connected:
			_push(m.peer, "cl_room_update", [info])


func _push(peer: int, fn: String, args: Array) -> void:
	outbox.append({"peer": peer, "fn": fn, "args": args})
	if _dirty_sink is Dictionary:
		_dirty_sink[code] = true


func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
