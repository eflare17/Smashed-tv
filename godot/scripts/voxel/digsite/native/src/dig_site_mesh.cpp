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

// The surface is relaxed (the owner, 8 Nov: "make it look better", after the blocky rims and the rippled tunnel
// walls): constrained surface nets. Each vertex moves to the average of the vertices it shares a face with, RELAX
// times, but never out of its own little cube, so the surface stays within half a block of the blocks (flat ground
// stays exactly on their tops, a one-block wall or roof doesn't vanish) while a hole's rim comes out round and a wall
// comes out smooth, not stepped. The normals come from the relaxed triangles. The section works out PAD cubes past
// its sides, so the vertices on its edge come out the same as its neighbour's (no seams).
static const int RELAX = 4;
static const int PAD = RELAX + 2;

// A section's surface as triangles: [verts (metres from the grid's corner), normals, colours, custom (4 floats a
// vertex: loose share, cavity shade, grass, rock)] (no index: the same verts make the collision shape)
Array DigSiteGrid::mesh_section(int sx, int sy, int sz) const {
	int x0 = sx * SW, y0 = sy * SH, z0 = sz * SW;
	int x1 = std::min(w, x0 + SW), y1 = std::min(h, y0 + SH), z1 = std::min(d, z0 + SW);
	// cells [x0-2-PAD, x1+1+PAD] (and so on), solid or not
	int cx0 = x0 - 2 - PAD, cy0 = y0 - 2 - PAD, cz0 = z0 - 2 - PAD;
	int cnx = (x1 - x0) + 4 + 2 * PAD, cny = (y1 - y0) + 4 + 2 * PAD, cnz = (z1 - z0) + 4 + 2 * PAD;
	std::vector<uint8_t> solid((size_t)cnx * cny * cnz);
	auto ci = [&](int x, int y, int z) { return ((y - cy0) * cnz + (z - cz0)) * cnx + (x - cx0); };
	bool any_solid = false, any_air = false;
	// (past the site's sides the edge column carries on, so the ground runs flat out to the field: treating it as
	// solid made a wall round the site the player couldn't get through; under the grid's floor and over its roof,
	// the bottom and top rows carry on. A row at a time, the middle of it read straight off the grid)
	int mx0 = std::max(cx0, 0), mx1 = std::min(cx0 + cnx, w);
	for (int y = cy0; y < cy0 + cny; y++)
		for (int z = cz0; z < cz0 + cnz; z++) {
			const uint8_t *row = &cells[idx(0, std::clamp(y, 0, h - 1), std::clamp(z, 0, d - 1))];
			uint8_t *o = &solid[ci(cx0, y, z)];
			uint8_t left = (row[0] & MAT_MASK) != AIR, right = (row[w - 1] & MAT_MASK) != AIR;
			for (int x = cx0; x < mx0; x++)
				o[x - cx0] = left;
			for (int x = mx0; x < mx1; x++)
				o[x - cx0] = (row[x] & MAT_MASK) != AIR;
			for (int x = mx1; x < cx0 + cnx; x++)
				o[x - cx0] = right;
			if (y >= y0 - 2 && y <= y1 + 1 && z >= z0 - 2 && z <= z1 + 1)
				for (int x = x0 - 2; x <= x1 + 1; x++) {
					bool sd = o[x - cx0];
					any_solid |= sd;
					any_air |= !sd;
				}
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
	// samples at the cell middles [x0-1-PAD, x1+PAD] (and so on): the share of the 27 round each that's solid
	int sx0 = x0 - 1 - PAD, sy0 = y0 - 1 - PAD, sz0 = z0 - 1 - PAD;
	int snx = (x1 - x0) + 2 + 2 * PAD, sny = (y1 - y0) + 2 + 2 * PAD, snz = (z1 - z0) + 2 + 2 * PAD;
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
	auto in_s = [&](int x, int y, int z) { return smp[si(x, y, z)] >= 0.5f; };
	// each row of samples along x: all out (0), all in (1) or both (2), so the cubes between four rows all the same
	// (deep in the ground, up in the air: most of them) are skipped without looking at them one by one
	std::vector<uint8_t> rowu((size_t)sny * snz);
	for (int y = sy0; y < sy0 + sny; y++)
		for (int z = sz0; z < sz0 + snz; z++) {
			const float *r = &smp[si(sx0, y, z)];
			bool a = false, b = false;
			for (int x = 0; x < snx; x++) {
				if (r[x] >= 0.5f)
					a = true;
				else
					b = true;
			}
			rowu[(size_t)(y - sy0) * snz + (z - sz0)] = a && b ? 2 : (a ? 1 : 0);
		}
	auto ru = [&](int y, int z) { return rowu[(size_t)(y - sy0) * snz + (z - sz0)]; };
	// a vertex in each cube (between samples i..i+1) the surface passes through: cubes [sx0, sx0+snx-1) (and so on)
	int dnx = snx - 1, dny = sny - 1, dnz = snz - 1;
	std::vector<int> vid((size_t)dnx * dny * dnz, -1);
	auto di = [&](int x, int y, int z) { return ((y - sy0) * dnz + (z - sz0)) * dnx + (x - sx0); };
	std::vector<Vector3> vpos;              // in sample units: the cube's corner plus where in it (0..1)
	std::vector<Vector3i> vcube;
	static const int corner[8][3] = {{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {1, 1, 0}, {0, 0, 1}, {1, 0, 1}, {0, 1, 1}, {1, 1, 1}};
	static const int edge[12][2] = {{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
	for (int y = sy0; y < sy0 + dny; y++)
		for (int z = sz0; z < sz0 + dnz; z++) {
			uint8_t r0 = ru(y, z);
			if (r0 != 2 && ru(y + 1, z) == r0 && ru(y, z + 1) == r0 && ru(y + 1, z + 1) == r0)
				continue;
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
				vid[di(x, y, z)] = (int)vpos.size();
				vpos.push_back(Vector3(x + px / nc, y + py / nc, z + pz / nc));
				vcube.push_back(Vector3i(x, y, z));
			}
		}
	// who's next to whom: the cubes either side of a face the surface crosses (one of the face's four samples on the
	// other side from the rest). Two cubes with vertices but no crossing between them are on two sheets (a thin
	// wall's two sides): they're left apart, or the wall would be pulled in
	size_t nv = vpos.size();
	std::vector<int> nbr(nv * 6, -1);
	for (size_t i = 0; i < nv; i++) {
		const Vector3i &c = vcube[i];
		for (int ax = 0; ax < 3; ax++)
			for (int sg = 0; sg < 2; sg++) {
				Vector3i o = c;
				o[ax] += sg ? 1 : -1;
				if (o.x < sx0 || o.y < sy0 || o.z < sz0 || o.x >= sx0 + dnx || o.y >= sy0 + dny || o.z >= sz0 + dnz)
					continue;
				int j = vid[di(o.x, o.y, o.z)];
				if (j < 0)
					continue;
				// the shared face: its plane along ax at c[ax] + (sg ? 1 : 0); its four samples
				int fa = c[ax] + (sg ? 1 : 0);
				int b1 = (ax + 1) % 3, b2 = (ax + 2) % 3;
				int ins = 0;
				for (int u = 0; u < 2; u++)
					for (int vv = 0; vv < 2; vv++) {
						Vector3i q;
						q[ax] = fa;
						q[b1] = c[b1] + u;
						q[b2] = c[b2] + vv;
						ins += in_s(q.x, q.y, q.z) ? 1 : 0;
					}
				if (ins == 0 || ins == 4)
					continue;
				nbr[i * 6 + ax * 2 + sg] = j;
			}
	}
	// relaxed: each to its neighbours' average, kept in its cube
	std::vector<Vector3> next(nv);
	for (int pass = 0; pass < RELAX; pass++) {
		for (size_t i = 0; i < nv; i++) {
			Vector3 sum;
			int n = 0;
			for (int k = 0; k < 6; k++) {
				int j = nbr[i * 6 + k];
				if (j >= 0) {
					sum += vpos[j];
					n++;
				}
			}
			if (n == 0) {
				next[i] = vpos[i];
				continue;
			}
			const Vector3i &c = vcube[i];
			Vector3 a = sum / (float)n;
			next[i] = Vector3(std::clamp(a.x, c.x + 0.02f, c.x + 0.98f), std::clamp(a.y, c.y + 0.02f, c.y + 0.98f), std::clamp(a.z, c.z + 0.02f, c.z + 0.98f));
		}
		vpos.swap(next);
	}
	// the quads: one for each sample edge the surface crosses with all four cubes round it there; every one in the
	// padded block adds to its corners' normals, the section's own are drawn
	std::vector<Vector3> vnor(nv, Vector3());
	std::vector<int> tri;
	auto quad = [&](int a, int b, int c, int dd, const Vector3 &outward, bool draw) {
		if (a < 0 || b < 0 || c < 0 || dd < 0)
			return;
		Vector3 area = (vpos[c] - vpos[a]).cross(vpos[dd] - vpos[b]);
		if (area.dot(outward) < 0)
			area = -area;
		vnor[a] += area;
		vnor[b] += area;
		vnor[c] += area;
		vnor[dd] += area;
		if (!draw)
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
	for (int y = sy0 + 1; y < sy0 + dny; y++)
		for (int z = sz0 + 1; z < sz0 + dnz; z++) {
			uint8_t r0 = ru(y, z);
			if (r0 != 2 && ru(y + 1, z) == r0 && ru(y, z + 1) == r0)
				continue;
			for (int x = sx0 + 1; x < sx0 + dnx; x++) {
				bool here = in_s(x, y, z);
				bool draw = x >= x0 && x < x1 && y >= y0 && y < y1 && z >= z0 && z < z1;
				if (here != in_s(x + 1, y, z))
					quad(vid[di(x, y - 1, z - 1)], vid[di(x, y, z - 1)], vid[di(x, y, z)], vid[di(x, y - 1, z)], Vector3(here ? 1 : -1, 0, 0), draw);
				if (here != in_s(x, y + 1, z))
					quad(vid[di(x - 1, y, z - 1)], vid[di(x, y, z - 1)], vid[di(x, y, z)], vid[di(x - 1, y, z)], Vector3(0, here ? 1 : -1, 0), draw);
				if (here != in_s(x, y, z + 1))
					quad(vid[di(x - 1, y - 1, z)], vid[di(x, y - 1, z)], vid[di(x, y, z)], vid[di(x - 1, y, z)], Vector3(0, 0, here ? 1 : -1), draw);
			}
		}
	// what each drawn vertex wears (worked out once a vertex, only for the ones drawn)
	std::vector<int> done(nv, 0);
	std::vector<Color> vcol(nv), vcus(nv);
	auto dress = [&](int i) {
		if (done[i])
			return;
		done[i] = 1;
		const Vector3i &cb = vcube[i];
		int x = cb.x, y = cb.y, z = cb.z;
		Vector3 nn = vnor[i];
		float len = nn.length();
		nn = len > 1e-6f ? nn / len : Vector3(0, 1, 0);
		vnor[i] = nn;
		// its colour: the topmost solid cell of the eight (the one you'd see)
		int best = -1, best_y = -1 << 30, n_solid = 0, n_loose = 0;
		uint8_t cell = 0;
		for (int k = 0; k < 8; k++) {
			int cx = x + corner[k][0], cy = y + corner[k][1], cz = z + corner[k][2];
			uint8_t c = at(std::clamp(cx, 0, w - 1), std::clamp(cy, 0, h - 1), std::clamp(cz, 0, d - 1));
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
		// the cavity shade: how far the ground round here stands over this point
		float vy = vpos[i].y + 0.5f;
		float dark = 0.0f;
		for (int ring = 0; ring < 3; ring++) {
			int rr = RING_R[ring], dd = rr * 7 / 10;
			float total = top_at(x - rr, z) + top_at(x + rr, z) + top_at(x, z - rr) + top_at(x, z + rr) +
					top_at(x - dd, z - dd) + top_at(x + dd, z - dd) + top_at(x - dd, z + dd) + top_at(x + dd, z + dd);
			dark = std::max(dark, (total / 8.0f - vy) * CELL_M / RING_SCALE[ring]);
		}
		float loose_share = n_solid > 0 ? (float)n_loose / n_solid : 0.0f;
		bool rock = best >= 0 && hard[m] >= 3 && !(cell & LOOSE);
		vcol[i] = Color(base[0] * var, base[1] * var, base[2] * var);
		vcus[i] = Color(loose_share, std::clamp(dark, 0.0f, 1.0f), grass ? 1.0f : 0.0f, rock ? 1.0f : 0.0f);
	};
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
		int i = tri[k];
		dress(i);
		const Vector3 &p = vpos[i];
		vp[k] = Vector3((p.x + 0.5f) * CELL_M, (p.y + 0.5f) * CELL_M, (p.z + 0.5f) * CELL_M);
		np[k] = vnor[i];
		cp[k] = vcol[i];
		const Color &u = vcus[i];
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
					// (the digger game's blade sizes: 0.72 to 1.3 wide, as tall again times 0.8 to 1.25, so up to 0.4 m:
					// ours were barely half its height, and it's the long grass that makes its paddock look lush)
					uint32_t hk2 = hk * 2654435761u + 977u;
					float s = 0.72f + 0.58f * hf(hk, 2);
					float tall = s * (0.8f + 0.45f * hf(hk2, 1));
					int o = grass.size();
					grass.resize(o + 12);
					lay_instance(grass.ptrw() + o, hk, at, Vector3(s, tall, s), true, hf(hk, 3) * 6.2831853f);
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
