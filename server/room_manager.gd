class_name RoomManager
extends RefCounted
## All active rooms in the single long-running server process (approved
## model A). Pure logic like FaraonRoom — the NetHub drains each room's
## outbox after every call. One instance lives for the whole server run.

var rooms := {} # code -> FaraonRoom
var peer_rooms := {} # peer id -> room code
var _rng := RandomNumberGenerator.new()
## Codes of rooms with queued output (filled by FaraonRoom._push through the
## shared dictionary) — draining touches only these, not every room.
var _dirty := {}


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value


func create_room(peer: int, p_name: String) -> FaraonRoom:
	var code := NetProtocol.make_code(_rng)
	while rooms.has(code):
		code = NetProtocol.make_code(_rng)
	var room := FaraonRoom.new(code, int(_rng.randi()))
	room._dirty_sink = _dirty
	rooms[code] = room
	# One connection = one seat: whatever room the peer sat in before (a
	# double-tapped "Create", a deep link while seated) is left properly,
	# otherwise it would keep a "connected" ghost that never gets purged.
	_leave_current(peer)
	room.join(peer, p_name)
	peer_rooms[peer] = code
	return room


## Returns {ok, seat, token, error}; on failure the hub replies to the peer
## directly (cl_join_failed) and the peer keeps its current room.
func join_room(peer: int, code: String, p_name: String, token: String) -> Dictionary:
	if not rooms.has(code):
		return {"ok": false, "error": "no_such_room"}
	var room: FaraonRoom = rooms[code]
	var res := room.join(peer, p_name, token)
	if res.ok:
		if peer_rooms.get(peer, code) != code:
			_leave_current(peer)
		peer_rooms[peer] = code
	return res


func room_of(peer: int) -> FaraonRoom:
	var code = peer_rooms.get(peer, "")
	return rooms.get(code) if code != "" else null


func leave(peer: int) -> void:
	_leave_current(peer)


func _leave_current(peer: int) -> void:
	var room := room_of(peer)
	if room != null:
		room.leave(peer)
	peer_rooms.erase(peer)


func on_disconnect(peer: int, now: float) -> void:
	var room := room_of(peer)
	if room != null:
		room.on_disconnect(peer, now)
	peer_rooms.erase(peer)


## Periodic housekeeping: expire abandoned seats, delete empty rooms.
func tick(now: float) -> void:
	for code in rooms.keys():
		if rooms[code].purge(now):
			rooms.erase(code)
			_dirty.erase(code)


## Collects and clears the pending outbound messages of every room that
## queued something since the last drain.
func drain_outbox() -> Array:
	var all: Array = []
	for code in _dirty.keys():
		var room: FaraonRoom = rooms.get(code)
		if room != null and not room.outbox.is_empty():
			all.append_array(room.outbox)
			room.outbox = []
	_dirty.clear()
	return all
