class_name LocalGameServer
extends Node
## In-process authoritative "server" for offline play. Owns the rules engine
## exactly like the future remote server will — the UI is a pure client that
## proposes actions and re-renders on state_updated. Swapping this node for a
## networked room client must not require touching the table scene.

signal state_updated(events: Array)
signal action_rejected(player_id: String, error: String)
## Živý stôl: hráč/bot si práve označil `count` kariet (0 = výber zrušený).
signal selection_updated(player_id: String, count: int)

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
	# B1: prvého štartéra určuje RNG so zvýhodnením hráča podľa obtiažnosti
	# (Ľahká 100 % hráč, Stredná 55 %, Ťažká rovnaké šance pre všetkých).
	var start_index := _first_starter_index(ids.size(), bot_difficulty)
	_variant.end_on_first_finish = mode != FaraonMatch.Mode.NORMAL
	match_state = null if mode == FaraonMatch.Mode.NORMAL \
			else FaraonMatch.new(mode, ids, ids[start_index])
	_start_round(ids, {}, seed_value, start_index)


func _first_starter_index(player_count: int, difficulty: int) -> int:
	match difficulty:
		BotStrategy.Difficulty.EASY:
			return 0 # ľudský hráč začína vždy
		BotStrategy.Difficulty.MEDIUM:
			if randf() < 0.55:
				return 0
			return randi_range(1, player_count - 1) # inak náhodný bot
		_:
			return randi_range(0, player_count - 1) # plne náhodné


## Rozdá ďalšie sub-kolo bežiaceho zápasu (rozstrel alebo nové kolo) s
## prídelmi a rotovaným štartérom z meta-vrstvy.
func next_round() -> void:
	if match_state == null or match_state.finished:
		return
	_start_round(match_state.sub_round_players(), match_state.hand_sizes(), 0,
			match_state.sub_start_index())


func _start_round(ids: Array, hand_sizes: Dictionary, seed_value: int = 0,
		start_index: int = 0) -> void:
	if seed_value == 0:
		seed_value = randi()
	fast_forward = false
	_round_settled = false
	var events := rules.start(ids, _variant, seed_value, hand_sizes, start_index)
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


## Lokálna hra nemá kam vysielať výber človeka (boti sa nepozerajú) —
## metóda existuje pre jednotné rozhranie s RoomClientom.
func update_selection(_count: int) -> void:
	pass


func propose(player_id: String, action: Dictionary) -> Dictionary:
	var res := rules.apply(player_id, action)
	if res.ok:
		# A finished round settles the match exactly once, before clients
		# render the game-over screen from the same event batch.
		if rules.state.phase == GameState.Phase.GAME_OVER \
				and match_state != null and not _round_settled:
			_round_settled = true
			var info := match_state.on_sub_round_over(rules.state)
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
	# „Živý stôl": pred položením bot krátko ukáže, koľko kariet si
	# pripravuje (nadvihnuté ruby so žiarou) — rovnaká spätná väzba, akú
	# dostávajú súperi v multiplayeri.
	if action.get("action", "") == FaraonActions.PLAY_CARDS:
		var n: int = action.get("cards", []).size()
		selection_updated.emit(bot_id, n)
		await get_tree().create_timer(0.12 if fast_forward else 0.55).timeout
		selection_updated.emit(bot_id, 0)
		# Svet sa mohol počas pauzy zmeniť (reštart, nové kolo, výmena ťahu).
		if rules.state == null or rules.state.phase != GameState.Phase.PLAYING \
				or rules.state.players[rules.state.current_index].id != bot_id:
			return
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
