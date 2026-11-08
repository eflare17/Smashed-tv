// DigSiteGrid's drawing (the owner, 8 Nov: "I want the ground to be smooth, not so Minecraft looking"): each section's
// ground as a smooth surface, not block faces. Naive surface nets: every cell's "how solid round here" is its 3 x 3 x 3
// neighbourhood's share of solid cells (so flat ground sits exactly on the blocks' tops, a slope or a dug edge comes out
// smooth); a vertex sits in each little cube between eight cell middles the surface (0.5) passes through, at the average
// of where it crosses the cube's edges; each edge it crosses makes a quad of the four cubes round that edge. Normals
// from the solidity's slope, so it lights smoothly; colours blended vertex to vertex from the material there (grass on
// top of topsoil facing up, loose ground paler, a shade off place to place). The cells, the digging, the dirt and the
// network are all unchanged (12.5 cm cells): only how they look. The collision uses the same triangles. Owned by the
// voxel session.
#include "dig_site_grid.h"

#include <algorithm>
#include <cmath>

using namespace godot;

static const float CELL_M = 0.125f;
static const int AIR = 0, TOPSOIL_MAT = 1, DIRT_MAT = 2;   // (dig_site_grid.cpp's ids)

// How far the ground round a point stands over it, in rings (cells) and the scale (m) each ring's drop is read
// against: the digger game's GroundView._shade_chunk. A hollow goes dark, a heap's top stays light, a tunnel's inside
// is as dark as it gets.
static const int RING_R[3] = {6, 16, 36};
static const float RING_SCALE[3] = {0.45f, 1.2f, 2.4f};

// A section's surface as triangles: [verts (metres from the grid's corner), normals, colours, custom (4 floats a
// vertex: loose share, cavity shade, grass, rock)] (no index: the same verts make the collision shape)
Array DigSiteGrid::mesh_section(int sx, int sy, int sz) const {
	int x0 = sx * SW, y0 = sy * SH, z0 = sz * SW;
	int x1 = std::min(w, x0 + SW), y1 = std::min(h, y0 + SH), z1 = std::min(d, z0 + SW);
	// cells [x0-2, x1+1] (and so on), solid or not
	int cx0 = x0 - 2, cy0 = y0 - 2, cz0 = z0 - 2;
	int cnx = (x1 - x0) + 4, cny = (y1 - y0) + 4, cnz = (z1 - z0) + 4;
	std::vector<uint8_t> solid((size_t)cnx * cny * cnz);
	auto ci = [&](int x, int y, int z) { return ((y - cy0) * cnz + (z - cz0)) * cnx + (x - cx0); };
	bool any_solid = false, any_air = false;
	for (int y = cy0; y < cy0 + cny; y++)
		for (int z = cz0; z < cz0 + cnz; z++)
			for (int x = cx0; x < cx0 + cnx; x++) {
				// (past the site's sides the edge column carries on, so the ground runs flat out to the field: treating
				// it as solid made a wall round the site the player couldn't get through)
				uint8_t v = at(std::clamp(x, 0, w - 1), y, std::clamp(z, 0, d - 1));
				bool s = (v & MAT_MASK) != AIR;
				solid[ci(x, y, z)] = s ? 1 : 0;
				any_solid |= s;
				any_air |= !s;
			}
	Array out;
	if (!any_solid || !any_air) {
		out.push_back(PackedVector3Array());
		out.push_back(PackedVector3Array());
		out.push_back(PackedColorArray());
		out.push_back(PackedFloat32Array());
		return out;
	}
	// the ground's height (cells) in and round the section, for the cavity shade (the grid's column tops, cached)
	int tx0 = x0 - RING_R[2] - 1, tz0 = z0 - RING_R[2] - 1;
	int tnx = (x1 - x0) + 2 * RING_R[2] + 3, tnz = (z1 - z0) + 2 * RING_R[2] + 3;
	std::vector<int16_t> tops((size_t)tnx * tnz);
	for (int z = 0; z < tnz; z++)
		for (int x = 0; x < tnx; x++)
			tops[(size_t)z * tnx + x] = (int16_t)top_cached(std::clamp(tx0 + x, 0, w - 1), std::clamp(tz0 + z, 0, d - 1));
	auto top_at = [&](int x, int z) { return (int)tops[(size_t)std::clamp(z - tz0, 0, tnz - 1) * tnx + std::clamp(x - tx0, 0, tnx - 1)]; };
	// samples at the cell middles [x0-1, x1] (and so on): the share of the 27 round each that's solid
	int sx0 = x0 - 1, sy0 = y0 - 1, sz0 = z0 - 1;
	int snx = (x1 - x0) + 2, sny = (y1 - y0) + 2, snz = (z1 - z0) + 2;
	std::vector<float> smp((size_t)snx * sny * snz);
	auto si = [&](int x, int y, int z) { return ((y - sy0) * snz + (z - sz0)) * snx + (x - sx0); };
	// (the 27 summed as three passes of three: along x, then z, then y; the same counts, a third of the reads)
	std::vector<uint8_t> sx_((size_t)cnx * cny * cnz, 0), sz_((size_t)cnx * cny * cnz, 0);
	for (int y = cy0; y < cy0 + cny; y++)
		for (int z = cz0; z < cz0 + cnz; z++)
			for (int x = cx0 + 1; x < cx0 + cnx - 1; x++) {
				int k = ci(x, y, z);
				sx_[k] = solid[k - 1] + solid[k] + solid[k + 1];
			}
	for (int y = cy0; y < cy0 + cny; y++)
		for (int z = cz0 + 1; z < cz0 + cnz - 1; z++)
			for (int x = cx0 + 1; x < cx0 + cnx - 1; x++) {
				int k = ci(x, y, z);
				sz_[k] = sx_[k - cnx] + sx_[k] + sx_[k + cnx];
			}
	int plane = cnx * cnz;
	for (int y = sy0; y < sy0 + sny; y++)
		for (int z = sz0; z < sz0 + snz; z++)
			for (int x = sx0; x < sx0 + snx; x++) {
				int k = ci(x, y, z);
				smp[si(x, y, z)] = (sz_[k - plane] + sz_[k] + sz_[k + plane]) / 27.0f;
			}
	// a vertex in each cube (between samples i..i+1) the surface passes through: cubes [x0-1, x1) (and so on)
	int dnx = snx - 1, dny = sny - 1, dnz = snz - 1;
	std::vector<int> vid((size_t)dnx * dny * dnz, -1);
	auto di = [&](int x, int y, int z) { return ((y - sy0) * dnz + (z - sz0)) * dnx + (x - sx0); };
	std::vector<Vector3> vpos, vnor;
	std::vector<Color> vcol, vcus;
	static const int corner[8][3] = {{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {1, 1, 0}, {0, 0, 1}, {1, 0, 1}, {0, 1, 1}, {1, 1, 1}};
	static const int edge[12][2] = {{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
	for (int y = sy0; y < sy0 + dny; y++)
		for (int z = sz0; z < sz0 + dnz; z++)
			for (int x = sx0; x < sx0 + dnx; x++) {
				float v[8];
				int inside = 0;
				for (int k = 0; k < 8; k++) {
					v[k] = smp[si(x + corner[k][0], y + corner[k][1], z + corner[k][2])];
					inside += v[k] >= 0.5f ? 1 : 0;
				}
				if (inside == 0 || inside == 8)
					continue;
				float px = 0, py = 0, pz = 0;
				int nc = 0;
				for (int e = 0; e < 12; e++) {
					float a = v[edge[e][0]], b = v[edge[e][1]];
					if ((a >= 0.5f) == (b >= 0.5f))
						continue;
					float t = (0.5f - a) / (b - a);
					const int *ca = corner[edge[e][0]], *cb = corner[edge[e][1]];
					px += ca[0] + (cb[0] - ca[0]) * t;
					py += ca[1] + (cb[1] - ca[1]) * t;
					pz += ca[2] + (cb[2] - ca[2]) * t;
					nc++;
				}
				px /= nc;
				py /= nc;
				pz /= nc;
				// the slope of the solidity: the normal points out of it
				float gx = (v[1] - v[0]) + (v[3] - v[2]) + (v[5] - v[4]) + (v[7] - v[6]);
				float gy = (v[2] - v[0]) + (v[3] - v[1]) + (v[6] - v[4]) + (v[7] - v[5]);
				float gz = (v[4] - v[0]) + (v[5] - v[1]) + (v[6] - v[2]) + (v[7] - v[3]);
				Vector3 nn(-gx, -gy, -gz);
				float len = nn.length();
				nn = len > 1e-5f ? nn / len : Vector3(0, 1, 0);
				// its colour: the topmost solid cell of the eight (the one you'd see)
				int best = -1, best_y = -1 << 30, n_solid = 0, n_loose = 0;
				uint8_t cell = 0;
				for (int k = 0; k < 8; k++) {
					int cx = x + corner[k][0], cy = y + corner[k][1], cz = z + corner[k][2];
					uint8_t c = at(std::clamp(cx, 0, w - 1), cy, std::clamp(cz, 0, d - 1));
					if ((c & MAT_MASK) == AIR || (c & MAT_MASK) >= NMAT)
						continue;
					n_solid++;
					if (c & LOOSE)
						n_loose++;
					if (cy > best_y) {
						best_y = cy;
						best = k;
						cell = c;
					}
				}
				int m = best >= 0 ? (cell & MAT_MASK) : DIRT_MAT;
				// (grass only on ground still standing as it was made: a blade's cut or a bucket's scrape shows soil)
				bool grass = m == TOPSOIL_MAT && !(cell & LOOSE) && nn.y > 0.55f;
				if (grass && best >= 0 && !start_tops.empty()) {
					int gx = std::clamp(x + corner[best][0], 0, w - 1), gz = std::clamp(z + corner[best][2], 0, d - 1);
					grass = best_y >= start_tops[(size_t)gz * w + gx];
				}
				const float *base = grass ? top_col : col[m];
				float var = 0.92f + 0.16f * ((hash3(x >> 1, y >> 1, z >> 1) & 255) / 255.0f);
				float r = base[0] * var, g = base[1] * var, b = base[2] * var;
				// the cavity shade: how far the ground round here stands over this point
				float vy = y + 0.5f + py;
				float dark = 0.0f;
				for (int ring = 0; ring < 3; ring++) {
					int rr = RING_R[ring], dd = rr * 7 / 10;
					float total = top_at(x - rr, z) + top_at(x + rr, z) + top_at(x, z - rr) + top_at(x, z + rr) +
							top_at(x - dd, z - dd) + top_at(x + dd, z - dd) + top_at(x - dd, z + dd) + top_at(x + dd, z + dd);
					dark = std::max(dark, (total / 8.0f - vy) * CELL_M / RING_SCALE[ring]);
				}
				float loose_share = n_solid > 0 ? (float)n_loose / n_solid : 0.0f;
				bool rock = best >= 0 && hard[m] >= 3 && !(cell & LOOSE);
				vid[di(x, y, z)] = (int)vpos.size();
				vpos.push_back(Vector3((x + 0.5f + px) * CELL_M, (y + 0.5f + py) * CELL_M, (z + 0.5f + pz) * CELL_M));
				vnor.push_back(nn);
				vcol.push_back(Color(r, g, b));
				vcus.push_back(Color(loose_share, std::clamp(dark, 0.0f, 1.0f), grass ? 1.0f : 0.0f, rock ? 1.0f : 0.0f));
			}
	// a quad for each edge between two samples the surface crosses, the edge's first sample in the section
	std::vector<int> tri;
	auto quad = [&](int a, int b, int c, int dd, const Vector3 &outward) {
		if (a < 0 || b < 0 || c < 0 || dd < 0)
			return;
		Vector3 n = (vpos[b] - vpos[a]).cross(vpos[c] - vpos[a]);
		if (n.dot(outward) > 0) {     // (Godot's front faces: clockwise seen from outside)
			std::swap(b, dd);
		}
		tri.push_back(a);
		tri.push_back(b);
		tri.push_back(c);
		tri.push_back(a);
		tri.push_back(c);
		tri.push_back(dd);
	};
	for (int y = y0; y < y1; y++)
		for (int z = z0; z < z1; z++)
			for (int x = x0; x < x1; x++) {
				bool here = smp[si(x, y, z)] >= 0.5f;
				// along x
				if (here != (smp[si(x + 1, y, z)] >= 0.5f) && y - 1 >= sy0 && z - 1 >= sz0)
					quad(vid[di(x, y - 1, z - 1)], vid[di(x, y, z - 1)], vid[di(x, y, z)], vid[di(x, y - 1, z)], Vector3(here ? 1 : -1, 0, 0));
				// along y
				if (here != (smp[si(x, y + 1, z)] >= 0.5f) && x - 1 >= sx0 && z - 1 >= sz0)
					quad(vid[di(x - 1, y, z - 1)], vid[di(x, y, z - 1)], vid[di(x, y, z)], vid[di(x - 1, y, z)], Vector3(0, here ? 1 : -1, 0));
				// along z
				if (here != (smp[si(x, y, z + 1)] >= 0.5f) && x - 1 >= sx0 && y - 1 >= sy0)
					quad(vid[di(x - 1, y - 1, z)], vid[di(x, y - 1, z)], vid[di(x, y, z)], vid[di(x - 1, y, z)], Vector3(0, 0, here ? 1 : -1));
			}
	PackedVector3Array verts, norms;
	PackedColorArray cols;
	PackedFloat32Array cus;
	verts.resize(tri.size());
	norms.resize(tri.size());
	cols.resize(tri.size());
	cus.resize(tri.size() * 4);
	Vector3 *vp = verts.ptrw();
	Vector3 *np = norms.ptrw();
	Color *cp = cols.ptrw();
	float *up = cus.ptrw();
	for (size_t k = 0; k < tri.size(); k++) {
		vp[k] = vpos[tri[k]];
		np[k] = vnor[tri[k]];
		cp[k] = vcol[tri[k]];
		const Color &u = vcus[tri[k]];
		up[k * 4] = u.r;
		up[k * 4 + 1] = u.g;
		up[k * 4 + 2] = u.b;
		up[k * 4 + 3] = u.a;
	}
	out.push_back(verts);
	out.push_back(norms);
	out.push_back(cols);
	out.push_back(cus);
	return out;
}

// ---------------------------------------------------------------- the decoration (DsLook): grass blades and clods

// A random rotation about a random axis, scaled, laid in a MultiMesh buffer (12 floats: the basis' rows with the
// origin on the end)
static void lay_instance(float *o, uint32_t h, const Vector3 &at, const Vector3 &scale, bool upright, float yaw) {
	Basis b;
	if (upright) {
		b = Basis(Vector3(0, 1, 0), yaw);
	} else {
		Vector3 axis((float)(h & 255) / 127.5f - 1.0f, (float)((h >> 8) & 255) / 127.5f - 1.0f, (float)((h >> 16) & 255) / 127.5f - 1.0f);
		if (axis.length() < 0.01f)
			axis = Vector3(0, 1, 0);
		b = Basis(axis.normalized(), (float)((h >> 24) & 255) / 255.0f * 6.2831853f);
	}
	b.scale(scale);
	for (int r = 0; r < 3; r++) {
		o[r * 4] = b.rows[r][0];
		o[r * 4 + 1] = b.rows[r][1];
		o[r * 4 + 2] = b.rows[r][2];
		o[r * 4 + 3] = at[r];
	}
}

static inline float hf(uint32_t h, int k) { return (float)((h >> (k * 8)) & 255) / 255.0f; }

// What stands on a section's ground: [grass blades' MultiMesh buffer (12 floats each: on firm topsoil still at the
// height it was made, blades_per_m2 of them), clods' buffer (16 floats each, a colour after the transform: lumps
// lying on loose dirt, bigger where it lies deeper, part sunk in)]. Rebuilt with the section's mesh, so digging
// takes the grass with it and a heap brings lumps up out of it.
Array DigSiteGrid::decor_section(int sx, int sy, int sz, float blades_per_m2) const {
	int x0 = sx * SW, y0 = sy * SH, z0 = sz * SW;
	int x1 = std::min(w, x0 + SW), y1 = std::min(h, y0 + SH), z1 = std::min(d, z0 + SW);
	PackedFloat32Array grass, clods;
	float per_cell = blades_per_m2 * CELL_M * CELL_M;
	int ring = 8;
	for (int z = std::max(z0, ring); z < std::min(z1, d - ring); z++)
		for (int x = std::max(x0, ring); x < std::min(x1, w - ring); x++) {
			int top = top_cached(x, z);
			if (top < y0 || top >= y1)
				continue;
			uint8_t c = cells[idx(x, top, z)];
			int m = c & MAT_MASK;
			uint32_t hsh = hash3(x, top, z);
			float base_y = (top + 1) * CELL_M;
			if (!(c & LOOSE) && m == TOPSOIL_MAT && !start_tops.empty() && top >= start_tops[(size_t)z * w + x]) {
				// grass: so many blades a cell, jittered, each its own height and turn
				int n = (int)per_cell;
				if (hf(hsh, 0) < per_cell - n)
					n++;
				for (int k = 0; k < n; k++) {
					uint32_t hk = hash3(x * 3 + k, top + 77 * k, z * 5 + 13 * k);
					Vector3 at((x + hf(hk, 0)) * CELL_M, base_y - 0.03f, (z + hf(hk, 1)) * CELL_M);
					float tall = 0.55f + 0.4f * hf(hk, 2);
					int o = grass.size();
					grass.resize(o + 12);
					lay_instance(grass.ptrw() + o, hk, at, Vector3(0.85f, tall, 0.85f), true, hf(hk, 3) * 6.2831853f);
				}
			} else if (c & LOOSE) {
				// clods: how deep the loose dirt lies here decides how big a lump it holds
				int deep = 0;
				for (int y = top; y >= 0 && (cells[idx(x, y, z)] & LOOSE); y--)
					deep++;
				float deep_m = deep * CELL_M;
				for (int k = 0; k < 2; k++) {
					uint32_t hk = hash3(x * 7 + k, top + 31 * k, z * 11 + 5 * k);
					if (k == 1 && hf(hk, 3) > 0.45f)
						continue;
					float size = 0.07f + 0.27f * std::pow(hf(hk, 0), 1.7f);
					if (deep_m < size * 0.45f)
						continue;
					Vector3 at((x + hf(hk, 1)) * CELL_M, base_y - size * 0.35f, (z + hf(hk, 2)) * CELL_M);
					int o = clods.size();
					clods.resize(o + 16);
					float *p = clods.ptrw() + o;
					lay_instance(p, hk * 2654435761u + 7, at, Vector3(size * (0.85f + 0.5f * hf(hk, 2)), size, size * (0.8f + 0.45f * hf(hk, 3))), false, 0.0f);
					float shade = 0.8f + 0.35f * hf(hk * 747796405u, 1);
					const float *mc = (m > 0 && m < NMAT) ? col[m] : col[DIRT_MAT];
					p[12] = mc[0] * shade;
					p[13] = mc[1] * shade;
					p[14] = mc[2] * shade;
					p[15] = 1.0f;
				}
			}
		}
	Array out;
	out.push_back(grass);
	out.push_back(clods);
	return out;
}
