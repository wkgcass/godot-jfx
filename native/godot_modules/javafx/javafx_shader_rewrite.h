#pragma once

#include "core/string/string_name.h"
#include "core/string/ustring.h"
#include "core/templates/vector.h"

namespace godot_javafx {

// Rewrites value-typed uniforms of a generated canvas shader into per-instance
// uniforms for the render-target draw path and reports their names. Samplers
// stay material-level (instance uniforms cannot sample), and the shared-item
// immediate surface path keeps compiling the original source, so per-draw
// state stays expressible there. Instance uniform slots are limited (16
// vec4 indices per instance), so sources with more value uniforms than that
// are returned unchanged and report an empty list, leaving every constant on
// the material path. The memo keyed by source keeps name lists identical for
// every compile of the same shader text, within 256 entries / 4 MiB payload.
String rewrite_instance_uniforms(const String &p_source, Vector<StringName> &r_names);

// COW-owned list, safe across eviction; empty when the source was not rewritten.
Vector<StringName> instance_uniform_names(const String &p_source);

uint64_t instance_uniform_cache_size();
uint64_t instance_uniform_cache_bytes();
void clear_instance_uniform_cache();

} // namespace godot_javafx
