// DigSiteGrid's ground as drawn (the owner, 9 Nov: "it's really jumpy ... have a look at the web one"). A section's
// mesh is made from the cells now and then; the surface moves every frame (the loose layer, dig_site_layer.cpp, moves
// mm at a time). So each column keeps its top as its shown mesh has it (meshed_top, from a snapshot taken when the
// section's mesh was made, committed when it's shown), and how far the true surface stands off that (show_off, in
// cells: the cells changed since, and the layer's mm). The ground's, the lumps' and the grass's shaders read it
// (DsTerrain uploads show_offsets, half floats, and show_topo_bytes, RGBA8: meshed top, loose depth in 1/8 cells,
// the surface's material) and draw each column's top there. The host's is exact every frame; a guest's (the host's
// ground arrives 15 times a second) eases to it. A change too big to draw that way (a blast, a cave-in) shows when
// the mesh is made again. Owned by the voxel session.
#include "dig_site_grid.h"

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

// cells: a bigger change just shows when its section's redrawn (a blast, a cave-in). It was 3 (the gliding's limit),
// but a blade heaps dirt up and cuts it away faster than the near redraw keeps up: past 3 the surface stood where the
// mesh had it, half a metre into the blade or under the heap, for a frame or ten (the telemetry, 9 Nov). A flat mesh
// drawn 2 m off is still the right shape (the offsets are a smooth field over it)
static const float BIGGEST_OFF = 16.0f;

// float -> IEEE half (round to nearest; offsets are small, normal numbers)
static uint16_t to_half(float f) {
	uint32_t x;
	std::memcpy(&x, &f, 4);
	uint32_t sign = (x >> 16) & 0x8000u;
	int32_t e = (int32_t)((x >> 23) & 0xff) - 127 + 15;
	uint32_t mant = x & 0x7fffffu;
	if (e <= 0)
		return (uint16_t)sign;                 // (tiny: zero)
	if (e >= 31)
		return (uint16_t)(sign | 0x7bffu);     // (huge: the biggest)
	uint32_t hm = mant >> 13;
	if (mant & 0x1000u) {                      // round
		hm++;
		if (hm == 0x400u) {
			hm = 0;
			e++;
			if (e >= 31)
				return (uint16_t)(sign | 0x7bffu);
		}
	}
	return (uint16_t)(sign | ((uint32_t)e << 10) | hm);
}

void DigSiteGrid::show_reset() {
	size_t n = (size_t)w * d;
	meshed_top.assign(n, -1);
	show_off.assign(n, 0.0f);
	show_tgt.assign(n, 0.0f);
	show_half.assign(n, 0);
	show_topo.assign(n * 4, 0);
	easing.clear();
	easing_on.assign(n, 0);
	col_loose.assign(n, 0);
	int cw = (w + SW - 1) / SW, cd = (d + SW - 1) / SW;
	loose_cols.assign((size_t)cw * cd, 0);
	col_seen.assign(n, 0);
	col_list.clear();
	topo_dirty = true;
	off_dirty = true;
}

// A section column's tops as they are now, when its mesh is made (each of its SW x SW columns' top cell, x fastest;
// -1: none)
PackedInt32Array DigSiteGrid::section_tops(int sx, int sz) const {
	PackedInt32Array out;
	out.resize(SW * SW);
	int32_t *o = out.ptrw();
	for (int z = 0; z < SW; z++)
		for (int x = 0; x < SW; x++) {
			int gx = sx * SW + x, gz = sz * SW + z;
			o[z * SW + x] = (gx < w && gz < d) ? top_cached(gx, gz) : -1;
		}
	return out;
}

// Where column i's surface truly stands off its meshed top (cells), and its loose depth and material for the shaders
void DigSiteGrid::show_target(size_t i) {
	int x = (int)(i % w), z = (int)(i / w);
	int t = top_cached(x, z);
	int mt = meshed_top[i];
	float tgt = 0.0f;
	if (mt >= 0 && t >= 0) {
		tgt = (float)(t - mt) + (fr.empty() ? 0.0f : fr[i] / (float)MM);
		if (std::fabs(tgt) > BIGGEST_OFF)
			tgt = 0.0f;
	}
	show_tgt[i] = tgt;
	if (show_off[i] != tgt && !easing_on[i]) {
		easing_on[i] = 1;
		easing.push_back((int)i);
	}
	// its loose depth (eighths of a cell) and the material on top
	int deep = loose_depth_mm(x, z, 255 * MM / 8);
	int m = 0;
	if (!fr.empty() && fr[i] > 0)
		m = fm[i] & MAT_MASK;
	else if (t >= 0)
		m = cells[idx(x, t, z)] & MAT_MASK;
	uint8_t *q = &show_topo[i * 4];
	uint8_t g = (uint8_t)std::min(255, (deep * 8 + MM / 2) / MM);
	if (q[1] != g || q[2] != (uint8_t)m) {
		q[1] = g;
		q[2] = (uint8_t)m;
		topo_dirty = true;
	}
	// (lumps are drawn over a section column with any loose dirt on top)
	uint8_t lo = deep >= 20 ? 1 : 0;
	if (lo != col_loose[i]) {
		col_loose[i] = lo;
		int cw = (w + SW - 1) / SW;
		uint16_t &lc = loose_cols[(size_t)(z / SW) * cw + x / SW];
		lc = (uint16_t)(lo ? lc + 1 : (lc > 0 ? lc - 1 : 0));
		topo_dirty = true;
	}
}

// That section's mesh shown: its columns' tops are what it draws now. A column's taken on if its top (now or as it
// was drawn) is in this section's height (sy), so a deep section shown doesn't move a surface another section draws.
// What's drawn stays where it was (the offset takes up the difference), then goes where it should.
void DigSiteGrid::commit_tops(int sx, int sy, int sz, const PackedInt32Array &snap) {
	if (meshed_top.empty())
		show_reset();
	if (snap.size() < SW * SW)
		return;
	const int32_t *p = snap.ptr();
	int y0 = sy * SH, y1 = y0 + SH;
	for (int z = 0; z < SW; z++)
		for (int x = 0; x < SW; x++) {
			int gx = sx * SW + x, gz = sz * SW + z;
			if (gx >= w || gz >= d)
				continue;
			size_t i = (size_t)gz * w + gx;
			int t = p[z * SW + x];
			int old = meshed_top[i];
			bool mine = (t >= y0 && t < y1) || (old >= y0 && old < y1) || old < 0;
			if (!mine || t < 0)
				continue;
			if (old >= 0 && t != old) {
				float off = show_off[i] + (float)(old - t);
				show_off[i] = std::fabs(off) > BIGGEST_OFF ? 0.0f : off;
				show_half[i] = to_half(show_off[i]);
				off_dirty = true;
			}
			meshed_top[i] = (int16_t)t;
			uint8_t *q = &show_topo[i * 4];
			q[0] = (uint8_t)std::clamp(t, 0, 255);
			q[3] = 255;
			show_target(i);
		}
	topo_dirty = true;
	topo_urgent = true;
}

// Each frame: the columns changed since looked at again, and the drawn surface brought to the true one (at once, or
// eased at ease_rate a second: a guest's). -> the offsets changed (upload them)
bool DigSiteGrid::show_update(float dt, float ease_rate) {
	if (meshed_top.empty())
		return false;
	for (int k : col_list) {
		col_seen[k] = 0;
		show_target((size_t)k);
	}
	col_list.clear();
	if (easing.empty()) {
		bool was = off_dirty;
		off_dirty = false;
		return was;
	}
	float kk = ease_rate <= 0.0f ? 1.0f : 1.0f - std::exp(-ease_rate * dt);
	size_t keep = 0;
	for (size_t e = 0; e < easing.size(); e++) {
		int i = easing[e];
		float tgt = show_tgt[i];
		float o = show_off[i] + (tgt - show_off[i]) * kk;
		if (std::fabs(tgt - o) < 0.004f) {
			o = tgt;
			easing_on[i] = 0;
		} else {
			easing[keep++] = i;
		}
		show_off[i] = o;
		show_half[i] = to_half(o);
	}
	easing.resize(keep);
	off_dirty = false;
	return true;
}

// How far each column's surface is drawn off its meshed top (cells), half floats, x fastest: an RH texture's bytes
PackedByteArray DigSiteGrid::show_offsets() const {
	PackedByteArray out;
	size_t n = (size_t)w * d;
	out.resize(n * 2);
	if (show_half.size() == n)
		std::memcpy(out.ptrw(), show_half.data(), n * 2);
	else
		std::memset(out.ptrw(), 0, n * 2);
	return out;
}

// Each column's meshed top cell, loose depth (eighths of a cell) and surface material (RGBA8: an image's bytes)
PackedByteArray DigSiteGrid::show_topo_bytes() const {
	PackedByteArray out;
	size_t n = (size_t)w * d * 4;
	out.resize(n);
	if (show_topo.size() == n)
		std::memcpy(out.ptrw(), show_topo.data(), n);
	else
		std::memset(out.ptrw(), 0, n);
	return out;
}

// Loose columns on top in each section column (x fastest): where lumps are worth drawing
PackedInt32Array DigSiteGrid::loose_columns() const {
	PackedInt32Array out;
	out.resize(loose_cols.size());
	for (size_t i = 0; i < loose_cols.size(); i++)
		out.set(i, loose_cols[i]);
	return out;
}

// Whether the tops/loose depth/material texture needs uploading (and it's taken as done): when a section's mesh was
// just shown (its meshed tops changed: always), or anything changed and any is set (the loose depth and material can
// wait a frame: DsTerrain asks with any 30 times a second)
bool DigSiteGrid::take_topo_dirty(bool any) {
	if (!topo_dirty || (!any && !topo_urgent))
		return false;
	topo_dirty = false;
	topo_urgent = false;
	return true;
}
