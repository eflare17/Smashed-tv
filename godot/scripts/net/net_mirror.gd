class_name NetMirror
extends RefCounted
## Showing what the other player is doing: the pictures lobby life stands in for a character (sitting, lifting,
## lying in bed, carrying Gothica...) are LobbyPics; each one visible under a node is captured (its picture and
## how it stands, in world space) and the other side stands copies of them in the same places. Pictures go over
## once each: a file's path when it has one, else the pixels as a PNG (hair and shirt bakes, the bong's glow).
## Owned by the Online task.

var _ids: Dictionary = {}          # texture instance id -> wire id (what we've sent)
var _next := 1
var _out: Array = []               # [id, path, png] waiting to go
var _tex: Dictionary = {}          # wire id -> Texture2D (what we've had)
var _pics: Dictionary = {}         # key -> Array[LobbyPic] shown here

## The wire id of a texture (queues it to go over the first time).
func tex_id(t: Texture2D) -> int:
	if t == null:
		return 0
	var k := t.get_instance_id()
	if _ids.has(k):
		return _ids[k]
	var id := _next
	_next += 1
	_ids[k] = id
	var path := t.resource_path
	if path != "" and not path.contains("::"):
		_out.append([id, path, PackedByteArray()])
	else:
		var img := t.get_image()
		if img == null or img.is_empty():
			_out.append([id, "", PackedByteArray()])
		else:
			if img.is_compressed():
				img.decompress()
			_out.append([id, "", img.save_png_to_buffer()])
	return id

## Textures to send before the next state that uses them.
func take_outgoing() -> Array:
	var o := _out
	_out = []
	return o

func add_texture(e: Array) -> void:
	var id: int = e[0]
	var path: String = e[1]
	var png: PackedByteArray = e[2]
	var t: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		t = load(path)
	elif png.size() > 0:
		var img := Image.new()
		if img.load_png_from_buffer(png) == OK:
			t = ImageTexture.create_from_image(img)
	_tex[id] = t

func texture(id: int) -> Texture2D:
	return _tex.get(id, null)

func reset_remote() -> void:
	_tex.clear()
	clear_all()

func reset_local() -> void:
	_ids.clear()
	_out.clear()

## The LobbyPics showing under these roots, as [[tex, upp, foot, lift, shift, flip, recolour, modulate, flat, xform]].
## also: pics to take even if hidden (the pose of a player in first person, hidden only from his own eyes).
func capture(roots: Array, also: Array = []) -> Array:
	var out := []
	for r in roots:
		if r == null or not is_instance_valid(r):
			continue
		_capture(r, also, out)
	return out

func _capture(n: Node, also: Array, out: Array) -> void:
	if n is LobbyPic:
		var p: LobbyPic = n
		if (p.is_visible_in_tree() or also.has(p)) and p.texture != null and p.is_inside_tree():
			out.append([tex_id(p.texture), p.units_per_px, p.foot_px, p.lift, p.shift_x, p.flip, p.recolour_for,
				p.modulate, p.flat_to_camera, p.global_transform])
		return
	if n is Node3D and not (n as Node3D).visible and not _has_also(n, also):
		return
	for c in n.get_children():
		_capture(c, also, out)

func _has_also(n: Node, also: Array) -> bool:
	for a in also:
		if a is Node and is_instance_valid(a) and n.is_ancestor_of(a):
			return true
	return false

## Stand copies of the captured pictures under parent (key: whose they are).
func apply(key: String, parent: Node, list: Array, offset := Vector3.ZERO) -> void:
	var have: Array = _pics.get(key, [])
	while have.size() < list.size():
		var p := LobbyPic.new()
		p.name = "NetPic"
		parent.add_child(p)
		p.top_level = true
		have.append(p)
	for i in have.size():
		var p: LobbyPic = have[i]
		if not is_instance_valid(p):
			continue
		if i >= list.size():
			p.visible = false
			continue
		var e: Array = list[i]
		var t := texture(int(e[0]))
		p.visible = t != null
		if t == null:
			continue
		if p.texture != t:
			p.texture = t
		if p.units_per_px != float(e[1]): p.units_per_px = float(e[1])
		if p.foot_px != float(e[2]): p.foot_px = float(e[2])
		if p.lift != float(e[3]): p.lift = float(e[3])
		if p.shift_x != float(e[4]): p.shift_x = float(e[4])
		if p.flip != bool(e[5]): p.flip = bool(e[5])
		if p.recolour_for != String(e[6]): p.recolour_for = String(e[6])
		if p.modulate != e[7]: p.modulate = e[7]
		if p.flat_to_camera != bool(e[8]): p.flat_to_camera = bool(e[8])
		var xf: Transform3D = e[9]
		xf.origin += offset
		p.global_transform = xf
	_pics[key] = have

func clear(key: String) -> void:
	for p in _pics.get(key, []):
		if is_instance_valid(p):
			p.queue_free()
	_pics.erase(key)

func clear_all() -> void:
	for k in _pics.keys():
		clear(k)
