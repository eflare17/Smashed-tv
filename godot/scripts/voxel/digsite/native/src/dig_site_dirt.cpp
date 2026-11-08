// DigSiteGrid's dirt (stage 4): loose and firm ground, like the digger game's dirt_sim.gd but in 3D cells. A cell is
// firm (as the ground was made) or loose (dug and dumped, or a firm wall that gave way). Loose cells fall into air and
// slump down any slope steeper than ~34 degrees (the angle of repose); a firm wall of soil stands straight up to its
// material's height (wall_h: clay higher than dirt, sand hardly at all) and gives way past that or past ~60 degrees,
// its rim turning loose (to slump in turn). Rock never gives way here (cave-ins are stage 7's). Cells only ever swap
// places with air, so no dirt is ever made or lost. Only chunks where something changed are worked on (a chunk goes to
// sleep when nothing in it moves), within a time budget: what's left waits for the next call. Owned by the voxel
// session.
#include "dig_site_grid.h"

#include <algorithm>
#include <chrono>
#include <cmath>

using namespace godot;

// the eight ways round (the first four straight, the last four corners)
static const int DX[8] = {1, -1, 0, 0, 1, 1, -1, -1};
static const int DZ[8] = {0, 0, 1, -1, 1, -1, 1, -1};
// How far loose dirt may drop over 1, 2, 3 cells out before it slides: ~34 degrees (round(0.67 x the run)), the
// corners' runs 1.41 times as long. A one-cell step is fine (a staircase averages the angle out).
static const int LOOSE_OK[2][3] = {{1, 2, 2}, {1, 2, 3}};
// What a firm wall may drop more than its straight-up height over 2 and 3 cells out: ~60 degrees (1.73 a cell)
static const int BED_MORE[2] = {2, 3};

void DigSiteGrid::set_physics(const PackedInt32Array &walls) {
	for (int i = 0; i < NMAT; i++)
		wall_h[i] = i < walls.size() ? std::max(0, (int)walls[i]) : 0;
}

// the chunk a cell's in and, near a chunk's side, the next chunk over (what it does reaches 4 cells)
void DigSiteGrid::wake_near(int x, int y, int z) {
	if (awake.empty())
		return;
	int x0 = std::max(0, x - 4) / CS, x1 = std::min(w - 1, x + 4) / CS;
	int y0 = std::max(0, y - 4) / CS, y1 = std::min(h - 1, y + 4) / CS;
	int z0 = std::max(0, z - 4) / CS, z1 = std::min(d - 1, z + 4) / CS;
	for (int cy = y0; cy <= y1; cy++)
		for (int cz = z0; cz <= z1; cz++)
			for (int cx = x0; cx <= x1; cx++)
				awake[(cy * ccz + cz) * ccx + cx] = 1;
}

void DigSiteGrid::wake_all() {
	std::fill(awake.begin(), awake.end(), 1);
}

int DigSiteGrid::awake_count() const {
	int n = 0;
	for (uint8_t a : awake)
		n += a;
	return n + std::max(0, (int)wake_list.size() - wake_at);
}

// How far down from level y the ground is at column (x, z): the air cells from y down (0: solid at y; the site's sides
// count as solid), at most limit
int DigSiteGrid::drop_at(int x, int y, int z, int limit) const {
	if (x < 0 || z < 0 || x >= w || z >= d)
		return 0;
	int n = 0;
	for (int yy = y; yy >= 0 && n < limit; yy--) {
		if ((cells[idx(x, yy, z)] & MAT_MASK) != 0)
			break;
		n++;
	}
	return n;
}

// the cell at index `from` moved to (x, y, z) (air: a swap, so nothing's made or lost)
void DigSiteGrid::move_cell(int from, int x, int y, int z) {
	int to = idx(x, y, z);
	cells[to] = cells[from];
	cells[from] = 0;
	moved_bits[to >> 6] |= (1ull << (to & 63));
	moved_list.push_back(to);
	int fx = from % w, fz = (from / w) % d, fy = from / (w * d);
	touch(fx, fy, fz);
	touch(x, y, z);
	moves_total++;
}

// One chunk worked through once, bottom up: -> cells moved (or turned loose)
int DigSiteGrid::settle_chunk(int ci) {
	int cx = ci % ccx, cz = (ci / ccx) % ccz, cy = ci / (ccx * ccz);
	int n = 0;
	bool flip = (tick_n & 1) != 0;
	for (int ly = 0; ly < CS; ly++) {
		int y = cy * CS + ly;
		for (int lz0 = 0; lz0 < CS; lz0++) {
			int lz = flip ? CS - 1 - lz0 : lz0;
			int z = cz * CS + lz;
			for (int lx0 = 0; lx0 < CS; lx0++) {
				int lx = flip ? CS - 1 - lx0 : lx0;
				int x = cx * CS + lx;
				int i = idx(x, y, z);
				uint8_t c = cells[i];
				int m = c & MAT_MASK;
				if (m == 0 || m >= NMAT)
					continue;
				if (moved_bits[i >> 6] & (1ull << (i & 63)))
					continue;
				if (c & LOOSE) {
					// falling: down through air, up to 3 cells a tick
					if (air_at(x, y - 1, z)) {
						int ny = y - 1;
						while (ny - 1 >= 0 && air_at(x, ny - 1, z) && y - ny < 3)
							ny--;
						move_cell(i, x, ny, z);
						n++;
						continue;
					}
					// slumping: the way it's steepest past the angle of repose (a random one of the steepest)
					int best = -1, best_ex = 0, ties = 0;
					for (int k = 0; k < 8; k++) {
						int corner = k >= 4 ? 1 : 0;
						if (corner && !air_at(x + DX[k], y, z) && !air_at(x, y, z + DZ[k]))
							continue;      // (no squeezing between two cells' corners)
						int ex = 0;
						for (int r = 1; r <= 3; r++) {
							int dp = drop_at(x + DX[k] * r, y, z + DZ[k] * r, 6);
							if (dp == 0)
								break;     // (blocked at this level: nothing further counts)
							ex = std::max(ex, dp - LOOSE_OK[corner][r - 1]);
						}
						if (ex <= 0)
							continue;
						if (ex > best_ex) {
							best = k;
							best_ex = ex;
							ties = 1;
						} else if (ex == best_ex && (next() % (uint32_t)(++ties)) == 0) {
							best = k;
						}
					}
					if (best >= 0) {
						int nx = x + DX[best], nz = z + DZ[best];
						move_cell(i, nx, air_at(nx, y - 1, nz) ? y - 1 : y, nz);
						n++;
					}
					continue;
				}
				// a roof (air under it) wider than its material spans: it's going (dig_site_cave.cpp)
				if (span_max[m] > 0 && air_at(x, y - 1, z))
					check_roof(x, y, z, m);
				// a firm wall's rim (soil with air over it): too tall or too steep, it gives way (turns loose)
				int wh = wall_h[m];
				if (wh <= 0 || !(y + 1 >= h || air_at(x, y + 1, z)))
					continue;
				bool give = false;
				for (int k = 0; k < 4 && !give; k++) {
					int d1 = drop_at(x + DX[k], y, z + DZ[k], wh + 2);
					if (d1 == 0)
						continue;
					if (d1 > wh) {
						give = true;
						break;
					}
					for (int r = 2; r <= 3; r++) {
						int dp = drop_at(x + DX[k] * r, y, z + DZ[k] * r, wh + 5);
						if (dp == 0)
							break;
						if (dp > wh + BED_MORE[r - 2]) {
							give = true;
							break;
						}
					}
				}
				if (give) {
					cells[i] = (uint8_t)(c | LOOSE);
					touch(x, y, z);
					moves_total++;
					n++;
				}
			}
		}
	}
	return n;
}

// The awake chunks worked through, for up to budget_usec: -> cells moved. (A chunk where nothing moved goes to sleep;
// one where something did stays awake, and wakes the chunks beside it.)
int DigSiteGrid::settle(int budget_usec) {
	if (awake.empty())
		return 0;
	auto t0 = std::chrono::steady_clock::now();
	if (wake_at >= (int)wake_list.size()) {
		// a new tick: this tick's chunks, bottom up (falling dirt lands before what's above it's looked at)
		wake_list.clear();
		wake_at = 0;
		for (int i = 0; i < (int)awake.size(); i++)
			if (awake[i]) {
				awake[i] = 0;
				wake_list.push_back(i);
			}
		for (int b : moved_list)
			moved_bits[b >> 6] = 0;
		moved_list.clear();
		tick_n++;
		cave_tick();
	}
	int n = 0;
	while (wake_at < (int)wake_list.size()) {
		n += settle_chunk(wake_list[wake_at]);
		wake_at++;
		auto us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();
		if (us > budget_usec)
			break;
	}
	return n;
}

// n loose cells of m dropped on column (x, z), stacked up from its top (they slump from there): -> how many fitted
int DigSiteGrid::drop_column(int x, int z, int m, int n) {
	if (x < 0 || z < 0 || x >= w || z >= d || m <= 0 || m >= NMAT)
		return 0;
	int y = column_top(x, z) + 1;
	int put = 0;
	while (put < n && y < h) {
		cells[idx(x, y, z)] = (uint8_t)(m | LOOSE);
		touch(x, y, z);
		y++;
		put++;
	}
	return put;
}
