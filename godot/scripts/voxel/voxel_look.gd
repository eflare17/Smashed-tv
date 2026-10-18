class_name VoxelLook
extends RefCounted
## Jared's look from the mirror and the wardrobe (lobby life's LobbyLook: the hair style and the picture printed on
## his singlet) on the block Jared: the style picks which hair part he wears (assets/voxel/jared/hair_<style>.vox),
## the picture is painted onto the singlet's front (and back) voxels, darkened by the singlet's folds the way
## LobbyLook does it on the pictures. Owned by the voxel session. All static.

static var _orig_torso = null      # the torso's own grid, kept to repaint from
static var _done_rev := -1

## Bumped when the look changes (LobbyLook.rev).
static var rev: int:
	get:
		LobbyLook.load_saved()
		return LobbyLook.rev

## The hair part's style key ("classic", "mullet", ...).
static func style_key() -> String:
	LobbyLook.load_saved()
	var b := LobbyLook.beards()
	if b.is_empty():
		return "classic"
	return String(b[posmod(LobbyLook.style, b.size())].key)

static func _is_shirt(c: int) -> bool:
	var k := c - 1
	var r := (k >> 16) & 255
	var g := (k >> 8) & 255
	var b := k & 255
	return (g > 1.2 * r and g > 1.2 * b and g > 80) or (r < 60 and g >= 70 and b <= 1.2 * g) or (r < 30 and g >= 45 and g > 2 * r and b <= 1.4 * g)

## Paints the print (or puts the plain singlet back) on the model's torso, once per look change.
static func apply_print(model: VoxelModel) -> void:
	if model == null or not model.parts.has("torso"):
		return
	if _done_rev == rev and _orig_torso != null:
		return
	_done_rev = rev
	if _orig_torso == null:
		_orig_torso = model.grid("torso")
	var g: Dictionary = {"size": _orig_torso.size, "cells": (_orig_torso.cells as PackedInt32Array).duplicate()}
	var any := false
	if LobbyLook.art_front != null:
		any = _paint(g, LobbyLook.art_front, LobbyLook.place_front, false) or any
	var back_art: Image = LobbyLook.art_back if LobbyLook.art_back != null else LobbyLook.art_front
	if back_art != null:
		any = _paint(g, back_art, LobbyLook.place_back if LobbyLook.art_back != null else LobbyLook.place_front, true) or any
	model.set_grid("torso", g if any else _orig_torso)

## The picture on the singlet's outside voxels facing front (or back): like LobbyLook._print on a frame.
static func _paint(g: Dictionary, art: Image, place: Rect2, back: bool) -> bool:
	var s: Vector3i = g.size
	var cells: PackedInt32Array = g.cells
	# the surface: the front-most (or back-most) voxel of each column across x, y
	var surf := PackedInt32Array()
	surf.resize(s.x * s.y)
	surf.fill(-1)
	for y in s.y:
		for x in s.x:
			for k in s.z:
				var z := (s.z - 1 - k) if not back else k
				if cells[x + s.x * (y + s.y * z)] != 0:
					surf[x + s.x * y] = z
					break
	var mask := PackedByteArray()
	mask.resize(s.x * s.y)
	var x0 := s.x
	var x1 := -1
	var y0 := s.y
	var y1 := -1
	var lum_sum := 0.0
	var lum_n := 0
	for y in s.y:
		for x in s.x:
			var z := surf[x + s.x * y]
			if z < 0:
				continue
			var c := cells[x + s.x * (y + s.y * z)]
			if _is_shirt(c):
				mask[x + s.x * y] = 1
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
				var k2 := c - 1
				lum_sum += 0.3 * ((k2 >> 16) & 255) + 0.59 * ((k2 >> 8) & 255) + 0.11 * (k2 & 255)
				lum_n += 1
	if lum_n < 60:
		return false
	# the rows between the singlet's edges count (the lettering), skin doesn't
	for y in range(y0, y1 + 1):
		var lo := -1
		var hi := -1
		for x in range(x0, x1 + 1):
			if mask[x + s.x * y] == 1:
				if lo < 0:
					lo = x
				hi = x
		for x in range(maxi(lo, 0), hi + 1):
			if mask[x + s.x * y] == 0 and surf[x + s.x * y] >= 0:
				var c2 := cells[x + s.x * (y + s.y * surf[x + s.x * y])] - 1
				var r := (c2 >> 16) & 255
				var gg := (c2 >> 8) & 255
				var b := c2 & 255
				if not (r > 110 and r > 1.15 * gg and r > 1.3 * b):
					mask[x + s.x * y] = 2
	var avg := maxf(1.0, lum_sum / lum_n)
	var bw := x1 - x0 + 1
	var bh := y1 - y0 + 1
	var pw := maxi(1, int(round(place.size.x * bw)))
	var ph := maxi(1, int(round(place.size.y * bh)))
	var pic := art.duplicate()
	if back:
		pic.flip_x()          # seen from behind
	pic.resize(pw, ph, Image.INTERPOLATE_BILINEAR if LobbyLook.smooth else Image.INTERPOLATE_NEAREST)
	var plx := (1.0 - place.position.x - place.size.x) if back else place.position.x
	var px0 := x0 + int(round(plx * bw))
	var amt := 0.3 if back else 0.75
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var mk := mask[x + s.x * y]
			if mk == 0:
				continue
			# picture rows go down the screen, model rows up: the top of the box is y1
			var sx := x - px0
			var sy := (y1 - y) - int(round(place.position.y * bh))
			if sx < 0 or sy < 0 or sx >= pw or sy >= ph:
				continue
			var pc: Color = pic.get_pixel(sx, sy)
			if pc.a < 0.02:
				continue
			var z := surf[x + s.x * y]
			var idx := x + s.x * (y + s.y * z)
			var o := cells[idx] - 1
			var oc := Color8((o >> 16) & 255, (o >> 8) & 255, o & 255)
			var shade := 1.0
			if mk == 1:
				var lum := 0.3 * oc.r8 + 0.59 * oc.g8 + 0.11 * oc.b8
				shade = 1.0 - amt + amt * clampf(roundf(255.0 * lum / avg), 60.0, 255.0) / 255.0
			var col := Color(pc.r * shade, pc.g * shade, pc.b * shade)
			if pc.a < 1.0:
				col = oc.lerp(col, pc.a)
			cells[idx] = ((col.r8 << 16) | (col.g8 << 8) | col.b8) + 1
	return true
