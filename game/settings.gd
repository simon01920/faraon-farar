class_name GameSettings
extends RefCounted
## Persisted player preferences (user://settings.cfg): house-rule toggles and
## locale. In multiplayer the room creator's rule toggles will define the
## room's RulesVariant; joining clients get informed about any mismatch with
## their own preferences before the game starts.

const PATH := "user://settings.cfg"

## key -> [SK label key, SK description key]; the UI builds itself from this.
const RULE_TOGGLES := {
	"faraon_blocks_eso": "RULE_FARAON_BLOCKS_ESO",
	"hornik_strict": "RULE_HORNIK_STRICT",
	"eso_round_robin": "RULE_ESO_ROUND_ROBIN",
	"spalena_multiply": "RULE_SPALENA_MULTIPLY",
}


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH) # missing file is fine — defaults apply
	return cfg


static func get_rule(key: String) -> bool:
	return _load().get_value("rules", key, false)


static func set_rule(key: String, value: bool) -> void:
	var cfg := _load()
	cfg.set_value("rules", key, value)
	cfg.save(PATH)


static func build_variant() -> RulesVariant:
	var v := RulesVariant.classic()
	var cfg := _load()
	for key in RULE_TOGGLES:
		v.set(key, cfg.get_value("rules", key, false))
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


## Pushes the persisted toggles onto the AudioServer buses: "Zvuky" mutes
## the SFX bus, "Hudba" the Music bus (both defined in default_bus_layout).
static func apply_audio() -> void:
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus != -1:
		AudioServer.set_bus_mute(sfx_bus, not get_sound_on())
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus != -1:
		AudioServer.set_bus_mute(music_bus, not get_music_on())


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
