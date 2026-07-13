class_name Haptics
extends RefCounted
## Tiny vibration helper: every game-feel buzz goes through here so the
## player's "Vibrácie" toggle is honoured in one place. vibrate_handheld is
## a documented no-op on desktop platforms, so no platform check is needed.


static func tap() -> void:
	_vibrate(35)


static func buzz() -> void:
	_vibrate(120)


## Long rumble for the spálená burn moment.
static func rumble() -> void:
	_vibrate(300)


static func _vibrate(ms: int) -> void:
	if GameSettings.get_vibrations_on():
		Input.vibrate_handheld(ms)
