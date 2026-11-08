// DigSiteGrid: the Dig Site's voxel ground (scripts/voxel/digsite). A box of cells 12.5 cm a side (512 x 192 x 512 by
// default: 64 m across, 24 m tall, the ground's top 4 m from the top), one byte a cell: the material (low 5 bits) and
// whether it's loose (LOOSE). Made from a seed (the same in every game), dug and filled, and drawn in sections
// (SW x SH x SW cells) as faces with their colours. Data is also tracked in 16^3 chunks (for the network and the dirt,
// in later stages). The materials' colours and hardness come from GDScript (DsMats). Owned by the voxel session.
#ifndef DIG_SITE_GRID_H
#define DIG_SITE_GRID_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cstdint>
#include <vector>
#include <map>

namespace godot {

class DigSiteGrid : public RefCounted {
	GDCLASS(DigSiteGrid, RefCounted)

public:
	static const int MAT_MASK = 0x1f;
	static const int LOOSE = 0x20;
	static const int CS = 16;     // data chunk side
	static const int SW = 32;     // a drawn section's width (x, z) ...
	static const int SH = 64;     // ... and height
	static const int NMAT = 32;

private:
	int w = 0, h = 0, d = 0;      // cells x, y, z
	int surface = 0;              // cell y of the ground's base level (its top cells sit just under it)
	int seed_ = 1;
	std::vector<uint8_t> cells;
	// chunks (16^3) and sections (SW x SH x SW)
	int ccx = 0, ccy = 0, ccz = 0;
	int scx = 0, scy = 0, scz = 0;
	std::vector<uint8_t> sec_dirty;
	std::vector<uint8_t> chunk_touched;   // changed since the last take (the network, later)
	// materials
	float col[NMAT][3];
	int hard[NMAT];
	float top_col[3];                      // a topsoil cell's top with air over it: grass
	uint32_t rng = 1;
	// the dirt (dig_site_dirt.cpp): which chunks are awake, how tall each material's firm wall stands
	int wall_h[NMAT];                      // cells a firm wall of it stands straight up (0: never gives way: rock)
	std::vector<uint8_t> awake;            // chunk -> 1: something may move in it
	std::vector<uint64_t> moved_bits;      // cells moved into this tick (not moved again till the next)
	std::vector<int> moved_list;
	std::vector<int> wake_list;            // the awake chunks being worked through (what's left carries over)
	int wake_at = 0;
	int tick_n = 0;
	int moves_total = 0;
	void wake_near(int x, int y, int z);
	inline bool air_at(int x, int y, int z) const { return in(x, y, z) && (cells[idx(x, y, z)] & MAT_MASK) == 0; }
	// machines' blades and buckets, solid to the loose dirt (dig_site_blade.cpp): cells marked here are as good as
	// ground to it (it banks against them and rests on them), cleared and marked again as each one moves
	std::vector<uint64_t> blocked_bits;
	std::map<int, std::vector<int>> blocked_by;
	inline bool blocked(int i) const { return !blocked_bits.empty() && ((blocked_bits[i >> 6] >> (i & 63)) & 1ull); }
	inline bool free_at(int x, int y, int z) const {
		if (!in(x, y, z))
			return false;
		int i = idx(x, y, z);
		return (cells[i] & MAT_MASK) == 0 && !blocked(i);
	}
	int drop_at(int x, int y, int z, int limit) const;
	void move_cell(int from, int x, int y, int z);
	int settle_chunk(int ci);
	// cave-ins (dig_site_cave.cpp): how wide a roof of each material spans unheld, the roofs that are going
	int span_max[NMAT];                    // cells (0: never caves: bedrock, the edge, supports)
	struct Going { int x, y, z, ticks, m; };
	std::vector<Going> going;
	std::vector<int> cave_events;          // [kind (1 warning, 2 collapse), x, y, z, n] ...
	int cave_ticks = 60;                   // ticks from the warning to the fall
	int roof_span(int x, int y, int z, int limit) const;
	void check_roof(int x, int y, int z, int m);
	void cave_tick();
	int collapse(const Going &g);
	// blades (dig_site_blade.cpp)
	int moved_total_blade = 0;
	std::vector<int16_t> start_tops;
	// each column's top solid cell (-1: none), worked out again only when something in the column's changed (touch,
	// apply_chunks, generate mark it): the mesher, the grass and clods, and column_top read it
	mutable std::vector<int16_t> col_top;
	mutable std::vector<uint8_t> col_dirty;
	int top_cached(int x, int z) const;   // (each column's top cell as made: a dozer's CUT holds its depth under it)
	uint32_t blade_rng = 12345u;
	int dither(float v);
	bool lay_on(int x, int z, uint8_t v, int top_y);
	bool spill(float px, float pz, float fx, float fz, float ox, float oz, float to_end, uint8_t v, int top_y);
	// the network (dig_site_net.cpp): chunks changed since made (sent to a guest arriving), their checksums
	std::vector<uint8_t> chunk_mod;
	std::vector<uint32_t> chunk_hash;
	std::vector<uint8_t> hash_dirty;
	void pack_chunk(PackedByteArray &out, int ci) const;
	uint32_t hash_chunk(int ci) const;

	inline int idx(int x, int y, int z) const { return (y * d + z) * w + x; }
	inline bool in(int x, int y, int z) const { return x >= 0 && y >= 0 && z >= 0 && x < w && y < h && z < d; }
	inline uint8_t at(int x, int y, int z) const { return in(x, y, z) ? cells[idx(x, y, z)] : (y >= h ? 0 : 255); }
	void touch(int x, int y, int z);
	uint32_t next();
	float frand();
	static uint32_t hash3(int x, int y, int z);
	float noise2(float x, float z, int s) const;
	void blob(int m, float cx, float cy, float cz, float rx, float ry, float rz, int only_over_depth_lo, int only_over_depth_hi, const std::vector<int> &heights, bool only_in_solid);

protected:
	static void _bind_methods();

public:
	DigSiteGrid();
	void setup(int p_w, int p_h, int p_d, int p_surface);
	void set_materials(const PackedColorArray &colors, const PackedInt32Array &hardness, const Color &grass);
	void generate(int seed);
	int get_seed() const { return seed_; }
	int get_w() const { return w; }
	int get_h() const { return h; }
	int get_d() const { return d; }
	int get_surface() const { return surface; }
	int start_top(int x, int z) const;

	int get_cell(int x, int y, int z) const;
	void set_cell(int x, int y, int z, int v);
	int firm_top(int x, int z) const;
	int column_top(int x, int z) const;
	int count_mat(int m) const;
	int count_box(int x0, int y0, int z0, int x1, int y1, int z1, int what) const;

	Dictionary dig_sphere(const Vector3 &c, float r, int hardest);
	int fill_sphere(const Vector3 &c, float r, int m, int most, bool loose);
	Dictionary blast_sphere(const Vector3 &c, float r, const PackedFloat32Array &reach, float crack);
	// blades (dig_site_blade.cpp)
	Dictionary blade_sweep(const Vector3 &a, const Vector3 &b, const Vector3 &fwd, int rows, float mouth, int firm_most, int hardest, int take_most, float heap, float share = 1.0f);
	int load_ahead(const Vector3 &a, const Vector3 &b, const Vector3 &fwd, float reach) const;
	int pour_at(int x, int z, int top_y, int m, int n);
	void block_blade(int owner, const Vector3 &a, const Vector3 &b, const Vector3 &fwd, float thick, float high);
	void unblock(int owner);

	// the dirt (dig_site_dirt.cpp)
	void set_physics(const PackedInt32Array &walls);
	int settle(int budget_usec);
	int awake_count() const;
	void wake_all();
	int drop_column(int x, int z, int m, int n);
	int get_moves_total() const { return moves_total; }
	// cave-ins (dig_site_cave.cpp)
	void set_spans(const PackedInt32Array &spans);
	void set_cave_ticks(int t) { cave_ticks = std::max(1, t); }
	PackedInt32Array take_cave_events();
	int going_count() const { return (int)going.size(); }
	int roof_span_at(int x, int y, int z) const { return roof_span(x, y, z, 200); }

	// the network (dig_site_net.cpp)
	PackedByteArray take_diff(int most);
	PackedByteArray pack_chunks(const PackedInt32Array &list) const;
	PackedInt32Array modified_chunks() const;
	int apply_chunks(const PackedByteArray &data);
	PackedInt32Array section_hashes();
	PackedInt32Array section_chunks(int s) const;
	void clear_touched();
	int chunk_count() const { return ccx * ccy * ccz; }

	PackedInt32Array take_dirty_sections(int most);
	void mark_all_dirty();
	Array mesh_section(int sx, int sy, int sz) const;
	Array decor_section(int sx, int sy, int sz, float blades_per_m2) const;
	int section_count() const { return scx * scy * scz; }
	Vector3 section_dims() const { return Vector3(scx, scy, scz); }
};

} // namespace godot

#endif
