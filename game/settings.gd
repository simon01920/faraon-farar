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
