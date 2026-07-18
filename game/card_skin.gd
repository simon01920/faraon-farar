class_name CardSkin
extends RefCounted
## One visual card deck ("skin"): maps card ids to texture paths. Pure data +
## lookup — no game logic. New decks are added as registry entries only; the
## rest of the game asks the active skin for textures and never hardcodes
## paths. Progression rewards and purchases plug in here later by unlocking
## additional registry entries.

var id: String
## Localization key of the player-facing deck name (shown in the skin picker).
var name_key: String
## Hidden skins never appear in the player-facing picker; they stay reachable
## in code and via the dev feature flag (GameSettings.dev_skins_enabled).
var hidden := false
var _base_dir: String
## Layout of files under _base_dir:
##  "suit_dirs" — <base>/<suit_dir>/<rank_file>.png (the dev_preview layout)
##  "flat_en"   — <base>/<suit>-<rank>.png, English names (cards-large sets)
var _layout: String

const _SUIT_DIRS := ["zalud", "cerven", "zelen", "gula"]
const _RANK_FILES := ["VII", "VIII", "IX", "X", "dolnik", "hornik", "krali", "stopky"]
const _SUITS_EN := ["acorn", "heart", "leaf", "bell"]
const _RANKS_EN := ["seven", "eight", "nine", "ten", "unter", "ober", "king", "ace"]


func _init(p_id: String, p_name_key: String, base_dir: String,
		layout: String, p_hidden := false) -> void:
	id = p_id
	name_key = p_name_key
	_base_dir = base_dir
	_layout = layout
	hidden = p_hidden


## Texture path for a card id like "7C"; "" (or unknown layout) = card back.
func texture_path(card_id: String) -> String:
	if card_id == "":
		return back_path()
	if FaraonCard.is_reverse(card_id):
		# D7: Tanečnica má jeden spoločný asset naprieč skinmi.
		return "res://assets/reverse_specialcard.png"
	match _layout:
		"suit_dirs":
			return "%s/%s/%s.png" % [_base_dir,
					_SUIT_DIRS[FaraonCard.suit_of(card_id)],
					_RANK_FILES[FaraonCard.rank_of(card_id)]]
		"flat_en":
			return "%s/%s-%s.png" % [_base_dir,
					_SUITS_EN[FaraonCard.suit_of(card_id)],
					_RANKS_EN[FaraonCard.rank_of(card_id)]]
	return back_path()


func back_path() -> String:
	return _base_dir + "/back.png"


# --- registry ---------------------------------------------------------------

## All known skins. Order = display order in the picker; the first entry is
## the fallback/default ("Mariáš dvojhlavý").
static func all() -> Array[CardSkin]:
	var skins: Array[CardSkin] = [
		CardSkin.new("marias_dvojhlavy", "SKIN_MARIAS", "res://assets/cards_marias",
				"flat_en"),
		CardSkin.new("dev_preview", "SKIN_DEV_PREVIEW", "res://assets/cards",
				"suit_dirs", true),
	]
	return skins


## Skins offered to the player in UI. Hidden skins show up only with the dev
## feature flag ([dev] show_dev_skins in settings.cfg).
static func selectable() -> Array[CardSkin]:
	var out: Array[CardSkin] = []
	for s in all():
		if not s.hidden or GameSettings.dev_skins_enabled():
			out.append(s)
	return out


static func by_id(skin_id: String) -> CardSkin:
	for s in all():
		if s.id == skin_id:
			return s
	return all()[0]


## The skin every card texture is resolved through (player's persisted pick).
static func active() -> CardSkin:
	return by_id(GameSettings.get_card_skin())
