// DigSiteGrid's ground as drawn, gliding (the owner, 9 Nov: "it's really jumpy ... have a look at the web one"). The
// cells are 12.5 cm blocks, so a heap grows, slumps and gets pushed a block at a time, and redrawn it jumped a block at
// a time. The digger game's ground is millimetres and glides. So: each column keeps its top as its shown mesh has it
// (meshed_top, from a snapshot taken when the section's mesh was made, committed when it's shown), and when that top
// moves, how far the surface there is still drawn off it (show_off, in cells: it starts where the old surface was) and
// eases away: quickly where dirt's gone (a blade or a bucket took it: the surface mustn't hang up into the steel) and
// gently where it's arrived. The ground's and the lumps' shaders read it (DsTerrain uploads show_offsets and
// show_topo_bytes as textures) and lift or drop the surface by it. Only the drawing glides: the cells, the digging,
// the dirt and the network are as they were. Owned by the voxel session.
#include "dig_site_grid.h"

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

static const float BIGGEST_GLIDE = 3.0f;   // cells: a bigger change (a blast, a cave-in) just shows

void DigSiteGrid::show_reset() {
	size_t n = (size_t)w * d;
	meshed_top.assign(n, -1);
	show_off.assign(n, 0.0f);
	show_topo.assign(n * 4, 0);
	easing.clear();
	easing_on.assign(n, 0);
	int cw = (w + SW - 1) / SW, cd = (d + SW - 1) / SW;
	loose_cols.assign((size_t)cw * cd, 0);
	topo_dirty = true;
}

// A section column's tops as they are now, when its mesh is made: [top cell | loose depth << 8 | top material << 16]
// for each of its SW x SW columns, x fastest (top 255: none)
PackedInt32Array DigSiteGrid::section_tops(int sx, int sz) const {
	PackedInt32Array out;
	out.resize(SW * SW);
	int32_t *o = out.ptrw();
	for (int z = 0; z < SW; z++)
		for (int x = 0; x < SW; x++) {
			int gx = sx * SW + x, gz = sz * SW + z;
			int v = 255;
			if (gx < w && gz < d) {
				int t = top_cached(gx, gz);
				if (t >= 0) {
					int deep = 0;
					for (int y = t; y >= 0 && deep < 255 && (cells[idx(gx, y, gz)] & LOOSE); y--)
						deep++;
					v = t | (deep << 8) | ((cells[idx(gx, t, gz)] & MAT_MASK) << 16);
				}
			}
			o[z * SW + x] = v;
		}
	return out;
}

// That section's mesh shown: its columns' tops are what it draws now. A column's taken on if its top (now or as it
// was drawn) is in this section's height (sy), so a deep section shown doesn't move a surface another section draws
void DigSiteGrid::commit_tops(int sx, int sy, int sz, const PackedInt32Array &snap) {
	if (meshed_top.empty())
		show_reset();
	if (snap.size() < SW * SW)
		return;
	const int32_t *p = snap.ptr();
	int y0 = sy * SH, y1 = y0 + SH;
	int loose = 0;
	for (int z = 0; z < SW; z++)
		for (int x = 0; x < SW; x++) {
			int gx = sx * SW + x, gz = sz * SW + z;
			if (gx >= w || gz >= d)
				continue;
			size_t i = (size_t)gz * w + gx;
			int v = p[z * SW + x];
			int t = v & 255;
			int deep = (v >> 8) & 255, m = (v >> 16) & 255;
			if (t == 255) {
				t = 0;
				deep = 0;
			}
			if (deep > 0)
				loose++;
			int old = meshed_top[i];
			bool mine = (t >= y0 && t < y1) || (old >= y0 && old < y1) || old < 0;
			if (!mine)
				continue;
			if (old < 0) {
				show_off[i] = 0.0f;
			} else if (t != old) {
				float off = show_off[i] + (float)(old - t);
				show_off[i] = std::fabs(off) > BIGGEST_GLIDE ? 0.0f : off;
				if (show_off[i] != 0.0f && !easing_on[i]) {
					easing_on[i] = 1;
					easing.push_back((int)i);
				}
			}
			meshed_top[i] = (int16_t)t;
			uint8_t *q = &show_topo[i * 4];
			q[0] = (uint8_t)t;
			q[1] = (uint8_t)deep;
			q[2] = (uint8_t)m;
			q[3] = 255;
		}
	int cw = (w + SW - 1) / SW;
	loose_cols[(size_t)sz * cw + sx] = (uint16_t)loose;
	topo_dirty = true;
}

// Each frame: the columns still drawn off their tops eased back (up_rate where dirt's arrived and the surface is
// still below it, down_rate where it's gone and the surface still hangs over), per second. -> anything moved
bool DigSiteGrid::ease_tops(float dt, float up_rate, float down_rate) {
	if (easing.empty())
		return false;
	float ku = std::exp(-up_rate * dt), kd = std::exp(-down_rate * dt);
	size_t keep = 0;
	for (size_t k = 0; k < easing.size(); k++) {
		int i = easing[k];
		float o = show_off[i];
		o *= o > 0.0f ? kd : ku;
		if (std::fabs(o) < 0.01f) {
			o = 0.0f;
			easing_on[i] = 0;
		} else {
			easing[keep++] = i;
		}
		show_off[i] = o;
	}
	easing.resize(keep);
	return true;
}

// How far each column's surface is drawn off its top (cells), float32s, x fastest: an RF texture's bytes
PackedByteArray DigSiteGrid::show_offsets() const {
	PackedByteArray out;
	size_t n = (size_t)w * d;
	out.resize(n * 4);
	if (show_off.size() == n)
		std::memcpy(out.ptrw(), show_off.data(), n * 4);
	else
		std::memset(out.ptrw(), 0, n * 4);
	return out;
}

// Each column's top cell, loose depth and top material (RGBA8: an image's bytes)
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

bool DigSiteGrid::take_topo_dirty() {
	bool t = topo_dirty;
	topo_dirty = false;
	return t;
}
