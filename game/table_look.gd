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
		TableLook.new("dark_wood", "TABLE_DARK_WOOD",
				"res://assets/backgrounds/dark_wood.jpg"),
		TableLook.new("green_cloth", "TABLE_GREEN_CLOTH",
				"res://assets/backgrounds/green_cloth.jpg"),
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
