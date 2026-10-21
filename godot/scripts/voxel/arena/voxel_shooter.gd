class_name VoxelShooter
extends RefCounted
## Who is holding a weapon (multiplayer, the owner, 21 Oct): every weapon asks its shooter where the eye is, which
## way it looks, where the player stands, the top-down avatar to pose, the aim and the mouse, instead of the arena's
## one camera and player. The local player's shooter reads the arena's own (its camera, its CharacterBody3D, Jared
## top-down, the real mouse); the other player's is filled in from the network every frame (a camera that is never
## current, standing at their eye; a body where they stand; their Jared; their aim and mouse ray). Owned by the voxel
## session.

var arena: Node3D               # VoxelArena
var local := true               # the player at this keyboard (false: the other one, over the network)
var pid := 0                    # player number: 0 the host's, 1 the guest's
var cam: Camera3D               # the eye: where it is and which way it faces
var player: CharacterBody3D     # where they stand (feet)
var avatar: VoxelBody           # their Jared (top-down here; the other player's always)
var weapon := ""                # the weapon id they have out
var _top_down := false
var _mouse_v := Vector2.ZERO
var _aiming := false
var _kick := 0.0
var _look_yaw := 0.0
var _ray := []                  # remote: [origin, dir] of their mouse's ray top-down (or [])
var _floor := Vector3.INF       # remote: where their mouse is on the floor top-down
var _dash := [Vector3.ZERO, 0.0]

## The local player's: the arena's camera, player and avatar.
static func local_for(arena_: Node3D) -> VoxelShooter:
	var s := VoxelShooter.new()
	s.arena = arena_
	s.local = true
	s.cam = arena_.cam
	s.player = arena_.player
	s.avatar = arena_.avatar
	return s

## First person or top-down.
var top_down: bool:
	get:
		return bool(arena.top_down) if local else _top_down
	set(v):
		_top_down = v

## The mouse's recent motion on screen, px/s (a swing's direction).
var mouse_v: Vector2:
	get:
		return arena._mouse_v if local else _mouse_v
	set(v):
		if local:
			arena._mouse_v = v
		else:
			_mouse_v = v

## A gun aimed in (the view closes in).
var aiming: bool:
	get:
		return bool(arena._aiming) if local else _aiming
	set(v):
		if local:
			arena._aiming = v
		else:
			_aiming = v

## The view's kick (only the local player's screen shakes).
var kick: float:
	get:
		return float(arena._kick) if local else _kick
	set(v):
		if local:
			arena._kick = v
		else:
			_kick = v

## Which way they face (top-down with the mouse off the floor).
var look_yaw: float:
	get:
		return float(arena.look_yaw) if local else _look_yaw
	set(v):
		_look_yaw = v

## Where their mouse is on the floor top-down (1.2 m up), INF if off it.
func mouse_floor() -> Vector3:
	if local:
		return arena._mouse_floor()
	return _floor

## Their mouse's ray top-down: [origin, dir], or [] (first person, or unknown).
func mouse_ray() -> Array:
	if local:
		var mp: Vector2 = arena.get_viewport().get_mouse_position()
		return [cam.project_ray_origin(mp), cam.project_ray_normal(mp)]
	return _ray

## Where a gun points from and to: [from, dir], or [] when there's nowhere to aim.
func aim() -> Array:
	if local:
		return arena._aim()
	if top_down:
		var pp := player.global_position + Vector3(0, 1.2, 0)
		if _floor == Vector3.INF:
			return []
		return [pp, (_floor - pp).normalized()]
	return [cam.global_position, -cam.global_transform.basis.z]

## Thrown along vel for secs (a lunge); the other player's goes to their game.
func dash(vel: Vector3, secs: float) -> void:
	if local:
		arena.dash(vel, secs)
	else:
		_dash = [vel, secs]
		if arena.net:
			arena.net.send_dash(pid, vel, secs)

## The ray query exclusions for this player's shots (both players' bodies: shots go through friends).
func exclude() -> Array[RID]:
	var out: Array[RID] = [player.get_rid()]
	if arena.net:
		for s in arena.net.shooters():
			if s != self and is_instance_valid(s.player):
				out.append(s.player.get_rid())
	return out
