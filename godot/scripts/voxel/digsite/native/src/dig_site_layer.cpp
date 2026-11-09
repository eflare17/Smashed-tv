// DigSiteGrid's loose layer (the owner, 9 Nov: "honestly this looks trash its still so jumpy ... make it look good").
// (The layer can also be firm (FIRM_LAYER in fm): what's left of a firm cell a blade or bucket cut part way into, so
// a cut floor stands exactly where the edge went, firm, not a block's step or a skin of loose dirt. It doesn't slump;
// loose dirt landing on it loosens it.)
// The cells are 12.5 cm blocks, so loose dirt slumped, got pushed and filled buckets a block at a time, and the ground
// jumped a block at a time with it. The digger game's dirt is millimetres: a little moves every frame. So each column
// also keeps the loose dirt lying on its top cell in mm (fr, less than a cell and a half: FR_OVER; fm, its material),
// and its surface stands at (top + 1) x 125 mm + fr. Putting dirt on a column adds to its layer, 125 mm of it becoming
// a loose cell on top once the layer's FR_OVER deep; taking it off takes the layer first, then turns the top cell (a
// loose one; a firm one only for a blade or a bucket cutting, at its rate; never rock) into layer. So the cells hold
// everything solid as before (tunnels, cave-ins, supports, blasts and the network all work on them) and the layer is
// the fine part on top. Loose dirt on a column's top (the layer, and the loose cells under it with nothing but solid
// over them) slumps here, in mm, as the digger game's DirtSim._slump_chunk does: a quarter of what a column stands too
// high over its neighbour (past ~34 degrees: 84 mm over a column's 125, 119 to a corner) slides down to it, every
// frame, in the blocks of columns where something moved. The cell sim (dig_site_dirt.cpp) still drops dirt through
// air, slumps it inside tunnels and lets firm walls give way. Nothing's made or lost: ground_mm() adds it all up.
// Owned by the voxel session.
#include "dig_site_grid.h"

#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>

using namespace godot;

static const int LIMIT = 84;            // mm a column may stand over a straight neighbour (~34 degrees) ...
static const int LIMIT_CORNER = 119;    // ... and over a corner one, 1.41 columns off
static const int SDX[2][4] = {{-1, 1, 0, 0}, {-1, 1, -1, 1}};
static const int SDZ[2][4] = {{0, 0, -1, 1}, {-1, 1, 1, -1}};

// The column's surface (mm up from the grid's floor): its top cell's top, and the layer on it
int DigSiteGrid::height_mm(int x, int z) const {
	if (x < 0 || z < 0 || x >= w || z >= d)
		return 0;
	return (top_cached(x, z) + 1) * MM + (fr.empty() ? 0 : fr[colk(x, z)]);
}

// The loose dirt on the column's top (mm): its layer and the loose cells under it, down to firm ground or air (at
// most `most`)
int DigSiteGrid::loose_depth_mm(int x, int z, int most) const {
	if (x < 0 || z < 0 || x >= w || z >= d || fr.empty())
		return 0;
	size_t k = colk(x, z);
	if (fm[k] & FIRM_LAYER && fr[k] > 0)
		return 0;                       // (firm ground on top)
	int n = fr[k];
	for (int y = top_cached(x, z); y >= 0 && n < most; y--) {
		uint8_t c = cells[idx(x, y, z)];
		if ((c & MAT_MASK) == 0 || !(c & LOOSE))
			break;
		n += MM;
	}
	return std::min(n, most);
}

// A loose cell the layer looks after (the cell sim leaves it be): nothing but solid between it and its column's top
bool DigSiteGrid::lay_owns(int x, int y, int z) const {
	if (fr.empty())
		return false;
	int t = top_cached(x, z);
	if (y > t)
		return false;
	for (int yy = y + 1; yy <= t; yy++)
		if ((cells[idx(x, yy, z)] & MAT_MASK) == 0)
			return false;
	return true;
}

// The column's block of columns queued to slump (and the next block over, near its side: what moves reaches one over)
void DigSiteGrid::lay_wake(int x, int z) {
	if (lay_awake.empty())
		return;
	int bx0 = std::max(0, x - 1) / CS, bx1 = std::min(w - 1, x + 1) / CS;
	int bz0 = std::max(0, z - 1) / CS, bz1 = std::min(d - 1, z + 1) / CS;
	for (int bz = bz0; bz <= bz1; bz++)
		for (int bx = bx0; bx <= bx1; bx++) {
			int b = bz * lcx + bx;
			if (!lay_awake[b]) {
				lay_awake[b] = 1;
				lay_queue.push_back(b);
			}
		}
}

// The column's surface changed: the drawing looks again
void DigSiteGrid::lay_changed(int x, int z) {
	if (col_seen.empty())
		return;
	size_t k = colk(x, z);
	if (!col_seen[k]) {
		col_seen[k] = 1;
		col_list.push_back((int)k);
	}
}

// The column's layer changed: the drawing, the network (its block goes in the next diff) and the slump
void DigSiteGrid::lay_mark(int x, int z) {
	lay_changed(x, z);
	if (lay_touched.empty())
		return;
	int b = (z / CS) * lcx + x / CS;
	lay_touched[b] = 1;
	lay_mod[b] = 1;
	lay_hash_dirty[b] = 1;
}

// Up to amt mm taken off the top of column (x, z), all of one material (m), none from under floor_mm: the layer
// first; with none, the top cell turned into layer (125 mm) and that taken from. Firm ground (a firm cell, or a firm
// layer) only while firm_mm lasts (a blade's rate, mm; counted in cut), never harder than hardest (rock: set, nothing
// taken); a firm cell becomes a firm layer, so what's left under the edge is still firm ground, exactly at the edge (a
// cut floor's neither a block's step nor a skin of loose dirt: the owner's clip, 9 Nov, had loose lumps all down the
// cut). -> mm taken (0: nothing more to be had)
int DigSiteGrid::lay_take(int x, int z, int amt, int floor_mm, int &firm_mm, int hardest, int &m, int &cut, bool &rock) {
	m = 0;
	if (amt <= 0 || x < 0 || z < 0 || x >= w || z >= d || fr.empty())
		return 0;
	size_t k = colk(x, z);
	int t = top_cached(x, z);
	int room = std::min(amt, (t + 1) * MM + fr[k] - floor_mm);
	if (room <= 0)
		return 0;
	if (fr[k] == 0) {
		if (t < 0)
			return 0;
		uint8_t &c = cells[idx(x, t, z)];
		int cm = c & MAT_MASK;
		if (cm == 0 || cm >= NMAT)
			return 0;
		bool firm = !(c & LOOSE);
		if (firm) {
			if (hard[cm] > hardest) {
				rock = true;
				return 0;
			}
			if (firm_mm <= 0)
				return 0;
		}
		c = 0;
		touch(x, t, z);
		if (!col_dirty.empty()) {
			int nt = t - 1;             // (the next solid cell down's the top now)
			while (nt >= 0 && (cells[idx(x, nt, z)] & MAT_MASK) == 0)
				nt--;
			col_top[k] = (int16_t)nt;
			col_dirty[k] = 0;
		}
		fr[k] = (uint8_t)MM;
		fm[k] = (uint8_t)(cm | (firm ? FIRM_LAYER : 0));
	}
	int g = std::min(room, (int)fr[k]);
	if (fm[k] & FIRM_LAYER) {
		if (hard[fm[k] & MAT_MASK] > hardest) {
			rock = true;
			return 0;
		}
		g = std::min(g, firm_mm);
		if (g <= 0)
			return 0;
		firm_mm -= g;
		cut += g;
	}
	fr[k] = (uint8_t)(fr[k] - g);
	m = fm[k] & MAT_MASK;
	lay_mark(x, z);
	lay_wake(x, z);
	return g;
}

// amt mm of m laid on column (x, z) (the edge ring's columns pass it on inward): onto its layer, the layer's 125 mm
// at a time becoming loose cells on top once it's FR_OVER deep. It always all goes on (nothing's refused, so nothing's
// lost). The layer takes the material there's more of.
void DigSiteGrid::lay_put(int x, int z, int amt, int m) {
	if (amt <= 0 || fr.empty())
		return;
	if (m <= 0 || m >= NMAT)
		m = 2;                          // (dirt)
	x = std::clamp(x, LRIM, w - 1 - LRIM);
	z = std::clamp(z, LRIM, d - 1 - LRIM);
	size_t k = colk(x, z);
	int t = top_cached(x, z);
	if (fm[k] & FIRM_LAYER)
		fm[k] &= (uint8_t)~FIRM_LAYER;   // (loose dirt landing on a firm layer loosens it)
	// (up to the grid's roof at most: what won't fit goes on the lowest column round it. Never in a game: pours and
	// spills stop well under it, but nothing may be lost)
	int fits = (h - 1 - t) * MM + (FR_OVER - 1) - fr[k];
	int spare = 0;
	if (amt > fits) {
		spare = amt - std::max(fits, 0);
		amt = std::max(fits, 0);
	}
	if (amt > 0) {
		int f = fr[k];
		if (f == 0 || amt > f)
			fm[k] = (uint8_t)m;
		f += amt;
		if (f >= FR_OVER) {
			while (f >= FR_OVER && t + 1 < h) {
				t++;
				cells[idx(x, t, z)] = (uint8_t)(fm[k] | LOOSE);
				touch(x, t, z);
				f -= MM;
			}
			if (!col_dirty.empty()) {
				col_top[k] = (int16_t)t;    // (known: no need to look down the column again)
				col_dirty[k] = 0;
			}
		}
		fr[k] = (uint8_t)f;
		lay_mark(x, z);
		lay_wake(x, z);
	}
	if (spare > 0) {
		int bx = x, bz = z, low = INT_MAX;
		for (int s = 0; s < 8; s++) {
			int nx = std::clamp(x + (s < 4 ? SDX[0][s] : SDX[1][s - 4]), (int)LRIM, w - 1 - LRIM);
			int nz = std::clamp(z + (s < 4 ? SDZ[0][s] : SDZ[1][s - 4]), (int)LRIM, d - 1 - LRIM);
			int hn = height_mm(nx, nz);
			if (hn < low && (nx != x || nz != z)) {
				low = hn;
				bx = nx;
				bz = nz;
			}
		}
		if (bx != x || bz != z)
			lay_put(bx, bz, spare, m);
	}
}

// amt mm of m that a blade took off column (x, z) and couldn't put anywhere (its heap's full) put back as it was: loose
// dirt as loose, firm ground as firm (the firm layer, a firm cell again once it's a whole one), so a jammed blade
// leaves the ground standing, not loosened under its tracks to be left behind it
void DigSiteGrid::lay_restore(int x, int z, int amt, int m, bool firm) {
	if (amt <= 0 || fr.empty())
		return;
	size_t k = colk(x, z);
	if (!firm || (fr[k] > 0 && !(fm[k] & FIRM_LAYER))) {
		lay_put(x, z, amt, m);
		return;
	}
	int f = fr[k] + amt;
	fm[k] = (uint8_t)((m & MAT_MASK) | FIRM_LAYER);
	int t = top_cached(x, z);
	while (f >= MM && t + 1 < h) {
		t++;
		cells[idx(x, t, z)] = (uint8_t)(m & MAT_MASK);
		touch(x, t, z);
		f -= MM;
	}
	if (!col_dirty.empty()) {
		col_top[k] = (int16_t)t;
		col_dirty[k] = 0;
	}
	fr[k] = (uint8_t)std::min(f, FR_OVER - 1);
	lay_mark(x, z);
	lay_wake(x, z);
}

// One pass over a block of columns, sliding loose dirt to its straight (diag false) or corner neighbours, the digger
// game's DirtSim._slump_chunk: a quarter of how far it stands past the angle of repose goes, taken off its top as the
// layer and its loose cells, put on the neighbour's. Swept a different way each tick, or it'd lean one way. Not into a
// column a blade, bucket or machine stands over (it banks against them). -> anything moved
bool DigSiteGrid::lay_slump_chunk(int ci, bool diag) {
	int cx = ci % lcx, cz = ci / lcx;
	int x0 = cx * CS, z0 = cz * CS;
	int x1 = std::min(x0 + CS, w), z1 = std::min(z0 + CS, d);
	int limit = diag ? LIMIT_CORNER : LIMIT;
	int di = diag ? 1 : 0;
	bool flip = (lay_tick_n & 1) != 0;
	bool moved = false;
	for (int zi = 0; zi < z1 - z0; zi++) {
		int z = flip ? z1 - 1 - zi : z0 + zi;
		if (z < LRIM || z >= d - LRIM)
			continue;
		for (int xi = 0; xi < x1 - x0; xi++) {
			int x = flip ? x0 + xi : x1 - 1 - xi;
			if (x < LRIM || x >= w - LRIM)
				continue;
			size_t k = colk(x, z);
			int t = top_cached(x, z);
			if (t < 0)
				continue;
			// what can slide: its layer, and its top cell if that's loose (more goes next tick); a firm layer doesn't
			if (fm[k] & FIRM_LAYER && fr[k] > 0)
				continue;
			int avail = fr[k];
			uint8_t tc = cells[idx(x, t, z)];
			if ((tc & LOOSE) && (tc & MAT_MASK) != 0)
				avail += MM;
			if (avail <= 0)
				continue;
			int hh = (t + 1) * MM + fr[k];
			for (int s = 0; s < 4 && avail > 0; s++) {
				int nx = x + SDX[di][s], nz = z + SDZ[di][s];
				if (nx < LRIM || nz < LRIM || nx >= w - LRIM || nz >= d - LRIM)
					continue;
				int hn = height_mm(nx, nz);
				int dd = hh - hn;
				if (dd <= limit)
					continue;
				int ry = hn / MM;
				if (ry < h && blocked(idx(nx, ry, nz)))
					continue;
				int mv = std::min((dd - limit + 3) / 4, avail);
				int got = 0;
				while (got < mv) {
					int m = 0, cut = 0, firm = 0;
					bool rock = false;
					int g = lay_take(x, z, mv - got, INT_MIN / 2, firm, 0, m, cut, rock);
					if (g <= 0)
						break;
					lay_put(nx, nz, g, m);
					got += g;
				}
				if (got > 0) {
					hh -= got;
					avail -= got;
					lay_moved += got;
					moved = true;
				}
			}
		}
	}
	return moved;
}

// One tick of the slump (the digger game's: every frame), over the queued blocks of columns, for up to budget_usec:
// straight neighbours and corner ones each pass, in turn. -> mm moved
int DigSiteGrid::layer_step(int budget_usec) {
	if (lay_awake.empty())
		return 0;
	auto t0 = std::chrono::steady_clock::now();
	int64_t was = lay_moved;
	lay_tick_n++;
	bool corner_first = ((lay_tick_n >> 1) & 1) != 0;
	size_t end = lay_queue.size();
	size_t i = lay_at;
	while (i < end) {
		int b = lay_queue[i++];
		lay_awake[b] = 0;
		bool a = lay_slump_chunk(b, corner_first);
		bool c = lay_slump_chunk(b, !corner_first);
		if (a || c) {
			// (anything that moved woke its own block again: looked at next tick)
		}
		auto us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();
		if (us > budget_usec)
			break;
	}
	lay_at = i;
	if (lay_at >= lay_queue.size()) {
		lay_queue.clear();
		lay_at = 0;
	} else if (lay_at > 4096) {
		lay_queue.erase(lay_queue.begin(), lay_queue.begin() + (long)lay_at);
		lay_at = 0;
	}
	return (int)(lay_moved - was);
}

void DigSiteGrid::layer_wake_all() {
	for (int b = 0; b < lcx * lcz; b++)
		if (!lay_awake[b]) {
			lay_awake[b] = 1;
			lay_queue.push_back(b);
		}
}

// The ground's surface at a point (cells, x and z from the grid's corner), blended between the four columns' middles
// round it (cells up from the grid's floor; off the grid, its edge carries on): what the machines ride on
float DigSiteGrid::height_at(float x, float z) const {
	float fx = x - 0.5f, fz = z - 0.5f;
	int ix = (int)std::floor(fx), iz = (int)std::floor(fz);
	float tx = fx - ix, tz = fz - iz;
	float hh[4];
	for (int k = 0; k < 4; k++) {
		int cx = std::clamp(ix + (k & 1), 0, w - 1), cz = std::clamp(iz + (k >> 1), 0, d - 1);
		hh[k] = height_mm(cx, cz) / (float)MM;
	}
	float a = hh[0] + (hh[1] - hh[0]) * tx;
	float b = hh[2] + (hh[3] - hh[2]) * tx;
	return a + (b - a) * tz;
}

// The column's layer: mm | material << 8 (and FIRM_LAYER << 8 if it's firm ground)
int DigSiteGrid::get_layer(int x, int z) const {
	if (x < 0 || z < 0 || x >= w || z >= d || fr.empty())
		return 0;
	size_t k = colk(x, z);
	return fr[k] | (fm[k] << 8);
}

// (tests, and the network's own ground) the column's layer set outright (under FR_OVER)
void DigSiteGrid::set_layer(int x, int z, int mm, int m) {
	if (x < 0 || z < 0 || x >= w || z >= d || fr.empty())
		return;
	size_t k = colk(x, z);
	fr[k] = (uint8_t)std::clamp(mm, 0, FR_OVER - 1);
	fm[k] = (uint8_t)((std::clamp(m & MAT_MASK, 0, NMAT - 1)) | (m & FIRM_LAYER));
	lay_mark(x, z);
	lay_wake(x, z);
}

// mm of m laid on a column (onto its layer; loose cells on top as it fills): -> mm laid (all of it)
int DigSiteGrid::put_layer(int x, int z, int mm, int m) {
	if (mm <= 0)
		return 0;
	lay_put(x, z, mm, m);
	return mm;
}

// Everything solid, in mm over a column's area: every solid cell's 125 and all the layer (so this never changes as the
// dirt moves, whatever moves it)
int64_t DigSiteGrid::ground_mm() const {
	int64_t n = 0;
	for (uint8_t c : cells)
		if ((c & MAT_MASK) != 0)
			n += MM;
	for (uint8_t f : fr)
		n += f;
	return n;
}

// All the loose dirt (mm): loose cells and the layer
int64_t DigSiteGrid::loose_mm() const {
	int64_t n = 0;
	for (uint8_t c : cells)
		if ((c & MAT_MASK) != 0 && (c & LOOSE))
			n += MM;
	for (uint8_t f : fr)
		n += f;
	return n;
}

// One material's (mm): its cells and its layer
int64_t DigSiteGrid::mat_mm(int m) const {
	int64_t n = 0;
	for (uint8_t c : cells)
		if ((c & MAT_MASK) == m)
			n += MM;
	for (size_t k = 0; k < fr.size(); k++)
		if ((fm[k] & MAT_MASK) == m)
			n += fr[k];
	return n;
}
