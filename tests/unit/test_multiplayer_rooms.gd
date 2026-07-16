extends GutTest
## Unit tests for the transport-free multiplayer room layer (server/):
## room codes, join/rejoin tokens, host rights, propose routing, reconnect
## grace and message shape validation. No sockets involved — rooms queue
## their outbound messages in `outbox`.


func _msgs(room: FaraonRoom, fn: String) -> Array:
	return room.outbox.filter(func(m): return m.fn == fn)


# --- protocol shape ---------------------------------------------------------

func test_room_codes_avoid_confusable_characters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in 50:
		var code := NetProtocol.make_code(rng)
		assert_eq(code.length(), NetProtocol.ROOM_CODE_LEN)
		for banned in ["0", "O", "1", "I"]:
			assert_false(code.contains(banned), "%s contains %s" % [code, banned])
		assert_true(NetProtocol.valid_code(code))


func test_action_shape_validation_blocks_garbage() -> void:
	assert_true(NetProtocol.valid_action(FaraonActions.draw()))
	assert_true(NetProtocol.valid_action(FaraonActions.play(["7C"], 2)))
	assert_false(NetProtocol.valid_action(null))
	assert_false(NetProtocol.valid_action("DRAW"))
	assert_false(NetProtocol.valid_action({"action": "PLAY_CARDS", "cards": []}))
	assert_false(NetProtocol.valid_action(
			{"action": "PLAY_CARDS", "cards": ["XX"]}))
	assert_false(NetProtocol.valid_action(
			{"action": "PLAY_CARDS", "cards": ["7C"], "declared_suit": 9}))


# --- room membership --------------------------------------------------------

func test_join_assigns_seats_and_tokens() -> void:
	var room := FaraonRoom.new("ABCDE", 1)
	var a := room.join(101, "Simon")
	var b := room.join(102, "Katka")
	assert_eq(a.seat, "S1")
	assert_eq(b.seat, "S2")
	assert_ne(a.token, b.token)
	assert_true(room.is_host(101))
	assert_false(room.is_host(102))


func test_room_full_and_game_running_rejections() -> void:
	var room := FaraonRoom.new("ABCDE", 2)
	for i in NetProtocol.MAX_PLAYERS:
		assert_true(room.join(100 + i, "P%d" % i).ok)
	assert_eq(room.join(200, "late").error, "room_full")


func test_host_starts_game_and_views_are_censored() -> void:
	var room := FaraonRoom.new("ABCDE", 3)
	room.join(101, "Simon")
	room.join(102, "Katka")
	assert_eq(room.start_game(102, {}).error, "host_only")
	assert_true(room.start_game(101, {}).ok)
	var starts := _msgs(room, "cl_game_started")
	assert_eq(starts.size(), 2)
	for msg in starts:
		var view: Dictionary = msg.args[0]
		var mine: String = view.you
		for pd in view.players:
			if pd.id == mine:
				assert_true(pd.has("hand"), "own hand visible")
			else:
				assert_false(pd.has("hand"), "foreign hand hidden")
				assert_true(pd.has("hand_count"))
		assert_false(view.has("draw_pile"), "draw pile never leaves the server")


func test_propose_routes_by_connection_identity() -> void:
	var room := FaraonRoom.new("ABCDE", 4)
	room.join(101, "Simon")
	room.join(102, "Katka")
	room.start_game(101, {})
	room.outbox = []
	# Whoever is NOT on turn gets rejected regardless of message contents.
	var on_turn: String = room.rules.state.players[room.rules.state.current_index].id
	var off_peer := 102 if on_turn == "S1" else 101
	room.propose(off_peer, FaraonActions.draw())
	var rejected := _msgs(room, "cl_action_rejected")
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0].peer, off_peer)
	# The player on turn CAN draw and everyone gets fresh events + views.
	room.outbox = []
	var on_peer := 101 if on_turn == "S1" else 102
	room.propose(on_peer, FaraonActions.draw())
	assert_eq(_msgs(room, "cl_game_events").size(), 2)


func test_reconnect_by_token_rebinds_seat() -> void:
	var room := FaraonRoom.new("ABCDE", 5)
	var joined := room.join(101, "Simon")
	room.join(102, "Katka")
	room.start_game(101, {})
	room.on_disconnect(101, 1000.0)
	assert_false(room.member_by_peer(101).size() > 0)
	# Reconnect with the token under a NEW peer id -> same seat + snapshot.
	room.outbox = []
	var back := room.join(555, "Simon", joined.token)
	assert_true(back.ok)
	assert_eq(back.seat, "S1")
	assert_true(room.is_host(555), "host rights follow the seat")
	assert_eq(_msgs(room, "cl_game_started").size(), 1,
			"reconnect gets a full snapshot for resync")


func test_grace_expiry_purges_seat_and_empty_room() -> void:
	var room := FaraonRoom.new("ABCDE", 6)
	room.join(101, "Simon")
	room.on_disconnect(101, 1000.0)
	assert_false(room.purge(1000.0 + 30.0), "still inside the grace window")
	assert_true(room.purge(1000.0 + NetProtocol.RECONNECT_GRACE_SEC + 1.0),
			"empty after expiry -> room can be destroyed")


func test_manager_creates_unique_rooms_and_routes() -> void:
	var mgr := RoomManager.new(9)
	var room_a := mgr.create_room(101, "Simon")
	var room_b := mgr.create_room(201, "Katka")
	assert_ne(room_a.code, room_b.code)
	assert_eq(mgr.join_room(102, room_a.code, "Jano", "").ok, true)
	assert_eq(mgr.join_room(103, "ZZZZZ", "Nikto", "").error, "no_such_room")
	assert_eq(mgr.room_of(102), room_a)
	mgr.leave(102)
	assert_null(mgr.room_of(102))
