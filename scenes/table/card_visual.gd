class_name CardVisual
extends Control
## One on-screen card at any size. Front/back textures, a soft shadow that
## reacts to the card's "height" above the table, tap handling and the
## pseudo-3D flip (scale.x 1 -> 0 -> 1 with a texture swap at the midpoint).

signal tapped(card: CardVisual)

const BACK_TEXTURE := "res://assets/cards/back.png"

var card_id := "" # "" = face down (back shown)
var base_width := 120.0
var selected := false:
	set(v):
		selected = v
		_update_selection()

var _shadow: Panel
var _face: TextureRect
var _lift := 0.0


func _init(id: String = "", width: float = 120.0) -> void:
	card_id = id
	base_width = width
	custom_minimum_size = Vector2(width, width * 1.5)
	size = custom_minimum_size
	pivot_offset = size / 2.0
	var k := width / 120.0 # scale shadow geometry with card size

	_shadow = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = int(8 * k)
	sb.shadow_offset = Vector2(0, 6 * k)
	sb.set_corner_radius_all(int(8 * k))
	_shadow.add_theme_stylebox_override("panel", sb)
	_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	_face = TextureRect.new()
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_SCALE
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)
	_refresh_texture()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)
		accept_event()


func set_card(id: String) -> void:
	card_id = id
	_refresh_texture()


func _refresh_texture() -> void:
	var path := FaraonCard.texture_path(card_id) if card_id != "" else BACK_TEXTURE
	_face.texture = load(path)


func _update_selection() -> void:
	# The hand layout owns the position; selection just lifts the art.
	set_lift(16.0 if selected else 0.0)


## Raises the art above the table: bigger, softer, offset shadow sells the
## height. Used by selection and by drag/flight animations.
func set_lift(px: float) -> void:
	_lift = px
	_face.position.y = -px
	var k := base_width / 120.0
	var sb: StyleBoxFlat = _shadow.get_theme_stylebox("panel")
	sb.shadow_size = int(8 * k + px * 0.7)
	sb.shadow_offset = Vector2(0, 6 * k + px * 0.55)
	sb.shadow_color = Color(0, 0, 0, clampf(0.4 - px * 0.009, 0.14, 0.4))


## Pseudo-3D flip: squeeze on X, swap the texture at the midpoint.
func flip_to(id: String, duration := 0.35) -> void:
	var half := duration / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, half) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(set_card.bind(id))
	tw.tween_property(self, "scale:x", 1.0, half) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Landing squash-and-stretch after a throw/deal.
func land_squash() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.07, 0.93), 0.06)
	tw.tween_property(self, "scale", Vector2(0.97, 1.03), 0.07)
	tw.tween_property(self, "scale", Vector2.ONE, 0.08)
