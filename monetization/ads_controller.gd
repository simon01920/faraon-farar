class_name AdsController
extends RefCounted
## Bridges the pure AdPolicy + persisted counter to a concrete AdNetwork. This
## is the object the game talks to ("a game just finished", "show the menu
## banner"); it decides nothing about frequency itself — that stays in AdPolicy
## so it can be tested — and it owns the offline/premium short-circuits.
##
## Two-phase so an interstitial never covers the result screen or gameplay:
##   1. on_game_completed()  — when the game ends and its result screen shows:
##      advance the counter, decide, and (if due) ARM an interstitial;
##   2. run_after_results()  — when the player leaves the result screen (New
##      game / Menu): show the armed interstitial, then continue once closed.
##
## Offline behaviour (final decision, per zadanie 1.2): the counter runs even
## offline so ads cannot be dodged in airplane mode, but an interstitial that
## comes due while offline is NOT stacked — a single `interstitial_pending`
## flag is set and the one owed ad shows at the next online game. Premium
## players skip the whole path: the counter never even advances.

enum Decision {
	NONE,  # nothing to show for this game
	SHOW,  # arm an interstitial (shown at the next transition)
	DEFER, # one is owed but we are offline — remember it, show later
}

var network: AdNetwork
## An interstitial has been decided for the just-finished game and will show
## when the player leaves the result screen.
var _armed := false
## Continuation waiting for the interstitial currently on screen.
var _pending_then := Callable()


func _init(ad_network: AdNetwork = null) -> void:
	network = ad_network if ad_network != null else AdNetwork.MockAdNetwork.new()


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func is_premium() -> bool:
	return MonetizationStore.is_premium(_now())


func interstitial_armed() -> bool:
	return _armed


## Pure decision table — unit-tested directly. Given the frequency verdict
## (`ad_due`), whether one was already owed (`pending`) and connectivity,
## returns what to do. Premium is handled by the caller before this runs.
static func decide(ad_due: bool, pending: bool, online: bool) -> Decision:
	if not (ad_due or pending):
		return Decision.NONE
	return Decision.SHOW if online else Decision.DEFER


## Call once when a game has fully finished and its result screen is up.
## Advances the counter and ARMS (does not yet show) an interstitial. Premium
## players return immediately — the frequency logic never runs for them.
func on_game_completed() -> Decision:
	if is_premium():
		return Decision.NONE
	var result := AdPolicy.register_completed_game(
			MonetizationStore.ad_state(), _now())
	MonetizationStore.set_ad_state(result["state"])
	var decision := decide(bool(result["ad_due"]),
			MonetizationStore.interstitial_pending(), network.is_online())
	match decision:
		Decision.SHOW:
			MonetizationStore.set_interstitial_pending(false)
			_armed = true
		Decision.DEFER:
			MonetizationStore.set_interstitial_pending(true)
	return decision


## Call when the player leaves the result screen (New game / Back to menu).
## Shows the armed interstitial and runs `then` once it closes; if nothing is
## armed (or the ad fails), `then` runs straight away so the player is never
## stranded on a black screen.
func run_after_results(then: Callable) -> void:
	if not _armed:
		then.call()
		return
	_armed = false
	# Exactly one continuation per shown ad: whichever of closed/failed fires
	# first runs it and disconnects BOTH listeners (a one-shot per signal
	# left the other connected, and a later ad re-ran every old `then`).
	_pending_then = then
	if not network.interstitial_closed.is_connected(_on_interstitial_done):
		network.interstitial_closed.connect(_on_interstitial_done)
	if not network.interstitial_failed.is_connected(_on_interstitial_done):
		network.interstitial_failed.connect(_on_interstitial_done)
	network.show_interstitial()


func _on_interstitial_done() -> void:
	if network.interstitial_closed.is_connected(_on_interstitial_done):
		network.interstitial_closed.disconnect(_on_interstitial_done)
	if network.interstitial_failed.is_connected(_on_interstitial_done):
		network.interstitial_failed.disconnect(_on_interstitial_done)
	var then := _pending_then
	_pending_then = Callable()
	if then.is_valid():
		then.call()


## Reset the ad window if the player has been away >= 6h (call on app open).
func on_app_open() -> void:
	if is_premium():
		return
	MonetizationStore.set_ad_state(
			AdPolicy.on_app_open(MonetizationStore.ad_state(), _now()))


## Show the banner in a menu screen — unless the player is premium.
func show_menu_banner() -> void:
	if is_premium():
		network.hide_banner()
		return
	network.show_banner()


func hide_banner() -> void:
	network.hide_banner()
