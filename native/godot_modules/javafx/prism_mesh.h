#pragma once
#include "scene/resources/mesh.h"
#include "servers/rendering/rendering_server.h"

#include "bounded_lru_cache.h"
#include <cstring>

// Hashes select candidates, never establish content equality. Packed arrays
// retain COW snapshots while the bounded cache owns the compiled mesh.
// The 48 MiB budget counts input payload, not driver/ArrayMesh allocations.
class PrismMeshCache {
public:
	using Key = uint64_t;
private:
	struct Entry {
		Ref<ArrayMesh> mesh;
		PackedFloat32Array vertices;
		PackedByteArray colors;
	};
	godot_javafx::BoundedLruCache<Key, Entry> entries{48ULL * 1024 * 1024, 4096};
	static uint64_t fnv(const uint8_t *p_data, size_t p_size, uint64_t p_seed) {
		uint64_t h = p_seed;
		for (size_t i = 0; i < p_size; ++i) { h ^= p_data[i]; h *= 1099511628211ULL; }
		return h;
	}
public:
	static Key hash(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors) {
		const uint8_t *vertex_data = reinterpret_cast<const uint8_t *>(p_vertices.ptr());
		uint64_t hash = fnv(vertex_data, size_t(p_vertices.size()) * sizeof(float), 1469598103934665603ULL);
		return fnv(p_colors.ptr(), p_colors.size(), hash) ^ uint64_t(p_vertices.size());
	}
	Ref<ArrayMesh> get(Key p_key, const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors) {
		const Entry *entry = entries.get(p_key, [&](const Entry &p_entry) {
			return p_entry.vertices.size() == p_vertices.size() && p_entry.colors.size() == p_colors.size()
					&& (p_vertices.is_empty() || memcmp(p_entry.vertices.ptr(), p_vertices.ptr(), size_t(p_vertices.size()) * sizeof(float)) == 0)
					&& (p_colors.is_empty() || memcmp(p_entry.colors.ptr(), p_colors.ptr(), p_colors.size()) == 0);
		});
		return entry ? entry->mesh : Ref<ArrayMesh>();
	}
	void put(Key p_key, const Ref<ArrayMesh> &p_mesh, const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors) {
		entries.put(p_key, {p_mesh, p_vertices, p_colors}, size_t(p_vertices.size()) * sizeof(float) + p_colors.size());
	}
	void clear() { entries.clear(); }
	size_t size() const { return entries.size(); }
};

// Shared Prism attribute conversion for host and offscreen geometry.
inline void build_prism_mesh(Ref<ArrayMesh> &mesh, const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors) {
	int count = p_vertices.size() / 7;
	ERR_FAIL_COND(count <= 0 || count > 65536 || count % 4 || p_vertices.size() != count * 7 || p_colors.size() != count * 4);
	PackedVector2Array positions, uv;
	PackedFloat32Array custom;
	PackedColorArray colors;
	PackedInt32Array indices;
	positions.resize(count); uv.resize(count); custom.resize(count * 4); colors.resize(count); indices.resize(count / 4 * 6);
	// Acquire writable storage once: PackedArray::set performs a COW check on
	// every element, including each component of every Prism vertex.
	Vector2 *position_data = positions.ptrw(), *uv_data = uv.ptrw();
	float *custom_data = custom.ptrw();
	Color *color_data = colors.ptrw();
	int32_t *index_data = indices.ptrw();
	const float *vertex_data = p_vertices.ptr();
	const uint8_t *rgba = p_colors.ptr();
	for (int i = 0; i < count; ++i) {
		for (int j = 0; j < 7; ++j) ERR_FAIL_COND(!Math::is_finite(vertex_data[i * 7 + j]));
		ERR_FAIL_COND_MSG(vertex_data[i * 7 + 2] != 0, "3D Prism projection is not implemented.");
		position_data[i] = Vector2(vertex_data[i * 7], vertex_data[i * 7 + 1]);
		uv_data[i] = Vector2(vertex_data[i * 7 + 3], vertex_data[i * 7 + 4]);
		custom_data[i * 4] = vertex_data[i * 7 + 5]; custom_data[i * 4 + 1] = vertex_data[i * 7 + 6];
		custom_data[i * 4 + 2] = 0; custom_data[i * 4 + 3] = 0;
		color_data[i] = Color(rgba[i * 4] / 255.f, rgba[i * 4 + 1] / 255.f, rgba[i * 4 + 2] / 255.f, rgba[i * 4 + 3] / 255.f);
	}
	for (int q = 0; q < count / 4; ++q) {
		// Prism VertexBuffer order is top-left, bottom-left, top-right, bottom-right.
		const int local[] = { 0, 1, 2, 2, 1, 3 };
		for (int j = 0; j < 6; ++j) index_data[q * 6 + j] = q * 4 + local[j];
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = positions; arrays[Mesh::ARRAY_TEX_UV] = uv;
	arrays[Mesh::ARRAY_CUSTOM0] = custom; arrays[Mesh::ARRAY_COLOR] = colors; arrays[Mesh::ARRAY_INDEX] = indices;
	mesh.instantiate();
	uint64_t flags = uint64_t(RSE::ARRAY_CUSTOM_RGBA_FLOAT) << RSE::ARRAY_FORMAT_CUSTOM_BASE;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, TypedArray<Array>(), Dictionary(), flags);
	if (mesh->get_surface_count() != 1) mesh.unref();
}
