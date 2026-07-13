class_name Progression
extends RefCounted
## Points + level meta-game (architecture/progression_proposal.md — numbers
## approved by Simon). Pure retention mechanic: nothing here may ever feed
## back into faraon_rules.gd, probabilities or any gameplay advantage.
##
## points = BASE[player_count][finish_position] × context multiplier
## level cost: n -> n+1 costs 400 + 100 × n cumulative points, no cap.

## BASE[player_count] indexed by finish_position - 1; last place = 0.
const BASE := {
	2: [100, 0],
	3: [130, 45, 0],
	4: [160, 70, 30, 0],
	5: [190, 95, 50, 20, 0],
}

## Mutually exclusive game contexts: bot difficulty, or multiplayer later.
const MULTIPLIER := {
	"easy": 0.5,
	"medium": 1.0,
	"hard": 1.5,
	"multiplayer": 2.0,
}


static func points_for(player_count: int, finish_position: int,
		context: String) -> int:
	if finish_position < 1 or not BASE.has(player_count):
		return 0
	var base: Array = BASE[player_count]
	if finish_position > base.size():
		return 0
	return int(round(base[finish_position - 1] * MULTIPLIER.get(context, 1.0)))


static func cost_of_level(n: int) -> int:
	return 400 + 100 * n # level n -> n+1


## Level for a cumulative points total (level 1 at 0 points).
static func level_for(total: int) -> int:
	var level := 1
	var remaining := total
	while remaining >= cost_of_level(level):
		remaining -= cost_of_level(level)
		level += 1
	return level


## {level, into, needed}: points already inside the current level and the
## full cost of the next one — drives the menu progress bar.
static func progress_for(total: int) -> Dictionary:
	var level := 1
	var remaining := total
	while remaining >= cost_of_level(level):
		remaining -= cost_of_level(level)
		level += 1
	return {"level": level, "into": remaining, "needed": cost_of_level(level)}


static func level() -> int:
	return level_for(ProgressionStore.total_points())


## Awards one finished round for the local player and persists it.
## Returns {points, won, level_before, level_after, unlocks: Array} —
## `unlocks` holds the Rewards entries newly reached by a level-up.
static func record_round(player_count: int, finish_position: int,
		context: String) -> Dictionary:
	var before_total := ProgressionStore.total_points()
	var pts := points_for(player_count, finish_position, context)
	var won := finish_position == 1
	ProgressionStore.record(pts, won)
	var level_before := level_for(before_total)
	var level_after := level_for(before_total + pts)
	var unlocks: Array = []
	if level_after > level_before:
		for r in Rewards.all():
			if r.level > level_before and r.level <= level_after:
				unlocks.append(r)
	return {"points": pts, "won": won, "level_before": level_before,
			"level_after": level_after, "unlocks": unlocks}


## True when the cosmetic is available: free, reached by level, or granted
## directly (future purchase path through ProgressionStore.grant()).
static func is_unlocked(cosmetic_id: String) -> bool:
	var required := Rewards.level_required(cosmetic_id)
	if required <= 1:
		return true
	if level() >= required:
		return true
	return ProgressionStore.extra_unlocks().has(cosmetic_id)
