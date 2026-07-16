# Štartové animácie — návrhy variantov (čaká na Simonovo schválenie)

Podľa sekcie 3 zberného promptu. Bug z 3.2 (staré karty z predošlej hry ostali
na kôpke počas rozdávania novej) je **opravený nezávisle** — kôpka sa čistí na
začiatku rozdania. Vizuálny štýl oboch animácií čaká na výber variantu.

## 3.2 Vyloženie štartovacej karty (dnes: rovnaký let ako pri rozdávaní)

Aktuálna sekvencia: karta letí oblúčikom z vrchu balíčka na kôpku a v letu sa
otočí lícom (0.36 s) — po novom už vždy na čistú, prázdnu kôpku.

| Variant | Sekvencia | Trvanie | Pocit |
|---|---|---|---|
| **A — let ako pri rozdávaní** (aktuálny štýl) | oblúkový let z balíčka na kôpku, flip v letu | ~0.4 s | rýchle, jednotný vizuálny jazyk s rozdávaním |
| **B — slávnostné odhalenie** | karta vyjde z balíčka do stredu stola, zväčší sa ~1.4×, drží sa 0.6 s s jemnou žiarou (jasné "toto je štartovacia karta"), potom si sadne na kôpku | ~1.1 s | ceremónia, nový hráč pochopí význam karty |
| **C — flip na mieste** | karta sa presunie rubom hore z balíčka na kôpku a AŽ TAM sa otočí lícom (ako pri pasiansovej kôpke) | ~0.7 s | najfyzickejšie, "stolová" logika |

## 3.1 Otočenie balíčka pri štartovom horníkovi/ese/sedme

Aktuálna sekvencia (ktorá sa nepáči): blok 3 kariet na mieste balíčka sa
pseudo-3D stlačí (scale.x → 0), vymení líce na spodnú kartu, roztiahne späť;
drží 0.85 s; rovnakým stlačením sa vráti rubom hore (~1.5 s spolu). Efekt je
rovnaký ako flip jednej karty, len na bloku — nepôsobí ako fyzické prevrátenie
celého balíčka.

| Variant | Sekvencia | Trvanie | Pocit |
|---|---|---|---|
| **A — prevrátenie cez hranu** | balíček sa zdvihne, preklopí sa cez dlhú hranu (skew + rastúci tieň + "thud" zvuk pri dopade), spodná karta leží lícom hore na stole, drží, prevráti sa späť | ~2 s | najrealistickejšie, pomalé a čitateľné |
| **B — rýchly flip + vysunutie karty** | rýchly flip bloku (0.25 s), spodná karta sa VYSUNIE z bloku do stredu, zväčší ~1.5× so žiarou, vráti sa, blok sa flipne späť | ~1.6 s | dôraz na určujúcu kartu, nie na mechaniku otočenia |
| **C — "peek" pod balíček** | celý balíček sa zdvihne k hráčovi (zväčšenie + hlbší tieň), mierne naklopí (~6°), ukáže spodok s kartou v perspektívnom skose, položí sa späť | ~1.3 s | gesto "nadvihnem balíček a pozriem sa pod neho" — najbližšie k reálnemu stolu |

Pri oboch: nadväznosť 3.2 → 3.1 (keď štartovka je horník/eso/sedma, druhá
animácia začne z pokojového stavu prvej, žiadny strih); zvuky flip/thud už
existujú v SFX sade; fast-forward škáluje trvania ako všade inde.

**Napíš mi kombináciu (napr. „3.2 B + 3.1 C") a implementujem finálne verzie.**
