class_name GothCarry
extends Interactable
## E on Gothica in a Protect run (modes_hud.md 2.5): PICK UP when Juicy Jared is close enough, PUT DOWN while he
## carries her. Through the milestone 1 Interactable, so the E prompt and the round on-screen button work.

var fight: Node

func _ready() -> void:
	reach = 46.0

func update_pos() -> void:
	var s: FightSim = fight.sim
	if s.goth:
		global_position = GameData.world_to_3d(s.goth.x, s.goth.y, 0.0)
	else:
		global_position = Vector3(0, -1000, 0)

func label_for(_p: Node) -> String:
	var s: FightSim = fight.sim
	if s.goth == null or s.over:
		return ""
	if s.goth.carrier == fight.f.id:
		return "PUT DOWN"
	if ProtectSim.can_carry(s, fight.f):
		return "PICK UP"
	return ""

func act(_p: Node) -> void:
	fight.request_use()
