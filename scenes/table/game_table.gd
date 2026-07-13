class_name GameTable
extends Control
## The playing table. Pure client of a game server node (LocalGameServer now,
## networked room client later): it proposes actions and re-renders from the
## server's broadcast state. Every state change arrives as events that are
## played back sequentially through an animation queue, so the player can
## follow each move; the ground-truth refresh happens when the queue drains.

const SUIT_KEYS := ["SUIT_ZALUD", "SUIT_CERVEN", "SUIT_ZELEN", "SUIT_GULA"]

signal exit_to_menu_requested
signal new_game_requested

var server: LocalGameServer
var _selected: Array[String] = []
var _seats := {} # player_id -> PlayerSeat
var _queue: Array[Callable] = []
var _busy := false

var _status: Label
var _pending_badge: PanelContainer
var _pending_label: Label
var _declared_chip: PanelContainer
var _declared_label: Label
var _deck: DeckStack
var _discard: DiscardStack
var _hand_area: Control
var _actions: HBoxContainer
var _btn_play: Button
var _btn_draw: Button
var _btn_pass: Button
var _btn_ff: Button
var _suit_popup: PopupPanel
var _fx: Control
var _game_over_layer: Control
var _game_over_label: Label
var _ranking_box: VBoxContainer
var _pending_play: Array = []


func setup(game_server: LocalGameServer) -> void:
	server = game_server
	server.state_updated.connect(_on_state_updated)
	server.action_rejected.connect(_on_action_rejected)


func _state() -> GameState:
	return server.rules.state


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_center()
	_build_hand_and_actions()
	_build_status()
	_build_suit_popup()
	_build_fx_layer()
	_build_game_over_layer()
	if server != null and _state() != null:
		_setup_seats()
		_refresh_all()


# --- UI construction ------------------------------------------------------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = UIKit.TABLE_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Warm pool of light in the middle of the felt.
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(UIKit.TABLE_GLOW, 0.85), Color(UIKit.TABLE_MID, 0.5),
		Color(UIKit.TABLE_DARK, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.47)
	gt.fill_to = Vector2(0.5, 1.05)
	gt.width = 640
	gt.height = 640
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	# Vignette so the edges fall away like a lit table in a dark room.
	var vin := TextureRect.new()
	var vgrad := Gradient.new()
	vgrad.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	vgrad.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55),
	])
	var vt := GradientTexture2D.new()
	vt.gradient = vgrad
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(0.5, 1.15)
	vt.width = 640
	vt.height = 640
	vin.texture = vt
	vin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vin.stretch_mode = TextureRect.STRETCH_SCALE
	vin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vin)


func _build_center() -> void:
	_deck = DeckStack.new()
	_deck.tapped.connect(_do_draw)
	add_child(_deck)

	_discard = DiscardStack.new()
	add_child(_discard)

	_declared_chip = UIKit.chip("", UIKit.GOLD, 17)
	_declared_chip.visible = false
	add_child(_declared_chip)
	_declared_label = _declared_chip.get_child(0)

	_pending_badge = UIKit.chip("", UIKit.RED, 22)
	_pending_badge.visible = false
	add_child(_pending_badge)
	_pending_label = _pending_badge.get_child(0)


func _build_hand_and_actions() -> void:
	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 14)
	_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_actions.offset_top = -292
	_actions.offset_bottom = -240
	add_child(_actions)

	_btn_play = UIKit.pill_button(tr("GAME_PLAY"), Color("2e7d4f"), Vector2(170, 52))
	_btn_play.pressed.connect(_do_play)
	_actions.add_child(_btn_play)

	_btn_draw = UIKit.pill_button(tr("GAME_DRAW_CARD"), UIKit.BLUE, Vector2(150, 52))
	_btn_draw.pressed.connect(_do_draw)
	_actions.add_child(_btn_draw)

	_btn_pass = UIKit.pill_button(tr("GAME_PASS"), Color("8a6d3b"), Vector2(150, 52))
	_btn_pass.pressed.connect(_do_pass)
	_actions.add_child(_btn_pass)

	_hand_area = Control.new()
	_hand_area.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hand_area.offset_top = -232
	_hand_area.offset_bottom = -18
	add_child(_hand_area)

	# Fast-forward lives in the top-right corner, away from the play field.
	# Local games only (vs bots); shown once the human has finished so they
	# don't have to sit through full-pace bot turns.
	_btn_ff = UIKit.pill_button(tr("GAME_FAST_FORWARD"), Color("6b5a3e"),
			Vector2(150, 46), 18)
	_btn_ff.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_btn_ff.offset_left = -166
	_btn_ff.offset_right = -16
	_btn_ff.offset_top = 14
	_btn_ff.offset_bottom = 60
	_btn_ff.visible = false
	_btn_ff.pressed.connect(_do_fast_forward)
	add_child(_btn_ff)


func _build_status() -> void:
	_status = UIKit.heading("", 24)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -336
	_status.offset_bottom = -300
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)


func _build_suit_popup() -> void:
	_suit_popup = PopupPanel.new()
	var panel_sb := UIKit.panel_style(UIKit.TABLE_MID, 16, UIKit.GOLD, 2)
	panel_sb.content_margin_left = 20
	panel_sb.content_margin_right = 20
	panel_sb.content_margin_top = 16
	panel_sb.content_margin_bottom = 16
	_suit_popup.add_theme_stylebox_override("panel", panel_sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(UIKit.heading(tr("GAME_DECLARE_SUIT"), 21))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for s in 4:
		var b := UIKit.pill_button(tr(SUIT_KEYS[s]), UIKit.SUIT_COLORS[s],
				Vector2(120, 48), 18)
		b.pressed.connect(_on_suit_chosen.bind(s))
		row.add_child(b)
	box.add_child(row)
	_suit_popup.add_child(box)
	add_child(_suit_popup)


func _build_fx_layer() -> void:
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)


func _build_game_over_layer() -> void:
	_game_over_layer = Control.new()
	_game_over_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_layer.visible = false
	add_child(_game_over_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_layer.add_child(dim)

	# CenterContainer keeps the panel centered even as the standings list
	# grows its minimum size (PRESET_CENTER would drift bottom-right).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(UIKit.TABLE_MID, 20, UIKit.GOLD, 2)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 32
	sb.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	_game_over_label = UIKit.heading("", 38)
	box.add_child(_game_over_label)

	_ranking_box = VBoxContainer.new()
	_ranking_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_ranking_box.add_theme_constant_override("separation", 6)
	box.add_child(_ranking_box)

	var again := UIKit.pill_button(tr("GAME_NEW"), Color("2e7d4f"), Vector2(260, 54))
	again.pressed.connect(func(): new_game_requested.emit())
	box.add_child(again)

	var menu := UIKit.pill_button(tr("MENU_BACK"), UIKit.BLUE, Vector2(260, 54))
	menu.pressed.connect(func(): exit_to_menu_requested.emit())
	box.add_child(menu)


# --- seats ----------------------------------------------------------------

func _setup_seats() -> void:
	for seat in _seats.values():
		seat.queue_free()
	_seats.clear()
	var s := _state()
	var opponents: Array = []
	for p in s.players:
		if p.id != LocalGameServer.HUMAN_ID:
			opponents.append(p)

	var slots: Array = []
	match opponents.size():
		1: slots = [Vector2(0.5, 0.11)]
		2: slots = [Vector2(0.3, 0.11), Vector2(0.7, 0.11)]
		_: slots = [Vector2(0.16, 0.16), Vector2(0.5, 0.09), Vector2(0.84, 0.16)]

	for i in opponents.size():
		var p: GameState.PlayerState = opponents[i]
		var seat := PlayerSeat.new(p.id, _display_name(p.id),
				UIKit.AVATAR_COLORS[(i + 1) % UIKit.AVATAR_COLORS.size()])
		var c: Vector2 = slots[i]
		seat.position = Vector2(size.x * c.x - 90, size.y * c.y - 30)
		add_child(seat)
		_seats[p.id] = seat

	var me := PlayerSeat.new(LocalGameServer.HUMAN_ID,
			_display_name(LocalGameServer.HUMAN_ID), UIKit.AVATAR_COLORS[0], true)
	me.position = Vector2(size.x * 0.075 - 90, size.y * 0.80 - 40)
	add_child(me)
	_seats[LocalGameServer.HUMAN_ID] = me

	# Center piles between the seats and the hand.
	_deck.position = Vector2(size.x * 0.42 - 62, size.y * 0.40 - 93)
	_discard.position = Vector2(size.x * 0.56 - 70, size.y * 0.40 - 100)
	_declared_chip.position = Vector2(size.x * 0.56 - 34, size.y * 0.40 + 96)
	_pending_badge.position = Vector2(size.x * 0.685, size.y * 0.40 - 22)


# --- state -> UI ----------------------------------------------------------

func _on_state_updated(events: Array) -> void:
	if not is_node_ready():
		await ready
	if _seats.is_empty():
		_setup_seats()
	_selected.clear()
	var had_anims := false
	for e in events:
		had_anims = _enqueue_event(e) or had_anims
	if had_anims:
		_drain()
	else:
		_refresh_all()


## Returns true when the event produced a queued animation.
func _enqueue_event(e: Dictionary) -> bool:
	match e.get("type", ""):
		"DEALT":
			_enqueue(_anim_deal.bind(e.hand_size))
		"START_CARD":
			_enqueue(_anim_start_card.bind(e.card))
		"CARDS_PLAYED":
			_enqueue(_anim_play_cards.bind(e.player, e.cards))
		"DREW":
			_enqueue(_anim_draw.bind(e.player, e.count, e.get("penalty", false)))
		"STOPPED":
			_enqueue(func():
				_seat_flash(e.player, tr("GAME_STOPPED_BADGE"), UIKit.RED)
				await _sleep(0.5))
		"ESO_CONTINUATION":
			_enqueue(func():
				_toast(tr("TOAST_ESO_CONTINUE") % _display_name(e.player))
				await _sleep(0.4))
		"PLAYER_FINISHED":
			_enqueue(func():
				_seat_flash(e.player, tr("GAME_FINISHED_MARK"), Color("2e7d4f"))
				if _seats.has(e.player):
					_seats[e.player].set_finished(true, e.get("position", 0))
				await _sleep(0.5))
		"PLAYER_RETURNED":
			_enqueue(func():
				_toast(tr("TOAST_RETURNED") % _display_name(e.player))
				await _sleep(0.5))
		"SPALENA_EXTRA_TURN":
			_enqueue(func():
				_toast(tr("TOAST_SPALENA"))
				await _sleep(0.5))
		"DECK_EXHAUSTED":
			_enqueue(func():
				_toast(tr("TOAST_DECK_EMPTY"))
				await _sleep(0.4))
		"GAME_OVER":
			_enqueue(func():
				await _sleep(0.4)
				_show_game_over(e.get("loser", "")))
		_:
			return false
	return true


func _enqueue(cb: Callable) -> void:
	_queue.append(cb)


func _drain() -> void:
	if _busy:
		return
	_busy = true
	_refresh_actions()
	while not _queue.is_empty():
		var cb: Callable = _queue.pop_front()
		@warning_ignore("redundant_await")
		await cb.call()
	_busy = false
	_refresh_all()


func _refresh_all() -> void:
	var s := _state()
	if s == null or _seats.is_empty():
		return
	for p in s.players:
		var seat: PlayerSeat = _seats.get(p.id)
		if seat == null:
			continue
		seat.set_finished(p.status == GameState.PlayerStatus.FINISHED,
				p.finish_position)
		seat.set_count(p.hand.size())
		seat.set_active(s.phase == GameState.Phase.PLAYING
				and s.players[s.current_index].id == p.id)
	_deck.set_count(s.draw_pile.size())
	var tail := s.discard_pile.slice(maxi(0, s.discard_pile.size() - 4))
	_discard.rebuild(tail)
	_refresh_center_chips(s)
	_refresh_hand(s)
	_refresh_actions()
	_refresh_status(s)


func _refresh_center_chips(s: GameState) -> void:
	if s.declared_suit != -1:
		_declared_label.text = tr(SUIT_KEYS[s.declared_suit])
		var sb: StyleBoxFlat = _declared_chip.get_theme_stylebox("panel")
		sb.bg_color = UIKit.SUIT_COLORS[s.declared_suit]
		_declared_chip.visible = true
	else:
		_declared_chip.visible = false
	if s.pending_sevens_draw > 0:
		_pending_label.text = "+%d" % s.pending_sevens_draw
		_pending_badge.visible = true
	elif s.pending_aces > 0:
		_pending_label.text = tr("GAME_ESO_STOP")
		_pending_badge.visible = true
	else:
		_pending_badge.visible = false


func _refresh_hand(s: GameState) -> void:
	for c in _hand_area.get_children():
		c.queue_free()
	var me := s.player_by_id(LocalGameServer.HUMAN_ID)
	if me == null:
		return
	var hand := me.hand.duplicate()
	hand.sort_custom(func(a, b):
		if FaraonCard.suit_of(a) != FaraonCard.suit_of(b):
			return FaraonCard.suit_of(a) < FaraonCard.suit_of(b)
		return FaraonCard.rank_of(a) < FaraonCard.rank_of(b))

	var n := hand.size()
	if n == 0:
		return
	var spacing := minf(94.0, (size.x - 420.0) / maxf(n, 1))
	var start_x := size.x / 2.0 - spacing * (n - 1) / 2.0 - 60.0
	for i in n:
		var cv := CardVisual.new(hand[i])
		var off := i - (n - 1) / 2.0
		cv.position = Vector2(start_x + i * spacing, 26.0 + absf(off) * 5.0)
		cv.rotation = off * 0.032
		cv.selected = _selected.has(hand[i])
		cv.set_order(_selected.find(hand[i]) + 1)
		cv.tapped.connect(_on_card_tapped)
		_hand_area.add_child(cv)


func _refresh_actions() -> void:
	var s := _state()
	if s == null:
		return
	var my_turn := _is_my_turn(s) and not _busy
	_btn_play.visible = not _busy
	_btn_play.disabled = not my_turn or _selected.is_empty()
	_btn_pass.visible = my_turn and s.pending_aces > 0
	_btn_draw.visible = not _busy and s.pending_aces == 0
	_btn_draw.disabled = not my_turn
	if s.pending_sevens_draw > 0 and my_turn:
		_btn_draw.text = tr("GAME_DRAW_CARD") + " +%d" % s.pending_sevens_draw
	else:
		_btn_draw.text = tr("GAME_DRAW_CARD")
	var me := s.player_by_id(LocalGameServer.HUMAN_ID)
	var human_out := me != null and me.status == GameState.PlayerStatus.FINISHED
	if server.fast_forward and me != null and not human_out:
		server.fast_forward = false # returned to the game -> normal pace
	_btn_ff.visible = s.phase == GameState.Phase.PLAYING and human_out \
			and not server.fast_forward


func _do_fast_forward() -> void:
	server.fast_forward = true
	_btn_ff.visible = false


## Animation time scale: fast-forward compresses the wait, not the moves.
func _anim_scale() -> float:
	return 0.3 if server != null and server.fast_forward else 1.0


func _refresh_status(s: GameState) -> void:
	if s.phase == GameState.Phase.GAME_OVER:
		_status.text = ""
		return
	if _is_my_turn(s):
		_status.text = tr("GAME_YOUR_TURN")
		_status.add_theme_color_override("font_color", UIKit.GOLD)
	else:
		_status.text = tr("GAME_TURN_OF") % _display_name(s.players[s.current_index].id)
		_status.add_theme_color_override("font_color", UIKit.CREAM)


# --- animations -----------------------------------------------------------

func _sleep(t: float) -> void:
	await get_tree().create_timer(t * _anim_scale()).timeout


func _flight_step(t: float, node: Control, from: Vector2, mid: Vector2,
		to: Vector2) -> void:
	if not is_instance_valid(node):
		return
	var a := from.lerp(mid, t)
	var b := mid.lerp(to, t)
	node.global_position = a.lerp(b, t)


## Quadratic-bezier flight with a bit of lift — no teleports, no straight
## laser lines.
func _fly(node: Control, from: Vector2, to: Vector2, dur: float,
		arc := 70.0, final_rot := 0.0) -> void:
	dur *= _anim_scale()
	node.global_position = from
	var mid := (from + to) / 2.0 + Vector2(randf_range(-24.0, 24.0), -arc)
	var tw := create_tween()
	tw.tween_method(_flight_step.bind(node, from, mid, to), 0.0, 1.0, dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "rotation", final_rot, dur)
	await tw.finished


func _spawn_overlay(card_id: String, width: float, at: Vector2) -> CardVisual:
	var cv := CardVisual.new(card_id, width)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(cv)
	cv.global_position = at
	cv.set_lift(18.0)
	return cv


func _anim_deal(hand_size: int) -> void:
	var s := _state()
	for seat in _seats.values():
		seat.set_count(0)
	_deck.set_count(32)
	await _sleep(0.25)
	for _round in hand_size:
		for p in s.players:
			var seat: PlayerSeat = _seats[p.id]
			var cv := _spawn_overlay("", 72, _deck.top_anchor())
			await _fly(cv, _deck.top_anchor(), seat.card_anchor(), 0.16, 40.0)
			cv.queue_free()
			seat.set_count(seat._shown_count + 1)


func _anim_start_card(card: String) -> void:
	var cv := _spawn_overlay("", 120, _deck.top_anchor())
	cv.flip_to(card, 0.3)
	await _fly(cv, _deck.top_anchor(), _discard.landing_anchor(), 0.36, 60.0,
			DiscardStack.rot_for(card))
	cv.queue_free()
	_discard.push_card(card)
	await _sleep(0.15)


func _anim_play_cards(player_id: String, cards: Array) -> void:
	var seat: PlayerSeat = _seats.get(player_id)
	var human := player_id == LocalGameServer.HUMAN_ID
	for card in cards:
		var origin: Vector2
		var cv: CardVisual
		if human:
			var hand_cv := _find_hand_card(card)
			origin = hand_cv.global_position if hand_cv != null \
					else _hand_area.global_position + Vector2(size.x / 2.0, 40.0)
			if hand_cv != null:
				hand_cv.visible = false
			cv = _spawn_overlay(card, 120, origin)
		else:
			origin = seat.card_anchor() if seat != null else Vector2(size.x / 2.0, 60.0)
			cv = _spawn_overlay("", 120, origin)
			cv.flip_to(card, 0.28)
			if seat != null:
				seat.set_count(seat._shown_count - 1)
		await _fly(cv, origin, _discard.landing_anchor(), 0.34, 80.0,
				DiscardStack.rot_for(card))
		cv.queue_free()
		_discard.push_card(card)
		await _sleep(0.12)
	await _sleep(0.1)


func _anim_draw(player_id: String, count: int, penalty: bool) -> void:
	var seat: PlayerSeat = _seats.get(player_id)
	var human := player_id == LocalGameServer.HUMAN_ID
	var target: Vector2 = _hand_area.global_position + Vector2(size.x / 2.0, 60.0) \
			if human else (seat.card_anchor() if seat != null else Vector2.ZERO)
	if penalty and count > 0:
		_seat_flash(player_id, "+%d" % count, UIKit.RED)
	for i in mini(count, 5):
		var cv := _spawn_overlay("", 90, _deck.top_anchor())
		await _fly(cv, _deck.top_anchor(), target, 0.22, 45.0)
		cv.queue_free()
		if seat != null:
			seat.set_count(seat._shown_count + 1)
		_deck.set_count(maxi(_deck_shown() - 1, 0))
	await _sleep(0.1)


func _deck_shown() -> int:
	return int(_deck._badge_label.text)


func _seat_flash(player_id: String, text: String, color: Color) -> void:
	var seat: PlayerSeat = _seats.get(player_id)
	if seat != null:
		seat.flash(text, color)


func _toast(msg: String) -> void:
	var chipn := UIKit.chip(msg, Color(UIKit.INK, 0.9), 19)
	_fx.add_child(chipn)
	chipn.reset_size()
	chipn.position = Vector2(size.x / 2.0 - chipn.size.x / 2.0, size.y * 0.30)
	chipn.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(chipn, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(chipn, "position:y", size.y * 0.27, 1.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(chipn, "modulate:a", 0.0, 0.3)
	tw.tween_callback(chipn.queue_free)


# --- interactions ---------------------------------------------------------

func _is_my_turn(s: GameState) -> bool:
	return s.phase == GameState.Phase.PLAYING \
			and s.players[s.current_index].id == LocalGameServer.HUMAN_ID


func _display_name(id: String) -> String:
	if id == LocalGameServer.HUMAN_ID:
		return tr("PLAYER_YOU")
	if id.begins_with("BOT"):
		return tr("BOT_NAME") % id.trim_prefix("BOT")
	return id


func _find_hand_card(card_id: String) -> CardVisual:
	for c in _hand_area.get_children():
		if c is CardVisual and c.card_id == card_id and c.visible:
			return c
	return null


func _on_card_tapped(cv: CardVisual) -> void:
	var s := _state()
	if _busy or not _is_my_turn(s):
		return
	var id := cv.card_id
	if _selected.has(id):
		_selected.erase(id)
	elif _selected.is_empty() \
			or FaraonCard.rank_of(id) == FaraonCard.rank_of(_selected[0]):
		_selected.append(id)
	else:
		_selected.clear()
		_selected.append(id)
	_refresh_hand(s)
	_refresh_actions()


func _do_play() -> void:
	if _busy or _selected.is_empty():
		return
	# Cards go to the server exactly in the order the player numbered them
	# (1 = first on the pile, last = new top). No silent reordering — an
	# invalid order comes back as a rejection toast and the player fixes it.
	var ordered: Array = _selected.duplicate()
	if FaraonCard.is_hornik(ordered.back()):
		_pending_play = ordered
		_suit_popup.popup_centered()
		return
	server.propose(LocalGameServer.HUMAN_ID, FaraonActions.play(ordered))


func _do_draw() -> void:
	if _busy:
		return
	if _is_my_turn(_state()) and _state().pending_aces == 0:
		server.propose(LocalGameServer.HUMAN_ID, FaraonActions.draw())


func _do_pass() -> void:
	if _busy:
		return
	server.propose(LocalGameServer.HUMAN_ID, FaraonActions.pass_turn())


func _on_suit_chosen(suit: int) -> void:
	_suit_popup.hide()
	if _pending_play.is_empty():
		return
	server.propose(LocalGameServer.HUMAN_ID,
			FaraonActions.play(_pending_play, suit))
	_pending_play = []


func _on_action_rejected(player_id: String, error: String) -> void:
	if player_id != LocalGameServer.HUMAN_ID:
		return
	if error == "card_does_not_match" and _selected.size() > 1:
		# Multi-card play rejected on the opener: the combination/order is
		# the problem, tell the player instead of silently reordering.
		_toast(tr("ERR_FIRST_CARD_ORDER"))
		return
	var key := "ERR_" + error.to_upper()
	_toast(tr(key) if tr(key) != key else tr("ERR_GENERIC"))


func _show_game_over(_loser_id: String) -> void:
	_game_over_layer.visible = true
	var s := _state()
	var me := s.player_by_id(LocalGameServer.HUMAN_ID)
	var last := s.players.size()

	# Only 1st place counts as a win; last place is the explicit loss;
	# anything between is an informative placement.
	if me.finish_position == 1:
		_game_over_label.text = tr("GAME_OVER_WIN")
		_game_over_label.add_theme_color_override("font_color", Color("6fd08c"))
	elif me.finish_position == last or me.finish_position == -1:
		_game_over_label.text = tr("GAME_OVER_LOSE")
		_game_over_label.add_theme_color_override("font_color", UIKit.RED.lightened(0.2))
	else:
		_game_over_label.text = tr("GAME_OVER_PLACE") % me.finish_position
		_game_over_label.add_theme_color_override("font_color", UIKit.GOLD)

	# Full standings, best placement first.
	for c in _ranking_box.get_children():
		c.queue_free()
	var ranked := s.players.duplicate()
	ranked.sort_custom(func(a, b):
		var pa: int = a.finish_position if a.finish_position != -1 else last + 1
		var pb: int = b.finish_position if b.finish_position != -1 else last + 1
		return pa < pb)
	for p in ranked:
		var place := str(p.finish_position) + "." if p.finish_position != -1 else "–"
		var row := UIKit.heading("%s %s" % [place, _display_name(p.id)], 21,
				UIKit.GOLD if p.finish_position == 1 else UIKit.CREAM)
		_ranking_box.add_child(row)
