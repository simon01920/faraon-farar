extends GutTest
## Monetizácia: čistá frekvenčná logika reklám (AdPolicy), premium stav
## (MonetizationStore) a rozhodovacia tabuľka kontroléra vrátane offline
## správania. Presne pokrýva 6 scenárov zo zadania — bez reálneho SDK.

const T0 := 1_700_000_000 # pevný "teraz" (unix), aby boli testy deterministické
const HOUR := 3600
const WINDOW := AdPolicy.WINDOW_SECONDS # 6 h


func before_each() -> void:
	# Každý test začína s čistým lokálnym úložiskom monetizácie.
	DirAccess.remove_absolute(
			ProjectSettings.globalize_path(MonetizationStore.PATH))


func after_all() -> void:
	DirAccess.remove_absolute(
			ProjectSettings.globalize_path(MonetizationStore.PATH))


# --- scenár 1: čerstvý reset, 1-2-3 čisté, 4 a 6 reklama -------------------

func test_scenario_1_first_three_clean_then_every_second() -> void:
	var state := AdPolicy.fresh_state()
	var expected := [false, false, false, true, false, true, false, true]
	for i in expected.size():
		var r := AdPolicy.register_completed_game(state, T0 + i * 60)
		state = r["state"]
		assert_eq(r["ad_due"], expected[i],
				"hra %d: očakávané ad_due=%s" % [i + 1, expected[i]])
	assert_eq(int(state["games_in_window"]), 8)


# --- scenár 2: návrat do 6 h — počítadlo pokračuje ------------------------

func test_scenario_2_return_within_window_keeps_counting() -> void:
	var state := AdPolicy.fresh_state()
	for i in 4: # štyri hry, window_start = T0
		state = AdPolicy.register_completed_game(state, T0 + i * 60)["state"]
	# Návrat po 3 hodinách (menej ako 6 h): okno sa NEresetuje.
	var back := T0 + 3 * HOUR
	assert_false(AdPolicy.window_elapsed(state, back), "okno ešte beží")
	var g5 := AdPolicy.register_completed_game(state, back)
	assert_false(g5["ad_due"], "5. hra bez reklamy")
	var g6 := AdPolicy.register_completed_game(g5["state"], back + 60)
	assert_true(g6["ad_due"], "6. hra s reklamou")


# --- scenár 3: návrat po 6 h — reset, ďalšie 3 čisté ----------------------

func test_scenario_3_return_after_window_resets() -> void:
	var state := AdPolicy.fresh_state()
	for i in 4:
		state = AdPolicy.register_completed_game(state, T0 + i * 60)["state"]
	var back := T0 + 7 * HOUR # viac ako 6 h
	assert_true(AdPolicy.window_elapsed(state, back), "okno vypršalo")
	var expected := [false, false, false, true] # opäť tri čisté, potom reklama
	for i in expected.size():
		var r := AdPolicy.register_completed_game(state, back + i * 60)
		state = r["state"]
		assert_eq(r["ad_due"], expected[i], "po resete hra %d" % [i + 1])


func test_on_app_open_resets_only_after_window() -> void:
	var state: Dictionary = AdPolicy.register_completed_game(
			AdPolicy.fresh_state(), T0)["state"]
	assert_eq(int(AdPolicy.on_app_open(state, T0 + 3 * HOUR)["games_in_window"]), 1,
			"do 6 h sa počítadlo zachová")
	assert_eq(int(AdPolicy.on_app_open(state, T0 + 6 * HOUR)["games_in_window"]), 0,
			"po 6 h sa počítadlo vynuluje")


# --- scenár 4 + 6: premium (lifetime) — nikdy reklama, aj offline ----------

func test_scenario_4_and_6_lifetime_premium_is_always_ad_free() -> void:
	MonetizationStore.set_lifetime()
	assert_true(MonetizationStore.is_premium(T0))
	assert_true(MonetizationStore.is_premium(T0 + 100 * 365 * 24 * HOUR),
			"lifetime nikdy nevyprší")
	# Kontrolér pre premium ani nespustí počítadlo.
	var ctrl := AdsController.new(AdNetwork.MockAdNetwork.new())
	for _i in 10:
		assert_eq(ctrl.on_game_completed(), AdsController.Decision.NONE)
	assert_eq(ctrl.network.interstitials_shown, 0, "premium: žiadna reklama")
	# A počítadlo ostáva netknuté (logika sa vôbec nespustila).
	assert_eq(int(MonetizationStore.ad_state()["games_in_window"]), 0)


# --- scenár 5: subscription vyprší — návrat na free -----------------------

func test_scenario_5_subscription_expiry_returns_to_free() -> void:
	MonetizationStore.set_subscription(T0 + 30 * 24 * HOUR)
	assert_true(MonetizationStore.is_premium(T0), "aktívne predplatné")
	assert_false(MonetizationStore.is_premium(T0 + 31 * 24 * HOUR),
			"po expirácii už nie je premium")


# --- kontrolér: offline defer, žiadne nahromadené reklamné dlhy ------------

func test_offline_defers_a_single_interstitial_then_shows_once_online() -> void:
	var net := AdNetwork.MockAdNetwork.new()
	net.online = false
	var ctrl := AdsController.new(net)
	# Tri čisté hry offline.
	for _i in 3:
		assert_eq(ctrl.on_game_completed(), AdsController.Decision.NONE)
	# 4. hra je „dlžná" reklama, ale offline — odloží sa, nič sa nezobrazí.
	assert_eq(ctrl.on_game_completed(), AdsController.Decision.DEFER)
	assert_eq(net.interstitials_shown, 0)
	assert_true(MonetizationStore.interstitial_pending())
	# Online, 5. hra (sama o sebe bez reklamy) — jediná dlžná sa nazbrojí.
	net.online = true
	assert_eq(ctrl.on_game_completed(), AdsController.Decision.SHOW)
	assert_true(ctrl.interstitial_armed(), "reklama je pripravená, nie zobrazená")
	assert_eq(net.interstitials_shown, 0, "počas výsledkov sa nič neukáže")
	assert_false(MonetizationStore.interstitial_pending())
	# Odchod z výsledkovej obrazovky — vtedy sa zobrazí PRÁVE JEDNA.
	var continued := [false]
	ctrl.run_after_results(func(): continued[0] = true)
	assert_eq(net.interstitials_shown, 1, "žiadne nahromadené reklamy")
	assert_true(continued[0], "pokračovanie beží až po zatvorení reklamy")
	assert_false(ctrl.interstitial_armed())


func test_decide_table() -> void:
	var D := AdsController.Decision
	assert_eq(AdsController.decide(false, false, true), D.NONE)
	assert_eq(AdsController.decide(true, false, true), D.SHOW)
	assert_eq(AdsController.decide(false, true, true), D.SHOW, "dlžná sa ukáže")
	assert_eq(AdsController.decide(true, false, false), D.DEFER, "offline odloží")
	assert_eq(AdsController.decide(false, false, false), D.NONE)


func test_run_after_results_is_instant_when_nothing_armed() -> void:
	var ctrl := AdsController.new(AdNetwork.MockAdNetwork.new())
	var ran := [false]
	ctrl.run_after_results(func(): ran[0] = true)
	assert_true(ran[0], "bez pripravenej reklamy pokračovanie beží hneď")
	assert_eq(ctrl.network.interstitials_shown, 0)


func test_banner_hidden_for_premium() -> void:
	var net := AdNetwork.MockAdNetwork.new()
	var ctrl := AdsController.new(net)
	ctrl.show_menu_banner()
	assert_true(net.banner_visible, "free hráč vidí banner v menu")
	MonetizationStore.set_lifetime()
	ctrl.show_menu_banner()
	assert_false(net.banner_visible, "premium banner nevidí")
