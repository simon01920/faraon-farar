class_name UIKit
extends RefCounted
## Shared visual vocabulary — one place for the palette and control factories
## so menu and table read as the same product.

const TABLE_DARK := Color("0d241c")
const TABLE_MID := Color("144233")
const TABLE_GLOW := Color("1f6b4f")
const CREAM := Color("f2e4c3")
const GOLD := Color("e5b954")
const RED := Color("c2453a")
const BLUE := Color("3d6b8f")
const INK := Color("0a1512")

const SUIT_COLORS := [
	Color("b07f2e"), # žaluď
	Color("cc4a3d"), # červeň
	Color("4f9153"), # zeleň
	Color("d9a934"), # guľa
]

const AVATAR_COLORS := [
	Color("3d6b8f"), Color("a8543f"), Color("6f5a93"), Color("b58a2f"),
	Color("4f7f6a"),
]


static func pill_button(text: String, color: Color, min_size := Vector2(190, 56),
		font_size := 21) -> Button:
	var b := Button.new()
	b.pressed.connect(func(): GameAudio.sfx("ui"))
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", CREAM.darkened(0.4))

	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(min_size.y / 2.0))
	sb.set_border_width_all(2)
	sb.border_color = color.lightened(0.22)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	b.add_theme_stylebox_override("normal", sb)

	var sb_h: StyleBoxFlat = sb.duplicate()
	sb_h.bg_color = color.lightened(0.12)
	sb_h.shadow_size = 9
	b.add_theme_stylebox_override("hover", sb_h)

	var sb_p: StyleBoxFlat = sb.duplicate()
	sb_p.bg_color = color.darkened(0.12)
	sb_p.shadow_size = 2
	sb_p.shadow_offset = Vector2(0, 1)
	b.add_theme_stylebox_override("pressed", sb_p)

	var sb_d: StyleBoxFlat = sb.duplicate()
	sb_d.bg_color = color.darkened(0.5)
	sb_d.border_color = color.darkened(0.35)
	sb_d.shadow_size = 0
	b.add_theme_stylebox_override("disabled", sb_d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func panel_style(bg: Color, radius := 14, border := Color.TRANSPARENT,
		border_w := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb


static func heading(text: String, font_size: int, color := CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", int(font_size / 6.0))
	return l


static func chip(text: String, color: Color, font_size := 17) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := panel_style(color, 999)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_size = 4
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p


# --- responsive layout -------------------------------------------------------

## Probe/debug override of the device safe-area insets in screen pixels
## (left, top, right, bottom). Vector4.ZERO = ask the OS (mobile only).
static var simulated_insets := Vector4.ZERO


## The part of the viewport not covered by a notch, punch-hole camera, rounded
## corners or the home indicator — in layout units, so screens can keep
## buttons and text inside it while backgrounds still fill the whole display.
## Desktop windows have no cutouts: the full viewport.
static func safe_rect(ctrl: Control) -> Rect2:
	var vp_size := ctrl.get_viewport_rect().size
	var full := Rect2(Vector2.ZERO, vp_size)
	var win := ctrl.get_window()
	if win == null or win.size.x <= 0 or win.size.y <= 0:
		return full
	var px := simulated_insets
	if px == Vector4.ZERO:
		if not OS.has_feature("mobile"):
			return full
		var safe := DisplayServer.get_display_safe_area()
		if safe.size.x <= 0 or safe.size.y <= 0:
			return full
		px = Vector4(safe.position.x, safe.position.y,
				win.size.x - safe.end.x, win.size.y - safe.end.y)
	var k := vp_size.x / float(win.size.x) # screen px -> layout units
	var l := maxf(px.x, 0.0) * k
	var t := maxf(px.y, 0.0) * k
	var r := maxf(px.z, 0.0) * k
	var b := maxf(px.w, 0.0) * k
	return Rect2(l, t, maxf(vp_size.x - l - r, 1.0), maxf(vp_size.y - t - b, 1.0))


## Width a centered panel's content may take: its preferred width, shrunk on
## narrow (portrait phone) screens so panel + margins never leave the display.
static func fit_width(preferred: float, available: float, chrome := 68.0,
		gutter := 16.0) -> float:
	return maxf(minf(preferred, available - chrome - 2.0 * gutter), 240.0)


## In-style modal question (the stock ConfirmationDialog looks like a foreign
## desktop window and is tiny on phones). Returns the overlay so callers can
## free it early; it frees itself after either answer.
static func confirm(parent: Control, title: String, body: String,
		yes_text: String, no_text: String, on_yes: Callable,
		yes_color := RED) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 80
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	var sb := panel_style(TABLE_MID, 18, GOLD.darkened(0.2), 2)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	if title != "":
		box.add_child(heading(title, 24, GOLD))
	var text := Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.custom_minimum_size = Vector2(
			fit_width(420.0, parent.get_viewport_rect().size.x, 52.0), 0)
	text.add_theme_font_size_override("font_size", 17)
	text.add_theme_color_override("font_color", CREAM)
	box.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var no := pill_button(no_text, BLUE, Vector2(170, 52), 18)
	no.pressed.connect(layer.queue_free)
	row.add_child(no)
	var yes := pill_button(yes_text, yes_color, Vector2(170, 52), 18)
	yes.pressed.connect(func():
		layer.queue_free()
		on_yes.call())
	row.add_child(yes)
	box.add_child(row)
	parent.add_child(layer)
	return layer
