# Android: podpisový kľúč pre beta APK

APK pre testerov stavia GitHub Actions (`.github/workflows/release.yml`, job
`build`) ako **debug export** (`--export-debug "Android"`, len arm64-v8a,
minSdk 24 = Android 7.0, targetSdk 36). Lokálne Android SDK netreba.

## Prečo je kľúč v repe

Android pustí aktualizáciu (inštaláciu cez starú verziu) **len vtedy, keď je
APK podpísané tým istým kľúčom**. Keby CI pri každom behu vyrobilo nový
náhodný debug kľúč, tester by v0.1.3 nenainštaloval cez v0.1.2 — musel by
appku odinštalovať a prišiel by o uložený postup. Preto sa podpisuje stále
tým istým kľúčom:

1. **repo secret `ANDROID_DEBUG_KEYSTORE_B64`**, ak je nastavený (keystore
   v base64), s voliteľnými `ANDROID_DEBUG_KEYSTORE_USER` (alias, default
   `androiddebugkey`) a `ANDROID_DEBUG_KEYSTORE_PASSWORD` (default `android`);
2. inak **`android/beta-debug.keystore`** z tohto priečinka.

| | |
|---|---|
| súbor | `android/beta-debug.keystore` (PKCS12) |
| alias / heslo | `androiddebugkey` / `android` |
| platnosť | do 2056 |
| SHA-256 certifikátu | `CE:15:9E:C1:01:B0:D1:65:B9:6C:2B:8E:EC:31:98:18:86:06:5A:85:DE:67:46:42:7B:42:E2:FC:3D:ED:0A:8B` |

**Tento kľúč NIE JE tajný** — je verejne v repe, takže ktokoľvek ním vie
podpísať APK s rovnakým názvom balíka. Na sideload betu to stačí (testeri
sťahujú APK len z našej GitHub stránky), ale:

- **nikdy ho nepoužívaj pre Google Play** ani pre žiadnu „ostrú" verziu;
- Play Protect môže pri inštalácii upozorniť (neznámy vývojár, debug build).

Workflow po exporte overí `apksigner verify --print-certs`, že APK je
podpísané práve vybraným kľúčom, a cez `aapt2 dump badging` balík
`sk.pirios.faraon` a že `versionName` sedí s tagom.

## Pri každom vydaní

V `export_presets.cfg` (preset „Android") zvýš **`version/code`** o 1 a
nastav **`version/name`** na verziu tagu (bez `v`). Nižší alebo rovnaký
`version/code` Android ako aktualizáciu neprijme; nesúlad `version/name`
s tagom workflow zastaví.

## Neskôr: ostrý release kľúč (Google Play)

1. Vyrob vlastný kľúč a **nikam ho necommituj** (zálohuj ho; strata = už
   žiadna aktualizácia tej istej appky):
   `keytool -genkeypair -v -keystore faraon-release.keystore -storetype PKCS12 -alias faraon -keyalg RSA -keysize 2048 -validity 10000`
2. Do GitHubu (Settings → Secrets and variables → Actions) ho daj ako secrets,
   napr. `ANDROID_RELEASE_KEYSTORE_B64` (`base64 -w0 faraon-release.keystore`),
   `ANDROID_RELEASE_KEYSTORE_USER`, `ANDROID_RELEASE_KEYSTORE_PASSWORD`.
3. Vo workflow exportuj `--export-release "Android"` a kľúč odovzdaj cez
   premenné `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD`
   (rovnako, ako sa teraz odovzdáva debug kľúč). Pre Play Store sa navyše
   exportuje AAB (gradle build, `gradle_build/export_format=1`).
4. APK podpísané iným kľúčom sa **nedá nainštalovať cez beta verziu** —
   testeri musia betu raz odinštalovať. Ak chceš beta kanál zachovať
   oddelene, stačí nechať tento beta kľúč pre GitHub APK.

Keď chceš len vymeniť beta kľúč (napr. aby nebol verejný), nastav secret
`ANDROID_DEBUG_KEYSTORE_B64` — platí rovnaké upozornenie: testeri musia
jednorazovo odinštalovať.
