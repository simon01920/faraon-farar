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

## D8: rozsah vracania červenou sedmou — "round" (DEFAULT: len hráč, ktorý
## vypadol v aktuálnom kole, t. j. od jeho vypadnutia ešte neprebehol celý
## obeh stola) alebo "anyone" (hocikto, kto vypadol od začiatku hry).
## Default platí pre oba herné módy; presné meranie kola: GameState.handovers.
var red7_return_scope := "round"

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

## D7a: Tanečnica/Otočka — 33. karta navyše, ktorá otáča smer hry.
var reverse_card := false

## D11: spodky (dolníky okrem zeleného = faraóna) sú meničmi HODNOTY —
## pri vyložení hráč ohlási znak; ostatní ťahajú, kým ho niekto nepoloží
## alebo neprebije ďalším spodkom.
var unter_announcer := false

## D15: Hospodské prší — submód: zapína D11, zeleného kráľa BEZ prebíjacej
## varianty a všetky desiatky obracajú smer hry. Vylučuje sa s D13.
var pub_mode := false

## --- P: rozdiely českého Prší (preset „prsi") --------------------------
## Tieto prepínače sú zapnuté/vypnuté presetom, ale ostávajú v domácich
## pravidlách — hráč si ich vie doladiť v oboch módoch.

## P3: je zelený dolník žolíkom (faraónom)? V Prší nie — je to bežný spodok.
var faraon_wild := true

## P9/Q2: vracia červená sedma vypadnutého hráča? V Prší je to len
## regionálna varianta, takže preset „prsi" ju vypína.
var red7_return := true

## P4: spálená (4 rovnaké = ťah navyše). V Prší sa nehrá.
var spalena_enabled := true

## P2: strop nahromadeného trestu za sedmy (0 = bez stropu). Prší: 8.
var seven_penalty_cap := 0

## P5: menič farby (horník/svršek) sa nesmie položiť na eso ani na sedmu.
var changer_blocked_on_specials := false

## P6: smie sa naraz položiť viac kariet rovnakého znaku? V štandardnom
## Prší nie (a tým pádom tam neexistuje ani spálená).
var multi_card_play := true

## B2 (runtime, nie používateľské pravidlo): sub-kolo olympijského zápasu
## končí hneď prvým dohratým hráčom — zvyšok rieši rozstrel v meta-vrstve.
var end_on_first_finish := false

const RULE_KEYS := [
	"faraon_blocks_eso", "hornik_strict", "spalena_multiply",
	"red7_on_active_eso", "eso_no_counter", "seven_interrupt",
	"faraon_interrupt", "purista", "green_king", "green_king_counter",
	"red_ten", "reverse_card", "unter_announcer", "pub_mode",
	"faraon_wild", "spalena_enabled", "changer_blocked_on_specials",
	"multi_card_play", "red7_return",
	"end_on_first_finish",
]
const VALUE_KEYS := ["initial_hand_size", "seven_penalty_step",
	"seven_penalty_cap", "red7_return_scope", "finish_rule"]

## Defaulty pre UI (štítok „predvolené" + reset) — jediný zdroj pravdy pre
## mód Faraón. Mód Prší ich prepisuje cez PRESET_PRSI nižšie.
const DEFAULTS := {
	"faraon_blocks_eso": false, "hornik_strict": false,
	"spalena_multiply": false, "red7_on_active_eso": false,
	"eso_no_counter": false, "seven_interrupt": false,
	"faraon_interrupt": true, "purista": false, "green_king": false,
	"green_king_counter": false, "red_ten": false,
	"initial_hand_size": 5, "seven_penalty_step": 3,
	"seven_penalty_cap": 0, "red7_return_scope": "round",
	"finish_rule": "none", "reverse_card": false, "unter_announcer": false,
	"pub_mode": false, "faraon_wild": true, "spalena_enabled": true,
	"changer_blocked_on_specials": false, "multi_card_play": true,
	"red7_return": true, "end_on_first_finish": false,
}

## Herné módy (presety pravidiel). „faraon" = doterajšia hra, „prsi" =
## české pravidlá overené v architecture/prsi_rules_proposal.md
## (schválené: 4 karty, bez návratu červenou sedmou).
const PRESETS := ["faraon", "prsi"]

const PRESET_PRSI := {
	"initial_hand_size": 4,              # Q1
	"seven_penalty_step": 2,             # P1: sedma = ber 2
	"seven_penalty_cap": 8,              # P2: reťaz 2/4/6/8, ďalej už nie
	"faraon_wild": false,                # P3: zelený spodok je bežná karta
	"spalena_enabled": false,            # P4
	"changer_blocked_on_specials": true, # P5: svršek nejde na eso ani sedmu
	"multi_card_play": false,            # P6
	"red7_return": false,                # Q2
	"faraon_interrupt": false,           # bez faraóna nemá čo prerušovať
}


## Predvolená hodnota pravidla v danom móde — jediný zdroj pre UI badge
## „predvolené", pre reset aj pre build_variant().
static func preset_default(key: String, preset: String = "faraon") -> Variant:
	if preset == "prsi" and PRESET_PRSI.has(key):
		return PRESET_PRSI[key]
	return DEFAULTS.get(key, false)


static func from_preset(preset: String) -> RulesVariant:
	var v := RulesVariant.new()
	for k in RULE_KEYS + VALUE_KEYS:
		v.set(k, preset_default(k, preset))
	return v


static func classic() -> RulesVariant:
	return RulesVariant.new()


static func prsi() -> RulesVariant:
	return from_preset("prsi")


static func olympic(hand_size: int = 5) -> RulesVariant:
	var v := RulesVariant.new()
	v.kind = Kind.OLYMPIC
	v.initial_hand_size = hand_size
	return v


## D10: Purista potláča špeciálne schopnosti — engine sa pýta cez tieto
## efektívne gettery namiesto priameho čítania polí.
func allows_red7_return() -> bool:
	return red7_return and not purista


func allows_spalena() -> bool:
	return spalena_enabled and multi_card_play and not purista


func counter_allowed() -> bool:
	return not (eso_no_counter or purista)


func faraon_is_wild() -> bool:
	return faraon_wild and not purista


## P5: smie menič farby (horník/svršek) padnúť na eso alebo sedmu?
func changer_allowed_on(top: String) -> bool:
	if not changer_blocked_on_specials or top == "":
		return true
	return not (FaraonCard.is_eso(top) or FaraonCard.is_sedma(top))


## P2: strop nahromadeného trestu (0 = bez stropu).
func capped_penalty(total: int) -> int:
	return mini(total, seven_penalty_cap) if seven_penalty_cap > 0 else total


## D11/D15: spodok-menič aktívny (Hospodské prší ho zapína automaticky).
func unter_announcer_active() -> bool:
	return (unter_announcer or pub_mode) and not purista


## D12/D15: zelený kráľ aktívny; v Hospodskom prší vždy, ale bez prebíjania.
func green_king_active() -> bool:
	return (green_king or pub_mode) and not purista


func green_king_counter_active() -> bool:
	return green_king_counter and green_king and not pub_mode and not purista


## D15: všetky desiatky obracajú smer hry.
func tens_reverse_active() -> bool:
	return pub_mode and not purista


## D13 sa vylučuje s D15 (desiatka má v každom inú funkciu).
func red_ten_active() -> bool:
	return red_ten and not pub_mode and not purista


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
	# D2 slider range (4–7). The dict may come from a multiplayer host, so an
	# out-of-range size must never reach the deal.
	v.initial_hand_size = clampi(int(v.initial_hand_size), 4, 7)
	return v


## Je táto konfigurácia (ešte) verná presetu? Používa UI na popis módu.
func matches_preset(preset: String) -> bool:
	for k in RULE_KEYS + VALUE_KEYS:
		if k == "end_on_first_finish":
			continue
		if get(k) != preset_default(k, preset):
			return false
	return true
