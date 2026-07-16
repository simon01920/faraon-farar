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
			return (declared is int or declared is float) \
					and int(declared) >= -1 and int(declared) <= 3
	return false
