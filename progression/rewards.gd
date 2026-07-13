class_name Rewards
extends RefCounted
## Level -> cosmetic reward table. Rewards are pure cosmetic ids resolved by
## the appearance registries (TableLook, CardSkin) — no game logic. The same
## ids can be granted directly by a future res://monetization/ module via
## ProgressionStore.grant(), bypassing the grind without touching this table.


class Reward:
	extends RefCounted
	var level: int
	var kind: String # "table" | "card_skin"
	var id: String
	var name_key: String

	func _init(p_level: int, p_kind: String, p_id: String, p_name_key: String) -> void:
		level = p_level
		kind = p_kind
		id = p_id
		name_key = p_name_key


static func all() -> Array[Reward]:
	var rewards: Array[Reward] = [
		Reward.new(2, "table", "wood_table", "TABLE_WOOD"),
		Reward.new(3, "table", "rustic_wood", "TABLE_RUSTIC_WOOD"),
		Reward.new(4, "table", "dark_wood", "TABLE_DARK_WOOD"),
		# Milestone levels (5, 10, 15...) are reserved for future card skins
		# beyond marias_dvojhlavy; they plug into the CardSkin registry.
	]
	return rewards


## Level required for a cosmetic id; 0 = not level-gated (free).
static func level_required(cosmetic_id: String) -> int:
	for r in all():
		if r.id == cosmetic_id:
			return r.level
	return 0
