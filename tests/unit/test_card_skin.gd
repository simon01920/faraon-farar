extends GutTest
## Unit tests for the CardSkin registry (game/card_skin.gd): every registered
## skin must resolve all 32 cards + the back to textures that actually exist,
## so a future set ("Mariáš dvojhlavý") can't ship with holes unnoticed.


func test_every_registered_skin_resolves_all_textures() -> void:
	for skin in CardSkin.all():
		for c in FaraonDeck.build():
			var path: String = skin.texture_path(c)
			assert_true(ResourceLoader.exists(path),
					"%s: missing texture for %s (%s)" % [skin.id, c, path])
		assert_true(ResourceLoader.exists(skin.back_path()),
				"%s: missing card back" % skin.id)


func test_unknown_skin_id_falls_back_to_first_entry() -> void:
	assert_eq(CardSkin.by_id("no_such_skin").id, CardSkin.all()[0].id)


func test_empty_card_id_resolves_to_back() -> void:
	var skin := CardSkin.all()[0]
	assert_eq(skin.texture_path(""), skin.back_path())


func test_dev_preview_is_hidden_from_the_picker() -> void:
	var ids: Array = CardSkin.selectable().map(func(s): return s.id)
	assert_false(ids.has("dev_preview"),
			"dev_preview must not be player-selectable without the dev flag")
