extends GutTest
## Regression tests for the multiplayer/monetization review fixes: variant
## validation, unique seat ids, the absent-seat autopilot, lobby host/purge
## broadcasts, ghost-free room switching, per-room outbox draining, RoomClient
## reconnect plumbing, NetHub idling, ad continuations, IAP entitlements and
## the backwards-clock ad window. Transport-free like test_multiplayer_rooms.

const T0 := 1_700_000_000
const GRACE := NetProtocol.RECONNECT_GRACE_SEC

var _monetization_backup = null # PackedByteArray of the user's file, or null


func before_all() -> void:
	var path := ProjectSettings.globalize_path(MonetizationStore.PATH)
	if FileAccess.file_exists(path):
		_monetization_backup = FileAccess.get_file_as_bytes(path)


func after_all() -> void:
	var path := ProjectSettings.globalize_path(MonetizationStore.PATH)
	if _monetization_backup == null:
		DirAccess.remove_absolute(path)
	else:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(_monetization_backup)
		f.close()
	ConfigCache.invalidate(MonetizationStore.PATH)
	Iap._revalidation_backend = null


func _msgs(room: FaraonRoom, fn: String) -> Array:
	return room.outbox.filter(func(m): return m.fn == fn)


func _room3(code: String, seed_value: int) -> FaraonRoom:
	var room := FaraonRoom.new(code, seed_value)
	room.join(101, "A")
	room.join(102, "B")
	room.join(103, "C")
	return room


func _peer_of(seat: String) -> int:
	return {"S1": 101, "S2": 102, "S3": 103}[seat]


func _current(room: FaraonRoom) -> String:
	return room.rules.state.players[room.rules.state.current_index].id


## Draw (or pass inside an eso chain) for whoever is on turn.
func _simple_move(room: FaraonRoom) -> void:
	var act := FaraonActions.pass_turn() if room.rules.state.pending_aces > 0 \
			else FaraonActions.draw()
	room.propose(_peer_of(_current(room)), act)


# --- #2 variant validation -------------------------------------------------

func test_sanitize_variant_clamps_and_drops_garbage() -> void:
	var clean := NetProtocol.sanitize_variant({
		"initial_hand_size": 2000000000, "seven_penalty_step": 99,
		"seven_penalty_cap": -5, "red7_return_scope": 7, "finish_rule": "x",
		"faraon_wild": "yes", "kind": 1, "end_on_first_finish": true,
		"bogus": 1, "multi_card_play": false,
	})
	assert_eq(clean.get("initial_hand_size"), NetProtocol.HAND_SIZE_MAX,
			"hand size is clamped into the slider range")
	for k in ["seven_penalty_step", "seven_penalty_cap", "red7_return_scope",
			"finish_rule", "faraon_wild", "kind", "end_on_first_finish", "bogus"]:
		assert_false(clean.has(k), "%s must be dropped" % k)
	assert_eq(clean.get("multi_card_play"), false, "valid bool rules survive")
	assert_eq(NetProtocol.sanitize_variant(null), {})
	assert_eq(NetProtocol.sanitize_variant({"initial_hand_size": -3})
			.get("initial_hand_size"), NetProtocol.HAND_SIZE_MIN)


func test_sanitize_variant_keeps_every_ui_preset() -> void:
	for preset in RulesVariant.PRESETS:
		var v := RulesVariant.from_dict(NetProtocol.sanitize_variant(
				RulesVariant.from_preset(preset).to_dict()))
		assert_true(v.matches_preset(preset), "preset %s survives the wire" % preset)


func test_deck_fits() -> void:
	assert_true(NetProtocol.deck_fits(5, 6))
	assert_false(NetProtocol.deck_fits(5, 7), "35 cards do not fit a 32 deck")
	assert_true(NetProtocol.deck_fits(4, 7))
	assert_false(NetProtocol.deck_fits(5, 7, true), "33 cards are not enough either")


func test_start_game_with_huge_hand_size_is_clamped_and_fast() -> void:
	var room := FaraonRoom.new("HUGEH", 1)
	room.join(101, "A")
	room.join(102, "B")
	var t0 := Time.get_ticks_msec()
	assert_true(room.start_game(101, {"initial_hand_size": 2000000000}).ok)
	assert_lt(Time.get_ticks_msec() - t0, 500, "no multi-hour deal loop")
	for p in room.rules.state.players:
		assert_eq(p.hand.size(), NetProtocol.HAND_SIZE_MAX)


func test_start_game_rejects_hands_the_deck_cannot_deal() -> void:
	var room := FaraonRoom.new("FIVE7", 2)
	for i in 5:
		room.join(101 + i, "P%d" % i)
	room.outbox = []
	var res := room.start_game(101, {"initial_hand_size": 7})
	assert_false(res.ok)
	assert_eq(res.error, "too_many_cards")
	assert_eq(room.phase, FaraonRoom.Phase.LOBBY, "room stays in the lobby")
	assert_eq(_msgs(room, "cl_game_started").size(), 0)
	assert_true(room.start_game(101, {"initial_hand_size": 6}).ok, "5 x 6 fits")


# --- #3 unique seat ids ---------------------------------------------------

func test_seat_ids_stay_unique_after_a_lobby_leave() -> void:
	var room := _room3("SEATS", 3)
	room.leave(102)
	var d := room.join(104, "D")
	assert_eq(d.seat, "S2", "the freed seat id is reused")
	var seats := {}
	for m in room.members:
		assert_false(seats.has(m.seat), "duplicate seat %s" % m.seat)
		seats[m.seat] = true
	assert_true(room.start_game(101, {}).ok)
	assert_eq(room.rules.state.players.size(), 3)


func test_repeated_join_from_the_same_peer_does_not_add_a_seat() -> void:
	var room := FaraonRoom.new("TWICE", 4)
	var a := room.join(101, "A")
	var again := room.join(101, "A")
	assert_eq(room.members.size(), 1)
	assert_eq(again.seat, a.seat)
	assert_eq(again.token, a.token)


# --- #4 absent seats never stall a game -----------------------------------

func test_start_game_seats_only_connected_members() -> void:
	var room := _room3("CONNO", 5)
	room.on_disconnect(103, 1000.0)
	room.outbox = []
	assert_true(room.start_game(101, {}).ok)
	var ids := []
	for p in room.rules.state.players:
		ids.append(p.id)
	assert_eq(ids, ["S1", "S2"], "the dropped member sits this game out")
	for m in room.outbox:
		assert_ne(m.peer, 103)
	# Coming back mid-game: rejoined to the room, but no table for a game
	# they are not part of.
	room.outbox = []
	assert_true(room.join(555, "C", room.member_by_seat("S3").token).ok)
	assert_eq(_msgs(room, "cl_joined").size(), 1)
	assert_eq(_msgs(room, "cl_game_started").size(), 0)


func test_explicit_leave_mid_game_is_autoplayed() -> void:
	var room := _room3("LEAVE", 6)
	room.start_game(101, {})
	room.outbox = []
	room.leave(103)
	var waited_on_absent := false
	for _i in 80:
		if room.phase != FaraonRoom.Phase.PLAYING:
			break
		if _current(room) == "S3":
			waited_on_absent = true
			break
		_simple_move(room)
	assert_false(waited_on_absent, "the game never waits on a seat that left")
	var autoplayed := room.outbox.filter(func(m):
		return m.fn == "cl_game_events" and m.args[0].any(func(e):
			return e.get("player", "") == "S3"))
	assert_gt(autoplayed.size(), 0, "S3's turns were played by the room")
	var view := room._view_for("S1")
	assert_eq(view.names.get("S3"), "C", "opponents still see the leaver's name")


func test_disconnected_seat_waits_for_grace_then_is_autoplayed() -> void:
	var room := _room3("GRACE", 7)
	room.start_game(101, {})
	var seat := _current(room)
	room.on_disconnect(_peer_of(seat), 1000.0)
	assert_eq(_current(room), seat, "inside the grace window the seat waits")
	room.outbox = []
	assert_false(room.purge(1000.0 + GRACE + 1.0))
	if room.phase == FaraonRoom.Phase.PLAYING:
		assert_ne(_current(room), seat, "after expiry the room plays for it")
	assert_gt(_msgs(room, "cl_room_update").size(), 0, "lobby told about the purge")


func test_game_is_abandoned_when_no_present_player_is_left_in_it() -> void:
	var room := _room3("ABAND", 8)
	room.start_game(101, {})
	room.leave(102)
	room.leave(103)
	# S1 is done (finished) — only absent seats would keep drawing forever.
	var st := room.rules.state
	st.player_by_id("S1").status = GameState.PlayerStatus.FINISHED
	st.current_index = st.index_of("S2")
	room.outbox = []
	room._autoplay_absent()
	assert_eq(room.phase, FaraonRoom.Phase.LOBBY, "room returns to the lobby")
	assert_eq(st.phase, GameState.Phase.GAME_OVER)
	var over := _msgs(room, "cl_game_events").filter(func(m):
		return m.peer == 101 and m.args[0].any(func(e): return e.type == "GAME_OVER"))
	assert_eq(over.size(), 1, "the remaining player gets a regular game over")


# --- #8 one room per connection -----------------------------------------------

func test_double_create_leaves_the_first_room_without_a_ghost() -> void:
	var mgr := RoomManager.new(21)
	var r1 := mgr.create_room(101, "A")
	var r2 := mgr.create_room(101, "A") # double-tapped "Create"
	assert_eq(r1.members.size(), 0, "the first room was left properly")
	assert_eq(mgr.room_of(101), r2)
	mgr.on_disconnect(101, 1000.0)
	mgr.tick(1000.0 + GRACE + 1.0)
	assert_eq(mgr.rooms.size(), 0, "no room survives forever")


func test_joining_another_room_leaves_the_old_one() -> void:
	var mgr := RoomManager.new(22)
	var a := mgr.create_room(101, "A")
	var b := mgr.create_room(201, "B")
	assert_true(mgr.join_room(101, b.code, "A", "").ok)
	assert_eq(a.members.size(), 0)
	assert_eq(b.members.size(), 2)
	assert_eq(mgr.join_room(201, "ZZZZZ", "B", "").error, "no_such_room")
	assert_eq(mgr.room_of(201), b, "a failed join keeps the current room")
	assert_true(mgr.join_room(101, b.code, "A", "").ok)
	assert_eq(b.members.size(), 2, "re-joining the same room adds no seat")


# --- #9 host = first connected, purge is broadcast ------------------------

func test_dropped_host_does_not_block_the_start() -> void:
	var room := _room3("HOSTX", 9)
	room.on_disconnect(101, 1000.0)
	assert_true(room.is_host(102), "the first connected member hosts")
	assert_eq(room.lobby_info().host, "S2")
	assert_true(room.start_game(102, {}).ok)


func test_purge_broadcasts_the_new_lobby() -> void:
	var room := FaraonRoom.new("PURGE", 10)
	room.join(101, "Host")
	room.join(102, "B")
	room.on_disconnect(101, 0.0)
	room.outbox = []
	room.purge(GRACE + 1.0)
	var updates := _msgs(room, "cl_room_update")
	assert_eq(updates.size(), 1)
	assert_eq(updates[0].peer, 102)
	var info: Dictionary = updates[0].args[0]
	assert_eq(info.members.size(), 1)
	assert_eq(info.host, "S2")


# --- #19 per-room draining ------------------------------------------------

func test_drain_touches_only_rooms_with_output() -> void:
	var mgr := RoomManager.new(23)
	var a := mgr.create_room(101, "A")
	var b := mgr.create_room(201, "B")
	mgr.drain_outbox()
	assert_true(mgr._dirty.is_empty())
	mgr.join_room(102, a.code, "A2", "")
	assert_eq(mgr._dirty.keys(), [a.code], "only the touched room is dirty")
	var msgs := mgr.drain_outbox()
	assert_gt(msgs.size(), 0)
	assert_true(mgr._dirty.is_empty())
	# Calls made directly on a room (the hub's start/propose path) mark it too.
	a.start_game(101, {})
	assert_eq(mgr._dirty.keys(), [a.code])
	assert_gt(mgr.drain_outbox().size(), 0)
	assert_true(b.outbox.is_empty())


# --- #5 / #12 RoomClient reconnect + room state -------------------------------

class FakeClient:
	extends RoomClient
	var sent: Array = []
	var connects := 0
	var online := false

	func _send(fn: String, args: Array) -> bool:
		if not online:
			return false
		sent.append([fn, args])
		return true

	func _connect_to_server() -> bool:
		connects += 1
		return true


func _hub() -> Node:
	return get_node("/root/NetHub")


func _seated_client() -> FakeClient:
	var c := FakeClient.new()
	add_child_autofree(c)
	_hub().joined.emit("ABCDE", "S2", "tok123")
	return c


func test_client_reconnects_with_its_token() -> void:
	var c := _seated_client()
	watch_signals(c)
	_hub().connection_failed_or_lost.emit()
	assert_signal_emitted_with_parameters(c, "reconnecting", [1])
	assert_true(c.is_reconnecting())
	assert_eq(c.room_code, "ABCDE", "room + token survive the attempt")
	assert_eq(c._reconnect_timer.wait_time, RoomClient.RECONNECT_DELAYS[0])
	c._attempt_reconnect()
	assert_eq(c.connects, 1)
	c.online = true
	_hub().connected_to_server.emit()
	assert_eq(c.sent, [["sv_join_room", ["ABCDE", "", "tok123"]]])
	_hub().joined.emit("ABCDE", "S2", "tok123")
	assert_signal_emitted(c, "reconnected")
	assert_false(c.is_reconnecting())
	assert_true(c._reconnect_timer.is_stopped())


func test_reconnect_backoff_grows() -> void:
	var c := _seated_client()
	var waits := []
	for _i in 6:
		_hub().connection_failed_or_lost.emit()
		waits.append(c._reconnect_timer.wait_time)
	assert_eq(waits, [1.0, 2.0, 4.0, 8.0, 15.0, 15.0])


func test_reconnect_gives_up_and_clears_the_room() -> void:
	var c := _seated_client()
	watch_signals(c)
	_hub().connection_failed_or_lost.emit()
	_hub().join_failed.emit("no_such_room")
	assert_signal_emitted_with_parameters(c, "reconnect_failed", ["no_such_room"])
	assert_eq(c.room_code, "")
	assert_eq(c.my_token, "")
	assert_eq(c.my_seat, "")
	# Timeout path.
	var d := _seated_client()
	watch_signals(d)
	_hub().connection_failed_or_lost.emit()
	d._reconnect_started_ms -= int(RoomClient.RECONNECT_GIVE_UP_SEC * 1000.0) + 1000
	_hub().connection_failed_or_lost.emit()
	assert_signal_emitted_with_parameters(d, "reconnect_failed", ["timeout"])
	assert_false(d.is_in_room())


func test_no_reconnect_when_not_seated() -> void:
	var c := FakeClient.new()
	add_child_autofree(c)
	watch_signals(c)
	_hub().connection_failed_or_lost.emit()
	assert_signal_not_emitted(c, "reconnecting")


func test_resync_snapshot_rerenders_the_running_game() -> void:
	var room := FaraonRoom.new("RESYN", 12)
	room.join(101, "A")
	room.join(102, "B")
	room.start_game(101, {})
	var c := _seated_client()
	c._apply_view(room._view_for("S2"))
	_hub().connection_failed_or_lost.emit()
	c.online = true
	_hub().connected_to_server.emit()
	_hub().joined.emit("ABCDE", "S2", "tok123")
	watch_signals(c)
	_hub().game_started.emit(room._view_for("S2"))
	assert_signal_emitted_with_parameters(c, "state_updated", [[]])


func test_leave_clears_room_state_and_tells_the_server() -> void:
	var c := _seated_client()
	c.online = true
	c.leave()
	assert_eq(c.sent, [["sv_leave", []]])
	assert_false(c.is_in_room())
	assert_eq(c.my_token, "")


func test_propose_while_offline_is_rejected_not_lost() -> void:
	var c := _seated_client()
	watch_signals(c)
	var res := c.propose("S2", FaraonActions.draw())
	assert_false(res.ok)
	assert_signal_emitted_with_parameters(c, "action_rejected", ["S2", "offline"])


func test_deliberate_disconnect_stops_reconnecting() -> void:
	var c := _seated_client()
	_hub().connection_failed_or_lost.emit()
	_hub().client_disconnected.emit()
	assert_false(c.is_reconnecting())
	assert_false(c.is_in_room())


# --- #14 NetHub idles offline ---------------------------------------------

func test_nethub_does_no_per_frame_work_offline() -> void:
	var hub := _hub()
	assert_false(hub.is_server)
	assert_false(hub.is_processing(), "no _process in single-player")
	watch_signals(hub)
	hub.disconnect_client()
	assert_signal_emitted(hub, "client_disconnected")
	assert_false(hub.is_connected_client)
	assert_true(hub.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


# --- #7 one continuation per interstitial -----------------------------------

class FlakyNet:
	extends AdNetwork
	var fail_next := false

	func is_online() -> bool:
		return true

	func show_interstitial() -> void:
		if fail_next:
			interstitial_failed.emit()
		else:
			interstitial_closed.emit()


func test_each_interstitial_runs_its_continuation_exactly_once() -> void:
	var net := FlakyNet.new()
	var ctrl := AdsController.new(net)
	var calls := {}
	for i in 3:
		ctrl._armed = true
		ctrl.run_after_results(func(): calls[i] = int(calls.get(i, 0)) + 1)
	assert_eq(net.interstitial_closed.get_connections().size(), 0)
	assert_eq(net.interstitial_failed.get_connections().size(), 0,
			"no listener stays behind after an ad")
	net.fail_next = true
	ctrl._armed = true
	ctrl.run_after_results(func(): calls["failed"] = int(calls.get("failed", 0)) + 1)
	assert_eq(calls, {0: 1, 1: 1, 2: 1, "failed": 1},
			"a failed ad never re-runs older continuations")


# --- #10 / #15 / #19 IAP ----------------------------------------------------

func test_subscription_never_overwrites_lifetime() -> void:
	MonetizationStore.set_lifetime()
	var iap := Iap.new()
	iap.backend.purchase_completed.emit(Iap.PRODUCT_YEARLY, "subscription", T0 - 10)
	assert_eq(MonetizationStore.premium_kind(), "lifetime")
	assert_true(MonetizationStore.is_premium(T0 + 10 * 365 * 24 * 3600))
	MonetizationStore.clear_premium()


func test_older_subscription_receipt_does_not_shorten_premium() -> void:
	MonetizationStore.clear_premium()
	MonetizationStore.set_subscription(T0 + 1000)
	Iap._apply_entitlement("subscription", T0 + 10)
	assert_eq(MonetizationStore.premium_until(), T0 + 1000)
	Iap._apply_entitlement("subscription", T0 + 5000)
	assert_eq(MonetizationStore.premium_until(), T0 + 5000, "renewals extend")
	MonetizationStore.clear_premium()


func test_iap_is_freed_with_its_last_reference() -> void:
	var iap := Iap.new()
	var w: WeakRef = weakref(iap)
	var wb: WeakRef = weakref(iap.backend)
	iap = null
	assert_null(w.get_ref(), "no Iap <-> backend reference cycle")
	assert_null(wb.get_ref())


class AsyncBackend:
	extends StoreBackend
	var asked_until := -1

	func validate_subscription(cached_until: int) -> void:
		asked_until = cached_until # answers later, like a real store


func _start_revalidation() -> WeakRef:
	var backend := AsyncBackend.new()
	Iap.refresh_entitlements(backend)
	return weakref(backend)


func test_revalidation_backend_survives_until_the_store_answers() -> void:
	MonetizationStore.clear_premium()
	MonetizationStore.set_subscription(T0 + 100)
	var w := _start_revalidation()
	var backend: AsyncBackend = w.get_ref()
	assert_not_null(backend, "kept alive after refresh_entitlements returned")
	assert_eq(backend.asked_until, T0 + 100)
	backend.purchase_completed.emit(Iap.PRODUCT_YEARLY, "subscription", T0 + 99999)
	assert_eq(MonetizationStore.premium_until(), T0 + 99999, "late renewal applied")
	Iap._revalidation_backend = null
	MonetizationStore.clear_premium()


# --- #16 backwards clock --------------------------------------------------

func test_clock_going_backwards_does_not_reset_the_ad_counter() -> void:
	var state := AdPolicy.fresh_state()
	for i in 3:
		state = AdPolicy.register_completed_game(state, T0 + i * 60)["state"]
	# NTP pulls the clock back a few minutes: the 4th game still shows an ad.
	var r := AdPolicy.register_completed_game(state, T0 - 300)
	assert_eq(int(r["state"]["games_in_window"]), 4)
	assert_true(r["ad_due"])
	assert_eq(int(AdPolicy.on_app_open(r["state"], T0 - 3600)["games_in_window"]), 4,
			"opening the app with an earlier clock keeps the count too")
	# The re-anchored window still expires normally afterwards.
	var anchored: Dictionary = AdPolicy.on_app_open(r["state"], T0 - 3600)
	assert_eq(int(AdPolicy.on_app_open(anchored,
			T0 - 3600 + AdPolicy.WINDOW_SECONDS)["games_in_window"]), 0)
