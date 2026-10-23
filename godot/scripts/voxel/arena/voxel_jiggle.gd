class_name VoxelJiggle
extends RefCounted
## Gothica's soft parts (the owner, 23 Oct: "her jiggle physics impressive, out of this world impressive"). What moves:
## her chest (each side its own mass on a spring, sculpted round by VoxelModel's "gothica" variant: BUST), her long hair
## and her skirt. Nothing here is animated by hand: every frame it measures how the bone each hangs from really moved
## (the point's acceleration in the world, the turn of the body, which way gravity pulls in the body's frame) and lets
## the springs answer it, sub-stepped at 480 Hz so a stiff spring at a low frame rate stays steady.
##
## Each side of the chest: a spring with its own stiffness up and down, side to side and in and out (up and down the
## softest, in and out the stiffest), lightly damped so a jolt rings on for a second; stiffer the further it's pulled
## (it can't fly off), a quicker second wobble on top of the first (the ripple after a hard landing), the two sides
## colliding in the middle rather than passing through, and the shape stretching as it's pulled down and squashing as
## it's thrown up (keeping its volume). Steps, landings, bumps and turns all come out of the body's own movement;
## heel strikes and hops give it an extra kick (kick()). The look: shader() bends the cubes in the vertex
## shader, the front of each shape moving most and the base where it meets her chest not at all, so it bends and
## sways like something soft instead of sliding about as a block; the light runs over it (her top is satin: a sheen).
##
## level (the settings' Jiggle): 0 off, 1 natural, 2 bouncy, 3 out of this world. Owned by the voxel session.

const SUB := 1.0 / 480.0
const G := Vector3(0, -9.8, 0)
## Per level: [up/down Hz, side Hz, in/out Hz, damping ratio, how hard it answers, reach (metres: up/down, side, in/out)].
## The springs are linear (so they ring true); what's drawn is eased into the reach (reach * tanh(x / reach)): a big
## jolt goes most of the way and no further, never stopping dead against a limit.
const LEVELS := [
	[0.0, 0.0, 0.0, 1.0, 0.0, Vector3.ZERO],
	[4.4, 3.8, 5.6, 0.24, 0.6, Vector3(0.012, 0.009, 0.008)],
	[3.6, 3.1, 4.8, 0.16, 0.7, Vector3(0.02, 0.014, 0.012)],
	[3.0, 2.6, 4.0, 0.12, 0.8, Vector3(0.032, 0.022, 0.018)],
]
static var level := 3

var body: VoxelBody
var mats := {}                  # "torso", "hair", "skirt", "rest": ShaderMaterial
var sides: Array = []           # [{c: Vector3 (chest's space), p, v, q, qv: ripple, prev: Vector3, pv, a: world}] left, right
var hair := {}                  # {anchor (head's space), p, v, prev, pv, a}
var skirt := {}
var _vm := 0.0125
var _wave := 0.0
var _first := true
var _chest := -1
var _head := -1
var _hips := -1

static var _shader: Shader

func setup(body_: VoxelBody) -> void:
	body = body_
	_vm = body.model.voxel_m
	_chest = body.model.bone("chest")
	_head = body.model.bone("head")
	_hips = body.model.bone("hips")
	var piv: Vector3 = body.model.bone_pivot[_chest]
	var b: Dictionary = VoxelModel.BUST
	var mid := 0.0                                         # (the torso's middle, model x)
	for k in 2:
		var sx := 1.0 if k == 0 else -1.0                 # (left: the model's +x)
		var c := (Vector3(mid + sx * float(b.x), float(b.y), float(b.z)) - piv) * _vm
		sides.append({"c": c, "p": Vector3.ZERO, "v": Vector3.ZERO, "q": Vector3.ZERO, "qv": Vector3.ZERO,
			"prev": Vector3.ZERO, "pv": Vector3.ZERO, "a": Vector3.ZERO})
	var hp: Vector3 = body.model.bone_pivot[_head]
	hair = {"anchor": (Vector3(1, 96, -12) - hp) * _vm, "p": Vector3.ZERO, "v": Vector3.ZERO, "q": Vector3.ZERO, "qv": Vector3.ZERO,
		"prev": Vector3.ZERO, "pv": Vector3.ZERO, "a": Vector3.ZERO}
	var kp: Vector3 = body.model.bone_pivot[_hips]
	skirt = {"anchor": (Vector3(0, 56, 0) - kp) * _vm, "p": Vector3.ZERO, "v": Vector3.ZERO, "q": Vector3.ZERO, "qv": Vector3.ZERO,
		"prev": Vector3.ZERO, "pv": Vector3.ZERO, "a": Vector3.ZERO}
	# the materials: one for each kind of soft part, one for the rest of her (the same satin and skin)
	for nm in ["torso", "hair", "skirt", "rest"]:
		var m := ShaderMaterial.new()
		m.shader = shader()
		mats[nm] = m
	var t: ShaderMaterial = mats.torso
	t.set_shader_parameter("mode", 1)
	t.set_shader_parameter("c_l", sides[0].c)
	t.set_shader_parameter("c_r", sides[1].c)
	t.set_shader_parameter("rad", Vector3(float(b.rx), (float(b.ry_up) + float(b.ry_down)) * 0.5, float(b.rz)) * _vm)
	var h: ShaderMaterial = mats.hair
	h.set_shader_parameter("mode", 2)
	h.set_shader_parameter("root_y", (132.0 - hp.y) * _vm)
	h.set_shader_parameter("len_y", 76.0 * _vm)
	h.set_shader_parameter("power", 1.6)
	var sk: ShaderMaterial = mats.skirt
	sk.set_shader_parameter("mode", 2)
	sk.set_shader_parameter("root_y", (80.0 - kp.y) * _vm)
	sk.set_shader_parameter("len_y", 30.0 * _vm)
	sk.set_shader_parameter("power", 1.4)
	dress(body, mats.rest, {"torso": mats.torso, "hair": mats.hair, "skirt": mats.skirt}, false)

## A jolt to the chest (its own frame, metres a second): a heel coming down, a landing, a bump.
func kick(v: Vector3) -> void:
	for s in sides:
		s.v += v * randf_range(0.85, 1.15)
		s.qv += v * 0.6

func _bone_xf(b: int) -> Transform3D:
	return body.skeleton.global_transform * body.skeleton.get_bone_global_pose(b)

# a point's acceleration in the world from where it's been the last two frames (gently smoothed: a frame's jitter
# isn't a jolt)
func _accel(st: Dictionary, w: Vector3, dt: float) -> Vector3:
	var vel: Vector3 = (w - (st.prev as Vector3)) / dt
	var a: Vector3 = (vel - (st.pv as Vector3)) / dt
	if _first:
		vel = Vector3.ZERO
		a = Vector3.ZERO
	st.prev = w
	st.pv = vel
	if a.length() > 400.0:
		a = a.normalized() * 400.0                     # (put somewhere else: not a jolt to answer)
	st.a = (st.a as Vector3).lerp(a, 0.6)
	return st.a

func step(dt: float) -> void:
	if dt <= 0.0 or body == null:
		return
	var L: Array = LEVELS[clampi(level, 0, 3)]
	var on := level > 0
	var chest := _bone_xf(_chest)
	var cb := chest.basis.orthonormalized()
	var g_local := cb.inverse() * G - G                # (gravity, as the body leans, from upright)
	var n := clampi(int(ceil(dt / SUB)), 1, 64)
	var h := dt / n
	var w := Vector3(TAU * float(L[1]), TAU * float(L[0]), TAU * float(L[2]))
	var zeta := float(L[3])
	var gain := float(L[4])
	var reach: Vector3 = L[5]
	var reach_x := Vector3(reach.y, reach.x, reach.z)  # (x side, y up, z out)
	for s in sides:
		var a := _accel(s, chest * (s.c as Vector3), dt)
		var f := (cb.inverse() * -a + g_local * 0.6) * gain
		if not on:
			s.p = Vector3.ZERO
			s.v = Vector3.ZERO
			continue
		for i in n:
			_spring(s, f, w, zeta, reach_x, h)
			_ripple(s, f, h)
	if on:
		_collide(h)
	for k in 2:
		var s: Dictionary = sides[k]
		var tag := "l" if k == 0 else "r"
		var p := _ease(s.p, reach_x)
		mats.torso.set_shader_parameter("d_" + tag, p)
		mats.torso.set_shader_parameter("q_" + tag, s.q)
		mats.torso.set_shader_parameter("s_" + tag, -p.y / maxf(0.001, reach.x) * 0.16)
	# the hair: a heavy, slow pendulum off the back of her head; the skirt: quicker, off her hips
	_hang(hair, _bone_xf(_head), 1.25, 0.22, Vector3(0.11, 0.05, 0.11), 1.0, mats.hair, dt, n, h, on)
	_hang(skirt, _bone_xf(_hips), 1.9, 0.3, Vector3(0.045, 0.02, 0.05), 0.9, mats.skirt, dt, n, h, on)
	var spd: float = body.speed
	_wave += dt * (2.0 + spd * 5.0)
	mats.skirt.set_shader_parameter("wave", clampf(spd * 0.02, 0.0, 0.05) if on else 0.0)
	mats.skirt.set_shader_parameter("phase", _wave)
	_first = false

static func _ease(p: Vector3, reach: Vector3) -> Vector3:
	return Vector3(reach.x * tanh(p.x / reach.x), reach.y * tanh(p.y / reach.y), reach.z * tanh(p.z / reach.z))

# one sub-step of a spring (linear, a little stiffer past its reach; held within three times it)
func _spring(s: Dictionary, f: Vector3, w: Vector3, zeta: float, reach: Vector3, h: float) -> void:
	var p: Vector3 = s.p
	var v: Vector3 = s.v
	var r := Vector3(p.x / reach.x, p.y / reach.y, p.z / reach.z)
	var big := maxf(0.0, r.length_squared() - 1.0)
	var stiff := 1.0 + 0.25 * big
	var damp := zeta * (1.0 + 1.5 * big)               # (a big swing loses more each time: settles to a long gentle ring)
	var acc := Vector3(
		f.x - w.x * w.x * stiff * p.x - 2.0 * damp * w.x * v.x,
		f.y - w.y * w.y * stiff * p.y - 2.0 * damp * w.y * v.y,
		f.z - w.z * w.z * stiff * p.z - 2.0 * damp * w.z * v.z)
	v += acc * h                                        # (semi-implicit Euler: steady for a spring)
	p += v * h
	for ax in 3:
		if absf(p[ax]) > reach[ax] * 3.0:
			p[ax] = signf(p[ax]) * reach[ax] * 3.0
			if signf(v[ax]) == signf(p[ax]):
				v[ax] = 0.0
	s.p = p
	s.v = v

# the quicker wobble riding on the first (8 Hz, a little damped): what a hard jolt leaves after the main bounce
func _ripple(s: Dictionary, f: Vector3, h: float) -> void:
	var w := TAU * 8.0
	var q: Vector3 = s.q
	var qv: Vector3 = s.qv
	qv += (f * 0.25 - q * w * w - qv * 2.0 * 0.2 * w) * h
	q += qv * h
	s.q = q.limit_length(0.008)
	s.qv = qv

# the two sides meet in the middle: pushed apart there, sharing what they were moving with
func _collide(_h: float) -> void:
	var l: Dictionary = sides[0]
	var r: Dictionary = sides[1]
	var over: float = (r.p as Vector3).x - (l.p as Vector3).x - 0.002     # (left is +x: they overlap when r's x passes l's)
	if over > 0.0:
		l.p = (l.p as Vector3) + Vector3(over * 0.5, 0, 0)
		r.p = (r.p as Vector3) - Vector3(over * 0.5, 0, 0)
		var lv: Vector3 = l.v
		var rv: Vector3 = r.v
		var m := (lv.x + rv.x) * 0.5
		l.v = Vector3(m + (m - lv.x) * 0.3, lv.y, lv.z)
		r.v = Vector3(m + (m - rv.x) * 0.3, rv.y, rv.z)

# a hanging part (hair, skirt): its free end a mass on a spring from the bone, swinging behind as the bone moves and
# hanging the way gravity pulls
func _hang(st: Dictionary, xf: Transform3D, hz: float, zeta: float, reach: Vector3, gain: float, m: ShaderMaterial,
		dt: float, n: int, h: float, on: bool) -> void:
	var b := xf.basis.orthonormalized()
	var a := _accel(st, xf * (st.anchor as Vector3), dt)
	if not on:
		m.set_shader_parameter("h_d", Vector3.ZERO)
		return
	var f := (b.inverse() * -a + (b.inverse() * G - G)) * gain
	var w := Vector3(TAU * hz, TAU * hz * 1.6, TAU * hz)
	for i in n:
		_spring(st, f, w, zeta, reach, h)
	m.set_shader_parameter("h_d", _ease(st.p, reach))

## The shader all of her is drawn with: vertex colours lit (her top, skirt and boots satin-black with a sheen, skin
## softer); mode 1 bends the chest (each side by its own d, q, s), mode 2 swings a hanging part (h_d, more the further
## down, the skirt's hem rippling with wave).
## A block character drawn with shader(): every part's material (one for her soft parts each, if given; the rest
## shared) and its rounded shape for the smooth shading (VoxelReshape.shape).
static func dress(b: VoxelBody, rest: ShaderMaterial = null, own: Dictionary = {}, shapes := true) -> void:
	if rest == null:
		rest = ShaderMaterial.new()
		rest.shader = shader()
	for n in b.parts:
		var p: Dictionary = b.parts[n]
		var mi: MeshInstance3D = p.mesh
		mi.material_override = own.get(n, rest)
		if not shapes:
			continue
		var sh := VoxelReshape.shape(p.grid, b.mesh_origin(n), Vector3.ZERO, b.vm)
		mi.set_instance_shader_parameter("shape_c", sh[0])
		mi.set_instance_shader_parameter("shape_r", sh[1])

static func shader() -> Shader:
	if _shader:
		return _shader
	_shader = Shader.new()
	_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int mode = 0;
uniform vec3 c_l; uniform vec3 c_r; uniform vec3 rad = vec3(0.06);
uniform vec3 d_l; uniform vec3 d_r; uniform vec3 q_l; uniform vec3 q_r;
uniform float s_l = 0.0; uniform float s_r = 0.0;
uniform float root_y = 0.0; uniform float len_y = 1.0; uniform float power = 1.5;
uniform vec3 h_d; uniform float wave = 0.0; uniform float phase = 0.0;
// the part's rounded shape (VoxelReshape.shape, set on each part: dress()): its cubes lit as that shape, not as steps
instance uniform vec3 shape_c;
instance uniform vec3 shape_r;
uniform float round_k = 0.62;
varying float v_soft;
varying vec3 v_pos;
varying vec3 v_n;

void bend(inout vec3 v, inout vec3 n, inout float soft, vec3 c, vec3 d, vec3 q, float s) {
	vec3 rel = (v - c) / rad;
	// 0 outside the shape and at its base on her chest, 1 at its front; the upper slope held to her more
	float inside = 1.0 - smoothstep(0.9, 1.45, length(rel * vec3(1.0, 1.0, 0.75)));
	float fw = clamp((rel.z + 0.85) / 1.85, 0.0, 1.0);
	float w = inside * fw * fw * (3.0 - 2.0 * fw);
	w *= 1.0 - 0.35 * clamp(rel.y, 0.0, 1.0);
	vec3 off = v - c;
	v += w * d + w * w * q;
	v += vec3(-0.5 * s * off.x, s * off.y, -0.5 * s * off.z) * w;
	// shaded as the smooth round shape it stands for (not its cubes' steps), turned as it bends: the light runs over
	// it as it moves
	vec3 tilt = cross(vec3(0.0, 0.0, 1.0), d + q) / rad.z;
	vec3 round_n = normalize(rel / rad + vec3(0.0, 0.0, 0.15));
	round_n = normalize(round_n + cross(tilt * 1.4, round_n));
	float smooth_k = inside * smoothstep(-0.6, 0.2, rel.z);
	n = normalize(mix(n + cross(tilt * w * 1.4, n), round_n, smooth_k * 0.9));
	soft = smooth_k;
}

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float soft = 0.0;
	v_pos = VERTEX;
	v_n = NORMAL;
	if (mode == 1) {
		if (distance(v.xy, c_l.xy) < distance(v.xy, c_r.xy)) {
			bend(v, n, soft, c_l, d_l, q_l, s_l);
		} else {
			bend(v, n, soft, c_r, d_r, q_r, s_r);
		}
	} else if (mode == 2) {
		float w = pow(clamp((root_y - v.y) / len_y, 0.0, 1.0), power);
		float rip = sin(atan(v.x, v.z) * 6.0 + phase) * wave * w;
		v += w * h_d + vec3(v.x, 0.0, v.z) * rip;
		n = normalize(n - vec3(h_d.x, 0.0, h_d.z) * w * 2.0 * n.y);
	}
	VERTEX = v;
	NORMAL = n;
	v_soft = soft;
}

void fragment() {
	if (shape_r.x > 0.0 && v_soft < 0.02) {
		// an oval body, or a limb (much longer than it's wide): round along its length, its ends capped
		vec3 q = v_pos - shape_c;
		vec3 r = max(shape_r, vec3(0.005));
		float w = min(r.x, r.z);
		vec3 rn;
		if (r.y > w * 1.7) {
			float h = r.y - w;
			q.y = sign(q.y) * max(0.0, abs(q.y) - h);
			rn = normalize(vec3(q.x / (r.x * r.x), q.y / (w * w), q.z / (r.z * r.z)));
		} else {
			rn = normalize(q / (r * r));
		}
		vec3 nl = normalize(mix(normalize(v_n), rn, round_k));
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nl, 0.0)).xyz);
	}
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float skin = step(0.35, c.r) * step(c.b * 1.25, c.r);
	float dark = 1.0 - smoothstep(0.08, 0.2, lum);
	// matt on the cubes' steps (a sheen there is stripes); satin where it's shaded smooth (the chest)
	float sheen = dark * v_soft;
	ROUGHNESS = mix(mix(0.8, 0.5, sheen), 0.6, skin);
	SPECULAR = mix(mix(0.4, 0.6, sheen), 0.35, skin);
}
"""
	return _shader
