class_name DsBobcat
extends DsDingo
## The Bobcat (stage 10): the digger game's Bobcat (Loader BOBCAT: its body, wheels, arms and bucket from DsProps, its
## numbers): a skid-steer loader you sit in, the Dingo's bigger brother, on four wheels, faster, its bucket twice as
## big and wider. The same controls and the same digging and pouring as the Dingo (DsDingo); pour over the tip
## truck's tray and it goes in the truck. Owned by the voxel session.

func _init() -> void:
	super()
	kind = "Bobcat"
	length = 2.2
	width = 1.8
	max_speed = 3.0
	accel = 2.0
	turn_rate = 1.4
	max_climb = deg_to_rad(30.0)
	step_up = 0.3
	seat = Vector3(0, 0.05, -0.1)
	capacity = 520
	pivot = Vector2(-0.82, 1.62)
	arm_len = 2.3
	arm_low = -0.9
	arm_high = 1.0
	bucket_len = 0.72
	bucket_half = 0.92
	bucket_high = 0.62
	firm_rate = 2
	bog = 2000.0

func _build_body() -> void:
	var kit := DsKit.new()
	DsProps.bobcat_body(kit)
	_add(_look, kit)
	var w := DsKit.new()
	DsProps.wheel(w, 0.32)
	var tyre := w.mesh()
	for side in [-1.0, 1.0]:
		for x in [-0.62, 0.62]:
			var mi := MeshInstance3D.new()
			mi.mesh = tyre
			mi.material_override = DsExcavator.mat()
			mi.position = Vector3(x, 0.38, side * 0.84)
			mi.basis = Basis.IDENTITY.scaled(Vector3(0.38, 0.38, 1.0))
			_look.add_child(mi)
			_wheels.append([mi, 0.38])

func keys() -> String:
	return "W/S drive   A/D turn   R/F arms up/down\nright mouse: curl the bucket   left mouse: tip it (over the truck: in it)   V view   wheel zoom   E get off"
