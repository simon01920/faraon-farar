class_name PlayerSeat
extends Control
## One player's presence at the table: avatar circle, name plate, a fan of
## card backs showing roughly how many cards they hold, and a count badge —
## the physical-table read the UNO reference nails. Also the anchor point
## every card animation flies from/to.

const FAN_W := 42.0
const MAX_FAN := 8

var player_id: String
var display_name: String
var seat_color: Color
var is_human := false

var _avatar: PanelContainer
var _avatar_style: StyleBoxFlat
var _name_label: Label
var _fan: Control
var _badge: PanelContainer
var _badge_label: Label
var _finished := false
var _pulse: Tween
var _active := false
var _shown_count := 0
## The fan's card backs, built once and re-posed by set_count — the table
## refreshes every seat after each move and per dealt card, and rebuilding
## eight card nodes per seat each time was pure churn.
var _fan_cards: Array[CardVisual] = []
## Koľko rubov z vejára je „nadvihnutých" — súper si práve pripravuje toľko
## kariet na položenie (hodnoty ostávajú skryté, ide len o počet).
var _selected_shown := 0


func _init(id: String, p_name: String, color: Color, human := false) -> void:
	player_id = id
	display_name = p_name
	seat_color = color
	is_human = human
	custom_minimum_size = Vector2(180, 150)
	size = custom_minimum_size


func _ready() -> void:
	_fan = Control.new()
	_fan.position = Vector2(90, 40)
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fan)
	if not is_human:
		for i in MAX_FAN:
			var cv := CardVisual.new("", FAN_W)
			cv.pivot_offset = Vector2(FAN_W / 2.0, FAN_W * 1.5)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.visible = false
			_fan.add_child(cv)
			_fan_cards.append(cv)

	_avatar = PanelContainer.new()
	_avatar_style = UIKit.panel_style(seat_color, 27, Color.TRANSPARENT, 0)
	_avatar_style.shadow_size = 6
	_avatar.add_theme_stylebox_override("panel", _avatar_style)
	_avatar.custom_minimum_size = Vector2(54, 54)
	_avatar.position = Vector2(63, 58)
	var initial := Label.new()
	initial.text = display_name.substr(0, 1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 26)
	initial.add_theme_color_override("font_color", Color.WHITE)
	_avatar.add_child(initial)
	_avatar.pivot_offset = Vector2(27, 27)
	add_child(_avatar)

	_name_label = UIKit.heading(display_name, 17)
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name_label.offset_top = -32
	add_child(_name_label)

	_badge = UIKit.chip("0", UIKit.INK, 15)
	_badge.position = Vector2(104, 92)
	add_child(_badge)
	_badge_label = _badge.get_child(0)

	set_count(_shown_count)


## Re-poses the mini fan of card backs and updates the count badge.
func set_count(n: int) -> void:
	_shown_count = max(n, 0)
	if not is_node_ready():
		return
	_badge_label.text = str(_shown_count)
	_badge.visible = not _finished
	var shown := 0 if is_human or _finished else mini(_shown_count, MAX_FAN)
	var raised := mini(_selected_shown, shown)
	for i in _fan_cards.size():
		var cv := _fan_cards[i]
		cv.visible = i < shown
		if i >= shown:
			continue
		var off := i - (shown - 1) / 2.0
		cv.rotation = off * 0.16
		cv.position = Vector2(off * 14.0 - FAN_W / 2.0,
				-40.0 + absf(off) * 2.5)
		# Vybraný rub sa vysunie z vejára von (po vlastnej osi karty,
		# t. j. smerom k stredu stola z pohľadu diváka) + zlatá žiara.
		# Hodnota karty ostáva skrytá — hýbe sa len rub.
		var lifted := i >= shown - raised
		if lifted:
			cv.position += Vector2(0, -12).rotated(cv.rotation)
		cv.set_glow(lifted)
		cv.z_index = 1 if lifted else 0


## Živý stôl: súper si práve označil `n` kariet na položenie — príslušný
## počet rubov sa nadvihne z vejára so žiarou. 0 = výber zmizol.
func set_selected_count(n: int) -> void:
	if _selected_shown == maxi(n, 0):
		return
	_selected_shown = maxi(n, 0)
	set_count(_shown_count)


## Narrow name plate for tight spots (the local player's seat beside the
## action row in portrait): it shrinks to the avatar's column and long names
## end in an ellipsis instead of running off the screen edge.
func set_compact(on: bool) -> void:
	if not is_node_ready():
		await ready
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if on \
			else TextServer.OVERRUN_NO_TRIMMING
	_name_label.offset_left = 45.0 if on else 0.0
	_name_label.offset_right = -45.0 if on else 0.0


func set_finished(finished: bool, place: int = 0) -> void:
	_finished = finished
	if finished:
		_name_label.text = "%s ✓ %d." % [display_name, place] if place > 0 \
				else display_name + " ✓"
		set_count(0)
	else:
		_name_label.text = display_name
	_avatar_style.bg_color = seat_color.darkened(0.35) if finished else seat_color


func set_active(active: bool) -> void:
	# The table re-applies this to every seat after each move; restarting an
	# unchanged pulse made the active avatar visibly snap back to scale 1.
	if active == _active:
		return
	_active = active
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	_avatar.scale = Vector2.ONE
	if active:
		_avatar_style.set_border_width_all(3)
		_avatar_style.border_color = UIKit.GOLD
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_avatar, "scale", Vector2(1.08, 1.08), 0.55) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse.tween_property(_avatar, "scale", Vector2.ONE, 0.55) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_avatar_style.set_border_width_all(0)


## Short floating badge over the seat ("STOJÍ", "+9", ...).
func flash(text: String, color := UIKit.RED) -> void:
	var b := UIKit.chip(text, color, 18)
	b.position = Vector2(40, 8)
	b.modulate.a = 0.0
	add_child(b)
	var tw := create_tween()
	tw.tween_property(b, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(b, "position:y", -6.0, 0.9) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(b, "modulate:a", 0.0, 0.25)
	tw.tween_callback(b.queue_free)


## Where flying cards originate/land for this seat (global coordinates).
func card_anchor() -> Vector2:
	return _fan.global_position if not is_human else global_position + size / 2.0
