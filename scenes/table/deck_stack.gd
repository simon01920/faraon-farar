class_name DeckStack
extends Control
## The draw pile rendered as an actual stack: several offset card backs whose
## count scales with the remaining cards, plus a count badge. Tap to draw.

signal tapped

const CARD_W := 110.0

var _layers: Array[CardVisual] = []
var _badge: PanelContainer
var _badge_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W + 14, CARD_W * 1.5 + 16)
	size = custom_minimum_size
	for i in 5:
		var cv := CardVisual.new("", CARD_W)
		cv.position = Vector2(10 - i * 2.0, 10 - i * 2.0)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cv)
		_layers.append(cv)
	_badge = UIKit.chip("32", UIKit.INK, 16)
	_badge.position = Vector2(size.x / 2.0 - 18, size.y - 14)
	add_child(_badge)
	_badge_label = _badge.get_child(0)


func set_count(n: int) -> void:
	if not is_node_ready():
		return
	_badge_label.text = str(n)
	var visible_layers := clampi(int(ceil(n / 7.0)), 1 if n > 0 else 0, 5)
	for i in _layers.size():
		_layers[i].visible = i < visible_layers
	modulate.a = 1.0 if n > 0 else 0.45


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()
		accept_event()


## Global position of the stack's top card (animation origin).
func top_anchor() -> Vector2:
	return global_position + Vector2(10, 10)
