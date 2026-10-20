class_name MonetizationStore
extends RefCounted
## Local persistence for the monetization layer (user://monetization.cfg):
## the ad-frequency counter, the "one interstitial owed from offline" flag, and
## the cached premium entitlement. Kept separate from GameSettings/Progression
## so the whole module stays self-contained and mockable. Never read by the
## rules engine.
##
## Premium is cached locally so a lifetime buyer stays ad-free fully offline;
## for a subscription the cache is re-validated against the store at startup
## (Iap.refresh_entitlements) with a grace period, never flipped off on a single
## failed check.

const PATH := "user://monetization.cfg"
const SCHEMA_VERSION := 1


static func _load() -> ConfigFile:
	return ConfigCache.get_file(PATH) # missing file is fine — free, fresh counter


static func _save(cfg: ConfigFile) -> void:
	cfg.set_value("meta", "schema_version", SCHEMA_VERSION)
	cfg.save(PATH)


# --- ad-frequency counter --------------------------------------------------

static func ad_state() -> Dictionary:
	var cfg := _load()
	return AdPolicy.sanitize({
		"window_start": cfg.get_value("ads", "window_start", -1),
		"games_in_window": cfg.get_value("ads", "games_in_window", 0),
	})


static func set_ad_state(state: Dictionary) -> void:
	var cfg := _load()
	cfg.set_value("ads", "window_start", int(state.get("window_start", -1)))
	cfg.set_value("ads", "games_in_window", int(state.get("games_in_window", 0)))
	_save(cfg)


## An interstitial was owed while offline; show one (not many) once online.
static func interstitial_pending() -> bool:
	return bool(_load().get_value("ads", "interstitial_pending", false))


static func set_interstitial_pending(pending: bool) -> void:
	var cfg := _load()
	cfg.set_value("ads", "interstitial_pending", pending)
	_save(cfg)


# --- premium entitlement ---------------------------------------------------

## "none" | "lifetime" | "subscription". Lifetime never expires; subscription
## is only trusted until `premium_until` (grace-extended by the store check).
static func premium_kind() -> String:
	return str(_load().get_value("premium", "kind", "none"))


## Unix seconds until which a subscription is considered valid (0 = n/a).
static func premium_until() -> int:
	return int(_load().get_value("premium", "until", 0))


static func set_lifetime() -> void:
	var cfg := _load()
	cfg.set_value("premium", "kind", "lifetime")
	cfg.set_value("premium", "until", 0)
	_save(cfg)


static func set_subscription(valid_until_unix: int) -> void:
	var cfg := _load()
	cfg.set_value("premium", "kind", "subscription")
	cfg.set_value("premium", "until", valid_until_unix)
	_save(cfg)


static func clear_premium() -> void:
	var cfg := _load()
	cfg.set_value("premium", "kind", "none")
	cfg.set_value("premium", "until", 0)
	_save(cfg)


## Is premium active as of `now`? Lifetime always; subscription until its
## expiry. Pure read — the store re-validation happens in Iap.
static func is_premium(now: int) -> bool:
	match premium_kind():
		"lifetime":
			return true
		"subscription":
			return now < premium_until()
		_:
			return false
