# Faraón — kompletný kontext projektu (handoff pre AI asistenta)

> **Účel dokumentu:** odovzdať celý kontext projektu inému AI asistentovi, ktorý
> nemá históriu konverzácie. Obsahuje stav kódu, herné pravidlá, rozhodnutia
> zadávateľa, pracovné konvencie a technické pasce tohto konkrétneho stroja.
>
> **Stav k:** 2026-10-20, vetva `claude/admiring-knuth-hfxupx` (PR do `main`)
> — výkon, mobile-first UI, opravy chýb z review (sekcia 12).
> **Testy:** 220/220 GUT zelených.

---

## 1. O projekte a o zadávateľovi

**Faraón** je slovenská kartová hra (rodina Mau-Mau, 32-kartový mariášový
balíček) v **Godot 4.7 / GDScript**, cieľ Android + iOS + Windows.
Repo: <https://github.com/simon01920/faraon-farar>

**Zadávateľ: Simon Polakovic** (simonpolakovic@proton.me)
- Sólo vývojár, komunikuje **po slovensky** — odpovedaj mu po slovensky.
- Pracuje štýlom „prompt file → implementácia": napíše `.md` prompt do
  `C:\Users\simon\Downloads\`, pošle ho a čaká kompletné vykonanie.
- Chce **overené fakty, nie odhady**. Keď niečo tvrdíš, zmeraj to alebo ukáž
  screenshot/test. Keď sa mýliš, prizná sa to a opraví bez omáčky.
- Vie byť ostrý, keď sa niečo opakovane pokazí. Reaguj vecne, oprav to poriadne
  (nájdi *príčinu*, nie symptóm) a pokračuj.
- Pravidlá hry sú **jeho doména** — nikdy si nedomýšľaj herné pravidlo. Ak je
  nejednoznačné, spýtaj sa, alebo implementuj + jasne označ predpoklad.

### Pracovný rytmus, ktorý očakáva
1. Preštuduj existujúci kód → 2. navrhni → 3. (pri pravidlách/store) nechaj
   schváliť → 4. implementuj → 5. testy + vizuálny probe → 6. commit → 7. push.
- **Commit správy: bez diakritiky** (ASCII), v slovenčine, viacriadkové s
  odrážkami. Zakončené `Co-Authored-By: Claude <model> <noreply@anthropic.com>`.
- Po väčšom bloku vždy **push** na `origin/main` (`git push origin master:main`).
- Komentáre v kóde: slovensky pri hernej logike/rozhodnutiach, anglicky pri
  technických/architektonických veciach — v repe sa to mieša, drž sa okolia.

---

## 2. Prostredie a nástroje (POZOR: pasce tohto stroja)

| Vec | Hodnota |
|---|---|
| Godot | `C:\Users\simon\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe` (priečinok končí na `.exe`, vnútri je `_console.exe`) |
| Projekt | `C:\Users\simon\Downloads\faraon-farar-main\faraon-farar-main` |
| Android SDK | `C:\Users\simon\Downloads\android-sdk` |
| JDK | Amazon Corretto 25 |
| OS | Windows 11, shell PowerShell + Git Bash |

```bash
# Testy (GUT, headless)
<godot> --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Po zmene localization/strings.csv NAJPRV reimport, inak tr() vracia holé kľúče
<godot> --headless --path . --import

# Kontrola syntaxe jedného skriptu
<godot> --headless --path . --check-only --script res://cesta/subor.gd

# Vizuálny probe (NIE headless — kreslí a ukladá PNG do tools/)
<godot> --path . -s res://tools/<nieco>_probe.gd

# Android APK
<godot> --headless --path . --export-debug "Android" build/faraon.apk
```

### Kritické pasce (naozaj sa stali)
1. **NIKDY neprepisuj `.gd` cez PowerShell `Get-Content`/`Set-Content`** — zmrší
   UTF-8 na cp1252 (`☰ · —` → `Â·`, `â€"`). Používaj Edit/Write nástroje, alebo
   Git Bash heredoc. Raz to rozbilo `game_table.gd`, oprava bola bajtová.
2. **Nové testy/skripty GUT nevidí hneď** — najprv `--import`, potom test run.
   Hláška „Ignoring script … does not extend GutTest" ≈ **parse error**, nie
   dedičnosť. Over cez `--check-only`.
3. **V GDScript stringu nesmie byť ASCII `"`** vnútri slovenských úvodzoviek
   `„..."` — parse error. Buď preformuluj, alebo použi typografické `"`.
4. **GIMP 3** na AVIF konverziu: `gimp-console-3.0.exe -i --batch-interpreter
   python-fu-eval -b "<py>"`. **script-fu batch zamŕza** — nepoužívať.
5. **`%LOCALAPPDATA%` zápisy z Claude sedenia** idú do MSIX overlay a natívny
   Godot ich nevidí — preto je SDK v `Downloads\android-sdk`.
6. **Godot `PRESET_CENTER`** na kontajneroch, ktorým narastie min. veľkosť,
   posúva obsah vpravo dole — v tomto repe sa používajú full-rect
   `CenterContainer`-y.
7. **Proby píšu do `user://settings.cfg`** — ak probe nastaví jazyk/preset,
   musí ho na konci vrátiť (`GameSettings.clear_locale()` /
   `locale_is_explicit()`). Raz som mu takto prepol appku do angličtiny.
   `tools/layout_probe.gd` si user:// súbory zálohuje a na konci obnoví.
8. **`.cfg` súbory sú v pamäti (`ConfigCache`)** — GameSettings,
   ProgressionStore, Challenges a MonetizationStore čítajú súbor raz za beh.
   Kód/test, ktorý súbor zmaže alebo prepíše MIMO týchto API, musí zavolať
   `ConfigCache.invalidate(path)` (pozri `before_each` v testoch).

---

## 3. Architektúra

```
game/         čistá herná logika (RefCounted, žiadny scene tree, testovateľná)
  faraon_rules.gd    AUTORITATÍVNY engine pravidiel (666 r.)
  game_state.gd      dátový kontajner kola + view_for() cenzúra pre klienta
  rules_variant.gd   konfigurácia pravidiel + presety Faraón/Prší
  faraon_match.gd    meta-vrstva (olympijské režimy, rozstrely, rotácia)
  bot_strategy.gd    boti (Easy/Medium/Hard), skórovanie kandidátov
  card.gd, deck.gd, card_memory.gd, card_skin.gd, table_look.gd
  settings.gd        ConfigFile user://settings.cfg (jazyk, pravidlá, preset)
  config_cache.gd    jediné parsovanie user://*.cfg za beh (výkon na mobile)
  game_audio.gd, haptics.gd, messages.gd
net/          local_server.gd (LocalGameServer), room_client.gd (RoomClient)
server/       faraon_room.gd (transport-free, outbox), net_hub.gd (autoload,
              @rpc), room_manager.gd, net_protocol.gd
monetization/ ad_policy.gd (čistá logika), monetization_store.gd, ad_network.gd
              (+Mock), ads_controller.gd, store_backend.gd (+Mock), iap.gd
progression/  progression.gd, progression_store.gd, challenges.gd, rewards.gd
scenes/       main.gd (router), menu/main_menu.gd (1350 r.),
              table/game_table.gd (1635 r.), tutorial/tutorial.gd
ui/ui_kit.gd  spoločné štýly (pill_button, panel_style, heading, farby) +
              safe_rect() (výrez/zaoblené rohy), fit_width(), confirm()
tests/        13 súborov, 220 testov
tools/        25 screenshot probe skriptov (PNG sú gitignored)
architecture/ návrhové dokumenty a schválenia
```

### Nosné princípy (dodržuj ich)
- **Engine je čistý**: `FaraonRules` nepozná scény, siete ani čas. Vstup =
  akcia, výstup = `{ok, error, events}`. Klient len renderuje `events`.
- **Server je autoritatívny**, klienti posielajú návrhy. `GameState.view_for()`
  cenzuruje cudzie ruky a balíček — karty súperov nikdy neopustia server.
- **Duck typing servera**: `GameTable` hovorí rovnakým rozhraním s
  `LocalGameServer` aj `RoomClient` (`rules.state`, `propose()`,
  `state_updated`, `display_name()`, `progression_context()`…).
- **Transport-free room**: `FaraonRoom` nemá sokety, správy skladá do `outbox`
  → dá sa testovať bez siete (`test_multiplayer_rooms.gd`).
- **Mockovateľná monetizácia**: `AdNetwork`/`StoreBackend` sú rozhrania,
  default sú mocky → hra beží a testuje sa **bez akéhokoľvek SDK**.
- **Animácie cez frontu**: `GameTable._enqueue()` + `_drain()`; udalosti sa
  prehrávajú sériovo, `_busy` blokuje vstup. Pauzy (`_sleep`) sú tweeny
  viazané na stôl; uzly kariet v ruke/vejároch/kôpke sa recyklujú, nestavajú
  sa pri každom refreshi nanovo.
- **Mierka plátna podľa orientácie** (`main.gd`): na šírku základ 1280×720,
  na výšku 600×1000 (`_apply_content_scale` pri každej zmene okna). Rozloženie
  stola/menu/tutoriálu počíta s `UIKit.safe_rect()`; menu sa na šírku
  delí do dvoch stĺpcov.

---

## 4. Herné pravidlá — implementovaný stav

### Karty
ID = znak + farba. Znaky `7 8 9 X D H K A` (X=desiatka, D=dolník, H=horník),
farby `Z`=žaluď, `C`=červeň, `E`=zeleň, `G`=guľa.
Špeciálne: **`DE`** = zelený dolník = **faraón** (žolík), **`7C`** = červená
sedma (návrat hráča), **`RV`** = Tanečnica (33. karta, otáča smer; opt-in).

### Jadro
- Kladie sa na **farbu alebo znak**; kto nemá, ťahá a končí ťah.
- **Eso = čistý skip** jedného hráča. Žiadne „pokračovanie vlastníka reťaze"
  (A2 zmena). Prebitie esom predlžuje reťaz.
- **Sedma** = trest (default 3 karty), reťazí sa. Obrana: ďalšia sedma
  (eskalácia) alebo faraón (zrušenie na nulu).
- **Faraón** je neutrálny žolík: padne na čokoľvek, čokoľvek naň, ruší
  sedmičkovú reťaz. **Farbu hlási horník**, nie faraón.
- **Spálená**: 4 rovnaké znaky naraz = ťah navyše (nie pri esách/sedmách).
- **Červená sedma** vracia naposledy vypadnutého hráča. Obeť berie
  **krok × počet sediem v TOMTO ťahu** (7C+7X = 6 kariet). Predchádzajúca
  reťaz sa neráta — *toto bola Simonova explicitná oprava, nepokaz ju.*
- **Rozsah návratu (D8)**: default **„len z aktuálneho kola"**. Kolo sa meria
  cez `GameState.handovers` (odovzdania ťahu), nie počtom akcií.
- **Obrana kombináciou** (posledné zadanie): 1..N sediem naraz, ALEBO faraón
  (voliteľne s ďalšími dolníkmi) — **faraón musí byť prvá karta ťahu**.
  Zmiešaná sedma+faraón je neplatná (rôzny znak). Platí aj počas pauzy
  trestného ťahania (ťah vedie vytiahnutá karta).

### Domáce pravidlá (`RulesVariant`, všetky v UI „Domáce pravidlá")
`faraon_blocks_eso`, `hornik_strict`, `spalena_multiply`, `red7_on_active_eso`,
`eso_no_counter` (D9 rýchly režim), `seven_interrupt` (D4), `faraon_interrupt`
(D5, **default ON**), `purista` (D10), `green_king`(+counter) (D12),
`red_ten` (D13), `reverse_card` (D7a Tanečnica), `unter_announcer` (D11 —
dolníky okrem DE hlásia ZNAK), `pub_mode` (D15 Hospodské prší),
`faraon_wild`, `spalena_enabled`, `changer_blocked_on_specials`,
`multi_card_play`, `red7_return`.
Hodnotové: `initial_hand_size` (4–7), `seven_penalty_step` (2/3/4),
`seven_penalty_cap` (0/8/12), `red7_return_scope` (round/anyone),
`finish_rule` (none/no_seven/hornik_only).

> D16 „Neuner" Simon **zamietol** — neimplementovať.

### Herné módy = presety pravidiel (nie druhý engine)
| | Faraón (default) | Prší (české) |
|---|---|---|
| Rozdané karty | 5 | **4** |
| Trest za sedmu | 3, bez stropu | **2, strop 8** |
| Faraón (DE) | žolík | **bežná karta** |
| Spálená | áno | **nie** |
| Viac kariet naraz | áno | **nie** |
| Návrat 7C | áno (aktuálne kolo) | **nie** |
| Menič (horník/svršek) | padne na čokoľvek | **nie na eso ani sedmu** |

Preset určuje **predvolené hodnoty**, hráč si ich vie doladiť v oboch módoch.
Olympijské režimy sú **kolmé** na preset. Auto-výber pri prvom spustení podľa
jazyka zariadenia (čeština → Prší) a **pri Prší sa appka opýta dialógom**.
Tutoriál preskočí kroky, ktoré v danom móde neplatia.

### Režimy zápasu (`FaraonMatch`)
`NORMAL`, `OLYMPIC` (prehrávajúci dostáva menej kariet, kým nevypadne),
`REVERSE_OLYMPIC` (Simonov vynález: víťaz odovzdáva kartu, prvý na nule vyhráva).
Rozstrely (B2) o ďalšie miesta, rotácia začínajúceho (B1: Easy 100 % človek,
Medium 55 %, Hard/MP rovnaká šanca).

---

## 5. Multiplayer

- Model: **jeden proces hostí všetky roomky**, `ws://` na loopback :9000,
  **Nginx** terminuje `wss://` na 443 (schválené Simonom).
- `NetHub` (autoload) = jediné miesto, ktoré sa dotýka siete; `@rpc` metódy
  `sv_*` (klient→server) a `cl_*` (server→klient).
- 5-znakový kód roomky (bez zameniteľných znakov), **reconnect do 120 s** cez
  session token, cenzurované snapshoty, validácia tvaru správ v `NetProtocol`.
- **Obnova spojenia (klient)**: `RoomClient` sa po výpadku pripája sám
  (backoff 1–15 s, vzdá sa pred koncom 120 s okna) a vráti sa s tokenom;
  signály `reconnecting/reconnected/reconnect_failed` ukazuje stôl aj lobby.
  `RoomClient.leave()` = odchod + zabudnutie kódu/tokenu.
- **Neprítomné miesto** (odišiel/vypadol po grace) server odohráva sám
  (ťahá / stojí pri esách), aby ostatní dohrali; host = prvý pripojený člen.
- **Variant od hostiteľa** sa sanitizuje (`NetProtocol.sanitize_variant`),
  ruky, ktoré sa z balíčka nedajú rozdať → chyba `too_many_cards`.
- Kozmetický kanál „živý stôl": `sv_selection(count)` — súperi vidia **počet**
  nadvihnutých kariet (nie hodnoty), debounce 150 ms, čistí sa pri akcii a
  odpojení.
- Spustenie: `run_server.bat [port]` (Windows) alebo
  `<godot> --headless --path . -- --server --port=9000`.
  Kompletný návod: **`SERVER_SETUP.md`** (lokálne, LAN s telefónom, VPS+TLS).
- ⚠️ **`NetProtocol.PROD_URL` je stále `wss://faraon.example.com/ws`** — pred
  release buildom tam musí ísť skutočná doména.

---

## 6. Monetizácia (posledný veľký blok)

Reklamný model je zámerne **nerušivý**:
- **6-hodinové okno**; hry **1–3 čisté**, reklama po **4., 6., 8., 10.**…
- Interstitial je **statický, hneď zatvoriteľný** (žiadne video/rewarded) a
  zobrazí sa **až pri odchode z výsledkovej obrazovky** — nikdy počas hry,
  animácií ani medzi olympijskými kolami.
- **Offline**: počítadlo beží (nedá sa obísť letovým režimom), ale dlžná
  reklama je **len jedna**, zobrazí sa online. Žiadne „reklamné dlhy".
- **Banner** len v menu (spodný pruh, menu sa oň skráti), v hre a pre premium
  mizne.

Produkty (oba rušia všetky reklamy):
`faraon_remove_ads_yearly` **6,99 €/rok** (subscription),
`faraon_remove_ads_lifetime` **14,99 €** (non-consumable).
Ceny sa čítajú **zo store**, nie hardcoded. Restore purchases je povinný
(Apple). Lifetime platí offline navždy; subscription má grace revalidáciu.

Odporúčané pluginy (over pri nasadení): **Poing Studios AdMob**, IAP cez
cross-platformový **Godot IAP (OpenIAP)**. Výmena mocku za reál sú **2 riadky**
— presne zdokumentované v **`monetization/STORE_SETUP.md`** vrátane postupu v
Google Play Console a App Store Connect.

---

## 7. Lokalizácia

`localization/strings.csv` — stĺpce `keys,sk,en,cs` (~240 kľúčov, kompletné).
- Prepínač jazyka = dropdown (Slovenčina / Čeština / English).
- Pri prvom spustení jazyk určí **zariadenie** (sk→sk, cs→cs, ostatné→en),
  potom má prednosť voľba hráča.
- Názvy podľa jazyka: SK/EN titul **Faraón** + podnázov „Farár / Prší";
  CS titul **Prší** + podnázov „Faraon / Farář".
- Česká terminológia: **spodek / svršek / žaludy / červené / zelené / kule**,
  „lízat" namiesto „ťahať".

---

## 8. Otvorené veci (čaká sa na Simona alebo na neskôr)

| Vec | Detail |
|---|---|
| **Q3 z Prší** | Nikdy neodpovedal, či sa v Prší má dať klásť viac kariet naraz. Implementované podľa odporúčania = **vypnuté**, ale je to prepínač v domácich pravidlách. |
| **Doména pre MP** | `NetProtocol.PROD_URL` + reálne nasadenie na VPS. |
| **Streak bonusy** | Čísla v `architecture/engagement_numbers_proposal.md` neschválené. |
| **Hudba** | 8 Suno skladieb sa mieša všade; nepriradené ku kontextom. |
| **EULA/Privacy + auto-renew text** | Musí pribudnúť do nákupnej obrazovky pred submitom (Apple aj Google to vyžadujú). |
| **UMP/GDPR consent** | Pri napojení AdMobu treba doriešiť. |
| **Friends leaderboard** | Odložené, kým nebeží server. |
| **Portrait UI scale** | Vyriešené (základ 600×1000 na výšku, ~2× väčšie UI) — ešte overiť na reálnom telefóne vrátane výrezu (`UIKit.safe_rect`). |
| **Pravidlo: vyschnutý balík počas trestu** | PREDPOKLAD: zvyšok trestu ťahajúceho prepadá (predtým nechtiac prechádzal na ďalšieho hráča). Označené v `faraon_rules.gd` — Simon môže prehodnotiť. |
| **Pravidlo: spálená končiaca KE/XC** | Trest +4/zapečatený +1 dostane hráč, ktorý spálenú zahral (tah navyše). Nezmenené — rozhodnutie pre Simona. |
| **Pravidlo: pauza pri trestnom ťahaní** | Udalosť `PENALTY_INTERRUPT` (a hláška „X môže prerušiť faraónom/sedmou") prezradí všetkým, akú kartu ťahajúci vytiahol. Snapshot `interrupt_card` už vidí len majiteľ. Je to zámer? |
| **MP: 5 hráčov × 7 kariet** | Engine rozdá max. (balík−2)/hráčov (=6); room štart s takou rukou odmietne `too_many_cards`. |
| **Veľkosť buildu** | Android PCK 74.8 MB (z 154.7). Zvyšok je hlavne hudba (53 MB MP3, ~200 kb/s) — prekódovanie na OGG ~112 kb/s by ušetrilo ~25 MB; nerobené, je to otázka kvality zvuku. Dev skin `assets/cards/<farba>/` sa do exportu nedáva (v editore funguje). |
| **Simonove lokálne nastavenia** | V `settings.cfg` má `initial_hand_size=4` a `red7_return_scope="round"` ako vlastnú voľbu — vo Faraóne teda dostáva 4 karty. Bol upozornený. |

---

## 9. Ako overovať prácu (očakávaný štandard)

1. **Unit testy** na každú hernú zmenu — engine je čistý, takže sa dá otestovať
   všetko vrátane botov (`test_prsi_mode.gd` hrá 24 celých partií a kontroluje,
   že každý návrh bota je legálny).
2. **Vizuálny probe** na každú UI zmenu: `tools/*_probe.gd` uloží PNG, ktorý si
   pozri. Pri drobnostiach (zarovnanie textu) **priblíž si výrez a zmeraj
   geometriu** — z celkového screenshotu 1280×720 sa chyba o 13 px nedá vidieť.
   Presne na tomto som raz zlyhal dvakrát po sebe.
3. **Screenshoty ukáž Simonovi** v odpovedi, keď menil vzhľad.

Užitočné proby: **`layout_probe`** (menu, nastavenia, tutoriál, stôl, veľká
ruka, pauza, výber farby, výsledky × telefón na výšku/šírku, tablet, desktop;
`-- --insets=90,0,90,40` simuluje výrez, `-- --only=phone_portrait`),
`settings_probe` (3 rozlíšenia), `czech_probe`, `prsi_probe`,
`monetization_probe`, `penalty_combo_probe`, `mp_probe`, `pause_probe`,
`selection_glow_probe`, `startflip_probe`, `anim_probe`.

---

## 10. História (skrátene, najnovšie hore)

| Commit | Obsah |
|---|---|
| 2026-10-20 (PR) | **Multiplayer + monetizácia**: obnova spojenia, unikátne seaty, neprítomné miesta, sanitizácia variantu, reklamné callbacky, lifetime vs. predplatné |
| 2026-10-20 (PR) | **Ľahší build**: pozadia lossy 2048 px, export bez duplikátov/dev skinu (155 → 75 MB), low-processor mode |
| 2026-10-20 (PR) | **Mobile-first UI**: portrét 600×1000, safe area, dvojstĺpcové menu, recyklácia uzlov kariet |
| 2026-10-20 (PR) | **Engine + výkon**: rng_seed v snapshote, zamietnutý ťah bez vedľajších účinkov, pečať D13, olympijské prídely, boti, ConfigCache |
| `980cf45` | Dropdown jazyka: skutočné vycentrovanie (OptionButton vyhradzuje 16 px šípke) |
| `26de8ef` | Rozostupy v menu, vodoznak presahuje mimo obsah |
| `900be79` | Zarovnanie produktových kariet, prvá oprava dropdownu |
| `c178549`–`5e99f63` | **Monetizácia** (3 commity): frekvenčná logika + testy, banner/interstitial/IAP/UI, STORE_SETUP.md |
| `44cfbcd` | Názvy podľa jazyka, dropdown, jazyk zariadenia |
| `732851c` | **Herný mód Prší** (preset, dialóg pri prvom štarte, tutoriál) |
| `125ae76` | Návrh pravidiel Prší + oprava hlášky pauzy |
| `5535e0d` | **Čeština** ako tretí jazyk |
| `e3bc74b` | Kombinovanie trestných kariet + D8 default „aktuálne kolo" |
| `9309090` | Spustiteľný MP server, `SERVER_SETUP.md`, fix export presetu |
| `06d3e0b` | Selection glow (živý stôl) lokálne + boti + MP |
| `fb57e55` | HOTFIX: pád hry pri otvorení menu |
| `2d0a6d8` | Tanečnica, spodok-menič, Hospodské prší, dev režim |
| staršie | pravidlá A1/A2/B/C/D, multiplayer, tutoriál/výzvy/štatistiky, progresia, animácie, vzhľad, Android export |

**Dev režim:** 7 ťuknutí na nadpis „Nastavenia" (alebo `[dev] dev_mode=true`)
→ v lokálnej hre tlačidlo 🛠 / F12 = DevPanel (dať karty, nastaviť tresty,
spustiť efekty).

---

## 11. Odporúčaný prvý krok pre preberajúceho asistenta

```bash
cd "C:/Users/simon/Downloads/faraon-farar-main/faraon-farar-main"
git log --oneline -10
<godot> --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```
Ak je 164/164 zelených, stav sedí s týmto dokumentom. Potom si prečítaj
`game/faraon_rules.gd` (hlavičkový komentár zhŕňa všetky rozhodnutia o
pravidlách) a `game/rules_variant.gd` (presety) — to sú dva najdôležitejšie
súbory projektu.


---

## 12. Výkon, mobile-first a opravy (2026-10-20)

Merané na desktope (headless, rovnaká scéna pred/po; na telefóne je rozdiel
väčší):

| Čo | Pred | Po |
|---|---|---|
| `GameTable._refresh_all` (po každom ťahu, ruka 14 kariet) | 11–19 ms | 0.3–0.5 ms |
| prekreslenie ruky po ťuknutí na kartu | ~11.5 ms | ~0.19 ms |
| `GameSettings.build_variant()` | 1.47 ms | 0.13 ms |
| Android PCK | 154.7 MB | 74.8 MB |

- Staré 11–19 ms sa nezmestili do 16 ms snímky → zásek pri každom ťahu.
- Pravidlá: opravené len chyby, kde kód odporoval zdokumentovaným pravidlám
  alebo padal; rozhodnutia, ktoré patria Simonovi, sú v sekcii 8.
- Na overenie na zariadení: rotácia počas hry aj tutoriálu, telefón s
  výrezom/gestom domov, výpadok Wi-Fi počas online hry (má sa ukázať
  „Spojenie prerušené — pripájam znova…").
