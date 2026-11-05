class_name NetProtocol
extends RefCounted
## Shared client+server networking contract: protocol version, room-code
## format and defensive shape-validation of everything a client can send.
## The server validates SHAPE here (types/lengths) before any input reaches
## the rules engine — a malformed message must never crash the process, and
## game legality stays the engine's job.

const PROTOCOL_VERSION := 1
## Internal WebSocket port on the VPS; Nginx terminates wss:// on 443 and
## proxies here (loopback only, never exposed publicly).
const DEFAULT_PORT := 9000
const DEV_URL := "ws://127.0.0.1:9000"
## Set the real domain before the first production client build.
const PROD_URL := "wss://faraon.example.com/ws"

const ROOM_CODE_LEN := 5
## No 0/O or 1/I — codes are read aloud between friends.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAX_PLAYERS := 5
const MAX_NAME_LEN := 16
## How long a dropped player's seat (hand, order) survives for reconnect.
const RECONNECT_GRACE_SEC := 120.0

## Allowed host-chosen value rules — mirrors the options the UI offers
## (GameSettings.RULE_VALUES). Anything else from the wire is dropped and the
## engine default applies; the hand size is clamped into its slider range.
const HAND_SIZE_MIN := 4
const HAND_SIZE_MAX := 7
const PENALTY_STEPS := [2, 3, 4]
const PENALTY_CAPS := [0, 8, 12]
const RETURN_SCOPES := ["round", "anyone"]
const FINISH_RULES := ["none", "no_seven", "hornik_only"]
## 32-card mariáš deck; the optional Tanečnica (reverse_card) adds one.
const BASE_DECK_SIZE := 32


static func make_code(rng: RandomNumberGenerator) -> String:
	var code := ""
	for _i in ROOM_CODE_LEN:
		code += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return code


static func valid_code(code) -> bool:
	if not (code is String) or code.length() != ROOM_CODE_LEN:
		return false
	for ch in code:
		if not CODE_ALPHABET.contains(ch):
			return false
	return true


static func clean_name(p_name) -> String:
	if not (p_name is String):
		return ""
	return p_name.strip_edges().left(MAX_NAME_LEN)


## Shape check for a proposed action dictionary (PLAY_CARDS/DRAW/PASS).
static func valid_action(action) -> bool:
	if not (action is Dictionary):
		return false
	var kind = action.get("action", "")
	if not (kind is String):
		return false
	match kind:
		FaraonActions.DRAW, FaraonActions.PASS:
			return true
		FaraonActions.PLAY_CARDS:
			var cards = action.get("cards")
			if not (cards is Array) or cards.is_empty() or cards.size() > 8:
				return false
			for c in cards:
				if not (c is String) or not FaraonCard.is_valid_id(c):
					return false
			var declared = action.get("declared_suit", -1)
			if not ((declared is int or declared is float) \
					and int(declared) >= -1 and int(declared) <= 3):
				return false
			var declared_rank = action.get("declared_rank", -1)
			return (declared_rank is int or declared_rank is float) \
					and int(declared_rank) >= -1 and int(declared_rank) <= 7
	return false


## Shape/range-checked copy of a host-supplied RulesVariant dictionary: only
## known keys with the right type survive, value rules are limited to what
## the UI can produce, and runtime-only fields (kind, end_on_first_finish —
## online play is always a single normal round) never come from the wire.
## The result is safe to hand to RulesVariant.from_dict().
static func sanitize_variant(d) -> Dictionary:
	var clean := {}
	if not (d is Dictionary):
		return clean
	for k in RulesVariant.RULE_KEYS:
		if k == "end_on_first_finish":
			continue
		var b = d.get(k)
		if b is bool:
			clean[k] = b
	var hand = d.get("initial_hand_size")
	if hand is int or hand is float:
		clean["initial_hand_size"] = clampi(int(hand), HAND_SIZE_MIN, HAND_SIZE_MAX)
	var step = d.get("seven_penalty_step")
	if (step is int or step is float) and PENALTY_STEPS.has(int(step)):
		clean["seven_penalty_step"] = int(step)
	var cap = d.get("seven_penalty_cap")
	if (cap is int or cap is float) and PENALTY_CAPS.has(int(cap)):
		clean["seven_penalty_cap"] = int(cap)
	var scope = d.get("red7_return_scope")
	if scope is String and RETURN_SCOPES.has(scope):
		clean["red7_return_scope"] = scope
	var finish = d.get("finish_rule")
	if finish is String and FINISH_RULES.has(finish):
		clean["finish_rule"] = finish
	return clean


## Can `players` hands of `hand_size` be dealt and still leave the start card
## plus at least one card in the draw pile (the start-card rules flip its
## bottom card)?
static func deck_fits(players: int, hand_size: int, with_reverse_card := false) -> bool:
	var deck := BASE_DECK_SIZE + (1 if with_reverse_card else 0)
	return players * hand_size + 2 <= deck
