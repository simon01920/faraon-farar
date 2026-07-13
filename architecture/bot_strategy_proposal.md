# BotStrategy — návrh na schválenie (pred implementáciou)

Návrh podľa bodu 6 opravného promptu. **Nič z tohto ešte nie je implementované** —
najprv schválenie, potom ladenie. Súčasný `BotPlayer` zostáva nedotknutý, kým sa
návrh neodklepne.

## Architektúra

```
game/bot_strategy.gd (nová trieda, RefCounted — čistá logika, unit-testovateľná)
├── enum Difficulty { EASY, MEDIUM, HARD }
├── var difficulty: Difficulty
├── var memory: CardMemory            # len HARD ju reálne používa
└── func choose(state: GameState, id: String) -> Dictionary   # FaraonActions.*
```

- `BotStrategy` nahradí `BotPlayer` ako mozog v `LocalGameServer`; server dostane
  `bot_difficulty` parameter pri `start_game(...)` (per hra, nie per bot).
- Rules engine (`faraon_rules.gd`) sa **nedotýka** — stratégia číta iba
  `GameState` view (vlastná ruka + verejné info: odkladacia kôpka, počty kariet,
  pending stavy). Žiadne nahliadanie do cudzích rúk, aby ten istý mozog mohol
  neskôr bežať server-side v multiplayeri.
- `CardMemory` (malá pomocná trieda): eviduje karty videné v odkladacej kôpke
  od začiatku hry + počty kariet súperov. Plní sa z events (`CARDS_PLAYED`,
  `DREW`), resetuje pri reflipe kôpky (karty sa vracajú do obehu).

## Rozhodovací princíp: scoring kandidátskych ťahov

Každý legálny ťah (skupina kariet / draw / pass) dostane skóre; bot hrá
najlepší. Difficulty určuje, ktoré zložky skóre sú zapnuté a koľko šumu sa
pridá:

```
score(move) = w_size   * počet zahraných kariet
            + w_block  * blokovacia hodnota (eso/sedma keď súper má málo kariet)
            + w_save   * hodnota podržania špeciálu na neskôr (záporná za minutie)
            + w_suit   * vyrovnanie farieb v ruke (hrať z najpočetnejšej farby)
            + w_memory * odhad z počítania kariet (len HARD)
            + noise    * randf()  (EASY vysoký šum, HARD ~0)
```

## Úrovne

| Zložka | Easy | Medium | Hard |
|---|---|---|---|
| Legálnosť ťahov | ✓ | ✓ | ✓ |
| Šum (náhodnosť výberu) | vysoký — prakticky náhodný legálny ťah | nízky | ~0 |
| Drží eso/sedmu/faraóna na neskôr | nie — hrá hneď | základne (proti súperovi s ≤2 kartami) | strategicky (kľúčové momenty, faraón na sedmy v núdzi) |
| Vyrovnávanie farieb v ruke | nie | ✓ | ✓ |
| Blokovanie hráča blízko výhry | nie | zjavné situácie | aktívne (cieli esá/sedmy na lídra) |
| Počítanie kariet (kôpka) | nie | nie | ✓ — odhad, či súper môže mať eso/sedmu/farbu |
| Červená sedma | podľa enginu (automat) | drží si ju, ak niekto môže dohrať | drží + časuje na najsilnejšieho súpera |

**Presné váhy `w_*` zámerne nenavrhujeme** — po schválení štruktúry ich
nastavíme spolu pri ladení (prompt výslovne žiada konzultáciu, „aby neboli
sprostí" je subjektívne).

## UI plumbing (súčasť tejto úlohy, po schválení)

- Výber Easy / Medium / Hard pri zakladaní lokálnej hry (rozšírenie riadku
  „Hrať proti súperom" v menu), persistuje sa v `GameSettings`.
- Default: Medium.

## Testovateľnosť

- Unit testy na deterministický výber pri noise = 0 (HARD): daný stav → daný ťah.
- Smoke test: 3× BotStrategy dohrá hru bez zásahu (žiadne zaseknutie).
- `CardMemory` unit testy: reflip reset, počítanie videných es.
