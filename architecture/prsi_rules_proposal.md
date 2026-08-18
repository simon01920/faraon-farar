# Herný mód „Prší" — návrh pravidiel na schválenie

> **Stav: ČAKÁ NA SIMONOVO SCHVÁLENIE. Zatiaľ nie je napísaný ani riadok kódu.**
> Zadanie (`faraon_penalty_cards_czech_modes_prompt.md`, sekcia 4) hovorí:
> najprv zoznam pravidiel s vyznačením rozdielov oproti Faraónovi, potom
> potvrdenie, až potom implementácia.

## 1. Odkiaľ sú pravidlá

Overené z viacerých nezávislých českých zdrojov (august 2026):

| Zdroj | Čo potvrdzuje |
|---|---|
| hracikarty.cz — návod Prší | 2–5 hráčov, rozdáva sa 5 kariet, sedma = ber 2 (reťazí sa), eso = vynecháš kolo, svršek = ľubovoľná karta + hlásenie farby, víťaz hlási „prší" |
| sdszs.cz — Pravidlá Prší a Prší 48 | rozdávajú sa 4 karty, sedma = 2 (reťaz 2/4), eso sa dá prebiť esom, svršek mení farbu, hlásenie „mám poslední kartu" |
| karetnihry.blogspot.com — Prší pravidla | rozdávajú sa 4 karty, reťaz sediem 2/4/6/8 s **maximom 8**, svršek sa **nesmie** položiť na eso ani na sedmu, červená sedma ako regionálna varianta vracia vypadnutého hráča |
| gameday.cz / odpovedi.cz | spodok ako rozšírenie („měnič" — hlási hodnotu), rovnaká základná mechanika farba/hodnota |

Zdroje sa nezhodujú v dvoch bodoch (4 vs 5 rozdaných kariet; strop reťaze
sediem) — obidva sú nižšie ako otvorené otázky.

## 2. Čo je ROVNAKÉ ako vo Faraóne (bez zmeny enginu)

- 32-kartový mariášový balíček, rovnaké farby (žaludy, červené, zelené, kule).
- Základné kladenie: sedí **farba alebo hodnota** vrchnej karty.
- Kto nemá čo položiť, **líže** kartu z talónu a ťah končí.
- **Eso = stopka**: nasledujúci hráč vynechá ťah, ak neprebije vlastným esom
  (t. j. presne náš „pomalý" režim D9 — a je to v Prší štandard).
- **Sedma = trestné karty** s reťazením; kto sa neubráni, berie celý balík.
- Talón sa po vyčerpaní premieša z odhadzovacej kôpky.
- Víťaz = kto sa prvý zbaví kariet; hra pokračuje o ďalšie miesta.

## 3. Čo je INÉ (a čo si to vyžiada v kóde)

| # | Pravidlo | Faraón (dnes) | Prší (návrh) | Zásah do kódu |
|---|---|---|---|---|
| P1 | Trest za sedmu | 3 karty | **2 karty** | žiadny — `seven_penalty_step` (D6) už existuje |
| P2 | Strop reťaze sediem | bez stropu | **max 8** kariet | nový `seven_penalty_cap` (0 = bez stropu) |
| P3 | Faraón (zelený dolník ako žolík) | áno, žolík + ruší trest | **neexistuje**, zelený spodok je bežná karta | nový `faraon_wild` (dnes to vypína len Purista naraz so všetkým ostatným) |
| P4 | Spálená (4 rovnaké = ťah navyše) | áno | **nie je súčasťou Prší** | nový `spalena_enabled` (dnes tiež len cez Puristu) |
| P5 | Menič farby | horník (Ober) padne na čokoľvek | **svršek** — padne na čokoľvek **okrem esa a sedmy** | nový `changer_blocked_on_specials` |
| P6 | Viac kariet rovnakej hodnoty naraz | áno (a spálená na tom stojí) | v štandardnom Prší **nie** | nový `multi_card_play` — **otázka Q3** |
| P7 | Spodok hlási hodnotu | domáce pravidlo D11 (default vyp.) | v Prší tiež len **rozšírenie** → default vyp., ale v UI zapnuteľné | žiadny — D11 už existuje |
| P8 | Rozdané karty | 5 | **4** (2 z 3 zdrojov) | žiadny — `initial_hand_size` (D2) |
| P9 | Návrat červenou sedmou | áno (default: len z aktuálneho kola) | v Prší je to **regionálna varianta**, nie základ | rozhodnutie: default ZAP alebo VYP — **otázka Q2** |
| P10 | Hlásenie poslednej karty / „prší" | nemáme | „mám poslední kartu", víťaz hlási „prší" | kozmetika (toast + hláška), bez dopadu na pravidlá |
| P11 | Bodovanie zvyšku v ruke (spodok 2, svršek 3, kráľ 4, eso 11) | máme vlastnú progresiu (body/levely) | klasické Prší počíta body za karty v ruke | **neodporúčam** miešať s našou progresiou; nechal by som našu |

## 4. Ako to zapadne do architektúry (bez paralelného systému)

Presne podľa zadania — **žiadny druhý rules engine**. `FaraonRules` ostáva
jediný; „Prší" je len ďalší **preset hodnôt `RulesVariant`**:

```gdscript
static func prsi() -> RulesVariant:
    var v := RulesVariant.new()
    v.initial_hand_size = 4          # P8
    v.seven_penalty_step = 2         # P1
    v.seven_penalty_cap = 8          # P2  (nové pole)
    v.faraon_wild = false            # P3  (nové pole)
    v.spalena_enabled = false        # P4  (nové pole)
    v.changer_blocked_on_specials = true  # P5 (nové pole)
    v.multi_card_play = false        # P6  (nové pole, ak schválené)
    return v
```

- Nové polia idú do `RULE_KEYS`/`VALUE_KEYS`/`DEFAULTS` — teda sa automaticky
  objavia aj v obrazovke domácich pravidiel a v multiplayerovej výmene
  pravidiel (zakladateľ miestnosti ich posiela ostatným).
- Preset **nie je zámok**: hráč si aj v Prší môže domáce pravidlá doladiť,
  rovnako ako dnes vo Faraóne. Preset len nastaví východiskové hodnoty.
- Olympijské režimy (`Kind.OLYMPIC`) ostávajú **kolmé** na preset — dá sa
  hrať aj „olympijské Prší", nič sa nevylučuje.
- Purista (D10) ostáva ako je; interne začne používať tie isté nové vypínače
  (`faraon_wild`, `spalena_enabled`) namiesto vlastného vetvenia — jeden
  zdroj pravdy, menej kódu.

### Auto-výber podľa jazyka zariadenia

- Pri prvom spustení: `OS.get_locale()` → `cs*` = preset **Prší**, čokoľvek
  iné = **Faraón**. Uloží sa do `settings.cfg` (`app/rule_preset`), takže sa
  rozhoduje raz, nie pri každom štarte.
- Jazyk UI a herný mód sú **oddelené voľby** — český hráč si môže nechať
  češtinu a prepnúť na Faraóna aj naopak. (Detekcia jazyka UI už funguje —
  dodaná v sekcii 3 tohto zadania.)
- V Nastaveniach pribudne samostatná položka „Herný mód: Faraón / Prší"
  nad domácimi pravidlami, s vysvetlením, čo preset mení.

### Dopad na botov (`BotStrategy`)

Prehodnotené, žiadny redizajn netreba — heuristiky sú viazané na *hodnoty*
kariet (sedma/eso/dolník), nie na konkrétne faraónske mechaniky:

1. Obrana faraónom — už dnes strážená cez `faraon_is_wild()` (opravené v
   sekcii 1 tohto zadania), v Prší jednoducho odpadne.
2. Záložný ťah „faraón na čokoľvek" v `_choose_normal_play` — treba doplniť
   rovnakú stráž, inak by bot v Prší navrhoval nelegálny ťah.
3. `_ordered_group` — pri `multi_card_play = false` vráti vždy jednu kartu.
4. Card-counting (`CardMemory`) je čisto po hodnotách → funguje bez zmeny;
   v Prší len prestane mať zmysel počítať faraóna (jedna karta menej).

## 5. Otázky, na ktoré potrebujem odpoveď pred implementáciou

**Q1 — Koľko kariet sa v Prší rozdáva?** Zdroje sa líšia: 4 (sdszs.cz,
karetnihry) vs 5 (hracikarty.cz). *Odporúčam 4* (väčšina zdrojov + odlíši to
mód od Faraóna). Alternatíva: nechať 5, nech sú módy porovnateľné.

**Q2 — Má mať Prší návrat červenou sedmou?** V Prší je to regionálna
varianta, nie základ. *Odporúčam default VYPNUTÝ* (Prší tak ostane „čistejšie"
a odlíšené od Faraóna), s možnosťou zapnúť v domácich pravidlách. Ak by si
ho chcel zapnutý, platí preň rovnaký default rozsahu „len aktuálne kolo".

**Q3 — Má sa v Prší dať položiť viac kariet rovnakej hodnoty naraz?**
Štandardné Prší to nemá; naša hra na tom stojí (spálená, poradie kladenia,
číslované badge). *Odporúčam vypnúť* (verné pravidlám) — ale je to najväčší
zásah do pocitu z hry, tak to nechávam na teba.

**Q4 — Terminológia v českom preklade.** Momentálne v češtine používam
mariášové názvy: **spodek / svršek / kule / zelené / červené / žaludy**,
a pre mód Faraón som ponechal slovo **faraon** (zelený spodek). Sedí ti to,
alebo chceš pre Prší niečo iné (napr. len „měnič" namiesto „svršek")?

**Q5 — Hlásenie „prší" / „poslední karta".** Chceš to ako kozmetickú hlášku
(toast + zvuk, keď hráčovi ostane jedna karta), alebo to nechať tak?

---

Po tvojom potvrdení (stačí odpovedať Q1–Q5 a „ideš") je to podľa mňa
**jeden pracovný blok**: 5 nových prepínačov v `RulesVariant`, preset,
voľba v nastaveniach + auto-detekcia, 3 stráže v botoch, testy na každý
nový prepínač a doplnenie tutoriálu o českú verziu.
