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


static func record(points: int, won: bool) -> void:
	var cfg := _load()
	cfg.set_value("progress", "schema_version", SCHEMA_VERSION)
	cfg.set_value("progress", "total_points",
			cfg.get_value("progress", "total_points", 0) + points)
	cfg.set_value("progress", "games_played",
			cfg.get_value("progress", "games_played", 0) + 1)
	if won:
		cfg.set_value("progress", "wins", cfg.get_value("progress", "wins", 0) + 1)
	cfg.save(PATH)


static func grant(cosmetic_id: String) -> void:
	var cfg := _load()
	var extras: Array = cfg.get_value("progress", "extra_unlocks", [])
	if not extras.has(cosmetic_id):
		extras.append(cosmetic_id)
		cfg.set_value("progress", "extra_unlocks", extras)
		cfg.save(PATH)
