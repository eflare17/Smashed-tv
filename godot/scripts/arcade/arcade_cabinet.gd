class_name ArcadeCabinet
extends Interactable
## One arcade cabinet (an entry of CABINETS: {x, game, body, trim}). E plays it, from where the HTML game's
## arcadeNear lets you: within 30 across of its middle and from 4 behind its feet line (cabY) to 46 in front,
## standing on the floor. Also the little screen on its face, playing to itself (ARCADE_GAMES[game].mini), or
## the picture of the Mega Drive game being played on it (mdCabPic).

var cab: Dictionary = {}
var cab_y: float = 116.0
var arcade: Arcade
var screen_vp: SubViewport

func _init() -> void:
	reach = 70.0

func label_for(p: Node) -> String:
	if p == null or p.get("frozen") or p.get("on_tramp") or float(p.get("dz") if p.get("dz") != null else 0.0) > 2.0:
		return ""
	if Arcade.is_open():
		return ""
	var hp: Vector3 = GameData.from_3d(p.global_position)
	if absf(hp.x - float(cab.x)) < 30.0 and hp.y > cab_y - 4.0 and hp.y < cab_y + 46.0:
		return "PLAY"
	return ""

func act(_p: Node) -> void:
	if arcade:
		arcade.use_cabinet(self)

# ---------------------------------------------------------------- the little screen

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords, depth_draw_opaque;
// The cabinet's own lean (the World's prop shader), so it stays on the cabinet's face, a hair toward the camera.
uniform sampler2D tex : source_color, filter_nearest;
uniform float lean_max = 1.35;
uniform float glow = 1.15;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - o;
	vec3 cr = INV_VIEW_MATRIX[0].xyz;
	vec3 r = vec3(cr.x, 0.0, cr.z);
	r = length(r) > 1e-4 ? normalize(r) : vec3(1.0, 0.0, 0.0);
	vec3 fh = vec3(r.z, 0.0, -r.x);
	float pitch = asin(clamp(INV_VIEW_MATRIX[2].y, -1.0, 1.0));
	float th = min(lean_max, max(pitch, 0.0) * smoothstep(0.35, 0.9, pitch));
	vec3 up = cos(th) * vec3(0.0, 1.0, 0.0) + sin(th) * fh;
	VERTEX = o + r * local.x + up * local.y;
	VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * 0.012;
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * glow;
}
"""

## Put the live little screen on the cabinet's picture (the World's prop for it, standing at its feet).
func add_screen(prop: Node3D) -> void:
	screen_vp = SubViewport.new()
	screen_vp.size = Vector2i(72, 60)
	screen_vp.disable_3d = true
	screen_vp.transparent_bg = false
	screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(screen_vp)
	var drawer := _Mini.new()
	drawer.cab = self
	drawer.size = Vector2(72, 60)
	screen_vp.add_child(drawer)
	# the screen on the HTML game's cabinet: 36 x 30, 7 in from its left edge and 22 down from its top
	# (drawCabinet: W 50, H 104 standing at cabY), so from 52 to 82 up and 18 either side of the middle
	var U := GameData.UNIT
	var x0 := -18.0 * U
	var x1 := 18.0 * U
	var y0 := (cab_y - (cab_y - 104.0 + 22.0 + 30.0)) * U
	var y1 := (cab_y - (cab_y - 104.0 + 22.0)) * U
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])
	var mi := MeshInstance3D.new()
	mi.name = "ArcadeScreen"
	mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = SCREEN_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("tex", screen_vp.get_texture())
	sm.render_priority = 1
	mi.material_override = sm
	mi.extra_cull_margin = 4.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prop.add_child(mi)

class _Mini extends Control:
	var cab: ArcadeCabinet
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(2, 2))
		var r := Rect2(0, 0, 36, 30)
		var pic: Texture2D = null
		if cab.cab.game == "bricks" and cab.arcade and cab.arcade.md:
			pic = cab.arcade.md.cab_picture()
		if pic:
			draw_texture_rect(pic, r, false)
		else:
			var s = Arcade.GAMES.get(String(cab.cab.game))
			if s:
				s.mini(self, r, _t)
		draw_rect(Rect2(0, 0, 36, 2), Color(1, 1, 1, 0.12))
