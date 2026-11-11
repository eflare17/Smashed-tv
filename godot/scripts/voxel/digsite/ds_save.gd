class_name DsSave
extends RefCounted
## The Dig Site kept between games (the owner, 11 Nov: what you dug was gone when you quit): the ground as it's been
## changed from how it's made (DigSiteGrid.modified_chunks, packed as the co-op game sends it to a mate joining, the
## loose dirt with it), the grass worn bare, and where each machine's parked. Beside the game's own save
## (VoxelStorages.save_path + ".digsite"; none where that's none: the tests, --nosave). Your own site only: a
## guest at a mate's doesn't save theirs. Not kept: what's in a bucket or the truck's tray. Owned by the voxel session.

const VERSION := 1

static func path(site: DigSite) -> String:
	var base: String = site.arena.stash.save_path if site.arena and site.arena.get("stash") else ""
	return "" if base == "" else base + ".digsite"

static func save(site: DigSite) -> bool:
	var p := path(site)
	if p == "" or not site.built or site.terrain == null or site._is_guest():
		return false
	var g: DigSiteGrid = site.terrain.grid
	var chunks: PackedByteArray = g.pack_chunks(g.modified_chunks())
	var machines := []
	for m: DsMachine in site.machines.list:
		machines.append([m.id, m.global_position.x, m.global_position.y, m.global_position.z, m.yaw])
	var d := {
		"v": VERSION, "seed": g.get_seed(),
		"chunks_n": chunks.size(), "chunks": chunks.compress(FileAccess.COMPRESSION_ZSTD),
		"wear": site.terrain.wear.compress(FileAccess.COMPRESSION_ZSTD), "wear_n": site.terrain.wear.size(),
		"machines": machines,
	}
	# (written beside it and moved over: a crash half way leaves the last good one)
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(d)
	f.close()
	DirAccess.rename_absolute(p + ".tmp", p)
	return true

## The saved site put back (the ground just made, its machines where they start). -> whether there was one
static func load_into(site: DigSite) -> bool:
	var p := path(site)
	if p == "" or not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return false
	var d = f.get_var()
	f.close()
	if not (d is Dictionary) or int(d.get("v", 0)) != VERSION:
		return false
	var g: DigSiteGrid = site.terrain.grid
	if int(d.get("seed", -1)) != g.get_seed():
		return false                              # (another ground: its changes don't fit this one)
	var n := int(d.get("chunks_n", 0))
	if n > 0:
		var chunks: PackedByteArray = (d.chunks as PackedByteArray).decompress(n, FileAccess.COMPRESSION_ZSTD)
		if chunks.size() != n:
			return false
		g.apply_chunks(chunks)
		g.clear_touched()
		g.mark_all_dirty()
	var wn := int(d.get("wear_n", 0))
	if wn == site.terrain.wear.size() and wn > 0:
		var w: PackedByteArray = (d.wear as PackedByteArray).decompress(wn, FileAccess.COMPRESSION_ZSTD)
		if w.size() == wn:
			site.terrain.wear = w
			site.terrain._wear_due = true
	for rec in d.get("machines", []):
		var m: DsMachine = site.machines.by_id(int(rec[0]))
		if m:
			m.global_position = Vector3(rec[1], rec[2], rec[3])
			m.yaw = rec[4]
			m._pose_now()
	return true
