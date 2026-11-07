class_name RoomClient
extends Node
## Client-side adapter with the same surface GameTable already speaks to
## LocalGameServer: `rules.state`, propose(), state_updated/action_rejected
## signals, display_name(), local_player_id(). The censored server view is
## rebuilt into a GameState — hidden hands and the draw pile are padded with
## placeholder backs so counts render, while real card data never reaches
## other clients.
##
## Reconnect: while seated in a room the client keeps room_code + session
## token. A lost connection triggers automatic reconnect attempts with
## backoff; once back, it rejoins with the token and the server rebinds the
## seat (inside NetProtocol.RECONNECT_GRACE_SEC) and resends a snapshot.

signal state_updated(events: Array)
signal action_rejected(player_id: String, error: String)
## Živý stôl: hráč na seate si označil `count` kariet (0 = zrušený výber).
signal selection_updated(player_id: String, count: int)
## Connection to the room was lost; reconnect attempt `attempt` (1-based) is
## scheduled. Fires once per attempt — the UI can show "reconnecting…".
signal reconnecting(attempt: int)
## Back in the room on the same seat (a snapshot follows if a game runs).
signal reconnected
## Reconnect gave up (`reason`: "timeout", "no_server" or the server's join
## error such as "no_such_room"). The room state has been cleared.
signal reconnect_failed(reason: String)

## Backoff between reconnect attempts (seconds); the last value repeats.
const RECONNECT_DELAYS := [1.0, 2.0, 4.0, 8.0, 15.0]
## Give up after this long — the server frees the seat after its grace window
## anyway, so trying longer cannot succeed.
const RECONNECT_GIVE_UP_SEC := NetProtocol.RECONNECT_GRACE_SEC - 5.0

## Compatibility with the table's LocalGameServer expectations.
var rules := FaraonRules.new()
var fast_forward := false
var match_state = null # Olympic modes are single-device only for now

var my_seat := ""
var my_token := ""
var room_code := ""
var _names := {}

## Debounce odosielania výberu: posiela sa len zmena, najviac raz za okno —
## rýchle preklikávanie kariet nezahlcuje server (viac room-ov naraz).
const SELECTION_DEBOUNCE := 0.15
var _sel_timer: Timer
var _sel_pending := 0
var _sel_last_sent := 0

var _reconnect_timer: Timer
var _reconnecting := false
var _reconnect_attempt := 0
var _reconnect_started_ms := 0
## The next cl_game_started is a resync snapshot of the game already on the
## table, not a fresh deal — the table must re-render from it.
var _awaiting_resync := false


## Runtime autoload lookup (compiles under -s tool runs too).
func _hub() -> Node:
	return get_node("/root/NetHub")


func _ready() -> void:
	_hub().game_events.connect(_on_game_events)
	_hub().game_started.connect(_on_game_started)
	_hub().selection_changed.connect(func(seat, count):
		selection_updated.emit(str(seat), int(count)))
	_hub().move_rejected.connect(func(reason):
		action_rejected.emit(my_seat, reason))
	_hub().joined.connect(_on_joined)
	_hub().join_failed.connect(_on_join_failed)
	_hub().room_updated.connect(_on_room_updated)
	_hub().connected_to_server.connect(_on_connected)
	_hub().connection_failed_or_lost.connect(_on_connection_lost)
	_hub().client_disconnected.connect(_on_client_disconnected)
	_sel_timer = Timer.new()
	_sel_timer.one_shot = true
	_sel_timer.wait_time = SELECTION_DEBOUNCE
	_sel_timer.timeout.connect(func():
		if _sel_pending != _sel_last_sent:
			_send_selection())
	add_child(_sel_timer)
	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_attempt_reconnect)
	add_child(_reconnect_timer)


# --- the LocalGameServer-compatible surface --------------------------------

func propose(_player_id: String, action: Dictionary) -> Dictionary:
	if not _send("sv_propose", [action]):
		# Offline (e.g. mid-reconnect): say so instead of waiting forever for
		# an answer that cannot come.
		action_rejected.emit(my_seat, "offline")
		return {"ok": false, "error": "offline", "events": []}
	return {"ok": true, "error": "", "events": []} # server answers async


## Priebežný výber (počet označených kariet) — leading send + trailing
## debounce: prvá zmena ide hneď, ďalšie sa zlučujú do okna 150 ms.
func update_selection(count: int) -> void:
	_sel_pending = clampi(count, 0, 8)
	if _sel_timer == null or not _sel_timer.is_stopped():
		return
	_send_selection()
	_sel_timer.start()


func _send_selection() -> void:
	_sel_last_sent = _sel_pending
	_send("sv_selection", [_sel_pending])


func local_player_id() -> String:
	return my_seat


func display_name(id: String) -> String:
	return str(_names.get(id, id))


func supports_fast_forward() -> bool:
	return false # never against real players


func supports_restart() -> bool:
	return false # rematch goes through the lobby


func progression_context() -> String:
	return "multiplayer"


func game_mode() -> String:
	return "normal"


# --- room membership ----------------------------------------------------------

## Leaves the current room for good (the server gives the seat up, a running
## game continues without us) and forgets the room locally.
func leave() -> void:
	if room_code != "":
		_send("sv_leave", [])
	_stop_reconnect()
	_clear_room()


func is_in_room() -> bool:
	return room_code != ""


func is_reconnecting() -> bool:
	return _reconnecting


func _clear_room() -> void:
	room_code = ""
	my_seat = ""
	my_token = ""
	_awaiting_resync = false


## Sends one RPC to the server; false when there is no live connection.
## (Separate method so tests can capture traffic without a socket.)
func _send(fn: String, args: Array) -> bool:
	var hub := _hub()
	if not hub.is_connected_client:
		return false
	match args.size():
		0: hub.rpc_id(1, fn)
		1: hub.rpc_id(1, fn, args[0])
		2: hub.rpc_id(1, fn, args[0], args[1])
		_: hub.rpc_id(1, fn, args[0], args[1], args[2])
	return true


## Opens a new connection to the last server URL. Overridable in tests.
func _connect_to_server() -> bool:
	var url: String = _hub().server_url
	if url == "":
		return false
	_hub().connect_to_server(url)
	return true


# --- reconnect ----------------------------------------------------------------

func _on_connection_lost() -> void:
	if room_code == "" or my_token == "":
		return # not seated anywhere — nothing to restore
	if not _reconnecting:
		_reconnecting = true
		_reconnect_attempt = 0
		_reconnect_started_ms = Time.get_ticks_msec()
	_schedule_reconnect()


func _schedule_reconnect() -> void:
	var elapsed := (Time.get_ticks_msec() - _reconnect_started_ms) / 1000.0
	if elapsed >= RECONNECT_GIVE_UP_SEC:
		_give_up("timeout")
		return
	var delay: float = RECONNECT_DELAYS[mini(_reconnect_attempt,
			RECONNECT_DELAYS.size() - 1)]
	_reconnect_attempt += 1
	reconnecting.emit(_reconnect_attempt)
	if _reconnect_timer != null:
		_reconnect_timer.start(delay)


func _attempt_reconnect() -> void:
	if not _reconnecting:
		return
	if _hub().is_connected_client:
		_send_rejoin() # someone (e.g. the menu) already reconnected
		return
	if not _connect_to_server():
		_give_up("no_server")
	# Success continues in _on_connected; a failure comes back through
	# connection_failed_or_lost -> _on_connection_lost -> next attempt.


func _on_connected() -> void:
	if _reconnecting:
		_send_rejoin()


func _send_rejoin() -> void:
	# The name is ignored for a token rejoin — the seat keeps its own.
	_send("sv_join_room", [room_code, "", my_token])


func _on_joined(code, seat, token) -> void:
	room_code = str(code)
	my_seat = str(seat)
	my_token = str(token)
	if _reconnecting:
		_stop_reconnect()
		_awaiting_resync = rules.state != null \
				and rules.state.phase == GameState.Phase.PLAYING
		reconnected.emit()


func _on_join_failed(reason) -> void:
	if _reconnecting:
		_give_up(str(reason)) # e.g. the seat expired or the room is gone


func _on_room_updated(info: Dictionary) -> void:
	# A rejoin into a room that is back in the lobby gets no snapshot.
	if _awaiting_resync and not info.get("playing", false):
		_awaiting_resync = false


func _on_client_disconnected() -> void:
	# Deliberate disconnect (leaving the online screens): no reconnecting.
	_stop_reconnect()
	_clear_room()


func _give_up(reason: String) -> void:
	_stop_reconnect()
	_clear_room()
	reconnect_failed.emit(reason)


func _stop_reconnect() -> void:
	_reconnecting = false
	_reconnect_attempt = 0
	if _reconnect_timer != null:
		_reconnect_timer.stop()


# --- server messages --------------------------------------------------------

func _on_game_started(view: Dictionary) -> void:
	_apply_view(view)
	if _awaiting_resync:
		# Resync after a reconnect: same game, so no friend bump; an empty
		# event batch makes the table re-render from the fresh state.
		_awaiting_resync = false
		state_updated.emit([])
		return
	# Friends-leaderboard groundwork: remember who we sat with (locally).
	for seat in _names:
		if seat != my_seat:
			ProgressionStore.bump_friend(str(_names[seat]))


func _on_game_events(events: Array, view: Dictionary) -> void:
	_apply_view(view)
	state_updated.emit(events)


func _apply_view(view: Dictionary) -> void:
	my_seat = str(view.get("you", my_seat))
	_names = view.get("names", _names)
	var s := GameState.from_dict(view)
	# Pad hidden information with placeholder backs so counts render.
	for pd in view.get("players", []):
		if not pd.has("hand"):
			var p := s.player_by_id(str(pd.get("id", "")))
			if p != null:
				for _i in int(pd.get("hand_count", 0)):
					p.hand.append("")
	for _i in int(view.get("draw_pile_count", 0)):
		s.draw_pile.append("")
	rules.state = s
	# Reconnect/late-join: server posiela aj aktuálne výbery, aby nadvihnuté
	# ruby súperov sedeli s realitou (a nič neostalo „zaseknuté").
	var sels: Dictionary = view.get("selections", {})
	for seat in sels:
		selection_updated.emit(str(seat), int(sels[seat]))
