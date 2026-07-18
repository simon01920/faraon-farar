class_name FaraonDeck
extends RefCounted
## Builds and shuffles the 32-card deck (D7: optionally 33 with the
## Tanečnica/reverse card). Pure logic, deterministic when seeded — the
## server owns the seed, clients never shuffle.


static func build(include_reverse := false) -> Array[String]:
	var cards: Array[String] = []
	for suit in FaraonCard.Suit.values():
		for rank in FaraonCard.Rank.values():
			cards.append(FaraonCard.make_id(rank, suit))
	if include_reverse:
		cards.append(FaraonCard.REVERSE_ID) # D7a: 33. karta navyše
	return cards


static func shuffled(seed_value: int, include_reverse := false) -> Array[String]:
	var cards := build(include_reverse)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
	return cards
