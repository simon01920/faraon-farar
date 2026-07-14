class_name DiscardStack
extends Control
## The face-up pile: keeps the last few cards visible with a deterministic
## per-card skew so the pile reads as physically thrown, not a single sprite.
## As the game progresses the pile gains visual depth — ghost edge layers
## stack up beneath the cards, the shadow under the pile strengthens and the
## whole top drifts slightly upward, as if the heap underneath were growing.
## Depth changes are tweened, so the growth reads as gradual, not stepped.

const CARD_W := 120.0
const VISIBLE := 4
const MAX_GHOSTS := 6
## One ghost edge layer per this many discarded cards.
const CARDS_PER_GHOST := 5.0
const GHOST_STEP := 1.6
## How far the visible cards ride up per ghost layer (the "growing heap").
const RISE_PER_GHOST := 1.4

var _cards: Array[CardVisual] = []
var _ghosts: Array[Panel] = []
## Everything sits in the holder; depth animates the holder, not each card.
var _holder: Control
var _shown_ghosts := 0
## Tracked tweens (per-ghost fades + holder rise) killed before restarting —
## rapid depth changes otherwise stack conflicting tweens on one property
## and stale hide-callbacks can leave a ghost invisible while "shown".
var _ghost_tweens := {}
var _rise_tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W + 20, CARD_W * 1.5 + 20)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	for i in MAX_GHOSTS:
		var g := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("f2ead8").darkened(0.06 + i * 0.02)
		sb.set_corner_radius_all(8)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 4 + i # deepest pile edge carries the biggest shadow
		sb.shadow_offset = Vector2(0, 4)
		g.add_theme_stylebox_override("panel", sb)
		g.size = Vector2(CARD_W, CARD_W * 1.5)
		g.position = Vector2(10 + (i + 1) * GHOST_STEP, 10 + (i + 1) * GHOST_STEP)
		g.rotation = float(i % 5 - 2) * 0.012
		g.visible = false
		g.modulate.a = 0.0
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_holder.add_child(g)
		_ghosts.append(g)


static func rot_for(card_id: String) -> float:
	return float(hash(card_id) % 17 - 8) * 0.022


## Scales the visual depth to the true pile size. Ghost layers appear one by
## one (capped, so long games never clutter) and the card layer drifts up.
func set_depth(total_cards: int) -> void:
	if not is_node_ready():
		return
	var target := clampi(int(floor(total_cards / CARDS_PER_GHOST)), 0, MAX_GHOSTS)
	if target == _shown_ghosts:
		return
	for i in _ghosts.size():
		var g := _ghosts[i]
		var should := i < target
		if g.visible == should:
			continue
		if _ghost_tweens.has(i) and is_instance_valid(_ghost_tweens[i]):
			_ghost_tweens[i].kill()
		var tw := create_tween()
		_ghost_tweens[i] = tw
		if should:
			g.visible = true
			tw.tween_property(g, "modulate:a", 1.0, 0.3)
		else:
			tw.tween_property(g, "modulate:a", 0.0, 0.3)
			tw.tween_callback(func(): g.visible = false)
	_shown_ghosts = target
	if _rise_tween != null and _rise_tween.is_valid():
		_rise_tween.kill()
	_rise_tween = create_tween()
	_rise_tween.tween_property(_holder, "position:y", -target * RISE_PER_GHOST, 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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
	_holder.add_child(cv)
	_cards.append(cv)
	return cv


## Where flying cards should land (global coordinates, tracks the rise).
func landing_anchor() -> Vector2:
	var rise := _holder.position.y if _holder != null else 0.0
	return global_position + Vector2(10, 10 + rise)
