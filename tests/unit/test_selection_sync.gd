extends GutTest
## Unit testy kozmetickej synchronizácie výberu kariet (selection glow) na
## transport-free FaraonRoom: relay ostatným, čistenie pri akcii/odpojení
## a prítomnosť v reconnect snapshotе. Žiadny socket — kontroluje sa outbox.


func _make_room_with_game() -> FaraonRoom:
	var room := FaraonRoom.new("TESTX", 42)
	room.join(101, "Simon")
	room.join(202, "Peter")
	room.start_game(101, {})
	room.outbox.clear()
	return room


func _sel_msgs(room: FaraonRoom) -> Array:
	return room.outbox.filter(func(m): return m.fn == "cl_selection")


func test_selection_relays_to_other_members_only() -> void:
	var room := _make_room_with_game()
	room.set_selection(101, 3)
	var msgs := _sel_msgs(room)
	assert_eq(msgs.size(), 1, "výber ide len ostatným, nie odosielateľovi")
	assert_eq(msgs[0].peer, 202)
	assert_eq(msgs[0].args, ["S1", 3])
	assert_eq(int(room.selections.get("S1", 0)), 3)


func test_duplicate_selection_is_not_rebroadcast() -> void:
	var room := _make_room_with_game()
	room.set_selection(101, 2)
	room.outbox.clear()
	room.set_selection(101, 2)
	assert_eq(_sel_msgs(room).size(), 0, "rovnaká hodnota sa neposiela znova")


func test_selection_clamped_and_zero_erases() -> void:
	var room := _make_room_with_game()
	room.set_selection(101, 99)
	assert_eq(int(room.selections.get("S1", 0)), 8, "clamp na rozumný strop")
	room.set_selection(101, 0)
	assert_false(room.selections.has("S1"), "nula výber odstraňuje")


func test_applied_action_clears_the_selection() -> void:
	var room := _make_room_with_game()
	var seat: String = room.rules.state.players[room.rules.state.current_index].id
	var peer: int = 101 if seat == "S1" else 202
	room.set_selection(peer, 4)
	room.outbox.clear()
	room.propose(peer, FaraonActions.draw())
	assert_false(room.selections.has(seat),
			"aplikovaná akcia zneplatňuje rozpracovaný výber")
	var clear_msgs := _sel_msgs(room).filter(func(m): return m.args == [seat, 0])
	assert_gt(clear_msgs.size(), 0, "ostatní dostanú explicitné vynulovanie")


func test_disconnect_clears_the_selection_for_others() -> void:
	var room := _make_room_with_game()
	room.set_selection(101, 4)
	room.outbox.clear()
	room.on_disconnect(101, Time.get_unix_time_from_system())
	assert_false(room.selections.has("S1"),
			"výber odpojeného hráča nesmie ostať zaseknutý")
	var clear_msgs := _sel_msgs(room).filter(func(m): return m.args == ["S1", 0])
	assert_eq(clear_msgs.size(), 1)


func test_snapshot_view_carries_live_selections() -> void:
	var room := _make_room_with_game()
	room.set_selection(101, 2)
	var view := room._view_for("S2")
	assert_eq(view.get("selections", {}), {"S1": 2},
			"reconnect snapshot obsahuje aktuálne výbery")


func test_selection_ignored_outside_a_running_game() -> void:
	var room := FaraonRoom.new("TESTY", 43)
	room.join(101, "Simon")
	room.outbox.clear()
	room.set_selection(101, 3)
	assert_true(room.selections.is_empty(), "v lobby sa výber neeviduje")
	assert_eq(_sel_msgs(room).size(), 0)
