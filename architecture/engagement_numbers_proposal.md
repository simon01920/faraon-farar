# Engagement — návrhy čakajúce na Simonovo rozhodnutie

## 1. Streak bonus (čísla na schválenie — bodová ekonomika)

Streak počítadlo + pravidlo je implementované a viditeľné v UI („Zahraj dnes
aspoň jednu hru, aby si neprišiel o streak" — kalendárne dni, vynechaný celý
deň = reset na 1). **Bonusové body sa zatiaľ NEUDEĽUJÚ** — návrh čísel:

| Deň streaku | Bonus pri prvej hre dňa |
|---|---|
| 2. | +10 b |
| 3. | +20 b |
| 4. | +30 b |
| 5.–6. | +40 b |
| 7. a každý ďalší 7. (14., 21., …) | **+100 b** |
| ostatné dni nad 7 | +50 b (strop) |

Kontext: bežná výhra = 100–240 b, splnená denná výzva = +40 b. Strop +50/+100
drží streak ako „malý dôvod vrátiť sa", nie hlavný zdroj bodov.
**Schváľ/uprav čísla a zapnem udeľovanie** (kód je pripravený v
`Challenges._update_streak`, chýba len bonusová vetva).

## 2. Denné výzvy — implementované hodnoty (informačne)

3 aktívne výzvy denne (deterministický výber z poolu 8 podľa dátumu, reset o
polnoci lokálneho času), splnenie = **+40 b** (konštanta
`Challenges.CHALLENGE_POINTS`, ľahko upraviteľná).

## 3. Rebríček medzi priateľmi (4.4.2) — odporúčam ODLOŽIŤ za nasadenie servera

Dôvod (technická závislosť, nie preferencia): rebríček porovnáva level/win
rate hráčov na RÔZNYCH zariadeniach — potrebuje centrálny bod, kde hráči
nahlásia svoje skóre a prečítajú skóre priateľov. To je presne multiplayer
server (bod 1), ktorý je síce implementovaný, ale ešte nie je nasadený na VPS
s doménou. Lokálne sa to sfalšovať nedá (súperove body nemám odkiaľ vziať).

Čo je už pripravené teraz:
- lokálny log „s kým som hral" (`ProgressionStore.bump_friend` — meno + počet
  spoločných hier, plní sa pri každom online game_started),
- room/protokolová vrstva, do ktorej sa po nasadení doplní jeden RPC pár
  (`sv_report_score` / `sv_get_friends_board`) + malá perzistencia na serveri.

Návrh poradia: nasadiť server na VPS → overiť reálne hranie cez internet →
potom rebríček (odhad: malý prírastok, ~1 sedenie).

## 4. Hudobné kontexty (informačne, z importu assetov)

Názvy stôp nerozlišujú menu vs. hra — playlist zatiaľ rotuje všetkých 8 stôp
všade. Ak chceš niektoré stopy viazať na menu/hru, napíš priradenie.
