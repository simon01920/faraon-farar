class_name DiscardStack
extends Control
## The face-up pile: keeps the last few cards visible with a deterministic
## per-card skew so the pile reads as physically thrown, not a single sprite.

const CARD_W := 120.0
const VISIBLE := 4

var _cards: Array[CardVisual] = []


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W + 20, CARD_W * 1.5 + 20)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func rot_for(card_id: String) -> float:
	return float(hash(card_id) % 17 - 8) * 0.022


## Replaces the whole pile from the state's tail (oldest first).
func rebuild(tail: Array) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for id in tail:
		_add_visual(id)


## Adds one just-played card with a landing squash.
func push_card(card_id: String) -> void:
	var cv := _add_visual(card_id)
	cv.land_squash()
	while _cards.size() > VISIBLE:
		_cards.pop_front().queue_free()


func _add_visual(card_id: String) -> CardVisual:
	var cv := CardVisual.new(card_id, CARD_W)
	cv.position = Vector2(10, 10)
	cv.rotation = rot_for(card_id)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cv)
	_cards.append(cv)
	return cv


## Where flying cards should land (global coordinates).
func landing_anchor() -> Vector2:
	return global_position + Vector2(10, 10)
