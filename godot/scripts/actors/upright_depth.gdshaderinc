// CONTRACT. How anything drawn as an upright picture (characters: CharSprite; the World's prop cut-outs; milestone
// 2's enemies) sorts against everything else, the HTML game's y-sort done with the depth buffer.
//
// A picture stands on its feet (origin) in the upright plane along `right` (horizontal) and straight up. Where it is
// DRAWN can differ (tipped back toward the camera from above, so a top-down view shows it whole), but its DEPTH is
// always the upright plane's: each point is as deep as where the camera's ray through it crosses that plane. So
// something south of the feet (nearer the camera) covers it and something north of them never cuts into it, however
// far the picture leans. Use it in a vertex() that writes POSITION:
//
//   #include "res://scripts/actors/upright_depth.gdshaderinc"
//   ...
//   VERTEX = drawn;   // world space (render_mode world_vertex_coords), or set POSITION from it directly
//   POSITION = upright_clip(drawn, origin, right, VIEW_MATRIX, INV_VIEW_MATRIX, PROJECTION_MATRIX, bias, reach);
//
// drawn: the point as drawn, world space. origin: the feet, world space. right: the picture's horizontal axis
// (unit, y = 0). bias: metres toward the camera (so the feet win over the floor they stand on; characters 0.06,
// props 0.03). reach: the most (metres) a leaning point's depth is pulled toward the camera (6 normally; more for
// a picture lying flat that's long north to south).

vec4 upright_clip(vec3 drawn, vec3 origin, vec3 right, mat4 view_m, mat4 inv_view_m, mat4 proj_m, float bias, float reach) {
	vec4 clip = proj_m * (view_m * vec4(drawn, 1.0));
	vec3 n = vec3(-right.z, 0.0, right.x);                     // the upright plane's normal, toward the camera's side
	bool ortho = proj_m[3][3] > 0.5;
	vec3 cam = inv_view_m[3].xyz;
	vec3 to_cam = ortho ? inv_view_m[2].xyz : normalize(cam - drawn);
	float behind = -dot(drawn - origin, n);                    // how far behind the plane the drawn point is
	float mu = clamp(behind / max(dot(to_cam, n), 0.0001), 0.0, reach);
	if (!ortho) {
		mu = min(mu, max(0.0, length(cam - drawn) - 0.25));    // never past the camera's near plane
	}
	vec4 vd = view_m * vec4(drawn + to_cam * mu, 1.0);
	vd.z += bias;
	vec4 cd = proj_m * vd;
	if (cd.w > 0.0001) {
		clip.z = cd.z / cd.w * clip.w;
	}
	return clip;
}
