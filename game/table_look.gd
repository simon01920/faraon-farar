class_name TableLook
extends RefCounted
## One table appearance: either the procedural felt (default) or a photo
## texture. Pure data + registry, mirroring CardSkin — the table scene asks
## the active look for its background and never hardcodes paths. Unlockable
## looks are level-gated through Progression/Rewards (or granted directly by
## a future purchase), never a gameplay advantage.

var id: String
var name_key: String
## "" = procedural felt; otherwise the background texture path.
var texture_path: String


func _init(p_id: String, p_name_key: String, p_texture_path := "") -> void:
	id = p_id
	name_key = p_name_key
	texture_path = p_texture_path


func is_unlocked() -> bool:
	return Progression.is_unlocked(id)


static func all() -> Array[TableLook]:
	var looks: Array[TableLook] = [
		TableLook.new("felt_green", "TABLE_FELT"),
		TableLook.new("wood_table", "TABLE_WOOD",
				"res://assets/backgrounds/wood_table.jpg"),
		TableLook.new("rustic_wood", "TABLE_RUSTIC_WOOD",
				"res://assets/backgrounds/rustic_wood.jpg"),
		TableLook.new("dark_wood", "TABLE_DARK_WOOD",
				"res://assets/backgrounds/dark_wood.jpg"),
		TableLook.new("felt_bright", "TABLE_FELT_BRIGHT",
				"res://assets/backgrounds/felt_bright.jpg"),
		TableLook.new("poker_green", "TABLE_POKER_GREEN",
				"res://assets/backgrounds/poker_green.jpg"),
		TableLook.new("felt_blue", "TABLE_FELT_BLUE",
				"res://assets/backgrounds/felt_blue.jpg"),
		TableLook.new("oak_light", "TABLE_OAK_LIGHT",
				"res://assets/backgrounds/oak_light.jpg"),
		TableLook.new("maple_light", "TABLE_MAPLE_LIGHT",
				"res://assets/backgrounds/maple_light.jpg"),
		TableLook.new("walnut_warm", "TABLE_WALNUT_WARM",
				"res://assets/backgrounds/walnut_warm.jpg"),
		TableLook.new("planks_golden", "TABLE_PLANKS_GOLDEN",
				"res://assets/backgrounds/planks_golden.jpg"),
		TableLook.new("teak_sun", "TABLE_TEAK_SUN",
				"res://assets/backgrounds/teak_sun.jpg"),
		TableLook.new("wood_scuffed", "TABLE_WOOD_SCUFFED",
				"res://assets/backgrounds/wood_scuffed.jpg"),
		TableLook.new("planks_dark", "TABLE_PLANKS_DARK",
				"res://assets/backgrounds/planks_dark.jpg"),
	]
	return looks


static func by_id(look_id: String) -> TableLook:
	for l in all():
		if l.id == look_id:
			return l
	return all()[0]


static func active() -> TableLook:
	var look := by_id(GameSettings.get_table_look())
	# A lock that appeared after the pick (e.g. fresh device) falls back to
	# the free default instead of showing content the player hasn't earned.
	return look if look.is_unlocked() else all()[0]
