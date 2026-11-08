// DigSiteGrid's network side (stage 5): the host's ground goes to the guest as whole 16^3 chunks: every chunk changed
// since the ground was made when the guest arrives (both make the rest from the same seed), then the chunks changed
// since the last send, 15 times a second (DsNet packs them with zstd). Each chunk's checksum is kept (worked out again
// only once it's changed), a drawn section's from its chunks', so the two games can compare cheaply and fix a section
// that's drifted. A packed chunk: its index (4 bytes, little end first), then its 4096 cells (x fastest, then z, then
// y). Owned by the voxel session.
#include "dig_site_grid.h"

#include <algorithm>

using namespace godot;

static const int CHUNK_CELLS = DigSiteGrid::CS * DigSiteGrid::CS * DigSiteGrid::CS;
static const int RECORD = 4 + CHUNK_CELLS;

void DigSiteGrid::pack_chunk(PackedByteArray &out, int ci) const {
	int cx = ci % ccx, cz = (ci / ccx) % ccz, cy = ci / (ccx * ccz);
	int at = out.size();
	out.resize(at + RECORD);
	uint8_t *p = out.ptrw() + at;
	p[0] = ci & 0xff;
	p[1] = (ci >> 8) & 0xff;
	p[2] = (ci >> 16) & 0xff;
	p[3] = (ci >> 24) & 0xff;
	p += 4;
	for (int ly = 0; ly < CS; ly++)
		for (int lz = 0; lz < CS; lz++) {
			const uint8_t *row = &cells[idx(cx * CS, cy * CS + ly, cz * CS + lz)];
			std::copy(row, row + CS, p);
			p += CS;
		}
}

// The chunks changed since the last take (most of them; the rest next time), packed
PackedByteArray DigSiteGrid::take_diff(int most) {
	PackedByteArray out;
	int n = 0;
	for (int i = 0; i < (int)chunk_touched.size() && n < most; i++)
		if (chunk_touched[i]) {
			chunk_touched[i] = 0;
			pack_chunk(out, i);
			n++;
		}
	return out;
}

PackedByteArray DigSiteGrid::pack_chunks(const PackedInt32Array &list) const {
	PackedByteArray out;
	for (int k = 0; k < list.size(); k++) {
		int ci = list[k];
		if (ci >= 0 && ci < (int)chunk_mod.size())
			pack_chunk(out, ci);
	}
	return out;
}

// Every chunk changed since the ground was made
PackedInt32Array DigSiteGrid::modified_chunks() const {
	PackedInt32Array out;
	for (int i = 0; i < (int)chunk_mod.size(); i++)
		if (chunk_mod[i])
			out.push_back(i);
	return out;
}

void DigSiteGrid::clear_touched() {
	std::fill(chunk_touched.begin(), chunk_touched.end(), 0);
}

// Packed chunks put in (the guest's: the host's ground as it is): their sections redrawn. -> chunks put in
int DigSiteGrid::apply_chunks(const PackedByteArray &data) {
	const uint8_t *p = data.ptr();
	int size = data.size();
	int n = 0;
	for (int at = 0; at + RECORD <= size; at += RECORD) {
		int ci = (int)p[at] | ((int)p[at + 1] << 8) | ((int)p[at + 2] << 16) | ((int)p[at + 3] << 24);
		if (ci < 0 || ci >= (int)chunk_mod.size())
			continue;
		int cx = ci % ccx, cz = (ci / ccx) % ccz, cy = ci / (ccx * ccz);
		const uint8_t *src = p + at + 4;
		for (int ly = 0; ly < CS; ly++)
			for (int lz = 0; lz < CS; lz++) {
				uint8_t *row = &cells[idx(cx * CS, cy * CS + ly, cz * CS + lz)];
				for (int lx = 0; lx < CS; lx++) {
					uint8_t v = src[(ly * CS + lz) * CS + lx];
					row[lx] = (v & MAT_MASK) < NMAT ? v : 0;
				}
			}
		chunk_mod[ci] = 1;
		hash_dirty[ci] = 1;
		if (!col_dirty.empty())
			for (int lz = 0; lz < CS; lz++)
				for (int lx = 0; lx < CS; lx++)
					col_dirty[(size_t)(cz * CS + lz) * w + cx * CS + lx] = 1;
		// the sections it's in, and those beside its faces (their faces against it change too)
		for (int sy = std::max(0, cy * CS - 2) / SH; sy <= std::min(h - 1, cy * CS + CS + 1) / SH; sy++)
			for (int sz = std::max(0, cz * CS - 2) / SW; sz <= std::min(d - 1, cz * CS + CS + 1) / SW; sz++)
				for (int sx = std::max(0, cx * CS - 2) / SW; sx <= std::min(w - 1, cx * CS + CS + 1) / SW; sx++)
					sec_dirty[(sy * scz + sz) * scx + sx] = 1;
		n++;
	}
	return n;
}

uint32_t DigSiteGrid::hash_chunk(int ci) const {
	int cx = ci % ccx, cz = (ci / ccx) % ccz, cy = ci / (ccx * ccz);
	uint32_t hsh = 2166136261u;
	for (int ly = 0; ly < CS; ly++)
		for (int lz = 0; lz < CS; lz++) {
			const uint8_t *row = &cells[idx(cx * CS, cy * CS + ly, cz * CS + lz)];
			for (int lx = 0; lx < CS; lx++) {
				hsh ^= row[lx];
				hsh *= 16777619u;
			}
		}
	return hsh;
}

// Every drawn section's checksum (from its chunks', each worked out again only if it's changed)
PackedInt32Array DigSiteGrid::section_hashes() {
	for (int i = 0; i < (int)hash_dirty.size(); i++)
		if (hash_dirty[i]) {
			hash_dirty[i] = 0;
			chunk_hash[i] = hash_chunk(i);
		}
	PackedInt32Array out;
	out.resize(scx * scy * scz);
	for (int s = 0; s < scx * scy * scz; s++) {
		PackedInt32Array ch = section_chunks(s);
		uint32_t hsh = 2166136261u;
		for (int k = 0; k < ch.size(); k++) {
			hsh ^= chunk_hash[ch[k]];
			hsh *= 16777619u;
		}
		out.set(s, (int32_t)hsh);
	}
	return out;
}

// The chunks a drawn section is made of
PackedInt32Array DigSiteGrid::section_chunks(int s) const {
	PackedInt32Array out;
	if (s < 0 || s >= scx * scy * scz)
		return out;
	int sx = s % scx, sz = (s / scx) % scz, sy = s / (scx * scz);
	for (int cy = sy * SH / CS; cy < std::min(ccy, (sy + 1) * SH / CS); cy++)
		for (int cz = sz * SW / CS; cz < std::min(ccz, (sz + 1) * SW / CS); cz++)
			for (int cx = sx * SW / CS; cx < std::min(ccx, (sx + 1) * SW / CS); cx++)
				out.push_back((cy * ccz + cz) * ccx + cx);
	return out;
}
