# Faraón — deployment a build postupy

## Android debug APK (Windows) — vyriešenie `ERROR: Unable to open Android 'build-tools' directory`

**Diagnóza (2026-07-14):** chyba znamenala, že Godot nenašiel Android SDK — na stroji
nebolo SDK nainštalované vôbec a `editor_settings-4.7.tres` obsahoval starú/rozbitú
cestu `android_sdk_path`. Navyše chýbali export templates pre Godot 4.7.

### Čo je teraz nainštalované a kde

| Súčasť | Cesta |
|---|---|
| Android SDK (cmdline-tools, platform-tools, build-tools 35.0.0, platforms android-35) | `C:\Users\simon\Downloads\android-sdk` |
| Godot 4.7 export templates | `%APPDATA%\Godot\export_templates\4.7.stable\` |
| Debug keystore (alias `androiddebugkey`, heslo `android`) | `C:\Users\simon\.android\debug.keystore` |
| JDK | Amazon Corretto 25 (`C:\Program Files\Amazon Corretto\jdk25.0.3_9`) |

Editor settings (`%APPDATA%\Godot\editor_settings-4.7.tres`) majú nastavené:
```
export/android/android_sdk_path = "C:/Users/simon/Downloads/android-sdk"
export/android/java_sdk_path = "C:/Program Files/Amazon Corretto/jdk25.0.3_9"
export/android/debug_keystore = "C:/Users/simon/.android/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
```

`gradle_build/use_gradle_build` v export presete je **vypnuté** — bez Android
pluginov ho netreba a ne-gradle export je jednoduchší a menej citlivý na verziu JDK.

### Export (CLI)

```powershell
& "<godot_console.exe>" --headless --path . --export-debug "Android" build/faraon.apk
```

Overené: debug APK ~95 MB sa zbuilduje a podpíše `apksigner`-om bez chýb.

### Zopakovanie od nuly na inom stroji

1. Stiahni Android command-line tools (Windows) z
   https://developer.android.com/studio#command-line-tools-only a rozbaľ do
   `<sdk>\cmdline-tools\latest\` (dôležité: obsah zipu patrí do podpriečinka `latest`).
2. `"<sdk>\cmdline-tools\latest\bin\sdkmanager.bat" --licenses` — odsúhlas všetky (y).
3. `"<sdk>\cmdline-tools\latest\bin\sdkmanager.bat" "platform-tools" "build-tools;35.0.0" "platforms;android-35"`
4. Over, že existuje `<sdk>\build-tools\35.0.0\apksigner.bat` — presne tento súbor
   Godot hľadá, keď hlási „Unable to open Android 'build-tools' directory".
5. V Godote: Editor → Editor Settings → Export → Android → nastav `Android SDK Path`
   na `<sdk>` a `Java SDK Path` na nainštalované JDK (17+).
6. Debug keystore (ak neexistuje):
   ```powershell
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android `
     -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android `
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999
   ```
7. Nainštaluj export templates: Editor → Manage Export Templates → Download and
   Install (alebo rozbaľ `Godot_v4.7-stable_export_templates.tpz` — je to zip — do
   `%APPDATA%\Godot\export_templates\4.7.stable\`).
8. Testovací export príkazom vyššie.

### Poznámka k sandboxu (dôležité pri práci cez Claude)

Zápisy do `%LOCALAPPDATA%` z Claude sedenia idú do MSIX overlay
(`C:\Users\simon\AppData\Local\Packages\Claude_...\LocalCache\Local\...`) a natívne
spustený Godot ich nevidí. Preto je SDK úmyselne v `C:\Users\simon\Downloads\android-sdk`
(nevirtualizovaná cesta, viditeľná pre oba svety). `%APPDATA%` (Roaming) sa
nevirtualizuje — templates a editor settings sú v skutočných priečinkoch.
