class_name Challenges
extends RefCounted
## Daily challenges + play streak. Pure local, offline-friendly: the active
## trio of challenges is picked DETERMINISTICALLY from the pool by the local
## calendar date (no server clock needed), progress lives in the progression
## save and resets when the stored date differs from today — i.e. at local
## midnight.
##
## Streak rule (shown to the player verbatim in the UI): play at least one
## game every calendar day. Playing on consecutive days grows the streak by
## one per day; skipping a whole day resets it to 1 on the next game.
## Completing a challenge awards CHALLENGE_POINTS progression points.
## The escalating STREAK bonus is proposed but NOT yet awarded — the numbers
## await Simon's approval (see architecture/engagement_numbers_proposal.md).

const CHALLENGE_POINTS := 40
const ACTIVE_PER_DAY := 3

## The pool: id -> [name_key, target]. Progress hooks live in
## observe_event()/on_game_finished() below and only read data the game
## already produces.
const POOL := {
	"play_3": ["CH_PLAY_3", 3],
	"win_hard": ["CH_WIN_HARD", 1],
	"spalena": ["CH_SPALENA", 1],
	"win_3plus": ["CH_WIN_3PLUS", 1],
	"play_esa": ["CH_PLAY_ESA", 2],
	"return_red7": ["CH_RETURN_RED7", 1],
	"win_olympic": ["CH_WIN_OLYMPIC", 1],
	"finish_top2": ["CH_FINISH_TOP2", 2],
}


static func _today() -> int:
	var d := Time.get_date_dict_from_system()
	return d.year * 10000 + d.month * 100 + d.day


static func _cfg() -> ConfigFile:
	return ConfigCache.get_file(ProgressionStore.PATH)


## Today's active challenge ids — deterministic shuffle seeded by the date.
static func active_ids() -> Array:
	var ids := POOL.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = _today()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	return ids.slice(0, ACTIVE_PER_DAY)


## {id, name_key, target, progress, done} for the UI.
static func today() -> Array:
	var cfg := _reset_if_new_day()
	var out: Array = []
	for id in active_ids():
		out.append({
			"id": id,
			"name_key": POOL[id][0],
			"target": POOL[id][1],
			"progress": cfg.get_value("daily", "prog_" + id, 0),
			"done": cfg.get_value("daily", "done_" + id, false),
		})
	return out


static func streak() -> int:
	return _cfg().get_value("daily", "streak", 0)


static func longest_streak() -> int:
	return _cfg().get_value("daily", "longest_streak", 0)


## True when the player has already kept the streak alive today.
static func played_today() -> bool:
	return _cfg().get_value("daily", "last_play_day", 0) == _today()


## Called once per finished round (from Progression.record_round).
static func on_game_finished(player_count: int, position: int,
		context: String, mode: String) -> int:
	var cfg := _reset_if_new_day()
	_update_streak(cfg)
	var earned := 0
	earned += _step(cfg, "play_3", 1)
	if position == 1 and context == "hard":
		earned += _step(cfg, "win_hard", 1)
	if position == 1 and player_count >= 3:
		earned += _step(cfg, "win_3plus", 1)
	if position == 1 and (mode == "olympic" or mode == "reverse"):
		earned += _step(cfg, "win_olympic", 1)
	if position >= 1 and position <= 2:
		earned += _step(cfg, "finish_top2", 1)
	cfg.save(ProgressionStore.PATH)
	if earned > 0:
		ProgressionStore.add_points(earned) # len body: record() by zarátal ďalšiu hru
	return earned


## Mid-game observations (called with each event the local player sees).
## Only the three tracked moments touch the save, and only an actual
## progress step writes it — not every card the player puts down.
static func observe_event(e: Dictionary, me: String) -> void:
	var kind: String = e.get("type", "")
	var id := ""
	var amount := 1
	if kind == "SPALENA_EXTRA_TURN" and e.get("player", "") == me:
		id = "spalena"
	elif kind == "PLAYER_RETURNED" and e.get("by", "") == me:
		id = "return_red7"
	elif kind == "CARDS_PLAYED" and e.get("player", "") == me:
		amount = 0
		for c in e.get("cards", []):
			if c is String and FaraonCard.is_valid_id(c) and FaraonCard.is_eso(c):
				amount += 1
		if amount > 0:
			id = "play_esa"
	if id == "":
		return
	var cfg := _reset_if_new_day()
	if not active_ids().has(id) or cfg.get_value("daily", "done_" + id, false):
		return
	var earned := _step(cfg, id, amount)
	cfg.save(ProgressionStore.PATH)
	if earned > 0:
		ProgressionStore.add_points(earned) # len body: record() by zarátal ďalšiu hru


static func _step(cfg: ConfigFile, id: String, amount: int) -> int:
	if not active_ids().has(id) or cfg.get_value("daily", "done_" + id, false):
		return 0
	var target: int = POOL[id][1]
	var prog: int = cfg.get_value("daily", "prog_" + id, 0) + amount
	cfg.set_value("daily", "prog_" + id, mini(prog, target))
	if prog >= target:
		cfg.set_value("daily", "done_" + id, true)
		return CHALLENGE_POINTS
	return 0


static func _update_streak(cfg: ConfigFile) -> void:
	var today := _today()
	var last: int = cfg.get_value("daily", "last_play_day", 0)
	if last == today:
		return
	var streak_now: int = cfg.get_value("daily", "streak", 0)
	streak_now = streak_now + 1 if _is_yesterday(last, today) else 1
	cfg.set_value("daily", "streak", streak_now)
	cfg.set_value("daily", "last_play_day", today)
	cfg.set_value("daily", "longest_streak",
			maxi(streak_now, cfg.get_value("daily", "longest_streak", 0)))


static func _is_yesterday(last: int, today: int) -> bool:
	if last == 0:
		return false
	var t := Time.get_unix_time_from_datetime_dict({
		"year": today / 10000, "month": (today / 100) % 100, "day": today % 100,
		"hour": 12, "minute": 0, "second": 0})
	var y := Time.get_datetime_dict_from_unix_time(int(t) - 86400)
	return last == y.year * 10000 + y.month * 100 + y.day


static func _reset_if_new_day() -> ConfigFile:
	var cfg := _cfg()
	if cfg.get_value("daily", "date", 0) != _today():
		cfg.set_value("daily", "date", _today())
		for id in POOL:
			cfg.set_value("daily", "prog_" + id, 0)
			cfg.set_value("daily", "done_" + id, false)
		cfg.save(ProgressionStore.PATH)
	return cfg
