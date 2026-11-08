class_name DsBobcat
extends DsDingo
## The Bobcat (stage 10): a skid-steer loader, the Dingo's bigger brother (the digger game's Loader BOBCAT): you sit
## in its cab, it's on four wheels, faster, its bucket twice as big and wider. The same controls and the same digging
## and pouring as the Dingo (DsDingo); pour over the tip truck's tray and it goes in the truck. Owned by the voxel
## session.

func _init() -> void:
	super()
	kind = "Bobcat"
	length = 2.2
	width = 1.4
	max_speed = 3.0
	accel = 2.0
	turn_rate = 1.4
	max_climb = deg_to_rad(30.0)
	step_up = 0.3
	seat = Vector3(0, 0.3, 0.15)
	capacity = 520
	arm_pivot = Vector3(0, 1.25, -0.3)
	arm_len = 1.5
	arm_low = -1.15
	bucket_w = 1.5
	colour = Color8(240, 240, 236)

func _build_body() -> void:
	var dark := Color8(36, 36, 40)
	var orange := Color8(232, 112, 30)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.3
			cm.bottom_radius = 0.3
			cm.height = 0.26
			w.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = dark
			w.material_override = m
			w.rotation.z = PI * 0.5
			w.position = Vector3(sx * 0.62, 0.3, sz * 0.62)
			add_child(w)
	_box(self, Vector3(1.0, 0.5, 2.0), Vector3(0, 0.55, 0.05), colour)
	_box(self, Vector3(1.04, 0.3, 0.5), Vector3(0, 0.95, 0.75), orange)
	# the cab: a cage of posts, a roof, the seat inside
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(self, Vector3(0.06, 1.1, 0.06), Vector3(sx * 0.46, 1.35, 0.1 + sz * 0.42), dark)
	_box(self, Vector3(1.0, 0.06, 0.95), Vector3(0, 1.92, 0.1), colour)
	_box(self, Vector3(0.5, 0.12, 0.4), Vector3(0, 0.85, 0.3), dark)

func keys() -> String:
	return "W/S drive   A/D turn   R/F arms up/down   right mouse: curl the bucket   left mouse: tip it (over the truck: in it)   E get off"
