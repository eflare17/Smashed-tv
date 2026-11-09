// DigSiteGrid (dig_site_grid.h). Owned by the voxel session.
#include "dig_site_grid.h"

#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>

using namespace godot;

// the materials' ids (DsMats in GDScript has the same list, with names, colours, hardness and items)
enum {
	AIR = 0, TOPSOIL = 1, DIRT = 2, CLAY = 3, SAND = 4, GRAVEL = 5, STONE = 6, HARDROCK = 7, BEDROCK = 8,
	COAL = 9, IRON = 10, GOLD = 11, GEM = 12, EDGE = 13, WOOD = 14, CONCRETE = 15
};

static const float CELL_M = 0.125f;

DigSiteGrid::DigSiteGrid() {
	for (int i = 0; i < NMAT; i++) {
		col[i][0] = col[i][1] = col[i][2] = 0.5f;
		hard[i] = 1;
		wall_h[i] = 0;
		span_max[i] = 0;
	}
	top_col[0] = 0.34f;
	top_col[1] = 0.47f;
	top_col[2] = 0.23f;
}

int DigSiteGrid::start_top(int x, int z) const {
	if (start_tops.empty())
		return surface - 1;
	x = std::clamp(x, 0, w - 1);
	z = std::clamp(z, 0, d - 1);
	return start_tops[(size_t)z * w + x];
}

void DigSiteGrid::setup(int p_w, int p_h, int p_d, int p_surface) {
	w = std::max(CS, p_w / CS * CS);
	h = std::max(CS, p_h / CS * CS);
	d = std::max(CS, p_d / CS * CS);
	surface = std::clamp(p_surface, 8, h - 8);
	cells.assign((size_t)w * h * d, 0);
	ccx = w / CS;
	ccy = h / CS;
	ccz = d / CS;
	scx = (w + SW - 1) / SW;
	scy = (h + SH - 1) / SH;
	scz = (d + SW - 1) / SW;
	sec_dirty.assign((size_t)scx * scy * scz, 1);
	chunk_touched.assign((size_t)ccx * ccy * ccz, 0);
	awake.assign((size_t)ccx * ccy * ccz, 0);
	chunk_mod.assign((size_t)ccx * ccy * ccz, 0);
	chunk_hash.assign((size_t)ccx * ccy * ccz, 0);
	hash_dirty.assign((size_t)ccx * ccy * ccz, 1);
	moved_bits.assign(((size_t)w * h * d + 63) / 64, 0);
	moved_list.clear();
	wake_list.clear();
	wake_at = 0;
	// the loose layer (dig_site_layer.cpp): blocks of CS x CS columns, as the chunks' footprints
	lcx = ccx;
	lcz = ccz;
	fr.assign((size_t)w * d, 0);
	fm.assign((size_t)w * d, 0);
	lay_awake.assign((size_t)lcx * lcz, 0);
	lay_queue.clear();
	lay_at = 0;
	lay_touched.assign((size_t)lcx * lcz, 0);
	lay_mod.assign((size_t)lcx * lcz, 0);
	lay_hash.assign((size_t)lcx * lcz, 0);
	lay_hash_dirty.assign((size_t)lcx * lcz, 1);
}

void DigSiteGrid::set_materials(const PackedColorArray &colors, const PackedInt32Array &hardness, const Color &grass) {
	for (int i = 0; i < NMAT; i++) {
		if (i < colors.size()) {
			col[i][0] = colors[i].r;
			col[i][1] = colors[i].g;
			col[i][2] = colors[i].b;
		}
		if (i < hardness.size())
			hard[i] = hardness[i];
	}
	top_col[0] = grass.r;
	top_col[1] = grass.g;
	top_col[2] = grass.b;
}

uint32_t DigSiteGrid::next() {
	rng ^= rng << 13;
	rng ^= rng >> 17;
	rng ^= rng << 5;
	return rng;
}

float DigSiteGrid::frand() {
	return (next() & 0xffffff) / float(0x1000000);
}

uint32_t DigSiteGrid::hash3(int x, int y, int z) {
	uint32_t hsh = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u + (uint32_t)z * 2147483647u;
	hsh = (hsh ^ (hsh >> 13)) * 1274126177u;
	return hsh ^ (hsh >> 16);
}

// smooth value noise over a grid of `s` cells, -1 .. 1
float DigSiteGrid::noise2(float x, float z, int s) const {
	float fx = x / s, fz = z / s;
	int ix = (int)std::floor(fx), iz = (int)std::floor(fz);
	float tx = fx - ix, tz = fz - iz;
	tx = tx * tx * (3 - 2 * tx);
	tz = tz * tz * (3 - 2 * tz);
	auto v = [&](int a, int b) { return (hash3(a, s * 7 + seed_, b) & 0xffff) / 32767.5f - 1.0f; };
	float a = v(ix, iz) + (v(ix + 1, iz) - v(ix, iz)) * tx;
	float b = v(ix, iz + 1) + (v(ix + 1, iz + 1) - v(ix, iz + 1)) * tx;
	return a + (b - a) * tz;
}

// an ellipsoid pocket of material m, only into the cells between the given depths below the ground's top (and solid)
void DigSiteGrid::blob(int m, float cx, float cy, float cz, float rx, float ry, float rz, int dlo, int dhi, const std::vector<int> &heights, bool only_in_solid) {
	int x0 = std::max(0, (int)(cx - rx)), x1 = std::min(w - 1, (int)(cx + rx));
	int y0 = std::max(0, (int)(cy - ry)), y1 = std::min(h - 1, (int)(cy + ry));
	int z0 = std::max(0, (int)(cz - rz)), z1 = std::min(d - 1, (int)(cz + rz));
	for (int z = z0; z <= z1; z++)
		for (int x = x0; x <= x1; x++) {
			int top = heights[z * w + x];
			for (int y = y0; y <= y1; y++) {
				float ex = (x + 0.5f - cx) / rx, ey = (y + 0.5f - cy) / ry, ez = (z + 0.5f - cz) / rz;
				float k = ex * ex + ey * ey + ez * ez;
				// (a rough edge: not a perfect egg)
				if (k > 1.0f - 0.25f * ((hash3(x, y, z) & 255) / 255.0f))
					continue;
				int depth = top - y;
				if (depth < dlo || depth > dhi)
					continue;
				uint8_t &c = cells[idx(x, y, z)];
				if (only_in_solid && (c == AIR || c == EDGE || c == BEDROCK))
					continue;
				c = (uint8_t)m;
			}
		}
}

// The ground from its seed: a gently rolling top (flat at the edges, to meet the field), topsoil, dirt, a clay band,
// stone, hard rock and bedrock by depth (wavy boundaries), with pockets of sand and gravel, clay lenses in the dirt,
// and ore: coal shallow in the stone, iron deeper, gold deeper still, gems right down. A ring of EDGE round it (looks
// like the ground, never digs) so a hole never opens onto nothing.
void DigSiteGrid::generate(int seed) {
	seed_ = seed;
	rng = (uint32_t)seed * 2654435761u + 12345u;
	if (rng == 0)
		rng = 1;
	std::fill(cells.begin(), cells.end(), 0);
	col_top.assign((size_t)w * d, -1);
	show_reset();
	col_dirty.assign((size_t)w * d, 1);
	std::fill(chunk_mod.begin(), chunk_mod.end(), 0);
	std::fill(chunk_touched.begin(), chunk_touched.end(), 0);
	std::fill(hash_dirty.begin(), hash_dirty.end(), 1);
	std::fill(awake.begin(), awake.end(), 0);
	std::fill(fr.begin(), fr.end(), 0);
	std::fill(fm.begin(), fm.end(), 0);
	std::fill(lay_awake.begin(), lay_awake.end(), 0);
	lay_queue.clear();
	lay_at = 0;
	lay_moved = 0;
	std::fill(lay_touched.begin(), lay_touched.end(), 0);
	std::fill(lay_mod.begin(), lay_mod.end(), 0);
	std::fill(lay_hash_dirty.begin(), lay_hash_dirty.end(), 1);
	going.clear();
	cave_events.clear();
	const int ring = 8; // 1 m
	std::vector<int> heights((size_t)w * d);
	start_tops.assign((size_t)w * d, (int16_t)(surface - 1));
	for (int z = 0; z < d; z++)
		for (int x = 0; x < w; x++) {
			float e = std::min(std::min(x, w - 1 - x), std::min(z, d - 1 - z)) / 48.0f;   // 0 at the edge .. 1, 6 m in
			e = std::clamp(e, 0.0f, 1.0f);
			float n = noise2(x, z, 96) * 6.0f + noise2(x, z, 32) * 2.0f;
			int top = surface - 1 + (int)std::lround(n * e);
			heights[z * w + x] = top;
			start_tops[(size_t)z * w + x] = (int16_t)top;
			int dirt_d = 22 + (int)(noise2(x, z, 40) * 6.0f);       // ~3 m of dirt
			int clay_d = 52 + (int)(noise2(x + 999, z, 56) * 10.0f);  // the clay band to ~6.5 m
			int stone_d = 112 + (int)(noise2(x, z + 555, 64) * 14.0f); // hard rock from ~14 m
			bool edge = x < ring || z < ring || x >= w - ring || z >= d - ring;
			for (int y = 0; y <= top && y < h; y++) {
				int depth = top - y;
				uint8_t m;
				if (y < 4)
					m = BEDROCK;
				else if (edge)
					m = EDGE;
				else if (depth < 4)
					m = TOPSOIL;
				else if (depth < dirt_d)
					m = DIRT;
				else if (depth < clay_d)
					m = ((hash3(x / 6, y / 3, z / 6) & 7) == 0) ? DIRT : CLAY;
				else if (depth < stone_d)
					m = STONE;
				else
					m = HARDROCK;
				cells[idx(x, y, z)] = m;
			}
		}
	auto pockets = [&](int m, int n, float rmin, float rmax, float flat, int dlo, int dhi) {
		for (int i = 0; i < n; i++) {
			float cx = ring + frand() * (w - 2 * ring), cz = ring + frand() * (d - 2 * ring);
			int top = heights[std::clamp((int)cz, 0, d - 1) * w + std::clamp((int)cx, 0, w - 1)];
			float cy = top - (dlo + frand() * (dhi - dlo));
			float r = rmin + frand() * (rmax - rmin);
			blob(m, cx, cy, cz, r * (0.8f + frand() * 0.5f), r * flat, r * (0.8f + frand() * 0.5f), dlo, dhi, heights, true);
		}
	};
	float area = (w * d) / (512.0f * 512.0f);   // (counts for a 64 x 64 m site; more or fewer for another size)
	pockets(SAND, (int)(46 * area), 8, 20, 0.45f, 8, 60);
	pockets(GRAVEL, (int)(24 * area), 6, 14, 0.5f, 10, 70);
	pockets(CLAY, (int)(40 * area), 8, 18, 0.4f, 6, 24);
	pockets(COAL, (int)(70 * area), 4, 10, 0.6f, 50, 100);
	pockets(IRON, (int)(55 * area), 3, 8, 0.7f, 70, 140);
	pockets(GOLD, (int)(30 * area), 2, 5, 0.8f, 100, 160);
	pockets(GEM, (int)(18 * area), 1.5f, 3.5f, 1.0f, 130, 190);
	std::fill(sec_dirty.begin(), sec_dirty.end(), 1);
	std::fill(chunk_touched.begin(), chunk_touched.end(), 0);
}

// ---------------------------------------------------------------- cells

int DigSiteGrid::get_cell(int x, int y, int z) const {
	return in(x, y, z) ? cells[idx(x, y, z)] : (y >= h ? 0 : 255);
}

int DigSiteGrid::top_cached(int x, int z) const {
	if (x < 0 || z < 0 || x >= w || z >= d)
		return -1;
	size_t k = (size_t)z * w + x;
	if (col_dirty.empty()) {
		col_top.assign((size_t)w * d, -1);
		col_dirty.assign((size_t)w * d, 1);
	}
	if (col_dirty[k]) {
		int t = -1;
		for (int y = h - 1; y >= 0; y--)
			if ((cells[idx(x, y, z)] & MAT_MASK) != AIR) {
				t = y;
				break;
			}
		col_top[k] = (int16_t)t;
		col_dirty[k] = 0;
	}
	return col_top[k];
}

void DigSiteGrid::touch(int x, int y, int z) {
	if (!col_dirty.empty())
		col_dirty[(size_t)z * w + x] = 1;
	// every section within 2 cells (the smooth surface there is shaped by this cell: dig_site_mesh.cpp)
	for (int sy = std::max(0, y - 2) / SH; sy <= std::min(h - 1, y + 2) / SH; sy++)
		for (int sz = std::max(0, z - 2) / SW; sz <= std::min(d - 1, z + 2) / SW; sz++)
			for (int sx = std::max(0, x - 2) / SW; sx <= std::min(w - 1, x + 2) / SW; sx++)
				sec_dirty[(sy * scz + sz) * scx + sx] = 1;
	int ci = ((y / CS) * ccz + z / CS) * ccx + x / CS;
	chunk_touched[ci] = 1;
	chunk_mod[ci] = 1;
	hash_dirty[ci] = 1;
	wake_near(x, y, z);
	// (the column's surface may have moved: drawn again; its loose dirt may slide now)
	lay_changed(x, z);
	lay_wake(x, z);
}

void DigSiteGrid::set_cell(int x, int y, int z, int v) {
	if (!in(x, y, z))
		return;
	uint8_t &c = cells[idx(x, y, z)];
	uint8_t nv = (uint8_t)(v & 0xff);
	if ((nv & MAT_MASK) >= NMAT)
		nv = 0;
	if (c == nv)
		return;
	c = nv;
	touch(x, y, z);
}

int DigSiteGrid::firm_top(int x, int z) const {
	if (x < 0 || z < 0 || x >= w || z >= d)
		return -1;
	for (int y = h - 1; y >= 0; y--) {
		uint8_t c = cells[idx(x, y, z)];
		if ((c & MAT_MASK) != AIR && !(c & LOOSE))
			return y;
	}
	return -1;
}

int DigSiteGrid::column_top(int x, int z) const {
	return top_cached(x, z);
}

int DigSiteGrid::count_mat(int m) const {
	int n = 0;
	for (uint8_t c : cells)
		if ((c & MAT_MASK) == m)
			n++;
	return n;
}

// what: >= 0 that material, -1 anything solid, -2 air, -3 loose
int DigSiteGrid::count_box(int x0, int y0, int z0, int x1, int y1, int z1, int what) const {
	int n = 0;
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++)
		for (int z = std::max(0, z0); z <= std::min(d - 1, z1); z++)
			for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
				uint8_t c = cells[idx(x, y, z)];
				int m = c & MAT_MASK;
				if ((what >= 0 && m == what) || (what == -1 && m != AIR) || (what == -2 && m == AIR) || (what == -3 && (c & LOOSE) && m != AIR))
					n++;
			}
	return n;
}

// ---------------------------------------------------------------- digging and filling

// Every cell within r (cells) of c (cells) no harder than `hardest`, taken out. -> {counts: cells by material, n,
// refused: the hardness of the hardest it couldn't take (0: none)}
Dictionary DigSiteGrid::dig_sphere(const Vector3 &c, float r, int hardest) {
	PackedInt32Array counts;
	counts.resize(NMAT);
	for (int i = 0; i < NMAT; i++)
		counts.set(i, 0);
	int n = 0, refused = 0;
	int x0 = (int)std::floor(c.x - r), x1 = (int)std::floor(c.x + r);
	int y0 = (int)std::floor(c.y - r), y1 = (int)std::floor(c.y + r);
	int z0 = (int)std::floor(c.z - r), z1 = (int)std::floor(c.z + r);
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++)
		for (int z = std::max(0, z0); z <= std::min(d - 1, z1); z++)
			for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
				float ex = x + 0.5f - c.x, ey = y + 0.5f - c.y, ez = z + 0.5f - c.z;
				if (ex * ex + ey * ey + ez * ez > r * r)
					continue;
				uint8_t &cell = cells[idx(x, y, z)];
				int m = cell & MAT_MASK;
				if (m == AIR)
					continue;
				int hd = (cell & LOOSE) ? 1 : hard[m];
				if (hd > hardest) {
					refused = std::max(refused, hd);
					continue;
				}
				counts.set(m, counts[m] + 1);
				cell = AIR;
				touch(x, y, z);
				n++;
			}
	Dictionary out;
	out["counts"] = counts;
	out["n"] = n;
	out["refused"] = refused;
	return out;
}

// A blast at c (cells), r (cells) for the softest ground: a cell of m within r x reach[m] is blown out (reach 0:
// never: bedrock, the edge), one within crack times that turned loose (it slumps). -> {counts: blown out by material,
// n, cracked}
Dictionary DigSiteGrid::blast_sphere(const Vector3 &c, float r, const PackedFloat32Array &reach, float crack) {
	PackedInt32Array counts;
	counts.resize(NMAT);
	for (int i = 0; i < NMAT; i++)
		counts.set(i, 0);
	int n = 0, cracked = 0;
	float far = r * std::max(1.0f, crack);
	int x0 = (int)std::floor(c.x - far), x1 = (int)std::floor(c.x + far);
	int y0 = (int)std::floor(c.y - far), y1 = (int)std::floor(c.y + far);
	int z0 = (int)std::floor(c.z - far), z1 = (int)std::floor(c.z + far);
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++)
		for (int z = std::max(0, z0); z <= std::min(d - 1, z1); z++)
			for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
				uint8_t &cell = cells[idx(x, y, z)];
				int m = cell & MAT_MASK;
				if (m == AIR)
					continue;
				float k = m < reach.size() ? reach[m] : 0.0f;
				if (k <= 0.0f)
					continue;
				float ex = x + 0.5f - c.x, ey = y + 0.5f - c.y, ez = z + 0.5f - c.z;
				float dd = std::sqrt(ex * ex + ey * ey + ez * ez);
				if (dd <= r * k) {
					counts.set(m, counts[m] + 1);
					cell = AIR;
					touch(x, y, z);
					n++;
				} else if (dd <= r * k * crack && !(cell & LOOSE)) {
					cell |= LOOSE;
					touch(x, y, z);
					cracked++;
				}
			}
	Dictionary out;
	out["counts"] = counts;
	out["n"] = n;
	out["cracked"] = cracked;
	return out;
}

// Up to `most` cells of m put into the empty cells within r of c, the lowest first. -> how many
int DigSiteGrid::fill_sphere(const Vector3 &c, float r, int m, int most, bool loose) {
	if (most <= 0 || m <= 0 || m >= NMAT)
		return 0;
	std::vector<std::pair<int, int>> spots;   // (y, index)
	int x0 = (int)std::floor(c.x - r), x1 = (int)std::floor(c.x + r);
	int y0 = (int)std::floor(c.y - r), y1 = (int)std::floor(c.y + r);
	int z0 = (int)std::floor(c.z - r), z1 = (int)std::floor(c.z + r);
	for (int y = std::max(0, y0); y <= std::min(h - 1, y1); y++)
		for (int z = std::max(0, z0); z <= std::min(d - 1, z1); z++)
			for (int x = std::max(0, x0); x <= std::min(w - 1, x1); x++) {
				float ex = x + 0.5f - c.x, ey = y + 0.5f - c.y, ez = z + 0.5f - c.z;
				if (ex * ex + ey * ey + ez * ez > r * r)
					continue;
				if ((cells[idx(x, y, z)] & MAT_MASK) == AIR)
					spots.push_back({y, idx(x, y, z)});
			}
	std::stable_sort(spots.begin(), spots.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
	int n = 0;
	for (auto &s : spots) {
		if (n >= most)
			break;
		cells[s.second] = (uint8_t)(m | (loose ? LOOSE : 0));
		int i = s.second;
		int x = i % w, z = (i / w) % d, y = i / (w * d);
		touch(x, y, z);
		n++;
	}
	return n;
}

// ---------------------------------------------------------------- drawing

PackedInt32Array DigSiteGrid::take_dirty_sections(int most) {
	PackedInt32Array out;
	for (int i = 0; i < (int)sec_dirty.size() && out.size() < most; i++)
		if (sec_dirty[i]) {
			sec_dirty[i] = 0;
			out.push_back(i);
		}
	return out;
}

void DigSiteGrid::mark_all_dirty() {
	std::fill(sec_dirty.begin(), sec_dirty.end(), 1);
}

void DigSiteGrid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "w", "h", "d", "surface"), &DigSiteGrid::setup);
	ClassDB::bind_method(D_METHOD("set_materials", "colors", "hardness", "grass"), &DigSiteGrid::set_materials);
	ClassDB::bind_method(D_METHOD("generate", "seed"), &DigSiteGrid::generate);
	ClassDB::bind_method(D_METHOD("get_seed"), &DigSiteGrid::get_seed);
	ClassDB::bind_method(D_METHOD("get_w"), &DigSiteGrid::get_w);
	ClassDB::bind_method(D_METHOD("get_h"), &DigSiteGrid::get_h);
	ClassDB::bind_method(D_METHOD("get_d"), &DigSiteGrid::get_d);
	ClassDB::bind_method(D_METHOD("get_surface"), &DigSiteGrid::get_surface);
	ClassDB::bind_method(D_METHOD("start_top", "x", "z"), &DigSiteGrid::start_top);
	ClassDB::bind_method(D_METHOD("get_cell", "x", "y", "z"), &DigSiteGrid::get_cell);
	ClassDB::bind_method(D_METHOD("set_cell", "x", "y", "z", "v"), &DigSiteGrid::set_cell);
	ClassDB::bind_method(D_METHOD("column_top", "x", "z"), &DigSiteGrid::column_top);
	ClassDB::bind_method(D_METHOD("firm_top", "x", "z"), &DigSiteGrid::firm_top);
	ClassDB::bind_method(D_METHOD("count_mat", "m"), &DigSiteGrid::count_mat);
	ClassDB::bind_method(D_METHOD("count_box", "x0", "y0", "z0", "x1", "y1", "z1", "what"), &DigSiteGrid::count_box);
	ClassDB::bind_method(D_METHOD("dig_sphere", "c", "r", "hardest"), &DigSiteGrid::dig_sphere);
	ClassDB::bind_method(D_METHOD("fill_sphere", "c", "r", "m", "most", "loose"), &DigSiteGrid::fill_sphere);
	ClassDB::bind_method(D_METHOD("blast_sphere", "c", "r", "reach", "crack"), &DigSiteGrid::blast_sphere);
	ClassDB::bind_method(D_METHOD("blade_sweep", "a", "b", "fwd", "rows", "mouth", "firm_most", "hardest", "take_most", "heap", "share"), &DigSiteGrid::blade_sweep, DEFVAL(1.0f));
	ClassDB::bind_method(D_METHOD("load_ahead", "a", "b", "fwd", "reach"), &DigSiteGrid::load_ahead);
	ClassDB::bind_method(D_METHOD("pour_at", "x", "z", "top_y", "m", "n"), &DigSiteGrid::pour_at);
	ClassDB::bind_method(D_METHOD("block_blade", "owner", "a", "b", "fwd", "thick", "high"), &DigSiteGrid::block_blade);
	ClassDB::bind_method(D_METHOD("unblock", "owner"), &DigSiteGrid::unblock);
	ClassDB::bind_method(D_METHOD("take_diff", "most"), &DigSiteGrid::take_diff);
	ClassDB::bind_method(D_METHOD("pack_chunks", "list"), &DigSiteGrid::pack_chunks);
	ClassDB::bind_method(D_METHOD("modified_chunks"), &DigSiteGrid::modified_chunks);
	ClassDB::bind_method(D_METHOD("apply_chunks", "data"), &DigSiteGrid::apply_chunks);
	ClassDB::bind_method(D_METHOD("section_hashes"), &DigSiteGrid::section_hashes);
	ClassDB::bind_method(D_METHOD("section_chunks", "s"), &DigSiteGrid::section_chunks);
	ClassDB::bind_method(D_METHOD("clear_touched"), &DigSiteGrid::clear_touched);
	ClassDB::bind_method(D_METHOD("chunk_count"), &DigSiteGrid::chunk_count);
	ClassDB::bind_method(D_METHOD("set_physics", "walls"), &DigSiteGrid::set_physics);
	ClassDB::bind_method(D_METHOD("set_spans", "spans"), &DigSiteGrid::set_spans);
	ClassDB::bind_method(D_METHOD("set_cave_ticks", "ticks"), &DigSiteGrid::set_cave_ticks);
	ClassDB::bind_method(D_METHOD("take_cave_events"), &DigSiteGrid::take_cave_events);
	ClassDB::bind_method(D_METHOD("going_count"), &DigSiteGrid::going_count);
	ClassDB::bind_method(D_METHOD("roof_span_at", "x", "y", "z"), &DigSiteGrid::roof_span_at);
	ClassDB::bind_method(D_METHOD("settle", "budget_usec"), &DigSiteGrid::settle);
	ClassDB::bind_method(D_METHOD("awake_count"), &DigSiteGrid::awake_count);
	ClassDB::bind_method(D_METHOD("wake_all"), &DigSiteGrid::wake_all);
	ClassDB::bind_method(D_METHOD("drop_column", "x", "z", "m", "n"), &DigSiteGrid::drop_column);
	ClassDB::bind_method(D_METHOD("get_moves_total"), &DigSiteGrid::get_moves_total);
	ClassDB::bind_method(D_METHOD("take_dirty_sections", "most"), &DigSiteGrid::take_dirty_sections);
	ClassDB::bind_method(D_METHOD("mark_all_dirty"), &DigSiteGrid::mark_all_dirty);
	ClassDB::bind_method(D_METHOD("mesh_section", "sx", "sy", "sz"), &DigSiteGrid::mesh_section);
	ClassDB::bind_method(D_METHOD("decor_section", "sx", "sy", "sz", "blades_per_m2"), &DigSiteGrid::decor_section);
	ClassDB::bind_method(D_METHOD("section_tops", "sx", "sz"), &DigSiteGrid::section_tops);
	ClassDB::bind_method(D_METHOD("commit_tops", "sx", "sy", "sz", "snap"), &DigSiteGrid::commit_tops);
	ClassDB::bind_method(D_METHOD("show_update", "dt", "ease_rate"), &DigSiteGrid::show_update);
	ClassDB::bind_method(D_METHOD("layer_step", "budget_usec"), &DigSiteGrid::layer_step);
	ClassDB::bind_method(D_METHOD("layer_awake"), &DigSiteGrid::layer_awake);
	ClassDB::bind_method(D_METHOD("layer_wake_all"), &DigSiteGrid::layer_wake_all);
	ClassDB::bind_method(D_METHOD("height_at", "x", "z"), &DigSiteGrid::height_at);
	ClassDB::bind_method(D_METHOD("get_layer", "x", "z"), &DigSiteGrid::get_layer);
	ClassDB::bind_method(D_METHOD("set_layer", "x", "z", "mm", "m"), &DigSiteGrid::set_layer);
	ClassDB::bind_method(D_METHOD("put_layer", "x", "z", "mm", "m"), &DigSiteGrid::put_layer);
	ClassDB::bind_method(D_METHOD("ground_mm"), &DigSiteGrid::ground_mm);
	ClassDB::bind_method(D_METHOD("loose_mm"), &DigSiteGrid::loose_mm);
	ClassDB::bind_method(D_METHOD("mat_mm", "m"), &DigSiteGrid::mat_mm);
	ClassDB::bind_method(D_METHOD("get_layer_moved"), &DigSiteGrid::get_layer_moved);
	ClassDB::bind_method(D_METHOD("show_offsets"), &DigSiteGrid::show_offsets);
	ClassDB::bind_method(D_METHOD("show_topo_bytes"), &DigSiteGrid::show_topo_bytes);
	ClassDB::bind_method(D_METHOD("loose_columns"), &DigSiteGrid::loose_columns);
	ClassDB::bind_method(D_METHOD("take_topo_dirty", "any"), &DigSiteGrid::take_topo_dirty, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("section_count"), &DigSiteGrid::section_count);
	ClassDB::bind_method(D_METHOD("section_dims"), &DigSiteGrid::section_dims);
}
