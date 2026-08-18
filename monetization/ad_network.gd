class_name AdNetwork
extends RefCounted
## The thin boundary between our own frequency logic and whatever ad SDK is
## installed. Everything above this line (AdPolicy, AdsController, tests) is
## SDK-free; only a concrete subclass touches a real plugin. The default is
## MockAdNetwork, so the whole game builds and every rule is testable with no
## AdMob plugin present. To ship real ads, drop in an AdMobNetwork subclass
## (see monetization/STORE_SETUP.md) and hand it to AdsController.
##
## Contract: interstitials are STATIC full-screen pop-ups that the user can
## close immediately (X from frame 0, or at worst after 5s) — never rewarded /
## unskippable / auto-play video. Banners appear only in menus.

signal interstitial_closed
signal interstitial_failed

## Whether the device currently has connectivity (ads need it). Real networks
## override with the SDK's reachability; the mock lets tests set it.
func is_online() -> bool:
	return false


## Preload the next interstitial so showing it is instant. No-op for the mock.
func load_interstitial() -> void:
	pass


## Show a static, immediately-closable interstitial. Must emit
## `interstitial_closed` (or `interstitial_failed`) exactly once so the caller
## can continue the flow it paused.
func show_interstitial() -> void:
	interstitial_closed.emit()


func show_banner() -> void:
	pass


func hide_banner() -> void:
	pass


class MockAdNetwork:
	extends AdNetwork
	## Deterministic stand-in for dev + tests: records calls, never draws
	## anything, and lets a test pretend to be on/offline.
	var online := true
	var interstitials_shown := 0
	var banner_visible := false

	func is_online() -> bool:
		return online

	func show_interstitial() -> void:
		interstitials_shown += 1
		interstitial_closed.emit()

	func show_banner() -> void:
		banner_visible = true

	func hide_banner() -> void:
		banner_visible = false
