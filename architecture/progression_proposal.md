# Progression (body + levely) — návrh čísel na schválenie

Podľa sekcie 4 progression promptu: **konkrétne čísla vyžadujú schválenie
pred implementáciou** — tento dokument je návrh, žiadny kód zatiaľ neexistuje.
Referencia: Microsoft Solitaire štýl levelov a kozmetických odomknutí.

## 1. Bodový vzorec

```
body = TABUĽKA[počet_hráčov][umiestnenie] × multiplikátor
```

### Základná tabuľka (umiestnenie × počet hráčov)

| Hráčov | 1. miesto | 2. | 3. | 4. | 5. (posledný) |
|--------|-----------|----|----|----|----|
| 2      | 100       | 0  |    |    |    |
| 3      | 130       | 45 | 0  |    |    |
| 4      | 160       | 70 | 30 | 0  |    |
| 5      | 190       | 95 | 50 | 20 | 0  |

- Posledné miesto = vždy 0 (prehra sa neodmeňuje, ale ani netrestá záporne).
- 1. miesto rastie o +30 za každého hráča navyše — výhra proti viacerým
  súperom je hodnotnejšia.

### Multiplikátory (navzájom výlučné)

| Kontext hry                | Multiplikátor |
|----------------------------|---------------|
| Boti — Easy                | ×0.5          |
| Boti — Medium              | ×1.0          |
| Boti — Hard                | ×1.5          |
| Multiplayer (reálni hráči) | ×2.0          |

Príklady: výhra 4-hráčovej hry proti Hard botom = 160 × 1.5 = **240 b**;
2. miesto v 3-hráčovom multiplayeri = 45 × 2.0 = **90 b**; výhra 1v1 proti
Easy botovi = **50 b**.

## 2. Level krivka

Kumulatívne body; cena ďalšieho levelu rastie lineárne (mierne nelineárna
kumulatívna krivka, číta sa ľahko a nedá sa "zaseknúť"):

```
cena levelu n -> n+1 = 400 + 100 × n      (level 1 -> 2 = 500 b, 2 -> 3 = 600 b, ...)
```

| Level | Body na ďalší | Kumulatívne | ≈ výhier (4p Medium, 160 b) |
|-------|---------------|-------------|------------------------------|
| 1→2   | 500           | 500         | ~3                           |
| 2→3   | 600           | 1 100       | ~7                           |
| 5→6   | 900           | 3 500       | ~22                          |
| 9→10  | 1 300         | 8 100       | ~51                          |
| 19→20 | 2 300         | 26 100      | ~163                         |

Bez level capu (krivka rastie donekonečna); UI zobrazuje level + progress bar
do ďalšieho.

## 3. Odmeny (návrh mapovania)

- **Každý level**: pozadie stola alebo farebný variant (lacná kozmetika).
- **Míľniky 5 / 10 / 15 / 20...**: nový card skin (cez CardSkin registry).
- **Olympijský faraón ako odomykateľný variant**: NEROZHODNUTÉ — súvisí s
  monetizačnou stratégiou (level-gate vs. priama kúpa vs. voľne dostupný),
  čaká na tvoje rozhodnutie, do implementácie prvej verzie nejde.

## 4. Architektúra (po schválení čísel)

```
res://progression/
├── progression.gd        # record_game_result(...) -> {body, level pred/po, odomknutia}
├── progression_store.gd  # user://progression.cfg, schema_version, cloud-sync-ready dict
└── rewards.gd            # tabuľka level -> reward id (kozmetika, CardSkin idčka)
```

- Vstup: `finish_position`, počet hráčov, difficulty/multiplayer kontext —
  volané po GAME_OVER z klientskej vrstvy, **nikdy z faraon_rules.gd**.
- Odmeny = čisté kozmetické idčka; `res://monetization/` môže rovnaké idčka
  odomknúť kúpou (obchádza grind) cez spoločný `unlock(id, source)` bod.
- Level/body nikdy nevstupujú do hernej logiky ani pravdepodobností.
- Mimo rozsahu: denné výzvy, leaderboardy.

**Čakám na schválenie/úpravu čísel — potom implementujem.**
