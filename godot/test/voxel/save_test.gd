extends SceneTree
## Saves written safely, with backups (VoxelSaveFile; headless: --fixed-fps 60 -s test/voxel/save_test.gd): a save
## goes through a .tmp and leaves none; the first save of a session keeps the old file as .bak1, later ones in the same
## session don't (till BACKUP_EVERY); three backups at most, the oldest dropped; a broken save reads its newest good
## backup; a finished .tmp left by a stop at the wrong moment is read; then the game's own: cash saved, the save broken,
## loaded back from the backup; the mine's ground file broken, its backup loaded. Owned by the voxel session.

var passed := 0
var failed := 0
var arena: Node
var t := 0.0
var step := 0
const P := "user://save_test_x.json"

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("SAVE ok   ", what)
	else:
		failed += 1
		print("SAVE FAIL ", what)

func _clean(path: String) -> void:
	for p in [path, path + ".tmp", path + ".bak1", path + ".bak2", path + ".bak3", path + ".bak4"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""

func _initialize() -> void:
	_clean(P)
	VoxelSaveFile._backed.clear()
	VoxelSaveFile.write_text(P, '{"n": 1}')
	check(_read(P) == '{"n": 1}' and not FileAccess.file_exists(P + ".tmp") and not FileAccess.file_exists(P + ".bak1"), "a first save: in place, no .tmp left, nothing to back up")
	VoxelSaveFile.write_text(P, '{"n": 2}')
	check(_read(P) == '{"n": 2}' and _read(P + ".bak1") == '{"n": 1}', "the first save over an old one keeps it as .bak1")
	VoxelSaveFile.write_text(P, '{"n": 3}')
	check(_read(P) == '{"n": 3}' and _read(P + ".bak1") == '{"n": 1}', "saves in the same session don't back up again")
	for n in [4, 5, 6]:
		VoxelSaveFile._backed.clear()         # (a new session each time)
		VoxelSaveFile.write_text(P, '{"n": %d}' % n)
	check(_read(P + ".bak1") == '{"n": 5}' and _read(P + ".bak2") == '{"n": 4}' and _read(P + ".bak3") == '{"n": 3}' and not FileAccess.file_exists(P + ".bak4"), "three backups at most, newest first")
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string('{"n": 7, "cut off')
	f.close()
	var from := []
	var d = VoxelSaveFile.read_json(P, from)
	check(typeof(d) == TYPE_DICTIONARY and int(d.n) == 5 and from == [P + ".bak1"], "a broken save: its newest good backup read")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(P))
	f = FileAccess.open(P + ".tmp", FileAccess.WRITE)
	f.store_string('{"n": 8}')
	f.close()
	d = VoxelSaveFile.read_json(P)
	check(typeof(d) == TYPE_DICTIONARY and int(d.n) == 8, "stopped between moving the old one away and putting the new in place: the finished .tmp read")
	_clean(P)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	var st = arena.stash
	var path := "user://save_test_game.json"
	match step:
		0:
			_clean(path)
			_clean(path.get_basename() + "_mine.bin")
			VoxelSaveFile._backed.clear()
			st.save_path = path
			arena.cash = 123
			st.save()
			arena.cash = 456
			VoxelSaveFile._backed.clear()     # (the next session's first save: the old one kept)
			st.save()
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string("{ broken")
			f.close()
			arena.cash = 0
			st.load_save()
			check(arena.cash == 123, "the game's save broken: loaded from its backup (cash $%d)" % arena.cash)
			# the mine's ground
			var m: VoxelMine = arena.mine
			m._build()
			var sd := m.ground.seed_
			m._ground_dirty = true
			m._write_ground()
			m.ground.generate(sd + 7, m._flags())
			m._ground_dirty = true
			VoxelSaveFile._backed.clear()
			m._write_ground()
			var gp := m._ground_path()
			f = FileAccess.open(gp, FileAccess.WRITE)
			f.store_string("nonsense")
			f.close()
			check(m._load_ground() and m.ground.seed_ == sd, "the mine's ground file broken: its backup loaded (seed %d)" % m.ground.seed_)
			_clean(path)
			_clean(gp)
			print("SAVE done %d passed, %d failed" % [passed, failed])
			return true
	return false
