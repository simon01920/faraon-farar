class_name FaraonCard
extends RefCounted
## Card identity helpers. Cards travel through the whole game (state, network,
## UI) as compact String ids like "7C" (červená sedma) or "DE" (zelený dolník
## = faraón): first char rank, second char suit. This file is pure logic —
## no scene-tree or networking dependencies.

enum Suit { ZALUD, CERVEN, ZELEN, GULA }
enum Rank { R7, R8, R9, R10, DOLNIK, HORNIK, KRAL, ESO }

const SUIT_CHARS := ["Z", "C", "E", "G"]
const RANK_CHARS := ["7", "8", "9", "X", "D", "H", "K", "A"]

## Localized display names are resolved through tr() at the UI layer;
## these are canonical Slovak names for logs/debugging.
const SUIT_NAMES := ["žaluď", "červeň", "zeleň", "guľa"]
const RANK_NAMES := ["sedma", "osma", "devina", "desina", "dolník", "horník", "kráľ", "eso"]


static func make_id(rank: Rank, suit: Suit) -> String:
	return RANK_CHARS[rank] + SUIT_CHARS[suit]


static func is_valid_id(id: String) -> bool:
	return id.length() == 2 and RANK_CHARS.has(id[0]) and SUIT_CHARS.has(id[1])


static func rank_of(id: String) -> Rank:
	return RANK_CHARS.find(id[0]) as Rank


static func suit_of(id: String) -> Suit:
	return SUIT_CHARS.find(id[1]) as Suit


static func is_faraon(id: String) -> bool:
	return id == "DE" # zelený dolník


static func is_eso(id: String) -> bool:
	return rank_of(id) == Rank.ESO


static func is_sedma(id: String) -> bool:
	return rank_of(id) == Rank.R7


static func is_red_sedma(id: String) -> bool:
	return id == "7C"


static func is_hornik(id: String) -> bool:
	return rank_of(id) == Rank.HORNIK


static func display_name(id: String) -> String:
	return "%s %s" % [SUIT_NAMES[suit_of(id)], RANK_NAMES[rank_of(id)]]


## Path of the processed art asset for this card id.
static func texture_path(id: String) -> String:
	var suit_dirs := ["zalud", "cerven", "zelen", "gula"]
	var rank_files := ["VII", "VIII", "IX", "X", "dolnik", "hornik", "krali", "stopky"]
	return "res://assets/cards/%s/%s.png" % [suit_dirs[suit_of(id)], rank_files[rank_of(id)]]
