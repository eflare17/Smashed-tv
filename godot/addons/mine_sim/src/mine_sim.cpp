// The mine's pixel world: see mine_sim.h. Owned by the voxel session.
#include "mine_sim.h"

#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

static const uint32_t OUTLINE = 0xFF05060Au;     // (a, b, g, r) the dark edge round solid ground
static const uint32_t WHITE = 0xFFFAFFFFu;
static const float GRASS[3] = {84.0f / 255.0f, 150.0f / 255.0f, 60.0f / 255.0f};

MineSim::MineSim() {}

uint32_t MineSim::pack(const Color &c) {
	uint32_t r = (uint32_t)std::clamp((int)std::lround(c.r * 255.0f), 0, 255);
	uint32_t g = (uint32_t)std::clamp((int)std::lround(c.g * 255.0f), 0, 255);
	uint32_t b = (uint32_t)std::clamp((int)std::lround(c.b * 255.0f), 0, 255);
	uint32_t a = (uint32_t)std::clamp((int)std::lround(c.a * 255.0f), 0, 255);
	return (a << 24) | (b << 16) | (g << 8) | r;
}

uint32_t MineSim::mul(uint32_t c, float f) {
	uint32_t r = (uint32_t)std::min(255.0f, (c & 255) * f);
	uint32_t g = (uint32_t)std::min(255.0f, ((c >> 8) & 255) * f);
	uint32_t b = (uint32_t)std::min(255.0f, ((c >> 16) & 255) * f);
	return (c & 0xFF000000u) | (b << 16) | (g << 8) | r;
}

float MineSim::noise(float x, float y, int seed) const {
	int ix = (int)std::floor(x), iy = (int)std::floor(y);
	float fx = x - ix, fy = y - iy;
	fx = fx * fx * (3 - 2 * fx);
	fy = fy * fy * (3 - 2 * fy);
	auto h = [&](int a, int b) { return (hash2(a + seed * 101, b - seed * 37) & 0xFFFF) / 65535.0f; };
	float a = h(ix, iy), b = h(ix + 1, iy), c = h(ix, iy + 1), d = h(ix + 1, iy + 1);
	return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
}

void MineSim::setup(int w_, int h_, int sky_rows) {
	w = std::max(1, w_);
	h = std::max(1, h_);
	sky = sky_rows;
	cw = (w + CS - 1) / CS;
	chh = (h + CS - 1) / CS;
	mat.assign(w * h, 0);
	var.assign(w * h, 0);
	dmg.assign(w * h, 0);
	back.assign(w * h, 0);
	stamp.assign(w * h, 0);
	awake.assign(cw * chh, 0);
	awake_next.assign(cw * chh, 0);
	parts.clear();
	changed = 0;
}

void MineSim::set_material(int m, int flags, float hardness, int need, const PackedColorArray &shades, const Color &glow) {
	if (m < 0 || m >= NM)
		return;
	Mat &M = mats[m];
	M.flags = flags;
	M.hard = hardness;
	M.need = need;
	for (int i = 0; i < 8; i++) {
		Color c = shades.size() > 0 ? shades[std::min(i, (int)shades.size() - 1)] : Color(1, 0, 1);
		M.col[i] = pack(c);
		M.ao[i] = mul(M.col[i], 0.78f);
		M.rim[i] = mul(M.col[i], 0.55f);
		M.top[i] = mul(M.col[i], 1.14f);
	}
	M.glow = pack(glow);
}

void MineSim::set_back(int b, const PackedColorArray &shades, int pattern) {
	if (b < 0 || b >= NB)
		return;
	for (int i = 0; i < 8; i++)
		backs[b].col[i] = pack(shades.size() > 0 ? shades[std::min(i, (int)shades.size() - 1)] : Color(0, 0, 0));
	backs[b].pattern = pattern;
}

void MineSim::set_special(int basalt, int obsidian, int bedrock) {
	basalt_m = basalt;
	obsidian_m = obsidian;
	bedrock_m = bedrock;
}

uint8_t MineSim::shade_for(int x, int y, int m) const {
	float n = noise(x * 0.11f, y * 0.11f, m);
	int s = (int)(n * 5.0f) + (int)(hash2(x, y) & 3);
	return (uint8_t)std::clamp(s, 0, 7);
}

int MineSim::get_cell(int x, int y) const { return in(x, y) ? mat[idx(x, y)] : (y < 0 ? 0 : bedrock_m); }
int MineSim::get_var(int x, int y) const { return in(x, y) ? var[idx(x, y)] : 0; }
int MineSim::get_dmg(int x, int y) const { return in(x, y) ? dmg[idx(x, y)] : 0; }
int MineSim::get_back(int x, int y) const { return in(x, y) ? back[idx(x, y)] : 0; }
bool MineSim::is_loose(int x, int y) const { return in(x, y) && (var[idx(x, y)] & LOOSE); }

void MineSim::set_back_at(int x, int y, int b) {
	if (in(x, y))
		back[idx(x, y)] = (uint8_t)b;
}

void MineSim::set_loose(int x, int y, bool on) {
	if (!in(x, y))
		return;
	int i = idx(x, y);
	var[i] = on ? (var[i] | LOOSE) : (var[i] & ~LOOSE);
	wake(x, y);
}

void MineSim::put(int x, int y, int m, bool loose) {
	if (!in(x, y))
		return;
	int i = idx(x, y);
	mat[i] = (uint8_t)m;
	var[i] = m ? (uint8_t)(shade_for(x, y, m) | (loose ? LOOSE : 0)) : 0;
	dmg[i] = 0;
	changed++;
	wake(x, y);
}

void MineSim::set_cell(int x, int y, int m) { put(x, y, m, false); }

void MineSim::wake(int x, int y) {
	if (!in(x, y))
		return;
	int cx = x / CS, cy = y / CS;
	auto on = [&](int a, int b) {
		if (a < 0 || b < 0 || a >= cw || b >= chh)
			return;
		awake[b * cw + a] = 1;
		awake_next[b * cw + a] = 1;
	};
	on(cx, cy);
	int lx = x % CS, ly = y % CS;
	if (lx == 0) on(cx - 1, cy);
	if (lx == CS - 1) on(cx + 1, cy);
	if (ly == 0) on(cx, cy - 1);
	if (ly == CS - 1) on(cx, cy + 1);
}

void MineSim::wake_all() {
	std::fill(awake.begin(), awake.end(), 1);
	std::fill(awake_next.begin(), awake_next.end(), 1);
}

int MineSim::awake_chunks() const {
	int n = 0;
	for (uint8_t a : awake)
		n += a;
	return n;
}

int MineSim::take_changed() {
	int c = changed;
	changed = 0;
	return c;
}

// ---------------------------------------------------------------- making the world

void MineSim::fill_zones(int seed, const PackedFloat32Array &bounds, const PackedInt32Array &ms, const PackedInt32Array &bs, float wobble) {
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			int i = idx(x, y);
			if (y < sky) {
				mat[i] = 0;
				var[i] = 0;
				back[i] = 0;
				continue;
			}
			float d = (float)(y - sky) + (noise(x * 0.03f, y * 0.012f, seed) - 0.5f) * 2.0f * wobble + (noise(x * 0.12f, y * 0.12f, seed + 7) - 0.5f) * wobble * 0.5f;
			int z = 0;
			while (z < bounds.size() && d >= bounds[z])
				z++;
			int m = ms.size() > z ? ms[z] : 1;
			mat[i] = (uint8_t)m;
			var[i] = shade_for(x, y, m);
			back[i] = (uint8_t)(bs.size() > z ? bs[z] : 1);
			dmg[i] = 0;
		}
	}
	changed++;
	wake_all();
}

// mode: 0 anything but bedrock (and what can't be dug), 1 only plain ground (what fill_zones laid: the zones'
// materials, 1..6), 2 only empty cells
int MineSim::blob(float cx, float cy, float rx, float ry, int m, float rough, int seed, int mode, int bk) {
	int n = 0;
	int x0 = (int)std::floor(cx - rx - 2), x1 = (int)std::ceil(cx + rx + 2);
	int y0 = (int)std::floor(cy - ry - 2), y1 = (int)std::ceil(cy + ry + 2);
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++) {
		for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
			float px = (x + 0.5f - cx) / std::max(0.5f, rx), py = (y + 0.5f - cy) / std::max(0.5f, ry);
			float d = std::sqrt(px * px + py * py);
			float edge = 1.0f - rough * (noise(x * 0.35f, y * 0.35f, seed) - 0.3f);
			if (d > edge)
				continue;
			int i = idx(x, y);
			uint8_t cur = mat[i];
			if (cur == bedrock_m || (cur && mats[cur].hard < 0.0f && mode != 2))
				continue;
			if (mode == 1 && !(cur >= 1 && cur <= 6))
				continue;
			if (mode == 2 && cur != 0)
				continue;
			mat[i] = (uint8_t)m;
			var[i] = m ? shade_for(x, y, m) : 0;
			dmg[i] = 0;
			if (bk >= 0)
				back[i] = (uint8_t)bk;
			n++;
		}
	}
	changed++;
	wake_all();
	return n;
}

// count veins of m between rows y0 and y1, most of them near ypeak (a triangle), each a little rough blob
int MineSim::scatter(int m, int count, int y0, int y1, int ypeak, float rmin, float rmax, int seed, int mode) {
	uint32_t save = rng;
	rng = (uint32_t)(seed * 2654435761u) | 1u;
	int made = 0;
	for (int k = 0; k < count; k++) {
		float y = 0.0f;
		for (int t = 0; t < 30; t++) {
			y = y0 + rnd() * (y1 - y0);
			float kk = y < ypeak ? (y - y0) / std::max(1.0f, (float)(ypeak - y0)) : (y1 - y) / std::max(1.0f, (float)(y1 - ypeak));
			if (rnd() < std::max(0.12f, kk))
				break;
		}
		float x = 2.0f + rnd() * (w - 4.0f);
		float r = rmin + rnd() * (rmax - rmin);
		if (blob(x, y, r * (0.8f + rnd() * 0.5f), r * (0.6f + rnd() * 0.4f), m, 0.6f, seed + k, mode, -1) > 0)
			made++;
	}
	rng = save;
	return made;
}

// patterns: 0 plain, 1 brick (shade 7 the mortar), 2 locker, 3 crate of bricks, 4 timber, 5 concrete slabs
void MineSim::rect(int x0, int y0, int x1, int y1, int m, int bk, int pattern) {
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++) {
		for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
			int i = idx(x, y);
			mat[i] = (uint8_t)m;
			dmg[i] = 0;
			if (bk >= 0)
				back[i] = (uint8_t)bk;
			if (!m) {
				var[i] = 0;
				continue;
			}
			int lx = x - x0, ly = y - y0, ww = x1 - x0 + 1, hh = y1 - y0 + 1;
			uint8_t s = shade_for(x, y, m);
			switch (pattern) {
				case 1: {
					int row = ly / 4, off = (row & 1) * 4;
					s = (ly % 4 == 3 || (lx + off) % 8 == 7) ? 7 : (uint8_t)(((lx + off) / 8 + row) % 3 + (hash2(x, y) & 1) * 2);
					break;
				}
				case 2: {
					bool rim = lx == 0 || ly == 0 || lx == ww - 1 || ly == hh - 1 || lx == ww / 2;
					bool slot = (ly == 2 || ly == 3) && (lx % 2 == 0);
					s = rim ? 6 : (slot ? 7 : (uint8_t)(2 + (hash2(x, y) & 1)));
					if (ly == hh - 2 && lx > 0 && lx < ww - 1) s = 5;
					break;
				}
				case 3: {
					bool rim = lx == 0 || ly == 0 || lx == ww - 1 || ly == hh - 1;
					s = rim ? 6 : (((lx / 3 + ly / 3) & 1) ? 1 : 2);
					if (!rim && ly % 3 == 0) s = 4;
					break;
				}
				case 4:
					s = (lx == 0 || lx == ww - 1) ? 6 : (uint8_t)((lx * 3 + ly / 4) % 5);
					break;
				case 5:
					s = (lx % 8 == 0 || ly % 8 == 0) ? 6 : (uint8_t)(1 + (hash2(x, y) & 3));
					break;
				default:
					break;
			}
			var[i] = s;
		}
	}
	changed++;
	wake_all();
}

// the lower part (below level: 0 top .. 1 bottom) of an ellipse filled with a liquid where it's empty
void MineSim::fill_liquid(float cx, float cy, float rx, float ry, int m, float level) {
	float cut = cy - ry + level * 2.0f * ry;
	for (int y = std::max(0, (int)(cy - ry)); y <= std::min(h - 1, (int)(cy + ry + 1)); y++) {
		if (y + 0.5f < cut)
			continue;
		for (int x = std::max(0, (int)(cx - rx)); x <= std::min(w - 1, (int)(cx + rx + 1)); x++) {
			float px = (x + 0.5f - cx) / rx, py = (y + 0.5f - cy) / ry;
			if (px * px + py * py > 1.0f)
				continue;
			int i = idx(x, y);
			if (mat[i] == 0) {
				mat[i] = (uint8_t)m;
				var[i] = shade_for(x, y, m);
			}
		}
	}
	changed++;
	wake_all();
}

// ---------------------------------------------------------------- saving

PackedByteArray MineSim::get_raw() const {
	PackedByteArray out;
	int n = w * h;
	out.resize(n * 3);
	uint8_t *p = out.ptrw();
	std::memcpy(p, mat.data(), n);
	std::memcpy(p + n, var.data(), n);
	std::memcpy(p + 2 * n, back.data(), n);
	return out;
}

bool MineSim::set_raw(const PackedByteArray &raw) {
	int n = w * h;
	if (raw.size() != n * 3)
		return false;
	const uint8_t *p = raw.ptr();
	std::memcpy(mat.data(), p, n);
	std::memcpy(var.data(), p + n, n);
	std::memcpy(back.data(), p + 2 * n, n);
	std::fill(dmg.begin(), dmg.end(), 0);
	std::fill(stamp.begin(), stamp.end(), 0);
	parts.clear();
	wake_all();
	return true;
}

// ---------------------------------------------------------------- the simulation

void MineSim::set_block(int x, int y, int bw_, int bh_) {
	bx = x;
	by = y;
	bw = bw_;
	bh = bh_;
}

bool MineSim::empty_for_mover(int x, int y) const {
	return in(x, y) && mat[idx(x, y)] == 0 && !blocked_cell(x, y);
}

void MineSim::mv(int a, int b) {
	std::swap(mat[a], mat[b]);
	std::swap(var[a], var[b]);
	std::swap(dmg[a], dmg[b]);
	stamp[a] = stamp[b] = frame;
	wake(a % w, a / w);
	wake(b % w, b / w);
	changed++;
}

void MineSim::update_cell(int x, int y) {
	int i = idx(x, y);
	uint8_t m = mat[i];
	if (!m || stamp[i] == frame)
		return;
	const Mat &M = mats[m];
	int f = M.flags;
	bool loose = var[i] & LOOSE;
	int d = rnd() < 0.5f ? -1 : 1;
	if (f & F_LIQUID) {
		bool hot = f & F_HOT;
		if (hot) {
			// lava against water: both gone to obsidian (the lava) and steam (the water)
			const int nx[4] = {x - 1, x + 1, x, x}, ny[4] = {y, y, y - 1, y + 1};
			for (int k = 0; k < 4; k++) {
				if (!in(nx[k], ny[k]))
					continue;
				int j = idx(nx[k], ny[k]);
				if (mat[j] && (mats[mat[j]].flags & F_WET)) {
					mat[i] = (uint8_t)obsidian_m;
					var[i] = shade_for(x, y, obsidian_m);
					dmg[i] = 0;
					mat[j] = 0;
					var[j] = 0;
					stamp[i] = stamp[j] = frame;
					wake(x, y);
					changed++;
					return;
				}
			}
		}
		bool moved = false;
		if (!hot || rnd() < 0.35f) {
			if (empty_for_mover(x, y + 1)) {
				mv(i, i + w);
				return;
			}
			if (empty_for_mover(x + d, y + 1)) {
				mv(i, idx(x + d, y + 1));
				return;
			}
			if (empty_for_mover(x - d, y + 1)) {
				mv(i, idx(x - d, y + 1));
				return;
			}
			// sideways only when it's pushed (liquid on top, or behind it) or there's a drop to run into: pools
			// settle instead of sloshing for ever
			bool above = y > 0 && mat[i - w] && (mats[mat[i - w]].flags & F_LIQUID);
			int reach = hot ? 2 : 4;
			for (int s = 0; s < 2 && !moved; s++) {
				int dir = s ? -d : d;
				bool behind = in(x - dir, y) && mat[idx(x - dir, y)] == m;
				int nxp = x;
				bool drop = false;
				for (int k = 1; k <= reach; k++) {
					int tx = x + dir * k;
					if (!empty_for_mover(tx, y))
						break;
					nxp = tx;
					if (empty_for_mover(tx, y + 1)) {
						drop = true;
						break;
					}
				}
				if (nxp != x && (above || behind || drop)) {
					mv(i, idx(nxp, y));
					moved = true;
				}
			}
		}
		if (!moved && hot) {
			// cooling, if it's open to the air (and not where the ship is)
			bool open = empty_for_mover(x - 1, y) || empty_for_mover(x + 1, y) || empty_for_mover(x, y - 1);
			if (open) {
				wake(x, y);
				bool near = x >= bx - 3 && x < bx + bw + 3 && y >= by - 3 && y < by + bh + 3;
				if ((frame & 7) == 0 && !near) {
					if (dmg[i] >= 254) {
						mat[i] = (uint8_t)basalt_m;
						var[i] = shade_for(x, y, basalt_m);
						dmg[i] = 0;
						changed++;
					} else {
						dmg[i]++;
					}
				}
			}
		}
		return;
	}
	if ((f & F_FALLS) || loose) {
		if (y + 1 >= h)
			return;
		int b = i + w;
		if (empty_for_mover(x, y + 1)) {
			mv(i, b);
			return;
		}
		uint8_t bm = mat[b];
		if (bm && (mats[bm].flags & F_LIQUID) && !blocked_cell(x, y + 1) && rnd() < 0.6f) {
			mv(i, b);
			return;
		}
		if (empty_for_mover(x + d, y + 1)) {
			mv(i, idx(x + d, y + 1));
			return;
		}
		if (empty_for_mover(x - d, y + 1)) {
			mv(i, idx(x - d, y + 1));
			return;
		}
		return;
	}
	// thin bits of crumbly ground with nothing under them crumble off
	if ((f & F_CRUMBLE) && empty_for_mover(x, y + 1)) {
		int solid = 0;
		for (int oy = -1; oy <= 1; oy++)
			for (int ox = -1; ox <= 1; ox++)
				if ((ox || oy) && (!in(x + ox, y + oy) || mat[idx(x + ox, y + oy)]))
					solid++;
		if (solid <= 3 && rnd() < 0.15f) {
			var[i] |= LOOSE;
			wake(x, y);
		}
	}
}

int MineSim::step() {
	frame++;
	if (!frame)
		frame = 1;
	int before = changed;
	bool ltr = frame & 1;
	for (int cy = chh - 1; cy >= 0; cy--) {
		bool any = false;
		for (int cx = 0; cx < cw; cx++)
			any = any || awake[cy * cw + cx];
		if (!any)
			continue;
		for (int y = std::min(h - 1, cy * CS + CS - 1); y >= cy * CS; y--) {
			for (int k = 0; k < cw; k++) {
				int cx = ltr ? k : cw - 1 - k;
				if (!awake[cy * cw + cx])
					continue;
				int xs = cx * CS, xe = std::min(w, xs + CS);
				for (int j = 0; j < xe - xs; j++)
					update_cell(ltr ? xs + j : xe - 1 - j, y);
			}
		}
	}
	step_parts();
	awake.swap(awake_next);
	std::fill(awake_next.begin(), awake_next.end(), 0);
	return changed - before;
}

void MineSim::step_parts() {
	for (size_t k = 0; k < parts.size();) {
		Part &p = parts[k];
		p.vy += 0.035f;
		p.vx *= 0.99f;
		int steps = std::max(1, (int)std::ceil(std::max(std::fabs(p.vx), std::fabs(p.vy))));
		bool dead = false;
		for (int s = 0; s < steps; s++) {
			float nx = p.x + p.vx / steps, ny = p.y + p.vy / steps;
			int ix = (int)std::floor(nx), iy = (int)std::floor(ny);
			if (ix < 0 || ix >= w || iy >= h) {
				dead = true;
				break;
			}
			if (iy >= 0 && (mat[idx(ix, iy)] || blocked_cell(ix, iy))) {
				// landed: it stays where it was, as rubble (or the liquid it is)
				int cx = (int)std::floor(p.x), cyy = (int)std::floor(p.y);
				for (int up = 0; up < 3; up++) {
					if (empty_for_mover(cx, cyy - up)) {
						int i = idx(cx, cyy - up);
						mat[i] = p.m;
						var[i] = (uint8_t)((p.v & 7) | ((mats[p.m].flags & F_LIQUID) ? 0 : LOOSE));
						dmg[i] = 0;
						wake(cx, cyy - up);
						changed++;
						break;
					}
				}
				dead = true;
				break;
			}
			p.x = nx;
			p.y = ny;
		}
		if (dead) {
			parts[k] = parts.back();
			parts.pop_back();
		} else {
			k++;
		}
	}
}

// ---------------------------------------------------------------- the drill, blasts, shots

// A rounded box (centre cx, cy; half sizes hx, hy; corner radius rc; cells) worked on for dt seconds: each cell's
// damage goes up by rate / its hardness a second (faster at the near side of the box, along dx, dy, and a little
// uneven so the face breaks up), and at full it's gone. Cells harder than the tier won't take it (refused: the tier
// they need; 100: nothing gets through). loot false: the worm's (what's taken isn't counted). Some of what's broken
// flies off as chips (spray: the chance), landing as rubble. Thin crumbly bits round the hole crumble.
Dictionary MineSim::dig(float cx, float cy, float hx, float hy, float rc, float rate, int tier, float dt, float spr, float dx, float dy, bool loot) {
	PackedInt32Array counts;
	counts.resize(NM);
	counts.fill(0);
	PackedFloat32Array sx, sy;
	sx.resize(NM);
	sy.resize(NM);
	sx.fill(0.0f);
	sy.fill(0.0f);
	int touched = 0, broke = 0, refused = 0;
	float hard = 0.0f;
	rc = std::min(rc, std::min(hx, hy));
	float ext = std::fabs(dx) * hx + std::fabs(dy) * hy;
	int x0 = (int)std::floor(cx - hx), x1 = (int)std::ceil(cx + hx), y0 = (int)std::floor(cy - hy), y1 = (int)std::ceil(cy + hy);
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++) {
		for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
			float px = x + 0.5f - cx, py = y + 0.5f - cy;
			float qx = std::fabs(px) - (hx - rc), qy = std::fabs(py) - (hy - rc);
			float dd = std::sqrt(std::max(qx, 0.0f) * std::max(qx, 0.0f) + std::max(qy, 0.0f) * std::max(qy, 0.0f)) + std::min(std::max(qx, qy), 0.0f) - rc;
			if (dd > 0.0f)
				continue;
			int i = idx(x, y);
			uint8_t m = mat[i];
			if (!m)
				continue;
			const Mat &M = mats[m];
			bool loose = var[i] & LOOSE;
			bool gone = false;
			if (M.flags & F_LIQUID)
				continue;
			if (loose || (M.flags & F_FALLS)) {
				gone = true;
			} else if (!(M.flags & F_DIG) || M.hard < 0.0f) {
				refused = std::max(refused, 100);
				continue;
			} else if (M.need > tier) {
				refused = std::max(refused, M.need);
				continue;
			} else {
				touched++;
				hard += M.hard;
				float frac = ext > 0.0f ? std::clamp((px * dx + py * dy + ext) / (2.0f * ext), 0.0f, 1.0f) : 0.5f;
				float jit = 0.7f + 0.6f * ((hash2(x, y) & 255) / 255.0f);
				float inc = 255.0f * dt * rate / std::max(0.01f, M.hard) * (1.5f - frac) * jit;
				int nd = (int)dmg[i] + std::max(1, (int)inc);
				if (nd >= 255)
					gone = true;
				else
					dmg[i] = (uint8_t)nd;
			}
			if (!gone)
				continue;
			broke++;
			if (loot) {
				counts[m] = counts[m] + 1;
				sx[m] = sx[m] + x;
				sy[m] = sy[m] + y;
			}
			if (!(M.flags & (F_RIM | F_TWINKLE)) && rnd() < spr && parts.size() < 4000) {
				float len = std::max(0.3f, std::sqrt(px * px + py * py));
				parts.push_back({x + 0.5f, y + 0.5f, px / len * 0.5f - dx * (0.4f + rnd() * 0.5f) + (rnd() - 0.5f) * 0.9f,
						-0.5f - rnd() * 0.9f + (dy > 0.5f ? -0.4f : 0.0f), m, (uint8_t)(var[i] & 7)});
			}
			mat[i] = 0;
			var[i] = 0;
			dmg[i] = 0;
			changed++;
			wake(x, y);
		}
	}
	// crumbly bits round the hole: loose
	int r2 = 3;
	for (int y = std::max(0, y0 - r2); y <= std::min(h - 1, y1 + r2); y++) {
		for (int x = std::max(0, x0 - r2); x <= std::min(w - 1, x1 + r2); x++) {
			int i = idx(x, y);
			uint8_t m = mat[i];
			if (!m || !(mats[m].flags & F_CRUMBLE) || (var[i] & LOOSE))
				continue;
			int solid = 0;
			for (int oy = -1; oy <= 1; oy++)
				for (int ox = -1; ox <= 1; ox++)
					if ((ox || oy) && (!in(x + ox, y + oy) || mat[idx(x + ox, y + oy)]))
						solid++;
			if (solid <= 4 && rnd() < 0.3f) {
				var[i] |= LOOSE;
				wake(x, y);
			}
		}
	}
	Dictionary out;
	out["counts"] = counts;
	out["sx"] = sx;
	out["sy"] = sy;
	out["touched"] = touched;
	out["broke"] = broke;
	out["refused"] = refused;
	out["hard"] = touched > 0 ? hard / touched : 0.0f;
	return out;
}

// A blast at cx, cy (cells) of radius r: everything but what can't be dug (bedrock, the pads) and liquids gone,
// some of it flying off as chips; the crumbly ground round it loosened. -> {counts}
Dictionary MineSim::explode(float cx, float cy, float r, float spr) {
	PackedInt32Array counts;
	counts.resize(NM);
	counts.fill(0);
	int x0 = (int)std::floor(cx - r - 3), x1 = (int)std::ceil(cx + r + 3), y0 = (int)std::floor(cy - r - 3), y1 = (int)std::ceil(cy + r + 3);
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++) {
		for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
			int i = idx(x, y);
			uint8_t m = mat[i];
			if (!m)
				continue;
			const Mat &M = mats[m];
			float px = x + 0.5f - cx, py = y + 0.5f - cy;
			float d = std::sqrt(px * px + py * py) + (noise(x * 0.4f, y * 0.4f, 3) - 0.5f) * 2.0f;
			if (M.hard < 0.0f || (M.flags & F_LIQUID))
				continue;
			if (d <= r) {
				counts[m] = counts[m] + 1;
				if (!(M.flags & (F_RIM | F_TWINKLE)) && rnd() < spr && parts.size() < 4000) {
					float len = std::max(0.5f, std::sqrt(px * px + py * py));
					float sp = 1.2f + rnd() * 1.6f;
					parts.push_back({x + 0.5f, y + 0.5f, px / len * sp, py / len * sp - 0.8f, m, (uint8_t)(var[i] & 7)});
				}
				mat[i] = 0;
				var[i] = 0;
				dmg[i] = 0;
				changed++;
				wake(x, y);
			} else if (d <= r + 2.5f && (M.flags & F_CRUMBLE) && rnd() < 0.5f) {
				var[i] |= LOOSE;
				wake(x, y);
			}
		}
	}
	Dictionary out;
	out["counts"] = counts;
	return out;
}

// A shot landing at cx, cy: its material into the empty cells within r (loose: it falls; clay sticks)
int MineSim::deposit(float cx, float cy, float r, int m, bool lo) {
	int n = 0;
	for (int y = std::max(0, (int)(cy - r - 1)); y <= std::min(h - 1, (int)(cy + r + 1)); y++) {
		for (int x = std::max(0, (int)(cx - r - 1)); x <= std::min(w - 1, (int)(cx + r + 1)); x++) {
			float px = x + 0.5f - cx, py = y + 0.5f - cy;
			if (px * px + py * py > r * r || !empty_for_mover(x, y))
				continue;
			put(x, y, m, lo);
			n++;
		}
	}
	return n;
}

void MineSim::spray(float x, float y, int m, int n, float vx, float vy, float spread) {
	for (int k = 0; k < n && parts.size() < 4000; k++)
		parts.push_back({x, y, vx + (rnd() - 0.5f) * spread, vy + (rnd() - 0.5f) * spread, (uint8_t)m, (uint8_t)(hash2(k, (int)x) & 7)});
}

// ---------------------------------------------------------------- asking

// what: -1 what stops the ship (solid, not loose, not sand), -2 loose or sand, -3 liquid, -4 lava, -5 water,
// -6 empty, 0.. that material. Past the sides and the bottom counts as what stops the ship.
int MineSim::count_rect(int x0, int y0, int rw, int rh, int what) const {
	int n = 0;
	for (int y = y0; y < y0 + rh; y++) {
		for (int x = x0; x < x0 + rw; x++) {
			if (!in(x, y)) {
				if (what == -1 && (x < 0 || x >= w || y >= h))
					n++;
				else if (what == -6 && y < 0)
					n++;
				continue;
			}
			int i = idx(x, y);
			uint8_t m = mat[i];
			int f = m ? mats[m].flags : 0;
			bool lo = var[i] & LOOSE;
			switch (what) {
				case -1: n += (m && (f & F_SOLID) && !lo && !(f & F_FALLS)) ? 1 : 0; break;
				case -2: n += (m && (lo || (f & F_FALLS))) ? 1 : 0; break;
				case -3: n += (f & F_LIQUID) ? 1 : 0; break;
				case -4: n += (f & F_HOT) ? 1 : 0; break;
				case -5: n += (f & F_WET) ? 1 : 0; break;
				case -6: n += m == 0 ? 1 : 0; break;
				default: n += m == what ? 1 : 0; break;
			}
		}
	}
	return n;
}

// Loose cells, sand and liquids inside the rect pushed out of it (up first, then to the sides; gone if there's
// nowhere): the ship moving through rubble and water. -> how many
int MineSim::displace(int x0, int y0, int rw, int rh) {
	int n = 0;
	for (int y = y0; y < y0 + rh; y++) {
		for (int x = x0; x < x0 + rw; x++) {
			if (!in(x, y))
				continue;
			int i = idx(x, y);
			uint8_t m = mat[i];
			if (!m)
				continue;
			int f = mats[m].flags;
			if (!((var[i] & LOOSE) || (f & (F_FALLS | F_LIQUID))))
				continue;
			n++;
			int to = -1;
			for (int up = y0 - 1; up >= std::max(0, y0 - 10) && to < 0; up--)
				if (in(x, up) && mat[idx(x, up)] == 0 && !blocked_cell(x, up))
					to = idx(x, up);
			for (int k = 1; k <= 4 && to < 0; k++) {
				if (in(x0 - k, y) && mat[idx(x0 - k, y)] == 0)
					to = idx(x0 - k, y);
				else if (in(x0 + rw - 1 + k, y) && mat[idx(x0 + rw - 1 + k, y)] == 0)
					to = idx(x0 + rw - 1 + k, y);
			}
			if (to >= 0) {
				mat[to] = m;
				var[to] = var[i];
				dmg[to] = 0;
				wake(to % w, to / w);
			}
			mat[i] = 0;
			var[i] = 0;
			dmg[i] = 0;
			changed++;
			wake(x, y);
		}
	}
	return n;
}

// The world in bs x bs blocks: 1 where a block has no more than max_block cells that stop things (open enough to
// fly through), for the chasers' maps.
PackedByteArray MineSim::coarse(int bs, int max_block) const {
	int nx = (w + bs - 1) / bs, ny = (h + bs - 1) / bs;
	PackedByteArray out;
	out.resize(nx * ny);
	uint8_t *o = out.ptrw();
	for (int by_ = 0; by_ < ny; by_++)
		for (int bx_ = 0; bx_ < nx; bx_++)
			o[by_ * nx + bx_] = count_rect(bx_ * bs, by_ * bs, bs, bs, -1) <= max_block ? 1 : 0;
	return out;
}

PackedInt32Array MineSim::find(int m, int x0, int y0, int x1, int y1, int max) const {
	PackedInt32Array out;
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1) && out.size() < max * 2; y++)
		for (int x = std::max(0, x0); x <= std::min(w - 1, x1) && out.size() < max * 2; x++)
			if (mat[idx(x, y)] == m) {
				out.push_back(x);
				out.push_back(y);
			}
	return out;
}

// ---------------------------------------------------------------- drawing

Array MineSim::paint(int x0, int y0, int pw, int ph, int fn) {
	PackedByteArray col, glo;
	col.resize(pw * ph * 4);
	glo.resize(pw * ph * 4);
	uint32_t *C = (uint32_t *)col.ptrw();
	uint32_t *G = (uint32_t *)glo.ptrw();
	auto at = [&](int x, int y) -> int {
		if (y < 0)
			return 0;
		if (x < 0 || x >= w || y >= h)
			return bedrock_m;
		return mat[idx(x, y)];
	};
	for (int y = 0; y < ph; y++) {
		int wy = y0 + y;
		for (int x = 0; x < pw; x++) {
			int wx = x0 + x;
			uint32_t c = 0, g = 0xFF000000u;
			if (wy < 0) {
				c = 0;
			} else if (wx < 0 || wx >= w || wy >= h) {
				c = mats[bedrock_m].col[hash2(wx, wy) & 7];
			} else {
				int i = idx(wx, wy);
				uint8_t m = mat[i];
				int v = var[i] & 7;
				if (!m) {
					const Back &B = backs[back[i] < NB ? back[i] : 0];
					if (back[i] == 0) {
						c = 0;
					} else {
						int s = hash2(wx, wy) & 7;
						switch (B.pattern) {
							case 1: {
								int row = wy / 4, off = (row & 1) * 4;
								s = (wy % 4 == 3 || (wx + off) % 8 == 7) ? 7 : (((wx + off) / 8 + row) % 3);
								break;
							}
							case 2:
								s = (wy % 5 == 4) ? 7 : (int)((wx / 6 + wy * 3) % 4);
								break;
							case 3:
								s = (wx % 8 == 0 || wy % 8 == 0) ? 7 : (((wx / 8 + wy / 8) & 1) * 2 + (int)(hash2(wx, wy) & 1));
								break;
							default:
								s = (int)(noise(wx * 0.15f, wy * 0.15f, 9) * 4.0f) + (int)(hash2(wx, wy) & 3);
								s = std::min(s, 6);
								break;
						}
						c = B.col[s];
					}
				} else {
					const Mat &M = mats[m];
					int f = M.flags;
					bool lo = var[i] & LOOSE;
					int up = at(wx, wy - 1), dn = at(wx, wy + 1), lf = at(wx - 1, wy), rt = at(wx + 1, wy);
					if (f & F_ANIM) {
						int s = (v + ((f & F_HOT) ? (fn >> 4) : (fn >> 3)) + ((wx * 3 + wy) >> 2)) & 7;
						c = (up == 0 && wy > 0) ? M.top[s] : M.col[s];
						if (f & F_HOT)
							g = mul(c, 0.9f);
					} else if (lo || (f & F_FALLS)) {
						c = ((f & F_TOPLIT) && up == 0 && dn != 0) ? M.top[v] : (lo ? mul(M.col[v], 0.88f) : M.col[v]);
					} else {
						bool edge = up == 0 || dn == 0 || lf == 0 || rt == 0;
						if (edge) {
							if ((f & F_GRASS) && up == 0 && wy <= sky + 2) {
								float k = 0.85f + v * 0.04f;
								c = 0xFF000000u | ((uint32_t)(GRASS[2] * k * 255) << 16) | ((uint32_t)(GRASS[1] * k * 255) << 8) | (uint32_t)(GRASS[0] * k * 255);
							} else if (f & F_SOFTEDGE) {
								c = M.ao[v];
							} else {
								c = OUTLINE;
							}
						} else {
							bool ao = at(wx, wy - 2) == 0 || at(wx, wy + 2) == 0 || at(wx - 2, wy) == 0 || at(wx + 2, wy) == 0 ||
									at(wx - 1, wy - 1) == 0 || at(wx + 1, wy - 1) == 0 || at(wx - 1, wy + 1) == 0 || at(wx + 1, wy + 1) == 0;
							if ((f & F_TWINKLE) && ((i * 7 + (fn >> 3) * 13) % 97) == 0) {
								c = WHITE;
								g = 0xFFD0D0D0u;
							} else if ((f & F_RIM) && (up != m || dn != m || lf != m || rt != m)) {
								c = M.rim[v];
							} else {
								c = ao ? M.ao[v] : M.col[v];
							}
						}
						// cracks spreading as the drill works it
						int dm = dmg[i];
						if (dm > 0) {
							uint32_t hh = hash2(wx * 3 + 1, wy * 7 + 2) & 255;
							if (hh < (uint32_t)(dm * 0.7f))
								c = mul(c, 0.42f);
							else
								c = mul(c, 1.0f - dm / 255.0f * 0.2f);
						}
					}
					if ((f & F_GLOW) && !(f & F_HOT) && (v >= 6 || (f & F_FALLS) || lo))
						g = M.glow;
				}
			}
			C[y * pw + x] = c;
			G[y * pw + x] = g;
		}
	}
	for (const Part &p : parts) {
		int px = (int)std::floor(p.x) - x0, py = (int)std::floor(p.y) - y0;
		if (px < 0 || py < 0 || px >= pw || py >= ph)
			continue;
		const Mat &M = mats[p.m];
		C[py * pw + px] = M.col[p.v & 7];
		if (M.flags & F_GLOW)
			G[py * pw + px] = M.glow;
	}
	Array out;
	out.append(col);
	out.append(glo);
	return out;
}

// ---------------------------------------------------------------- the bindings

void MineSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "w", "h", "sky_rows"), &MineSim::setup);
	ClassDB::bind_method(D_METHOD("get_w"), &MineSim::get_w);
	ClassDB::bind_method(D_METHOD("get_h"), &MineSim::get_h);
	ClassDB::bind_method(D_METHOD("get_sky"), &MineSim::get_sky);
	ClassDB::bind_method(D_METHOD("set_material", "m", "flags", "hardness", "need", "shades", "glow"), &MineSim::set_material);
	ClassDB::bind_method(D_METHOD("set_back", "b", "shades", "pattern"), &MineSim::set_back);
	ClassDB::bind_method(D_METHOD("set_special", "basalt", "obsidian", "bedrock"), &MineSim::set_special);
	ClassDB::bind_method(D_METHOD("get_cell", "x", "y"), &MineSim::get_cell);
	ClassDB::bind_method(D_METHOD("set_cell", "x", "y", "m"), &MineSim::set_cell);
	ClassDB::bind_method(D_METHOD("get_var", "x", "y"), &MineSim::get_var);
	ClassDB::bind_method(D_METHOD("get_dmg", "x", "y"), &MineSim::get_dmg);
	ClassDB::bind_method(D_METHOD("get_back", "x", "y"), &MineSim::get_back);
	ClassDB::bind_method(D_METHOD("set_back_at", "x", "y", "b"), &MineSim::set_back_at);
	ClassDB::bind_method(D_METHOD("is_loose", "x", "y"), &MineSim::is_loose);
	ClassDB::bind_method(D_METHOD("set_loose", "x", "y", "on"), &MineSim::set_loose);
	ClassDB::bind_method(D_METHOD("fill_zones", "seed", "bounds", "mats", "backs", "wobble"), &MineSim::fill_zones);
	ClassDB::bind_method(D_METHOD("blob", "cx", "cy", "rx", "ry", "m", "rough", "seed", "mode", "back"), &MineSim::blob);
	ClassDB::bind_method(D_METHOD("scatter", "m", "count", "y0", "y1", "ypeak", "rmin", "rmax", "seed", "mode"), &MineSim::scatter);
	ClassDB::bind_method(D_METHOD("rect", "x0", "y0", "x1", "y1", "m", "back", "pattern"), &MineSim::rect);
	ClassDB::bind_method(D_METHOD("fill_liquid", "cx", "cy", "rx", "ry", "m", "level"), &MineSim::fill_liquid);
	ClassDB::bind_method(D_METHOD("get_raw"), &MineSim::get_raw);
	ClassDB::bind_method(D_METHOD("set_raw", "raw"), &MineSim::set_raw);
	ClassDB::bind_method(D_METHOD("take_changed"), &MineSim::take_changed);
	ClassDB::bind_method(D_METHOD("set_block", "x", "y", "w", "h"), &MineSim::set_block);
	ClassDB::bind_method(D_METHOD("step"), &MineSim::step);
	ClassDB::bind_method(D_METHOD("wake_all"), &MineSim::wake_all);
	ClassDB::bind_method(D_METHOD("awake_chunks"), &MineSim::awake_chunks);
	ClassDB::bind_method(D_METHOD("dig", "cx", "cy", "hx", "hy", "rc", "rate", "tier", "dt", "spray", "dx", "dy", "loot"), &MineSim::dig);
	ClassDB::bind_method(D_METHOD("explode", "cx", "cy", "r", "spray"), &MineSim::explode);
	ClassDB::bind_method(D_METHOD("deposit", "cx", "cy", "r", "m", "loose"), &MineSim::deposit);
	ClassDB::bind_method(D_METHOD("spray", "x", "y", "m", "n", "vx", "vy", "spread"), &MineSim::spray);
	ClassDB::bind_method(D_METHOD("count_rect", "x0", "y0", "w", "h", "what"), &MineSim::count_rect);
	ClassDB::bind_method(D_METHOD("displace", "x0", "y0", "w", "h"), &MineSim::displace);
	ClassDB::bind_method(D_METHOD("coarse", "bs", "max_block"), &MineSim::coarse);
	ClassDB::bind_method(D_METHOD("find", "m", "x0", "y0", "x1", "y1", "max"), &MineSim::find);
	ClassDB::bind_method(D_METHOD("particles"), &MineSim::particles);
	ClassDB::bind_method(D_METHOD("paint", "x0", "y0", "w", "h", "frame"), &MineSim::paint);
}
