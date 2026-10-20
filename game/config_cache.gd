class_name ConfigCache
extends RefCounted
## In-memory cache of the persisted user:// ConfigFiles (settings,
## progression, monetization). Every store getter used to re-read and re-parse
## its file from disk, and the hot paths call those getters a lot — each card
## visual resolves the active skin, every haptic buzz checks the vibration
## toggle, every placed card picks its sound by the table look — so a single
## table refresh cost dozens of flash reads on a phone. Now each file is parsed
## once per process; the stores keep writing through `cfg.save(path)` on the
## same cached instance, so memory and disk never disagree.
##
## Code that changes a file behind the stores' back (tests deleting saves)
## must call invalidate() afterwards.

static var _files := {}


## The parsed file at `path`; a missing file yields an empty ConfigFile, so
## every getter falls back to its default exactly as before.
static func get_file(path: String) -> ConfigFile:
	var cfg: ConfigFile = _files.get(path)
	if cfg == null:
		cfg = ConfigFile.new()
		cfg.load(path)
		_files[path] = cfg
	return cfg


## Drops the cached copy of `path` ("" = all files) so the next read hits
## the disk again.
static func invalidate(path := "") -> void:
	if path == "":
		_files.clear()
	else:
		_files.erase(path)
