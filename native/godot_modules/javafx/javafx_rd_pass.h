#pragma once

#include "core/io/image.h"
#include "core/math/color.h"
#include "core/math/rect2.h"
#include "core/math/rect2i.h"
#include "core/math/vector2i.h"
#include "core/math/vector3.h"
#include "core/math/transform_2d.h"
#include "core/templates/hash_map.h"
#include "core/templates/rid.h"
#include "core/templates/vector.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "javafx_shader_translate.h"

// Production RD-direct offscreen pass (RD-direct backend plan, P3).
// JavaFXRenderTarget delegates its lifecycle here when GODOT_JFX_RD_DIRECT=1:
// the per-pass viewport render cycle becomes recorded draws flushed as one
// RenderingDevice render pass on the render thread. Caches mirror the
// viewport path's economics: pipelines per translated shader, vertex buffers
// per geometry content, uniform sets per parameter/texture identity, uniform
// buffers per constant bytes.
class JavaFXRenderTarget;

namespace godot_javafx::rd_direct {

// Frees the module-lifetime shared sampler at engine teardown.
void release_shared_sampler();
// Drops identity-cache entries of a disposed mesh from every live pass;
// mesh addresses get reused, and a stale entry would draw old geometry.
void purge_identity_caches(const void *p_mesh);
// Releases every live OffscreenPass at engine teardown; a backstop for
// targets held past the last FIFO drain by Java-side texture pooling.
void release_all_passes();
// Clears shared cached pipeline ownership at engine teardown.
void release_shared_pipelines();
uint64_t shared_pipeline_cache_size();
// Prints GODOT_JFX_RD_PROFILE sub-site totals once at teardown.
void print_rd_profile();
bool rd_profile_enabled();
// Sub-site timing sinks for callers outside this TU (GODOT_JFX_RD_PROFILE).
void rd_profile_sink(uint32_t p_site, uint64_t p_us);
void rd_profile_print_sinks();

// A translated+compiled canvas source. Pipelines depend only on the source
// and the (process-wide identical) RGBA8 framebuffer and vertex formats, so
// entries are shared by every OffscreenPass; per-scene target recreation
// with a per-instance cache recompiled ~100 shaders per scene switch.
class PipelineLifetime : public RefCounted {
public:
	RID pipeline, shader;
	~PipelineLifetime();
};

struct PipelineEntry {
	Ref<PipelineLifetime> lifetime;
	String source;
	RID pipeline;
	RID shader;
	RdShaderSources layout;
	bool uses_screen = false;
};

class OffscreenPass : public RefCounted {
public:
	OffscreenPass();
	~OffscreenPass();
	struct Stats {
		uint64_t passes = 0, draws = 0;
		uint64_t pipelines_created = 0, vertex_buffers_created = 0;
		uint64_t uniform_sets_created = 0, uniform_buffers_created = 0;
	};

	bool initialize(const Size2i &p_size);
	void begin_pass(bool p_clear);
	void add_rectangle(const Rect2 &p_rect, const Color &p_premultiplied);
	void copy_target(RID p_source_texture, const Rect2 &p_rect);
	void draw_quads(const Vector<float> &p_vertices, const Vector<uint8_t> &p_colors, const String &p_shader,
			const Dictionary &p_parameters, bool p_clip, const Rect2i &p_rect, RID p_texture,
			const Transform2D &p_transform, float p_modulate, const void *p_identity_key = nullptr);
	void end_pass();
	// Renders every recorded draw as one render pass on the render thread.
	// With batching (default) flush() only appends to a pending batch; the
	// passes render together in one render-thread submission when the host
	// tick closes (commit_batches) or a consumer needs the content.
	void flush();
	// Submits every pending pass as one render-thread job plus one sync.
	// No-op when nothing is pending; safe from the main thread only.
	static void commit_batches();
	static uint64_t batch_commit_count();
	static bool has_pending_batches();
	void finish_pass();
	void clear_pass();
	RID get_texture() const { return bridge_texture; }
	bool is_valid() const { return rd_texture.is_valid(); }
	const Stats &get_stats() const { return stats; }
	// Immediate full-target readback (RGBA8 image); the ledger bridge is a
	// shared RD view whose texture_2d_get blit-readback is not equivalent,
	// so the raw device texture is read on the render thread instead.
	Ref<Image> readback();
	void release();
	// Drops the identity entry of a disposed mesh (its address may be reused).
	void purge_identity(const void *p_mesh) { identity_vertex_cache.erase(p_mesh); }

private:
	struct RecordedDraw {
		Ref<PipelineLifetime> pipeline_lifetime;
		RID pipeline, uniform_set, vertex_array, index_array;
		uint32_t index_count = 0;
		Vector<uint8_t> push;
		bool scissor = false;
		Rect2i scissor_rect;
		bool uses_screen = false;
	};
	struct BufferEntry {
		RID buffer;
		Vector<uint8_t> bytes; // COW-owned content, not just its hash.
	};
	struct VertexArrayEntry {
		RID array, buffer;
		uint32_t count = 0;
	};
	struct UniformEntry {
		RID uniform_set, pipeline, texture;
		RID value_buffer;
		bool provisional = false; // A missing texture view used the white fallback.
		Dictionary params;
		Vector<RID> textures; // Sampled RS textures for liveness revalidation.
	};
	struct FlushList {
		RID framebuffer;
		bool clear = false;
		bool snapshot = false;
		RID snapshot_source, snapshot_dest;
		Vector3 snapshot_size;
		// Share the immutable recorded array until the render job completes.
		// One record owns every argument; parallel arrays cannot drift apart.
		Vector<RecordedDraw> draws;
	};
	static void render_flush_job();
	static Vector<FlushList> batch_pending; // accumulated by flush(), main thread only
	static Vector<RID> garbage_staging; // handed to the in-flight job
	static Vector<uint8_t> garbage_kinds_staging;
	static Vector<FlushList> batch_job; // handed to the in-flight render job; reused after its sync
	static uint64_t batch_commits;
	static bool batching_disabled(); // GODOT_JFX_RD_BATCH=0 keeps per-pass submission

	// Global cache lookup (compiles on miss); false only when the source
	// fails to translate/compile.
	static bool pipeline_for(const String &p_source, RID p_framebuffer, PipelineEntry &r_entry);
	RID acquire_vertex_buffer(const Vector<uint8_t> &p_bytes, uint64_t p_content_key, bool p_immutable);
	// Evicts the content buffer cache together with its arrays and identity
	// refs; dropped RIDs retire at the next commit (process-global garbage).
	void evict_vertex_caches();
	// flush() body without the closed-pass guard, used to stage the open
	// pass's recorded draws ahead of a cache eviction.
	void flush_internal();
	void flush_partial_if_recording();
	RID acquire_vertex_array(RID p_vertex_buffer, uint32_t p_vertex_count);
	RID acquire_index_array(uint32_t p_index_count);
	RID acquire_uniform_set(const PipelineEntry &entry, const Dictionary &p_parameters, RID p_texture);
	RID acquire_uniform_buffer(const Vector<uint8_t> &p_bytes);
	static void pack_value_bytes(Vector<uint8_t> &r_bytes, const RdShaderSources &p_layout, const Dictionary &p_parameters);
	void build_push_constant(Vector<uint8_t> &r_push, const RdShaderSources &p_layout,
			const Transform2D &p_transform, float p_modulate) const;
	void ensure_index_buffer();

	RID rd_texture, framebuffer, bridge_texture, snapshot_texture;
	RID index_buffer;
	// Mutable vertex buffers for changing content (uploaded batches): reused
	// via buffer_update instead of a device allocation per frame. Never
	// entered into the content cache, so no aliasing with cached entries. A
	// slot is rewritten only after an observed commit drained the batch that
	// last used it (epoch bookkeeping).
	Vector<RID> vertex_ring;
	Vector<uint32_t> vertex_ring_sizes;
	Vector<uint64_t> vertex_ring_epochs;
	uint64_t vertex_ring_epoch = 1;
	HashMap<uint64_t, BufferEntry> vertex_buffer_cache;
	// Immutable-geometry identity keys (cached mesh pointers): skip the
	// interleave conversion and content hash entirely on repeat draws.
	HashMap<const void *, RID> identity_vertex_cache;
	HashMap<uint64_t, VertexArrayEntry> vertex_array_cache;
	HashMap<uint64_t, RID> index_array_cache;

	HashMap<uint64_t, UniformEntry> uniform_set_cache;
	void retire_uniform_sets_for(RID p_buffer);
	HashMap<uint64_t, BufferEntry> uniform_buffer_cache;
	Vector<RecordedDraw> recorded;
	Size2i size;
	bool pass_open = false;
	bool clear_pending = true;
	bool initialized_contents = false;
	Stats stats;
};

} // namespace godot_javafx::rd_direct
