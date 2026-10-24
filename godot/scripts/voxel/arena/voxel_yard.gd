class_name VoxelYard
extends Node3D
## The back yard (the owner, 21 Oct, Stage 4: digging, the outside area): through a back door in the arena's south
## wall, east of the bedroom, a fenced garden whose middle is ground you dig (VoxelTerrain), grass round it, a tool
## bench by the door (E: make a better shovel). Like the bedroom, a safe place: the enemies stay in the arena.
##
## Digging in co-op: a dig or a fill is the same call in both games (VoxelTerrain is the same everywhere it starts
## and digs commute), so only the call is sent, either way; each player keeps what their own digging brings up. The
## host sends each chunk's fingerprint every few seconds and a guest whose chunk differs gets it whole. A guest joining
## gets every chunk dug so far; a guest's own yard is kept while they're away and back when they leave. The yard's
## dug chunks are saved with the backpack and chests. Owned by the voxel session.

const X0 := 5.2                 # the yard (world metres) ...
const X1 := 22.5
const Z0 := 22.5
const Z1 := 40.0
const DOOR_X0 := 12.0           # the back door in the arena's south wall
const DOOR_X1 := 13.45
const DIG_ORIGIN := Vector3(5.85, -3.0, 23.25)    # VoxelTerrain's corner: 16 x 16 m of it in the middle of the yard
const BENCH := Vector3(15.6, 0, 23.05)            # the tool bench, against the wall by the door
const SUM_T := 3.0              # seconds between the host's fingerprints

## Better shovels at the bench: the tier, what it takes, what it says.
const UPGRADES := [
	{"tier": 1, "name": "Good shovel", "cost": {"stone": 150, "bone": 500}, "desc": "a proper steel shovel: bigger scoops, quicker"},
	{"tier": 2, "name": "Golden shovel", "cost": {"gold": 80, "brain": 500}, "desc": "silly: huge scoops, very quick, even through stone"},
]

var arena: Node3D
var ground: VoxelTerrain
var farm: VoxelFarm
var chickens: VoxelChickens
var shredder: VoxelShredder
var barbecue: VoxelBarbecue
var _sum_t := 0.0
var _own = null                 # guest: their own yard's dug chunks while in someone else's (null: not a guest)
var _was_role := ""
var _op := 0                    # this player's own digs, fills and tills so far ...
var _op_at := {}                # ... chunk -> the last of them that changed it
var _asked := {}                # (a guest's) chunk -> _op when it asked the host for it

## In the yard (or its doorway): the enemies keep out and don't go for anyone here.
static func in_yard(p: Vector3) -> bool:
	return p.z > 21.6 and p.x > X0 and p.x < X1 + 0.3 and p.z < Z1 + 0.3

func setup(arena_: Node3D) -> void:
	arena = arena_
	ground = VoxelTerrain.new()
	add_child(ground)
	ground.setup(DIG_ORIGIN)
	_surround()
	_bench()
	farm = VoxelFarm.new()
	add_child(farm)
	farm.setup(arena, self)
	chickens = VoxelChickens.new()
	add_child(chickens)
	chickens.setup(arena, self)
	shredder = VoxelShredder.new()
	add_child(shredder)
	shredder.setup(arena)
	barbecue = VoxelBarbecue.new()
	add_child(barbecue)
	barbecue.setup(arena)

# ---------------------------------------------------------------- digging (the tools call these)

## This player's dig: blocks out of the ground (what came up is theirs), told to the other game.
func dig(c: Vector3, r: float, hardest: int) -> Dictionary:
	var got := ground.dig(c, r, hardest)
	_msg(["dig", c, r, hardest])
	if not (got._cells as Array).is_empty():
		_mine(ground.cell_of(c - Vector3.ONE * r), ground.cell_of(c + Vector3.ONE * r))
	return got

## This player's fill: up to n dirt blocks back in (n from their backpack). Returns how many went in.
func fill(c: Vector3, r: float, n: int) -> int:
	var k := ground.fill(c, r, n)
	if k > 0:
		_msg(["fill", c, r, k])
		_mine(ground.cell_of(c - Vector3.ONE * r), ground.cell_of(c + Vector3.ONE * r))
	return k

## This player's hoe: the planting spots in keys tilled (Stage 5), told to the other game.
func till(keys: Array) -> int:
	var sc := int(VoxelFarm.SPOT / VoxelTerrain.CELL)
	var n := ground.till(keys, sc)
	if n > 0:
		_msg(["till", keys])
		for key in keys:
			var at := Vector3i(int(key) / 1000 * sc, 0, int(key) % 1000 * sc)
			_mine(at, at + Vector3i(sc - 1, 0, sc - 1))
	return n

# this player's own change over these blocks: the chunks they're in changed here (a guest: the host's copy of one, sent
# before the host had this, is older than ours)
func _mine(lo: Vector3i, hi: Vector3i) -> void:
	_op += 1
	var cs := VoxelTerrain.CS
	for cz in range(clampi(lo.z, 0, VoxelTerrain.NZ - 1) / cs, clampi(hi.z, 0, VoxelTerrain.NZ - 1) / cs + 1):
		for cx in range(clampi(lo.x, 0, VoxelTerrain.NX - 1) / cs, clampi(hi.x, 0, VoxelTerrain.NX - 1) / cs + 1):
			_op_at[cz * (VoxelTerrain.NX / cs) + cx] = _op

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_yard(m)

func on_net(m: Array) -> void:
	var host: bool = arena.net.role == "host"
	match String(m[0]):
		"dig":
			ground.dig(m[1], float(m[2]), int(m[3]))
		"fill":
			ground.fill(m[1], float(m[2]), int(m[3]))
		"till":
			ground.till(m[1], int(VoxelFarm.SPOT / VoxelTerrain.CELL))
		"all":
			if not host:
				if _own == null:
					_own = ground.changed_chunks()
				ground.load_chunks(m[1])
		"sum":
			if not host:
				var theirs: PackedInt64Array = m[1]
				var want := []
				for c in mini(theirs.size(), ground.chunk_count()):
					if ground.chunk_hash(c) != theirs[c]:
						want.append(c)
				if not want.is_empty():
					for c in want:
						_asked[c] = _op
					_msg(["want", want])
		"want":
			if host:
				for c in m[1]:
					var b := ground.chunk_bytes(int(c))
					_msg(["chunk", int(c), b.compress(FileAccess.COMPRESSION_ZSTD)])
		"chunk":
			if not host:
				# (ours changed since we asked: the host's is from before that reached it, so not put over ours; the next
				# fingerprints check it again)
				if int(_op_at.get(int(m[1]), -1)) > int(_asked.get(int(m[1]), -1)):
					return
				var raw: PackedByteArray = m[2]
				ground.set_chunk_bytes(int(m[1]), raw.decompress(VoxelTerrain.CS * VoxelTerrain.NY * VoxelTerrain.CS, FileAccess.COMPRESSION_ZSTD))

func _process(dt: float) -> void:
	var role: String = arena.net.role if arena.net and arena.net.linked else ""
	if role != _was_role:
		if _was_role == "guest" and _own != null:
			ground.load_chunks(_own)          # (back from someone else's: our own yard again)
			_own = null
		_was_role = role                      # (a guest coming gets it all from send_all, on their hello)
	if role == "host":
		_sum_t += dt
		if _sum_t >= SUM_T:
			_sum_t = 0.0
			_msg(["sum", ground.hashes()])

## A guest just came (the host's): every chunk dug so far.
func send_all() -> void:
	if arena.net and arena.net.role == "host":
		_msg(["all", ground.changed_chunks()])

## For the save file: the dug chunks, base64 (a guest in someone's game: its own yard).
func save_data() -> Dictionary:
	var d: Dictionary = _own if _own != null else ground.changed_chunks()
	var out := {}
	for c in d:
		out[str(c)] = Marshalls.raw_to_base64(d[c])
	return out

func load_data(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	var chunks := {}
	for k in d:
		chunks[int(k)] = Marshalls.base64_to_raw(String(d[k]))
	ground.load_chunks(chunks)

# ---------------------------------------------------------------- the bench

## Looking at the tool bench within reach.
func bench_at(eye: Vector3, dir: Vector3, reach := 2.4) -> bool:
	var box := AABB(BENCH + Vector3(-0.9, 0, -0.4), Vector3(1.8, 1.1, 0.8))
	var hit = box.intersects_ray(eye, dir)
	return hit != null and (hit as Vector3).distance_to(eye) <= reach

# ---------------------------------------------------------------- building it

func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _solid(size: Vector3, at: Vector3, m: Material, parent: Node3D = self, show := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = at
	parent.add_child(sb)
	if show:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = m
		sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	return sb

func _surround() -> void:
	# grass round the dug ground (its top is the ground's top: level with the floor)
	var grass := _mat(Color8(62, 110, 40), 0.95)
	var gx0 := DIG_ORIGIN.x
	var gz0 := DIG_ORIGIN.z
	var gx1 := gx0 + VoxelTerrain.NX * VoxelTerrain.CELL
	var gz1 := gz0 + VoxelTerrain.NZ * VoxelTerrain.CELL
	for r in [Rect2(X0, Z0, X1 - X0, gz0 - Z0), Rect2(X0, gz1, X1 - X0, Z1 - gz1), Rect2(X0, gz0, gx0 - X0, gz1 - gz0), Rect2(gx1, gz0, X1 - gx1, gz1 - gz0)]:
		if r.size.x > 0.01 and r.size.y > 0.01:
			_solid(Vector3(r.size.x, 0.5, r.size.y), Vector3(r.position.x + r.size.x * 0.5, -0.25, r.position.y + r.size.y * 0.5), grass)
	# under it all, a floor nothing falls through
	_solid(Vector3(X1 - X0, 0.4, Z1 - Z0), Vector3((X0 + X1) * 0.5, -3.25, (Z0 + Z1) * 0.5), grass, self, false)
	# a timber fence round the east and south (the bedroom's wall and the arena's are the other sides)
	var wood := _mat(Color8(150, 112, 70), 0.85)
	var post := _mat(Color8(110, 80, 50), 0.85)
	# (the east one with the chicken run's gate in it: VoxelChickens)
	var g0 := VoxelChickens.GATE_Z0
	var g1 := VoxelChickens.GATE_Z1
	_solid(Vector3(0.1, 1.8, g0 - Z0), Vector3(X1 + 0.05, 0.9, (Z0 + g0) * 0.5), wood)
	_solid(Vector3(0.1, 1.8, Z1 - g1), Vector3(X1 + 0.05, 0.9, (g1 + Z1) * 0.5), wood)
	_solid(Vector3(X1 - X0 + 0.2, 1.8, 0.1), Vector3((X0 + X1) * 0.5, 0.9, Z1 + 0.05), wood)
	_solid(Vector3(0.1, 1.8, Z1 - Z0), Vector3(X0 - 0.05, 0.9, (Z0 + Z1) * 0.5), wood, self, false)   # (behind the bedroom's wall)
	var z := Z0
	while z <= Z1:
		if z > g0 - 0.2 and z < g1 + 0.2:
			z += 2.0
			continue
		var pm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 1.95, 0.14)
		pm.mesh = bm
		pm.material_override = post
		pm.position = Vector3(X1 + 0.05, 0.975, z)
		add_child(pm)
		z += 2.0
	for gz in [g0 - 0.07, g1 + 0.07]:
		_solid(Vector3(0.16, 2.0, 0.14), Vector3(X1 + 0.05, 1.0, gz), post)
	var x := X0
	while x <= X1:
		var pm2 := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.14, 1.95, 0.14)
		pm2.mesh = bm2
		pm2.material_override = post
		pm2.position = Vector3(x, 0.975, Z1 + 0.05)
		add_child(pm2)
		x += 2.0
	# the outside of the bedroom's east wall, the yard side (painted)
	var mi := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.02, 2.7, Z1 - Z0)
	mi.mesh = wm
	mi.material_override = _mat(Color8(214, 206, 190), 0.95)
	mi.position = Vector3(X0 + 0.01, 1.35, (Z0 + Z1) * 0.5)
	add_child(mi)

func _bench() -> void:
	var wood := _mat(Color8(140, 98, 58), 0.8)
	var dark := _mat(Color8(96, 64, 38), 0.8)
	var steel := _mat(Color8(150, 152, 158), 0.4, 0.8)
	var root := Node3D.new()
	root.position = BENCH
	add_child(root)
	_solid(Vector3(1.8, 0.08, 0.7), Vector3(0, 0.9, 0), wood, root)
	for lx in [-0.8, 0.8]:
		for lz in [-0.28, 0.28]:
			_solid(Vector3(0.08, 0.86, 0.08), Vector3(lx, 0.43, lz), dark, root)
	_solid(Vector3(1.7, 0.04, 0.6), Vector3(0, 0.3, 0), dark, root)
	# a pegboard with a few tools on it, a vice
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.9, 0.03)
	board.mesh = bm
	board.material_override = _mat(Color8(196, 160, 110), 0.9)
	board.position = Vector3(0, 1.45, -0.33)
	root.add_child(board)
	for k in 4:
		var t := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.05, 0.4, 0.03)
		t.mesh = tm
		t.material_override = steel if k % 2 == 0 else dark
		t.position = Vector3(-0.6 + k * 0.4, 1.45, -0.3)
		root.add_child(t)
	var vice := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.18, 0.14, 0.2)
	vice.mesh = vm
	vice.material_override = steel
	vice.position = Vector3(0.7, 1.01, 0.1)
	root.add_child(vice)
	var l := Label3D.new()
	l.text = "TOOL BENCH"
	l.font_size = 48
	l.pixel_size = 0.004
	l.outline_size = 8
	l.position = Vector3(0, 1.95, -0.3)
	root.add_child(l)
