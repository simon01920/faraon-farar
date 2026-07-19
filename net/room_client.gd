class_name RoomClient
extends Node
## Client-side adapter with the same surface GameTable already speaks to
## LocalGameServer: `rules.state`, propose(), state_updated/action_rejected
## signals, display_name(), local_player_id(). The censored server view is
## rebuilt into a GameState — hidden hands and the draw pile are padded with
## placeholder backs so counts render, while real card data never reaches
## other clients.

signal state_updated(events: Array)
signal action_rejected(player_id: String, error: String)
## Živý stôl: hráč na seate si označil `count` kariet (0 = zrušený výber).
signal selection_updated(player_id: String, count: int)

## Compatibility with the table's LocalGameServer expectations.
var rules := FaraonRules.new()
var fast_forward := false
var match_state = null # Olympic modes are single-device only for now

var my_seat := ""
var my_token := ""
var room_code := ""
var _names := {}

## Debounce odosielania výberu: posiela sa len zmena, najviac raz za okno —
## rýchle preklikávanie kariet nezahlcuje server (viac room-ov naraz).
const SELECTION_DEBOUNCE := 0.15
var _sel_timer: Timer
var _sel_pending := 0
var _sel_last_sent := 0


## Runtime autoload lookup (compiles under -s tool runs too).
func _hub() -> Node:
	return get_node("/root/NetHub")


func _ready() -> void:
	_hub().game_events.connect(_on_game_events)
	_hub().game_started.connect(_on_game_started)
	_hub().selection_changed.connect(func(seat, count):
		selection_updated.emit(str(seat), int(count)))
	_hub().move_rejected.connect(func(reason):
		action_rejected.emit(my_seat, reason))
	_hub().joined.connect(func(code, seat, token):
		room_code = code
		my_seat = seat
		my_token = token)
	_sel_timer = Timer.new()
	_sel_timer.one_shot = true
	_sel_timer.wait_time = SELECTION_DEBOUNCE
	_sel_timer.timeout.connect(func():
		if _sel_pending != _sel_last_sent:
			_send_selection())
	add_child(_sel_timer)


# --- the LocalGameServer-compatible surface --------------------------------

func propose(_player_id: String, action: Dictionary) -> Dictionary:
	_hub().rpc_id(1, "sv_propose", action)
	return {"ok": true, "error": "", "events": []} # server answers async


## Priebežný výber (počet označených kariet) — leading send + trailing
## debounce: prvá zmena ide hneď, ďalšie sa zlučujú do okna 150 ms.
func update_selection(count: int) -> void:
	_sel_pending = clampi(count, 0, 8)
	if _sel_timer == null or not _sel_timer.is_stopped():
		return
	_send_selection()
	_sel_timer.start()


func _send_selection() -> void:
	_sel_last_sent = _sel_pending
	_hub().rpc_id(1, "sv_selection", _sel_pending)


func local_player_id() -> String:
	return my_seat


func display_name(id: String) -> String:
	return str(_names.get(id, id))


func supports_fast_forward() -> bool:
	return false # never against real players


func supports_restart() -> bool:
	return false # rematch goes through the lobby


func progression_context() -> String:
	return "multiplayer"


func game_mode() -> String:
	return "normal"


# --- server messages --------------------------------------------------------

func _on_game_started(view: Dictionary) -> void:
	_apply_view(view)
	# Friends-leaderboard groundwork: remember who we sat with (locally).
	for seat in _names:
		if seat != my_seat:
			ProgressionStore.bump_friend(str(_names[seat]))


func _on_game_events(events: Array, view: Dictionary) -> void:
	_apply_view(view)
	state_updated.emit(events)


func _apply_view(view: Dictionary) -> void:
	my_seat = str(view.get("you", my_seat))
	_names = view.get("names", _names)
	var s := GameState.from_dict(view)
	# Pad hidden information with placeholder backs so counts render.
	for pd in view.get("players", []):
		if not pd.has("hand"):
			var p := s.player_by_id(str(pd.get("id", "")))
			if p != null:
				for _i in int(pd.get("hand_count", 0)):
					p.hand.append("")
	for _i in int(view.get("draw_pile_count", 0)):
		s.draw_pile.append("")
	rules.state = s
	# Reconnect/late-join: server posiela aj aktuálne výbery, aby nadvihnuté
	# ruby súperov sedeli s realitou (a nič neostalo „zaseknuté").
	var sels: Dictionary = view.get("selections", {})
	for seat in sels:
		selection_updated.emit(str(seat), int(sels[seat]))
