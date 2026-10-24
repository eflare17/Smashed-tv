class_name VoxelSaveFile
## Saves written safely, with backups (the owner, 24 Oct overnight list: "save backups"): a save is written to
## <file>.tmp and only then put in place of the old one, so a crash or a full disk mid-write never leaves half a save;
## the first save of a session and then one every BACKUP_EVERY of play keeps the old file as <file>.bak1 (the older
## ones moved down to .bak2, .bak3). Reading tries the file, then its backups, newest first, until one is good (the
## caller says what good is). Used for the backpack's save (VoxelStorages) and the mine's ground (VoxelMine).
## Owned by the voxel session.

const BACKUPS := 3
const BACKUP_EVERY := 30.0 * 60.0       # seconds of play between backups

static var _backed := {}                # path -> when it was last backed up (Time.get_ticks_msec() / 1000)

## Writes text to path safely (and keeps a backup when one's due)
static func write_text(path: String, text: String) -> bool:
	return write_bytes(path, text.to_utf8_buffer())

static func write_bytes(path: String, b: PackedByteArray) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(b)
	f.close()
	var real := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		var now := Time.get_ticks_msec() / 1000.0
		if not _backed.has(path) or now - float(_backed[path]) >= BACKUP_EVERY:
			_backed[path] = now
			_rotate(path)
		else:
			DirAccess.remove_absolute(real)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real) == OK

## The file moved to .bak1 (.bak1 to .bak2 ...; the oldest dropped)
static func _rotate(path: String) -> void:
	var g := func(k: int) -> String: return ProjectSettings.globalize_path(path if k == 0 else "%s.bak%d" % [path, k])
	if FileAccess.file_exists(g.call(BACKUPS)):
		DirAccess.remove_absolute(g.call(BACKUPS))
	for k in range(BACKUPS - 1, -1, -1):
		if FileAccess.file_exists(g.call(k)):
			DirAccess.rename_absolute(g.call(k), g.call(k + 1))

## The file and its backups, newest first (those that are there)
static func candidates(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k in BACKUPS + 2:
		# (the file; a finished .tmp, there if the game stopped between taking the old file away and putting it in place)
		var p := path if k == 0 else (path + ".tmp" if k == 1 else "%s.bak%d" % [path, k - 1])
		if FileAccess.file_exists(p):
			out.append(p)
	return out

## The save's JSON (a Dictionary) from the file, or the newest backup that reads, or null; which one in `from`
static func read_json(path: String, from: Array = []) -> Variant:
	for p in candidates(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(d) == TYPE_DICTIONARY:
			if p != path:
				push_warning("VoxelSaveFile: %s wouldn't read, loaded its backup %s" % [path, p])
			from.append(p)
			return d
	return null
