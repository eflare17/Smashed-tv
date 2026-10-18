class_name VoxelWeapons
extends RefCounted
## Where the block weapons sit on a character (assets/voxel/weapons/*.vox, built from the weapon sheets' side frames
## by vox_build.py: the grip at the origin, the barrel toward +z). Owned by the voxel session.
##
## Hand guns hang in the fist with the barrel along the arm (pointing at the floor when the arm hangs, straight ahead
## when VoxelAnim raises the arm to aim); the blasters come in pairs, one a hand; the nuke launcher rides on the right
## shoulder, fixed to the chest.

## The attachments for VoxelModel.build_mesh: [{arrays, bone, xform}] for the weapon held ("" for none).
static func attachments(model: VoxelModel, weapon: String, lod: int) -> Array:
	var out := []
	if model == null:
		return out
	var m := model.voxel_m
	var g: Array = model.rig.get("grip_r", [-34.5, 56.0, -2.0])
	var grip_r := Vector3(g[0], g[1], -2.0) * m
	var grip_l := Vector3(-grip_r.x, grip_r.y, grip_r.z)
	var down := Basis(Vector3.RIGHT, PI / 2.0)       # weapon +z (barrel) along -y, its top toward +z
	match weapon:
		"spud", "lob":
			out.append({"arrays": VoxelModel.weapon_arrays("spud", lod, m), "bone": "hand_r", "xform": Transform3D(down, grip_r)})
		"blaster":
			out.append({"arrays": VoxelModel.weapon_arrays("blaster", lod, m), "bone": "hand_r", "xform": Transform3D(down, grip_r)})
			out.append({"arrays": VoxelModel.weapon_arrays("blaster", lod, m), "bone": "hand_l", "xform": Transform3D(down, grip_l)})
		"shotgun":
			out.append({"arrays": VoxelModel.weapon_arrays("shotgun", lod, m), "bone": "hand_r", "xform": Transform3D(down, grip_r)})
		"launcher":
			var at: Array = model.rig.get("launcher_at", [-22.0, 104.0, 14.0])
			out.append({"arrays": VoxelModel.weapon_arrays("launcher", lod, m), "bone": "chest",
				"xform": Transform3D(Basis.IDENTITY, Vector3(at[0], at[1], at[2]) * m)})
	return out
