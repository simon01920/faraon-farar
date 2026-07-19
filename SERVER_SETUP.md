# Faraón — multiplayerový server: návod na spustenie a nasadenie

Tento návod ťa prevedie všetkými spôsobmi, ako spustiť multiplayerový server
Faraónu — od lokálneho testu na tvojom PC, cez hranie po Wi‑Fi s telefónom,
až po ostré nasadenie na VPS s `wss://` (TLS).

## Ako to celé funguje (v skratke)

- Server je **ten istý projekt Godot** spustený headless s argumentom
  `--server` (alebo ako dedicated-server export). Neotvára žiadne okno —
  len WebSocket na porte **9000** (default) a hostí všetky roomky naraz.
- Klient (normálne spustená hra) sa pripojí cez **Hrať online**, vytvorí
  roomku s 5-znakovým kódom a kamaráti sa ním pripoja.
- Server je autoritatívny: klienti posielajú len návrhy ťahov, pravidlá
  vyhodnocuje engine na serveri a klientom sa posielajú cenzurované pohľady
  (karty súperov nikdy neopustia server).
- Pri výpadku spojenia má hráč **120 sekúnd** na návrat (session token) —
  miesto aj karty mu ostávajú.

---

## 1. Najrýchlejší štart — Windows (tvoje PC)

V koreňovom priečinku projektu je pripravený skript **`run_server.bat`**:

```bat
run_server.bat          :: server na porte 9000
run_server.bat 9100     :: server na inom porte
```

Skript použije Godot z `C:\Users\simon\Downloads\Godot_v4.7-stable_win64.exe\`.
Ak máš Godot inde, buď uprav cestu v skripte, alebo nastav premennú
prostredia `GODOT_EXE` na plnú cestu ku *konzolovému* exe.

Úspešný štart vypíše:

```
Faraón server listening on port 9000
```

Ukončenie: `Ctrl+C` (alebo zavri okno).

To isté ručne, bez skriptu:

```powershell
& "<godot_console.exe>" --headless --path . -- --server --port=9000
```

> Pozor na samostatné `--` pred `--server` — oddeľuje argumenty hry od
> argumentov enginu. Port sa dá zadať aj premennou prostredia `FARAON_PORT`.

### Test na jednom PC

1. Nechaj bežať `run_server.bat`.
2. Spusti hru normálne (editor / debug build) → **Hrať online**.
   Debug build sa automaticky pripája na `ws://127.0.0.1:9000`.
3. Vytvor roomku, spusti druhú inštanciu hry a pripoj sa kódom.

Automatický smoke test celej cesty (spawn servera, connect, roomka):

```powershell
& "<godot_console.exe>" --path . -s res://tools/mp_probe.gd
```

---

## 2. Hranie po domácej sieti (telefón ↔ PC)

Server beží na PC (bod 1), telefón sa pripája cez Wi‑Fi.

1. **Zisti IP adresu PC** v lokálnej sieti:
   ```powershell
   ipconfig   # hľadaj "IPv4 Address", napr. 192.168.1.42
   ```
2. **Povoľ port vo Windows firewalle** (raz, ako správca):
   ```powershell
   netsh advfirewall firewall add rule name="Faraon server" dir=in action=allow protocol=TCP localport=9000
   ```
3. **Nasmeruj klienta na PC.** Klient číta override z `settings.cfg`,
   sekcia `[dev]`:
   ```ini
   [dev]
   server_url="ws://192.168.1.42:9000"
   ```
   Kde je `settings.cfg` (`user://settings.cfg`):
   - Windows: `%APPDATA%\Godot\app_userdata\Faraón\settings.cfg`
   - Android: `/sdcard/Android/data/sk.pirios.faraon/files/settings.cfg`
     (alebo cez `adb`: `adb shell run-as sk.pirios.faraon ...`)

   Override funguje v debug aj release buildoch — po teste riadok zmaž,
   aby sa klient vrátil na štandardnú adresu.
4. Na telefóne otvor **Hrať online** — pripojí sa na tvoje PC.

---

## 3. Ostré nasadenie na VPS (verejný internet)

Cieľová architektúra (schválená): **jeden headless proces** hostí všetky
roomky, počúva len na loopbacku `:9000`; **Nginx** terminuje `wss://` na
porte 443 s Let's Encrypt certifikátom a preposiela WebSocket dovnútra.
Port 9000 sa nikdy neotvára do internetu.

### 3.1 Zbuilduj linuxovú binárku (na tvojom PC)

```powershell
& "<godot_console.exe>" --headless --path . --export-release "Linux Server" build/faraon_server.x86_64
```

Používa export preset **„Linux Server"** (dedicated_server → naštartuje sa
NetHub namiesto UI). Výsledok: `build/faraon_server.x86_64` (~220 MB,
obsahuje zabalený celý projekt — na funkčnosť to nevadí).

### 3.2 Nastav server (Ubuntu/Debian VPS)

Binárku nahraj na VPS (napr. `scp build/faraon_server.x86_64 root@VPS:/root/`)
a potom:

```bash
# 1) Systémový používateľ + binárka
sudo adduser --system --group --home /opt/faraon faraon
sudo cp faraon_server.x86_64 /opt/faraon/
sudo chmod +x /opt/faraon/faraon_server.x86_64
sudo chown -R faraon:faraon /opt/faraon

# 2) Systemd služba (auto-štart aj auto-restart pri páde)
sudo cp deployment/faraon-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now faraon-server
sudo systemctl status faraon-server      # musí hlásiť "listening on port 9000"
journalctl -u faraon-server -f           # živé logy servera

# 3) Nginx + TLS certifikát
sudo apt install nginx certbot python3-certbot-nginx
sudo cp deployment/nginx-faraon.conf /etc/nginx/sites-available/faraon
sudo nano /etc/nginx/sites-available/faraon   # server_name -> tvoja doména
sudo ln -s /etc/nginx/sites-available/faraon /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d faraon.tvojadomena.sk # vystaví + auto-obnovuje cert

# 4) Firewall — verejné len 80/443, port 9000 NIKDY
sudo ufw allow 80,443/tcp
sudo ufw enable
```

Predpoklad: doména (alebo subdoména) s **A záznamom** mieriacim na IP VPS.

### 3.3 Nasmeruj release klientov na server

V [server/net_protocol.gd](server/net_protocol.gd) nastav pred prvým
release buildom skutočnú adresu:

```gdscript
const PROD_URL := "wss://faraon.tvojadomena.sk/ws"
```

(Cesta `/ws` musí sedieť s `location /ws` v nginx configu.) Debug buildy
ďalej idú na `ws://127.0.0.1:9000`, takže lokálny vývoj to neovplyvní.

### 3.4 Update servera

```bash
scp build/faraon_server.x86_64 root@VPS:/opt/faraon/
sudo systemctl restart faraon-server
```

---

## 4. Riešenie problémov

| Problém | Príčina / riešenie |
|---|---|
| `create_server failed on port 9000` | Port je obsadený (iný beh servera?). Spusti na inom porte: `run_server.bat 9100`, alebo ukonči starý proces. |
| Telefón sa nepripojí na PC | Firewall pravidlo z bodu 2, obe zariadenia na rovnakej Wi‑Fi, správna IP v `server_url`, PC sieť nastavená ako „Private". |
| Klient visí na „Pripájam sa…" | Server nebeží / zlá adresa. Skontroluj `Test-NetConnection <IP> -Port 9000` z PC. |
| `Cannot get keys from nonexistent section "preset.X.options"` | Rozbitá sekcia v `export_presets.cfg` (každý `[preset.N]` musí mať svoju `[preset.N.options]`). Opravené v tomto repe. |
| VPS: služba beží, ale `wss://` nejde | `sudo nginx -t`, platnosť certifikátu (`sudo certbot renew --dry-run`), `server_name` = doména z PROD_URL. |
| Hráč vypadol | Nič netreba — do 120 s sa vráti na svoje miesto (session token + plný snapshot). |

Logy: server loguje na stdout (`journalctl -u faraon-server` na VPS,
konzolové okno na Windows) a Godot file logging zapisuje aj do
`user://logs/`.

## 5. Bezpečnostné poznámky

- Server validuje tvar každej správy (`server/net_protocol.gd`) predtým,
  než sa čohokoľvek dotkne engine — zlá správa nikdy nezhodí proces.
- Karty súperov a balíček sa klientom neposielajú (len počty).
- Na VPS beží proces pod neprivilegovaným používateľom `faraon` a port
  9000 je viazaný len interne; jediný verejný vstup je Nginx s TLS.

Ďalšie build témy (Android APK, export templates, sandbox poznámky):
[deployment/README.md](deployment/README.md).
