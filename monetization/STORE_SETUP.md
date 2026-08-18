# Faraón — monetizácia: nastavenie obchodov a napojenie reálnych pluginov

Tento návod ťa prevedie od súčasného stavu (funkčný **mock**, žiadne reálne
reklamy ani platby) k ostrému nasadeniu s reálnym AdMob-om a nákupmi na
Google Play aj App Store. Je písaný pre sólo vývojára bez predošlej skúsenosti
so store monetizáciou — každý krok je vysvetlený, nie len odkázaný.

> **Dôležité:** appka je funkčná a testovateľná **už teraz** bez akéhokoľvek
> pluginu. Celá logika (frekvencia reklám, premium stav, obnovenie nákupov) je
> v `res://monetization/` a beží na `MockAdNetwork` / `MockStoreBackend`.
> Reálne SDK sa napája až tu — kód nad hranicou sietí sa nemení.

---

## 0. Ako je to poskladané (prehľad)

```
monetization/
  ad_policy.gd          čistá logika KEDY reklama (6h okno, hry 4/6/8...) — testy
  monetization_store.gd lokálne úložisko (počítadlo, premium) — user://monetization.cfg
  ad_network.gd         rozhranie k reklamnému SDK + MockAdNetwork (default)
  ads_controller.gd     mostík policy<->SDK, offline/premium short-circuit
  store_backend.gd      rozhranie k billing pluginu + MockStoreBackend (default)
  iap.gd                nákupná fasáda: nákup/obnovenie -> premium stav
```

Dve miesta, kde sa vymení mock za realitu (a nič iné):
1. **Reklamy:** v `scenes/main.gd`, `_ads = AdsController.new()` → odovzdaj mu
   reálnu sieť: `AdsController.new(AdMobNetwork.new())`.
2. **Nákupy:** v `scenes/menu/main_menu.gd`, `_iap = Iap.new()` → odovzdaj mu
   reálny backend: `Iap.new(PlayStoreBackend.new())` (resp. StoreKit na iOS).
   Rovnako v `main.gd` `Iap.refresh_entitlements(<backend>)` pri štarte.

---

## 1. Produkty a ceny (záväzné)

| Produkt | Product ID | Typ | Cena (koncová, vrátane DPH aj provízie) |
|---|---|---|---|
| Ročné predplatné | `faraon_remove_ads_yearly` | auto-renewable subscription | **6,99 € / rok** |
| Trvalý nákup | `faraon_remove_ads_lifetime` | non-consumable (lifetime) | **14,99 € navždy** |

Oba **odstraňujú všetky reklamy** (interstitial aj banner). Product IDs sú
konštanty v `store_backend.gd` — v oboch konzolách musia byť **presne rovnaké**.

**K cenám:** 6,99 € a 14,99 € sú sumy, ktoré nastavíš ako **predajnú cenu** v
konzole obchodu. Zákazník uvidí presne toto (v lokálnej mene podľa regiónu).
Nepripočítavaj žiadnu daň ani províziu — obchod to rieši sám. Tvoj čistý
príjem je po odpočítaní provízie a DPH z tejto sumy.

**Provízie (stav 2026, over pri nasadení):**
- **Apple Small Business Program:** 15 % pri príjme < 1 mil. USD/rok
  (treba sa prihlásiť). Bez programu 30 %; pri predplatnom klesá na 15 % po
  12 mesiacoch nepretržitého predplatného.
- **Google Play:** automaticky 15 % na prvý 1 mil. USD/rok (bez prihlásenia);
  predplatné 15 % od prvého dňa.

Zhrnuté: ako malý vývojár máš na oboch obchodoch reálne **~15 %** províziu.

---

## 2. Google Play Console (Android)

Predpoklad: máš vývojársky účet (jednorazový poplatok 25 USD) a nahranú
aspoň internú testovaciu verziu appky s **rovnakým `applicationId`**, aký je
v `export_presets.cfg` (`sk.pirios.faraon`).

### 2.1 Lifetime (jednorazový produkt)
1. Play Console → tvoja appka → **Monetize → Products → In-app products**.
2. **Create product**. Product ID: `faraon_remove_ads_lifetime`.
3. Name/description (lokalizované, aspoň EN + SK + CS).
4. **Set price** → zadaj 14,99 € v predvolenej mene; Google dopočíta ostatné
   regióny (môžeš doladiť).
5. **Activate**.

### 2.2 Ročné predplatné (subscription)
1. **Monetize → Products → Subscriptions → Create subscription**.
2. Product ID: `faraon_remove_ads_yearly`.
3. Pridaj **base plan** typu *auto-renewing*, billing period **1 rok**, cena
   6,99 €. (Grace period a account hold nechaj na odporúčaných hodnotách —
   riešia dočasné zlyhania platby, presne to, čo náš grace-revalidačný kód
   očakáva.)
4. **Activate** base plan aj subscription.

### 2.3 Testovanie
- Pridaj svoj Google účet do **License testing** (Play Console → Setup →
  License testing) — testovacie nákupy nebudú spoplatnené.
- Nahraj build do **internal testing** a testuj na reálnom zariadení
  (billing nefunguje v emulátore ani cez mock po napojení pluginu).

---

## 3. App Store Connect (iOS)

Predpoklad: Apple Developer Program (99 USD/rok), appka založená v App Store
Connect s bundle ID `sk.pirios.faraon`.

### 3.1 Prihlás sa do Small Business Program
**App Store Connect → Agreements** → *Apple Developer Program → Small Business
Program* (ak spĺňaš < 1 mil. USD). Zníži províziu na 15 %.

### 3.2 Lifetime (non-consumable)
1. **App Store Connect → tvoja appka → In-App Purchases → Manage → (+)**.
2. Typ: **Non-Consumable**. Reference Name: „Remove Ads Lifetime".
   Product ID: `faraon_remove_ads_lifetime`.
3. Cena: **Tier** zodpovedajúci 14,99 € (Apple používa cenové tiery).
4. Pridaj lokalizácie (EN/SK/CS), screenshot pre review, **Save**.

### 3.3 Ročné predplatné (auto-renewable)
1. **In-App Purchases → Subscriptions → Create Subscription Group**
   (napr. „Faraón Premium"). Jedna skupina stačí.
2. V skupine **(+)** → Product ID: `faraon_remove_ads_yearly`,
   dĺžka **1 rok**, cena zodpovedajúca 6,99 €.
3. Vyplň lokalizácie + review poznámku, **Save**.

### 3.4 Apple review — povinnosti (inak zamietnu)
- **Restore purchases** musí byť dostupné v UI — máme („Obnoviť nákupy" v
  Nastaveniach). Bez neho Apple appku zamietne.
- Pri predplatnom musí byť v appke (alebo blízko tlačidla kúpiť) uvedené:
  dĺžka a cena obdobia, že sa **automaticky obnovuje**, a odkaz na
  **Terms of Use (EULA)** a **Privacy Policy**. Doplň tieto texty/odkazy do
  nákupnej obrazovky pred submitom (dnes tam je len cena a popis).
- **Sandbox testing:** App Store Connect → Users and Access → Sandbox →
  vytvor testovací Apple ID a prihlás sa ním na zariadení (Settings →
  Developer). Testovacie nákupy sú zadarmo a subscription „rok" ubehne za
  minúty (zrýchlený sandbox čas) — ideálne na overenie expirácie.

---

## 4. Napojenie reálnych pluginov (Godot 4.7)

Projekt beží na **Godot 4.7**. Pluginy nižšie podporujú 4.2+, teda aj 4.7.

### 4.1 Reklamy — AdMob
Odporúčaný plugin: **Poing Studios „Godot AdMob Plugin"** (najlepšie
udržiavaný, oficiálny-ish, GDScript, mock ads v editore, banner aj
interstitial, Android aj iOS). Alternatíva: `godot-sdk-integrations/godot-admob`
(aktívny, navyše UMP consent pre GDPR).

Kroky:
1. Nainštaluj plugin podľa jeho README (Android: do `res://addons/`, pridaj
   ako Android plugin v export presete; iOS: cez CocoaPods pri exporte).
2. Vytvor AdMob účet, appku a ad unit IDs (jeden **interstitial**, jeden
   **banner**). Testovacie IDs používaj počas vývoja!
3. Vytvor `monetization/admob_network.gd` — podtriedu `AdNetwork`, ktorá
   metódy `load_interstitial() / show_interstitial() / show_banner() /
   hide_banner() / is_online()` napojí na plugin a **emituje
   `interstitial_closed`** pri zatvorení aj pri zlyhaní (aby hráč neostal
   visieť). Interstitial musí byť **statický, hneď zatvoriteľný** — v AdMob
   je to štandardný interstitial formát (žiadne rewarded/video).
4. V `scenes/main.gd` zmeň `AdsController.new()` na
   `AdsController.new(AdMobNetwork.new())`.

Frekvenciu, počítadlo ani okno **nemeníš** — o tom rozhoduje `AdPolicy`,
plugin len „zobraz teraz".

### 4.2 Nákupy — Billing / StoreKit
Odporúčanie pre sólo vývojára: **jeden cross-platformový plugin** namiesto
dvoch. „**Godot IAP**" (OpenIAP: StoreKit 2 na iOS + Google Play Billing 8+
na Androide, jedno GDScript API) = najmenej údržby. Ak by nevyhovoval, použi
oddelene oficiálny **godot-google-play-billing** (Android) + StoreKit plugin
(iOS).

Kroky:
1. Nainštaluj plugin (addons + export preset ako pri AdMob).
2. Vytvor `monetization/play_store_backend.gd` (a/alebo `storekit_backend.gd`)
   — podtriedu `StoreBackend`, ktorá:
   - v `query_products()` načíta produkty podľa `PRODUCT_IDS` a emituje
     `products_updated` s **lokalizovanou cenou zo store** (nie hardcoded);
   - v `purchase(id)` spustí platbu a po úspechu emituje `purchase_completed`
     so správnym `kind` a pri subscription aj `valid_until` (expirácia);
   - v `restore_purchases()` znovu načíta vlastníctva a emituje
     `purchase_completed` za každé platné;
   - vo `validate_subscription()` pri štarte overí, či predplatné ešte platí;
     ak na store vypršalo, zavolaj `MonetizationStore.clear_premium()`.
     **Nevypínaj premium pri jednom zlyhaní/offline** — to je grace period.
3. V `scenes/menu/main_menu.gd` zmeň `Iap.new()` na `Iap.new(<backend>)`
   a v `scenes/main.gd` `Iap.refresh_entitlements(<backend>)`.

---

## 5. Reklamný model (zhrnutie pravidiel, ktoré modul dodržiava)

- **6-hodinové okno**, reset po ≥ 6 h neprítomnosti (bez časovača na pozadí —
  porovnáva sa uložený timestamp pri štarte).
- Hry **1–3** čisté; reklama po **4., 6., 8., 10.** hre (od 4. každá druhá).
- Interstitial **až po výsledkovej obrazovke**, pri odchode z nej — nikdy
  počas hry, animácií ani medzi olympijskými kolami.
- **Offline:** počítadlo beží (nedá sa obísť letovým režimom), ale reklama sa
  zobrazí až online; dlžná reklama je **len jedna**, žiadne nahromadenie.
- **Banner** len v menu obrazovkách, na spodnom okraji; v hre a pre premium
  zmizne.
- **Premium** (lifetime alebo aktívne predplatné): celá reklamná logika sa
  vôbec nespustí; lifetime platí aj offline navždy.

Tieto pravidlá sú pokryté testami v `tests/unit/test_monetization.gd` a bežia
bez akéhokoľvek SDK.

---

## 6. Odporúčané ďalšie kroky pred submitom
1. Doplniť do nákupnej obrazovky odkazy na **EULA + Privacy Policy** a text o
   auto-obnove predplatného (Apple aj Google to vyžadujú).
2. Nastaviť **UMP / consent** (GDPR/EÚ) — AdMob plugin s UMP to zvláda; bez
   súhlasu sa v EÚ nesmú zobrazovať personalizované reklamy.
3. Doplniť **App Privacy** dotazník (Apple) / **Data safety** (Google) — appka
   cez AdMob zbiera reklamné identifikátory, treba to priznať.
