# Domáce pravidlá — otvorené otázky pre Simona (fix-polish prompt, sekcia D)

Implementované a otestované: A1, A2, B1–B3, C1–C3, D1–D6, D8–D10, D12–D14.
Nasledujúce body majú v zadaní tvoje vlastné „over so mnou" poznámky alebo
menia štruktúru balíka — čakajú na rozhodnutie, kód sa ich zatiaľ nedotýka:

## D7 — Tanečnica/Otočka (reverz karta)
Asset `assets/reverse_specialcard.png` je v repe. Otázka zo zadania: **ako sa
karta zaraďuje do balíka?**
- (a) 33. karta navyše — mení matematiku balíka (32 kariet je zapečené v
  deckoch, testoch aj v pravidlách spálenej/rozdávania), potrebuje vlastné
  ID mimo `rank+suit` schémy;
- (b) nahradí existujúcu kartu (ktorú?);
- (c) 4 kusy (jedna per farba) namiesto niektorých hodnôt.
Odporúčam (a) s novým špeciálnym ID a explicitným ošetrením v bot logike —
ale je to najväčší zásah; potvrď smer a implementujem vrátane smeru hry
(engine dostane `direction` do `next_active_index`).

## D11 — Spodok ako menič (výmenník)
32-kartový balíček spodky (dolníky) UŽ používa — „rozšírenie o spodky"
znamená buď novú funkciu existujúcich dolníkov (konflikt s faraónom =
zelený dolník!), alebo rozšírenie balíka. Ohlásenie HODNOTY (nie farby) je
nová mechanika (announce state + „ťahaj kým nepoložíš"). Potrebujem:
ktorá karta je „spodok" v našom 32-kartovom balíku a či D11 vypína
faraóna (zelený dolník by mal dve role).

## D15 — Hospodské prší
Stavia na D11 + D12 a mení funkciu desiatky (obracia smer) → kolízia s D13
(červená desiatka = ťahaj 1). Zadanie samo odporúča vzájomné vylúčenie
D13/D15 — súhlasím a navrhujem: D15 ako samostatný submód (segment
„Rozšírené módy": Žiadny / Hospodské prší / Neuner), nie kombinovateľný
toggle. Čaká na D11 rozhodnutie (rovnaká „spodok" otázka) + smer hry (D7
infra).

## D16 — Neuner
Vlastný submód (žolík v balíku!, deviatka ako menič, obmedzenie miešania,
5–6 kariet). Žolík = nová karta/asset + nové pravidlo — návrh: implementovať
až po D7 rozhodnutí (rovnaká „karta navyše" infra) a ako tretiu možnosť
segmentu submódov spolu s D15. Otázka zo zadania: vlastný rozsah rozdania
alebo D2 slider? Navrhujem: D16 fixne 6, ignoruje D2 (menšia UI zložitosť).

## D5 — konflikt so skorším schválením
Pred-multiplayerový prompt (sekcia 4) faraón-interrupt výslovne schválil ako
potvrdené pravidlo; nové zadanie ho navrhuje ako toggle s defaultom OFF
(„potvrdiť"). Implementované ako toggle s **defaultom ON** (zachováva skôr
schválené správanie) — ak má byť OFF, je to zmena jednej hodnoty v
`RulesVariant.DEFAULTS`.

## D9 — poznámka k „časovému oknu"
V ťahovej hre je reakčné okno prirodzene ťah zastaveného hráča (môže prebiť
alebo stáť) — toggle D9 (default ON) toto zachováva; vypnutie = eso má
okamžitý efekt (stopky sa vyhodnotia automaticky, bez šance prebiť), čo je
funkčne to isté ako D3. Nastaviteľná dĺžka okna (1–2 s) by dávala zmysel až
v realtime multiplayer režime — zatiaľ neimplementované, povedz, ak ju
chceš aj v ťahovom flow (auto-stoj po X sekundách).

## D4/D5 — detail „koľko trestu ide ďalej"
Zadanie D4: „pošle trest (napr. +3) ďalšiemu". Implementované: zvyšok
VLASTNÉHO trestu padá a ďalší hráč čelí kroku novej sedmy (D6 krok, default
3) — reťaz sa nepreklápa celá. Ak má ísť ďalej `zvyšok + krok`, je to
jednoriadková zmena.
