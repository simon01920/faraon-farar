class_name FaraonDeck
extends RefCounted
## Builds and shuffles the 32-card deck. Pure logic, deterministic when
## seeded — the server owns the seed, clients never shuffle.


static func build() -> Array[String]:
	var cards: Array[String] = []
	for suit in FaraonCard.Suit.values():
		for rank in FaraonCard.Rank.values():
			cards.append(FaraonCard.make_id(rank, suit))
	return cards


static func shuffled(seed_value: int) -> Array[String]:
	var cards := build()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
	return cards
