class_name TutorialScreen
extends Control
## Interactive "Ako hrať" onboarding: short lessons that DEMONSTRATE every
## special mechanic with the real card visuals and tweens instead of a wall
## of rules text, plus two hands-on steps where the player must actually tap
## and play the right card and gets immediate feedback on a wrong pick (the
## same philosophy as the manual play-order UI: explain, don't auto-fix).
## Skippable at any moment, reopenable from the menu, and the seen-flag is
## persisted so it only auto-opens on the very first launch.

signal finished

const CARD_W := 110.0

var _step := 0
var _title: Label
var _body: Label
var _stage: Control
var _next_btn: Button
var _demo_tween: Tween
## Interactive state: which card id must be tapped ("" = passive step).
var _expected := ""
var _steps: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIKit.TABLE_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_title = UIKit.heading("", 30, UIKit.GOLD)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 26
	_title.offset_bottom = 70
	add_child(_title)

	_body = UIKit.heading("", 18, UIKit.CREAM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_body.offset_left = 80
	_body.offset_right = -80
	_body.offset_top = 84
	_body.offset_bottom = 190
	add_child(_body)

	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.offset_top = 200
	_stage.offset_bottom = -110
	add_child(_stage)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 14)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -96
	bottom.offset_bottom = -30
	add_child(bottom)

	var skip := UIKit.pill_button(tr("TUT_SKIP"), Color("3a3f45"), Vector2(180, 52))
	skip.pressed.connect(_finish)
	bottom.add_child(skip)
	_next_btn = UIKit.pill_button(tr("TUT_NEXT"), Color("2e7d4f"), Vector2(220, 52))
	_next_btn.pressed.connect(_advance)
	bottom.add_child(_next_btn)

	# Tutoriál učí len to, čo v zvolenom móde naozaj platí — v Prší niet
	# faraóna, spálenej, návratu červenou sedmou ani viackartových ťahov.
	var v := GameSettings.build_variant()
	_steps = [
		["TUT_1_TITLE", "TUT_1_BODY", _demo_matching, "9Z"],
		["TUT_2_TITLE", "TUT_2_BODY", _demo_eso, ""],
		["TUT_3_TITLE", "TUT_3_BODY", _demo_sedma, ""],
	]
	if v.allows_red7_return():
		_steps.append(["TUT_4_TITLE", "TUT_4_BODY", _demo_red_seven, ""])
	if v.faraon_is_wild():
		_steps.append(["TUT_5_TITLE", "TUT_5_BODY", _demo_faraon, ""])
	_steps.append(["TUT_6_TITLE", "TUT_6_BODY", _demo_hornik, ""])
	if v.allows_spalena():
		_steps.append(["TUT_7_TITLE", "TUT_7_BODY", _demo_spalena, ""])
	if v.multi_card_play:
		_steps.append(["TUT_8_TITLE", "TUT_8_BODY", _demo_order, "AZ"])
	_show_step()


func _advance() -> void:
	_step += 1
	if _step >= _steps.size():
		_finish()
		return
	_show_step()


func _finish() -> void:
	GameSettings.set_tutorial_seen()
	finished.emit()


func _show_step() -> void:
	var s: Array = _steps[_step]
	_title.text = "%d/%d  %s" % [_step + 1, _steps.size(), tr(s[0])]
	_body.text = tr(s[1])
	_expected = s[3]
	_next_btn.disabled = _expected != ""
	_next_btn.text = tr("TUT_NEXT") if _step < _steps.size() - 1 else tr("TUT_DONE")
	for c in _stage.get_children():
		c.queue_free()
	if _demo_tween != null and _demo_tween.is_valid():
		_demo_tween.kill()
	s[2].call()


# --- stage helpers ----------------------------------------------------------

func _card(id: String, at: Vector2, tappable := false) -> CardVisual:
	var cv := CardVisual.new(id, CARD_W)
	cv.position = at
	if tappable:
		cv.tapped.connect(_on_card_tapped)
	else:
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(cv)
	return cv


func _pile_pos() -> Vector2:
	return Vector2(_stage.size.x / 2.0 - CARD_W / 2.0, 30.0)


func _hand_pos(i: int, n: int) -> Vector2:
	var spacing := 140.0
	return Vector2(_stage.size.x / 2.0 - spacing * (n - 1) / 2.0 + i * spacing
			- CARD_W / 2.0, _stage.size.y - CARD_W * 1.5 - 10.0)


func _chip(text: String, at: Vector2, color := UIKit.RED) -> Control:
	var c := UIKit.chip(text, color, 18)
	_stage.add_child(c)
	c.reset_size()
	c.position = at
	return c


func _on_card_tapped(cv: CardVisual) -> void:
	if _expected == "":
		return
	if cv.card_id != _expected:
		# Wrong pick: shake + explain, never auto-correct.
		GameAudio.sfx("slap")
		var origin := cv.position
		var tw := create_tween()
		tw.tween_property(cv, "position:x", origin.x - 12.0, 0.05)
		tw.tween_property(cv, "position:x", origin.x + 12.0, 0.08)
		tw.tween_property(cv, "position:x", origin.x, 0.05)
		_body.text = tr("TUT_WRONG")
		return
	_expected = ""
	GameAudio.place_sfx()
	var tw := create_tween()
	tw.tween_property(cv, "position", _pile_pos(), 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_body.text = tr("TUT_RIGHT")
	_next_btn.disabled = false


# --- demos -------------------------------------------------------------------

## 1: basic matching — top 8Z; tap the card that matches (9Z, not KC).
func _demo_matching() -> void:
	await get_tree().process_frame
	_card("8Z", _pile_pos())
	_card("9Z", _hand_pos(0, 2), true)
	_card("KC", _hand_pos(1, 2), true)


## 2: eso stops the opponent, the player continues.
func _demo_eso() -> void:
	await get_tree().process_frame
	_card("8Z", _pile_pos())
	var eso := _card("AZ", _hand_pos(0, 1))
	var badge := _chip(tr("GAME_STOPPED_BADGE"), Vector2(_stage.size.x / 2.0 + 90, 40))
	badge.modulate.a = 0.0
	_demo_tween = create_tween().set_loops()
	_demo_tween.tween_interval(0.6)
	_demo_tween.tween_property(eso, "position", _pile_pos(), 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_demo_tween.tween_property(badge, "modulate:a", 1.0, 0.25)
	_demo_tween.tween_interval(1.2)
	_demo_tween.tween_property(badge, "modulate:a", 0.0, 0.2)
	_demo_tween.tween_callback(func(): eso.position = _hand_pos(0, 1))


## 3: sevens accumulate 3 -> 6 -> 9.
func _demo_sedma() -> void:
	await get_tree().process_frame
	_card("8Z", _pile_pos())
	var s1 := _card("7Z", _hand_pos(0, 2))
	var s2 := _card("7G", _hand_pos(1, 2))
	var badge := _chip("+3", Vector2(_stage.size.x / 2.0 + 90, 40))
	badge.modulate.a = 0.0
	var lbl: Label = badge.get_child(0)
	_demo_tween = create_tween().set_loops()
	_demo_tween.tween_interval(0.5)
	_demo_tween.tween_property(s1, "position", _pile_pos(), 0.35)
	_demo_tween.tween_callback(func():
		lbl.text = "+3"
		badge.modulate.a = 1.0)
	_demo_tween.tween_interval(0.8)
	_demo_tween.tween_property(s2, "position", _pile_pos() + Vector2(6, 4), 0.35)
	_demo_tween.tween_callback(func(): lbl.text = "+6")
	_demo_tween.tween_interval(1.2)
	_demo_tween.tween_callback(func():
		badge.modulate.a = 0.0
		s1.position = _hand_pos(0, 2)
		s2.position = _hand_pos(1, 2))


## 4: the red seven brings a finished player back (3 penalty cards).
func _demo_red_seven() -> void:
	await get_tree().process_frame
	_card("8Z", _pile_pos())
	var red := _card("7C", _hand_pos(0, 1))
	var seat := _chip("✓ " + tr("GAME_FINISHED_MARK"),
			Vector2(_stage.size.x / 2.0 + 110, 40), Color("2e7d4f"))
	var lbl: Label = seat.get_child(0)
	_demo_tween = create_tween().set_loops()
	_demo_tween.tween_interval(0.7)
	_demo_tween.tween_property(red, "position", _pile_pos(), 0.4)
	_demo_tween.tween_callback(func(): lbl.text = tr("TOAST_RETURNED") % "…  +3 🂠")
	_demo_tween.tween_interval(1.4)
	_demo_tween.tween_callback(func():
		lbl.text = "✓ " + tr("GAME_FINISHED_MARK")
		red.position = _hand_pos(0, 1))


## 5: faraón lands on anything and kills the seven chain.
func _demo_faraon() -> void:
	await get_tree().process_frame
	_card("XG", _pile_pos())
	var de := _card("DE", _hand_pos(0, 1))
	var badge := _chip("+6 → 0", Vector2(_stage.size.x / 2.0 + 90, 40))
	badge.modulate.a = 0.0
	_demo_tween = create_tween().set_loops()
	_demo_tween.tween_interval(0.7)
	_demo_tween.tween_property(de, "position", _pile_pos(), 0.4)
	_demo_tween.tween_property(badge, "modulate:a", 1.0, 0.25)
	_demo_tween.tween_interval(1.2)
	_demo_tween.tween_property(badge, "modulate:a", 0.0, 0.2)
	_demo_tween.tween_callback(func(): de.position = _hand_pos(0, 1))


## 6: horník changes the declared suit.
func _demo_hornik() -> void:
	await get_tree().process_frame
	_card("8G", _pile_pos())
	var h := _card("HZ", _hand_pos(0, 1))
	var chipn := _chip(tr("SUIT_CERVEN"), Vector2(_stage.size.x / 2.0 + 90, 40),
			UIKit.SUIT_COLORS[1])
	chipn.modulate.a = 0.0
	_demo_tween = create_tween().set_loops()
	_demo_tween.tween_interval(0.7)
	_demo_tween.tween_property(h, "position", _pile_pos(), 0.4)
	_demo_tween.tween_property(chipn, "modulate:a", 1.0, 0.25)
	_demo_tween.tween_interval(1.2)
	_demo_tween.tween_property(chipn, "modulate:a", 0.0, 0.2)
	_demo_tween.tween_callback(func(): h.position = _hand_pos(0, 1))


## 7: spálená — four of a kind, extra move.
func _demo_spalena() -> void:
	await get_tree().process_frame
	_card("XC", _pile_pos())
	var kings := ["KC", "KG", "KE", "KZ"]
	var cards: Array = []
	for i in kings.size():
		cards.append(_card(kings[i], _hand_pos(i, 4)))
	_demo_tween = create_tween().set_loops()
	_demo_tween.tween_interval(0.6)
	for i in cards.size():
		_demo_tween.tween_property(cards[i], "position",
				_pile_pos() + Vector2(i * 6.0, i * 3.0), 0.22)
	_demo_tween.tween_callback(func(): GameAudio.sfx("spalena2"))
	_demo_tween.tween_interval(1.3)
	_demo_tween.tween_callback(func():
		for i in cards.size():
			cards[i].position = _hand_pos(i, 4))


## 8: interactive — play the ACE first (order badges): tap AZ, not 9C.
func _demo_order() -> void:
	await get_tree().process_frame
	_card("AG", _pile_pos())
	var a := _card("AZ", _hand_pos(0, 2), true)
	a.set_order(1)
	var nine := _card("9C", _hand_pos(1, 2), true)
	nine.set_order(0)
