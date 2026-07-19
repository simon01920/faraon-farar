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


func is_host(peer: int) -> bool:
	return not members.is_empty() and members[0].peer == peer \
			and members[0].connected


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
			if phase == Phase.PLAYING:
				_push(peer, "cl_game_started", [_view_for(back.seat)])
			_broadcast_lobby()
			return {"ok": true, "seat": back.seat, "token": back.token, "error": ""}
	if phase != Phase.LOBBY:
		return _fail("game_running")
	if members.size() >= NetProtocol.MAX_PLAYERS:
		return _fail("room_full")
	var seat := "S%d" % (members.size() + 1)
	var new_token := "%08x%08x" % [_rng.randi(), _rng.randi()]
	members.append({"token": new_token, "name": p_name, "seat": seat,
			"peer": peer, "connected": true, "disconnected_at": -1.0})
	_push(peer, "cl_joined", [code, seat, new_token])
	_broadcast_lobby()
	return {"ok": true, "seat": seat, "token": new_token, "error": ""}


func leave(peer: int) -> void:
	for i in members.size():
		if members[i].peer == peer:
			if phase == Phase.LOBBY:
				members.remove_at(i)
			else:
				members[i].connected = false
				members[i].disconnected_at = Time.get_unix_time_from_system()
			_broadcast_lobby()
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
## and should be destroyed by the manager.
func purge(now: float) -> bool:
	for i in range(members.size() - 1, -1, -1):
		var m: Dictionary = members[i]
		if not m.connected \
				and now - m.disconnected_at > NetProtocol.RECONNECT_GRACE_SEC:
			members.remove_at(i)
	return members.is_empty()


## Host starts the game for every seated player.
func start_game(peer: int, variant_dict: Dictionary) -> Dictionary:
	if not is_host(peer):
		return _fail("host_only")
	if phase != Phase.LOBBY:
		return _fail("game_running")
	if members.size() < 2:
		return _fail("need_players")
	phase = Phase.PLAYING
	selections.clear() # čistý stôl — žiadne výbery z minulej hry
	variant = RulesVariant.from_dict(variant_dict if variant_dict != null else {})
	rules = FaraonRules.new()
	var ids: Array = []
	for m in members:
		ids.append(m.seat)
	# B1 multiplayer: prvý štartér je určený plne náhodne (ekviprobabilne).
	var events := rules.start(ids, variant, int(_rng.randi()), {},
			_rng.randi_range(0, ids.size() - 1))
	for m in members:
		if m.connected:
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
	var res := rules.apply(m.seat, action)
	if res.ok:
		# Aplikovaná akcia zneplatňuje rozpracovaný výber daného hráča.
		_clear_selection(m.seat)
		for mm in members:
			if mm.connected:
				_push(mm.peer, "cl_game_events", [res.events, _view_for(mm.seat)])
		if rules.state.phase == GameState.Phase.GAME_OVER:
			phase = Phase.LOBBY # room returns to lobby for a rematch
			_broadcast_lobby()
	else:
		_push(peer, "cl_action_rejected", [res.error])
	return res


## Full censored snapshot for a resyncing client.
func snapshot_for(peer: int) -> void:
	var m := member_by_peer(peer)
	if m.is_empty() or rules == null:
		return
	_push(peer, "cl_game_started", [_view_for(m.seat)])


func lobby_info() -> Dictionary:
	var names: Array = []
	for m in members:
		names.append({"name": m.name, "seat": m.seat, "connected": m.connected})
	return {"code": code, "members": names, "playing": phase == Phase.PLAYING}


func _view_for(seat: String) -> Dictionary:
	var view := rules.state.view_for(seat)
	view["you"] = seat
	var names := {}
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


func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
