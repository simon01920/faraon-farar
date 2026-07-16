class_name RoomManager
extends RefCounted
## All active rooms in the single long-running server process (approved
## model A). Pure logic like FaraonRoom — the NetHub drains each room's
## outbox after every call. One instance lives for the whole server run.

var rooms := {} # code -> FaraonRoom
var peer_rooms := {} # peer id -> room code
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value


func create_room(peer: int, p_name: String) -> FaraonRoom:
	var code := NetProtocol.make_code(_rng)
	while rooms.has(code):
		code = NetProtocol.make_code(_rng)
	var room := FaraonRoom.new(code, int(_rng.randi()))
	rooms[code] = room
	room.join(peer, p_name)
	peer_rooms[peer] = code
	return room


## Returns the room on success, null on failure (reason pushed to the peer
## through the room outbox is not possible here — the hub replies directly).
func join_room(peer: int, code: String, p_name: String, token: String) -> Dictionary:
	if not rooms.has(code):
		return {"ok": false, "error": "no_such_room"}
	var room: FaraonRoom = rooms[code]
	var res := room.join(peer, p_name, token)
	if res.ok:
		peer_rooms[peer] = code
	return res


func room_of(peer: int) -> FaraonRoom:
	var code = peer_rooms.get(peer, "")
	return rooms.get(code) if code != "" else null


func leave(peer: int) -> void:
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


## Collects and clears every room's pending outbound messages.
func drain_outbox() -> Array:
	var all: Array = []
	for code in rooms:
		var room: FaraonRoom = rooms[code]
		if not room.outbox.is_empty():
			all.append_array(room.outbox)
			room.outbox = []
	return all
