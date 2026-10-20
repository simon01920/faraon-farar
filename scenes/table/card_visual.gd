class_name CardVisual
extends Control
## One on-screen card at any size. Front/back textures, a soft shadow that
## reacts to the card's "height" above the table, tap handling and the
## pseudo-3D flip (scale.x 1 -> 0 -> 1 with a texture swap at the midpoint).

signal tapped(card: CardVisual)


var card_id := "" # "" = face down (back shown)
var base_width := 120.0
var selected := false:
	set(v):
		selected = v
		_update_selection()
## Hand-fan preview: hovering (mouse) or selecting (touch/mouse) raises the
## card above its overlapping neighbours so the whole face is readable.
## Enabled only for cards sitting in the local hand.
var hover_preview := false

var _shadow: Panel
var _glow: Panel
var _face: TextureRect
var _order_badge: Label
var _lift := 0.0
var _hovered := false


func _init(id: String = "", width: float = 120.0) -> void:
	card_id = id
	base_width = width
	custom_minimum_size = Vector2(width, width * 1.5)
	size = custom_minimum_size
	pivot_offset = size / 2.0
	# Hover starts from real mouse motion in _gui_input (a finger's emulated
	# mouse must not leave the card raised after a tap); leaving ends it.
	mouse_exited.connect(_set_hover.bind(false))
	var k := width / 120.0 # scale shadow geometry with card size

	# Zlatá žiara „karta je vybraná na položenie" — samostatná vrstva POD
	# kartou, odlíšená od hover stavu (ten kartu len zväčší/zdvihne).
	_glow = Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0, 0, 0, 0)
	gsb.set_corner_radius_all(int(10 * k))
	gsb.shadow_color = Color(1.0, 0.84, 0.42, 0.85) # teplá zlatá (UIKit.GOLD)
	gsb.shadow_size = int(15 * k)
	gsb.shadow_offset = Vector2.ZERO
	_glow.add_theme_stylebox_override("panel", gsb)
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.visible = false
	add_child(_glow)

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

	# Play-order badge (child of the face so it rides the selection lift).
	_order_badge = Label.new()
	_order_badge.visible = false
	_order_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_order_badge.add_theme_font_size_override("font_size", int(20 * k))
	_order_badge.add_theme_color_override("font_color", Color("1c2b1f"))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("e0b64d")
	bsb.set_corner_radius_all(int(14 * k))
	bsb.border_color = Color("1c2b1f")
	bsb.set_border_width_all(int(2 * k))
	_order_badge.add_theme_stylebox_override("normal", bsb)
	_order_badge.custom_minimum_size = Vector2(28 * k, 28 * k)
	# Top-left: in the fanned hand cards overlap from the right, so only the
	# left edge of every card is guaranteed visible.
	_order_badge.position = Vector2(6 * k, 6 * k)
	_order_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_child(_order_badge)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not _hovered and event.device != InputEvent.DEVICE_ID_EMULATION:
			_set_hover(true)
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)
		accept_event()


func set_card(id: String) -> void:
	if id == card_id and _face.texture != null:
		return
	card_id = id
	_refresh_texture()


## Card faces stay resident for the session: a new game (or a flip) would
## otherwise decode the same textures again the moment the previous table
## released them — a visible hitch right at the deal on phones.
static var _textures := {}


func _refresh_texture() -> void:
	var path := CardSkin.active().texture_path(card_id)
	var tex: Texture2D = _textures.get(path)
	if tex == null:
		tex = load(path)
		_textures[path] = tex
	_face.texture = tex


func _set_hover(on: bool) -> void:
	if not hover_preview:
		return
	_hovered = on
	_update_selection()


## Žiara výberu nezávislá od `selected` settera — ruka ju viaže na výber,
## súperov vejár (ruby) ju zapína priamo cez set_glow.
func set_glow(on: bool) -> void:
	_glow.visible = on


func _update_selection() -> void:
	# The hand layout owns the position; selection/hover lift the art and
	# pop the card above its neighbours (z-order) so it reads in full.
	var lift := 0.0
	if selected:
		lift += 34.0
	if _hovered:
		lift += 26.0
	set_lift(lift)
	set_glow(selected) # glow = „vybraná na položenie", hover žiaru nemá
	if hover_preview:
		z_index = 2 if _hovered else (1 if selected else 0)
		scale = Vector2(1.12, 1.12) if _hovered else Vector2.ONE


## Shows the 1-based play-order number on the card; n <= 0 hides the badge.
func set_order(n: int) -> void:
	_order_badge.visible = n > 0
	if n > 0:
		_order_badge.text = str(n)


## Raises the art above the table: bigger, softer, offset shadow sells the
## height. Used by selection and by drag/flight animations.
func set_lift(px: float) -> void:
	_lift = px
	_face.position.y = -px
	_glow.position.y = -px # žiara obopína kartu, tak letí s ňou
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
