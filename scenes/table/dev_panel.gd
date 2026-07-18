class_name DevPanel
extends Control
## Dev režim: ladiaci panel na stole (len lokálne hry). Zapína sa 7 ťukmi
## na nadpis „Nastavenia" alebo `[dev] dev_mode=true` v settings.cfg.
## Umožňuje: dať ľubovoľnú kartu ľubovoľnému hráčovi, nastaviť tresty/stopky,
## spustiť efekty (spálená, shuffle, reflip, otočenie balíčka) a rýchlo
## ukončiť kolo. Všetko je lokálna „state surgery" — v multiplayeri panel
## nie je dostupný (server by ju aj tak odmietol).

var table: GameTable

var _target_idx := 0
var _rank_idx := 0
var _suit_idx := 0


func _init(p_table: GameTable) -> void:
	table = p_table


func _state() -> GameState:
	return table.server.rules.state


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 80
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			queue_free())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color("232a36", 0.98), 16, Color("d0a93c"), 2)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	box.add_child(UIKit.heading("DEV PANEL", 24, Color("d0a93c")))

	# --- dať kartu hráčovi -------------------------------------------------
	box.add_child(UIKit.heading("Dať kartu", 17, UIKit.CREAM))
	var give := HBoxContainer.new()
	give.add_theme_constant_override("separation", 8)
	var target := OptionButton.new()
	for i in _state().players.size():
		target.add_item(table.server.display_name(_state().players[i].id), i)
	target.item_selected.connect(func(i): _target_idx = i)
	give.add_child(target)
	var rank := OptionButton.new()
	for r in 8:
		rank.add_item(FaraonCard.RANK_NAMES[r], r)
	rank.item_selected.connect(func(i): _rank_idx = i)
	give.add_child(rank)
	var suit := OptionButton.new()
	for s in 4:
		suit.add_item(FaraonCard.SUIT_NAMES[s], s)
	suit.item_selected.connect(func(i): _suit_idx = i)
	give.add_child(suit)
	var give_btn := UIKit.pill_button("Daj", Color("2e7d4f"), Vector2(90, 40), 15)
	give_btn.pressed.connect(func():
		_give_card(FaraonCard.make_id(_rank_idx, _suit_idx)))
	give.add_child(give_btn)
	var give_rv := UIKit.pill_button("Tanečnica", Color("55617a"), Vector2(120, 40), 14)
	give_rv.pressed.connect(func(): _give_card(FaraonCard.REVERSE_ID))
	give.add_child(give_rv)
	box.add_child(give)

	# --- stav ---------------------------------------------------------------
	box.add_child(UIKit.heading("Stav", 17, UIKit.CREAM))
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 8)
	st.add_child(_mini("Trest +3", func(): _state().pending_sevens_draw += 3))
	st.add_child(_mini("Stopka +1", func(): _state().pending_aces += 1))
	st.add_child(_mini("Vynuluj tresty", func():
		_state().pending_sevens_draw = 0
		_state().pending_aces = 0
		_state().penalty_interrupt = false
		_state().interrupt_card = ""
		_state().pending_hard_penalty = false))
	st.add_child(_mini("Môj ťah", func():
		_state().current_index = _state().index_of(table._me)))
	box.add_child(st)

	# --- efekty -------------------------------------------------------------
	box.add_child(UIKit.heading("Efekty a animácie", 17, UIKit.CREAM))
	var fx := HBoxContainer.new()
	fx.add_theme_constant_override("separation", 8)
	fx.add_child(_mini("Spálená", func(): table._anim_spalena()))
	fx.add_child(_mini("Shuffle", func():
		table._anim_shuffle(table._deck.top_anchor())))
	fx.add_child(_mini("Otoč balíček", func():
		table._anim_start_deck_flip("9C")))
	fx.add_child(_mini("Otoč smer", func():
		_state().direction *= -1))
	box.add_child(fx)

	# --- rýchle konce -------------------------------------------------------
	var ends := HBoxContainer.new()
	ends.add_theme_constant_override("separation", 8)
	ends.add_child(_mini("Vyprázdni mi ruku (výhra)", func():
		var me := _state().player_by_id(table._me)
		if me != null and me.hand.size() > 1:
			var keep: Array[String] = [me.hand[0]]
			me.hand.assign(keep)))
	ends.add_child(_mini("Rýchli boti", func():
		table.server.bot_delay = 0.1))
	box.add_child(ends)

	var close := UIKit.pill_button("Zavrieť", UIKit.BLUE, Vector2(180, 44), 15)
	close.pressed.connect(queue_free)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(close)
	box.add_child(row)


func _mini(text: String, cb: Callable) -> Button:
	var b := UIKit.pill_button(text, Color("3f5b6e"), Vector2(0, 40), 13)
	b.pressed.connect(func():
		cb.call()
		table._refresh_all())
	return b


func _give_card(card: String) -> void:
	var s := _state()
	var p := s.players[_target_idx]
	# Kartu najprv odober z obehu (balíček/ruky/kôpka okrem vrchu), nech
	# ostáva konzervácia kariet aspoň približne pravdivá.
	s.draw_pile.erase(card)
	for other in s.players:
		other.hand.erase(card)
	if not p.hand.has(card):
		p.hand.append(card)
	table._refresh_all()
