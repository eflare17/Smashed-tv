# (Made by tools/stkilda_sync.sh: a stand-in for the St Kilda game's Juicy Jared, which SkWalker names. Nobody's him
# here.)
class_name SkJared
extends Node3D

const WALK := 2.0
const RUN := 4.0

var model: Node3D
var anim: AnimationPlayer

func jump() -> void:
	pass

func animate(_speed: float, _moving: bool) -> void:
	pass
