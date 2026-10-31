# (Copied from stkilda-godot scripts/world/people.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkPeople
extends RefCounted
## The cast, in 3D pixel art like Shane: built from 5 cm voxels (the same size as the heads, SkModels._head), so
## there's room for boots, a watch, a tattoo. They're jointed: each arm hangs from a shoulder pivot ("ArmL" /
## "ArmR", with a "Hand" hold point) and each leg from a hip ("LegL" / "LegR"), all inside "Body" (which bobs when
## they walk). Built 2.75 m tall and scaled to SCALE, so beside the cars they're a touch bigger than life, like the
## browser game's sprites. Facing -z, feet at y = 0. The shirt logo is a hi-res decal (assets/decals), not voxels.
##
## Jaymie: front desk / does everything. Dirty-blonde ponytail, black logo tee, tan work shorts and boots, a sleeve
## tattoo on her right forearm, a mint pendant, a mint wristband, long black almond nails. Carries a tablet.
## Sam: the mechanic. Long wavy dark-brown mullet swept back, short beard, black logo tee, grey-khaki work shorts,
## white crew socks with a black stripe, tan boots, a watch.
## The reference art is in reference/.

const SCALE := 0.72
const U := 0.05                       # one voxel

const SKIN := Color("#dba07f")
const SKIN_DK := Color("#b97d5e")
const TAN_BOOT := Color("#c8913f")
const KHAKI := Color("#b7a57c")
const TEE := Color("#1d1e22")
const INK := Color("#2e3a46")

## A decal texture from assets/decals (made by tools/make_decals.gd), mipmapped, cached.
static var _decals := {}
static func decal(name: String) -> Texture2D:
	if not _decals.has(name):
		_decals[name] = load("res://assets/decals/%s.png" % name)      # the imported texture (works in an exported build)
	return _decals[name]

static func _decal_mat(name: String, gloss := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = decal(name)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.1 if gloss else 0.9
	m.metallic_specular = 0.9 if gloss else 0.3
	return m

## A person. spec keys (all optional):
##   head: SkModels._head kind ("jaymie", "sam", "tow", or anything for short hair); hair: colour
##   shirt, sleeves ("short" / "long"), logo (the shirt decal), hivis (reflective strips)
##   bottoms ("shorts" / "pants"), pants, boots, socks: colours
##   tattoo_r (sleeve tattoo on the right forearm), wristband_l (colour), watch_l, necklace (pendant colour)
##   nail_art: long almond nails with her art on (SkPeople._nail_art)
##   size: how big they are against a grown-up (a kid's under 1); head_size: their head against their body (a kid's
##   is bigger for their size)
static func person(spec: Dictionary) -> Node3D:
	var hair: Color = spec.get("hair", Color("#4a2e1c"))
	var shirt: Color = spec.get("shirt", Color("#3d6fb6"))
	var pants: Color = spec.get("pants", Color("#2e3a55"))
	var boots: Color = spec.get("boots", TAN_BOOT)
	var socks: Color = spec.get("socks", Color("#18181c"))
	var shorts: bool = spec.get("bottoms", "pants") == "shorts"
	var long_sleeves: bool = spec.get("sleeves", "short") == "long"

	var root := Node3D.new()
	root.name = spec.get("name", "Person")
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	# torso: waistband y 24, shirt y 25..41 (untucked, over the waistband's top), x -6..6, z -3..3 (front is -z)
	var t := SkModels.Vox.new()
	t.fill(Vector3i(-6, 24, -3), Vector3i(6, 25, 3), pants, 0.05)
	if not shorts:
		t.fill(Vector3i(-6, 25, -3), Vector3i(6, 25, 3), Color("#4a3322"))          # belt
		t.put(Vector3i(0, 25, -3), SkData.C_STEEL_LIGHT)
	t.fill(Vector3i(-6, 26, -3), Vector3i(6, 41, 3), shirt, 0.04)
	t.fill(Vector3i(-6, 26, -3), Vector3i(6, 26, 3), shirt.darkened(0.25))          # the hem
	t.fill(Vector3i(-2, 41, -3), Vector3i(2, 41, -2), SKIN_DK)                      # crew neck opening
	t.fill(Vector3i(-3, 41, -3), Vector3i(-3, 41, -2), shirt.darkened(0.3))
	t.fill(Vector3i(3, 41, -3), Vector3i(3, 41, -2), shirt.darkened(0.3))
	t.fill(Vector3i(-2, 40, -3), Vector3i(2, 40, -3), shirt.darkened(0.3))
	if spec.get("polo", false):
		# a polo: a collar standing up round the neck and folded over at the front, a short button placket
		t.fill(Vector3i(-3, 42, -3), Vector3i(3, 42, 2), shirt.lightened(0.04))
		t.fill(Vector3i(-3, 42, -2), Vector3i(3, 43, 2), shirt.lightened(0.04))
		t.fill(Vector3i(-2, 42, -2), Vector3i(2, 43, 1), SKIN_DK)                       # (the neck inside it)
		t.fill(Vector3i(-3, 41, -4), Vector3i(-1, 41, -4), shirt.lightened(0.08))       # the collar's points
		t.fill(Vector3i(1, 41, -4), Vector3i(3, 41, -4), shirt.lightened(0.08))
		t.fill(Vector3i(0, 36, -3), Vector3i(0, 40, -3), shirt.darkened(0.2))           # the placket
		t.put(Vector3i(0, 38, -4), Color("#3a3c40"))
		t.put(Vector3i(0, 36, -4), Color("#3a3c40"))
	if spec.get("hivis", false):
		for y in [31, 35]:
			t.fill(Vector3i(-6, y, -3), Vector3i(6, y, 3), Color("#e6e9ec"))
	t.fill(Vector3i(-2, 42, -2), Vector3i(2, 43, 1), SKIN_DK)                       # neck
	body.add_child(SkModels._voxels("Torso", t, U))
	if spec.get("logo", false):
		var q := MeshInstance3D.new()
		q.name = "Logo"
		var qm := QuadMesh.new()
		# a small one on the left of the chest, up near the shoulder (like their real shirts, reference/)
		qm.size = Vector2(0.24, 0.24)
		q.mesh = qm
		q.material_override = _decal_mat("logo_shirt")
		q.position = Vector3(-0.17, 1.86, -0.179)
		q.rotation.y = PI
		body.add_child(q)
	# logos on the chest, from any picture: [[res path, width (m), which side: -1 their left, +1 their right]]
	for lg in spec.get("chest_logos", []):
		var tex: Texture2D = load(lg[0])
		var w: float = lg[1]
		var q := MeshInstance3D.new()
		q.name = "ChestLogo"
		var qm := QuadMesh.new()
		qm.size = Vector2(w, w * tex.get_height() / tex.get_width())
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.roughness = 0.9
		q.material_override = m
		q.position = Vector3(lg[2] * 0.17, 1.84, -0.179)
		q.rotation.y = PI
		body.add_child(q)
	# printed tees (decals): a print on the front (on her left, like the real one) and a big one across the back
	if spec.has("print_front"):
		var pf := MeshInstance3D.new()
		pf.name = "PrintFront"
		var pfm := QuadMesh.new()
		pfm.size = Vector2(0.62, 0.62)
		pf.mesh = pfm
		pf.material_override = _decal_mat(spec.print_front)
		pf.position = Vector3(-0.07, 1.6, -0.179)
		pf.rotation.y = PI
		body.add_child(pf)
	if spec.has("print_back"):
		var pb := MeshInstance3D.new()
		pb.name = "PrintBack"
		var pbm := QuadMesh.new()
		pbm.size = Vector2(0.6, 0.6)
		pb.mesh = pbm
		pb.material_override = _decal_mat(spec.print_back)
		pb.position = Vector3(0, 1.5, 0.179)
		body.add_child(pb)
	if spec.has("necklace"):
		_necklace(body, spec.necklace)

	var head := SkModels._voxels("Head", SkModels._head(spec.get("head", ""), hair), U)
	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 44 * U, 0)
	head_pivot.scale = Vector3.ONE * float(spec.get("head_size", 1.0))
	head_pivot.add_child(head)
	body.add_child(head_pivot)

	# legs from the hips (y 24): boots, socks, bare knees under shorts or khaki pants down to the boots
	for side in [["L", -1], ["R", 1]]:
		var sx: int = side[1]
		var l := SkModels.Vox.new()
		l.fill(Vector3i(0, -24, -4), Vector3i(4, -19, 2), boots, 0.05)
		l.fill(Vector3i(0, -24, -4), Vector3i(4, -24, 2), Color("#5a3e22"))         # sole
		l.fill(Vector3i(0, -23, -4), Vector3i(4, -22, -4), boots.darkened(0.15))     # toe cap
		l.fill(Vector3i(0, -19, -2), Vector3i(4, -19, 2), boots.darkened(0.2))       # padded collar
		for y in [-21, -20]:
			l.fill(Vector3i(1, y, -3), Vector3i(3, y, -3), Color("#e9dcc0"))         # laces
		if shorts:
			l.fill(Vector3i(0, -18, -2), Vector3i(4, -18, 2), socks)
			l.fill(Vector3i(0, -17, -2), Vector3i(4, -9, 2), SKIN, 0.03)
			if spec.get("crew_socks", false):
				l.fill(Vector3i(0, -17, -2), Vector3i(4, -15, 2), Color("#f2f2f0"))
				l.fill(Vector3i(0, -16, -2), Vector3i(4, -16, 2), Color("#18181c"))
			l.fill(Vector3i(0, -12, -2), Vector3i(4, -12, -2), SKIN_DK)              # knee
			l.fill(Vector3i(0, -8, -2), Vector3i(4, -1, 2), pants, 0.05)
			l.fill(Vector3i(-1 if sx < 0 else 0, -8, -3), Vector3i(4 if sx < 0 else 5, -7, 3), pants.lightened(0.08))   # rolled cuff
		else:
			l.fill(Vector3i(0, -18, -3), Vector3i(4, -1, 2), pants, 0.05)
			l.fill(Vector3i(0, -18, -3), Vector3i(4, -18, 3), pants.darkened(0.15))   # cuff over the boot
			l.fill(Vector3i(0, -11, -3), Vector3i(4, -11, -3), pants.darkened(0.12))  # knee seam
			var ox := 0 if sx < 0 else 4                                             # cargo pocket, outside
			var px := -1 if sx < 0 else 5
			l.fill(Vector3i(px, -11, -1), Vector3i(px, -6, 1), pants.darkened(0.08))
			l.fill(Vector3i(px, -6, -1), Vector3i(px, -6, 1), pants.darkened(0.2))
			l.put(Vector3i(ox, -3, -3), pants.darkened(0.2))
		var pivot := Node3D.new()
		pivot.name = "Leg" + side[0]
		pivot.position = Vector3(sx * 0.15, 24 * U, 0)
		var mi := SkModels._voxels("Voxels", l, U)
		mi.position.x = -0.1
		pivot.add_child(mi)
		body.add_child(pivot)

	# arms from the shoulders (y 41): sleeve, upper arm, forearm, wrist, hand
	for side in [["L", -1], ["R", 1]]:
		var sx: int = side[1]
		var outer := 0 if sx < 0 else 3
		var a := SkModels.Vox.new()
		var sleeve_end := -19 if long_sleeves else -7
		a.fill(Vector3i(0, sleeve_end, -2), Vector3i(3, 0, 1), shirt, 0.04)
		a.fill(Vector3i(0, sleeve_end, -2), Vector3i(3, sleeve_end, 1), shirt.darkened(0.25))
		if spec.get("hivis", false) and long_sleeves:
			a.fill(Vector3i(0, -12, -2), Vector3i(3, -12, 1), Color("#e6e9ec"))
		if not long_sleeves:
			a.fill(Vector3i(0, -19, -2), Vector3i(3, sleeve_end - 1, 1), SKIN, 0.03)
			a.fill(Vector3i(0, -12, 1), Vector3i(3, -12, 1), SKIN_DK)               # elbow
		if sx > 0 and spec.get("tattoo_r", false):
			_tattoo(a, -19, -13)
		a.fill(Vector3i(0, -20, -2), Vector3i(3, -20, 1), SKIN, 0.03)                # wrist
		if sx < 0 and spec.get("bracelets_l", false):
			a.fill(Vector3i(0, -20, -2), Vector3i(3, -20, 1), Color("#d8b8e8"))
			a.fill(Vector3i(0, -19, -2), Vector3i(3, -19, 1), Color("#e9d9a6"))
			a.put(Vector3i(0, -19, -2), Color("#f4f4f4"))
		if sx < 0 and spec.has("wristband_l"):
			a.fill(Vector3i(0, -20, -2), Vector3i(3, -20, 1), spec.wristband_l)
		if sx < 0 and spec.get("watch_l", false):
			a.fill(Vector3i(0, -20, -2), Vector3i(3, -20, 1), Color("#3a2a1e"))
			a.fill(Vector3i(outer, -20, -2), Vector3i(outer, -20, 0), Color("#d9dde2"))
			a.put(Vector3i(outer, -20, -1), Color("#2a3a4a"))
		# split at the elbow: the upper arm hangs from the shoulder, the forearm ("Fore") from the elbow
		var up := SkModels.Vox.new()
		var fore := SkModels.Vox.new()
		for p in a.cells:
			(up if p.y >= -11 else fore).cells[p] = a.cells[p]
		var pivot := Node3D.new()
		pivot.name = "Arm" + side[0]
		pivot.position = Vector3(sx * 0.43, 41 * U, -0.025)
		var mi := SkModels._voxels("Voxels", up, U)
		mi.position.x = -0.075
		pivot.add_child(mi)
		var elbow := Node3D.new()
		elbow.name = "Fore"
		elbow.position = Vector3(0, -11 * U, 0)
		var fm := SkModels._voxels("Voxels", fore, U)
		fm.position = Vector3(-0.075, 11 * U, 0)
		elbow.add_child(fm)
		pivot.add_child(elbow)
		# a hold point at the hand, for tablets, spanners, keys
		var hand := Node3D.new()
		hand.name = "Hand"
		hand.position = Vector3(0, -1.13 + 11 * U, -0.04)
		elbow.add_child(hand)
		# the hand itself: jointed, with separate fingers (SkPeople.hand), at the end of the wrist
		var hm := hand(sx, SKIN, _nail_art(sx) if spec.get("nail_art", false) else {})
		hm.position = Vector3(0, -0.45, -0.025)
		elbow.add_child(hm)
		body.add_child(pivot)
	root.scale = Vector3.ONE * SCALE * float(spec.get("size", 1.0))
	return root

## A sleeve tattoo round the forearm (rows y0..y1): dark ink swirls with a touch of mint.
static func _tattoo(a: SkModels.Vox, y0: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in 4:
			for z in range(-2, 2):
				if x != 0 and x != 3 and z != -2 and z != 1:
					continue
				var h := absi((x * 92837111) ^ (y * 689287499) ^ (z * 283923481)) % 7
				if h < 3:
					a.put(Vector3i(x, y, z), INK)
				elif h == 3:
					a.put(Vector3i(x, y, z), INK.lerp(SkData.C_MINT, 0.5))

## A fine chain from the neck to a mint pendant on the chest (small boxes, finer than the voxels).
static func _necklace(body: Node3D, pendant: Color) -> void:
	var gold := Color("#c9a85a")
	var top_y := 2.06
	for sx in [-1.0, 1.0]:
		var c := SkModels.box(body, Vector3(0.012, 0.13, 0.012), Vector3(sx * 0.045, top_y - 0.05, -0.183), gold, 0.3)
		c.rotation.z = sx * 0.45
	var p := SkModels.box(body, Vector3(0.045, 0.045, 0.015), Vector3(0, top_y - 0.125, -0.186), pendant, 0.3)
	p.rotation.z = PI / 4.0

static func jaymie() -> Node3D:
	var p := person({
		"name": "Jaymie", "head": "jaymie", "hair": Color("#b48a55"),
		"shirt": TEE, "logo": true, "bottoms": "shorts", "pants": KHAKI.darkened(0.05),
		"boots": TAN_BOOT, "tattoo_r": true, "wristband_l": SkData.C_MINT,
		"necklace": SkData.C_MINT, "nail_art": true,
	})
	# the tablet sits in front of her, screen tilted up to her face, her hands on its sides (the "tablet" pose)
	var tb := tablet(false)
	tb.name = "HeldTablet"
	tb.scale = Vector3.ONE / SCALE
	tb.position = Vector3(0, 1.42, -0.58)
	tb.rotation.x = 0.7
	p.get_node("Body").add_child(tb)
	p.set_meta("carry", [POSES.tablet[0], POSES.tablet[1]])      # she keeps the tablet up as she walks
	return p

## Chloe: the content creator (THAT. Content Agency). Long straight blonde hair with darker roots, glasses, a pink
## THAT. tee (the back reads "Your business called. It needs better content."), light acid-wash denim shorts,
## white sneakers, bracelets, her phone up filming. From her photos in reference/.
static func chloe() -> Node3D:
	var p := person({
		"name": "Chloe", "head": "chloe", "hair": Color("#ecd49e"),
		"shirt": Color("#ff9ccb"), "print_front": "chloe_front", "print_back": "chloe_back",
		"bottoms": "shorts", "pants": Color("#a9c0d8"), "boots": Color("#f2f2f0"), "socks": Color("#f2f2f0"),
		"bracelets_l": true,
	})
	var ph := SkProps.phone(Color("#eeeeec"))
	ph.name = "Phone"
	ph.position = Vector3(0.0, -0.02, -0.06)
	ph.rotation = Vector3(0.0, 0.0, PI / 2.0)
	hold(p, "ArmR", ph)
	p.set_meta("carry_r", true)
	return p

static func sam() -> Node3D:
	return person({
		"name": "Sam", "head": "sam", "hair": Color("#36261b"),
		"shirt": TEE, "logo": true, "bottoms": "shorts", "pants": Color("#8c8572"), "boots": TAN_BOOT, "watch_l": true,
		"socks": Color("#f2f2f0"), "crew_socks": true,
	})

## Kev, PJ's manager (from reference/people/kev.webp): short ginger hair and a short ginger beard, a black work polo
## with the oval PJ's 4x4 logo on his right chest and the Donway Caravans logo (the Australia map) on his left, black
## pants, black work shoes.
static func kev() -> Node3D:
	return person({
		"name": "Kev", "head": "kev", "hair": Color("#b4532a"),
		"shirt": Color("#16171a"), "polo": true, "sleeves": "long", "pants": Color("#18191c"), "boots": Color("#121214"), "socks": Color("#121214"),
		"chest_logos": [["res://assets/pjs/logo_pjs.png", 0.25, 1.0], ["res://assets/pjs/logo_donway_white.png", 0.17, -1.0]],
	})

## Maddie, from Where's Shane (copied from her sprite there, assets/sprite_maddie.png in that game), made to match
## Kev: wavy brown hair past her shoulders, a purple long-sleeved top, dark charcoal pants and dark shoes.
static func maddie() -> Node3D:
	return person({
		"name": "Maddie", "head": "maddie", "hair": Color("#5e3620"),
		"shirt": Color("#5a2a82"), "sleeves": "long", "pants": Color("#2b2c35"), "boots": Color("#1c1a22"), "socks": Color("#1c1a22"),
	})

## Fletcher, a kid (from the owner's photos, 2026-10-29): short dirty-blond hair with a fringe swept to the side,
## blue eyes, green mirrored sunnies, a plain white tee and khaki shorts. Shorter than the grown-ups, about up to
## their shoulders, with a bigger head for his size. (His shoes aren't in the photos: white sneakers.)
static func fletcher() -> Node3D:
	return person({
		"name": "Fletcher", "head": "fletcher", "hair": Color("#a8875c"), "size": 0.78, "head_size": 1.12,
		"shirt": Color("#ecebe3"), "bottoms": "shorts", "pants": Color("#857d68"), "boots": Color("#ecebe6"), "socks": Color("#f2f2f0"),
	})

static func driver() -> Node3D:
	return person({
		"name": "Driver", "head": "", "hair": Color("#2a1d14"),
		"shirt": Color("#c74b3c"), "pants": Color("#2e3a55"), "boots": Color("#5a4636"),
	})

static func tow_driver() -> Node3D:
	return person({
		"name": "TowDriver", "head": "tow", "hair": Color("#3a2a1e"),
		"shirt": SkData.C_ORANGE, "hivis": true, "sleeves": "long", "pants": Color("#26324a"),
		"boots": Color("#3a2a1e"),
	})

## Put a prop in someone's hand (on that arm's "Hand" point, on the forearm).
static func hold(p: Node3D, arm: String, prop: Node3D) -> void:
	var hand: Node3D = p.get_node("Body/%s/Fore/Hand" % arm)
	for c in hand.get_children():
		c.queue_free()
	hand.add_child(prop)

## Poses, as [left upper arm, left forearm, right upper arm, right forearm] rotations. On a left arm +z swings the
## hand in toward the body; on a right arm -z does. +x lifts it forward.
const POSES := {
	"idle": [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
	"tablet": [Vector3(0.1, 0, 0.1), Vector3(1.2, 0, 0.25), Vector3(0.1, 0, -0.1), Vector3(1.2, 0, -0.25)],
	"thumbs_up": [Vector3.ZERO, Vector3.ZERO, Vector3(0.4, 0, -0.1), Vector3(1.9, 0, -0.2)],
	"hands_on_head": [Vector3(0.3, 0, -2.3), Vector3(0, 0, 2.3), Vector3(0.3, 0, 2.3), Vector3(0, 0, -2.3)],
	"spanner": [Vector3(0.3, 0, 0.1), Vector3(0.6, 0, 0), Vector3(0.6, 0, -0.1), Vector3(1.1, 0, 0)],
	"wave": [Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 1.3), Vector3(0, 0, 1.4)],
	"phone": [Vector3(0.5, 0, 0.15), Vector3(1.3, 0, 0.35), Vector3(0.5, 0, -0.15), Vector3(1.3, 0, -0.35)],
	"filming": [Vector3(0.05, 0, 0.05), Vector3(0.3, 0, 0), Vector3(1.25, 0, -0.25), Vector3(0.7, 0, -0.35)],
	"on_phone": [Vector3.ZERO, Vector3(0.15, 0, 0), Vector3(0.35, 0, 0.75), Vector3(2.35, 0, -1.1)],
	"juggle": [Vector3(0.6, 0, 0.1), Vector3(1.3, 0, 0.3), Vector3(0.35, 0, 0.75), Vector3(2.35, 0, -1.1)],
	"head_in_hand": [Vector3(0.55, 0, 0.55), Vector3(2.2, 0, 0.5), Vector3(0.2, 0, -0.05), Vector3(0.9, 0, -0.2)],
	"keys": [Vector3.ZERO, Vector3(0.15, 0, 0), Vector3(0.6, 0, -0.05), Vector3(1.0, 0, 0)],
	"cheer": [Vector3(0, 0, -1.2), Vector3(0, 0, -1.2), Vector3(0, 0, 1.2), Vector3(0, 0, 1.2)],
	"sitting": [Vector3(0.45, 0, 0.12), Vector3(0.9, 0, 0.1), Vector3(0.45, 0, -0.12), Vector3(0.9, 0, -0.1)],
}

## Sat down (in the ute) or stood up again: legs out in front from the hips, hands in the lap.
static func sit(p: Node3D, on: bool) -> void:
	if not p.has_node("Body"):
		return
	for leg in ["LegL", "LegR"]:
		(p.get_node("Body/" + leg) as Node3D).rotation = Vector3(PI / 2.0 if on else 0.0, 0, 0)
	pose(p, "sitting" if on else "idle")

## Ease someone toward a pose (k = 1 snaps to it). Rotations only, so poses blend in the trailer.
static func pose(p: Node3D, name: String, k: float = 1.0) -> void:
	var want: Array = POSES.get(name, POSES.idle)
	var joints := [p.get_node("Body/ArmL"), p.get_node("Body/ArmL/Fore"), p.get_node("Body/ArmR"), p.get_node("Body/ArmR/Fore")]
	for i in 4:
		var j: Node3D = joints[i]
		j.rotation = j.rotation.lerp(want[i], k)
	var c: Array = CURLS.get(name, CURLS.idle)
	for i in 2:
		var hm: Node3D = p.get_node("Body/%s/Fore/HandModel" % ["ArmL", "ArmR"][i])
		var now: float = hm.get_meta("curl", 0.2)
		var amt := lerpf(now, c[i], k)
		hm.set_meta("curl", amt)
		curl(hm, amt, 0.0 if name == "thumbs_up" and i == 1 else -1.0)

## How far each hand's fingers curl in each pose: [left, right], 0 open .. 1 a fist.
const CURLS := {
	"idle": [0.2, 0.2], "tablet": [0.6, 0.6], "thumbs_up": [0.2, 1.0], "hands_on_head": [0.3, 0.3],
	"spanner": [0.3, 0.95], "wave": [0.2, 0.0], "phone": [0.6, 0.6], "filming": [0.3, 0.8],
	"on_phone": [0.2, 0.8], "juggle": [0.6, 0.8], "head_in_hand": [0.3, 0.2], "keys": [0.2, 0.7], "cheer": [0.9, 0.9],
	"sitting": [0.4, 0.4],
}

## Jaymie's tablet, after the reference art: a chunky rugged case in 5 mm voxels with stepped, rounded edges and
## corners, raised corner bumpers, a camera bump and two status lights on the back, buttons down the right side
## and an orange light on the top edge; the booking app lit on its screen (its +y face), in a black bezel.
## Built at true size (0.28 x 0.19 m); when it's held it's sized up by 1 / SCALE like the props.
const TV := 0.005
static func tablet(held := true) -> Node3D:
	var t := Node3D.new()
	t.name = "Tablet"
	var grey := Color("#4f5157")
	var dark := Color("#36383d")
	var rim := Color("#61646b")
	var v := SkModels.Vox.new()
	const W := 28
	const D := 19
	const R := 5
	# the case: five layers, the top and bottom ones stepped in so the edges read rounded
	for y in range(-2, 3):
		var inset := 1 if absi(y) == 2 else 0
		for x in range(-W, W):
			for z in range(-D, D):
				if _outside(x, z, W - inset, D - inset, R - inset):
					continue
				var c := rim if y == 2 else (dark if y == -2 else grey)
				v.put(Vector3i(x, y, z), SkModels._shade(c, x, y, z, 0.03))
	# a panel line round the back
	for x in range(-W + 4, W - 4):
		for z in range(-D + 4, D - 4):
			if x == -W + 4 or x == W - 5 or z == -D + 4 or z == D - 5:
				v.put(Vector3i(x, -2, z), dark.darkened(0.25))
	# the black bezel round the screen
	for x in range(-W + 3, W - 3):
		for z in range(-D + 3, D - 3):
			v.put(Vector3i(x, 2, z), Color("#17181b"))
	# raised corner bumpers, a voxel proud all round
	for y in range(-3, 4):
		for x in range(-W - 1, W + 1):
			for z in range(-D - 1, D + 1):
				if absf(x + 0.5) < W - 7.5 or absf(z + 0.5) < D - 7.5:
					continue
				if _outside(x, z, W + 1, D + 1, R + 1):
					continue
				var p := Vector3i(x, y, z)
				if not v.cells.has(p) or absi(y) >= 2:
					v.put(p, SkModels._shade(dark, x, y, z, 0.04))
	# the camera bump on the back, its lens and a glint
	v.fill(Vector3i(14, -3, -16), Vector3i(21, -3, -9), dark.darkened(0.15))
	v.fill(Vector3i(16, -4, -14), Vector3i(19, -4, -11), Color("#141518"))
	v.put(Vector3i(17, -4, -13), Color("#3a4f63"))
	# two status lights low on the back, buttons down the right side, an orange light on the top edge
	v.fill(Vector3i(-4, -3, D - 5), Vector3i(-3, -3, D - 5), Color("#9aa0a8"))
	v.fill(Vector3i(1, -3, D - 5), Vector3i(2, -3, D - 5), Color("#b89a9a"))
	v.fill(Vector3i(W, -1, -11), Vector3i(W, 0, -7), grey.lightened(0.1))
	v.fill(Vector3i(W, -1, -5), Vector3i(W, 0, -2), grey.lightened(0.1))
	v.fill(Vector3i(5, 0, -D - 1), Vector3i(6, 0, -D - 1), SkData.C_ORANGE)
	var mi := SkModels._voxels("Case", v, TV)
	mi.position = Vector3(0.5, -0.5, 0.5) * TV
	t.add_child(mi)
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var qm := QuadMesh.new()
	qm.size = Vector2(2 * (W - 4) * TV, 2 * (D - 4) * TV)
	screen.mesh = qm
	screen.rotation.x = -PI / 2.0
	screen.position.y = 0.0128
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = screen_texture()
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = sm
	t.add_child(screen)
	if held:
		# held up in front of her, tilted toward her face
		t.position = Vector3(0.24, -0.02, 0.0)
		t.rotation = Vector3(-0.45, 0.0, 0.0)
		t.scale = Vector3.ONE / SCALE
	return t

## Outside a rounded rectangle (half sizes w, d in voxels, corner radius r)?
static func _outside(x: int, z: int, w: int, d: int, r: int) -> bool:
	var dx := maxf(0.0, absf(x + 0.5) - (w - r - 0.5))
	var dz := maxf(0.0, absf(z + 0.5) - (d - r - 0.5))
	return absf(x + 0.5) > w or absf(z + 0.5) > d or dx * dx + dz * dz > r * r + 0.5

## A little pixel-art booking app for screens (tablet, phone, the booking board): mint header, rows of jobs.
static var _screen_tex: ImageTexture
static func screen_texture() -> ImageTexture:
	if _screen_tex:
		return _screen_tex
	var img := Image.create(64, 44, false, Image.FORMAT_RGBA8)
	img.fill(Color("#f6f7f5"))
	img.fill_rect(Rect2i(0, 0, 64, 8), SkData.C_MINT_DARK)
	img.fill_rect(Rect2i(2, 2, 20, 4), SkData.C_WHITE)
	img.fill_rect(Rect2i(56, 2, 6, 4), SkData.C_MAROON)
	var cols := [SkData.C_MINT, SkData.C_ORANGE, SkData.C_MAROON, SkData.C_MINT, SkData.C_STEEL]
	for i in 5:
		var y := 11 + i * 6
		img.fill_rect(Rect2i(2, y, 4, 4), cols[i])
		img.fill_rect(Rect2i(8, y, 30 - (i * 7) % 12, 2), Color("#3a3f4a"))
		img.fill_rect(Rect2i(8, y + 3, 18, 1), Color("#a4a9b2"))
		img.fill_rect(Rect2i(50, y, 12, 3), cols[i].lightened(0.4))
	_screen_tex = ImageTexture.create_from_image(img)
	return _screen_tex

# ================================================================ hands

## A hand in 12.5 mm voxels, jointed like the reference art (reference/hands_nails_tablet*.jpg): a chunky palm,
## four fingers each in three segments with a gap between them, a two-segment thumb. Every segment is its own pivot,
## so curl() bends them to hold things. Built as a right hand (sx = 1) and mirrored for the left. The wrist is at
## the origin and the fingers point down (-y); the palm faces in toward the body (-x on the right hand) and the
## thumb is at the front (-z). nails: finger name -> nail decal ("nail_plain" etc.); none if it's empty.
const HU := 0.0125
## each finger: name, its first z (it's 3 wide), its three segment lengths
const HAND_FINGERS := [["index", -7, [5, 4, 3]], ["middle", -3, [6, 4, 3]], ["ring", 1, [5, 4, 3]], ["little", 5, [4, 3, 3]]]
const THUMB := [5, 4]

static func hand(sx: int, skin := SKIN, nails := {}) -> Node3D:
	var root := Node3D.new()
	root.name = "HandModel"
	root.set_meta("side", sx)
	var dk := skin.darkened(0.14)
	var hi := skin.lightened(0.07)
	# the palm: 15 wide, 6 thick, 11 long, its corners knocked off, the back of the hand a shade lighter
	var p := SkModels.Vox.new()
	p.fill(Vector3i(-3, -11, -7), Vector3i(2, -1, 7), skin, 0.03)
	p.fill(Vector3i(2, -10, -6), Vector3i(2, -2, 6), hi, 0.02)
	for c in [Vector3i(-3, -1, -7), Vector3i(2, -1, -7), Vector3i(-3, -1, 7), Vector3i(2, -1, 7), Vector3i(-3, -11, 7), Vector3i(2, -11, 7)]:
		p.cells.erase(c)
	for fg in HAND_FINGERS:                                          # a crease under each knuckle
		var z0: int = fg[1]
		p.fill(Vector3i(2, -11, z0), Vector3i(2, -11, z0 + 2), dk)
	p.fill(Vector3i(-3, -8, -8), Vector3i(1, -2, -8), skin, 0.03)    # the mound at the base of the thumb
	root.add_child(_hand_mesh("Palm", p, sx))
	for fg in HAND_FINGERS:
		var parent: Node3D = root
		var lens: Array = fg[2]
		var z0: int = fg[1]
		for i in 3:
			var seg := Node3D.new()
			seg.name = "%s%d" % [fg[0], i]
			seg.position = Vector3(0, -11, 0) * HU if i == 0 else Vector3(0, -int(lens[i - 1]), 0) * HU
			parent.add_child(seg)
			var len: int = lens[i]
			var v := SkModels.Vox.new()
			v.fill(Vector3i(-2, -len, z0), Vector3i(0, -1, z0 + 2), skin, 0.03)
			v.fill(Vector3i(0, -1, z0), Vector3i(0, -1, z0 + 2), dk)          # the crease at this joint
			if i == 0:
				v.fill(Vector3i(1, -2, z0), Vector3i(1, -1, z0 + 2), skin)     # the knuckle
			if i == 2:
				for c in [Vector3i(-2, -len, z0), Vector3i(-2, -len, z0 + 2), Vector3i(0, -len, z0), Vector3i(0, -len, z0 + 2)]:
					v.cells.erase(c)                                          # a rounded fingertip
			seg.add_child(_hand_mesh("Voxels", v, sx))
			parent = seg
		if nails.get(fg[0], "") != "":
			_nail(parent, nails[fg[0]], Vector3(sx * (HU + 0.0015), -2.6 * HU, (z0 + 1) * HU), Vector3(sx, 0, 0), Vector3.DOWN, 2.6 * HU, 5.0 * HU)
	# the thumb, off the front of the palm, angled forward
	var tp: Node3D = root
	for i in 2:
		var seg := Node3D.new()
		seg.name = "thumb%d" % i
		seg.position = Vector3(0, -2, -8) * HU if i == 0 else Vector3(0, -int(THUMB[0]), 0) * HU
		tp.add_child(seg)
		var len: int = THUMB[i]
		var v := SkModels.Vox.new()
		v.fill(Vector3i(-2, -len, -1), Vector3i(0, -1, 1), skin, 0.03)
		v.fill(Vector3i(0, -1, -1), Vector3i(0, -1, 1), dk)
		if i == 1:
			for c in [Vector3i(-2, -len, -1), Vector3i(-2, -len, 1), Vector3i(0, -len, -1), Vector3i(0, -len, 1)]:
				v.cells.erase(c)
		seg.add_child(_hand_mesh("Voxels", v, sx))
		tp = seg
	if nails.get("thumb", "") != "":
		_nail(tp, nails["thumb"], Vector3(sx * (HU + 0.0015), -2.0 * HU, 0), Vector3(sx, 0, 0), Vector3.DOWN, 2.6 * HU, 5.0 * HU)
	curl(root, 0.2)
	return root

## Bend a hand's fingers: 0 open flat .. 1 a fist. thumb: its own amount (or the same as the fingers if < 0).
static func curl(h: Node3D, amount: float, thumb := -1.0) -> void:
	var sx: int = h.get_meta("side")
	var k := [0.9, 1.15, 0.8]
	for fg in HAND_FINGERS:
		var n: Node3D = h
		for i in 3:
			n = n.get_node("%s%d" % [fg[0], i])
			n.rotation.z = -sx * amount * k[i] * 1.5
	var t := amount if thumb < 0.0 else thumb
	var t0: Node3D = h.get_node("thumb0")
	t0.rotation = Vector3(0.5, 0.0, -sx * t * 0.8)
	t0.get_node("thumb1").rotation.z = -sx * t * 0.9

## A hand part's voxels as a mesh, mirrored for the left hand, centred across its thickness.
static func _hand_mesh(name: String, v: SkModels.Vox, sx: int) -> MultiMeshInstance3D:
	if sx < 0:
		var m := SkModels.Vox.new()
		for p in v.cells:
			m.cells[Vector3i(-p.x - 1, p.y, p.z)] = v.cells[p]
		v = m
	var mi := SkModels._voxels(name, v, HU)
	mi.position = Vector3(0.5 * HU, 0, 0)
	return mi

## Jaymie's nail art: left thumb the crossed-spanner logo, right thumb the name in script, right index the oil can,
## right middle the battery, left index the engine light; the rest plain glossy black.
static func _nail_art(sx: int) -> Dictionary:
	var a := {"thumb": "nail_plain", "index": "nail_plain", "middle": "nail_plain", "ring": "nail_plain", "little": "nail_plain"}
	if sx > 0:
		a.merge({"thumb": "nail_script", "index": "nail_oil", "middle": "nail_battery"}, true)
	else:
		a.merge({"thumb": "nail_logo", "index": "nail_engine"}, true)
	return a

# ================================================================ the close-up: Jaymie's hands on the tablet

## Her two hands gripping the tablet, the same jointed hands she has in the game, for the close-up shots. The tablet
## lies flat, screen up (+y), its top edge to -z; she's at +z. Her palms are against the back with the fingers along
## it toward the middle (a camera behind the tablet sees the fingernails), and her thumbs come over the edge onto the
## screen (a camera over her shoulder sees the thumbnails). "KeyLight" and "FillLight" light it.
const CLOSE_SCALE := 0.42

static func closeup_hands() -> Node3D:
	var root := Node3D.new()
	root.name = "HandsCloseup"
	root.add_child(tablet(false))
	var s := CLOSE_SCALE
	var hs := HU * s
	for sx in [1, -1]:
		var f := float(sx)
		var h := hand(sx, SKIN, _nail_art(sx))
		root.add_child(h)
		curl(h, 0.0, 0.0)
		# local x -> world down/up (the palm faces the tablet's back), local y -> outward (fingers point in)
		var hx := Transform3D(Basis(Vector3(0, -f, 0) * s, Vector3(f, 0, 0) * s, Vector3(0, 0, 1) * s), Vector3(f * 0.19, -0.0135 - 3.0 * hs, 0.0))
		h.transform = hx
		# the thumb over the edge, lying on the screen, its nail up
		var tw := Transform3D(Basis(Vector3(0, f, 0) * s, Vector3(f, 0, 0) * s, Vector3(0, 0, -1) * s), Vector3(f * 0.137, 0.0133 + 2.0 * hs, -0.025))
		(h.get_node("thumb0") as Node3D).transform = hx.affine_inverse() * tw
	var key := OmniLight3D.new()
	key.name = "KeyLight"
	key.position = Vector3(0.1, 0.35, 0.25)
	key.omni_range = 1.5
	key.light_energy = 0.7
	root.add_child(key)
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(-0.1, -0.35, -0.25)
	fill.omni_range = 1.5
	fill.light_energy = 0.5
	root.add_child(fill)
	return root

## A long almond nail: a glossy quad with the nail art, lying on a fingertip (normal out of the nail, along toward
## the tip), centred on the tip so half of it runs past the end of the finger.
static func _nail(parent: Node3D, tex: String, at: Vector3, normal: Vector3, along: Vector3, w: float, l: float) -> void:
	var q := MeshInstance3D.new()
	q.name = "Nail_" + tex
	var qm := QuadMesh.new()
	qm.size = Vector2(w, l)
	q.mesh = qm
	var m := _decal_mat(tex, true)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material_override = m
	var side := along.cross(normal).normalized()
	q.transform = Transform3D(Basis(side, along.normalized(), normal.normalized()), at + along.normalized() * 0.002)
	parent.add_child(q)


## A piggyback: the rider up on the carrier's back, arms round his neck, legs round his waist, head over his right
## shoulder; the carrier's hands back under her knees. k eases it on (0 standing apart .. 1 up). Sets the rider's
## whole transform from the carrier's, so call it every frame while it lasts.
static func piggyback(carrier: Node3D, rider: Node3D, k := 1.0) -> void:
	var e := k * k * (3.0 - 2.0 * k)
	var yaw := carrier.global_rotation.y
	var b := Basis(Vector3.UP, yaw)
	var up := carrier.global_position + b * Vector3(-0.28, 0.06, 0.28)
	var off := carrier.global_position + b * Vector3(0.0, 0.0, 0.7)
	rider.global_position = off.lerp(up, e)
	rider.rotation = Vector3(0, yaw, 0)
	var rb: Node3D = rider.get_node("Body")
	rb.rotation.x = -0.18 * e
	rb.position.y = 0.0
	var set_arm := func(p: Node3D, side: String, upper: Vector3, fore: Vector3, curl_amt: float) -> void:
		var a: Node3D = p.get_node("Body/Arm" + side)
		a.rotation = a.rotation.lerp(upper, e)
		var f: Node3D = a.get_node("Fore")
		f.rotation = f.rotation.lerp(fore, e)
		curl(a.get_node("Fore/HandModel"), lerpf(0.2, curl_amt, e))
	set_arm.call(rider, "L", Vector3(1.45, 0, 0.5), Vector3(0.35, 0, 1.0), 0.6)
	set_arm.call(rider, "R", Vector3(1.45, 0, -0.5), Vector3(0.35, 0, -1.0), 0.6)
	(rider.get_node("Body/LegL") as Node3D).rotation = Vector3(1.05, 0, -0.42) * e
	(rider.get_node("Body/LegR") as Node3D).rotation = Vector3(1.05, 0, 0.42) * e
	(rider.get_node("Body/HeadPivot") as Node3D).rotation = Vector3(0.05, 0.2, 0.15) * e
	set_arm.call(carrier, "L", Vector3(-0.1, 0, -0.45), Vector3(0.9, 0, 0.0), 0.8)
	set_arm.call(carrier, "R", Vector3(-0.1, 0, 0.45), Vector3(0.9, 0, 0.0), 0.8)

## Swap someone's head for another kind (the same hair): Kev's beaming one for the coaster video ("kev_happy").
static func set_head(p: Node3D, kind: String, hair: Color) -> void:
	var pivot := p.get_node_or_null("Body/HeadPivot") as Node3D
	if pivot == null:
		return
	var old := pivot.get_node_or_null("Head")
	var head := SkModels._voxels("Head", SkModels._head(kind, hair), U)
	if old:
		head.transform = (old as Node3D).transform
		pivot.remove_child(old)
		old.queue_free()
	pivot.add_child(head)
