// DigSiteGrid's cave-ins (stage 7). A roof is a firm cell with air under it. Each material spans so far unheld
// (span_max: dirt ~2 m, clay a bit more, sand hardly at all, stone ~6 m, hard rock more; bedrock, the site's edge
// and supports never cave): measured in the air under it, out to the nearest thing holding it up (a wall, a pillar
// left standing, a support: anything solid), any way round: twice that's its span (a long tunnel is held by its two
// sides, a room's middle by a post). A roof wider than its material spans starts to go: a warning (DsCaves creaks
// and drops dust) and cave_ticks later, unless it's been held up meanwhile, it falls: the roof cells round it that
// are also too
// wide, and the cell or two over each, turn loose and drop (the dirt slumps them; a roof over that may go next). The
// roofs are looked at as the dirt works the awake chunks (dig_site_dirt.cpp), so only where something's changed.
// Owned by the voxel session.
#include "dig_site_grid.h"

#include <algorithm>
#include <cstdlib>

using namespace godot;

void DigSiteGrid::set_spans(const PackedInt32Array &spans) {
	for (int i = 0; i < NMAT; i++)
		span_max[i] = i < spans.size() ? std::max(0, (int)spans[i]) : 0;
}

// The roof at (x, y, z)'s span: twice the way to the nearest thing holding it up, in the air under it, any way
// round (square rings out from under it: a wall, a pillar left standing, a support, the site's side); more than
// limit: limit + 2
int DigSiteGrid::roof_span(int x, int y, int z, int limit) const {
	int yy = y - 1;
	if (yy < 0)
		return 0;
	int reach = limit / 2 + 1;
	for (int r = 1; r <= reach; r++) {
		for (int k = -r; k <= r; k++) {
			if (!air_at(x + k, yy, z - r) || !air_at(x + k, yy, z + r) || !air_at(x - r, yy, z + k) || !air_at(x + r, yy, z + k))
				return 2 * r;
		}
	}
	return limit + 2;
}

void DigSiteGrid::check_roof(int x, int y, int z, int m) {
	int mx = span_max[m];
	if (roof_span(x, y, z, mx) <= mx)
		return;
	for (const Going &g : going)
		if (std::abs(g.x - x) <= 10 && std::abs(g.z - z) <= 10 && std::abs(g.y - y) <= 4)
			return;                 // (going already, near here)
	if (going.size() >= 64)
		return;
	going.push_back({x, y, z, cave_ticks, m});
	cave_events.push_back(1);
	cave_events.push_back(x);
	cave_events.push_back(y);
	cave_events.push_back(z);
	cave_events.push_back(0);
}

// Each dirt tick: the roofs that are going counted down; at 0, held up meanwhile or down they come
void DigSiteGrid::cave_tick() {
	for (int i = (int)going.size() - 1; i >= 0; i--) {
		Going &g = going[i];
		if (--g.ticks > 0)
			continue;
		Going done = g;
		going.erase(going.begin() + i);
		int c = cells[idx(done.x, done.y, done.z)];
		int m = c & MAT_MASK;
		if (m == 0 || (c & LOOSE) || span_max[m] <= 0 || !air_at(done.x, done.y - 1, done.z) ||
				roof_span(done.x, done.y, done.z, span_max[m]) <= span_max[m]) {
			cave_events.push_back(3);   // (held up in time, or gone already: it settles)
			cave_events.push_back(done.x);
			cave_events.push_back(done.y);
			cave_events.push_back(done.z);
			cave_events.push_back(0);
			continue;
		}
		int n = collapse(done);
		cave_events.push_back(2);
		cave_events.push_back(done.x);
		cave_events.push_back(done.y);
		cave_events.push_back(done.z);
		cave_events.push_back(n);
	}
}

// A roof down: the roof cells round it (that far out, too wide for themselves), and two over each, turned loose
// (they fall, the dirt slumps them). -> cells
int DigSiteGrid::collapse(const Going &g) {
	int r = std::max(4, span_max[g.m] / 2 + 2);
	int n = 0;
	std::vector<int> drop;
	for (int dz = -r; dz <= r; dz++)
		for (int dx = -r; dx <= r; dx++) {
			if (dx * dx + dz * dz > r * r)
				continue;
			int x = g.x + dx, z = g.z + dz;
			// the roof in this column near the going one's height: the lowest firm cell with air under it
			for (int y = g.y - 2; y <= g.y + 2; y++) {
				if (!in(x, y, z) || !air_at(x, y - 1, z))
					continue;
				uint8_t c = cells[idx(x, y, z)];
				int m = c & MAT_MASK;
				if (m == 0 || span_max[m] <= 0 || (c & LOOSE))
					continue;
				if (roof_span(x, y, z, span_max[m]) <= span_max[m])
					break;
				for (int k = 0; k < 3; k++) {
					if (!in(x, y + k, z))
						break;
					uint8_t c2 = cells[idx(x, y + k, z)];
					int m2 = c2 & MAT_MASK;
					if (m2 == 0 || span_max[m2] <= 0)
						break;
					drop.push_back(idx(x, y + k, z));
				}
				break;
			}
		}
	for (int i : drop) {
		cells[i] |= LOOSE;
		int x = i % w, z = (i / w) % d, y = i / (w * d);
		touch(x, y, z);
		n++;
	}
	moves_total += n;
	return n;
}

PackedInt32Array DigSiteGrid::take_cave_events() {
	PackedInt32Array out;
	for (int v : cave_events)
		out.push_back(v);
	cave_events.clear();
	return out;
}
