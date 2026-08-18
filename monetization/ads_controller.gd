class_name AdsController
extends RefCounted
## Bridges the pure AdPolicy + persisted counter to a concrete AdNetwork. This
## is the object the game talks to ("a game just finished", "show the menu
## banner"); it decides nothing about frequency itself — that stays in AdPolicy
## so it can be tested — and it owns the offline/premium short-circuits.
##
## Offline behaviour (final decision, per zadanie 1.2): the game counter runs
## even offline so ads cannot be dodged in airplane mode, but an interstitial
## that comes due while offline is NOT stacked — a single `interstitial_pending`
## flag is set and the one owed ad shows at the next opportunity when online.
## Premium players skip the whole path: the counter never even advances.

## What should happen for a completed game.
enum Decision {
	NONE,  # nothing to show
	SHOW,  # show an interstitial now
	DEFER, # one is owed but we are offline — remember it, show later
}

var network: AdNetwork


func _init(ad_network: AdNetwork = null) -> void:
	network = ad_network if ad_network != null else AdNetwork.MockAdNetwork.new()


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func is_premium() -> bool:
	return MonetizationStore.is_premium(_now())


## Pure decision table — unit-tested directly. Given the frequency verdict
## (`ad_due`), whether one was already owed (`pending`) and connectivity,
## returns what to do. Premium is handled by the caller before this runs.
static func decide(ad_due: bool, pending: bool, online: bool) -> Decision:
	if not (ad_due or pending):
		return Decision.NONE
	return Decision.SHOW if online else Decision.DEFER


## Call exactly once when a game has fully finished and its result screen has
## been shown. Advances the counter and shows/defers an interstitial. Premium
## players return immediately — the frequency logic never runs for them.
## Returns the Decision taken (handy for tests / logging).
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
			network.show_interstitial()
		Decision.DEFER:
			MonetizationStore.set_interstitial_pending(true)
	return decision


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
