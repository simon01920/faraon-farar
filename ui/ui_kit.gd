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
