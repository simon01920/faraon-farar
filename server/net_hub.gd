extends Node
## Autoload "NetHub" — the only node that touches the network on either
## side. Same stable node path on client and server, so every @rpc below
## routes cleanly. Server side: owns WebSocketMultiplayerPeer + RoomManager
## and drains room outboxes after every handled call. Client side: exposes
## the cl_* messages as signals for RoomClient/menu to consume.
## SceneTree polls multiplayer.multiplayer_peer automatically every frame.

signal connected_to_server
signal connection_failed_or_lost
signal joined(code: String, seat: String, token: String)
signal join_failed(reason: String)
signal room_updated(info: Dictionary)
signal game_started(view: Dictionary)
signal game_events(events: Array, view: Dictionary)
signal move_rejected(reason: String)
## Kozmetický „živý stôl": súper na seate si označil count kariet.
signal selection_changed(seat: String, count: int)
## This client closed its connection on purpose (disconnect_client) — not a
## loss, so nothing should try to reconnect.
signal client_disconnected

const TICK_INTERVAL := 5.0

var manager: RoomManager
var is_server := false
var is_connected_client := false
## Last URL handed to connect_to_server — RoomClient reconnects to it.
var server_url := ""
var _tick_accum := 0.0


func _ready() -> void:
	# Autoload runs in every build, single-player included: no per-frame
	# work until this process actually hosts rooms (the server tick is the
	# only thing _process does). The client side is purely signal-driven.
	set_process(false)


func start_server(port: int = NetProtocol.DEFAULT_PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Faraón server: create_server failed on port %d (%s)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(id): print("peer connected: ", id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	manager = RoomManager.new()
	is_server = true
	set_process(true)
	print("Faraón server listening on port ", port)
	return OK


## Starts (or keeps) a client connection. A second call while the previous
## attempt is still handshaking reuses it instead of opening another socket.
func connect_to_server(url: String) -> Error:
	if is_server:
		return ERR_ALREADY_IN_USE
	server_url = url
	if is_connected_client:
		return OK
	if is_connecting():
		return OK
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		connection_failed_or_lost.emit()
		return err
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_conn_lost)
		multiplayer.server_disconnected.connect(_on_conn_lost)
	return OK


## Closes the client connection on purpose (leaving the online screens, going
## offline): the socket stops being polled and kept alive, and listeners get
## `client_disconnected` instead of `connection_failed_or_lost`.
func disconnect_client() -> void:
	if is_server:
		return
	var current := multiplayer.multiplayer_peer
	if current != null and not (current is OfflineMultiplayerPeer):
		current.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_connected_client = false
	client_disconnected.emit()


## True while a connection attempt is handshaking (not yet connected).
func is_connecting() -> bool:
	var current := multiplayer.multiplayer_peer
	return current is WebSocketMultiplayerPeer and not is_server \
			and current.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING


func _on_connected() -> void:
	is_connected_client = true
	connected_to_server.emit()


func _on_conn_lost() -> void:
	is_connected_client = false
	connection_failed_or_lost.emit()


func _on_peer_disconnected(id: int) -> void:
	if manager != null:
		manager.on_disconnect(id, Time.get_unix_time_from_system())
		_flush()


func _process(delta: float) -> void:
	if not is_server:
		return
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL:
		_tick_accum = 0.0
		manager.tick(Time.get_unix_time_from_system())
		_flush()


## Sends every message the touched rooms queued up (RoomManager tracks which
## rooms have output, so this does not walk every room on each RPC).
func _flush() -> void:
	for msg in manager.drain_outbox():
		match msg.args.size():
			0: rpc_id(msg.peer, msg.fn)
			1: rpc_id(msg.peer, msg.fn, msg.args[0])
			2: rpc_id(msg.peer, msg.fn, msg.args[0], msg.args[1])
			_: rpc_id(msg.peer, msg.fn, msg.args[0], msg.args[1], msg.args[2])


# --- client -> server ------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func sv_create_room(p_name) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	var clean := NetProtocol.clean_name(p_name)
	manager.create_room(peer, clean if clean != "" else "Hráč")
	_flush()


@rpc("any_peer", "call_remote", "reliable")
func sv_join_room(code, p_name, token) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not NetProtocol.valid_code(code) or not (token is String):
		rpc_id(peer, "cl_join_failed", "bad_message")
		return
	var clean := NetProtocol.clean_name(p_name)
	var res: Dictionary = manager.join_room(peer, code,
			clean if clean != "" else "Hráč", token)
	if not res.get("ok", false):
		rpc_id(peer, "cl_join_failed", str(res.get("error", "join_failed")))
	_flush()


@rpc("any_peer", "call_remote", "reliable")
func sv_leave() -> void:
	if not is_server:
		return
	manager.leave(multiplayer.get_remote_sender_id())
	_flush()


@rpc("any_peer", "call_remote", "reliable")
func sv_start_game(variant_dict) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	var room := manager.room_of(peer)
	if room != null:
		var res := room.start_game(peer,
				variant_dict if variant_dict is Dictionary else {})
		if not res.ok:
			room._push(peer, "cl_action_rejected", [res.error])
	_flush()


@rpc("any_peer", "call_remote", "reliable")
func sv_propose(action) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not NetProtocol.valid_action(action):
		rpc_id(peer, "cl_action_rejected", "bad_message")
		return
	var room := manager.room_of(peer)
	if room != null:
		room.propose(peer, action)
	_flush()


## Priebežný výber kariet — kozmetický kanál MIMO autoritatívnej cesty
## ťahov: žiadna herná validácia (len clamp), klient throttluje odosielanie.
@rpc("any_peer", "call_remote", "reliable")
func sv_selection(count) -> void:
	if not is_server:
		return
	if not (count is int or count is float):
		return
	var peer := multiplayer.get_remote_sender_id()
	var room := manager.room_of(peer)
	if room != null:
		room.set_selection(peer, int(count))
		_flush()


@rpc("any_peer", "call_remote", "reliable")
func sv_snapshot() -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	var room := manager.room_of(peer)
	if room != null:
		room.snapshot_for(peer)
	_flush()


# --- server -> client ------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func cl_joined(code, seat, token) -> void:
	joined.emit(code, seat, token)


@rpc("authority", "call_remote", "reliable")
func cl_join_failed(reason) -> void:
	join_failed.emit(str(reason))


@rpc("authority", "call_remote", "reliable")
func cl_room_update(info) -> void:
	if info is Dictionary:
		room_updated.emit(info)


@rpc("authority", "call_remote", "reliable")
func cl_game_started(view) -> void:
	if view is Dictionary:
		game_started.emit(view)


@rpc("authority", "call_remote", "reliable")
func cl_game_events(events, view) -> void:
	if events is Array and view is Dictionary:
		game_events.emit(events, view)


@rpc("authority", "call_remote", "reliable")
func cl_action_rejected(reason) -> void:
	move_rejected.emit(str(reason))


@rpc("authority", "call_remote", "reliable")
func cl_selection(seat, count) -> void:
	if seat is String and (count is int or count is float):
		selection_changed.emit(seat, int(count))
