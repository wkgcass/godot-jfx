#pragma once

#include "core/object/ref_counted.h"
#include "core/math/rect2.h"
#include "core/math/color.h"
#include "core/templates/rid.h"
#include "core/templates/vector.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/list.h"
#include <utility>
#include <memory>
#include "scene/resources/mesh.h"
#include "prism_mesh.h"
#include "javafx_shader_rewrite.h"

// GPU-only offscreen allocation used by the Prism render-target bridge.
// References to sampled targets keep their borrowed viewport textures alive.
class JavaFXRenderTarget : public RefCounted {
	GDCLASS(JavaFXRenderTarget, RefCounted);
	RID viewport, canvas, commands, shader, material;
	// Borrowed from the viewport.
	RID viewport_texture;
	Size2i size;
	bool pass_open = false;
	bool initialized_contents = false;
	Vector<Ref<JavaFXRenderTarget>> sources;
	Vector<RID> draw_resources;
	// One canvas item per draw slot, kept alive across passes. A translating
	// parent only changes slot transforms, so unchanged slots need nothing but
	// a draw-index refresh instead of free/create/re-record every pass.
	struct DrawSlot {
		RID item, mesh, material, texture, shader;
		Ref<ArrayMesh> mesh_owner; // Recorded canvas draws must outlive cache eviction.
		HashMap<StringName, Variant> instance_values;
		bool clip = false;
		Rect2i rect;
		Transform2D transform;
		float modulate = 1.0f;
		bool visible = false;
		bool matches(RID p_mesh, RID p_material, RID p_texture, bool p_clip, const Rect2i &p_rect) const {
			return mesh == p_mesh && material == p_material && texture == p_texture && clip == p_clip && rect == p_rect;
		}
	};
	Vector<DrawSlot> slots;
	int next_draw_slot = 0; // Mesh slots only; draw_index also counts copies.
	// Immutable (shader, parameters) pairs repeat every pass; their materials
	// are shared instead of being recreated per batch. RID-bearing parameter
	// sets are cached too; their entries record the referenced RIDs so a hit
	// can revalidate them against the live-sampler set (RID values never
	// recycle; misses retire dead entries without waiting for capacity). Overflow entries
	// and pass-owned shaders stay in draw_resources with pass lifetime.
	// Full identity is stored and compared on every hit: the 64-bit hash key
	// only buckets entries, it never proves equality.
	struct MaterialEntry { RID material; RID shader; Dictionary params; Vector<RID> rids; };
	HashMap<uint64_t, MaterialEntry> material_cache;
	List<uint64_t> material_cache_order;
	// Main-thread targets share one bounded geometry memo. Draw slots own
	// their meshes independently, so cache eviction cannot invalidate a draw.
	std::shared_ptr<PrismMeshCache> mesh_cache;
	// Diagnostic mode only (GODOT_JFX_MESH_CACHE=0): per-pass mesh retention.
	Vector<Ref<ArrayMesh>> uncached_meshes;
	HashMap<String, RID> shader_cache;
	uint64_t shader_creations = 0;
	uint64_t retained_draws = 0;
	int draw_index = 0;
	RID create_draw_item(RID p_material);
	RID acquire_material(RID p_shader, const Dictionary &p_parameters, bool p_persistent_shader);
	void hide_unused_slots();
	void free_slots();
	void clear_draws();
	bool depends_on(const JavaFXRenderTarget *p_target) const;
protected:
	static void _bind_methods();
public:
	// RIDs currently alive as material sampler parameters, maintained by the
	// surface and targets at every free/retire site. Material-cache hits with
	// RID parameters revalidate against it.
	static HashSet<RID> live_sampler_rids;
	static bool sampler_alive(const RID &p_rid) { return live_sampler_rids.has(p_rid); }
	bool initialize(const Size2i &p_size);
	void begin_pass(bool p_clear);
	void copy_lcd_background(const Rect2i &p_rect);
	void copy_target(const Ref<JavaFXRenderTarget> &p_source, const Rect2 &p_rect);
	void end_pass();
	uint64_t draw_offscreen_pass();
	void finish_pass();
	void retire_sampler(RID p_texture);
	void clear_pass();
	void draw_prism_quads(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors,
		const String &p_shader, const Dictionary &p_parameters, bool p_clip, const Rect2i &p_rect, RID p_texture = RID(),
		const Transform2D &p_transform = Transform2D(), float p_modulate = 1.0f);
	// Geometry-deduplicated draw: a host-resident mesh rides the same slot
	// machinery without decoding or hashing its vertices again. The instance
	// parameter map carries per-draw constants that ride item instance data
	// instead of material uniforms; null means none.
	void draw_prism_mesh_with_instances(const Ref<ArrayMesh> &p_mesh, const String &p_shader, const Dictionary &p_parameters,
		bool p_clip, const Rect2i &p_rect, RID p_texture, const Transform2D &p_transform,
		float p_modulate, const HashMap<StringName, Variant> *p_instance_params);
	void draw_prism_quads_with_instances(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors,
		const String &p_shader, const Dictionary &p_parameters, bool p_clip, const Rect2i &p_rect, RID p_texture,
		const Transform2D &p_transform, float p_modulate, const HashMap<StringName, Variant> *p_instance_params);
	RID get_texture() const;
	Size2i get_size() const { return size; }
	bool has_initialized_contents() const { return initialized_contents; }
	int get_owned_resource_count() const;
	// Content-addressed mesh reuse is a bounded memo table, not per-pass
	// ownership; expose it separately from the hygiene count.
	int get_cached_mesh_count() const { return mesh_cache ? int(mesh_cache->size()) : 0; }
	static int get_shared_shader_count();
	int get_cached_shader_count() const { return shader_cache.size(); }
	// Persistent draw slots and shared materials are per-target ownership and
	// therefore part of the owned-resource count; exposed for its formula.
	int get_cached_material_count() const { return material_cache.size(); }
	int get_draw_slot_count() const { return slots.size(); }
	uint64_t get_retained_draw_count() const { return retained_draws; }
	int64_t get_shader_creation_count() const { return shader_creations; }
	Dictionary get_instance_uniform_cache_stats() const;
	// GPU timing (viewport_set_measure_render_time): the measured GPU time of
	// this target's most recent render, in microseconds.
	void set_measure_gpu_time(bool p_enable);
	double get_measured_gpu_time_us() const;
	// Process-wide cumulative render-thread wall time; profiling only, not GPU time.
	static Dictionary get_render_thread_profile();
	~JavaFXRenderTarget();
};
