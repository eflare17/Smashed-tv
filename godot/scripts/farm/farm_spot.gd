class_name FarmSpot
extends Interactable
## A place on the farm E does something at: a plot, a paddock row, the tank, the seed crate, the garage door,
## the compost bin, a FOR SALE sign, a gate, the breeding table. It asks the Farm what E says and does there
## (Farm.spot_label / spot_act), so the player's E and the HUD's button work for it in both views.
## With a rect (HTML units: x0, y0, x1, y1) its distance is to the rect's edge, like the HTML game's crateSide
## and sellNear; otherwise to its position.

var farm: Farm
var kind: String = ""
var idx: int = -1
var rect: Rect2 = Rect2()
## Gates: where the gate is (HTML units).
var gate_pos: Vector2 = Vector2.ZERO

func label_for(player: Node) -> String:
	if farm == null or not is_instance_valid(farm):
		return ""
	return farm.spot_label(self, player)

func act(player: Node) -> void:
	if farm and is_instance_valid(farm):
		farm.spot_act(self, player)

func ground_distance(player: Node3D) -> float:
	if rect.size == Vector2.ZERO:
		return super.ground_distance(player)
	var b: Vector3 = GameData.from_3d(player.global_position)
	var dx := maxf(0.0, maxf(rect.position.x - b.x, b.x - rect.end.x))
	var dy := maxf(0.0, maxf(rect.position.y - b.y, b.y - rect.end.y))
	return Vector2(dx, dy).length()
