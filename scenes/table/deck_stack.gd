class_name DeckStack
extends Control
## The draw pile rendered as an actual stack: offset card-back layers whose
## count tracks the remaining cards, so the pile visibly thins out as it is
## drawn down and reads almost flat for the last few cards (intuitive "cards
## are running out" feedback). Layers fade in/out through short tweens so the
## depth change feels gradual, never a pop. Tap to draw.

signal tapped

const CARD_W := 110.0
const MAX_LAYERS := 8
const LAYER_STEP := 1.8 # px of visible edge per layer
## One layer per this many remaining cards (32 -> 8 layers, <=4 -> 1 layer).
const CARDS_PER_LAYER := 4.0

var _layers: Array[CardVisual] = []
var _badge: PanelContainer
var _badge_label: Label
var _shown_layers := 0


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W + 18, CARD_W * 1.5 + 20)
	size = custom_minimum_size
	for i in MAX_LAYERS:
		var cv := CardVisual.new("", CARD_W)
		# Layer 0 is the physical bottom; later (topmost) layers draw on top
		# and sit up-left, so hiding them shrinks the pile downward.
		cv.position = Vector2(14 - i * LAYER_STEP, 14 - i * LAYER_STEP)
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
	var target := clampi(int(ceil(n / CARDS_PER_LAYER)), 1 if n > 0 else 0,
			MAX_LAYERS)
	if target != _shown_layers:
		for i in _layers.size():
			var cv := _layers[i]
			var should := i < target
			if cv.visible == should and (not should or cv.modulate.a >= 1.0):
				continue
			var tw := create_tween()
			if should:
				cv.visible = true
				tw.tween_property(cv, "modulate:a", 1.0, 0.18)
			else:
				tw.tween_property(cv, "modulate:a", 0.0, 0.18)
				tw.tween_callback(func(): cv.visible = false)
		_shown_layers = target
	modulate.a = 1.0 if n > 0 else 0.45


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()
		accept_event()


## Global position of the stack's current top card (animation origin) — it
## sinks toward the table as the pile thins.
func top_anchor() -> Vector2:
	var top := maxi(_shown_layers - 1, 0)
	return global_position + Vector2(14 - top * LAYER_STEP, 14 - top * LAYER_STEP)
