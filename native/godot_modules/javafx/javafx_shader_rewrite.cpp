#include "javafx_shader_rewrite.h"

#include "bounded_lru_cache.h"
#include "core/templates/hash_set.h"

namespace godot_javafx {
namespace {

constexpr int INSTANCE_UNIFORM_SLOTS = 16;

bool value_uniform_type(const String &p_type) {
	static const HashSet<String> types = [] {
		HashSet<String> set;
		for (const char *type : { "float", "int", "uint", "bool",
					"vec2", "vec3", "vec4",
					"ivec2", "ivec3", "ivec4",
					"uvec2", "uvec3", "uvec4",
					"bvec2", "bvec3", "bvec4" }) {
			set.insert(String(type));
		}
		return set;
	}();
	return types.has(p_type);
}

struct SourceHash {
	size_t operator()(const String &p_source) const { return p_source.hash(); }
};
using NameCache = BoundedLruCache<String, Vector<StringName>, SourceHash>;
NameCache &memo() {
	static NameCache cache(4 * 1024 * 1024, 256);
	return cache;
}

void remember(const String &p_source, const Vector<StringName> &p_names) {
	// Payload budget: UTF-32 source/name characters and name-vector storage.
	// Container overhead is bounded separately by the entry limit.
	size_t bytes = (size_t(p_source.length()) + 1) * sizeof(char32_t);
	bytes += size_t(p_names.size()) * sizeof(StringName);
	for (const StringName &name : p_names) bytes += (size_t(String(name).length()) + 1) * sizeof(char32_t);
	memo().put(p_source, p_names, bytes); // Oversized sources work without caching.
}

Vector<StringName> rewrite_uncached(const String &p_source, String &r_rewritten) {
	Vector<StringName> names;
	const Vector<String> lines = p_source.split("\n");
	bool changed = false;
	for (const String &line : lines) {
		const String trimmed = line.strip_edges(true, false);
		if (trimmed.begins_with("uniform ")) {
			const Vector<String> parts = trimmed.replace(";", "").split_spaces();
			// uniform <type> <name> [other tokens]
			if (parts.size() >= 3 && value_uniform_type(parts[1]) && parts[2].is_valid_identifier()) {
				names.push_back(StringName(parts[2]));
				r_rewritten += String("instance ") + line + "\n";
				changed = true;
				continue;
			}
		}
		r_rewritten += line + "\n";
	}
	// The instance buffer holds 16 vec4 indices; a shader beyond that keeps
	// every constant on the material path.
	if (names.size() > INSTANCE_UNIFORM_SLOTS) {
		names.clear();
		r_rewritten = p_source;
	}
	if (!changed && names.is_empty()) r_rewritten = p_source;
	return names;
}

} // namespace

String rewrite_instance_uniforms(const String &p_source, Vector<StringName> &r_names) {
	String rewritten;
	r_names = rewrite_uncached(p_source, rewritten);
	remember(p_source, r_names);
	return rewritten;
}

Vector<StringName> instance_uniform_names(const String &p_source) {
	if (const auto *cached = memo().get(p_source, [](const auto &) { return true; })) return *cached;
	String rewritten;
	Vector<StringName> names = rewrite_uncached(p_source, rewritten);
	remember(p_source, names);
	// Return COW ownership, not a reference invalidated by a later eviction.
	return names;
}

uint64_t instance_uniform_cache_size() { return memo().size(); }
uint64_t instance_uniform_cache_bytes() { return memo().bytes(); }
void clear_instance_uniform_cache() { memo().clear(); }

} // namespace godot_javafx
