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

// A section's surface as triangles: [verts (metres from the grid's corner), normals, colours] (no index: the same
// verts make the collision shape)
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
				uint8_t v = at(x, y, z);
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
		return out;
	}
	// samples at the cell middles [x0-1, x1] (and so on): the share of the 27 round each that's solid
	int sx0 = x0 - 1, sy0 = y0 - 1, sz0 = z0 - 1;
	int snx = (x1 - x0) + 2, sny = (y1 - y0) + 2, snz = (z1 - z0) + 2;
	std::vector<float> smp((size_t)snx * sny * snz);
	auto si = [&](int x, int y, int z) { return ((y - sy0) * snz + (z - sz0)) * snx + (x - sx0); };
	for (int y = sy0; y < sy0 + sny; y++)
		for (int z = sz0; z < sz0 + snz; z++)
			for (int x = sx0; x < sx0 + snx; x++) {
				int n = 0;
				for (int a = -1; a <= 1; a++)
					for (int b = -1; b <= 1; b++)
						for (int c = -1; c <= 1; c++)
							n += solid[ci(x + c, y + a, z + b)];
				smp[si(x, y, z)] = n / 27.0f;
			}
	// a vertex in each cube (between samples i..i+1) the surface passes through: cubes [x0-1, x1) (and so on)
	int dnx = snx - 1, dny = sny - 1, dnz = snz - 1;
	std::vector<int> vid((size_t)dnx * dny * dnz, -1);
	auto di = [&](int x, int y, int z) { return ((y - sy0) * dnz + (z - sz0)) * dnx + (x - sx0); };
	std::vector<Vector3> vpos, vnor;
	std::vector<Color> vcol;
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
				int best = -1, best_y = -1 << 30;
				uint8_t cell = 0;
				for (int k = 0; k < 8; k++) {
					int cx = x + corner[k][0], cy = y + corner[k][1], cz = z + corner[k][2];
					uint8_t c = at(cx, cy, cz);
					if ((c & MAT_MASK) == AIR || (c & MAT_MASK) >= NMAT)
						continue;
					if (cy > best_y) {
						best_y = cy;
						best = k;
						cell = c;
					}
				}
				int m = best >= 0 ? (cell & MAT_MASK) : DIRT_MAT;
				const float *base = (m == TOPSOIL_MAT && !(cell & LOOSE) && nn.y > 0.55f) ? top_col : col[m];
				float var = 0.92f + 0.16f * ((hash3(x >> 1, y >> 1, z >> 1) & 255) / 255.0f);
				float r = base[0] * var, g = base[1] * var, b = base[2] * var;
				if (cell & LOOSE) {
					r = r * 0.85f + 0.12f;
					g = g * 0.85f + 0.1f;
					b = b * 0.85f + 0.08f;
				}
				vid[di(x, y, z)] = (int)vpos.size();
				vpos.push_back(Vector3((x + 0.5f + px) * CELL_M, (y + 0.5f + py) * CELL_M, (z + 0.5f + pz) * CELL_M));
				vnor.push_back(nn);
				vcol.push_back(Color(r, g, b));
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
	verts.resize(tri.size());
	norms.resize(tri.size());
	cols.resize(tri.size());
	Vector3 *vp = verts.ptrw();
	Vector3 *np = norms.ptrw();
	Color *cp = cols.ptrw();
	for (size_t k = 0; k < tri.size(); k++) {
		vp[k] = vpos[tri[k]];
		np[k] = vnor[tri[k]];
		cp[k] = vcol[tri[k]];
	}
	out.push_back(verts);
	out.push_back(norms);
	out.push_back(cols);
	return out;
}
