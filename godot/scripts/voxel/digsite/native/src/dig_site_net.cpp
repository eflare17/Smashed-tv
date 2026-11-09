// DigSiteGrid's network side (stage 5): the host's ground goes to the guest as whole 16^3 chunks: every chunk changed
// since the ground was made when the guest arrives (both make the rest from the same seed), then the chunks changed
// since the last send, 15 times a second (DsNet packs them with zstd). Each chunk's checksum is kept (worked out again
// only once it's changed), a drawn section's from its chunks', so the two games can compare cheaply and fix a section
// that's drifted. A packed chunk: its index (4 bytes, little end first), then its 4096 cells (x fastest, then z, then
// y). The loose layer (dig_site_layer.cpp) goes the same way, a block of 16 x 16 columns at a time: its index with
// the top bit set, then each column's mm, then each one's material (256 + 256 bytes); a section's checksum takes in its
// columns' layer. Owned by the voxel session.
#include "dig_site_grid.h"

#include <algorithm>

using namespace godot;

static const int CHUNK_CELLS = DigSiteGrid::CS * DigSiteGrid::CS * DigSiteGrid::CS;
static const int RECORD = 4 + CHUNK_CELLS;
static const int LAYER_COLS = DigSiteGrid::CS * DigSiteGrid::CS;
static const int LAYER_RECORD = 4 + 2 * LAYER_COLS;
static const uint32_t LAYER_BIT = 0x80000000u;

static void put_u32(uint8_t *p, uint32_t v) {
	p[0] = v & 0xff;
	p[1] = (v >> 8) & 0xff;
	p[2] = (v >> 16) & 0xff;
	p[3] = (v >> 24) & 0xff;
}

// A block of columns' layer packed: its index | LAYER_BIT, their mm, their materials
void DigSiteGrid::pack_layer(PackedByteArray &out, int bi) const {
	int bx = bi % lcx, bz = bi / lcx;
	int at = out.size();
	out.resize(at + LAYER_RECORD);
	uint8_t *p = out.ptrw() + at;
	put_u32(p, (uint32_t)bi | LAYER_BIT);
	p += 4;
	for (int lz = 0; lz < CS; lz++)
		for (int lx = 0; lx < CS; lx++) {
			size_t k = colk(bx * CS + lx, bz * CS + lz);
			p[lz * CS + lx] = fr[k];
			p[LAYER_COLS + lz * CS + lx] = fm[k];
		}
}

uint32_t DigSiteGrid::hash_layer(int bi) const {
	int bx = bi % lcx, bz = bi / lcx;
	uint32_t hsh = 2166136261u;
	for (int lz = 0; lz < CS; lz++)
		for (int lx = 0; lx < CS; lx++) {
			size_t k = colk(bx * CS + lx, bz * CS + lz);
			hsh ^= fr[k];
			hsh *= 16777619u;
			hsh ^= fr[k] ? fm[k] : 0;     // (an empty layer's material doesn't matter)
			hsh *= 16777619u;
		}
	return hsh;
}

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

// The chunks changed since the last take (most of them; the rest next time), packed, then the blocks of the layer
// changed (all of them: they're small, and a layer half sent would show a heap's surface torn)
PackedByteArray DigSiteGrid::take_diff(int most) {
	PackedByteArray out;
	int n = 0;
	for (int i = 0; i < (int)chunk_touched.size() && n < most; i++)
		if (chunk_touched[i]) {
			chunk_touched[i] = 0;
			pack_chunk(out, i);
			n++;
		}
	for (int b = 0; b < (int)lay_touched.size(); b++)
		if (lay_touched[b]) {
			lay_touched[b] = 0;
			pack_layer(out, b);
		}
	return out;
}

// Those chunks packed, and the layer over each one's columns
PackedByteArray DigSiteGrid::pack_chunks(const PackedInt32Array &list) const {
	PackedByteArray out;
	std::vector<uint8_t> laid(lay_mod.size(), 0);
	for (int k = 0; k < list.size(); k++) {
		int ci = list[k];
		if (ci < 0 || ci >= (int)chunk_mod.size())
			continue;
		pack_chunk(out, ci);
		int b = ((ci / ccx) % ccz) * lcx + ci % ccx;
		if (b < (int)laid.size() && !laid[b]) {
			laid[b] = 1;
			pack_layer(out, b);
		}
	}
	return out;
}

// Every chunk changed since the ground was made (and, for a block of columns whose layer has changed, its bottom
// chunk: pack_chunks sends the layer with it)
PackedInt32Array DigSiteGrid::modified_chunks() const {
	PackedInt32Array out;
	std::vector<uint8_t> has(lay_mod.size(), 0);
	for (int i = 0; i < (int)chunk_mod.size(); i++)
		if (chunk_mod[i]) {
			out.push_back(i);
			int b = ((i / ccx) % ccz) * lcx + i % ccx;
			if (b < (int)has.size())
				has[b] = 1;
		}
	for (int b = 0; b < (int)lay_mod.size(); b++)
		if (lay_mod[b] && !has[b])
			out.push_back((b / lcx) * ccx + b % lcx);   // (cy 0)
	return out;
}

void DigSiteGrid::clear_touched() {
	std::fill(chunk_touched.begin(), chunk_touched.end(), 0);
	std::fill(lay_touched.begin(), lay_touched.end(), 0);
}

// Packed chunks put in (the guest's: the host's ground as it is): their sections redrawn. -> chunks put in
int DigSiteGrid::apply_chunks(const PackedByteArray &data) {
	const uint8_t *p = data.ptr();
	int size = data.size();
	int n = 0;
	for (int at = 0; at + 4 <= size;) {
		uint32_t head = (uint32_t)p[at] | ((uint32_t)p[at + 1] << 8) | ((uint32_t)p[at + 2] << 16) | ((uint32_t)p[at + 3] << 24);
		if (head & LAYER_BIT) {
			// a block of the layer
			if (at + LAYER_RECORD > size)
				break;
			int bi = (int)(head & ~LAYER_BIT);
			const uint8_t *src = p + at + 4;
			at += LAYER_RECORD;
			if (bi < 0 || bi >= lcx * lcz || fr.empty())
				continue;
			int bx = bi % lcx, bz = bi / lcx;
			for (int lz = 0; lz < CS; lz++)
				for (int lx = 0; lx < CS; lx++) {
					int x = bx * CS + lx, z = bz * CS + lz;
					size_t k = colk(x, z);
					uint8_t f = std::min<uint8_t>(src[lz * CS + lx], (uint8_t)(FR_OVER - 1));
					uint8_t m = src[LAYER_COLS + lz * CS + lx];
					if ((m & MAT_MASK) >= NMAT)
						m = 0;
					if (fr[k] != f || fm[k] != m) {
						fr[k] = f;
						fm[k] = m;
						lay_changed(x, z);
					}
				}
			lay_mod[bi] = 1;
			lay_hash_dirty[bi] = 1;
			n++;
			continue;
		}
		if (at + RECORD > size)
			break;
		int ci = (int)head;
		at += RECORD;
		if (ci < 0 || ci >= (int)chunk_mod.size())
			continue;
		int cx = ci % ccx, cz = (ci / ccx) % ccz, cy = ci / (ccx * ccz);
		const uint8_t *src = p + at - RECORD + 4;
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
				for (int lx = 0; lx < CS; lx++) {
					col_dirty[(size_t)(cz * CS + lz) * w + cx * CS + lx] = 1;
					lay_changed(cx * CS + lx, cz * CS + lz);
				}
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
	for (int b = 0; b < (int)lay_hash_dirty.size(); b++)
		if (lay_hash_dirty[b]) {
			lay_hash_dirty[b] = 0;
			lay_hash[b] = hash_layer(b);
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
		// (and the layer on its columns: every section in the column takes it in, so a drifted layer's fixed with them)
		int sx = s % scx, sz = (s / scx) % scz;
		for (int bz = sz * SW / CS; bz < std::min(lcz, (sz + 1) * SW / CS); bz++)
			for (int bx = sx * SW / CS; bx < std::min(lcx, (sx + 1) * SW / CS); bx++) {
				hsh ^= lay_hash[bz * lcx + bx];
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
