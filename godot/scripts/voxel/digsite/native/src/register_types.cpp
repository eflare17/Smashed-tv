// The Dig Site's GDExtension entry point: registers DigSiteGrid. Owned by the voxel session.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "dig_site_grid.h"

using namespace godot;

static void initialize_dig_site_sim(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE)
		return;
	GDREGISTER_CLASS(DigSiteGrid);
}

static void uninitialize_dig_site_sim(ModuleInitializationLevel level) {}

extern "C" {
GDExtensionBool GDE_EXPORT dig_site_sim_init(GDExtensionInterfaceGetProcAddress get_proc, const GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
	GDExtensionBinding::InitObject obj(get_proc, library, init);
	obj.register_initializer(initialize_dig_site_sim);
	obj.register_terminator(uninitialize_dig_site_sim);
	obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return obj.init();
}
}
