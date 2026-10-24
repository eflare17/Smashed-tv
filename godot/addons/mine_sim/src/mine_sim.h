// The mine's pixel world (the owner, 23 Oct: "the graphics from my sand digging game ... every pixel destructible,
// really satisfying drilling"): a grid of cells, each a material (dirt, clay, stone, ore, sand, water, lava ...) with
// its own shade, an amount of drilling damage and the back wall behind it; sand and loose rubble fall and pile,
// water flows and pools, lava oozes, burns into obsidian against water and cools to basalt; thin bits of dirt
// crumble off; chips knocked out fly and land as rubble. Only the parts of the world where something's moving are
// simulated (32 x 32 cell chunks, awake or asleep). It draws a window of itself as Sand Miner did (eight shades a
// material, dark outlines on edges, a soft shadow inside them, grass on the top, rims round ore and rock, sparkles
// in the precious ores, cracks spreading as the drill works, a darker back wall where it's dug) into RGBA8 pixels
// (the colour and what glows), for the mine to put on a quad in its 3D world. The game's rules are in GDScript
// (scripts/voxel/mine); this is the cells. Owned by the voxel session.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <cstdint>
#include <vector>

namespace godot {

class MineSim : public RefCounted {
	GDCLASS(MineSim, RefCounted)

public:
	// a material's ways
	enum {
		F_SOLID = 1,         // stops the ship (and anything moving)
		F_FALLS = 2,         // falls and piles like sand
		F_LIQUID = 4,        // flows (water, lava)
		F_DIG = 8,           // the drill can take it
		F_TWINKLE = 16,      // sparkles now and then
		F_RIM = 32,          // a darker rim where it meets something else (ore, rock)
		F_CRUMBLE = 64,      // thin bits of it crumble off into rubble
		F_SOFTEDGE = 128,    // its edges shaded, not outlined (clay)
		F_TOPLIT = 256,      // its top lighter (sand)
		F_ANIM = 512,        // its shades ripple (water, lava)
		F_GLOW = 1024,       // shines in the dark
		F_HOT = 2048,        // lava: burns into obsidian against water, cools to basalt
		F_WET = 4096,        // water
		F_GRASS = 8192,      // grass grows on its top at the surface
		F_NOCHIP = 16384,    // never flies off as chips (gas: a chip of it would be a blast waiting)
	};
	static const int NM = 64;          // materials
	static const int NB = 32;          // back walls
	static const int CS = 32;          // a chunk's cells across and down
	static const uint8_t LOOSE = 0x80; // (in a cell's var) loose: falls like sand, the ship pushes through it
	static const uint8_t CHIP = 0x40;  // (in a cell's var) landed from a chip of something already dug: not counted again
	static const uint8_t DUG = 0x20;   // (in a cell's var, belonging to the place, not what's in it) dug out by the drill or
	                                   // a blast: a void the player made (a cave-in can only come down over these)
	static const uint8_t FRAC = 0x18;  // (in a falling cell's var) how far into the next cell it's got, in quarters
	static const int FALL_G = 2;       // falling: speed gained a step (1/32 cell a step, kept in the cell's dmg) ...
	static const int FALL_START = 8;   // ... what it sets off at ...
	static const int FALL_MAX = 96;    // ... and the most (3 cells a step)

	MineSim();

	void setup(int w, int h, int sky_rows);
	int get_w() const { return w; }
	int get_h() const { return h; }
	int get_sky() const { return sky; }
	void set_material(int m, int flags, float hardness, int need, const PackedColorArray &shades, const Color &glow);
	void set_back(int b, const PackedColorArray &shades, int pattern);
	void set_special(int basalt, int obsidian, int bedrock);

	int get_cell(int x, int y) const;
	void set_cell(int x, int y, int m);
	int get_var(int x, int y) const;
	int get_dmg(int x, int y) const;
	int get_back(int x, int y) const;
	void set_back_at(int x, int y, int b);
	bool is_loose(int x, int y) const;
	void set_loose(int x, int y, bool on);

	// making the world
	void fill_zones(int seed, const PackedFloat32Array &bounds, const PackedInt32Array &mats, const PackedInt32Array &backs, float wobble);
	int blob(float cx, float cy, float rx, float ry, int m, float rough, int seed, int mode, int back);
	int scatter(int m, int count, int y0, int y1, int ypeak, float rmin, float rmax, int seed, int mode);
	void rect(int x0, int y0, int x1, int y1, int m, int back, int pattern);
	void fill_liquid(float cx, float cy, float rx, float ry, int m, float level);

	// saving
	PackedByteArray get_raw() const;
	bool set_raw(const PackedByteArray &raw);
	int take_changed();

	// the simulation
	void set_block(int x, int y, int bw, int bh);
	int step();
	void wake_all();
	int awake_chunks() const;

	// the drill, blasts, the launcher's shots
	Dictionary dig(float cx, float cy, float hx, float hy, float rc, float rate, int tier, float dt, float spray, float dx, float dy, bool loot);
	Dictionary explode(float cx, float cy, float r, float spray);
	int deposit(float cx, float cy, float r, int m, bool loose);
	void spray(float x, float y, int m, int n, float vx, float vy, float spread);

	// asking
	int count_rect(int x0, int y0, int rw, int rh, int what) const;
	int displace(int x0, int y0, int rw, int rh);
	PackedInt32Array collapse_scan(int x0, int y0, int x1, int y1, int vmin, int max_out) const;
	void crack_rect(int x0, int y0, int x1, int y1, int amount);
	int drop_rect(int x0, int y0, int x1, int y1);
	bool is_dug(int x, int y) const;
	void set_block2(int x, int y, int bw, int bh);
	PackedByteArray take_diff(int max_chunks);
	void diff_reset();
	int apply_chunks(const PackedByteArray &data);
	PackedByteArray chunks_in(const PackedInt32Array &rects, const PackedByteArray &except) const;
	PackedByteArray coarse(int bs, int max_block) const;
	PackedInt32Array find(int m, int x0, int y0, int x1, int y1, int max) const;
	int particles() const { return (int)parts.size(); }

	// drawing
	Array paint(int x0, int y0, int pw, int ph, int frame_no);

protected:
	static void _bind_methods();

private:
	struct Mat {
		int flags = 0;
		float hard = 1.0f;
		int need = 0;
		uint32_t col[8] = {0};
		uint32_t ao[8] = {0};
		uint32_t rim[8] = {0};
		uint32_t top[8] = {0};
		uint32_t glow = 0;
	};
	struct Back {
		uint32_t col[8] = {0};
		int pattern = 0;
	};
	struct Part {
		float x, y, vx, vy;
		uint8_t m, v;
	};

	int w = 0, h = 0, sky = 0;
	int cw = 0, chh = 0;
	std::vector<uint8_t> mat, var, dmg, back;
	std::vector<uint16_t> stamp;
	std::vector<uint8_t> awake, awake_next;
	std::vector<uint8_t> touched;                      // chunks woken since the last diff (the shared mine's)
	std::vector<uint8_t> prev_mat, prev_var, prev_dmg; // (the host's) the world as the guest was last sent it
	std::vector<Part> parts;
	Mat mats[NM];
	Back backs[NB];
	uint16_t frame = 1;
	int bx = 0, by = 0, bw = 0, bh = 0;
	int bx2 = 0, by2 = 0, bw2 = 0, bh2 = 0;            // the other ship's (the shared mine)
	int changed = 0;
	int basalt_m = 5, obsidian_m = 32, bedrock_m = 7;
	uint32_t rng = 1234567;

	inline int idx(int x, int y) const { return x + y * w; }
	inline bool in(int x, int y) const { return x >= 0 && y >= 0 && x < w && y < h; }
	inline bool blocked_cell(int x, int y) const {
		return (x >= bx && x < bx + bw && y >= by && y < by + bh) || (x >= bx2 && x < bx2 + bw2 && y >= by2 && y < by2 + bh2);
	}
	inline float rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return (rng & 0xFFFFFF) / 16777216.0f; }
	static inline uint32_t hash2(int x, int y) { uint32_t h = (uint32_t)(x * 73856093) ^ (uint32_t)(y * 19349663); h ^= h >> 13; h *= 0x5bd1e995; h ^= h >> 15; return h; }
	float noise(float x, float y, int seed) const;
	void wake(int x, int y);
	void mv(int a, int b);
	void put(int x, int y, int m, bool loose);
	bool empty_for_mover(int x, int y) const;
	void update_cell(int x, int y);
	void fall(int x, int y);
	bool roof_ok(int m) const;
	void step_parts();
	uint8_t shade_for(int x, int y, int m) const;
	static uint32_t pack(const Color &c);
	static uint32_t mul(uint32_t c, float f);
};

} // namespace godot
