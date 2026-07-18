extends GutTest
## Unit tests for the Olympic match layer (game/faraon_match.gd) and the
## progression math (progression/progression.gd — approved numbers).


func _ended_state(ids: Array, positions: Array) -> GameState:
	var s := GameState.new()
	for i in ids.size():
		var p := GameState.PlayerState.new()
		p.id = ids[i]
		p.finish_position = positions[i]
		s.players.append(p)
	s.phase = GameState.Phase.GAME_OVER
	return s


# --- per-player hand sizes in the engine -----------------------------------

func test_start_deals_per_player_hand_sizes() -> void:
	var r := FaraonRules.new()
	var events := r.start(["A", "B", "C"], RulesVariant.classic(), 999,
			{"A": 5, "B": 3, "C": 1})
	assert_eq(r.state.player_by_id("A").hand.size(), 5)
	assert_eq(r.state.player_by_id("B").hand.size(), 3)
	assert_eq(r.state.player_by_id("C").hand.size(), 1)
	var dealt: Dictionary = events[0].hands
	assert_eq(dealt, {"A": 5, "B": 3, "C": 1})


# --- olympic match (B2 rozstrely + B1 rotácia) -------------------------------

func test_olympic_loser_shrinks_and_gets_eliminated() -> void:
	var m := FaraonMatch.new(FaraonMatch.Mode.OLYMPIC, ["A", "B", "C"])
	assert_eq(m.hand_sizes(), {"A": 5, "B": 5, "C": 5})
	m.on_sub_round_over(_ended_state(["A", "B", "C"], [1, 2, 3]))
	assert_eq(m.allotments["C"], 4, "posledný v kole začína s kartou menej")
	assert_eq(m.allotments["A"], 5)
	for _i in 4:
		m.on_sub_round_over(_ended_state(["A", "B", "C"], [1, 2, 3]))
	assert_false(m.participants().has("C"), "na nule C vypadáva zo zápasu")
	assert_false(m.finished, "dvaja hráči pokračujú")


func test_olympic_last_standing_wins_match() -> void:
	var m := FaraonMatch.new(FaraonMatch.Mode.OLYMPIC, ["A", "B"])
	for _i in 5:
		assert_false(m.finished)
		m.on_sub_round_over(_ended_state(["A", "B"], [1, 2]))
	assert_true(m.finished)
	assert_eq(m.champion, "A")


func test_reverse_olympic_winner_sheds_and_wins_match() -> void:
	var m := FaraonMatch.new(FaraonMatch.Mode.REVERSE_OLYMPIC, ["A", "B", "C"])
	m.on_sub_round_over(_ended_state(["A", "B", "C"], [2, 1, 3]))
	assert_eq(m.allotments["B"], 4, "víťaz kola zhadzuje kartu")
	assert_eq(m.allotments["C"], 5, "porazený si prídel drží")
	for _i in 3:
		m.on_sub_round_over(_ended_state(["A", "B", "C"], [2, 1, 3]))
	assert_false(m.finished)
	m.on_sub_round_over(_ended_state(["A", "B", "C"], [2, 1, 3]))
	assert_true(m.finished, "kto prvý zhodí všetko, vyhráva zápas")
	assert_eq(m.champion, "B")


func test_b2_shootout_ranks_the_remaining_places() -> void:
	# Sub-kolo 1: dohrá len A (1. miesto kola) → rozstrel B+C; sub-kolo 2:
	# dohrá B (2. miesto) → C je posledný bez hrania a kolo sa boduje.
	var m := FaraonMatch.new(FaraonMatch.Mode.OLYMPIC, ["A", "B", "C"], "A")
	var r1 := m.on_sub_round_over(_ended_state(["A", "B", "C"], [1, -1, -1]))
	assert_false(r1.kolo_done)
	assert_eq(r1.shootout, ["B", "C"], "rozstrel hrajú neumiestnení")
	assert_eq(m.hand_sizes().keys(), ["B", "C"],
			"rozstrel sa rozdáva len zvyšným hráčom")
	var r2 := m.on_sub_round_over(_ended_state(["B", "C"], [1, -1]))
	assert_true(r2.kolo_done)
	assert_eq(r2.placements, ["A", "B", "C"])
	assert_eq(r2.get("loser", ""), "C", "posledné miesto kola stráca kartu")
	assert_eq(m.allotments["C"], 4)


func test_b1_starter_rotates_clockwise_each_kolo() -> void:
	# B4 scenár 3: rotácia štartéra cez 3 po sebe idúce kolá pri 4 hráčoch.
	var m := FaraonMatch.new(FaraonMatch.Mode.OLYMPIC, ["A", "B", "C", "D"], "B")
	assert_eq(m.starter_id, "B", "prvého štartéra určuje RNG (meta-vrstva)")
	m.on_sub_round_over(_ended_state(["A", "B", "C", "D"], [1, 2, 3, 4]))
	assert_eq(m.starter_id, "C", "kolo 2 začína ďalší v smere hodinových ručičiek")
	m.on_sub_round_over(_ended_state(["A", "B", "C", "D"], [1, 2, 3, 4]))
	assert_eq(m.starter_id, "D", "kolo 3 pokračuje v rotácii")
	m.on_sub_round_over(_ended_state(["A", "B", "C", "D"], [1, 2, 3, 4]))
	assert_eq(m.starter_id, "A", "rotácia sa pretáča cez koniec poradia")


func test_b1_shootout_starter_rotates_within_the_rest() -> void:
	var m := FaraonMatch.new(FaraonMatch.Mode.OLYMPIC, ["A", "B", "C"], "A")
	m.on_sub_round_over(_ended_state(["A", "B", "C"], [1, -1, -1]))
	assert_eq(m.sub_starter_id, "B", "rozstrel štartuje ďalší v poradí zo zvyšku")
	assert_eq(m.sub_start_index(), 0, "index v poli hráčov rozstrelu [B, C]")


# --- progression math (approved numbers) ------------------------------------

func test_points_table_and_multipliers() -> void:
	assert_eq(Progression.points_for(2, 1, "medium"), 100)
	assert_eq(Progression.points_for(2, 2, "medium"), 0, "last place = 0")
	assert_eq(Progression.points_for(4, 1, "hard"), 240, "160 x 1.5")
	assert_eq(Progression.points_for(4, 2, "medium"), 70)
	assert_eq(Progression.points_for(2, 1, "easy"), 50, "100 x 0.5")
	assert_eq(Progression.points_for(3, 2, "multiplayer"), 90, "45 x 2.0")
	assert_eq(Progression.points_for(5, 4, "medium"), 20)


func test_level_curve() -> void:
	assert_eq(Progression.cost_of_level(1), 500)
	assert_eq(Progression.cost_of_level(2), 600)
	assert_eq(Progression.level_for(0), 1)
	assert_eq(Progression.level_for(499), 1)
	assert_eq(Progression.level_for(500), 2)
	assert_eq(Progression.level_for(1100), 3)
	assert_eq(Progression.level_for(8100), 10)
	var prog := Progression.progress_for(700)
	assert_eq(prog.level, 2)
	assert_eq(prog.into, 200)
	assert_eq(prog.needed, 600)
