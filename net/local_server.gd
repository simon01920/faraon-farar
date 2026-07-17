class_name LocalGameServer
extends Node
## In-process authoritative "server" for offline play. Owns the rules engine
## exactly like the future remote server will — the UI is a pure client that
## proposes actions and re-renders on state_updated. Swapping this node for a
## networked room client must not require touching the table scene.

signal state_updated(events: Array)
signal action_rejected(player_id: String, error: String)

const HUMAN_ID := "YOU"

var rules := FaraonRules.new()
## Thinking pause before a bot moves; the table's card animations add to the
## perceived pace on top of this.
var bot_delay := 1.2
## One-shot fast-forward for a finished human: bots keep playing visibly but
## their thinking pauses (and the table's animations) are cut short. Reset by
## start_game and whenever the human returns to the game.
var fast_forward := false
## Olympic-mode match layer; null for a normal single-round game.
var match_state: FaraonMatch = null
var _bot := BotStrategy.new()
var _bot_ids: Array[String] = []
var _variant: RulesVariant
var _round_settled := false


func start_game(bot_count: int, variant: RulesVariant = null,
		seed_value: int = 0, bot_difficulty: int = BotStrategy.Difficulty.MEDIUM,
		mode: int = FaraonMatch.Mode.NORMAL) -> void:
	if variant == null:
		variant = RulesVariant.classic()
	_variant = variant
	_bot = BotStrategy.new(bot_difficulty)
	var ids: Array = [HUMAN_ID]
	_bot_ids.clear()
	for i in bot_count:
		var bid := "BOT%d" % (i + 1)
		ids.append(bid)
		_bot_ids.append(bid)
	match_state = null if mode == FaraonMatch.Mode.NORMAL \
			else FaraonMatch.new(mode, ids)
	_start_round(ids, {}, seed_value)


## Deals the next round of a running Olympic match with the shrunken hands.
func next_round() -> void:
	if match_state == null or match_state.finished:
		return
	_start_round(match_state.participants(), match_state.hand_sizes())


func _start_round(ids: Array, hand_sizes: Dictionary, seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = randi()
	fast_forward = false
	_round_settled = false
	var events := rules.start(ids, _variant, seed_value, hand_sizes)
	state_updated.emit(events)
	_schedule_bot()


# --- interface shared with RoomClient (the table is a pure client of it) ---

func local_player_id() -> String:
	return HUMAN_ID


func display_name(id: String) -> String:
	if id == HUMAN_ID:
		var custom := GameSettings.get_player_name()
		return custom if custom != "" else tr("PLAYER_YOU")
	if id.begins_with("BOT"):
		return tr("BOT_NAME") % id.trim_prefix("BOT")
	return id


func supports_fast_forward() -> bool:
	return true


func supports_restart() -> bool:
	return true


func progression_context() -> String:
	return GameSettings.get_bot_difficulty()


func game_mode() -> String:
	if match_state == null:
		return "normal"
	return "olympic" if match_state.mode == FaraonMatch.Mode.OLYMPIC else "reverse"


func propose(player_id: String, action: Dictionary) -> Dictionary:
	var res := rules.apply(player_id, action)
	if res.ok:
		# A finished round settles the match exactly once, before clients
		# render the game-over screen from the same event batch.
		if rules.state.phase == GameState.Phase.GAME_OVER \
				and match_state != null and not _round_settled:
			_round_settled = true
			var info := match_state.apply_round_result(rules.state)
			res.events.append({"type": "MATCH_UPDATE", "info": info})
		state_updated.emit(res.events)
		_schedule_bot()
	else:
		action_rejected.emit(player_id, res.error)
	return res


func _schedule_bot() -> void:
	if rules.state == null or rules.state.phase != GameState.Phase.PLAYING:
		return
	var cur := rules.state.players[rules.state.current_index]
	if cur.id in _bot_ids:
		var delay := 0.1 if fast_forward else bot_delay
		get_tree().create_timer(delay).timeout.connect(
				_bot_move.bind(cur.id), CONNECT_ONE_SHOT)


func _bot_move(bot_id: String) -> void:
	if rules.state == null or rules.state.phase != GameState.Phase.PLAYING:
		return
	# The turn may have shifted while the timer ran (e.g. new game started).
	if rules.state.players[rules.state.current_index].id != bot_id:
		return
	var action := _bot.choose(rules.state, bot_id)
	var res := propose(bot_id, action)
	if not res.ok:
		# A stuck bot must never freeze the table; drawing is always legal
		# outside an eso chain, passing inside one.
		push_warning("bot %s illegal action %s (%s), falling back" %
				[bot_id, action, res.error])
		if rules.state.pending_aces > 0:
			propose(bot_id, FaraonActions.pass_turn())
		else:
			propose(bot_id, FaraonActions.draw())
