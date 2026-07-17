extends GutTest
## Unit tests for daily challenges, the streak rule and the statistics
## counters. The progression save is backed by user://progression.cfg, so
## each test starts from a wiped file.


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProgressionStore.PATH))


func test_active_ids_are_deterministic_and_three() -> void:
	var a := Challenges.active_ids()
	var b := Challenges.active_ids()
	assert_eq(a, b, "same day picks the same challenges")
	assert_eq(a.size(), Challenges.ACTIVE_PER_DAY)
	for id in a:
		assert_true(Challenges.POOL.has(id))


func test_game_finish_steps_play_challenge_and_streak() -> void:
	Challenges.on_game_finished(4, 2, "medium", "normal")
	assert_eq(Challenges.streak(), 1, "first game today starts the streak")
	assert_true(Challenges.played_today())
	if Challenges.active_ids().has("play_3"):
		var today := Challenges.today()
		for ch in today:
			if ch.id == "play_3":
				assert_eq(ch.progress, 1)


func test_challenge_completion_awards_points_once() -> void:
	if not Challenges.active_ids().has("play_3"):
		pass_test("play_3 not active today - deterministic pool rotation")
		return
	var before := ProgressionStore.total_points()
	Challenges.on_game_finished(2, 2, "medium", "normal")
	Challenges.on_game_finished(2, 2, "medium", "normal")
	Challenges.on_game_finished(2, 2, "medium", "normal")
	var after_three := ProgressionStore.total_points()
	assert_eq(after_three - before, Challenges.CHALLENGE_POINTS,
			"completing play_3 pays out exactly once")
	Challenges.on_game_finished(2, 2, "medium", "normal")
	assert_eq(ProgressionStore.total_points(), after_three,
			"a done challenge never pays again")


func test_event_observation_tracks_esa() -> void:
	if not Challenges.active_ids().has("play_esa"):
		pass_test("play_esa not active today")
		return
	Challenges.observe_event({"type": "CARDS_PLAYED", "player": "YOU",
			"cards": ["AZ", "AC"]}, "YOU")
	for ch in Challenges.today():
		if ch.id == "play_esa":
			assert_true(ch.done, "two aces at once complete the challenge")


func test_stats_counters_slice_by_context_mode_and_position() -> void:
	ProgressionStore.record(100, true, "hard", "olympic", 1, 4)
	ProgressionStore.record(0, false, "hard", "normal", 4, 4)
	ProgressionStore.record(70, false, "medium", "normal", 2, 4)
	assert_eq(ProgressionStore.counter("games_hard"), 2)
	assert_eq(ProgressionStore.counter("wins_hard"), 1)
	assert_eq(ProgressionStore.counter("games_medium"), 1)
	assert_eq(ProgressionStore.counter("mode_normal"), 2)
	assert_eq(ProgressionStore.counter("mode_olympic"), 1)
	assert_eq(ProgressionStore.counter("pos_1"), 1)
	assert_eq(ProgressionStore.counter("pos_2"), 1)
	assert_eq(ProgressionStore.counter("pos_4"), 1)


func test_friend_log_accumulates() -> void:
	ProgressionStore.bump_friend("Katka")
	ProgressionStore.bump_friend("Katka")
	ProgressionStore.bump_friend("Jano")
	var f := ProgressionStore.friends()
	assert_eq(f.get("Katka"), 2)
	assert_eq(f.get("Jano"), 1)
