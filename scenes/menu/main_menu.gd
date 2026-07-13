class_name MainMenu
extends Control
## Main menu + house-rules screen, built in code. Local play works today;
## multiplayer entries are visible but disabled until the networking
## milestone. Rule toggles persist via GameSettings and will become the room
## creator's authoritative ruleset in multiplayer.

signal local_game_requested(bot_count: int)

var _menu_box: VBoxContainer
var _rules_panel: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UIKit.TABLE_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(UIKit.TABLE_GLOW, 0.6), Color(UIKit.TABLE_DARK, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.4)
	gt.fill_to = Vector2(0.5, 1.1)
	gt.width = 640
	gt.height = 640
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)

	var back_art := TextureRect.new()
	back_art.texture = load("res://assets/cards/back.png")
	back_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back_art.modulate = Color(1, 1, 1, 0.10)
	back_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back_art)

	_build_menu()
	_build_rules_panel()


func _build_menu() -> void:
	_menu_box = VBoxContainer.new()
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 14)
	_menu_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu_box.custom_minimum_size = Vector2(380, 0)
	_menu_box.position -= Vector2(190, 240)
	add_child(_menu_box)

	var title := UIKit.heading(tr("APP_NAME"), 72, UIKit.GOLD)
	_menu_box.add_child(title)
	var subtitle := UIKit.heading(tr("MENU_SUBTITLE"), 18, UIKit.CREAM.darkened(0.1))
	_menu_box.add_child(subtitle)
	_menu_box.add_child(_spacer(20))

	var play_label := UIKit.heading(tr("MENU_OPPONENTS"), 19)
	_menu_box.add_child(play_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for n in [1, 2, 3]:
		var b := UIKit.pill_button("%d" % n, Color("2e7d4f"), Vector2(100, 64), 28)
		b.pressed.connect(func(): local_game_requested.emit(n))
		row.add_child(b)
	_menu_box.add_child(row)
	_menu_box.add_child(_spacer(8))

	var rules := UIKit.pill_button(tr("MENU_RULES"), UIKit.GOLD.darkened(0.25), Vector2(340, 52))
	rules.pressed.connect(func():
		_rules_panel.visible = true
		_menu_box.visible = false)
	_menu_box.add_child(rules)

	var mp := UIKit.pill_button(tr("MENU_MULTIPLAYER") + " " + tr("MENU_SOON"),
			UIKit.BLUE, Vector2(340, 52))
	mp.disabled = true
	_menu_box.add_child(mp)

	var lang := UIKit.pill_button(tr("SETTINGS_LANGUAGE") + ": " +
			("SK" if TranslationServer.get_locale().begins_with("sk") else "EN"),
			Color("6b5a3e"), Vector2(340, 52))
	lang.pressed.connect(func():
		var next := "en" if TranslationServer.get_locale().begins_with("sk") else "sk"
		GameSettings.set_locale(next)
		TranslationServer.set_locale(next)
		get_tree().reload_current_scene())
	_menu_box.add_child(lang)


func _build_rules_panel() -> void:
	_rules_panel = Control.new()
	_rules_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rules_panel.visible = false
	add_child(_rules_panel)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rules_panel.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(620, 0)
	panel.add_child(box)

	box.add_child(UIKit.heading(tr("MENU_RULES"), 30, UIKit.GOLD))
	var hint := UIKit.heading(tr("MENU_RULES_HINT"), 15, UIKit.CREAM.darkened(0.15))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	box.add_child(_spacer(6))

	for key in GameSettings.RULE_TOGGLES:
		box.add_child(_toggle_row(key, GameSettings.RULE_TOGGLES[key]))

	box.add_child(_spacer(10))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func():
		_rules_panel.visible = false
		_menu_box.visible = true)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(back)
	box.add_child(center)


func _toggle_row(key: String, label_key: String) -> Control:
	var row := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.22), 12)
	sb.shadow_size = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = tr(label_key)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIKit.CREAM)
	texts.add_child(title)
	var desc := Label.new()
	desc.text = tr(label_key + "_DESC")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UIKit.CREAM.darkened(0.3))
	texts.add_child(desc)
	h.add_child(texts)

	var toggle := CheckButton.new()
	toggle.button_pressed = GameSettings.get_rule(key)
	toggle.toggled.connect(func(on: bool): GameSettings.set_rule(key, on))
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(toggle)
	return row


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
