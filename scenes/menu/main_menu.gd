class_name MainMenu
extends Control
## Main menu + settings screen, built in code. Local play works today;
## multiplayer entries are visible but disabled until the networking
## milestone. The settings screen holds the app preferences (language) and
## the house-rule toggles that persist via GameSettings and will become the
## room creator's authoritative ruleset in multiplayer.

signal local_game_requested(bot_count: int)
signal tutorial_requested
## Premium sa zmenil (nákup/obnovenie) — app root skryje/ukáže banner.
signal remove_ads_changed

## Injected by the app root; shared with the table when an online game runs.
var room_client: RoomClient

## Full-rect CenterContainers so both screens re-center themselves on any
## window size/aspect — never PRESET_CENTER on a container whose minimum
## size grows after the preset is applied (that leaves content offset
## toward the bottom-right and possibly off-screen/unclickable).
var _menu_screen: ScrollContainer
var _settings_screen: ScrollContainer
var _rules_box: VBoxContainer
var _remove_ads_box: VBoxContainer
## Purchase facade (mock backend by default) — created lazily, exercises the
## whole premium flow without a real store.
var _iap: Iap
var _dev_taps := 0
var _appearance_screen: ScrollContainer
var _mp_screen: ScrollContainer
var _mp_status: Label
var _mp_join_box: VBoxContainer
var _mp_lobby_box: VBoxContainer
var _mp_code_value: Label
var _mp_members: VBoxContainer
var _mp_start: Button
var _mp_code_input: LineEdit
var _challenges_screen: ScrollContainer
var _stats_screen: ScrollContainer
## Room code waiting for the connection to open (invite deep link).
var _pending_join := ""


func _swap_screen(target: Control) -> void:
	for s in [_menu_screen, _settings_screen, _appearance_screen, _mp_screen,
			_challenges_screen, _stats_screen]:
		if s != null:
			s.visible = s == target


## Runtime autoload lookup (compiles under -s tool runs too).
func _hub() -> Node:
	return get_node("/root/NetHub")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UIKit.TABLE_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var back_art := TextureRect.new()
	back_art.texture = load(CardSkin.active().back_path())
	back_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back_art.modulate = Color(1, 1, 1, 0.10)
	back_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back_art)

	_build_menu()
	_build_settings_screen()
	_build_appearance_screen()
	_build_mp_screen()
	_build_challenges_screen()
	_build_stats_screen()


func _build_menu() -> void:
	_menu_screen = ScrollContainer.new()
	_menu_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_screen.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(380, 0)
	center.add_child(box)

	var title := UIKit.heading(tr("APP_NAME"), 60, UIKit.GOLD)
	box.add_child(title)
	# C1: alternatívne ľudové názvy hry pod hlavným nadpisom.
	var alt := UIKit.heading(tr("MENU_ALT_NAMES"), 20, UIKit.GOLD.darkened(0.25))
	box.add_child(alt)
	var subtitle := UIKit.heading(tr("MENU_SUBTITLE"), 16, UIKit.CREAM.darkened(0.2))
	box.add_child(subtitle)
	box.add_child(_spacer(10))
	box.add_child(_profile_row())
	box.add_child(_spacer(10))

	box.add_child(_mode_row())

	var play_label := UIKit.heading(tr("MENU_OPPONENTS"), 19)
	box.add_child(play_label)
	box.add_child(_opponents_row())
	box.add_child(_difficulty_row())
	box.add_child(_spacer(6))

	# Explicit start button — picking a player count must never launch the
	# game by itself (too easy to fat-finger).
	var start := UIKit.pill_button(tr("MENU_START"), Color("2e7d4f"), Vector2(340, 60), 24)
	start.pressed.connect(func(): local_game_requested.emit(GameSettings.get_opponents()))
	box.add_child(start)
	box.add_child(_spacer(8))

	var mp := UIKit.pill_button(tr("MENU_MULTIPLAYER"), UIKit.BLUE, Vector2(340, 52))
	mp.pressed.connect(_open_mp_screen)
	box.add_child(mp)

	# Compact engagement row: daily challenges (with the streak flame),
	# statistics and the tutorial.
	var engage := HBoxContainer.new()
	engage.alignment = BoxContainer.ALIGNMENT_CENTER
	engage.add_theme_constant_override("separation", 8)
	var ch := UIKit.pill_button("🔥%d %s" % [Challenges.streak(), tr("MENU_CHALLENGES")],
			Color("7a4b2a"), Vector2(150, 44), 14)
	ch.pressed.connect(func(): _swap_screen(_challenges_screen))
	engage.add_child(ch)
	var st := UIKit.pill_button(tr("MENU_STATS"), Color("3f5b6e"), Vector2(120, 44), 14)
	st.pressed.connect(func(): _swap_screen(_stats_screen))
	engage.add_child(st)
	var tut := UIKit.pill_button(tr("MENU_HOW_TO"), Color("55617a"), Vector2(110, 44), 14)
	tut.pressed.connect(func(): tutorial_requested.emit())
	engage.add_child(tut)
	box.add_child(engage)

	var appearance := UIKit.pill_button(tr("MENU_APPEARANCE"),
			Color("55617a"), Vector2(340, 52))
	appearance.pressed.connect(func():
		_appearance_screen.visible = true
		_menu_screen.visible = false)
	box.add_child(appearance)

	# Settings sits last in the menu by design.
	var settings := UIKit.pill_button(tr("MENU_SETTINGS"),
			UIKit.GOLD.darkened(0.25), Vector2(340, 52))
	settings.pressed.connect(func():
		_settings_screen.visible = true
		_menu_screen.visible = false)
	box.add_child(settings)
	# Malá spodná rezerva (o banner sa stará offset_bottom v app roote).
	box.add_child(_spacer(12))


func _build_settings_screen() -> void:
	# Scroll wrapper so a panel taller than the window scrolls instead of
	# getting clipped (Späť must stay reachable on short screens).
	_settings_screen = ScrollContainer.new()
	_settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_screen.visible = false
	add_child(_settings_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_screen.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(620, 0)
	panel.add_child(box)

	var settings_title := UIKit.heading(tr("MENU_SETTINGS"), 30, UIKit.GOLD)
	# Dev režim: 7 ťukov na nadpis (klasický Android vzor).
	settings_title.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_title.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_dev_taps += 1
			if _dev_taps >= 7:
				_dev_taps = 0
				GameSettings.set_dev_mode(not GameSettings.dev_mode())
				settings_title.text = tr("MENU_SETTINGS") \
						+ ("  [DEV]" if GameSettings.dev_mode() else ""))
	if GameSettings.dev_mode():
		settings_title.text = tr("MENU_SETTINGS") + "  [DEV]"
	box.add_child(settings_title)

	box.add_child(_language_row())
	box.add_child(_spacer(6))

	_remove_ads_box = VBoxContainer.new()
	_remove_ads_box.add_theme_constant_override("separation", 10)
	box.add_child(_remove_ads_box)
	_rebuild_remove_ads()
	box.add_child(_spacer(6))

	box.add_child(UIKit.heading(tr("SETTINGS_AUDIO"), 21, UIKit.CREAM))
	box.add_child(_audio_row("SETTINGS_SOUND",
			GameSettings.get_sound_on, GameSettings.set_sound_on,
			GameSettings.get_sfx_volume, GameSettings.set_sfx_volume))
	box.add_child(_audio_row("SETTINGS_MUSIC",
			GameSettings.get_music_on, GameSettings.set_music_on,
			GameSettings.get_music_volume, GameSettings.set_music_volume))
	box.add_child(_audio_row("SETTINGS_VIBRATIONS",
			GameSettings.get_vibrations_on, GameSettings.set_vibrations_on,
			Callable(), Callable()))
	box.add_child(_spacer(6))

	# Herný mód pravidiel (Faraón / Prší) — samostatná voľba, nezávislá od
	# jazyka appky. Mení predvolené hodnoty všetkých pravidiel pod ňou.
	box.add_child(UIKit.heading(tr("SETTINGS_RULE_PRESET"), 21, UIKit.CREAM))
	var preset_hint := Label.new()
	preset_hint.text = tr("SETTINGS_RULE_PRESET_HINT")
	preset_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_hint.add_theme_font_size_override("font_size", 14)
	preset_hint.add_theme_color_override("font_color", UIKit.CREAM.darkened(0.1))
	box.add_child(preset_hint)
	box.add_child(_segmented_row(
			[["faraon", "PRESET_FARAON"], ["prsi", "PRESET_PRSI"]],
			func(): return GameSettings.get_rule_preset(),
			func(p):
				GameSettings.set_rule_preset(p)
				_rebuild_rule_rows(),
			Vector2(150, 46), 17, Color("55617a")))
	box.add_child(_spacer(6))

	box.add_child(UIKit.heading(tr("MENU_RULES"), 21, UIKit.CREAM))
	# C3: vysvetlenie, prečo sú pravidlá prispôsobiteľné.
	var explain := PanelContainer.new()
	var esb := UIKit.panel_style(Color(0, 0, 0, 0.28), 12)
	esb.shadow_size = 0
	esb.content_margin_left = 14
	esb.content_margin_right = 14
	esb.content_margin_top = 10
	esb.content_margin_bottom = 10
	explain.add_theme_stylebox_override("panel", esb)
	var etext := Label.new()
	etext.text = tr("RULES_EXPLAINER")
	etext.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	etext.add_theme_font_size_override("font_size", 14)
	etext.add_theme_color_override("font_color", UIKit.CREAM.darkened(0.1))
	explain.add_child(etext)
	box.add_child(explain)

	# C2: reset na predvolené s potvrdením.
	var reset_row := HBoxContainer.new()
	reset_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var reset := UIKit.pill_button(tr("RULES_RESET"), Color("7a4a3a"),
			Vector2(320, 44), 16)
	reset.pressed.connect(_confirm_rules_reset)
	reset_row.add_child(reset)
	box.add_child(reset_row)

	_rules_box = VBoxContainer.new()
	_rules_box.add_theme_constant_override("separation", 8)
	box.add_child(_rules_box)
	_rebuild_rule_rows()

	box.add_child(_spacer(10))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func():
		_settings_screen.visible = false
		_menu_screen.visible = true)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	box.add_child(back_row)


func _confirm_rules_reset() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = tr("RULES_RESET_CONFIRM")
	dialog.ok_button_text = tr("RULES_RESET_YES")
	dialog.cancel_button_text = tr("MENU_BACK_SHORT")
	dialog.confirmed.connect(func():
		GameSettings.reset_rules()
		_rebuild_rule_rows())
	add_child(dialog)
	dialog.popup_centered()


# --- odstránenie reklám (mikrotransakcie) ----------------------------------

## Nenápadná sekcia v Nastaveniach. Premium hráčovi ukáže len poďakovanie;
## free hráčovi oba produkty vedľa seba (ceny zo store) + Obnoviť nákupy.
## Žiadne agresívne „len teraz" nutkanie — konzistentne s nerušivou filozofiou.
func _rebuild_remove_ads() -> void:
	for c in _remove_ads_box.get_children():
		c.queue_free()
	_remove_ads_box.add_child(UIKit.heading(tr("REMOVE_ADS_TITLE"), 21, UIKit.CREAM))

	if MonetizationStore.is_premium(int(Time.get_unix_time_from_system())):
		var active := Label.new()
		active.text = tr("REMOVE_ADS_ACTIVE")
		active.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		active.add_theme_font_size_override("font_size", 15)
		active.add_theme_color_override("font_color", Color("6fd08c"))
		_remove_ads_box.add_child(active)
		return

	_ensure_iap()
	var note := Label.new()
	note.text = tr("REMOVE_ADS_NOTE")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", UIKit.CREAM.darkened(0.25))
	_remove_ads_box.add_child(note)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.add_child(_product_card(Iap.PRODUCT_YEARLY, tr("REMOVE_ADS_YEARLY"),
			tr("REMOVE_ADS_PER_YEAR"), false))
	row.add_child(_product_card(Iap.PRODUCT_LIFETIME, tr("REMOVE_ADS_LIFETIME"),
			"", true))
	_remove_ads_box.add_child(row)
	# HBox natiahne obe karty na výšku najvyššej; vnútorný expander v karte
	# pritlačí tlačidlá Kúpiť na spoločnú spodnú líniu.

	var restore := UIKit.pill_button(tr("REMOVE_ADS_RESTORE"),
			Color("55617a"), Vector2(280, 44), 15)
	restore.pressed.connect(func(): _iap.restore_purchases())
	var restore_row := HBoxContainer.new()
	restore_row.alignment = BoxContainer.ALIGNMENT_CENTER
	restore_row.add_child(restore)
	_remove_ads_box.add_child(restore_row)


func _ensure_iap() -> void:
	if _iap != null:
		return
	_iap = Iap.new()
	_iap.purchased.connect(func(_id):
		remove_ads_changed.emit()
		_rebuild_remove_ads())
	_iap.restored.connect(func(count):
		remove_ads_changed.emit()
		_rebuild_remove_ads())
	# Ceny prídu zo store asynchrónne — prekresli až po ich doručení
	# (call_deferred zabráni re-entrancii pri synchronnom mocku).
	_iap.products_updated.connect(func(_p): call_deferred("_rebuild_remove_ads"))
	_iap.query_products()


## Jedna produktová karta: názov, cena zo store (nie hardcoded), tlačidlo kúpiť.
## `highlight` = zvýrazni ako výhodnejšiu voľbu (lifetime), bez manipulácie.
## Obe karty majú rovnakú šírku a tlačidlo pritlačené na spodok, takže dvojica
## v riadku sedí na jednej línii bez ohľadu na počet riadkov obsahu.
func _product_card(product_id: String, title: String, price_suffix: String,
		highlight: bool) -> Control:
	var card := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.28), 14)
	sb.shadow_size = 0
	if highlight:
		sb.border_color = UIKit.GOLD.darkened(0.1)
		sb.set_border_width_all(2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(230, 158)
	card.add_child(v)

	var name_label := Label.new()
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color",
			UIKit.GOLD if highlight else UIKit.CREAM)
	v.add_child(name_label)

	# Cena zo store (lokálna mena); fallback na formát, kým sa nenačíta.
	var store_price := _iap.price_of(product_id)
	var price := Label.new()
	price.text = (store_price if store_price != "" else "…") + price_suffix
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 20)
	price.add_theme_color_override("font_color", UIKit.CREAM)
	v.add_child(price)

	# Badge „Najvýhodnejšie" má vyhradený riadok v OBOCH kartách — karta bez
	# neho dostane prázdny riadok rovnakej výšky, takže obsah sa nerozíde.
	var best := Label.new()
	best.text = tr("REMOVE_ADS_BEST_VALUE") if highlight else " "
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best.add_theme_font_size_override("font_size", 12)
	best.add_theme_color_override("font_color", UIKit.GOLD.darkened(0.1))
	v.add_child(best)

	# Expander zhltne prebytočnú výšku — tlačidlá oboch kariet končia na
	# spoločnej spodnej línii.
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(filler)

	var buy := UIKit.pill_button(tr("REMOVE_ADS_BUY"),
			Color("2e7d4f"), Vector2(194, 46), 15)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy.disabled = store_price == "" # počkaj na cenu zo store
	buy.pressed.connect(func(): _iap.purchase(product_id))
	v.add_child(buy)
	return card


## Či je pravidlo v UI zablokované konfliktom (E: Purista, Hospodské prší,
## vnorené D12b).
func _rule_disabled(key: String) -> bool:
	if key == "green_king_counter" and not GameSettings.get_rule("green_king"):
		return true
	if GameSettings.get_rule("purista") \
			and GameSettings.DISABLED_BY_PURISTA.has(key):
		return true
	if GameSettings.get_rule("pub_mode") \
			and GameSettings.DISABLED_BY_PUB.has(key):
		return true
	if not GameSettings.get_rule("multi_card_play") \
			and GameSettings.DISABLED_BY_SINGLE_CARD.has(key):
		return true
	if not GameSettings.get_rule("faraon_wild") \
			and GameSettings.DISABLED_BY_NO_FARAON.has(key):
		return true
	return false


## Postaví/rebuildne všetky riadky pravidiel (toggle/slider/segment) s C2
## označením predvolenej hodnoty a zablokovaním konfliktov.
func _rebuild_rule_rows() -> void:
	for c in _rules_box.get_children():
		c.queue_free()
	for key in GameSettings.RULE_TOGGLES:
		_rules_box.add_child(_rule_toggle_row(key, GameSettings.RULE_TOGGLES[key]))
	for key in GameSettings.RULE_VALUES:
		var spec: Array = GameSettings.RULE_VALUES[key]
		if spec[1] == "slider":
			_rules_box.add_child(_rule_slider_row(key, spec[0], spec[2]))
		else:
			_rules_box.add_child(_rule_segment_row(key, spec[0], spec[2]))


func _rule_row_base(key: String, label_key: String, non_default: bool) -> Array:
	var row := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.22), 12)
	sb.shadow_size = 0
	if non_default:
		sb.border_color = UIKit.GOLD.darkened(0.15)
		sb.set_border_width_all(2) # C2: odlíšenie upravenej hodnoty
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", sb)
	if _rule_disabled(key):
		row.modulate = Color(1, 1, 1, 0.45)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	row.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
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
	return [row, v, h, texts]


func _default_badge(text: String) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", UIKit.GOLD.darkened(0.1))
	return badge


func _rule_toggle_row(key: String, label_key: String) -> Control:
	var def: bool = GameSettings.rule_default(key)
	var cur := GameSettings.get_rule(key)
	var parts := _rule_row_base(key, label_key, cur != def)
	var row: PanelContainer = parts[0]
	var h: HBoxContainer = parts[2]
	var texts: VBoxContainer = parts[3]
	# C2: štítok predvolenej hodnoty.
	texts.add_child(_default_badge(tr("RULES_DEFAULT_IS") % \
			(tr("OPT_ON") if def else tr("OPT_OFF"))))
	var toggle := CheckButton.new()
	toggle.button_pressed = cur
	toggle.disabled = _rule_disabled(key)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.toggled.connect(func(on: bool):
		GameSettings.set_rule(key, on)
		# Purista / Hospodské prší / zelený kráľ menia dostupnosť riadkov.
		if key == "purista" or key == "green_king" or key == "pub_mode" \
				or key == "multi_card_play" or key == "faraon_wild":
			_rebuild_rule_rows())
	h.add_child(toggle)
	return row


func _rule_slider_row(key: String, label_key: String, minmax: Array) -> Control:
	var def: int = GameSettings.rule_default(key)
	var cur: int = GameSettings.get_rule_value(key)
	var parts := _rule_row_base(key, label_key, cur != def)
	var row: PanelContainer = parts[0]
	var v: VBoxContainer = parts[1]
	var texts: VBoxContainer = parts[3]
	texts.add_child(_default_badge(tr("RULES_DEFAULT_IS") % str(def)))
	var slide_h := HBoxContainer.new()
	slide_h.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = minmax[0]
	s.max_value = minmax[1]
	s.step = 1
	s.value = cur
	s.editable = not _rule_disabled(key)
	s.custom_minimum_size = Vector2(0, 34)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.text = str(cur)
	value_label.add_theme_font_size_override("font_size", 20)
	value_label.add_theme_color_override("font_color", UIKit.GOLD)
	s.value_changed.connect(func(val: float):
		GameSettings.set_rule_value(key, int(val))
		value_label.text = str(int(val)))
	slide_h.add_child(s)
	slide_h.add_child(value_label)
	v.add_child(slide_h)
	return row


func _rule_segment_row(key: String, label_key: String, options: Array) -> Control:
	var def: Variant = GameSettings.rule_default(key)
	var cur: Variant = GameSettings.get_rule_value(key)
	var parts := _rule_row_base(key, label_key, cur != def)
	var row: PanelContainer = parts[0]
	var v: VBoxContainer = parts[1]
	var seg := HBoxContainer.new()
	seg.alignment = BoxContainer.ALIGNMENT_CENTER
	seg.add_theme_constant_override("separation", 8)
	var buttons := {}
	var recolor := func():
		for opt in buttons:
			var b: Button = buttons[opt]
			b.modulate = Color(1, 1, 1,
					1.0 if GameSettings.get_rule_value(key) == opt else 0.45)
	for opt in options:
		var label := _option_label(key, opt)
		# C2: predvolená možnosť je označená bodkou priamo v štítku.
		if opt == def:
			label += " •"
		var b := UIKit.pill_button(label, Color("55617a"), Vector2(150, 40), 14)
		b.disabled = _rule_disabled(key)
		b.pressed.connect(func():
			GameSettings.set_rule_value(key, opt)
			recolor.call())
		buttons[opt] = b
		seg.add_child(b)
	recolor.call()
	v.add_child(seg)
	return row


func _option_label(key: String, opt: Variant) -> String:
	if opt is int:
		if key == "seven_penalty_cap" and int(opt) == 0:
			return tr("OPT_NO_CAP")
		return str(opt)
	match str(opt):
		"anyone": return tr("OPT_ANYONE")
		"round": return tr("OPT_ROUND")
		"none": return tr("OPT_NONE")
		"no_seven": return tr("OPT_NO_SEVEN")
		"hornik_only": return tr("OPT_HORNIK_ONLY")
	return str(opt)


## Multiplayer lobby: connect, create/join a room by code, see who is
## seated, invite a friend, and (as host) start the game.
func _build_mp_screen() -> void:
	_mp_screen = ScrollContainer.new()
	_mp_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mp_screen.visible = false
	add_child(_mp_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mp_screen.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(520, 0)
	panel.add_child(box)

	box.add_child(UIKit.heading(tr("MENU_MULTIPLAYER"), 30, UIKit.GOLD))
	_mp_status = UIKit.heading("", 16, UIKit.CREAM.darkened(0.15))
	_mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_mp_status)

	# --- not in a room yet: create / join by code
	_mp_join_box = VBoxContainer.new()
	_mp_join_box.add_theme_constant_override("separation", 10)
	box.add_child(_mp_join_box)

	var create := UIKit.pill_button(tr("MP_CREATE"), Color("2e7d4f"), Vector2(340, 52))
	create.pressed.connect(func():
		_mp_status.text = tr("MP_CONNECTING")
		_hub().rpc_id(1, "sv_create_room", _player_display_name()))
	var create_row := HBoxContainer.new()
	create_row.alignment = BoxContainer.ALIGNMENT_CENTER
	create_row.add_child(create)
	_mp_join_box.add_child(create_row)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 10)
	_mp_code_input = LineEdit.new()
	_mp_code_input.placeholder_text = tr("MP_CODE_HINT")
	_mp_code_input.max_length = NetProtocol.ROOM_CODE_LEN
	_mp_code_input.custom_minimum_size = Vector2(180, 48)
	join_row.add_child(_mp_code_input)
	var join := UIKit.pill_button(tr("MP_JOIN"), UIKit.BLUE, Vector2(170, 48), 18)
	join.pressed.connect(func():
		_mp_status.text = tr("MP_CONNECTING")
		_hub().rpc_id(1, "sv_join_room",
				_mp_code_input.text.strip_edges().to_upper(),
				_player_display_name(), ""))
	join_row.add_child(join)
	_mp_join_box.add_child(join_row)

	# --- seated in a room: code, members, invite, start (host)
	_mp_lobby_box = VBoxContainer.new()
	_mp_lobby_box.add_theme_constant_override("separation", 10)
	_mp_lobby_box.visible = false
	box.add_child(_mp_lobby_box)

	_mp_code_value = UIKit.heading("", 44, UIKit.GOLD)
	_mp_lobby_box.add_child(_mp_code_value)
	_mp_members = VBoxContainer.new()
	_mp_members.add_theme_constant_override("separation", 4)
	_mp_lobby_box.add_child(_mp_members)

	var invite := UIKit.pill_button(tr("MP_INVITE"), Color("55617a"), Vector2(340, 48), 18)
	invite.pressed.connect(func():
		DisplayServer.clipboard_set(tr("MP_INVITE_TEXT")
				% [room_client.room_code, room_client.room_code])
		_mp_status.text = tr("MP_INVITE_COPIED"))
	var invite_row := HBoxContainer.new()
	invite_row.alignment = BoxContainer.ALIGNMENT_CENTER
	invite_row.add_child(invite)
	_mp_lobby_box.add_child(invite_row)

	_mp_start = UIKit.pill_button(tr("MENU_START"), Color("2e7d4f"), Vector2(340, 56), 22)
	_mp_start.visible = false
	_mp_start.pressed.connect(func():
		_hub().rpc_id(1, "sv_start_game", GameSettings.build_variant().to_dict()))
	var start_row := HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	start_row.add_child(_mp_start)
	_mp_lobby_box.add_child(start_row)

	var leave := UIKit.pill_button(tr("MP_LEAVE"), UIKit.RED, Vector2(240, 44), 16)
	leave.pressed.connect(func():
		_hub().rpc_id(1, "sv_leave")
		_mp_lobby_box.visible = false
		_mp_join_box.visible = true
		_mp_status.text = "")
	var leave_row := HBoxContainer.new()
	leave_row.alignment = BoxContainer.ALIGNMENT_CENTER
	leave_row.add_child(leave)
	_mp_lobby_box.add_child(leave_row)

	box.add_child(_spacer(6))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func():
		_mp_screen.visible = false
		_menu_screen.visible = true)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	box.add_child(back_row)

	_hub().connected_to_server.connect(func():
		_mp_status.text = tr("MP_WAITING_INPUT")
		_do_pending_join())
	_hub().connection_failed_or_lost.connect(func():
		_mp_status.text = tr("MP_CONN_FAILED"))
	_hub().joined.connect(func(code, _seat, _token):
		_mp_join_box.visible = false
		_mp_lobby_box.visible = true
		_mp_code_value.text = code
		_mp_status.text = tr("MP_WAITING"))
	_hub().join_failed.connect(func(reason):
		_mp_status.text = tr("MP_ERR_" + reason.to_upper()) \
				if tr("MP_ERR_" + reason.to_upper()) != "MP_ERR_" + reason.to_upper() \
				else tr("MP_CONN_FAILED"))
	_hub().room_updated.connect(_on_mp_room_update)


## Deep-link entry: open the lobby and join `code` as soon as we connect.
func auto_join(code: String) -> void:
	if not NetProtocol.valid_code(code):
		return
	_pending_join = code
	_open_mp_screen()
	if _hub().is_connected_client:
		_do_pending_join()


func _do_pending_join() -> void:
	if _pending_join == "":
		return
	_mp_status.text = tr("MP_CONNECTING")
	_hub().rpc_id(1, "sv_join_room", _pending_join, _player_display_name(), "")
	_pending_join = ""


func _open_mp_screen() -> void:
	_menu_screen.visible = false
	_mp_screen.visible = true
	if not _hub().is_connected_client:
		_mp_status.text = tr("MP_CONNECTING")
		_hub().connect_to_server(GameSettings.get_server_url())
	if room_client != null and room_client.room_code != "":
		_mp_join_box.visible = false
		_mp_lobby_box.visible = true
		_mp_code_value.text = room_client.room_code


func _on_mp_room_update(info: Dictionary) -> void:
	for c in _mp_members.get_children():
		c.queue_free()
	var members: Array = info.get("members", [])
	for m in members:
		var line := "%s%s" % [m.get("name", "?"),
				"" if m.get("connected", true) else "  (offline)"]
		_mp_members.add_child(UIKit.heading(line, 18, UIKit.CREAM))
	# The first seat is the host — only they see the start button.
	_mp_start.visible = room_client != null and not members.is_empty() \
			and members[0].get("seat", "") == room_client.my_seat \
			and not info.get("playing", false)


func _player_display_name() -> String:
	var custom := GameSettings.get_player_name()
	return custom if custom != "" else tr("PLAYER_YOU")


## Shared scaffold for the simple list screens (challenges / stats).
func _list_screen(title_key: String) -> Array:
	var screen := ScrollContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.visible = false
	add_child(screen)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(center)
	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(540, 0)
	panel.add_child(box)
	box.add_child(UIKit.heading(tr(title_key), 30, UIKit.GOLD))
	return [screen, box]


func _screen_back_button(box: VBoxContainer) -> void:
	box.add_child(_spacer(8))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func(): _swap_screen(_menu_screen))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(back)
	box.add_child(row)


## Progress bar row used by both list screens.
func _bar_row(label: String, value: float, maximum: float, suffix := "") -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", UIKit.CREAM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lbl)
	var val := Label.new()
	val.text = suffix
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", UIKit.GOLD)
	top.add_child(val)
	v.add_child(top)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxf(maximum, 1.0)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	v.add_child(bar)
	return v


## Daily challenges + streak screen.
func _build_challenges_screen() -> void:
	var parts := _list_screen("MENU_CHALLENGES")
	_challenges_screen = parts[0]
	var box: VBoxContainer = parts[1]

	var streak := Challenges.streak()
	box.add_child(UIKit.heading("🔥 %s" % (tr("STREAK_DAYS") % streak), 22,
			Color("e8934a")))
	var hint := UIKit.heading(
			tr("STREAK_KEEP") if not Challenges.played_today()
			else tr("STREAK_SAFE"), 15, UIKit.CREAM.darkened(0.15))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	box.add_child(_spacer(4))

	for ch in Challenges.today():
		var done: bool = ch.done
		var label := "%s %s" % ["✅" if done else "▫️", tr(ch.name_key)]
		box.add_child(_bar_row(label, ch.progress, ch.target,
				"%d/%d" % [ch.progress, ch.target]))
	box.add_child(_spacer(2))
	var reward_note := UIKit.heading(tr("CHALLENGE_REWARD_NOTE")
			% Challenges.CHALLENGE_POINTS, 13, UIKit.CREAM.darkened(0.3))
	reward_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reward_note)
	_screen_back_button(box)


## Personal statistics screen — pure display over the stored counters.
func _build_stats_screen() -> void:
	var parts := _list_screen("MENU_STATS")
	_stats_screen = parts[0]
	var box: VBoxContainer = parts[1]

	var games := ProgressionStore.games_played()
	var wins := ProgressionStore.wins()
	var prog := Progression.progress_for(ProgressionStore.total_points())
	box.add_child(UIKit.heading("%s  ·  %s" % [tr("PROFILE_LEVEL") % prog.level,
			tr("STATS_POINTS") % ProgressionStore.total_points()], 18, UIKit.CREAM))
	box.add_child(_bar_row(tr("STATS_WINRATE"), wins, maxf(games, 1),
			"%d/%d (%d %%)" % [wins, games, int(100.0 * wins / maxf(games, 1))]))

	box.add_child(UIKit.heading(tr("STATS_BY_DIFFICULTY"), 17, UIKit.CREAM.darkened(0.1)))
	for ctx in ["easy", "medium", "hard", "multiplayer"]:
		var g := ProgressionStore.counter("games_" + ctx)
		if g == 0:
			continue
		var w := ProgressionStore.counter("wins_" + ctx)
		box.add_child(_bar_row(tr("DIFF_" + ctx.to_upper()) if ctx != "multiplayer"
				else tr("MENU_MULTIPLAYER"), w, g, "%d/%d" % [w, g]))

	box.add_child(UIKit.heading(tr("STATS_PLACES"), 17, UIKit.CREAM.darkened(0.1)))
	var medals := ["🥇", "🥈", "🥉", "4.", "5."]
	var most := 1
	for p in range(1, 6):
		most = maxi(most, ProgressionStore.counter("pos_%d" % p))
	for p in range(1, 6):
		var n := ProgressionStore.counter("pos_%d" % p)
		if n == 0 and p == 5:
			continue
		box.add_child(_bar_row(medals[p - 1], n, most, str(n)))

	# Favourite variant + longest streak, single info lines.
	var fav := "normal"
	var fav_n := -1
	for mode in ["normal", "olympic", "reverse"]:
		var n := ProgressionStore.counter("mode_" + mode)
		if n > fav_n:
			fav_n = n
			fav = mode
	var mode_keys := {"normal": "MODE_NORMAL", "olympic": "MODE_OLYMPIC",
			"reverse": "MODE_REVERSE"}
	box.add_child(UIKit.heading("%s: %s" % [tr("STATS_FAV_MODE"),
			tr(mode_keys[fav])], 16, UIKit.CREAM))
	box.add_child(UIKit.heading("%s: 🔥 %d" % [tr("STATS_LONGEST_STREAK"),
			Challenges.longest_streak()], 16, UIKit.CREAM))
	_screen_back_button(box)


## Player chip: name, level and the progress toward the next one. The ✎
## button opens a small popup to change the display name.
func _profile_row() -> Control:
	var row := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.30), 12)
	sb.shadow_size = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var name_value := GameSettings.get_player_name()
	if name_value == "":
		name_value = tr("PLAYER_YOU")
	var prog := Progression.progress_for(ProgressionStore.total_points())
	var name_label := Label.new()
	name_label.text = "%s  ·  %s" % [name_value, tr("PROFILE_LEVEL") % prog.level]
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", UIKit.CREAM)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name_label)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = prog.needed
	bar.value = prog.into
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)

	var edit := UIKit.pill_button("✎", Color("55617a"), Vector2(44, 36), 16)
	edit.pressed.connect(_open_name_popup)
	h.add_child(edit)
	return row


func _open_name_popup() -> void:
	var popup := PopupPanel.new()
	var sb := UIKit.panel_style(UIKit.TABLE_MID, 16, UIKit.GOLD, 2)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(UIKit.heading(tr("PROFILE_NAME"), 20))
	var input := LineEdit.new()
	input.text = GameSettings.get_player_name()
	input.placeholder_text = tr("PLAYER_YOU")
	input.max_length = 16
	input.custom_minimum_size = Vector2(240, 40)
	box.add_child(input)
	var save := UIKit.pill_button(tr("MENU_BACK_SHORT"), Color("2e7d4f"), Vector2(160, 44), 17)
	var commit := func():
		GameSettings.set_player_name(input.text)
		popup.hide()
		get_tree().reload_current_scene()
	save.pressed.connect(commit)
	input.text_submitted.connect(func(_t): commit.call())
	var save_row := HBoxContainer.new()
	save_row.alignment = BoxContainer.ALIGNMENT_CENTER
	save_row.add_child(save)
	box.add_child(save_row)
	popup.add_child(box)
	add_child(popup)
	popup.popup_centered()
	input.grab_focus()


## Appearance screen: pick the card skin and the table look. Locked table
## looks (level rewards) show their required level and stay disabled.
func _build_appearance_screen() -> void:
	_appearance_screen = ScrollContainer.new()
	_appearance_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_appearance_screen.visible = false
	add_child(_appearance_screen)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_appearance_screen.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(UIKit.TABLE_MID, 0.97), 20, UIKit.GOLD, 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)

	box.add_child(UIKit.heading(tr("MENU_APPEARANCE"), 30, UIKit.GOLD))

	box.add_child(UIKit.heading(tr("APPEARANCE_CARDS"), 20, UIKit.CREAM))
	var skin_row := HBoxContainer.new()
	skin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skin_row.add_theme_constant_override("separation", 10)
	box.add_child(skin_row)
	var refresh_skins := func():
		for c in skin_row.get_children():
			c.queue_free()
		for skin in CardSkin.selectable():
			var b := UIKit.pill_button(tr(skin.name_key), Color("2e7d4f"),
					Vector2(240, 46), 17)
			b.modulate.a = 1.0 if GameSettings.get_card_skin() == skin.id else 0.5
			skin_row.add_child(b)
			b.pressed.connect(func():
				GameSettings.set_card_skin(skin.id)
				for s in skin_row.get_children():
					s.modulate.a = 0.5
				b.modulate.a = 1.0)
	refresh_skins.call()

	box.add_child(UIKit.heading(tr("APPEARANCE_TABLE"), 20, UIKit.CREAM))
	var table_grid := VBoxContainer.new()
	table_grid.add_theme_constant_override("separation", 8)
	box.add_child(table_grid)
	for look in TableLook.all():
		var unlocked := look.is_unlocked()
		var label := tr(look.name_key) if unlocked \
				else "%s  —  %s" % [tr(look.name_key),
						tr("LOCKED_LEVEL") % Rewards.level_required(look.id)]
		var b := UIKit.pill_button(label, Color("386a50") if unlocked
				else Color("3a3f45"), Vector2(460, 46), 17)
		b.disabled = not unlocked
		b.modulate.a = 1.0 if GameSettings.get_table_look() == look.id else 0.55
		table_grid.add_child(b)
		if unlocked:
			b.pressed.connect(func():
				GameSettings.set_table_look(look.id)
				for row in table_grid.get_children():
					row.modulate.a = 0.55
				b.modulate.a = 1.0)

	box.add_child(_spacer(8))
	var back := UIKit.pill_button(tr("MENU_BACK_SHORT"), UIKit.BLUE, Vector2(220, 50))
	back.pressed.connect(func():
		_appearance_screen.visible = false
		_menu_screen.visible = true)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	box.add_child(back_row)


## Generic segmented picker row: [[value, label_key], ...] with a persisted
## getter/setter pair; the active segment renders at full opacity.
func _segmented_row(options: Array, get_current: Callable, set_current: Callable,
		btn_size: Vector2, font_size: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var buttons := {}
	var recolor := func():
		for key in buttons:
			var b: Button = buttons[key]
			b.modulate = Color(1, 1, 1, 1.0 if get_current.call() == key else 0.45)
	for opt in options:
		var b := UIKit.pill_button(tr(opt[1]) if opt[1] is String and tr(opt[1]) != opt[1]
				else str(opt[1]), color, btn_size, font_size)
		b.pressed.connect(func():
			set_current.call(opt[0])
			recolor.call())
		buttons[opt[0]] = b
		row.add_child(b)
	recolor.call()
	return row


## Klasický / Olympijský / Reverzný game-mode picker.
func _mode_row() -> Control:
	return _segmented_row(
			[["normal", "MODE_NORMAL"], ["olympic", "MODE_OLYMPIC"],
					["reverse", "MODE_REVERSE"]],
			func(): return GameSettings.get_game_mode(),
			func(m): GameSettings.set_game_mode(m),
			Vector2(122, 44), 15, Color("55617a"))


## 1 / 2 / 3 opponent selector — selection only, the start button launches.
func _opponents_row() -> Control:
	return _segmented_row(
			[[1, "1"], [2, "2"], [3, "3"]],
			func(): return GameSettings.get_opponents(),
			func(n): GameSettings.set_opponents(n),
			Vector2(96, 52), 24, Color("386a50"))


## Easy/Medium/Hard segmented picker; persists via GameSettings and colors
## the active segment gold. Cosmetic only for the menu — the difficulty is
## applied when the next local game starts.
func _difficulty_row() -> Control:
	return _segmented_row(
			[["easy", "DIFF_EASY"], ["medium", "DIFF_MEDIUM"], ["hard", "DIFF_HARD"]],
			func(): return GameSettings.get_bot_difficulty(),
			func(d): GameSettings.set_bot_difficulty(d),
			Vector2(104, 44), 16, UIKit.GOLD.darkened(0.35))


func _language_row() -> Control:
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

	var title := Label.new()
	title.text = tr("SETTINGS_LANGUAGE")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIKit.CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(title)

	# Rozbaľovací zoznam jazykov — jazyky sú pomenované vo vlastnom jazyku,
	# takže sa v ňom nájde aj ten, kto práve rozumie inému.
	var lang := OptionButton.new()
	lang.custom_minimum_size = Vector2(200, 46)
	lang.alignment = HORIZONTAL_ALIGNMENT_CENTER
	lang.add_theme_font_size_override("font_size", 17)
	lang.add_theme_color_override("font_color", UIKit.CREAM)
	# panel_style nemá vnútorné okraje — bez nich text lepí na ľavú hranu
	# a šípka na pravú. Vycentrovaný text + symetrické okraje.
	for style_name in ["normal", "hover", "pressed"]:
		var col := Color("6b5a3e")
		if style_name == "hover":
			col = col.lightened(0.12)
		elif style_name == "pressed":
			col = col.darkened(0.15)
		var sb_opt := UIKit.panel_style(col, 22)
		sb_opt.content_margin_left = 22
		sb_opt.content_margin_right = 34 # miesto pre rozbaľovaciu šípku
		sb_opt.content_margin_top = 8
		sb_opt.content_margin_bottom = 8
		lang.add_theme_stylebox_override(style_name, sb_opt)
	lang.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var popup := lang.get_popup()
	popup.add_theme_font_size_override("font_size", 17)
	popup.add_theme_color_override("font_color", UIKit.CREAM)
	var sb_panel := UIKit.panel_style(Color("1d3f33"), 12)
	sb_panel.content_margin_left = 10
	sb_panel.content_margin_right = 10
	sb_panel.content_margin_top = 8
	sb_panel.content_margin_bottom = 8
	popup.add_theme_stylebox_override("panel", sb_panel)
	var sb_hover := UIKit.panel_style(Color("6b5a3e"), 8)
	sb_hover.content_margin_left = 8
	sb_hover.content_margin_right = 8
	popup.add_theme_stylebox_override("hover", sb_hover)
	popup.add_theme_constant_override("v_separation", 6)
	for i in GameSettings.LOCALES.size():
		lang.add_item(GameSettings.LOCALE_NAMES[GameSettings.LOCALES[i]], i)
	lang.select(_locale_index())
	lang.item_selected.connect(func(index: int):
		var picked: String = GameSettings.LOCALES[index]
		if picked == TranslationServer.get_locale():
			return
		GameSettings.set_locale(picked)
		TranslationServer.set_locale(picked)
		get_tree().reload_current_scene())
	h.add_child(lang)
	return row


## Poradie aktuálneho jazyka v GameSettings.LOCALES (fallback: slovenčina).
func _locale_index() -> int:
	var lang := TranslationServer.get_locale().to_lower().split("_")[0]
	var i: int = GameSettings.LOCALES.find(lang)
	return i if i != -1 else 0


## One audio setting: big toggle + optional volume slider underneath.
func _audio_row(label_key: String, get_on: Callable, set_on: Callable,
		get_vol: Callable, set_vol: Callable) -> Control:
	var row := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0, 0, 0, 0.22), 12)
	sb.shadow_size = 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	row.add_child(v)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var title := Label.new()
	title.text = tr(label_key)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIKit.CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(title)
	var toggle := CheckButton.new()
	toggle.button_pressed = get_on.call()
	toggle.toggled.connect(func(on: bool): set_on.call(on))
	toggle.scale = Vector2(1.3, 1.3)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(toggle)

	if get_vol.is_valid():
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = get_vol.call()
		s.custom_minimum_size = Vector2(0, 34)
		s.value_changed.connect(func(val: float): set_vol.call(val))
		v.add_child(s)
	return row


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
