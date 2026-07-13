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


## Active card skin id. The default flips to the "Mariáš dvojhlavý" set for
## everyone (new and existing players) once its assets land — existing saves
## only pin a skin after an explicit pick in the UI.
static func get_card_skin() -> String:
	return _load().get_value("app", "card_skin", "dev_preview")


static func set_card_skin(skin_id: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "card_skin", skin_id)
	cfg.save(PATH)


## Dev feature flag: hidden skins (dev_preview) appear in the picker only
## when [dev] show_dev_skins=true is set manually in settings.cfg.
static func dev_skins_enabled() -> bool:
	return _load().get_value("dev", "show_dev_skins", false)


## Bot difficulty for local games: "easy" | "medium" | "hard".
static func get_bot_difficulty() -> String:
	return _load().get_value("app", "bot_difficulty", "medium")


static func set_bot_difficulty(d: String) -> void:
	var cfg := _load()
	cfg.set_value("app", "bot_difficulty", d)
	cfg.save(PATH)
