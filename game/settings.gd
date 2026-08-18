class_name GameSettings
extends RefCounted
## Persisted player preferences (user://settings.cfg): house-rule toggles and
## locale. In multiplayer the room creator's rule toggles will define the
## room's RulesVariant; joining clients get informed about any mismatch with
## their own preferences before the game starts.

const PATH := "user://settings.cfg"
## Verzia uloženého configu — migrácie bežia raz pri prvom načítaní.
const SETTINGS_VERSION := 2

## Bool pravidlá v poradí zobrazenia: key -> label key (popis = kľúč + "_DESC").
## D9 „eso_reaction" nie je pole enginu — build_variant ho preloží na
## eso_no_counter (vypnutá reakcia = eso sa nedá prebiť + okamžitý efekt).
const RULE_TOGGLES := {
	"purista": "RULE_PURISTA",
	"faraon_blocks_eso": "RULE_FARAON_BLOCKS_ESO",
	"hornik_strict": "RULE_HORNIK_STRICT",
	"spalena_multiply": "RULE_SPALENA_MULTIPLY",
	"red7_on_active_eso": "RULE_RED7_ON_ESO",
	"eso_reaction": "RULE_ESO_REACTION",
	"eso_no_counter": "RULE_ESO_NO_COUNTER",
	"seven_interrupt": "RULE_SEVEN_INTERRUPT",
	"faraon_interrupt": "RULE_FARAON_INTERRUPT",
	"green_king": "RULE_GREEN_KING",
	"green_king_counter": "RULE_GREEN_KING_COUNTER",
	"red_ten": "RULE_RED_TEN",
	"reverse_card": "RULE_REVERSE_CARD",
	"unter_announcer": "RULE_UNTER_ANNOUNCER",
	"pub_mode": "RULE_PUB_MODE",
}

## D15 Hospodské prší konfiguruje D11+D12 samo a vylučuje sa s D13.
const DISABLED_BY_PUB := [
	"unter_announcer", "green_king", "green_king_counter", "red_ten",
]

## Hodnotové pravidlá: key -> [label key, widget, options].
const RULE_VALUES := {
	"initial_hand_size": ["RULE_HAND_SIZE", "slider", [4, 7]],
	"seven_penalty_step": ["RULE_SEVEN_STEP", "segment", [2, 3, 4]],
	"red7_return_scope": ["RULE_RETURN_SCOPE", "segment", ["round", "anyone"]],
	"finish_rule": ["RULE_FINISH", "segment", ["none", "no_seven", "hornik_only"]],
}

## D10 Purista vypína závislé pravidlá (E: konflikty) — UI ich disabluje.
const DISABLED_BY_PURISTA := [
	"faraon_blocks_eso", "spalena_multiply", "red7_on_active_eso",
	"eso_reaction", "eso_no_counter", "seven_interrupt", "faraon_interrupt",
	"green_king", "green_king_counter", "red_ten", "red7_return_scope",
	"unter_announcer", "pub_mode",
]


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH) # missing file is fine — defaults apply
	if int(cfg.get_value("app", "settings_version", 1)) < SETTINGS_VERSION:
		_migrate(cfg)
	return cfg


## v2: default D8 sa zmenil na „len z aktuálneho kola". Staré uložené
## „anyone" bolo len prevzatým starým defaultom (zapisuje sa aj bez vedomej
## voľby), takže sa zahodí — nová hra tak má správne pravidlo od začiatku.
static func _migrate(cfg: ConfigFile) -> void:
	if cfg.has_section_key("rules", "red7_return_scope") \
			and cfg.get_value("rules", "red7_return_scope") == "anyone":
		cfg.erase_section_key("rules", "red7_return_scope")
	cfg.set_value("app", "settings_version", SETTINGS_VERSION)
	cfg.save(PATH)


## Predvolená hodnota pravidla (C2 badge + reset) — jediný zdroj: engine
## DEFAULTS, plus UI-only kľúč eso_reaction (D9, default zapnuté).
static func rule_default(key: String) -> Variant:
	if key == "eso_reaction":
		return true
	return RulesVariant.DEFAULTS.get(key, false)


static func get_rule(key: String) -> bool:
	return _load().get_value("rules", key, rule_default(key))


static func set_rule(key: String, value: bool) -> void:
	var cfg := _load()
	cfg.set_value("rules", key, value)
	cfg.save(PATH)


static func get_rule_value(key: String) -> Variant:
	return _load().get_value("rules", key, rule_default(key))


static func set_rule_value(key: String, value: Variant) -> void:
	var cfg := _load()
	cfg.set_value("rules", key, value)
	cfg.save(PATH)


## C2: „Obnoviť predvolené nastavenia" — zmaže celú sekciu pravidiel.
static func reset_rules() -> void:
	var cfg := _load()
	if cfg.has_section("rules"):
		cfg.erase_section("rules")
	cfg.save(PATH)


static func build_variant() -> RulesVariant:
	var v := RulesVariant.classic()
	for key in RulesVariant.RULE_KEYS:
		if key == "end_on_first_finish":
			continue # runtime flag, nie používateľské pravidlo
		v.set(key, get_rule(key))
	for key in RulesVariant.VALUE_KEYS:
		v.set(key, get_rule_value(key))
	# D9 vypnutá reakcia = eso bez prebíjania (rovnaký engine efekt ako D3).
	if not get_rule("eso_reaction"):
		v.eso_no_counter = true
	return v


static func get_locale() -> String:
	return _load().get_value("app", "locale", "sk")


static func set_locale(locale: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "locale", locale)
	cfg.save(PATH)


## Active card skin id. "Mariáš dvojhlavý" is the default for new AND
## existing players — saves only pin a skin after an explicit pick in the UI.
static func get_card_skin() -> String:
	return _load().get_value("app", "card_skin", "marias_dvojhlavy")


static func set_card_skin(skin_id: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "card_skin", skin_id)
	cfg.save(PATH)


## Dev feature flag: hidden skins (dev_preview) appear in the picker only
## when [dev] show_dev_skins=true is set manually in settings.cfg.
static func dev_skins_enabled() -> bool:
	return _load().get_value("dev", "show_dev_skins", false)


## Dev režim (ladiaci panel v hre): 7 ťukov na nadpis Nastavení alebo
## [dev] dev_mode=true v settings.cfg.
static func dev_mode() -> bool:
	return _load().get_value("dev", "dev_mode", false)


static func set_dev_mode(on: bool) -> void:
	var cfg := _load()
	cfg.set_value("dev", "dev_mode", on)
	cfg.save(PATH)


## Active table look id (TableLook registry).
static func get_table_look() -> String:
	return _load().get_value("app", "table_look", "felt_green")


static func set_table_look(look_id: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "table_look", look_id)
	cfg.save(PATH)


## Audio/haptics toggles (defaults on). Sound/music mute their AudioServer
## buses through apply_audio(), so future sfx/music tracks obey them without
## extra plumbing; vibrations are read by Haptics on every buzz.
static func get_sound_on() -> bool:
	return _load().get_value("app", "sound_on", true)


static func set_sound_on(on: bool) -> void:
	var cfg := _load()
	cfg.set_value("app", "sound_on", on)
	cfg.save(PATH)
	apply_audio()


static func get_music_on() -> bool:
	return _load().get_value("app", "music_on", true)


static func set_music_on(on: bool) -> void:
	var cfg := _load()
	cfg.set_value("app", "music_on", on)
	cfg.save(PATH)
	apply_audio()


static func get_vibrations_on() -> bool:
	return _load().get_value("app", "vibrations_on", true)


static func set_vibrations_on(on: bool) -> void:
	var cfg := _load()
	cfg.set_value("app", "vibrations_on", on)
	cfg.save(PATH)


## Per-bus volumes as linear 0..1 sliders (defaults: music at half so it
## sits under the game, SFX at full).
static func get_music_volume() -> float:
	return _load().get_value("app", "music_volume", 0.5)


static func set_music_volume(v: float) -> void:
	var cfg := _load()
	cfg.set_value("app", "music_volume", clampf(v, 0.0, 1.0))
	cfg.save(PATH)
	apply_audio()


static func get_sfx_volume() -> float:
	return _load().get_value("app", "sfx_volume", 1.0)


static func set_sfx_volume(v: float) -> void:
	var cfg := _load()
	cfg.set_value("app", "sfx_volume", clampf(v, 0.0, 1.0))
	cfg.save(PATH)
	apply_audio()


## Pushes the persisted toggles + volumes onto the AudioServer buses:
## "Zvuky" mutes/scales the SFX bus, "Hudba" the Music bus (both defined
## in default_bus_layout).
static func apply_audio() -> void:
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus != -1:
		AudioServer.set_bus_mute(sfx_bus, not get_sound_on())
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(get_sfx_volume(), 0.001)))
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus != -1:
		AudioServer.set_bus_mute(music_bus, not get_music_on())
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(get_music_volume(), 0.001)))


## Multiplayer server URL: dev builds default to the local ws:// endpoint,
## release builds to the production wss:// URL — ws:// can never leak into a
## release. A manual [dev] server_url in settings.cfg overrides both (LAN
## testing on a phone against a PC-hosted server).
static func get_server_url() -> String:
	var override = _load().get_value("dev", "server_url", "")
	if override is String and override != "":
		return override
	return NetProtocol.DEV_URL if OS.has_feature("debug") else NetProtocol.PROD_URL


## Tutorial seen-flag: the onboarding auto-opens only on the first launch.
static func tutorial_seen() -> bool:
	return _load().get_value("app", "tutorial_seen", false)


static func set_tutorial_seen() -> void:
	var cfg := _load()
	cfg.set_value("app", "tutorial_seen", true)
	cfg.save(PATH)


## Player display name; "" = use the localized default ("Ty"/"You").
static func get_player_name() -> String:
	return _load().get_value("app", "player_name", "")


static func set_player_name(p_name: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "player_name", p_name.strip_edges().left(16))
	cfg.save(PATH)


## Game mode: "normal" | "olympic" | "reverse".
static func get_game_mode() -> String:
	return _load().get_value("app", "game_mode", "normal")


static func set_game_mode(m: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "game_mode", m)
	cfg.save(PATH)


## Opponent (bot) count selected in the menu.
static func get_opponents() -> int:
	return _load().get_value("app", "opponents", 3)


static func set_opponents(n: int) -> void:
	var cfg := _load()
	cfg.set_value("app", "opponents", n)
	cfg.save(PATH)


## Bot difficulty for local games: "easy" | "medium" | "hard".
static func get_bot_difficulty() -> String:
	return _load().get_value("app", "bot_difficulty", "medium")


static func set_bot_difficulty(d: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "bot_difficulty", d)
	cfg.save(PATH)
