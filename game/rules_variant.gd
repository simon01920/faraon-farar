class_name RulesVariant
extends RefCounted
## Rules-variant configuration. Faraón spread by word of mouth and has many
## house-rule flavours — the base ruleset (rules/faraon.pdf) stays the
## default and individual house rules are opt-in toggles. In multiplayer the
## room creator's toggles will be authoritative for the whole room.

enum Kind { CLASSIC, OLYMPIC }

var kind: Kind = Kind.CLASSIC
## Cards dealt to each player at round start. Olympic decreases this per lost
## round (handled by the meta-game layer, not the in-round engine).
var initial_hand_size: int = 5

## House rule: faraón (zelený dolník) also blocks esá — a stopped player may
## cancel the whole ace chain by playing it. OFF = PDF default (faraón is
## powerless against an eso).
var faraon_blocks_eso := false

## House rule: horník behaves like a regular card — playable only on a suit
## or rank match (and only then changes the suit). OFF = PDF default (horník
## lands on anything that isn't an unresolved eso/sedma).
var hornik_strict := false

## House rule: ace stops are dealt around the table INCLUDING the player who
## laid them (2 aces head-to-head: opponent stands, you stand, opponent
## plays). OFF = PDF default (the chain owner gets a free continuation once
## every stopped player passes).
var eso_round_robin := false

## House rule: consecutive spálená multiplies — the 2nd four-of-a-kind in a
## row grants two extra moves, the 3rd three, etc. OFF = PDF default (every
## spálená grants exactly one extra move).
var spalena_multiply := false

const RULE_KEYS := ["faraon_blocks_eso", "hornik_strict", "eso_round_robin", "spalena_multiply"]


static func classic() -> RulesVariant:
	return RulesVariant.new()


static func olympic(hand_size: int = 5) -> RulesVariant:
	var v := RulesVariant.new()
	v.kind = Kind.OLYMPIC
	v.initial_hand_size = hand_size
	return v


func to_dict() -> Dictionary:
	var d := {"kind": kind, "initial_hand_size": initial_hand_size}
	for k in RULE_KEYS:
		d[k] = get(k)
	return d


static func from_dict(d: Dictionary) -> RulesVariant:
	var v := RulesVariant.new()
	v.kind = d.get("kind", Kind.CLASSIC) as Kind
	v.initial_hand_size = d.get("initial_hand_size", 5)
	for k in RULE_KEYS:
		v.set(k, d.get(k, false))
	return v
