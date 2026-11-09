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
#include <climits>
#include <cmath>

using namespace godot;

// how far ahead (cells) what's cut is laid, nearest first, and how far past the edge's end it rolls off
static const float SPILL_AHEAD[] = {2.5f, 4.0f, 6.0f, 8.5f, 12.0f, 16.0f, 20.0f};
static const float SPILL_SIDE[] = {1.5f, 3.0f, 5.0f};
static const int SIDE_LOWER = 6 * DigSiteGrid::MM;   // the ridge off the end stands this much lower than the heap in front
static const int OVER_HEAP = 4 * DigSiteGrid::MM;    // with no room anywhere, the lowest place seen takes it this far over the heap at most

// v rounded up or down at random, in proportion (a blade that loosens a tenth of a firm cell a call loosens one a call
// in ten)
int DigSiteGrid::dither(float v) {
	if (v <= 0.0f)
		return 0;
	int n = (int)v;
	blade_rng = blade_rng * 1664525u + 1013904223u;
	if ((float)(blade_rng >> 8) / 16777216.0f < v - n)
		n++;
	return n;
}

// amt mm of m cut at (px, pz) (cells: the blade's front edge there) laid ahead of it, the digger game's DirtSim._spill:
// just ahead up to top_mm, then further ahead, then rolled off past the end of the edge (a windrow, lower), then on the
// lowest place seen if that's not far over the heap's top. -> mm left over (no room: the blade's full)
int DigSiteGrid::spill_mm(float px, float pz, float fx, float fz, float ox, float oz, float to_end, int amt, int m, int top_mm) {
	int left = amt;
	int lx = -1, lz = -1, low = INT_MAX;
	int na = sizeof(SPILL_AHEAD) / sizeof(float), ns = sizeof(SPILL_SIDE) / sizeof(float);
	for (int k = 0; k < na + ns && left > 0; k++) {
		float sx, sz;
		int top = top_mm;
		if (k < na) {
			sx = px + fx * SPILL_AHEAD[k];
			sz = pz + fz * SPILL_AHEAD[k];
		} else {
			float o = to_end + SPILL_SIDE[k - na];
			sx = px + fx * 2.0f + ox * o;
			sz = pz + fz * 2.0f + oz * o;
			top = top_mm - SIDE_LOWER;
		}
		int x = std::clamp((int)std::floor(sx), (int)LRIM, w - 1 - LRIM);
		int z = std::clamp((int)std::floor(sz), (int)LRIM, d - 1 - LRIM);
		int hh = height_mm(x, z);
		if (hh < low) {
			low = hh;
			lx = x;
			lz = z;
		}
		int room = top - hh;
		if (room <= 0)
			continue;
		int g = std::min(room, left);
		lay_put(x, z, g, m);
		left -= g;
	}
	if (left > 0 && lx >= 0) {
		int room = top_mm + OVER_HEAP - height_mm(lx, lz);
		if (room > 0) {
			int g = std::min(room, left);
			lay_put(lx, lz, g, m);
			left -= g;
		}
	}
	return left;
}

// (a column standing taller than the blade reaches, firm on top) one cell within its reach cut out from under what's
// over it, the highest first (cells whose middle's over the edge, up to the mouth): -> mm (a cell's 125), 0: none left
// in reach, none it may loosen now, or rock (set)
static int cut_within_impl(DigSiteGrid *g, std::vector<uint8_t> &cells, int w, int h, int d, const int *hard, int x, int z,
		int edge_mm, int reach_mm, int &firm_mm, int hardest, int &m, int &cut, bool &rock, int &y_out) {
	int y0 = std::max(0, (int)std::ceil(edge_mm / (float)DigSiteGrid::MM - 0.5f));
	int y1 = std::min(h - 1, reach_mm / DigSiteGrid::MM);
	for (int y = y1; y >= y0; y--) {
		uint8_t &c = cells[((size_t)y * d + z) * w + x];
		int cm = c & DigSiteGrid::MAT_MASK;
		if (cm == 0 || cm >= DigSiteGrid::NMAT)
			continue;
		if (!(c & DigSiteGrid::LOOSE)) {
			if (hard[cm] > hardest) {
				rock = true;
				return 0;
			}
			if (firm_mm <= 0)
				return 0;
			firm_mm = std::max(0, firm_mm - DigSiteGrid::MM);
			cut += DigSiteGrid::MM;
		}
		c = 0;
		m = cm;
		y_out = y;
		return DigSiteGrid::MM;
	}
	return 0;
}

// The edge from a to b (cells), going fwd (flat, unit), rows deep (1.75 cells apart: the back rows catch what slides
// under it). The digger game's DirtSim.blade, in mm: it moves what it sweeps through, share of the way across a column
// this call (its travel over the 2 cells it takes to clear what stands in front of it): no travel, nothing moved, so a
// stalled blade can't pump soil up a heap. Each column it covers loses share of what stands above the edge, off the top
// (the back rows five times as much, so nothing leaks past): loose dirt freely, firm ground loosened a cell at a time,
// at most firm_most cells a column at full share (the second row clears what's left of it to the edge, so no step's left
// for the tracks; rows past that only sweep loose dirt), none harder than hardest (rock: felt, and nothing under it's
// reached). A column taller than the mouth (cells over the edge it reaches) loses its loose top, but firm ground over
// the mouth is out of reach: what's within reach is cut from under it. Up to take_most mm go in the bucket (counts);
// the rest are spilled ahead, heaped up to heap cells over the edge; with no room there, it stays (jammed). ->
// {counts: mm taken by material, taken, moved (spilled), cut (firm loosened), jammed, rock: hard ground in its way}
Dictionary DigSiteGrid::blade_sweep(const Vector3 &a, const Vector3 &b, const Vector3 &fwd, int rows, float mouth,
		int firm_most, int hardest, int take_most, float heap, float share) {
	PackedInt32Array counts;
	counts.resize(NMAT);
	for (int i = 0; i < NMAT; i++)
		counts.set(i, 0);
	int taken = 0, moved = 0, cut = 0, jammed = 0;
	bool rock = false;
	share = std::clamp(share, 0.0f, 1.0f);
	take_most = std::max(0, take_most);
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
	int mouth_mm = (int)std::lround(mouth * MM), heap_mm = (int)std::lround(heap * MM);
	std::vector<int> seen;                       // (a column's cut once a call, however many samples land in it)
	for (int row = 0; row < rows; row++) {
		float back = -1.75f * row;
		float row_share = row == 0 ? share : std::min(share * 5.0f, 1.0f);
		if (row_share <= 0.0f)
			continue;
		for (int s = 0; s <= steps; s++) {
			float t = (float)s / steps;
			float px = a.x + wx * t + fx * back, pz = a.z + wz * t + fz * back;
			float ey = a.y + (b.y - a.y) * t;
			int x = (int)std::floor(px), z = (int)std::floor(pz);
			if (x < LRIM || z < LRIM || x >= w - LRIM || z >= d - LRIM)
				continue;
			int key = z * w + x;
			if (std::find(seen.begin(), seen.end(), key) != seen.end())
				continue;
			seen.push_back(key);
			int edge_mm = (int)std::lround(ey * MM);
			int hh = height_mm(x, z);
			int high = hh - edge_mm;
			if (high <= 0)
				continue;
			// (firm ground it may cut here this call, mm: firm_most blocks' worth at full sweep. 999 and over, everything
			// above the edge, every row; an edge working by its travel, share under 1 (a dozer's blade, a loader's
			// bucket), clears the rest of it in its second row; an excavator's teeth, often going straight down, keep
			// their limit in both)
			int firm_mm = firm_most >= 999 ? (1 << 28) : row >= 2 ? 0 : (row == 1 && share < 1.0f) ? (1 << 28) : (int)std::lround(firm_most * MM * row_share);
			int want = row_share >= 1.0f ? high : std::max(1, (int)std::ceil(high * row_share));
			float to_end = width * (0.5f - std::fabs(t - 0.5f));
			float sx = t >= 0.5f ? ox : -ox, sz = t >= 0.5f ? oz : -oz;
			float ex = a.x + wx * t, ez = a.z + wz * t;      // (banked ahead of the blade's front edge, not of the row)
			int reach_mm = edge_mm + mouth_mm;
			while (want > 0) {
				int m = 0, got = 0;
				int cut_was = cut;
				int tt = top_cached(x, z);
				size_t ck = colk(x, z);
				bool firm_top = fr[ck] == 0 ? (tt >= 0 && !(cells[idx(x, tt, z)] & LOOSE)) : (fm[ck] & FIRM_LAYER) != 0;
				if (firm_top && (tt + 1) * MM > reach_mm) {
					int yc = -1;
					got = cut_within_impl(this, cells, w, h, d, hard, x, z, edge_mm, reach_mm, firm_mm, hardest, m, cut, rock, yc);
					if (got > 0)
						touch(x, yc, z);
				} else {
					got = lay_take(x, z, want, edge_mm, firm_mm, hardest, m, cut, rock);
				}
				if (got <= 0)
					break;
				want -= got;
				int into = std::min(got, take_most - taken);
				if (into > 0) {
					counts.set(m, counts[m] + into);
					taken += into;
				}
				int rest = got - into;
				if (rest > 0) {
					int left = spill_mm(ex, ez, fx, fz, sx, sz, to_end, rest, m, edge_mm + heap_mm);
					moved += rest - left;
					if (left > 0) {
						// (no room ahead: the blade's full. It goes back where it was, as it was (firm ground stays
						// firm), and this column's done)
						bool firm = cut > cut_was;
						lay_restore(x, z, left, m, firm);
						if (firm)
							cut -= std::min(left, cut - cut_was);
						jammed += left;
						break;
					}
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
	out["jammed"] = jammed;
	return out;
}

// What's banked against an edge from a to b going fwd (mm): the loose dirt lying over it (up to reach cells over it)
// in a strip ahead of it
int DigSiteGrid::load_ahead(const Vector3 &a, const Vector3 &b, const Vector3 &fwd, float reach) const {
	float fx = fwd.x, fz = fwd.z;
	float fl = std::sqrt(fx * fx + fz * fz);
	if (fl < 1e-4f)
		return 0;
	fx /= fl;
	fz /= fl;
	float wx = b.x - a.x, wz = b.z - a.z;
	int64_t n = 0;
	int reach_mm = (int)std::lround(reach * MM);
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
			int edge_mm = (int)std::lround((a.y + (b.y - a.y) * t) * MM);
			int hh = height_mm(x, z);
			if (hh <= edge_mm)
				continue;
			// (the loose dirt on its top lies from hh - its depth up to hh; what of that's between the edge and the reach)
			int lo = hh - loose_depth_mm(x, z, hh - edge_mm);
			int over = std::min(hh, edge_mm + reach_mm) - std::max(lo, edge_mm);
			if (over > 0)
				n += over;
		}
	}
	return (int)std::min<int64_t>(n, INT_MAX);
}

// n mm of m poured on column (x, z) (cells) from a bucket at top_y (cells): spread evenly over the columns under the
// bucket's mouth (2 round: it's half a metre across; filling the one column under it first stood it up in a 2 m spike
// for half a second), then, where those stand as high as the bucket (top_y's cell's top), over a wider disc, and so
// on: the slump makes a cone of it. -> mm that landed
int DigSiteGrid::pour_at(int x, int z, int top_y, int m, int n) {
	if (m <= 0 || m >= NMAT || n <= 0)
		return 0;
	int top_mm = (top_y + 1) * MM;
	int put = 0;
	std::vector<int> cols;
	for (int r = 2; r <= 12 && put < n; r++) {
		cols.clear();
		for (int dz = -r; dz <= r; dz++)
			for (int dx = -r; dx <= r; dx++) {
				if (dx * dx + dz * dz > r * r + r)
					continue;
				int cx = std::clamp(x + dx, (int)LRIM, w - 1 - LRIM), cz = std::clamp(z + dz, (int)LRIM, d - 1 - LRIM);
				int key = cz * w + cx;
				if (std::find(cols.begin(), cols.end(), key) == cols.end())
					cols.push_back(key);
			}
		bool any = true;
		while (any && put < n) {
			any = false;
			int open = 0;
			for (int key : cols)
				if (height_mm(key % w, key / w) < top_mm)
					open++;
			if (open == 0)
				break;
			int each = std::max(1, (n - put + open - 1) / open);
			for (int key : cols) {
				if (put >= n)
					break;
				int cx = key % w, cz = key / w;
				int room = top_mm - height_mm(cx, cz);
				if (room <= 0)
					continue;
				int g = std::min(std::min(room, each), n - put);
				lay_put(cx, cz, g, m);
				put += g;
				any = true;
			}
		}
	}
	return put;
}

// The cells a blade (or a bucket) fills, solid to the loose dirt: from its edge a to b (cells) back thick cells
// (against fwd) and up high cells over the edge. owner's last ones cleared first.
void DigSiteGrid::block_blade(int owner, const Vector3 &a, const Vector3 &b, const Vector3 &fwd, float thick, float high) {
	unblock(owner);
	if (blocked_bits.empty())
		blocked_bits.assign(((size_t)w * h * d + 63) / 64, 0ull);
	std::vector<int> &mine = blocked_by[owner];
	float fx = fwd.x, fz = fwd.z;
	float fl = std::sqrt(fx * fx + fz * fz);
	if (fl < 1e-4f)
		return;
	fx /= fl;
	fz /= fl;
	float wx = b.x - a.x, wz = b.z - a.z;
	float width = std::sqrt(wx * wx + wz * wz);
	int steps = std::max(1, (int)std::ceil(width / 0.5f));
	int deep = std::max(1, (int)std::ceil(thick / 0.5f));
	for (int s = 0; s <= steps; s++) {
		float t = (float)s / steps;
		float ey = a.y + (b.y - a.y) * t;
		int y0 = std::max(0, (int)std::floor(ey));
		int y1 = std::min(h - 1, (int)std::floor(ey + high));
		for (int k = 0; k <= deep; k++) {
			float back = -thick * k / deep;
			int x = (int)std::floor(a.x + wx * t + fx * back), z = (int)std::floor(a.z + wz * t + fz * back);
			if (x < 0 || z < 0 || x >= w || z >= d)
				continue;
			for (int y = y0; y <= y1; y++) {
				int i = idx(x, y, z);
				uint64_t bit = 1ull << (i & 63);
				if (blocked_bits[i >> 6] & bit)
					continue;
				blocked_bits[i >> 6] |= bit;
				mine.push_back(i);
			}
		}
	}
}

void DigSiteGrid::unblock(int owner) {
	auto it = blocked_by.find(owner);
	if (it == blocked_by.end())
		return;
	for (int i : it->second)
		blocked_bits[i >> 6] &= ~(1ull << (i & 63));
	it->second.clear();
}
