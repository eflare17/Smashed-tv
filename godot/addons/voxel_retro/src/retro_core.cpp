// See retro_core.h. Owned by the voxel session.
#include "retro_core.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <cstdarg>
#include <cstdio>
#include <cstring>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

using namespace godot;

static RetroCore *g_core = nullptr;     // the one running (libretro's callbacks are plain C)

static bool c_env(unsigned cmd, void *data) { return g_core ? g_core->env(cmd, data) : false; }
static void c_video(const void *data, unsigned w, unsigned h, size_t pitch) { if (g_core) g_core->video(data, w, h, pitch); }
static void c_audio(int16_t l, int16_t r) { int16_t s[2] = {l, r}; if (g_core) g_core->audio_batch(s, 1); }
static size_t c_audio_batch(const int16_t *data, size_t frames) { return g_core ? g_core->audio_batch(data, frames) : frames; }
static void c_poll(void) {}
static int16_t c_input(unsigned port, unsigned device, unsigned index, unsigned id) { return g_core ? g_core->input(port, device, index, id) : 0; }
static void c_log(enum retro_log_level level, const char *fmt, ...) {
	if (level < RETRO_LOG_WARN)
		return;
	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	UtilityFunctions::print("[retro] ", String(buf).strip_edges());
}

RetroCore::RetroCore() {}

RetroCore::~RetroCore() {
	unload();
	close_lib();
}

static void *sym(void *lib, const char *name) {
#ifdef _WIN32
	return (void *)GetProcAddress((HMODULE)lib, name);
#else
	return dlsym(lib, name);
#endif
}

bool RetroCore::load_core(const String &path) {
	unload();
	close_lib();
	if (g_core && g_core != this) {
		last_error = "another console is already running";
		return false;
	}
#ifdef _WIN32
	lib = (void *)LoadLibraryW((LPCWSTR)path.utf16().get_data());
#else
	lib = dlopen(path.utf8().get_data(), RTLD_LAZY | RTLD_LOCAL);
#endif
	if (!lib) {
		last_error = "can't load the core: " + path;
		return false;
	}
#define LOAD(f, n) *(void **)&f = sym(lib, n); if (!f) { last_error = String("the core has no ") + n; close_lib(); return false; }
	LOAD(f_init, "retro_init")
	LOAD(f_deinit, "retro_deinit")
	LOAD(f_set_environment, "retro_set_environment")
	LOAD(f_set_video_refresh, "retro_set_video_refresh")
	LOAD(f_set_audio_sample, "retro_set_audio_sample")
	LOAD(f_set_audio_sample_batch, "retro_set_audio_sample_batch")
	LOAD(f_set_input_poll, "retro_set_input_poll")
	LOAD(f_set_input_state, "retro_set_input_state")
	LOAD(f_get_system_info, "retro_get_system_info")
	LOAD(f_get_system_av_info, "retro_get_system_av_info")
	LOAD(f_set_controller_port_device, "retro_set_controller_port_device")
	LOAD(f_reset, "retro_reset")
	LOAD(f_run, "retro_run")
	LOAD(f_serialize_size, "retro_serialize_size")
	LOAD(f_serialize, "retro_serialize")
	LOAD(f_unserialize, "retro_unserialize")
	LOAD(f_load_game, "retro_load_game")
	LOAD(f_unload_game, "retro_unload_game")
#undef LOAD
	g_core = this;
	f_set_environment(c_env);
	f_set_video_refresh(c_video);
	f_set_audio_sample(c_audio);
	f_set_audio_sample_batch(c_audio_batch);
	f_set_input_poll(c_poll);
	f_set_input_state(c_input);
	f_init();
	core_inited = true;
	retro_system_info info = {};
	f_get_system_info(&info);
	core_name = String(info.library_name ? info.library_name : "?");
	return true;
}

void RetroCore::close_lib() {
	if (core_inited && f_deinit) {
		g_core = this;
		f_deinit();
	}
	core_inited = false;
	if (lib) {
#ifdef _WIN32
		FreeLibrary((HMODULE)lib);
#else
		dlclose(lib);
#endif
	}
	lib = nullptr;
	if (g_core == this)
		g_core = nullptr;
}

bool RetroCore::load_game(const String &path) {
	if (!core_inited) {
		last_error = "no core loaded";
		return false;
	}
	if (game_loaded)
		unload();
	retro_system_info info = {};
	f_get_system_info(&info);
	PackedByteArray bytes;
	if (!info.need_fullpath) {
		bytes = FileAccess::get_file_as_bytes(path);
		if (bytes.is_empty()) {
			last_error = "can't read the game: " + path;
			return false;
		}
	}
	CharString p = path.utf8();
	retro_game_info gi = {};
	gi.path = p.get_data();
	gi.data = bytes.is_empty() ? nullptr : bytes.ptr();
	gi.size = (size_t)bytes.size();
	g_core = this;
	if (!f_load_game(&gi)) {
		last_error = "the core couldn't start the game";
		return false;
	}
	f_get_system_av_info(&av);
	f_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
	f_set_controller_port_device(1, RETRO_DEVICE_JOYPAD);
	game_loaded = true;
	audio.clear();
	clear_buttons();
	return true;
}

void RetroCore::unload() {
	if (game_loaded && f_unload_game) {
		g_core = this;
		f_unload_game();
	}
	game_loaded = false;
	audio.clear();
}

void RetroCore::run() {
	if (!game_loaded)
		return;
	g_core = this;
	f_run();
}

void RetroCore::reset() {
	if (game_loaded)
		f_reset();
}

double RetroCore::get_aspect() const {
	if (av.geometry.aspect_ratio > 0.0f)
		return av.geometry.aspect_ratio;
	return frame_h > 0 ? double(frame_w) / double(frame_h) : 4.0 / 3.0;
}

void RetroCore::set_dirs(const String &system_dir, const String &save_dir) {
	system_dir_s = system_dir.utf8().get_data();
	save_dir_s = save_dir.utf8().get_data();
}

bool RetroCore::env(unsigned cmd, void *data) {
	switch (cmd) {
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
			retro_pixel_format f = *(const retro_pixel_format *)data;
			if (f != RETRO_PIXEL_FORMAT_0RGB1555 && f != RETRO_PIXEL_FORMAT_RGB565 && f != RETRO_PIXEL_FORMAT_XRGB8888)
				return false;
			pixel_format = f;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
			*(const char **)data = system_dir_s.empty() ? nullptr : system_dir_s.c_str();
			return !system_dir_s.empty();
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
			*(const char **)data = save_dir_s.empty() ? nullptr : save_dir_s.c_str();
			return !save_dir_s.empty();
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
			((retro_log_callback *)data)->log = c_log;
			return true;
		case RETRO_ENVIRONMENT_GET_CAN_DUPE:
			*(bool *)data = true;
			return true;
		case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
			return true;
		case RETRO_ENVIRONMENT_GET_VARIABLE:
			((retro_variable *)data)->value = nullptr;      // (every option at its default)
			return false;
		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
			*(bool *)data = false;
			return true;
		case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
			av = *(const retro_system_av_info *)data;
			return true;
		case RETRO_ENVIRONMENT_SET_GEOMETRY:
			av.geometry = *(const retro_game_geometry *)data;
			return true;
		case RETRO_ENVIRONMENT_GET_LANGUAGE:
			*(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
			return true;
		case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
		case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
		case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
		case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
		case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
		case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
			return true;
		case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
			*(unsigned *)data = 0;
			return true;
		case RETRO_ENVIRONMENT_SET_VARIABLES:
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL:
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
			return true;
		default:
			return false;
	}
}

void RetroCore::video(const void *data, unsigned w, unsigned h, size_t pitch) {
	if (!data)
		return;                     // (a duped frame: the last one stands)
	if ((int)w != frame_w || (int)h != frame_h || frame.size() != (int64_t)w * h * 3) {
		frame_w = (int)w;
		frame_h = (int)h;
		frame.resize((int64_t)w * h * 3);
	}
	uint8_t *out = frame.ptrw();
	const uint8_t *src = (const uint8_t *)data;
	for (unsigned y = 0; y < h; y++) {
		const uint8_t *row = src + y * pitch;
		uint8_t *o = out + (size_t)y * w * 3;
		if (pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
			const uint32_t *px = (const uint32_t *)row;
			for (unsigned x = 0; x < w; x++) {
				uint32_t c = px[x];
				o[0] = (c >> 16) & 255; o[1] = (c >> 8) & 255; o[2] = c & 255;
				o += 3;
			}
		} else if (pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
			const uint16_t *px = (const uint16_t *)row;
			for (unsigned x = 0; x < w; x++) {
				uint16_t c = px[x];
				uint8_t r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31;
				o[0] = (r << 3) | (r >> 2); o[1] = (g << 2) | (g >> 4); o[2] = (b << 3) | (b >> 2);
				o += 3;
			}
		} else {
			const uint16_t *px = (const uint16_t *)row;
			for (unsigned x = 0; x < w; x++) {
				uint16_t c = px[x];
				uint8_t r = (c >> 10) & 31, g = (c >> 5) & 31, b = c & 31;
				o[0] = (r << 3) | (r >> 2); o[1] = (g << 3) | (g >> 2); o[2] = (b << 3) | (b >> 2);
				o += 3;
			}
		}
	}
	frame_serial++;
}

size_t RetroCore::audio_batch(const int16_t *data, size_t frames) {
	if (audio.size() < 48000 * 2)       // (a second's worth at most waiting: nobody's listening, it's dropped)
		audio.insert(audio.end(), data, data + frames * 2);
	return frames;
}

int16_t RetroCore::input(unsigned port, unsigned device, unsigned index, unsigned id) {
	if (port >= 4 || (device & RETRO_DEVICE_MASK) != RETRO_DEVICE_JOYPAD)
		return 0;
	if (id == RETRO_DEVICE_ID_JOYPAD_MASK)
		return (int16_t)buttons[port];
	return (id < 16 && (buttons[port] >> id) & 1) ? 1 : 0;
}

Ref<Image> RetroCore::get_frame() const {
	if (frame_w <= 0 || frame_h <= 0)
		return Ref<Image>();
	return Image::create_from_data(frame_w, frame_h, false, Image::FORMAT_RGB8, frame);
}

PackedVector2Array RetroCore::take_audio() {
	PackedVector2Array out;
	size_t n = audio.size() / 2;
	out.resize((int64_t)n);
	Vector2 *w = out.ptrw();
	for (size_t i = 0; i < n; i++)
		w[i] = Vector2(audio[i * 2] / 32768.0f, audio[i * 2 + 1] / 32768.0f);
	audio.clear();
	return out;
}

void RetroCore::set_button(int port, int id, bool down) {
	if (port < 0 || port >= 4 || id < 0 || id >= 16)
		return;
	if (down)
		buttons[port] |= (1 << id);
	else
		buttons[port] &= ~(1 << id);
}

void RetroCore::clear_buttons() {
	for (int i = 0; i < 4; i++)
		buttons[i] = 0;
}

PackedByteArray RetroCore::save_state() {
	PackedByteArray out;
	if (!game_loaded)
		return out;
	size_t n = f_serialize_size();
	out.resize((int64_t)n);
	if (n == 0 || !f_serialize(out.ptrw(), n))
		out.clear();
	return out;
}

bool RetroCore::load_state(const PackedByteArray &data) {
	if (!game_loaded || data.is_empty())
		return false;
	return f_unserialize(data.ptr(), (size_t)data.size());
}

void RetroCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_core", "path"), &RetroCore::load_core);
	ClassDB::bind_method(D_METHOD("load_game", "path"), &RetroCore::load_game);
	ClassDB::bind_method(D_METHOD("unload"), &RetroCore::unload);
	ClassDB::bind_method(D_METHOD("is_running"), &RetroCore::is_running);
	ClassDB::bind_method(D_METHOD("run"), &RetroCore::run);
	ClassDB::bind_method(D_METHOD("reset"), &RetroCore::reset);
	ClassDB::bind_method(D_METHOD("get_frame"), &RetroCore::get_frame);
	ClassDB::bind_method(D_METHOD("get_frame_serial"), &RetroCore::get_frame_serial);
	ClassDB::bind_method(D_METHOD("take_audio"), &RetroCore::take_audio);
	ClassDB::bind_method(D_METHOD("set_button", "port", "id", "down"), &RetroCore::set_button);
	ClassDB::bind_method(D_METHOD("clear_buttons"), &RetroCore::clear_buttons);
	ClassDB::bind_method(D_METHOD("get_fps"), &RetroCore::get_fps);
	ClassDB::bind_method(D_METHOD("get_sample_rate"), &RetroCore::get_sample_rate);
	ClassDB::bind_method(D_METHOD("get_aspect"), &RetroCore::get_aspect);
	ClassDB::bind_method(D_METHOD("get_core_name"), &RetroCore::get_core_name);
	ClassDB::bind_method(D_METHOD("get_last_error"), &RetroCore::get_last_error);
	ClassDB::bind_method(D_METHOD("set_dirs", "system_dir", "save_dir"), &RetroCore::set_dirs);
	ClassDB::bind_method(D_METHOD("save_state"), &RetroCore::save_state);
	ClassDB::bind_method(D_METHOD("load_state", "data"), &RetroCore::load_state);
}
