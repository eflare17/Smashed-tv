class_name FT
extends RefCounted
## The fighting simulation's records, the HTML game's plain objects as small classes (HTML units, seconds).
## Field names follow Smashed.html so the specs (godot/specs/*.md) read straight onto them.

## One player's input for a step (the HTML input record, localInput0 / shroomInput).
class Inp:
	var mx := 0.0                ## move, -1..1 each (HTML ground axes)
	var my := 0.0
	var ax := 0.0                ## aim: cursor - player (not normalised: its length is the range), or a stick
	var ay := 0.0
	var shoot := false
	var roll := false
	var st := false              ## the aim is a stick (its length is a push 0..1)
	var tc := false              ## touch seen
	var tap := 0                 ## launcher touch tap counter (a new value fires at tx, ty)
	var tx := 0.0
	var ty := 0.0
	var lt := false              ## potato touch: a finger on the landing spot lx, ly
	var lx := 0.0
	var ly := 0.0
	var wsel := ""               ## a weapon to switch to
	var use := false             ## E this step (Protect: pick Gothica up / put her down)

## A player in the fight (newPlayer, L711). The Player node is its body and its picture.
class Fighter:
	var id := 0
	var node: Node3D = null
	var ch := "juicy"
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var fx := 0.0                ## facing
	var fy := 1.0
	var ix := 0.0                ## move input this step
	var iy := 0.0
	var moving := false
	var odo := 0.0
	var roll := 0.0
	var roll_cd := 0.0
	var rdx := 0.0
	var rdy := 1.0
	var hp := 5.0
	var alive := true
	var iframe := 0.0
	var grace := 0.0
	var launch := 0.0
	var coins := 0
	var kills := 0
	var shots := 0
	var speed := 0.0             ## SPEED BOOST seconds
	var magnet := 0.0            ## CASH MAGNET seconds
	var spin := 0.0              ## pulling the slot machine
	var buy := 0.0               ## stood at the vending machine
	var down_t := 0.0            ## Protect: seconds down
	# weapons (weapons.md 3.1)
	var weapon := "spud"
	var blasters := 0
	var w_time := 0.0
	var rockets := 0
	var dump := 0.0
	var ammo := 0
	var reload := 0.0
	var pickup := 0.0
	var throw := 0.0
	var threw := false
	var throw_whole := false
	var throw_pow := 0.5
	var throw_dx := 0.0
	var throw_dy := 1.0
	var throw_dist := 110.0
	var throw_tx := NAN
	var throw_ty := NAN
	var charge := 0.0
	var charging := false
	var lob_pow := 0.0
	var lob_dist := 0.0
	var punch := 0.0
	var punched := false
	var click := 0.0
	var dry_hint := 0.0
	var cooldown := 0.0
	var muzzle := 0.0
	var mdx := 0.0
	var mdy := 1.0
	var gun := 0
	var last_gun := 0
	var firing := false
	var adx := 0.0
	var ady := 1.0
	var tx := 0.0
	var ty := 0.0
	var aim_on := false
	var lob_held := false
	var tap_fire := false
	var last_tap := 0
	var bonk := 0.0              ## seconds since a hard wall bounce (sound once)
	var shared_wallet := false   ## his coins are the game's one wallet (/root/Wallet): player 1
	var driven := false          ## the sim works out his movement in the lobby too (player 2: the Fight node slides him)

	func pos() -> Vector2:
		return Vector2(x, y)

class Bullet:
	var owner := 0
	var x := 0.0
	var y := 0.0
	var x0 := 0.0                ## where it was fired from (the picture flies out of the gun for the first 70)
	var y0 := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 1.4
	var kb := 1.0
	var size := 4.0
	var dmg := 1.0
	var spud := false
	var rot := 0.0
	var travelled := 0.0

class Husk:
	var owner := 0
	var whole := false
	var x := 0.0
	var y := 0.0
	var dz := 14.0
	var vz := 0.0
	var vx := 0.0
	var vy := 0.0
	var dmg := -1.0
	var power := 0.0
	var rot := 0.0
	var spin := 0.0
	var life := 1.2

class Rocket:
	var owner := 0
	var sx := 0.0
	var sy := 0.0
	var h0 := 0.0
	var tx := 0.0
	var ty := 0.0
	var t := 0.0
	var big_h := 110.0           ## H, the arc's height
	var id := 0

class Blast:
	var x := 0.0
	var y := 0.0
	var t := 0.0
	var id := 0

class Plant:
	var x := 0.0
	var y := 0.0
	var t := 0.0
	var wob := 0.0

## A potato in the air (RAIN): from the rope, or a thrown one that landed without bursting.
class Rain:
	var x := 0.0
	var y := 0.0
	var dz := 0.0
	var vz := 0.0
	var vx := 0.0
	var vy := 0.0
	var squash := 0.0
	var delay := 0.0
	var bounces := 0
	var rot := 0.0
	var spin := 0.0

class Enemy:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var t := 0
	var hp := 3.0
	var flash := 0.0
	var spawn := 0.35
	var st := 0                  ## batter state (BAT)
	var st_t := 0.0
	var sdx := 0.0
	var sdy := 1.0
	var odo := 0.0
	var stun := 0.0
	var hit := false
	var uid := 0

class Shard:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 1.1

class Bit:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.5
	var col := Color.WHITE

class Blood:
	var x := 0.0
	var y := 0.0
	var a := 0.0
	var t := 0.0
	var big := false
	var scale := 1.0

class Splat:
	var x := 0.0
	var y := 0.0
	var k := 0
	var life := 45.0
	var a := 0.0
	var scale := 1.0

class Corpse:
	var x := 0.0
	var y := 0.0
	var t := 0
	var odo := 0.0
	var flip := false
	var life := 7.0
	var max_life := 7.0
	var rot := 0.0
	var vx := 0.0
	var vy := 0.0
	var spin := 0.0
	var part := -1
	var mask := 0
	var z := 0.0
	var vz := 0.0
	var landed := false

class Coin:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 6.0
	var arm := 0.0
	var rot := 0.0
	var spin := 0.0
	var phase := 0.0
	var owner := -1
	var pull := false

class Floater:
	var x := 0.0
	var y := 0.0
	var text := ""
	var t := 0.0
	var col := Color("#7fd89a")

class Dummy:
	var x := 0.0
	var y := 0.0
	var hp := 6.0
	var flash := 0.0
	var down := 0.0
	var wob := 0.0

class Nuke:
	var x := 430.0
	var y := 260.0
	var t := 0.0
	var boom := false

## The janitor, Gary (enemies_waves.md 9).
class Janitor:
	var phase := "idle"
	var t := 0.0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var flip := false
	var hits := 0
	var from := 0
	var shots := 0
	var target := -1
	var resume := "enter"
	var spent := false
	var paid := false
	var took := false
	var odo := 0.0
	var wdx := 0.0
	var wdy := 1.0
	var secret_return := false   ## shot as he left: he goes back to the cabinet, and the machine swallows you

## Gothica in Protect mode (modes_hud.md 2.2).
class Goth:
	var x := 430.0
	var y := 260.0
	var odo := 0.0
	var moving := false
	var ix := 0.0
	var iy := 1.0
	var fx := 0.0
	var fy := 1.0
	var vx := 0.0
	var vy := 0.0
	var tx := 430.0
	var ty := 260.0
	var wait := 1.5
	var hp := 10.0
	var max_hp := 10.0
	var hurt := 0.0
	var carrier := -1
	var carry_t := 0.0
	var carry_cd := 0.0
	var face := false
	var panic := 0.0
	var run_x := 0.0
	var run_y := 0.0
	var say_cd := 0.0
	var bubble := ""
	var bubble_t := 0.0
	var bubble_dur := 0.0

## The slot machine's state in the fight (gore_loot.md 13).
class Slot:
	var x := 430.0
	var y := 110.0
	var flash := 0.0
	var cool := 0.0
	var busy := -1
	var broken := false
	var prize := -1
	var decoy := [0, 0]

## A skull stamp in the bonus room (gore_loot.md 14.3).
class Hazard:
	var x := 0.0
	var y := 0.0
	var t := 0.0
	var hp := 3.0
	var hit := false

## The secret bonus room inside the slot machine (gore_loot.md 14).
class Secret:
	var phase := "intro"         ## intro, landing, bonus, payout, return, done
	var t := 0.0
	var room := false
	var saved: Dictionary = {}
	var origins: Array = []      ## [Vector2] where each player stood
	var hazards: Array = []
	var earned := 0
	var next_drop := 0.5
	var next_cash := 0.0
	var survived := false
