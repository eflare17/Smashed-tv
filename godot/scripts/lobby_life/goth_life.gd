class_name GothLife
extends Node3D
## Gothica's extra life in the lobby, an add-on to scripts/npc/gothica.gd (which wanders her about) that doesn't
## edit it: it steers her from outside. Owned by the Lobby life session.
##
## The API the other things use (keep it):
## - claim(owner, spot, speed_mul, face): she walks to spot (HTML units) at npcSpeed * speed_mul, round the
##   furniture, and stands there facing face until unclaim(owner). The newest claim wins (the cards' dealer spot,
##   the gym's watching spot...). at_spot(owner): she's there.
## - say(text, dur): a speech bubble over her.
## - is_busy(): she's being carried or thrown (or is swimming out): can't deal, can't watch.
## - held: true while something else moves her (carry, throw): her own wander is off.

var ll: LobbyLife
var goth: Node3D
## Something else is moving her (carry/throw/swim): her wander is switched off and she's placed by that.
var held: bool = false

var _claims: Array = []        # [{owner, spot, mul, face}], newest last
var _base_speed: float = 38.0
var _was_claimed: bool = false

func _ready() -> void:
	process_physics_priority = -10       # before her own _physics_process (0)
	goth = ll.gothica if ll else null
	if goth == null:
		var g := get_tree().get_nodes_in_group("gothica")
		goth = g[0] if g.size() > 0 else null
	_base_speed = LobbyLife.T("npcSpeed", 38.0)

func claim(owner: String, spot: Vector2, speed_mul: float = 1.0, face: Vector2 = Vector2(0, 1)) -> void:
	unclaim(owner)
	_claims.append({"owner": owner, "spot": spot, "mul": speed_mul, "face": face})

func unclaim(owner: String) -> void:
	for c in _claims.duplicate():
		if c.owner == owner:
			_claims.erase(c)

func claimed_by() -> String:
	return "" if _claims.is_empty() else String(_claims[-1].owner)

func at_spot(owner: String) -> bool:
	if goth == null or _claims.is_empty() or _claims[-1].owner != owner:
		return false
	return LobbyLife.hpos(goth).distance_to(_claims[-1].spot) < 5.0

func is_busy() -> bool:
	return held

func say(text: String, dur: float = 2.6) -> void:
	if ll and ll.ui and goth:
		ll.ui.say(goth, text, dur, 92.0)

## Where she is, HTML units.
func pos() -> Vector2:
	return LobbyLife.hpos(goth) if goth else Vector2.ZERO

func _physics_process(_delta: float) -> void:
	if goth == null or not is_instance_valid(goth):
		return
	if held:
		goth.set("_enabled", false)
		return
	goth.set("_enabled", goth.visible)
	if _claims.is_empty():
		if _was_claimed:
			_was_claimed = false
			goth.set("_speed", _base_speed)
			goth.set("wait", 1.5)
		return
	_was_claimed = true
	var c: Dictionary = _claims[-1]
	goth.set("_speed", _base_speed * float(c.mul))
	var at := LobbyLife.hpos(goth)
	if at.distance_to(c.spot) < 4.0:
		goth.set("wait", 0.5)
		goth.set("facing", c.face)
		goth.set("moving", false)
		goth.set("target", at)
	else:
		goth.set("wait", 0.0)
		goth.set("target", c.spot)
