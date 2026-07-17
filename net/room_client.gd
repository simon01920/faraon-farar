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

## Compatibility with the table's LocalGameServer expectations.
var rules := FaraonRules.new()
var fast_forward := false
var match_state = null # Olympic modes are single-device only for now

var my_seat := ""
var my_token := ""
var room_code := ""
var _names := {}


## Runtime autoload lookup (compiles under -s tool runs too).
func _hub() -> Node:
	return get_node("/root/NetHub")


func _ready() -> void:
	_hub().game_events.connect(_on_game_events)
	_hub().game_started.connect(_on_game_started)
	_hub().move_rejected.connect(func(reason):
		action_rejected.emit(my_seat, reason))
	_hub().joined.connect(func(code, seat, token):
		room_code = code
		my_seat = seat
		my_token = token)


# --- the LocalGameServer-compatible surface --------------------------------

func propose(_player_id: String, action: Dictionary) -> Dictionary:
	_hub().rpc_id(1, "sv_propose", action)
	return {"ok": true, "error": "", "events": []} # server answers async


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
