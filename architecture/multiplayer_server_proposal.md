# Multiplayer server — architektonické odporúčanie (krok 8, čaká na schválenie)

Podľa `faraon_multiplayer_server_prompt.md`: pred-multiplayerové fixy sú hotové
a otestované (animácie rozdávania/ťahania, faraón-interrupt, two-row UI, crash
diagnostika, Android build). Toto je odpoveď na otvorené otázky z bodov 1 a 4 +
návrh štruktúry z bodu 3. **Implementácia začne až po Simonovom potvrdení.**

## Overený stav Godot dokumentácie (bod 8.1)

- `WebSocketMultiplayerPeer.create_server(port, bind_address := "*", tls_server_options: TLSOptions = null)`
  a `create_client(url, tls_client_options := null)` — TLS je možné priamo v Godote,
  klient verifikuje certifikát proti hostname pri `wss://`.
- Dedicated server export mode automaticky pridáva feature tag `dedicated_server`
  (`OS.has_feature("dedicated_server")`) a vie stripnúť textúry/vizuálne resources
  z PCK — presne pattern z promptu.
- Polling: keď je peer priradený do `multiplayer.multiplayer_peer`, SceneTree ho
  polluje automaticky každý frame (`SceneTree.multiplayer_poll` je default true) —
  manuálny `poll()` netreba na žiadnej strane; treba ho len NEvypnúť.

## Odpoveď na bod 1: model (A) — jeden dlhobežiaci proces, viac room-ov v ňom

**Odporúčam (A).** Dôvody:
- Faraón room = 2–5 hráčov, ťahová hra, stav jednej room je jeden malý `GameState`
  dict. Jeden headless Godot proces utiahne stovky takýchto room-ov — škálovanie
  na procesy by riešilo problém, ktorý pri tomto rozsahu neexistuje.
- Matchmaking pri (A) sú dve RPC (`create_room`, `join_room(code)`) v tom istom
  procese — žiadna samostatná matchmaking služba, žiadne prideľovanie portov,
  žiadny orchestrátor procesov. Jeden systemd unit, jeden deploy, jeden log.
- Pre sólo vývojára bez DevOps skúsenosti je (B) výrazne viac pohyblivých častí
  (spawner, port pool, health-checky, cleanup zombie procesov) bez prínosu pre
  túto veľkosť hry.
- Upgrade cesta zostáva otvorená: room je zapuzdrená v `faraon_room.gd`, takže
  neskorší prechod na (B) znamená vymeniť room_manager, nie prepisovať hru.

## Odpoveď na bod 4: Nginx reverse proxy terminuje TLS — áno

**Odporúčam Nginx + Certbot.** Dôvody:
- Certbot obnovuje certifikát proti Nginx bez akéhokoľvek zásahu do Godot procesu.
  Pri priamej TLS terminácii v Godote by bolo treba vlastnú logiku načítania/
  reloadu certifikátu po každej obnove (reštart servera každých ~60 dní alebo
  custom reload) — zbytočná krehkosť.
- Godot počúva na `ws://127.0.0.1:9000` (port 9000, len loopback, nevystavený);
  Nginx na 443 terminuje `wss://` a proxyuje WebSocket upgrade. Firewall: len
  80/443 verejné.
- Nginx je zároveň pripravené miesto pre budúce HTTP endpointy (REST pre
  leaderboardy, health-check, verziu servera).
- Klientská konfigurácia: `wss://faraon.<doména>/ws` v prod, `ws://127.0.0.1:9000`
  len pre lokálny vývoj — oddelené v dev/prod configu, `ws://` sa nesmie dostať
  do release buildu.

## Bod 3: navrhovaná štruktúra `res://server/`

```
res://server/
├── main_server.gd    # vstup: OS.has_feature("dedicated_server") → štart listenera
├── room_manager.gd   # room kódy (bez 0/O/1/I), create/join, peer→room routing
├── faraon_room.gd    # jedna room: sedadlá+roly (player/deck_device), vlastná
│                     # FaraonRules inštancia, reconnect grace 90 s, snapshoty
└── net_protocol.gd   # zdieľané server+klient: názvy RPC, verzia protokolu,
                      # tvarová validácia správ (typy/rozsahy) pred rules enginom
```

- **Zdieľané moduly bez duplicity:** `game/faraon_rules.gd`, `game_state.gd`,
  `messages.gd` sú už čistá logika bez scén — server ich používa tak, ako sú.
  `GameState.view_for(player_id)` (cenzurovaný snapshot) už existuje a je presne
  to, čo sa posiela klientom + celé pri reconnecte.
- **Klient neskôr:** `net/room_client.gd` s rovnakým rozhraním ako
  `LocalGameServer` (signály `state_updated`/`action_rejected`, metóda `propose`)
  — stôl už dnes hovorí len s touto abstrakciou, takže sa nedotkne UI kód.
- **RPC bezpečnosť (bod 7):** návrhy ťahov `@rpc("any_peer", "call_remote",
  "reliable")` s identitou z `multiplayer.get_remote_sender_id()` (nikdy z tela
  správy); broadcasty stavu len z authority; každý vstup najprv tvarovo validuje
  `net_protocol.gd`, až potom ide do `faraon_rules.gd`.
- **Deployment (bod 6, po schválení):** headless Linux "dedicated server" export,
  jednoduchý shell skript + systemd unit (Dockerfile ako voliteľná alternatíva —
  pre jeden proces na jednom VPS je systemd jednoduchší na údržbu), Nginx +
  Certbot postup — všetko do `deployment/README.md`.

**Čakám na potvrdenie voľby (A) a Nginx smeru — potom: server skeleton →
room management → RPC + validácia → reconnect → TLS/Nginx/deployment, s
checkpointmi.**
