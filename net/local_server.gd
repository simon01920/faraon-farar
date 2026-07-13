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
var _bot := BotPlayer.new()
var _bot_ids: Array[String] = []


func start_game(bot_count: int, variant: RulesVariant = null,
		seed_value: int = 0) -> void:
	if variant == null:
		variant = RulesVariant.classic()
	if seed_value == 0:
		seed_value = randi()
	fast_forward = false
	var ids: Array = [HUMAN_ID]
	_bot_ids.clear()
	for i in bot_count:
		var bid := "BOT%d" % (i + 1)
		ids.append(bid)
		_bot_ids.append(bid)
	var events := rules.start(ids, variant, seed_value)
	state_updated.emit(events)
	_schedule_bot()


func propose(player_id: String, action: Dictionary) -> Dictionary:
	var res := rules.apply(player_id, action)
	if res.ok:
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
