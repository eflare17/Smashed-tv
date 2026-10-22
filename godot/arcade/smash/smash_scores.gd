extends RefCounted
## Smash arcade high-score table: top 10 of {name (3 letters), score, room}, kept in its own file in user:// (so
## it can't touch the main game's saves). Starts from a made-up table like an arcade machine fresh from the shop.

const PATH := "user://arcade_smash_scores.cfg"
const SIZE := 10
const SEED := [["SMA", 50000, 6], ["ACE", 40000, 5], ["TVG", 30000, 4], ["BOB", 25000, 4], ["JIM", 20000, 3],
		["KAT", 15000, 3], ["ZED", 10000, 2], ["MOE", 7500, 2], ["LOU", 5000, 1], ["DAN", 2500, 1]]

## Off: the table is neither loaded nor saved (the bench).
var persist := true
var entries: Array = []

func load_table() -> void:
	entries.clear()
	var cf := ConfigFile.new()
	if persist and cf.load(PATH) == OK:
		for i in SIZE:
			var e = cf.get_value("scores", str(i), null)
			if e is Array and e.size() == 3:
				entries.append([str(e[0]).substr(0, 3), int(e[1]), int(e[2])])
	if entries.is_empty():
		for e in SEED:
			entries.append(e.duplicate())

func save_table() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	for i in entries.size():
		cf.set_value("scores", str(i), entries[i])
	cf.save(PATH)

func qualifies(score: int) -> bool:
	return score > 0 and (entries.size() < SIZE or score > int(entries[entries.size() - 1][1]))

## Puts the entry in its place and saves. Returns its rank (0 = top), or -1 if it didn't make the table.
func insert(player_name: String, score: int, room: int) -> int:
	var at := entries.size()
	for i in entries.size():
		if score > int(entries[i][1]):
			at = i
			break
	if at >= SIZE:
		return -1
	entries.insert(at, [player_name, score, room])
	if entries.size() > SIZE:
		entries.resize(SIZE)
	save_table()
	return at
