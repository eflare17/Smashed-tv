// DigSiteGrid's blades (the owner, 8 Nov: "the digging currently feels really terrible ... it's so much better already
// on the web version"): a machine's cutting edge working the ground the way the digger game's DirtSim.blade does,
// not a ball bitten out of it. The edge is a line (a dozer's blade, a bucket's lip, an excavator's teeth); every cell
// standing above it in the columns it passes over (up to its mouth: how high over the edge it reaches) is cut: loose
// cells all at once, firm ones only so many a column each call (the machine's power: a full blade in firm ground cuts
// slowly and the machine bogs). What's cut goes in the bucket (take_most) or, past that or with none, is laid just ahead
// of the edge up to the heap's top, then further ahead, then rolled off past the ends of the edge (a windrow), and only
// last on the lowest place seen: so a dozer banks soil up against its blade and, driving on, picks the heap up again
// and pushes it. Rock (harder than it can cut) above the edge is felt and left. Cells only move (nothing's made or
// lost). Owned by the voxel session.
#include "dig_site_grid.h"

#include <algorithm>
#include <cmath>

using namespace godot;

// how far ahead (cells) what's cut is laid, nearest first, and how far past the edge's end it rolls off
static const float SPILL_AHEAD[] = {2.5f, 4.0f, 6.0f, 8.5f, 12.0f, 16.0f, 20.0f};
static const float SPILL_SIDE[] = {1.5f, 3.0f, 5.0f};

// The column's highest solid cell (y), or -1
static int top_of(const std::vector<uint8_t> &cells, int w, int h, int d, int x, int z) {
	for (int y = h - 1; y >= 0; y--)
		if ((cells[((size_t)y * d + z) * w + x] & 0x1f) != 0)
			return y;
	return -1;
}

// a loose cell of v's material laid on column (x, z) if its top's under top_y: -> placed
bool DigSiteGrid::lay_on(int x, int z, uint8_t v, int top_y) {
	x = std::clamp(x, 8, w - 9);    // (never past the site's edge ring)
	z = std::clamp(z, 8, d - 9);
	int y = top_of(cells, w, h, d, x, z) + 1;
	if (y >= h || y > top_y)
		return false;
	cells[idx(x, y, z)] = (uint8_t)((v & MAT_MASK) | LOOSE);
	touch(x, y, z);
	return true;
}

// A cut cell laid ahead of the edge: just ahead up to top_y, then further, then off past the end, then the lowest seen
void DigSiteGrid::spill(float px, float pz, float fx, float fz, float ox, float oz, float to_end, uint8_t v, int top_y) {
	int lx = -1, lz = -1, low = 1 << 30;
	int na = sizeof(SPILL_AHEAD) / sizeof(float), ns = sizeof(SPILL_SIDE) / sizeof(float);
	for (int k = 0; k < na + ns; k++) {
		float sx, sz;
		int top = top_y;
		if (k < na) {
			sx = px + fx * SPILL_AHEAD[k];
			sz = pz + fz * SPILL_AHEAD[k];
		} else {
			float o = to_end + SPILL_SIDE[k - na];
			sx = px + fx * 2.0f + ox * o;
			sz = pz + fz * 2.0f + oz * o;
			top = top_y - 6;            // (the ridge off the end stands lower than the heap in front)
		}
		int x = (int)std::floor(sx), z = (int)std::floor(sz);
		int cx = std::clamp(x, 8, w - 9), cz = std::clamp(z, 8, d - 9);
		int t = top_of(cells, w, h, d, cx, cz);
		if (t < low) {
			low = t;
			lx = cx;
			lz = cz;
		}
		if (lay_on(x, z, v, top))
			return;
	}
	if (lx >= 0)
		lay_on(lx, lz, v, h - 1);       // (everything round's higher: the lowest seen takes it)
}

// The edge from a to b (cells), going fwd (flat, unit), rows deep (the second row catches what slides under it).
// Cuts what stands above the edge in the columns it covers, up to mouth cells over it; firm cells at most firm_most a
// column (and only those no harder than hardest). Up to take_most go in the bucket (counts); the rest are spilled
// ahead, heaped up to heap cells over the edge. -> {counts: taken by material, taken, moved (spilled), cut (firm),
// rock: hard ground stood in its way}
Dictionary DigSiteGrid::blade_sweep(const Vector3 &a, const Vector3 &b, const Vector3 &fwd, int rows, float mouth,
		int firm_most, int hardest, int take_most, float heap) {
	PackedInt32Array counts;
	counts.resize(NMAT);
	for (int i = 0; i < NMAT; i++)
		counts.set(i, 0);
	int taken = 0, moved = 0, cut = 0;
	bool rock = false;
	float fx = fwd.x, fz = fwd.z;
	float fl = std::sqrt(fx * fx + fz * fz);
	if (fl > 1e-4f) {
		fx /= fl;
		fz /= fl;
	} else {
		fx = 0;
		fz = 0;
	}
	float wx = b.x - a.x, wz = b.z - a.z;
	float width = std::sqrt(wx * wx + wz * wz);
	float ox = width > 1e-4f ? wx / width : 0, oz = width > 1e-4f ? wz / width : 0;
	int steps = std::max(1, (int)std::ceil(width / 0.5f));
	std::vector<int> seen;                       // (a column's cut once a call, however many samples land in it)
	for (int row = 0; row < rows; row++) {
		float back = -1.75f * row;
		for (int s = 0; s <= steps; s++) {
			float t = (float)s / steps;
			float px = a.x + wx * t + fx * back, pz = a.z + wz * t + fz * back;
			float ey = a.y + (b.y - a.y) * t;
			int x = (int)std::floor(px), z = (int)std::floor(pz);
			if (x < 8 || z < 8 || x >= w - 8 || z >= d - 8)
				continue;
			int key = z * w + x;
			if (std::find(seen.begin(), seen.end(), key) != seen.end())
				continue;
			seen.push_back(key);
			int y0 = std::max(0, (int)std::ceil(ey - 0.5f));   // (cells whose middle's above the edge)
			int y1 = std::min(h - 1, (int)std::floor(ey + mouth));
			int firm_left = firm_most;
			float to_end = width * (0.5f - std::fabs(t - 0.5f));
			float sx = t >= 0.5f ? ox : -ox, sz = t >= 0.5f ? oz : -oz;
			for (int y = y0; y <= y1; y++) {
				uint8_t &c = cells[idx(x, y, z)];
				int m = c & MAT_MASK;
				if (m == 0 || m >= NMAT)
					continue;
				bool loose = (c & LOOSE) != 0;
				int hd = loose ? 1 : hard[m];
				if (hd > hardest) {
					rock = true;
					continue;
				}
				if (!loose) {
					if (firm_left <= 0)
						continue;
					firm_left--;
					cut++;
				}
				uint8_t v = c;
				c = 0;
				touch(x, y, z);
				if (taken < take_most) {
					counts.set(m, counts[m] + 1);
					taken++;
				} else {
					spill(px, pz, fx, fz, sx, sz, to_end, v, (int)std::floor(ey + heap));
					moved++;
				}
			}
		}
	}
	moved_total_blade += moved + taken;
	Dictionary out;
	out["counts"] = counts;
	out["taken"] = taken;
	out["moved"] = moved;
	out["cut"] = cut;
	out["rock"] = rock;
	return out;
}

// What's banked against an edge from a to b going fwd: cells above it (up to reach cells) in a strip ahead of it
int DigSiteGrid::load_ahead(const Vector3 &a, const Vector3 &b, const Vector3 &fwd, float reach) const {
	float fx = fwd.x, fz = fwd.z;
	float fl = std::sqrt(fx * fx + fz * fz);
	if (fl < 1e-4f)
		return 0;
	fx /= fl;
	fz /= fl;
	float wx = b.x - a.x, wz = b.z - a.z;
	int n = 0;
	std::vector<int> seen;
	for (int row = 0; row < 12; row++) {
		float ahead = 1.0f + row;
		for (int s = 0; s <= 16; s++) {
			float t = s / 16.0f;
			int x = (int)std::floor(a.x + wx * t + fx * ahead), z = (int)std::floor(a.z + wz * t + fz * ahead);
			if (!in(x, 0, z))
				continue;
			int key = z * w + x;
			if (std::find(seen.begin(), seen.end(), key) != seen.end())
				continue;
			seen.push_back(key);
			float ey = a.y + (b.y - a.y) * t;
			for (int y = std::max(0, (int)std::ceil(ey - 0.5f)); y <= std::min(h - 1, (int)(ey + reach)); y++) {
				uint8_t c = cells[idx(x, y, z)];
				if ((c & MAT_MASK) != 0 && (c & LOOSE))
					n++;
			}
		}
	}
	return n;
}

// n loose cells of m poured on column (x, z) (cells) from a bucket: the column under it first, then the columns round
// it ring by ring, none stacked higher than top_y (the pile under a bucket can't stand above it): -> how many landed
int DigSiteGrid::pour_at(int x, int z, int top_y, int m, int n) {
	if (m <= 0 || m >= NMAT || n <= 0)
		return 0;
	uint8_t v = (uint8_t)m;
	int put = 0;
	for (int r = 0; r <= 10 && put < n; r++) {
		bool any = true;
		while (any && put < n) {
			any = false;
			for (int dz = -r; dz <= r && put < n; dz++)
				for (int dx = -r; dx <= r && put < n; dx++) {
					if (std::max(std::abs(dx), std::abs(dz)) != r)
						continue;
					if (lay_on(x + dx, z + dz, v, top_y)) {
						put++;
						any = true;
					}
				}
		}
	}
	return put;
}
