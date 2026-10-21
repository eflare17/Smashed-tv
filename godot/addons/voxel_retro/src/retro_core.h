// The games room's console (Stage 7): a small libretro frontend as a Godot class. It loads a libretro core (a
// shared library: Genesis Plus GX for the Mega Drive, Master System and Game Gear; Snes9x for the Super Nintendo),
// loads a game into it, runs it a frame at a time when asked, and hands back the picture (an Image) and the sound
// (stereo frames for an AudioStreamGenerator); the buttons are set from Godot. One core runs at a time (libretro's
// callbacks are plain C functions). Owned by the voxel session.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <vector>
#include <string>

#include "libretro.h"

namespace godot {

class RetroCore : public RefCounted {
	GDCLASS(RetroCore, RefCounted)

public:
	RetroCore();
	~RetroCore();

	bool load_core(const String &path);
	bool load_game(const String &path);
	void unload();
	bool is_running() const { return game_loaded; }
	void run();
	Ref<Image> get_frame() const;
	int get_frame_serial() const { return frame_serial; }
	PackedVector2Array take_audio();
	void set_button(int port, int id, bool down);
	void clear_buttons();
	double get_fps() const { return av.timing.fps; }
	double get_sample_rate() const { return av.timing.sample_rate; }
	double get_aspect() const;
	String get_core_name() const { return core_name; }
	String get_last_error() const { return last_error; }
	void set_dirs(const String &system_dir, const String &save_dir);
	PackedByteArray save_state();
	bool load_state(const PackedByteArray &data);
	void reset();

	// (the C callbacks' way in)
	bool env(unsigned cmd, void *data);
	void video(const void *data, unsigned w, unsigned h, size_t pitch);
	size_t audio_batch(const int16_t *data, size_t frames);
	int16_t input(unsigned port, unsigned device, unsigned index, unsigned id);

protected:
	static void _bind_methods();

private:
	void *lib = nullptr;
	bool core_inited = false;
	bool game_loaded = false;
	String core_name;
	String last_error;
	std::string system_dir_s;
	std::string save_dir_s;
	retro_pixel_format pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
	retro_system_av_info av = {};
	PackedByteArray frame;          // RGB8, frame_w x frame_h
	int frame_w = 0;
	int frame_h = 0;
	int frame_serial = 0;
	std::vector<int16_t> audio;     // interleaved stereo
	uint16_t buttons[4] = {0, 0, 0, 0};

	// the core's functions
	void (*f_init)(void) = nullptr;
	void (*f_deinit)(void) = nullptr;
	void (*f_set_environment)(retro_environment_t) = nullptr;
	void (*f_set_video_refresh)(retro_video_refresh_t) = nullptr;
	void (*f_set_audio_sample)(retro_audio_sample_t) = nullptr;
	void (*f_set_audio_sample_batch)(retro_audio_sample_batch_t) = nullptr;
	void (*f_set_input_poll)(retro_input_poll_t) = nullptr;
	void (*f_set_input_state)(retro_input_state_t) = nullptr;
	void (*f_get_system_info)(retro_system_info *) = nullptr;
	void (*f_get_system_av_info)(retro_system_av_info *) = nullptr;
	void (*f_set_controller_port_device)(unsigned, unsigned) = nullptr;
	void (*f_reset)(void) = nullptr;
	void (*f_run)(void) = nullptr;
	size_t (*f_serialize_size)(void) = nullptr;
	bool (*f_serialize)(void *, size_t) = nullptr;
	bool (*f_unserialize)(const void *, size_t) = nullptr;
	bool (*f_load_game)(const retro_game_info *) = nullptr;
	void (*f_unload_game)(void) = nullptr;

	void close_lib();
};

} // namespace godot
