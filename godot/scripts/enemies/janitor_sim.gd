class_name JanitorSim
extends RefCounted
## Gary the janitor (godot/specs/enemies_waves.md 9). He fixes the broken slot machine in the first breather of
## the run: walks in from the bottom, throws the OUT OF ORDER sign down, three hammer blows, bends down, notes fall
## out, he pockets what's left, the machine goes live, he walks out. Shoot him once: knocked flat, he complains.
## Again: he stares, charges and whacks you across the room (unhurt), then trudges back to work.
## (The secret bonus room his second repair opens isn't built: see the integration note.)

const PHASES: Array[String] = ["idle", "enter", "yeet", "swing", "bend", "pocket", "exit", "done", "down", "rise",
	"gripe", "regrab", "stare", "chase", "whack", "giveup", "trudge"]

static func shootable(s: FightSim) -> bool:
	var j := s.janitor
	return j.phase != "idle" and j.phase != "done" and not j.spent

static func step(s: FightSim, dt: float) -> void:
	var j := s.janitor
	var sx := s.slot.x
	var sy := s.slot.y
	if j.phase == "idle":
		if not s.over and s.slot.broken and s.wave >= int(s.tv("janitorWave", 1)) and s.breather > 0.0:
			j.phase = "enter"
			j.t = 0.0
			j.hits = 0
			j.from = -1
			j.x = sx + 60.0
			j.y = FightSim.AH + 40.0
			j.flip = true
		return
	if j.phase == "done":
		return
	if j.phase != "exit":
		s.breather = maxf(s.breather, 0.6)
	j.t += dt
	var spd := s.tv("janitorSpeed", 105)
	match j.phase:
		"enter", "trudge":
			var to := Vector2(sx + 34.0, sy + 26.0)
			var d := to - Vector2(j.x, j.y)
			if d.length() < 8.0:
				if j.phase == "enter":
					j.phase = "yeet"
					j.flip = true
				else:
					j.phase = "yeet" if j.resume == "enter" else (j.resume if j.resume != "" else "swing")
				j.t = 0.0
			else:
				var u := d.normalized()
				j.x += u.x * spd * dt
				j.y += u.y * spd * dt
				j.wdx = u.x
				j.wdy = u.y
				j.flip = d.x < 0.0
				j.odo += spd * dt
		"yeet":
			if j.t > 0.18 and s.sign == "stand":
				s.sign = "floor"
			if j.t > 0.30:
				j.phase = "swing"
				j.t = 0.0
		"swing":
			if j.t > 0.30:
				j.t = 0.0
				j.hits += 1
				s.fx(FightSim.FX_WALL, sx + (-14.0 if j.from < 0 else 14.0), sy - 6.0)
				s.snd("clank")
				if j.hits >= int(s.tv("janitorHits", 3)):
					j.phase = "bend"
		"bend":
			if j.t > 0.22 and not j.paid:
				j.paid = true
				for i in int(s.tv("janitorPay", 3)):
					var a := -PI / 2.0 + (i - 1) * 0.55
					var c := s._coin(sx, sy + 6.0, cos(a) * 150.0, sin(a) * 90.0, s.tv("coinLife", 6) + 3.0, 0.5)
					c.spin = (s.rnd() - 0.5) * 10.0
			if j.t > 0.40:
				j.phase = "pocket"
				j.t = 0.0
		"pocket":
			if j.t > 0.25 and not j.took:
				j.took = true
				var keep := []
				for c: FT.Coin in s.coins:
					if Vector2(c.x - sx, c.y - sy).length() > 90.0:
						keep.append(c)
				s.coins = keep
			if j.t > 0.42:
				j.phase = "exit"
				j.t = 0.0
				s.slot.broken = false
				s.slot.flash = 0.9
				s.banner("MACHINE IS LIVE", 1.6)
		"exit":
			j.y += spd * dt
			j.wdx = 0.0
			j.wdy = 1.0
			j.odo += spd * dt
			if j.y > FightSim.AH + 40.0:
				j.phase = "done"
		"down":
			j.x += j.vx * dt
			j.vx *= pow(0.02, dt)
			if j.t > 0.9:
				j.phase = "rise"
				j.t = 0.0
		"rise":
			if j.t > 0.7:
				j.phase = "gripe"
				j.t = 0.0
		"gripe":
			if j.t > s.tv("gripeTime", 3.4):
				j.phase = "regrab"
				j.t = 0.0
		"regrab":
			if j.t > 0.5:
				j.phase = j.resume if j.resume != "" else "enter"
				j.t = 0.0
		"stare":
			var tp := _target(s)
			if tp:
				j.flip = tp.x < j.x
			if j.t > 0.75:
				j.phase = "chase"
				j.t = 0.0
		"chase":
			var tp := _target(s)
			if tp == null or not tp.alive or j.t > s.tv("chaseGiveUp", 8):
				j.phase = "giveup"
				j.t = 0.0
			else:
				var a := Vector2(tp.x + tp.vx * s.tv("janitorLead", 0.28), tp.y + tp.vy * s.tv("janitorLead", 0.28))
				var d := a - Vector2(j.x, j.y)
				if d.length() > 0.001:
					var u := d.normalized()
					j.x += u.x * s.tv("janitorRage", 340) * dt
					j.y += u.y * s.tv("janitorRage", 340) * dt
					j.flip = d.x < 0.0
					j.wdx = u.x
					j.wdy = u.y
				j.odo += s.tv("janitorRage", 340) * dt
				var gap := Vector2(tp.x - j.x, tp.y - j.y)
				if gap.length() < s.tv("radius", 14) + 22.0:
					var u := gap.normalized() if gap.length() > 0.001 else Vector2(0, 1)
					tp.vx = u.x * s.tv("whackForce", 980)
					tp.vy = u.y * s.tv("whackForce", 980)
					tp.iframe = maxf(tp.iframe, s.tv("launchTime", 1.1) + 0.3)
					tp.launch = s.tv("launchTime", 1.1)
					tp.roll = 0.0
					s.shake = maxf(s.shake, 22.0)
					s.freeze = maxf(s.freeze, 0.06)
					s.fx(FightSim.FX_HURT, tp.x, tp.y)
					s.snd("whack")
					j.phase = "whack"
					j.t = 0.0
		"whack":
			if j.t > 1.1:
				j.phase = "trudge"
				j.t = 0.0
				j.spent = true
		"giveup":
			if j.t > 1.6:
				j.phase = "trudge"
				j.t = 0.0
				j.spent = true
	j.odo += spd * dt

static func _target(s: FightSim) -> FT.Fighter:
	var j := s.janitor
	if j.target >= 0 and j.target < s.players.size():
		return s.players[j.target]
	return s.players[0] if not s.players.is_empty() else null

## A bullet hit him (9.3).
static func on_shot(s: FightSim, b: FT.Bullet) -> void:
	var j := s.janitor
	match j.phase:
		"chase", "stare":
			if j.target != b.owner:
				j.target = b.owner
				j.phase = "stare"
				j.t = 0.0
		"gripe", "regrab":
			j.shots += 1
			j.phase = "stare"
			j.t = 0.0
			j.target = b.owner
		"down", "rise", "whack", "giveup", "trudge":
			pass
		_:
			j.shots += 1
			if j.shots == 1:
				j.resume = j.phase
				j.phase = "down"
				j.t = 0.0
				j.vx = 90.0 if (b.vx if b.vx != 0.0 else 1.0) > 0.0 else -90.0
				s.snd("jan_down")
			else:
				j.phase = "stare"
				j.t = 0.0
				j.target = b.owner
