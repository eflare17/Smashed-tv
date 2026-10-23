// The mine_sim GDExtension's entry point: registers MineSim. Owned by the voxel session.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "mine_sim.h"

using namespace godot;

static void initialize_mine_sim(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE)
		return;
	GDREGISTER_CLASS(MineSim);
}

static void uninitialize_mine_sim(ModuleInitializationLevel level) {}

extern "C" {
GDExtensionBool GDE_EXPORT mine_sim_init(GDExtensionInterfaceGetProcAddress get_proc, const GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
	GDExtensionBinding::InitObject obj(get_proc, library, init);
	obj.register_initializer(initialize_mine_sim);
	obj.register_terminator(uninitialize_mine_sim);
	obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return obj.init();
}
}
