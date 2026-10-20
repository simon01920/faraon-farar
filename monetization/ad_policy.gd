class_name AdPolicy
extends RefCounted
## Pure, side-effect-free decision logic for WHEN an interstitial may show.
## Deliberately knows nothing about any ad SDK, ConfigFile, or the clock — the
## caller injects `now` (unix seconds) and the persisted counter state. This is
## the fully unit-testable core the monetization module is built around; the
## AdsController wires it to storage + the real network.
##
## Rule (záväzné, zo zadania):
##   * a 6-hour window; opening the app (or completing a game) after >= 6h
##     since the window started resets the counter to zero and starts a new one;
##   * games 1, 2, 3 in a window are completely ad-free;
##   * from game 4 on, an interstitial is due after every 2nd game:
##     games 4, 6, 8, 10, ... (i.e. index >= 4 and even).

## First N games of every window are clean.
const CLEAN_GAMES := 3
## Window length in seconds (6 hours).
const WINDOW_SECONDS := 6 * 60 * 60


## Fresh, empty counter state. `window_start == -1` means "no window yet";
## the first completed game opens one.
static func fresh_state() -> Dictionary:
	return {"window_start": -1, "games_in_window": 0}


## Normalises whatever came out of storage into the shape the logic expects,
## so a corrupt/old save can never crash the caller.
static func sanitize(state: Variant) -> Dictionary:
	var s: Dictionary = state if state is Dictionary else {}
	return {
		"window_start": int(s.get("window_start", -1)),
		"games_in_window": maxi(0, int(s.get("games_in_window", 0))),
	}


## Has the current window elapsed relative to `now`? A never-started window
## (window_start == -1) is treated as elapsed so the first game opens one.
## A clock that is now BEFORE the window start (NTP correction, manual time
## change) does not count as elapsed — see _reanchor.
static func window_elapsed(state: Dictionary, now: int) -> bool:
	var start: int = int(state.get("window_start", -1))
	if start < 0:
		return true
	return now >= start and now - start >= WINDOW_SECONDS


## Hodiny idúce dozadu (NTP korekcia o sekundu, ručná zmena času) nesmú
## vynulovať počítadlo — inak by sa reklamy dali obísť posunutím času. Okno
## sa len ukotví na „teraz", odohrané hry v ňom ostávajú.
static func _reanchor(s: Dictionary, now: int) -> Dictionary:
	if int(s["window_start"]) > now:
		s["window_start"] = now
	return s


## Would the n-th completed game of a window be shown an interstitial?
## games 1-3 -> false, 4 -> true, 5 -> false, 6 -> true, ...
static func game_shows_ad(game_index: int) -> bool:
	return game_index > CLEAN_GAMES and game_index % 2 == 0


## Applies one completed game to the state. Returns
##   {"state": <new counter state>, "ad_due": bool}
## where `ad_due` means "this game earns an interstitial" per the frequency
## rule alone (premium / offline handling lives in the controller, not here).
static func register_completed_game(state: Dictionary, now: int) -> Dictionary:
	var s := _reanchor(sanitize(state), now)
	if window_elapsed(s, now):
		s = {"window_start": now, "games_in_window": 0}
	s["games_in_window"] = int(s["games_in_window"]) + 1
	return {"state": s, "ad_due": game_shows_ad(int(s["games_in_window"]))}


## Resets the window if it has elapsed — call on app open so a returning player
## who was away >= 6h gets three fresh clean games. Never counts a game itself.
static func on_app_open(state: Dictionary, now: int) -> Dictionary:
	var s := _reanchor(sanitize(state), now)
	if window_elapsed(s, now):
		return fresh_state()
	return s
