class_name ProgressionStore
extends RefCounted
## Local persistence for the progression meta-game (user://progression.cfg).
## Deliberately a single flat, versioned dictionary of monotonic counters so
## a future cloud sync can merge saves by taking per-key maxima — nothing in
## the design assumes local-only storage. Never read by the rules engine.

const PATH := "user://progression.cfg"
const SCHEMA_VERSION := 1


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH) # missing file is fine — zero progress
	return cfg


static func total_points() -> int:
	return _load().get_value("progress", "total_points", 0)


static func games_played() -> int:
	return _load().get_value("progress", "games_played", 0)


static func wins() -> int:
	return _load().get_value("progress", "wins", 0)


## Cosmetic ids unlocked outside the level track (future direct purchases —
## the monetization module appends here through Progression.grant()).
static func extra_unlocks() -> Array:
	return _load().get_value("progress", "extra_unlocks", [])


static func record(points: int, won: bool, context := "medium",
		mode := "normal", position := 0, player_count := 0) -> void:
	var cfg := _load()
	cfg.set_value("progress", "schema_version", SCHEMA_VERSION)
	cfg.set_value("progress", "total_points",
			cfg.get_value("progress", "total_points", 0) + points)
	cfg.set_value("progress", "games_played",
			cfg.get_value("progress", "games_played", 0) + 1)
	if won:
		cfg.set_value("progress", "wins", cfg.get_value("progress", "wins", 0) + 1)
	# Per-slice counters for the statistics screen: all monotonic, so the
	# future cloud sync can still merge by per-key maximum.
	_bump(cfg, "games_" + context)
	if won:
		_bump(cfg, "wins_" + context)
	_bump(cfg, "mode_" + mode)
	if won:
		_bump(cfg, "modewins_" + mode)
	if position >= 1 and position <= 5:
		_bump(cfg, "pos_%d" % position)
	if player_count > 0:
		cfg.set_value("progress", "last_player_count", player_count)
	cfg.save(PATH)


static func _bump(cfg: ConfigFile, key: String) -> void:
	cfg.set_value("progress", key, cfg.get_value("progress", key, 0) + 1)


static func counter(key: String) -> int:
	return _load().get_value("progress", key, 0)


## Local "played with" log — groundwork for the friends leaderboard (which
## needs the deployed server for cross-device score comparison).
static func bump_friend(p_name: String) -> void:
	var cfg := _load()
	cfg.set_value("friends", p_name, cfg.get_value("friends", p_name, 0) + 1)
	cfg.save(PATH)


static func friends() -> Dictionary:
	var cfg := _load()
	var out := {}
	if cfg.has_section("friends"):
		for key in cfg.get_section_keys("friends"):
			out[key] = cfg.get_value("friends", key, 0)
	return out


static func grant(cosmetic_id: String) -> void:
	var cfg := _load()
	var extras: Array = cfg.get_value("progress", "extra_unlocks", [])
	if not extras.has(cosmetic_id):
		extras.append(cosmetic_id)
		cfg.set_value("progress", "extra_unlocks", extras)
		cfg.save(PATH)
