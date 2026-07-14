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
signal restart_requested

var server: LocalGameServer
var _selected: Array[String] = []
var _seats := {} # player_id -> PlayerSeat
var _opponent_ids: Array[String] = [] # seat order for re-layout
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
var _btn_interrupt_play: Button
var _btn_interrupt_draw: Button
var _suit_popup: PopupPanel
var _fx: Control
var _game_over_layer: Control
var _game_over_label: Label
var _ranking_box: VBoxContainer
var _btn_again: Button
var _pause_layer: Control
var _pending_play: Array = []
## Alternates the shuffle style (riffle / overhand) between plays.
var _shuffle_variant := 0


func setup(game_server: LocalGameServer) -> void:
	server = game_server
	server.state_updated.connect(_on_state_updated)
	server.action_rejected.connect(_on_action_rejected)


func _state() -> GameState:
	return server.rules.state


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_table()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_center()
	_build_hand_and_actions()
	_build_status()
	_build_suit_popup()
	_build_fx_layer()
	_build_game_over_layer()
	_build_pause_layer()
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

	# Photo table looks sit between the base color and the light overlays,
	# slightly darkened so cards and badges keep their contrast.
	var look := TableLook.active()
	if look.texture_path != "" and ResourceLoader.exists(look.texture_path):
		var photo := TextureRect.new()
		photo.texture = load(look.texture_path)
		photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photo.modulate = Color(0.82, 0.82, 0.82)
		photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(photo)

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

	# Paused penalty draw: play the just-drawn faraón or keep drawing.
	_btn_interrupt_play = UIKit.pill_button(tr("GAME_INTERRUPT_PLAY"),
			Color("2e7d4f"), Vector2(210, 52))
	_btn_interrupt_play.visible = false
	_btn_interrupt_play.pressed.connect(func():
		if not _busy:
			server.propose(LocalGameServer.HUMAN_ID, FaraonActions.play(["DE"])))
	_actions.add_child(_btn_interrupt_play)

	_btn_interrupt_draw = UIKit.pill_button(tr("GAME_INTERRUPT_DRAW"),
			UIKit.BLUE, Vector2(190, 52))
	_btn_interrupt_draw.visible = false
	_btn_interrupt_draw.pressed.connect(func():
		if not _busy:
			server.propose(LocalGameServer.HUMAN_ID, FaraonActions.draw()))
	_actions.add_child(_btn_interrupt_draw)

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

	_btn_again = UIKit.pill_button(tr("GAME_NEW"), Color("2e7d4f"), Vector2(260, 54))
	_btn_again.pressed.connect(func(): new_game_requested.emit())
	box.add_child(_btn_again)

	var menu := UIKit.pill_button(tr("MENU_BACK"), UIKit.BLUE, Vector2(260, 54))
	menu.pressed.connect(func(): exit_to_menu_requested.emit())
	box.add_child(menu)


# --- seats ----------------------------------------------------------------

func _setup_seats() -> void:
	for seat in _seats.values():
		seat.queue_free()
	_seats.clear()
	_opponent_ids.clear()
	var s := _state()
	for p in s.players:
		if p.id != LocalGameServer.HUMAN_ID:
			_opponent_ids.append(p.id)

	for i in _opponent_ids.size():
		var seat := PlayerSeat.new(_opponent_ids[i], _display_name(_opponent_ids[i]),
				UIKit.AVATAR_COLORS[(i + 1) % UIKit.AVATAR_COLORS.size()])
		add_child(seat)
		_seats[_opponent_ids[i]] = seat

	var me := PlayerSeat.new(LocalGameServer.HUMAN_ID,
			_display_name(LocalGameServer.HUMAN_ID), UIKit.AVATAR_COLORS[0], true)
	add_child(me)
	_seats[LocalGameServer.HUMAN_ID] = me
	_layout_table()


## Positions everything that depends on the window size. Runs again on every
## resize (desktop window drag, mobile rotation via the orientation sensor),
## with portrait-specific slots so the piles never collide on narrow screens.
func _layout_table() -> void:
	if _seats.is_empty() or _deck == null:
		return
	var portrait := size.y > size.x

	var slots: Array = []
	match _opponent_ids.size():
		1: slots = [Vector2(0.5, 0.10)]
		2: slots = [Vector2(0.26, 0.10), Vector2(0.74, 0.10)] if portrait \
				else [Vector2(0.3, 0.11), Vector2(0.7, 0.11)]
		_: slots = [Vector2(0.16, 0.17), Vector2(0.5, 0.07), Vector2(0.84, 0.17)] if portrait \
				else [Vector2(0.16, 0.16), Vector2(0.5, 0.09), Vector2(0.84, 0.16)]
	for i in _opponent_ids.size():
		var seat: PlayerSeat = _seats.get(_opponent_ids[i])
		if seat != null and i < slots.size():
			var c: Vector2 = slots[i]
			seat.position = Vector2(size.x * c.x - 90, size.y * c.y - 30)
	var me: PlayerSeat = _seats.get(LocalGameServer.HUMAN_ID)
	if me != null:
		me.position = Vector2(maxf(size.x * 0.075 - 90, 4.0), size.y * 0.80 - 40)

	# Center piles: side by side, spread wider apart in portrait so the
	# 110-120px cards don't overlap on narrow screens.
	var deck_x := 0.28 if portrait else 0.42
	var disc_x := 0.72 if portrait else 0.56
	var pile_y := 0.38 if portrait else 0.40
	_deck.position = Vector2(size.x * deck_x - 62, size.y * pile_y - 93)
	_discard.position = Vector2(size.x * disc_x - 70, size.y * pile_y - 100)
	_declared_chip.position = Vector2(size.x * disc_x - 34, size.y * pile_y + 96)
	_pending_badge.position = Vector2(size.x * (0.88 if portrait else 0.685),
			size.y * pile_y - 22)
	if _state() != null:
		_refresh_hand(_state())


# --- state -> UI ----------------------------------------------------------

func _on_state_updated(events: Array) -> void:
	if not is_node_ready():
		await ready
	var new_round := events.any(func(e): return e.get("type", "") == "DEALT")
	if new_round:
		# Drop any leftover animations from the previous round BEFORE the
		# seats are rebuilt: those queued callables capture seats that are
		# about to be freed (crash-grade race on fast Nová hra clicks).
		_queue.clear()
	if _seats.is_empty() or new_round:
		_setup_seats() # a new round may have a different set of players
	if new_round:
		_game_over_layer.visible = false
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
			_enqueue(_anim_deal.bind(e.hands))
		"START_CARD":
			_enqueue(_anim_start_card.bind(e.card))
		"CARDS_PLAYED":
			_enqueue(_anim_play_cards.bind(e.player, e.cards))
		"DREW":
			_enqueue(_anim_draw.bind(e.player, e.count, e.get("penalty", false)))
		"PILE_REFLIPPED":
			_enqueue(_anim_reflip.bind(e.top, e.remaining))
		"PENALTY_INTERRUPT":
			_enqueue(func():
				if e.player == LocalGameServer.HUMAN_ID:
					Haptics.tap()
				_toast(tr("TOAST_INTERRUPT") % _display_name(e.player))
				await _sleep(0.4))
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
			_enqueue(_anim_spalena)
		"DECK_EXHAUSTED":
			_enqueue(func():
				_toast(tr("TOAST_DECK_EMPTY"))
				await _sleep(0.4))
		"GAME_OVER":
			_enqueue(func():
				Haptics.buzz()
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
	# Events that landed between the last loop check and _busy=false would
	# otherwise sit unprocessed until the next state update ("stuck" anims).
	if not _queue.is_empty():
		_drain()
	else:
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
	_discard.set_depth(s.discard_pile.size())
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
	var me := s.player_by_id(LocalGameServer.HUMAN_ID)
	_render_hand(_sorted_hand(me.hand) if me != null else [])


## The display order of the local hand (by suit, then rank).
func _sorted_hand(cards: Array) -> Array:
	var hand := cards.duplicate()
	hand.sort_custom(func(a, b):
		if FaraonCard.suit_of(a) != FaraonCard.suit_of(b):
			return FaraonCard.suit_of(a) < FaraonCard.suit_of(b)
		return FaraonCard.rank_of(a) < FaraonCard.rank_of(b))
	return hand


## Local position of hand slot i when n cards are fanned out.
func _hand_slot(i: int, n: int) -> Vector2:
	# Narrow (portrait) screens reserve less side margin for the fan.
	var reserve := 420.0 if size.x > size.y else 150.0
	var spacing := minf(94.0, (size.x - reserve) / maxf(n, 1))
	var start_x := size.x / 2.0 - spacing * (n - 1) / 2.0 - 60.0
	var off := i - (n - 1) / 2.0
	return Vector2(start_x + i * spacing, 26.0 + absf(off) * 5.0)


## Rebuilds the fan from an explicit card list (used mid-deal/mid-draw to
## reveal the hand progressively, and by _refresh_hand for the full state).
func _render_hand(hand: Array) -> void:
	for c in _hand_area.get_children():
		c.queue_free()
	var n := hand.size()
	for i in n:
		var cv := CardVisual.new(hand[i])
		var off := i - (n - 1) / 2.0
		cv.position = _hand_slot(i, n)
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
	var interrupt := s.penalty_interrupt and my_turn
	_btn_interrupt_play.visible = interrupt
	_btn_interrupt_draw.visible = interrupt
	_btn_play.visible = not _busy and not interrupt
	_btn_play.disabled = not my_turn or _selected.is_empty()
	_btn_pass.visible = my_turn and s.pending_aces > 0
	_btn_draw.visible = not _busy and s.pending_aces == 0 and not interrupt
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


## A stack of face-down cards used as a shuffle prop.
func _make_stack(n: int, w: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(w, w * 1.5)
	holder.pivot_offset = holder.size / 2.0
	for i in n:
		var cv := CardVisual.new("", w)
		cv.position = Vector2(-i * 1.5, -i * 1.5)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(cv)
	_fx.add_child(holder)
	return holder


## Shuffle show before dealing and after a preshuffle — alternates between a
## riffle (split, interleave, merge) and an overhand (chunks over the top),
## per the two reference clips. `quick` halves the repetitions so the reflip
## sequence stays under ~1.5s.
func _anim_shuffle(at: Vector2, quick := false) -> void:
	_shuffle_variant = (_shuffle_variant + 1) % 2
	if _shuffle_variant == 1:
		await _anim_shuffle_riffle(at, quick)
	else:
		await _anim_shuffle_overhand(at, quick)


func _anim_shuffle_riffle(at: Vector2, quick: bool) -> void:
	var k := _anim_scale()
	var left := _make_stack(3, 100)
	var right := _make_stack(3, 100)
	left.global_position = at
	right.global_position = at
	var split := create_tween()
	split.set_parallel(true)
	split.tween_property(left, "global_position", at + Vector2(-62, 10), 0.16 * k) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	split.tween_property(left, "rotation", -0.22, 0.16 * k)
	split.tween_property(right, "global_position", at + Vector2(62, 10), 0.16 * k) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	split.tween_property(right, "rotation", 0.22, 0.16 * k)
	await split.finished
	# Interleave: thin cards flip-flop from both halves into the middle.
	for i in (4 if quick else 8):
		var side := left if i % 2 == 0 else right
		var cv := CardVisual.new("", 100)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx.add_child(cv)
		cv.global_position = side.global_position
		cv.rotation = side.rotation
		var drop := create_tween()
		drop.set_parallel(true)
		drop.tween_property(cv, "global_position", at + Vector2(0, 8 - i * 1.2),
				0.06 * k)
		drop.tween_property(cv, "rotation", 0.0, 0.06 * k)
		await drop.finished
		cv.queue_free()
	# The bridge: both halves snap back together.
	var merge := create_tween()
	merge.set_parallel(true)
	merge.tween_property(left, "global_position", at, 0.14 * k) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	merge.tween_property(left, "rotation", 0.0, 0.14 * k)
	merge.tween_property(right, "global_position", at, 0.14 * k) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	merge.tween_property(right, "rotation", 0.0, 0.14 * k)
	await merge.finished
	left.queue_free()
	right.queue_free()


func _anim_shuffle_overhand(at: Vector2, quick: bool) -> void:
	var k := _anim_scale()
	var base := _make_stack(4, 100)
	base.global_position = at
	for _i in (2 if quick else 4):
		var chunk := _make_stack(2, 100)
		chunk.global_position = at + Vector2(2, -4)
		var up := at + Vector2(randf_range(-12.0, 12.0), -54.0)
		var hop := create_tween()
		hop.tween_property(chunk, "global_position", up, 0.11 * k) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		hop.tween_property(chunk, "global_position", at + Vector2(-2, 2), 0.11 * k) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await hop.finished
		chunk.queue_free()
		await _sleep(0.03)
	base.queue_free()


## Full-screen spálená moment: ember burst, hot glow, big banner and a long
## vibration on handhelds — the burn spreads over everything but the text.
func _anim_spalena() -> void:
	Haptics.rumble()
	var k := _anim_scale()

	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.45, 0.05, 0.55), Color(0.9, 0.25, 0.02, 0.30),
		Color(0.4, 0.05, 0.0, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 1.1)
	gt.width = 640
	gt.height = 640
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate.a = 0.0
	_fx.add_child(glow)

	var embers := CPUParticles2D.new()
	embers.amount = 90
	embers.lifetime = 1.0
	embers.one_shot = true
	embers.explosiveness = 0.6
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(size.x * 0.45, size.y * 0.25)
	embers.direction = Vector2(0, -1)
	embers.spread = 40.0
	embers.gravity = Vector2(0, -420)
	embers.initial_velocity_min = 90.0
	embers.initial_velocity_max = 260.0
	embers.scale_amount_min = 2.0
	embers.scale_amount_max = 5.0
	var pgrad := Gradient.new()
	pgrad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	pgrad.colors = PackedColorArray([
		Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.35, 0.05, 0.9),
		Color(0.3, 0.05, 0.0, 0.0),
	])
	embers.color_ramp = pgrad
	embers.position = Vector2(size.x / 2.0, size.y * 0.55)
	embers.emitting = true
	_fx.add_child(embers)

	var banner := UIKit.heading(tr("GAME_SPALENA_BANNER"), 74, Color(1.0, 0.62, 0.12))
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.pivot_offset = size / 2.0
	banner.scale = Vector2(0.3, 0.3)
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(banner)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(glow, "modulate:a", 1.0, 0.18 * k)
	tw.tween_property(banner, "modulate:a", 1.0, 0.16 * k)
	tw.tween_property(banner, "scale", Vector2(1.12, 1.12), 0.22 * k) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	var settle := create_tween()
	settle.tween_property(banner, "scale", Vector2.ONE, 0.10 * k)
	await _sleep(0.7)
	var out := create_tween()
	out.set_parallel(true)
	out.tween_property(glow, "modulate:a", 0.0, 0.3 * k)
	out.tween_property(banner, "modulate:a", 0.0, 0.3 * k)
	await out.finished
	glow.queue_free()
	banner.queue_free()
	embers.queue_free()


## Deals per-player hand sizes (Olympic rounds shrink them) round-robin —
## one card to each player per lap, exactly like a physical deal. The local
## player's cards flip face-up and build the fan one by one; opponents only
## ever see backs. The draw pile thins in real time with every card.
func _anim_deal(hands: Dictionary) -> void:
	var s := _state()
	for seat in _seats.values():
		seat.set_count(0)
	_render_hand([])
	_deck.set_count(32)
	await _anim_shuffle(_deck.top_anchor())
	await _sleep(0.1)
	var me := s.player_by_id(LocalGameServer.HUMAN_ID)
	var shown: Array = []
	var max_size := 0
	for id in hands:
		max_size = maxi(max_size, hands[id])
	for round_i in max_size:
		for p in s.players:
			if round_i >= int(hands.get(p.id, 0)):
				continue
			var seat: PlayerSeat = _seats.get(p.id)
			if seat == null or not is_instance_valid(seat):
				continue # seats were rebuilt mid-animation (fast restart)
			if p.id == LocalGameServer.HUMAN_ID and me != null \
					and round_i < me.hand.size():
				# Engine deals round-robin too, so hand[round_i] IS this card.
				shown = await _reveal_hand_card(shown, me.hand[round_i], 0.16)
			else:
				await _fly_from_deck(seat.card_anchor(), 0.16)
			if is_instance_valid(seat):
				seat.set_count(seat._shown_count + 1)
			await _sleep(0.02)


func _anim_start_card(card: String) -> void:
	var cv := _spawn_overlay("", 120, _deck.top_anchor())
	cv.flip_to(card, 0.3)
	await _fly(cv, _deck.top_anchor(), _discard.landing_anchor(), 0.36, 60.0,
			DiscardStack.rot_for(card))
	cv.queue_free()
	_discard.push_card(card)
	_deck.set_count(maxi(_deck_shown() - 1, 0))
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


## In-game menu (☰, top-left): resume, restart, audio/vibration toggles and
## the way back to the main menu — the table is no longer a dead end.
func _build_pause_layer() -> void:
	var btn := UIKit.pill_button("☰", Color(UIKit.INK, 0.85), Vector2(56, 46), 20)
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left = 16
	btn.offset_right = 72
	btn.offset_top = 14
	btn.offset_bottom = 60
	btn.pressed.connect(func(): _pause_layer.visible = true)
	add_child(btn)

	_pause_layer = Control.new()
	_pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(UIKit.TABLE_MID, 20, UIKit.GOLD, 2)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	box.add_child(UIKit.heading(tr("GAME_MENU"), 28, UIKit.GOLD))

	var resume := UIKit.pill_button(tr("GAME_RESUME"), Color("2e7d4f"), Vector2(280, 50))
	resume.pressed.connect(func(): _pause_layer.visible = false)
	box.add_child(resume)

	var restart := UIKit.pill_button(tr("GAME_RESTART"), UIKit.BLUE, Vector2(280, 50))
	restart.pressed.connect(func(): restart_requested.emit())
	box.add_child(restart)

	box.add_child(_pause_toggle("SETTINGS_SOUND",
			GameSettings.get_sound_on, GameSettings.set_sound_on))
	box.add_child(_pause_toggle("SETTINGS_MUSIC",
			GameSettings.get_music_on, GameSettings.set_music_on))
	box.add_child(_pause_toggle("SETTINGS_VIBRATIONS",
			GameSettings.get_vibrations_on, GameSettings.set_vibrations_on))

	var quit := UIKit.pill_button(tr("MENU_BACK"), UIKit.RED, Vector2(280, 50))
	quit.pressed.connect(func(): exit_to_menu_requested.emit())
	box.add_child(quit)


func _pause_toggle(label_key: String, getter: Callable, setter: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = tr(label_key)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", UIKit.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = getter.call()
	toggle.toggled.connect(func(on: bool): setter.call(on))
	h.add_child(toggle)
	return h


## Preshuffle: the discard's top card steps aside, the spent pile flips over
## as one block (pseudo-3D squeeze on the whole holder) and slides onto the
## draw-pile spot with fresh depth, then the kept card settles back as the
## thin new discard. ~1.1s at normal pace; fast-forward compresses it via
## _anim_scale like every other animation.
func _anim_reflip(top_id: String, remaining: int) -> void:
	var k := _anim_scale()
	var discard_at := _discard.landing_anchor()

	# Capture the visible tail faces before clearing — they become the block
	# that flips; the kept top card becomes its own overlay.
	var tail_ids: Array = []
	for c in _discard._cards:
		if c.card_id != "":
			tail_ids.append(c.card_id)
	if not tail_ids.is_empty():
		tail_ids.pop_back() # the top card is animated separately
	if tail_ids.is_empty():
		tail_ids.append("") # face-down filler when nothing else was visible

	var kept := _spawn_overlay(top_id, 120, discard_at)
	kept.rotation = DiscardStack.rot_for(top_id)
	_discard.rebuild([])
	_discard.set_depth(0)

	var pile := Control.new()
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.size = Vector2(120, 180)
	pile.pivot_offset = pile.size / 2.0
	_fx.add_child(pile)
	pile.global_position = discard_at
	var block: Array = []
	for i in mini(tail_ids.size(), 3):
		var cv := CardVisual.new(tail_ids[i], 120)
		cv.position = Vector2(-i * 2.0, -i * 2.0)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pile.add_child(cv)
		block.append(cv)

	# 1. The kept card slides aside toward the player.
	await _fly(kept, discard_at, discard_at + Vector2(-26.0, 96.0), 0.22, 30.0)

	# 2. The whole block flips face-down at once (squeeze -> swap -> unsqueeze).
	var tw := create_tween()
	tw.tween_property(pile, "scale:x", 0.0, 0.14 * k) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		for cv in block:
			cv.set_card(""))
	tw.tween_property(pile, "scale:x", 1.0, 0.14 * k) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	# 3. ...and glides onto the draw-pile spot, gets a quick shuffle and
	# regains full depth.
	await _fly(pile, pile.global_position, _deck.top_anchor(), 0.3, 60.0)
	pile.queue_free()
	_deck.set_count(remaining)
	await _anim_shuffle(_deck.top_anchor(), true)

	# 4. The kept card settles back as the start of the new, thin discard.
	await _fly(kept, kept.global_position, _discard.landing_anchor(), 0.2, 24.0,
			DiscardStack.rot_for(top_id))
	kept.queue_free()
	_discard.push_card(top_id)
	await _sleep(0.1)


## Shared "one card leaves the draw pile" primitive used by dealing and by
## every draw: flies a back from the deck to `target`, optionally flipping
## it face-up mid-flight, and thins the deck badge/layers in real time.
func _fly_from_deck(target: Vector2, per_dur: float, reveal_as := "") -> void:
	var cv := _spawn_overlay("", 90, _deck.top_anchor())
	if reveal_as != "":
		cv.flip_to(reveal_as, per_dur * 1.4)
	await _fly(cv, _deck.top_anchor(), target, per_dur, 45.0)
	cv.queue_free()
	_deck.set_count(maxi(_deck_shown() - 1, 0))


## Reveals one more card of the local hand: sorted insertion, the flight
## lands exactly on the card's final slot, then the fan re-renders.
func _reveal_hand_card(shown: Array, card: String, per_dur: float) -> Array:
	shown = _sorted_hand(shown + [card])
	var idx := shown.find(card)
	var slot := _hand_area.global_position + _hand_slot(idx, shown.size())
	await _fly_from_deck(slot, per_dur, card)
	_render_hand(shown)
	return shown


## Draw animation scales to ANY count (a 9-card sedma penalty animates all
## nine, faster per card, never capped). The human's cards flip face-up and
## slot into the fan one by one; opponents receive backs at their seat.
func _anim_draw(player_id: String, count: int, penalty: bool) -> void:
	var seat: PlayerSeat = _seats.get(player_id)
	var human := player_id == LocalGameServer.HUMAN_ID
	if penalty and count > 0:
		_seat_flash(player_id, "+%d" % count, UIKit.RED)
		if human:
			Haptics.buzz()
	var per := 0.22 if count <= 3 else maxf(0.09, 0.8 / count)
	if human:
		var me := _state().player_by_id(LocalGameServer.HUMAN_ID)
		var shown: Array = []
		for c in _hand_area.get_children():
			if c is CardVisual and c.card_id != "":
				shown.append(c.card_id)
		var incoming: Array = me.hand.filter(func(c): return not shown.has(c)) \
				if me != null else []
		for card in incoming:
			shown = await _reveal_hand_card(shown, card, per)
	else:
		for i in count:
			var anchor := seat.card_anchor() if seat != null \
					and is_instance_valid(seat) else Vector2(size.x / 2.0, 60.0)
			await _fly_from_deck(anchor, per)
			if seat != null and is_instance_valid(seat):
				seat.set_count(seat._shown_count + 1)
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
		var custom := GameSettings.get_player_name()
		return custom if custom != "" else tr("PLAYER_YOU")
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
	var m := server.match_state

	# Headline. Match end beats round placement; a spectating human (already
	# eliminated from an Olympic match) gets a neutral round-over line. For a
	# single round: only 1st place is a win, last place is the explicit loss,
	# anything between is informative.
	if m != null and m.finished:
		if m.champion == LocalGameServer.HUMAN_ID:
			_game_over_label.text = tr("MATCH_WIN")
			_game_over_label.add_theme_color_override("font_color", Color("6fd08c"))
		else:
			_game_over_label.text = tr("MATCH_LOSE") % _display_name(m.champion)
			_game_over_label.add_theme_color_override("font_color", UIKit.RED.lightened(0.2))
	elif me == null:
		_game_over_label.text = tr("ROUND_OVER")
		_game_over_label.add_theme_color_override("font_color", UIKit.CREAM)
	elif me.finish_position == 1:
		_game_over_label.text = tr("GAME_OVER_WIN")
		_game_over_label.add_theme_color_override("font_color", Color("6fd08c"))
	elif me.finish_position == last or me.finish_position == -1:
		_game_over_label.text = tr("GAME_OVER_LOSE")
		_game_over_label.add_theme_color_override("font_color", UIKit.RED.lightened(0.2))
	else:
		_game_over_label.text = tr("GAME_OVER_PLACE") % me.finish_position
		_game_over_label.add_theme_color_override("font_color", UIKit.GOLD)

	# Full round standings, best placement first.
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

	# Olympic modes: match state (cards next round / out) under the round.
	if m != null:
		_ranking_box.add_child(UIKit.heading(
				tr("MATCH_STANDINGS") + "  ·  " + tr("MATCH_ROUND") % m.round_number,
				17, UIKit.CREAM.darkened(0.2)))
		for id in m.allotments:
			var n: int = m.allotments[id]
			var text := "%s — %s" % [_display_name(id),
					tr("MATCH_CARDS") % n if n > 0 else tr("MATCH_OUT")]
			_ranking_box.add_child(UIKit.heading(text, 16,
					UIKit.CREAM if n > 0 else UIKit.CREAM.darkened(0.45)))
	_btn_again.text = tr("GAME_NEXT_ROUND") if m != null and not m.finished \
			else tr("GAME_NEW")

	# Progression: award the round once (only when the human played in it).
	if me != null and me.finish_position != -1:
		var award := Progression.record_round(s.players.size(),
				me.finish_position, GameSettings.get_bot_difficulty())
		if award.points > 0:
			_ranking_box.add_child(UIKit.heading(
					tr("POINTS_EARNED") % award.points, 19, UIKit.GOLD))
		if award.level_after > award.level_before:
			_ranking_box.add_child(UIKit.heading(
					tr("LEVEL_UP") % award.level_after, 21, Color("6fd08c")))
