# Faraón — mobilná/tablet kartová hra (Godot 4.6) — Claude Code build prompt

## Kontext a cieľ projektu

Staviame modernú, multiplatformovú (iOS + Android, mobil aj tablet) digitálnu verziu slovenskej kartovej hry **Faraón** v **Godot 4.6**. Cieľom je vytvoriť produkt na úrovni komerčných kartových hier (Balatro, Marvel Snap, Hearthstone) čo do vizuálnej kvality a "feel"-u animácií, nie amatérsky vyzerajúci klon. Na iOS aktuálne neexistuje žiadna slovenská verzia tejto hry, na Androide len jedna zastaralá bez multiplayeru — chceme túto medzeru vyplniť kvalitným produktom.

Toto je sólo/indie projekt jedného vývojára. Priorizuj čistú, udržateľnú architektúru pred predčasnou optimalizáciou, ale nekompromituj na vizuálnej kvalite animácií — to je hlavný diferenciátor produktu.

## Dostupné zdroje v root priečinku projektu

- **`karty/`** — obrázky kariet, organizované do podpriečinkov podľa farby: `zalud/`, `cerven/`, `zelen/`, `gula/`. Každý podpriečinok obsahuje súbory ako `VII.jpg`, `hornik.jpg`, `dolnik.jpg`, `eso.jpg` atď. (slovenské maďarské/uhorské karty, 32 listov). Súbor `back.jpg` (rub karty) je priamo v `karty/`.
- **`rules/`** — PDF s kompletnými pravidlami hry Faraón (autor Piri, 2009). Pravidlá zhrnuté nižšie v sekcii Herná logika — over si ich v PDF pri akejkoľvek nejasnosti, nedomýšľaj si edge-case správanie.
- **`inspiration/`** — screenshoty/referencie existujúcich kartových hier vrátane starších (nekopírovať štýl, len pochopiť UX patterny) a modernej UNO implementácie (toto je bližšie k želanému modernému štýlu — použ ako referenčný bod pre úroveň polish-u, nie na doslovné kopírovanie).
- **`architecture/`** — mind-mapy/diagramy s predbežnou architektonickou víziou (shared-deck flow, room/multiplayer flow). Preštuduj pred písaním kódu, drž sa navrhnutých konceptov, ale over si detaily proti tomuto promptu, ktorý je záväznejší a podrobnejší zdroj pravdy.

**Prvý krok pred akýmkoľvek písaním kódu: preskúmaj všetky štyri priečinky (`karty/`, `rules/`, `inspiration/`, `architecture/`) a potvrď pochopenie obsahu predtým, než začneš navrhovať scénovú štruktúru.**

---

## 1. Herná logika — pravidlá Faraóna (autoritatívny zdroj: `rules/*.pdf`)

Implementuj ako **čistý, testovateľný GDScript modul oddelený od UI** (napr. `res://game/faraon_rules.gd` ako autoritatívny state machine, žiadna závislosť na scéne/node stromu pre samotnú logiku pravidiel — musí byť unit-testovateľná bez bežiaceho engine renderu).

### Základné pravidlá
- 32 kariet (7–A v štyroch farbách: žaluď, červené, zelené, guľa), 2–5 hráčov, každému 5 kariet na začiatku.
- Cieľ: zbaviť sa všetkých kariet ako prvý.
- Karta sa pokladá, ak sedí farbou alebo znakom na vrchnú kartu odkladacej kôpky.
- Ak hráč nemôže/nechce položiť, ťahá 1 kartu z balíčka a ťah prechádza na súpera.
- Hráč môže položiť viac kariet naraz, len ak majú **rovnaký znak** (napr. viac es, viac sedmičiek) — toto je jeden atomický ťah.

### Špeciálne karty
- **Zelený dolník ("faraón")** = žolík. Hrá sa na hocičo, mení farbu (hráč deklaruje novú farbu), chráni pred sedmou. Ako štartovacia karta platí automaticky. Nedá sa naň nič ďalšie priložiť v tom istom ťahu okrem toho, čo pravidlá PDF špecifikujú.
- **Eso** = zastavuje ďalšieho hráča v poradí, pokiaľ neprizná tiež eso. Viacero es sa dá reťaziť — implementuj ako **čakajúci stav (pending chain)**, kde sa každý ďalší hráč v poradí môže "pripojiť" vlastným esom skôr, než sa reťaz uzavrie. Toto je časovo/ťahovo citlivé — nedomýšľaj si zjednodušenú verziu, over presné podmienky v PDF (kto smie dokladať, kedy sa reťaz považuje za uzavretú).
- **Sedma** = ďalší hráč berie 3 karty navyše, pokiaľ nemá tiež sedmu (kumulatívne — viac sedmičiek za sebou = 3, 6, 9... kariet) alebo nepoloží faraóna (zeleného dolníka), ktorý sedmu ruší.
- **Červená sedma** = špeciálne vracia vypadnutého (už dohratého) hráča späť do hry; vrátený hráč si berie 3 karty. Tvoj `PlayerState` musí podporovať status `active` / `eliminated`, nie len boolean "hrá".
- **Horník** = mení farbu (hráč deklaruje). Dá sa položiť na čokoľvek, čo momentálne nezabraňuje v ťahu (napr. nie hneď na eso/sedmu skôr, než sa tie uplatnia).
- **"Spálená"** = vyloženie 4 kariet rovnakého znaku naraz = extra ťah pre hráča. Over presné podmienky v PDF.
- **Kamufláž / pajchel** = neplatný/podvodný ťah — ak súper neskontroluje a je to prijaté, platí; inak trest 3 karty z kopy. Toto je skôr "social" pravidlo pre voliteľný honor-system mód — v digitálnej verzii pravdepodobne **netreba implementovať podvádzanie ako feature**, ale spomeň to ako poznámku pri návrhu — over so mnou pred implementáciou, či to chceme ako toggle-ovateľný "voľné pravidlá" mód.

### Herné varianty
Implementuj `rules_variant` ako enum/config, minimálne:
- `classic` (klasický Faraón podľa vyššie)
- `olympic` ("Olympijský faraón" — pri prehre hráč dostane o kartu menej pri ďalšom kole, prehráva kto nemá žiadne karty; obsahuje aj "žobrák" mechaniku keď hráč nemá čím hrať)

Navrhni `rules_variant` tak, aby sa dal v budúcnosti ľahko rozšíriť o ďalšie slovenské kartové hry (nie len Faraón) — toto je súčasť dlhodobého product plánu, architektúra by to mala umožňovať bez veľkého refaktoru, ale **nestavaj to nateraz nad rámec potreby** (YAGNI — len nezamkni sa do niečoho, čo to vyslovene znemožní).

### Validácia ťahov
Server (autoritatívna inštancia hry, pozri sekciu Multiplayer) je jediný zdroj pravdy o platnosti ťahu. Klient nikdy nerozhoduje, či je ťah platný — iba navrhne ťah, server potvrdí alebo zamietne. Toto je kritické pre multiplayer integritu.

Napíš aspoň základné **GUT (Godot Unit Test) testy** pre `faraon_rules.gd` pokrývajúce: základné pokladanie karty, reťazenie es, kumulatívne sedmy, červenú sedmu a návrat hráča, spálenú, horníka a zmenu farby, koniec hry/víťaza.

---

## 2. Vizuálny štýl a UI/UX

### Referencie
Pozri `inspiration/` priečinok — staršie príklady sú tam len na pochopenie UX patternov klasických kartových hier (rozloženie stola, ruka kariet, odkladacia kôpka), **nie na kopírovanie vizuálu**. UNO príklad v tom istom priečinku je bližšie k cieľovej úrovni modernosti a polish-u — použi ho ako referenčný benchmark kvality, nie šablónu na kopírovanie.

Cieľový štýl: moderný, čistý, s výraznou identitou (nie generický "AI-safe" dizajn). Preferuj:
- Výrazná farebná paleta odvodená od kariet samotných (nie generický modrý gradient)
- Jemné, ale hmatateľné animácie pri každej interakcii (žiadna appka nesmie pôsobiť staticky)
- Priestor a dych v layoute — netlačiť UI prvky na seba

### Jazyk
Slovenčina ako primárny jazyk s prepínačom na angličtinu (toggle), podľa konvencie, ktorú Simon používa vo svojich ostatných projektoch. Všetky UI stringy cez lokalizačný systém Godotu (`.po`/`.csv` translation), nie hardcoded stringy v scénach.

### Pseudo-3D karty (kľúčová požiadavka)
Karty sú **ploché 2D obrázky** (z `karty/` priečinka), ale animované s pseudo-3D efektom cez transformácie, nie skutočné 3D modely:
- Otočenie karty (napr. odhalenie spodnej karty balíčka, flip pri rozdávaní): animuj `scale.x` z 1 → 0 → 1 cez `Tween`, v momente `scale.x == 0` vymeň textúru (rub ↔ líce). Pridaj mierny `skew`/perspektívny posun a dynamický tieň (mení sa s "výškou" karty) pre presvedčivý pocit hĺbky.
- Pri pohybe karty po stole (hranie karty, ťahanie z balíčka, swipe do odkladacej kôpky) pridaj jemné rotácie, mierne prehnutie dráhy (nie len lineárny presun), a "squash & stretch" pri dopade — klasické herné animation principles.
- Tieň pod kartou nech reaguje na výšku zdvihu (napr. pri draggovaní karty hráčom nech sa tieň zväčší/rozmaže, karta "stúpa" nad stôl).
- Použi Godot `Tween` (nie `AnimationPlayer` pre tieto dynamické/parametrizované animácie — Tween je vhodnejší na programaticky generované pohyby s premenlivými parametrami; `AnimationPlayer` môžeš použiť pre pevné, opakovane použiteľné sekvencie ako rozdávanie kariet na začiatku hry).
- Cieľ: hráč pri swipe geste (zahodenie karty) má pocit fyzického hodenia karty na stôl s momentum a doznievaním, nie okamžitý teleport.

### Spracovanie obrázkov kariet
Súbory v `karty/` sú `.jpg` a pravdepodobne majú biele/farebné pozadie namiesto priehľadného — to je problém pre vrstvenie kariet (tiene, prekrývanie, rotácia s viditeľným pozadím by vyzerali zle.

**Postup:**
1. Napíš Python skript (mimo Godotu, spustiteľný raz ako asset pipeline krok) používajúci `rembg` (alebo podobnú knižnicu na odstránenie pozadia) na spracovanie všetkých obrázkov v `karty/*/` a `karty/back.jpg`.
2. Výstup ulož ako `.png` s alfa kanálom do nového priečinka (napr. `assets/cards_processed/`), zachovaj rovnakú adresárovú štruktúru (farba/znak).
3. Over vizuálne výsledok na vzorke (napr. 3-4 karty) pred hromadným spracovaním celého balíčka — orezanie pozadia pri kartách s jemnými okrajmi (biele written detaily blízko bieleho pozadia) môže zlyhať, over manuálne.
4. Ak `rembg` nie je k dispozícii/zlyháva na niektorých kartách, zaznamenaj problematické súbory do zoznamu a uprac ma na ne — nepokračuj s poškodenými assetmi ticho.
5. Tieto spracované PNG sú finálne assety použité v Godot projekte (import do `res://assets/cards/`).

---

## 3. Shared deck mód (kľúčová inovatívna featúra)

Zariadenie (tablet/mobil) môže byť pripojené do herného room ako **`deck_device`** rola namiesto (alebo popri) rolí `player`:

- **Čistý `deck_device`** (nikto naň nehrá vlastnú ruku): zobrazuje zväčšené UI s vrchným balíčkom (na ťahanie) a odkladacou kôpkou (viditeľná posledná vyložená karta), presne ako fyzický stôl. Slúži hráčom, ktorí sedia spolu naživo, ale nemajú fyzické karty.
- **`deck_device` + lokálny hráč** (niekto pri tomto zariadení aj hrá): dole zobrazí aj vlastnú ruku kariet, hore zväčšené zdieľané UI balíčka/kôpky.
- Toto je čisto **zobrazovacia rola** — `deck_device` neiniciuje herné ťahy sám za seba (pokiaľ nemá aj lokálneho hráča), iba vizualizuje autoritatívny stav zo servera/hosta.
- Implementuj ako jeden zdieľaný scene/komponent s `has_local_hand: bool` prepínačom medzi módmi, nie ako dve oddelené scény (predíď duplicite UI kódu).
- Pripája sa do tej istej room cez rovnaký room-kód, len s inou rolou zvolenou pri joine (napr. tlačidlo "Pripojiť ako zdieľaný balíček" popri "Hrať s vlastnými kartami").

Detailný flow je v `architecture/` mind-mapách — implementuj podľa nich, priečinok si preštuduj pred písaním kódu tejto časti.

---

## 4. Multiplayer architektúra (Godot native)

**Použi Godot vstavané multiplayer capabilities**: `MultiplayerAPI`, `ENetMultiplayerPeer`, `MultiplayerSpawner`, `MultiplayerSynchronizer`, RPC systém (`@rpc` anotácie). Nepiš vlastný nízkoúrovňový networking protokol.

### Dôležité obmedzenia, ktoré musíš zohľadniť (over si to sám cez websearch/dokumentáciu Godot 4.6, moje info môže byť čiastočne zastarané)
- Godot ENet (UDP) **nezvláda NAT traversal sám od seba** — priame P2P spojenie medzi dvoma mobilmi na rôznych domácich sieťach zvyčajne zlyhá kvôli routerom blokujúcim incoming UDP. Pre skutočné cross-internet hranie (nie len LAN) budeš pravdepodobne potrebovať buď:
  - (a) **Relay server** (dedikovaný headless Godot server na malom VPS, cez ktorý sa všetka komunikácia smeruje — hráči sa nepripájajú priamo k sebe, ale k relay serveru, ktorý zároveň môže byť aj autoritatívny host hry), alebo
  - (b) `WebSocketMultiplayerPeer` (TCP-based, funguje spoľahlivejšie cez internet bez port-forwardingu, vyššia latencia ako ENet, ale pre ťahovú kartovú hru je latencia irelevantná)
- Godot nemá vstavaný lobby/matchmaking systém ani autentifikáciu — room-kód systém, zoznam hráčov v miestnosti, reconnect handling musíš postaviť sám nad multiplayer API.
- **Rozhodni a navrhni mi konkrétne odporúčanie** k tejto téme (relay server na VPS vs. WebSocket peer vs. iné) predtým, než začneš implementovať multiplayer vrstvu — nie som si istý najlepším prístupom pre tento typ ťahovej hry s malými miestnosťami (2-5 hráčov), over aktuálny stav Godot 4.6 dokumentácie a nejaké best practices, priprav mi stručné zhrnutie trade-offov a navrhni default, s ktorým začneš, ale confirmuj so mnou pred veľkou investíciou práce do jedného smeru.

### Room/session model
- Host vytvorí room → vygeneruje sa krátky alfanumerický room-kód (vylúč zameniteľné znaky ako 0/O, 1/I).
- Ostatní hráči zadajú kód a pripoja sa s rolou `player` alebo `deck_device`.
- Server (host alebo relay) drží autoritatívny `GameState`: poradie hráčov, ruky, balíček, odkladaciu kôpku, pending chain (aktívne reťazenie es/sedmičiek), `rules_variant`.
- Reconnect handling: ak hráč vypadne (stratí spojenie), server podrží jeho ruku/pozíciu aspoň 60-120 sekúnd pred tým, než ho considers ako definitívne odpojeného; pri návrate pošli full state snapshot na resync.
- Ak vypadne host, over a navrhni migráciu hostovania alebo presun na relay-based model, kde toto nie je problém (relay server je vždy dostupný na rozdiel od hráčovho telefónu).

### Dátový model ťahu (network message)
Ťahy posielaj ako atomické štruktúry (nie kartu po karte), napr.:
```gdscript
{
  "action": "PLAY_CARDS", # alebo DRAW, DECLARE_SUIT, PASS
  "cards": ["7H", "7S"],   # môže byť viac kariet v jednom ťahu
  "declared_suit": null,    # pri horníkovi/faraónovi
}
```
Server tento balík spracuje ako jeden atomický ťah cez `faraon_rules.gd`, validuje, a broadcastne nový `GameState` všetkým pripojeným peer-om (vrátane `deck_device` rolí).

---

## 5. Zvuk

Použi **voľne dostupné/licencované zvukové knižnice** (napr. freesound.org pod CC0/CC-BY licenciou — over licenčné podmienky pri každom stiahnutom zvuku a zaznamenaj zdroj/licenciu do `assets/audio/CREDITS.md` pre prípadné budúce publikovanie appky).

Potrebné zvukové efekty minimálne:
- Card flip / otočenie karty
- Shuffle balíčka
- Položenie karty na kôpku
- Ťahanie karty z balíčka
- Špeciálne efekty: eso (zastavenie), sedma (penalizácia), spálená (extra ťah), výhra/prehra hry
- Jemný UI feedback (tlačidlá, navigácia medzi obrazovkami)

Implementuj cez Godot `AudioStreamPlayer` s oddelenými audio bus-mi (Music, SFX, UI) a nastaviteľnou hlasitosťou v nastaveniach appky (min. master + SFX + music slider).

---

## 6. Monetizácia (in-app purchases + reklamy)

Použi Godot natívne/oficiálne udržiavané pluginy (Godot Foundation prevzala údržbu týchto pluginov v priebehu 2026, over si aktuálne verzie pred inštaláciou):
- **Android**: Godot Google Play Billing plugin (Google Play Billing Library, podpora one-time nákupov, konzumovateľných produktov, predplatných)
- **iOS**: Godot StoreKit 2 plugin
- Zváž aj cross-platformový **OpenIAP-based plugin** (unifikovaný GDScript API pre iOS aj Android naraz) ako alternatívu k spravovaniu dvoch oddelených natívnych pluginov — over aktuálny stav/zrelosť tohto pluginu a navrhni, ktorý prístup je pre sólo vývojára menej údržbovej záťaže.

### Monetizačný model
- Reklamy (banner/interstitial) pre free hráčov — over dostupné Godot reklamné SDK pluginy (AdMob je najbežnejší) a ich aktuálny stav pre Godot 4.6.
- Platba za odstránenie reklám (jednorazový nákup, non-consumable).
- Prémiové funkcie/kozmetika (napr. alternatívne dizajny balíčka kariet, stolové témy) ako ďalší monetizačný kanál — navrhni štruktúru produktov (product IDs), ale nemusíš implementovať finálny obsah kozmetiky teraz, priprav len systém/infraštruktúru.

Postav monetizačnú vrstvu ako samostatný modul (`res://monetization/`) oddelený od herné logiky, aby sa dal ľahko testovať/mockovať počas vývoja bez nutnosti reálnych store transakcií.

---

## 7. Architektonické princípy (zhrnutie)

1. **Rules engine oddelený od UI a networkingu** — `faraon_rules.gd` a príbuzné súbory nesmú importovať/závisieť od scene tree, node-ov ani multiplayer kódu. Musí byť testovateľný izolovane.
2. **Server je jediný zdroj pravdy** — žiadny klient (vrátane host-a) nerozhoduje o platnosti ťahu lokálne bez server-side potvrdenia, ani v single-player/local-test móde (drž rovnakú architektúru, aby prechod na multiplayer nevyžadoval refaktor).
3. **`deck_device` a `player` zdieľajú komponenty**, nie duplicitné scény.
4. **Assety (spracované karty, zvuky) sú oddelené od raw zdrojov** — `karty/`, `rules/` zostávajú nedotknuté ako zdrojový materiál, výstupy pipeline idú do `assets/`.
5. **Lokalizácia od začiatku** (SK primárny, EN toggle) — nehardcoduj stringy.
6. **Monetizácia je izolovaný modul**, mockovateľný počas vývoja.

---

## 8. Čo očakávam ako prvý krok od teba (Claude Code / Fable 5)

Nepíš rovno finálny kód. Namiesto toho:

1. Preskúmaj `karty/`, `rules/`, `inspiration/`, `architecture/` priečinky a potvrď, čo presne obsahujú (zoznam súborov, rýchly popis toho, čo vidíš v architecture mind-mapách).
2. Over si aktuálny stav Godot 4.6 multiplayer best practices pre malé ťahové hry (2-5 hráčov) cez internet — konkrétne k otázke relay server vs. WebSocketMultiplayerPeer vs. iné, a daj mi stručné odporúčanie s trade-offmi predtým, než začneš stavať túto vrstvu.
3. Navrhni scénovú/priečinkovú štruktúru projektu (Godot scene tree layout, priečinková organizácia `res://`) a ukáž mi ju na schválenie pred tým, než začneš generovať veľké množstvo súborov.
4. Spusti asset pipeline krok (rembg spracovanie kariet) ako samostatný, overiteľný krok — ukáž mi výsledok na vzorke kariet pred hromadným spracovaním.
5. Až potom postupuj k implementácii: najprv rules engine + testy, potom základné UI/stôl, potom animácie, potom multiplayer, potom monetizácia — v tomto poradí, s priebežnými checkpoint-mi na moje schválenie, nie ako jeden obrovský commit.

Pýtaj sa ma na spresnenie kdekoľvek, kde je nejednoznačnosť medzi týmto promptom a obsahom `rules/` PDF alebo `architecture/` mind-máp — nedomýšľaj si herné pravidlá ani architektonické rozhodnutia, ktoré nie sú explicitne pokryté.
