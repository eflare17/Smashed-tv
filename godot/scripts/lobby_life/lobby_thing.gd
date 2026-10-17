class_name LobbyThing
extends Interactable
## One of lobby life's things (the pool, the bench, the bed...): an Interactable (E and the round button, both
## views) that can also hold the player while he uses it (LobbyLife.hold / release). Owned by the Lobby life session.
##
## A thing says what E does next to it (label_for/act, the Interactable contract) and, while it holds him, what E
## does now (busy_label/busy_act), moves him (busy_step) and takes any other keys it wants (busy_input).

var ll: LobbyLife

## The player in HTML units on the ground.
func ppos(p: Node3D) -> Vector2:
	return LobbyLife.hpos(p)

## Holding him?
func holding(p: Node) -> bool:
	return ll != null and ll.busy.get(p) == self

## Free to start something (not busy with anything, not on the trampoline, on the floor).
func can_start(p: Node) -> bool:
	return ll != null and ll.can_start(p)

func busy_label(_p: Player) -> String:
	return ""

func busy_act(_p: Player) -> void:
	pass

func busy_step(_p: Player, _dt: float) -> void:
	pass

## Any other key while he's held here: return true if taken.
func busy_input(_p: Player, _event: InputEvent) -> bool:
	return false

## He's been taken off this thing by something else (another thing's hold): tidy up.
func busy_end(_p: Player) -> void:
	pass

## Hide his character sprite while held (when the thing draws him itself, or he's under water...).
func hides_sprite(_p: Player) -> bool:
	return false

## Put him somewhere (HTML units, z up) while held: the camera follows, dz says how high he is.
func put(p: Player, x: float, y: float, z: float = 0.0) -> void:
	p.global_position = GameData.world_to_3d(x, y, z)
	p.dz = z

## The steering (HTML ground axes, up to length 1), first person turned by where he looks (Player.read_steer).
func steer(p: Player) -> Vector2:
	return p.read_steer()
