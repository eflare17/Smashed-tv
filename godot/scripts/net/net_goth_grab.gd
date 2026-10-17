class_name NetGothGrab
extends Interactable
## Online, lobby Gothica is run by one of the two games (the host's, until the other picks her up: the HTML
## game's b309 "the guest couldn't pick her up"). On the other screen she's a picture of where she is there,
## and this stands on her: E says PICK UP when she's free and you can carry her, and asks for her (Net).
## Owned by the Online task.

var net: Net
var can_take := false            ## the other game says she can be picked up

func _ready() -> void:
	reach = 60.0
	remove_from_group("interactable")    # only while she's the other game's (Net puts it in)

func label_for(p: Node) -> String:
	if not can_take or net == null or not GothLife.is_carrier(p) or bool(p.get_meta("carrying_goth", false)):
		return ""
	var ll := LobbyLife.current
	if ll and not ll.can_start(p):
		return ""
	return "PICK UP" if ground_distance(p as Node3D) < LobbyLife.T("carryRange", 46.0) else ""

func act(p: Node) -> void:
	if label_for(p) != "" and net:
		net.ask_for_goth()
