// The voxel_retro GDExtension's entry point: registers RetroCore. Owned by the voxel session.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "retro_core.h"

using namespace godot;

static void initialize_voxel_retro(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE)
		return;
	GDREGISTER_CLASS(RetroCore);
}

static void uninitialize_voxel_retro(ModuleInitializationLevel level) {}

extern "C" {
GDExtensionBool GDE_EXPORT voxel_retro_init(GDExtensionInterfaceGetProcAddress get_proc, const GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
	GDExtensionBinding::InitObject obj(get_proc, library, init);
	obj.register_initializer(initialize_voxel_retro);
	obj.register_terminator(uninitialize_voxel_retro);
	obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return obj.init();
}
}
