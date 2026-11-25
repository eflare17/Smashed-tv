class_name VoxelDemolitionMob
extends Node
## The block's enemies (Demolition, phase B; the owner, 24 Nov, of the first version: enemies on the rooftops and in
## the windows). They stand posts on the buildings -- on the roof tiles, in the windows of the upper storeys -- and a
## few walk the street. The point of them is that they go down with the building: every post is a block or a roof tile
## of VoxelBreakables, and the moment the thing holding an enemy up is knocked out (a shot, a blast, the wrecking ball,
## or the roof caving in once the walls have gone) the enemy is let go into the air, falls like anything else knocked
## flying, and is hurt FALL_HURT a metre on the way down. Off the tower block that kills; off the timber shed it only
## breaks them, and whoever gets up comes at you.
##
## They come as you get near: a post within NEAR of you fills, one every GAP seconds so nothing hitches, at most
## ALIVE_CAP alive at a time and MOST in a run (half of each on the web and on a phone: a body is dear to make and
## dearer to draw). Kills count into Demolition's score (VoxelDemolition.score) and show on its HUD line.
##
## What moves them: nothing in the arena does. Demolition freezes the arena (as St Kilda and the gun range do) and
## these bodies are marked "riding" for as long as they live, so VoxelArena leaves them where they are but for
## react_step -- which is what flies them, lands them and lays them out. The standing ones are turned to face you; the
## walkers are walked here, and marked "walks" so the arena animates their stride through the freeze. No threads, no
## physics bodies, nothing made each frame: web-safe.

const KINDS := ["grunt", "grunt", "swarmer", "batter"]      # (light kinds: no boss, no brute, nothing that throws)
const ROOF := 0
const WINDOW := 1
const STREET := 2
const ALIVE_CAP := 12            # alive at once ...
const MOST := 26                 # ... and in a run
const ALIVE_CAP_WEB := 6
const MOST_WEB := 12
const NEAR := 34.0               # m: a post this near you fills
const GAP := 0.4                 # s between one spawn and the next (no hitch)
const PER_ROOF := 3              # posts a roof at most ...
const PER_WINDOW := 3            # ... and windows a building
const FALL_FREE := 1.2           # m you can fall for nothing
const FALL_HURT := 34.0          # health a metre past that (a two-storey roof kills; a shed's doesn't quite)
const REACH := 1.5               # m a walker swings at you from
const SWING := 7.0               # health a swing takes
const SWING_EVERY := 1.3         # s between swings
const DROP_OUT := 1.2            # m/s out from the wall a let-go enemy goes (they don't just sink)

var level: VoxelDemolition
var posts: Array = []            # [{at, kind, bi, c, row, tile, taken}]
var mobs: Array = []             # [{b, post, air, from_y, hurt, walks, swing, next}]
var kills := 0
var made := 0                    # bodies made this run
var dropped := 0                 # posts that fell out from under their enemy (the tests)
var fell_dead := 0               # ... and the enemies the fall killed
var _cool := 0.0
var _rng := RandomNumberGenerator.new()

func setup(l: VoxelDemolition) -> void:
	level = l
	name = "Mob"
	_rng.seed = 20261125

func small() -> bool:
	return OS.has_feature("web") or VoxelTouch.active

func alive_cap() -> int:
	return ALIVE_CAP_WEB if small() else ALIVE_CAP

func most() -> int:
	return MOST_WEB if small() else MOST

# ---------------------------------------------------------------- the posts

## Every post in the block, worked out once from the buildings themselves (the level's roof_spots / window_spots /
## street_spots are these, as points).
func build_posts() -> void:
	posts.clear()
	var bs: Array = level.breaks.list
	for bi in bs.size():
		var b: VoxelBreakables.Building = bs[bi]
		# the roof: up to PER_ROOF tiles, spread over it (a tile is 2 m: an enemy stands on one)
		var tiles: Array = b.roof_tiles
		if tiles.size() > 0:
			var n := mini(PER_ROOF, tiles.size())
			for k in n:
				var ti := int(float(k + 1) * tiles.size() / float(n + 1))
				var t: Vector3 = tiles[ti]
				posts.append({"at": Vector3(t.x, b.h + 0.05, t.z), "kind": ROOF, "bi": bi, "c": -1, "row": -1,
					"tile": ti, "taken": false})
		# the windows of the upper storeys: on the sill, just inside the glass
		var wins := []
		for c in b.cols.size():
			var cc: Dictionary = b.cols[c]
			if not bool(cc.glass):
				continue
			for r in range(1, b.rows):
				if b._block_col(c, r) != VoxelBreakables.GLASS or b.alive[c * b.rows + r] == 0:
					continue
				var n2: Vector2 = cc.n
				var at: Vector3 = b.block_at(c, r)
				wins.append({"at": Vector3(at.x - n2.x * 0.9, r * b.bh + 0.05, at.z - n2.y * 0.9), "kind": WINDOW,
					"bi": bi, "c": c, "row": r, "tile": -1, "taken": false})
		# (spread round the building, not three in a row: every nth of them)
		if wins.size() > PER_WINDOW:
			var pick := []
			for k in PER_WINDOW:
				pick.append(wins[int(float(k) * wins.size() / float(PER_WINDOW)) + wins.size() / (PER_WINDOW * 2)])
			wins = pick
		posts.append_array(wins)
	# the street: one in front of every other building, out on the road
	for bi in bs.size():
		if bi % 2 == 1:
			continue
		var b: VoxelBreakables.Building = bs[bi]
		var mid := Vector2.ZERO
		for v in b.ring:
			mid += v
		mid /= b.ring.size()
		var side := signf(mid.y - VoxelDemolition.AT.z)
		posts.append({"at": Vector3(mid.x, 0.05, VoxelDemolition.AT.z + side * 3.0), "kind": STREET, "bi": bi,
			"c": -1, "row": -1, "tile": -1, "taken": false})

func spots(kind: int) -> Array:
	var out := []
	for p in posts:
		if int(p.kind) == kind:
			out.append(p.at)
	return out

# ---------------------------------------------------------------- coming and going

## A new run: nobody about, every post free.
func reset() -> void:
	clear()
	if posts.is_empty():
		build_posts()
	for p in posts:
		p.taken = false

## Every enemy of this level's gone (going home, starting again).
func clear() -> void:
	for m in mobs:
		var b: VoxelBody = m.b
		if b != null and is_instance_valid(b):
			level.arena.bodies.erase(b)
			b.queue_free()
	mobs.clear()
	kills = 0
	made = 0
	dropped = 0
	fell_dead = 0
	_cool = 0.0

func alive_now() -> int:
	var n := 0
	for m in mobs:
		var b: VoxelBody = m.b
		if b != null and is_instance_valid(b) and b.alive:
			n += 1
	return n

## One enemy on a post (the tests put them where they want them).
func fill(post: Dictionary) -> VoxelBody:
	var key: String = KINDS[_rng.randi() % KINDS.size()]
	var b := level.arena.spawn_kind(key, post.at)
	b.set_meta("range", true)        # (not in the arena's square: it isn't dragged back into it, alive or dead)
	b.set_meta("riding", true)       # (the arena leaves it where it's put: this file moves it)
	b.yaw = 0.0
	b.died.connect(_died, CONNECT_ONE_SHOT)
	post.taken = true
	made += 1
	mobs.append({"b": b, "post": post, "air": false, "from_y": float(post.at.y), "hurt": false,
		"walks": int(post.kind) == STREET, "loose": int(post.kind) == STREET, "swing": _rng.randf_range(0.3, 1.2)})
	if int(post.kind) == STREET:
		b.set_meta("walks", true)
	return b

func _died(_b: VoxelBody) -> void:
	if level.running:
		kills += 1

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	if level.breaks == null:
		return
	if level.running:
		_spawn_step(dt)
	var me: Vector3 = level.arena.player.global_position
	var i := 0
	while i < mobs.size():
		var m: Dictionary = mobs[i]
		var b: VoxelBody = m.b
		if b == null or not is_instance_valid(b):
			mobs.remove_at(i)
			continue
		if b.alive:
			_hold(m, b, me, dt)
		i += 1

# a post near you fills, one at a time
func _spawn_step(dt: float) -> void:
	_cool = maxf(0.0, _cool - dt)
	if _cool > 0.0 or made >= most() or alive_now() >= alive_cap():
		return
	var me: Vector3 = level.arena.player.global_position
	var best: Dictionary = {}
	var best_d := NEAR * NEAR
	for p in posts:
		if bool(p.taken):
			continue
		var d: float = (p.at as Vector3).distance_squared_to(me)
		if d < best_d:
			best_d = d
			best = p
	if best.is_empty():
		return
	fill(best)
	_cool = GAP

# one enemy: is what it stands on still there, is it in the air, has it landed, what does it do
func _hold(m: Dictionary, b: VoxelBody, me: Vector3, dt: float) -> void:
	var post: Dictionary = m.post
	if not bool(m.loose) and not b.airborne and not _held_up(post):
		_let_go(m, b)                # (once only: the post is gone, it never stands on it again)
	if b.airborne:
		m.air = true
		return
	if bool(m.air):
		m.air = false
		var drop := float(m.from_y) - b.position.y
		if not bool(m.hurt):
			m.hurt = true
			if drop > FALL_FREE:
				var was := b.alive
				b.hurt((drop - FALL_FREE) * FALL_HURT)
				if was and not b.alive:
					fell_dead += 1
			level.arena.sound.play("thwack", b.position + Vector3.UP, -6.0, _rng.randf_range(0.8, 1.1))
		if b.alive:
			m.walks = true           # (it lived: it gets up and comes at you)
			b.set_meta("walks", true)
	if b.floored():
		return                       # (lying where it landed, getting up)
	var to := Vector3(me.x - b.position.x, 0.0, me.z - b.position.z)
	var d := to.length()
	if d > 0.01:
		b.yaw = lerp_angle(b.yaw, atan2(to.x, to.z), 1.0 - exp(-dt * 6.0))
	if not bool(m.walks):
		b.attack = 0.0
		return
	# a walker: along the street at you, apart from the others, a swing when it gets there
	if d > REACH:
		var mv := to / d * b.speed * b.move_factor()
		for o in mobs:
			var ob: VoxelBody = o.b
			if ob == b or ob == null or not is_instance_valid(ob) or not ob.alive:
				continue
			var away := b.position - ob.position
			away.y = 0.0
			var dl := away.length()
			if dl < 0.8 and dl > 0.001:
				mv += away / dl * (0.8 - dl) * 6.0
		b.position += mv * dt
		b.odo += mv.length() * dt
		b.attack = 0.0
	else:
		m.swing = maxf(0.0, float(m.swing) - dt)
		var a0 := b.attack
		b.attack = fmod(b.attack + dt * 1.6, 1.0)
		if a0 < 0.55 and b.attack >= 0.55 and float(m.swing) <= 0.0 and not level.arena.godmode:
			m.swing = SWING_EVERY
			level.arena.hurt_players_near(b.position + Vector3(0, 0.9, 0), REACH + 0.8, SWING)

## Is the block (or roof tile) this post stands on still standing?
func _held_up(post: Dictionary) -> bool:
	var bi := int(post.bi)
	if bi < 0 or bi >= level.breaks.list.size():
		return true
	var b: VoxelBreakables.Building = level.breaks.list[bi]
	match int(post.kind):
		ROOF:
			var t := int(post.tile)
			return t >= 0 and t < b.roof_on.size() and b.roof_on[t] == 1
		WINDOW:
			var i := int(post.c) * b.rows + int(post.row)
			return i >= 0 and i < b.alive.size() and b.alive[i] == 1
	return true

# what held it up has gone: into the air, out from the wall a little, turning over
func _let_go(m: Dictionary, b: VoxelBody) -> void:
	dropped += 1
	m.from_y = b.position.y
	m.hurt = false
	m.air = true
	m.loose = true
	b.set_meta("walks", true)        # (the arena animates it through the level's freeze: it's flying, then walking)
	var out := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	if out.length() < 0.1:
		out = Vector3.FORWARD
	b.launch(out.normalized() * DROP_OUT + Vector3(0.0, -0.4, 0.0), _rng.randf_range(2.0, 5.0))
