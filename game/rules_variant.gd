class_name RulesVariant
extends RefCounted
## Konfigurácia domácich pravidiel. Faraón sa šíril ústne a má množstvo
## regionálnych verzií — predvolený set je najrozšírenejšia/najférovejšia
## dohľadateľná verzia, všetko ostatné sú opt-in prepínače. V multiplayeri
## sú autoritatívne prepínače zakladateľa miestnosti.
##
## D7 (Tanečnica/Otočka), D11 (spodok-menič), D15 (Hospodské prší) a D16
## (Neuner) čakajú na Simonove rozhodnutia o zaradení kariet do balíka —
## pozri architecture/house_rules_open_questions.md.

enum Kind { CLASSIC, OLYMPIC }

var kind: Kind = Kind.CLASSIC

## D2: počet kariet rozdaných na začiatku (slider 4–7, default 5). Olympijské
## režimy ho znižujú per hráč cez meta-vrstvu (FaraonMatch).
var initial_hand_size: int = 5

## Faraón blokuje aj esá — zastavený hráč ním môže zrušiť celú reťaz.
var faraon_blocks_eso := false

## Horník sa správa ako bežná karta (len na farbu/znak; až potom mení farbu).
var hornik_strict := false

## Násobenie spálenej: druhá štvorica v rade dáva dva extra ťahy atď.
var spalena_multiply := false

## D1: červená sedma sa pri návrate dá položiť aj na AKTÍVNU stopku (eso) —
## reakcia spotrebuje hráčov stop. OFF = na aktívne eso sa odpovedá len esom.
var red7_on_active_eso := false

## D3 / D9-off: eso sa nedá prebiť ďalším esom — zastavený hráč len stojí.
var eso_no_counter := false

## D4: sedma vytiahnutá počas trestného ťahania sa dá ihneď vyložiť (trest
## kroku ide na ďalšieho hráča, zvyšok vlastného trestu padá). Default OFF.
var seven_interrupt := false

## D5: faraón vytiahnutý počas trestného ťahania sa dá ihneď vyložiť a ruší
## zvyšok trestu. Default ON — správanie odsúhlasené v pred-multiplayer
## prompte; nové zadanie navrhuje OFF, čaká na Simonovo potvrdenie.
var faraon_interrupt := true

## D6: veľkosť trestu za jednu sedmu (2/3/4, default 3 = doterajšia stupnica).
var seven_penalty_step := 3

## D8: rozsah vracania červenou sedmou — "anyone" (hocikto, kto vypadol od
## začiatku hry; default podľa zadania) alebo "round" (len z aktuálneho kola).
var red7_return_scope := "anyone"

## D10: Purista režim — čistá mau-mau: bez návratu červenou sedmou, bez
## spálenej, bez eso-reťaze (eso = jednoduchý skip) a faraón je obyčajný
## dolník. Nastavením sa efektívne vypnú závislé pravidlá.
var purista := false

## D12: zelený kráľ = ďalší hráč ťahá 4 karty; vnorená prebíjacia varianta
## (KE ↔ 7E sa prebíjajú navzájom).
var green_king := false
var green_king_counter := false

## D13: červená desiatka = ďalší hráč ťahá 1 kartu; dá sa položiť ako
## obrana na červenú sedmu (potom už bez ďalšej obrany); na desiatku sa dá
## položiť červená sedma.
var red_ten := false

## D14: obmedzenie poslednej karty: "none" / "no_seven" / "hornik_only".
var finish_rule := "none"

## B2 (runtime, nie používateľské pravidlo): sub-kolo olympijského zápasu
## končí hneď prvým dohratým hráčom — zvyšok rieši rozstrel v meta-vrstve.
var end_on_first_finish := false

const RULE_KEYS := [
	"faraon_blocks_eso", "hornik_strict", "spalena_multiply",
	"red7_on_active_eso", "eso_no_counter", "seven_interrupt",
	"faraon_interrupt", "purista", "green_king", "green_king_counter",
	"red_ten", "end_on_first_finish",
]
const VALUE_KEYS := ["initial_hand_size", "seven_penalty_step",
	"red7_return_scope", "finish_rule"]

## Defaulty pre UI (štítok „predvolené" + reset) — jediný zdroj pravdy.
const DEFAULTS := {
	"faraon_blocks_eso": false, "hornik_strict": false,
	"spalena_multiply": false, "red7_on_active_eso": false,
	"eso_no_counter": false, "seven_interrupt": false,
	"faraon_interrupt": true, "purista": false, "green_king": false,
	"green_king_counter": false, "red_ten": false,
	"initial_hand_size": 5, "seven_penalty_step": 3,
	"red7_return_scope": "anyone", "finish_rule": "none",
	"end_on_first_finish": false,
}


static func classic() -> RulesVariant:
	return RulesVariant.new()


static func olympic(hand_size: int = 5) -> RulesVariant:
	var v := RulesVariant.new()
	v.kind = Kind.OLYMPIC
	v.initial_hand_size = hand_size
	return v


## D10: Purista potláča špeciálne schopnosti — engine sa pýta cez tieto
## efektívne gettery namiesto priameho čítania polí.
func allows_red7_return() -> bool:
	return not purista


func allows_spalena() -> bool:
	return not purista


func counter_allowed() -> bool:
	return not (eso_no_counter or purista)


func faraon_is_wild() -> bool:
	return not purista


func to_dict() -> Dictionary:
	var d := {"kind": kind}
	for k in RULE_KEYS + VALUE_KEYS:
		d[k] = get(k)
	return d


static func from_dict(d: Dictionary) -> RulesVariant:
	var v := RulesVariant.new()
	v.kind = d.get("kind", Kind.CLASSIC) as Kind
	for k in RULE_KEYS + VALUE_KEYS:
		v.set(k, d.get(k, DEFAULTS.get(k)))
	return v
