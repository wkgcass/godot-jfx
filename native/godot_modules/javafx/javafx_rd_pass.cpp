#include "javafx_rd_pass.h"
#include "bounded_lru_cache.h"
#include "javafx_render_target.h"

#include "core/object/callable_mp.h"
#include "core/os/os.h"
#include "core/os/thread.h"
#include "core/templates/hashfuncs.h"
#include "servers/rendering/rendering_device.h"
#include "servers/rendering/rendering_server.h"
#include "servers/rendering/rendering_server_globals.h"
#include "servers/rendering/renderer_rd/storage_rd/texture_storage.h"

#include <string.h>
#include <atomic>

namespace godot_javafx::rd_direct {
namespace {

// Internal draw shaders ride the same translation pipeline as the corpus:
// solid fills and texture copies are degenerate stock shaders.
const char *SOLID_SOURCE = "shader_type canvas_item;\n"
		"render_mode unshaded, blend_premul_alpha;\n"
		"varying vec4 godot_vertex_color;\n"
		"void vertex() {\ngodot_vertex_color = COLOR;\n}\n"
		"void fragment() {\nCOLOR = godot_vertex_color;\n}";

const char *TEXTURED_SOURCE = "shader_type canvas_item;\n"
		"render_mode unshaded, blend_premul_alpha;\n"
		"varying vec2 godot_uv0;\n"
		"varying vec4 godot_vertex_color;\n"
		"void vertex() {\ngodot_uv0 = UV;\ngodot_vertex_color = COLOR;\n}\n"
		"uniform sampler2D inputTex;\n"
		"vec4 paint(vec2 texCoord) {\nreturn texture(inputTex, texCoord);\n}\n"
		"void fragment() {\nCOLOR = paint(godot_uv0) * godot_vertex_color;\n}";

uint64_t bytes_hash(const uint8_t *p_data, size_t p_size, uint64_t p_seed) {
	// Murmur3-style chunk hashing: word speed with real avalanche. A weaker
	// word-wise FNV collided heavily on structured float vertex data, so
	// distinct contents shared cache keys.
	uint64_t hash = p_seed ^ (uint64_t(p_size) * 0xC2B2AE3D27D4EB4FULL);
	size_t i = 0;
	for (; i + 8 <= p_size; i += 8) {
		uint64_t chunk;
		memcpy(&chunk, p_data + i, 8);
		chunk *= 0x87C37B91114253D5ULL;
		chunk = (chunk << 31) | (chunk >> 33);
		chunk *= 0x4CF5AD432745937FULL;
		hash ^= chunk;
		hash = (hash << 27) | (hash >> 37);
		hash = hash * 5 + 0x52DCE729D;
	}
	if (i < p_size) {
		uint64_t tail = 0;
		for (size_t r = p_size; r > i;) {
			--r;
			tail = (tail << 8) | p_data[r];
		}
		tail *= 0x87C37B91114253D5ULL;
		tail = (tail << 31) | (tail >> 33);
		tail *= 0x4CF5AD432745937FULL;
		hash ^= tail;
	}
	hash ^= hash >> 33;
	hash *= 0xFF51AFD7ED558CCDULL;
	hash ^= hash >> 33;
	hash *= 0xC4CEB9FE1A85EC53ULL;
	hash ^= hash >> 33;
	return hash;
}

// Cache-evicted RIDs from every OffscreenPass (main thread only), freed by
// the next commit after its draws have rendered. Kinds: 0 uniform set,
// 1 vertex/index array, 2 uniform buffer, 3 vertex buffer.
Vector<RID> g_cache_garbage;
Vector<uint8_t> g_cache_garbage_kinds;
// Live OffscreenPass instances (main thread only); Java-side texture pooling
// can keep scene targets referenced until process exit, when the render FIFO
// is already drained and their FreeJobs would never run.
HashSet<OffscreenPass *> g_live_passes;
bool rd_debug();

void free_garbage_pass(RenderingDevice *p_rd, const Vector<RID> &p_garbage, const Vector<uint8_t> &p_kinds) {
	// Sets first (a freed uniform buffer cascades its dependent sets; the
	// validity guard skips anything already gone), then arrays, then uniform
	// buffers, then vertex buffers (arrays die with their buffer, so buffers
	// free last).
	for (int i = 0; i < p_garbage.size(); ++i) {
		if (p_kinds[i] != 0) continue;
		if (rd_debug()) print_line("RD_RETIRE_SET set=" + itos(p_garbage[i].get_id()));
		if (p_garbage[i].is_valid() && p_rd->uniform_set_is_valid(p_garbage[i])) p_rd->free_rid(p_garbage[i]);
	}
	for (uint8_t kind = 1; kind <= 3; ++kind) {
		for (int i = 0; i < p_garbage.size(); ++i) {
			if (p_kinds[i] == kind && p_garbage[i].is_valid()) {
				p_rd->free_rid(p_garbage[i]);
			}
		}
	}
}

RID g_shared_sampler;

// Cached source/translated payload is bounded; queued draws separately own
// pipeline lifetime until their render job completes. Main thread only.
BoundedLruCache<uint64_t, PipelineEntry> g_pipeline_cache(16 * 1024 * 1024, 256);
int64_t g_vertex_format = -1; // identical for every translated pipeline

std::atomic<uint64_t> g_prof_key_hits{0}, g_prof_key_misses{0};
std::atomic<uint64_t> g_prof_src_len_total{0}, g_prof_src_len_max{0};
std::atomic<uint64_t> g_prof_pipelines{0};

// Hot pointer hits retain their COW source. Insertion clears these memos before
// LRU eviction, so they never extend ownership beyond the bounded cache.
struct SourceMemo {
	uint64_t key = 0;
	PipelineEntry entry;
};
SourceMemo g_source_memo[8];
int g_source_cursor = 0;

void clear_source_keys() {
	for (SourceMemo &memo : g_source_memo) memo = SourceMemo();
	g_source_cursor = 0;
}

void remember_pipeline(uint64_t p_key, const PipelineEntry &p_entry) {
	g_source_memo[g_source_cursor].key = p_key;
	g_source_memo[g_source_cursor].entry = p_entry;
	g_source_cursor = (g_source_cursor + 1) % 8;
}

bool rd_debug() {
	static const bool enabled = OS::get_singleton()->get_environment("GODOT_JFX_RD_DEBUG") == "1";
	return enabled;
}

// Sub-site cost attribution for the geometry apply path (main thread).
std::atomic<uint64_t> g_prof_pipeline_us{0}, g_prof_uniform_us{0}, g_prof_vertex_us{0}, g_prof_array_us{0}, g_prof_record_us{0};
std::atomic<uint64_t> g_prof_draws{0};
bool rd_profile() {
	static const bool enabled = OS::get_singleton()->get_environment("GODOT_JFX_RD_PROFILE") == "1";
	return enabled;
}

RID shared_sampler() {
	if (!g_shared_sampler.is_valid()) {
		RD::SamplerState state;
		state.mag_filter = RD::SAMPLER_FILTER_LINEAR;
		state.min_filter = RD::SAMPLER_FILTER_LINEAR;
		g_shared_sampler = RenderingServer::get_singleton()->get_rendering_device()->sampler_create(state);
	}
	return g_shared_sampler;
}

void free_failed_pipeline_shader(RID p_shader) {
	RenderingDevice::get_singleton()->free_rid(p_shader);
}


} // namespace

bool rd_profile_enabled() {
	return rd_profile();
}

namespace {
std::atomic<uint64_t> g_prof_sink_us[4] = {0, 0, 0, 0};
}

void rd_profile_sink(uint32_t p_site, uint64_t p_us) {
	if (p_site < 4) g_prof_sink_us[p_site].fetch_add(p_us, std::memory_order_relaxed);
}

void rd_profile_print_sinks() {
	if (!rd_profile() || g_prof_sink_us[0].load() + g_prof_sink_us[1].load() + g_prof_sink_us[2].load() == 0) return;
	print_line(vformat("RD_SINKS copy_us=%d merge_us=%d quads_call_us=%d",
			int64_t(g_prof_sink_us[0].load()), int64_t(g_prof_sink_us[1].load()), int64_t(g_prof_sink_us[2].load())));
}

void print_rd_profile() {
	if (!rd_profile() || g_prof_draws.load() == 0) return;
	print_line(vformat("RD_PROFILE draws=%d pipeline_us=%d uniform_us=%d vertex_us=%d array_us=%d record_us=%d key_hits=%d key_misses=%d src_avg=%d src_max=%d pipelines=%d",
			int64_t(g_prof_draws.load()), int64_t(g_prof_pipeline_us.load()), int64_t(g_prof_uniform_us.load()),
			int64_t(g_prof_vertex_us.load()), int64_t(g_prof_array_us.load()), int64_t(g_prof_record_us.load()),
			int64_t(g_prof_key_hits.load()), int64_t(g_prof_key_misses.load()),
			int64_t(g_prof_key_misses.load() ? g_prof_src_len_total.load() / g_prof_key_misses.load() : 0), int64_t(g_prof_src_len_max.load()), int64_t(g_prof_pipelines.load())));
}

void purge_identity_caches(const void *p_mesh) {
	for (OffscreenPass *pass : g_live_passes) pass->purge_identity(p_mesh);
}

void release_all_passes() {
	// Backstop for targets still referenced at engine teardown; normally the
	// host releases everything while the FIFO is alive.
	Vector<OffscreenPass *> pending;
	pending.resize(g_live_passes.size());
	int index = 0;
	for (OffscreenPass *pass : g_live_passes) pending.write[index++] = pass;
	for (int i = 0; i < pending.size(); ++i) pending[i]->release();
}

namespace {
void free_compiled_pipeline(RID p_pipeline, RID p_shader) {
	RenderingDevice *rd = RenderingDevice::get_singleton();
	if (p_pipeline.is_valid()) rd->free_rid(p_pipeline);
	if (p_shader.is_valid()) rd->free_rid(p_shader);
}
}

PipelineLifetime::~PipelineLifetime() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs != nullptr && rs->get_rendering_device() != nullptr) {
		// Own the RID values in the queued call, never a pointer to this object.
		rs->call_on_render_thread(callable_mp_static(&free_compiled_pipeline).bind(pipeline, shader));
	}
}

uint64_t shared_pipeline_cache_size() { return g_pipeline_cache.size(); }

void release_shared_pipelines() {
	clear_source_keys();
	g_pipeline_cache.clear();
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs != nullptr) rs->sync();
}

void release_shared_sampler() {
	if (!g_shared_sampler.is_valid()) return;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr || rs->get_rendering_device() == nullptr) return; // engine already tore the device down
	struct FreeSampler {
		static void run() {
			if (g_shared_sampler.is_valid()) RenderingDevice::get_singleton()->free_rid(g_shared_sampler);
			g_shared_sampler = RID();
		}
	};
	rs->call_on_render_thread(callable_mp_static(&FreeSampler::run));
	rs->sync();
}

bool OffscreenPass::initialize(const Size2i &p_size) {
	RenderingServer *rs = RenderingServer::get_singleton();
	RenderingDevice *rd = rs->get_rendering_device();
	if (rd == nullptr) return false;
	size = p_size;
	static const bool dbg = OS::get_singleton()->get_environment("GODOT_JFX_RD_DEBUG") == "1";
	if (dbg) print_line(vformat("RD_INIT %dx%d", p_size.x, p_size.y));
	RD::TextureFormat format;
	format.format = RD::DATA_FORMAT_R8G8B8A8_UNORM;
	format.width = size.x;
	format.height = size.y;
	format.texture_type = RD::TEXTURE_TYPE_2D;
	format.array_layers = 1;
	format.mipmaps = 1;
	format.usage_bits = RD::TEXTURE_USAGE_SAMPLING_BIT | RD::TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
			RD::TEXTURE_USAGE_CAN_COPY_FROM_BIT | RD::TEXTURE_USAGE_CAN_COPY_TO_BIT;
	rd_texture = rd->texture_create(format, RD::TextureView());
	ERR_FAIL_COND_V_MSG(!rd_texture.is_valid(), false, "Cannot allocate RD target texture.");
	Vector<RID> attachments;
	attachments.push_back(rd_texture);
	framebuffer = rd->framebuffer_create(attachments);
	ERR_FAIL_COND_V_MSG(!framebuffer.is_valid(), false, "Cannot allocate RD target framebuffer.");
	snapshot_texture = rd->texture_create(format, RD::TextureView());
	ERR_FAIL_COND_V_MSG(!snapshot_texture.is_valid(), false, "Cannot allocate RD screen snapshot texture.");
	// The ledger bridge allocates synchronously (consumers need a valid RID
	// immediately) and initializes on the render thread, mirroring the
	// viewport path's async proxy texture.
	bridge_texture = RSG::texture_storage->texture_allocate();
	ERR_FAIL_COND_V_MSG(!bridge_texture.is_valid(), false, "Cannot allocate RD target bridge texture.");
	struct BridgeInit {
		static void init(RID p_bridge, RID p_rd_texture) {
			RSG::texture_storage->texture_rd_initialize(p_bridge, p_rd_texture, RSE::TEXTURE_LAYERED_2D_ARRAY);
		}
	};
	rs->call_on_render_thread(callable_mp_static(&BridgeInit::init).bind(bridge_texture, rd_texture));
	return true;
}

void OffscreenPass::begin_pass(bool p_clear) {
	pass_open = true;
	clear_pending = p_clear || !initialized_contents;
	recorded.clear();
}

void OffscreenPass::add_rectangle(const Rect2 &p_rect, const Color &p_premultiplied) {
	ERR_FAIL_COND(!pass_open);
	Vector<float> vertices;
	Vector<uint8_t> colors;
	const float x0 = p_rect.position.x, y0 = p_rect.position.y;
	const float x1 = p_rect.position.x + p_rect.size.x, y1 = p_rect.position.y + p_rect.size.y;
	const float quad[4][4] = { { x0, y0, 0, 0 }, { x0, y1, 0, 1 }, { x1, y0, 1, 0 }, { x1, y1, 1, 1 } };
	for (int i = 0; i < 4; ++i) {
		vertices.push_back(quad[i][0]);
		vertices.push_back(quad[i][1]);
		vertices.push_back(0); // Prism position includes z before the two UV pairs.
		vertices.push_back(quad[i][2]);
		vertices.push_back(quad[i][3]);
		vertices.push_back(quad[i][2]);
		vertices.push_back(quad[i][3]);
	}
	const uint8_t rgba[4] = { uint8_t(CLAMP(int(p_premultiplied.r * 255.0f), 0, 255)), uint8_t(CLAMP(int(p_premultiplied.g * 255.0f), 0, 255)),
		uint8_t(CLAMP(int(p_premultiplied.b * 255.0f), 0, 255)), uint8_t(CLAMP(int(p_premultiplied.a * 255.0f), 0, 255)) };
	for (int i = 0; i < 16; ++i) colors.push_back(rgba[i & 3]);
	Dictionary no_parameters;
	draw_quads(vertices, colors, SOLID_SOURCE, no_parameters, false, Rect2i(), RID(), Transform2D(), 1.0f);
}

void OffscreenPass::copy_target(RID p_source_texture, const Rect2 &p_rect) {
	ERR_FAIL_COND(!pass_open);
	Vector<float> vertices;
	Vector<uint8_t> colors;
	const float x0 = p_rect.position.x, y0 = p_rect.position.y;
	const float x1 = p_rect.position.x + p_rect.size.x, y1 = p_rect.position.y + p_rect.size.y;
	const float quad[4][4] = { { x0, y0, 0, 0 }, { x0, y1, 0, 1 }, { x1, y0, 1, 0 }, { x1, y1, 1, 1 } };
	for (int i = 0; i < 4; ++i) {
		vertices.push_back(quad[i][0]);
		vertices.push_back(quad[i][1]);
		vertices.push_back(0);
		vertices.push_back(quad[i][2]);
		vertices.push_back(quad[i][3]);
		vertices.push_back(quad[i][2]);
		vertices.push_back(quad[i][3]);
	}
	for (int i = 0; i < 16; ++i) colors.push_back(255);
	Dictionary parameters;
	parameters["inputTex"] = p_source_texture;
	draw_quads(vertices, colors, TEXTURED_SOURCE, parameters, false, Rect2i(), p_source_texture, Transform2D(), 1.0f);
}

void OffscreenPass::draw_quads(const Vector<float> &p_vertices, const Vector<uint8_t> &p_colors, const String &p_shader,
		const Dictionary &p_parameters, bool p_clip, const Rect2i &p_rect, RID p_texture,
		const Transform2D &p_transform, float p_modulate, const void *p_identity_key) {
	ERR_FAIL_COND(!pass_open);
	const uint64_t prof_head = rd_profile() ? OS::get_singleton()->get_ticks_usec() : 0;
	PipelineEntry entry;
	if (!pipeline_for(p_shader, framebuffer, entry)) {
		ERR_PRINT("RD-direct draw dropped: pipeline unavailable for [" + p_shader.substr(0, 60) + "]");
		return;
	}
	if (rd_profile()) g_prof_pipeline_us.fetch_add(OS::get_singleton()->get_ticks_usec() - prof_head, std::memory_order_relaxed);
	const int count = p_vertices.size() / 7;
	ERR_FAIL_COND(count <= 0 || count % 4 || (int)p_colors.size() != count * 4);
	ensure_index_buffer();
	// Identity-cached geometry (an immutable referenced batch) skips the
	// interleave conversion and content hash; the viewport path rides mesh
	// RIDs the same way, and per-batch conversion otherwise dominates
	// drag frames.
	const uint64_t prof_start = rd_profile() ? OS::get_singleton()->get_ticks_usec() : 0;
	uint64_t prof_mark = prof_start;
	if (p_identity_key != nullptr) {
		if (const RID *cached = identity_vertex_cache.getptr(p_identity_key)) {
			RecordedDraw draw;
			draw.pipeline_lifetime = entry.lifetime;
			draw.pipeline = entry.pipeline;
			draw.uniform_set = acquire_uniform_set(entry, p_parameters, p_texture);
			ERR_FAIL_COND_MSG(!draw.uniform_set.is_valid() && (!entry.layout.sampler_names.is_empty() || entry.layout.value_buffer_bytes > 0), "RD-direct draw rejected: required uniform binding unavailable.");
			draw.vertex_array = acquire_vertex_array(*cached, count);
			draw.index_count = (count / 4) * 6;
			draw.index_array = acquire_index_array(draw.index_count);
			build_push_constant(draw.push, entry.layout, p_transform, p_modulate);
			draw.scissor = p_clip;
			draw.scissor_rect = p_rect;
			draw.uses_screen = entry.uses_screen;
			recorded.push_back(draw);
			++stats.draws;
			if (rd_profile()) {
				const uint64_t now = OS::get_singleton()->get_ticks_usec();
				g_prof_draws.fetch_add(1, std::memory_order_relaxed);
				g_prof_uniform_us.fetch_add(now - prof_mark, std::memory_order_relaxed);
				g_prof_array_us.fetch_add(0, std::memory_order_relaxed);
				g_prof_record_us.fetch_add(0, std::memory_order_relaxed);
			}
			return;
		}
	}
	// Interleaved RD layout: pos.xy, uv0.xy, uv1.xy floats + RGBA8 color.
	Vector<uint8_t> vertex_bytes;
	vertex_bytes.resize(count * 28);
	// Acquire COW writable storage once, then pack without typed aliasing
	// into the byte vector. No input pointer survives this conversion.
	uint8_t *packed = vertex_bytes.ptrw();
	const float *vertices = p_vertices.ptr();
	const uint8_t *colors = p_colors.ptr();
	for (int i = 0; i < count; ++i) {
		const float *src = vertices + i * 7;
		uint8_t *dst = packed + i * 28;
		memcpy(dst, src, 2 * sizeof(float)); // Position xy; z is not in the 2D layout.
		memcpy(dst + 8, src + 3, 4 * sizeof(float)); // UV0 and UV1.
		memcpy(dst + 24, colors + i * 4, 4);
	}
	RecordedDraw draw;
	draw.pipeline_lifetime = entry.lifetime;
	draw.pipeline = entry.pipeline;
	if (rd_profile()) prof_mark = OS::get_singleton()->get_ticks_usec();
	draw.uniform_set = acquire_uniform_set(entry, p_parameters, p_texture);
	ERR_FAIL_COND_MSG(!draw.uniform_set.is_valid() && (!entry.layout.sampler_names.is_empty() || entry.layout.value_buffer_bytes > 0), "RD-direct draw rejected: required uniform binding unavailable.");
	if (rd_profile()) {
		const uint64_t now = OS::get_singleton()->get_ticks_usec();
		g_prof_uniform_us.fetch_add(now - prof_mark, std::memory_order_relaxed);
		prof_mark = now;
	}
	const RID vertex_buffer = acquire_vertex_buffer(vertex_bytes, bytes_hash(vertex_bytes.ptr(), vertex_bytes.size(), 1469598103934665603ULL), p_identity_key != nullptr);
	if (rd_profile()) {
		const uint64_t now = OS::get_singleton()->get_ticks_usec();
		g_prof_vertex_us.fetch_add(now - prof_mark, std::memory_order_relaxed);
		prof_mark = now;
	}
	if (p_identity_key != nullptr && vertex_buffer.is_valid()) {
		if (identity_vertex_cache.size() >= 64) identity_vertex_cache.clear();
		identity_vertex_cache.insert(p_identity_key, vertex_buffer);
	}
	draw.vertex_array = acquire_vertex_array(vertex_buffer, count);
	draw.index_count = (count / 4) * 6;
	draw.index_array = acquire_index_array(draw.index_count);
	if (rd_profile()) {
		const uint64_t now = OS::get_singleton()->get_ticks_usec();
		g_prof_array_us.fetch_add(now - prof_mark, std::memory_order_relaxed);
		prof_mark = now;
	}
	build_push_constant(draw.push, entry.layout, p_transform, p_modulate);
	draw.scissor = p_clip;
	draw.scissor_rect = p_rect;
	draw.uses_screen = entry.uses_screen;
	recorded.push_back(draw);
	++stats.draws;
	if (rd_profile()) {
		g_prof_draws.fetch_add(1, std::memory_order_relaxed);
		g_prof_record_us.fetch_add(OS::get_singleton()->get_ticks_usec() - prof_mark, std::memory_order_relaxed);
	}
}

void OffscreenPass::end_pass() {
	ERR_FAIL_COND(!pass_open);
	pass_open = false;
}

Vector<OffscreenPass::FlushList> OffscreenPass::batch_pending;
Vector<RID> OffscreenPass::garbage_staging;
Vector<uint8_t> OffscreenPass::garbage_kinds_staging;
Vector<OffscreenPass::FlushList> OffscreenPass::batch_job;
uint64_t OffscreenPass::batch_commits = 0;

bool OffscreenPass::batching_disabled() {
	static const bool disabled = OS::get_singleton()->get_environment("GODOT_JFX_RD_BATCH") == "0";
	return disabled;
}

void OffscreenPass::render_flush_job() {
	RenderingDevice *rd = RenderingDevice::get_singleton();
	for (int pass = 0; pass < batch_job.size(); ++pass) {
		const FlushList &p_list = batch_job[pass];
		bool snapshot_taken = false;
		const Color transparent(0, 0, 0, 0);
		RD::DrawListID list = rd->draw_list_begin(p_list.framebuffer,
				p_list.clear ? RD::DRAW_CLEAR_COLOR_ALL : RD::DRAW_IGNORE_ALL, VectorView<Color>(&transparent, 1), 1.0f, 0);
		for (int i = 0; i < p_list.draws.size(); ++i) {
			const RecordedDraw &draw = p_list.draws[i];
			// A set recorded earlier in the tick can die before commit when
			// the device invalidates it (an external texture's RD view was
			// swapped mid-tick and the next acquire already rebuilt a fresh
			// one). Drop the draw instead of binding a dead RID — a failed
			// bind would leave the previous draw's set bound and sample the
			// wrong texture. The next tick re-records with the live set.
			const RID &set = draw.uniform_set;
			if (set.is_valid() && !rd->uniform_set_is_valid(set)) {
				ERR_PRINT_ONCE("RD-direct draw rejected: recorded uniform binding was invalidated before submission.");
				if (rd_debug()) print_line("RD_BATCH_DEAD_SET pass=" + itos(pass) + " draw=" + itos(i) + " set=" + itos(set.get_id()));
				continue;
			}
			if (draw.uses_screen && p_list.snapshot && !snapshot_taken) {
				// End the current list so this pass's clear and preceding draws
				// reach the destination before the first screen-sampling draw.
				// A copy before draw_list_begin would sample the previous frame.
				rd->draw_list_end();
				rd->texture_copy(p_list.snapshot_source, p_list.snapshot_dest, Vector3(), Vector3(), p_list.snapshot_size, 0, 0, 0, 0);
				list = rd->draw_list_begin(p_list.framebuffer, RD::DRAW_IGNORE_ALL, VectorView<Color>(&transparent, 1), 1.0f, 0);
				snapshot_taken = true;
			}
			rd->draw_list_bind_render_pipeline(list, draw.pipeline);
			if (set.is_valid()) {
				rd->draw_list_bind_uniform_set(list, set, 0);
			}
			rd->draw_list_bind_vertex_array(list, draw.vertex_array);
			rd->draw_list_bind_index_array(list, draw.index_array);
			rd->draw_list_set_push_constant(list, draw.push.ptr(), draw.push.size());
			if (draw.scissor) rd->draw_list_enable_scissor(list, Rect2(draw.scissor_rect));
			else rd->draw_list_disable_scissor(list);
			rd->draw_list_draw(list, true);
		}
		rd->draw_list_end();
	}
	// Every pending draw has rendered; nothing references the evicted RIDs.
	free_garbage_pass(rd, garbage_staging, garbage_kinds_staging);
}

void OffscreenPass::commit_batches() {
	if (batch_pending.is_empty()) return;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr || rs->get_rendering_device() == nullptr) {
		batch_pending.clear(); // device already gone; nothing to render into
		return;
	}
	// batch_job is static and shared with the render thread; the trailing
	// sync completes the previous job before this assignment reuses it.
	batch_job = batch_pending;
	batch_pending.clear();
	garbage_staging = g_cache_garbage;
	garbage_kinds_staging = g_cache_garbage_kinds;
	g_cache_garbage.clear();
	g_cache_garbage_kinds.clear();
	rs->call_on_render_thread(callable_mp_static(&OffscreenPass::render_flush_job));
	rs->sync();
	batch_job.clear();
	garbage_staging.clear();
	garbage_kinds_staging.clear();
	++batch_commits;
}

bool OffscreenPass::has_pending_batches() {
	return !batch_pending.is_empty();
}

uint64_t OffscreenPass::batch_commit_count() {
	return batch_commits;
}

void OffscreenPass::flush_partial_if_recording() {
	// Cache eviction must not free RIDs that the open pass still references
	// in `recorded`. Stage those draws into the pending batch first — the
	// batch renders entries to the same framebuffer in order — and clear
	// `recorded` so the pass's later flush does not stage them twice (the
	// duplicate second staging was the dead-array bind in earlier attempts).
	if (pass_open && !recorded.is_empty()) {
		flush_internal();
		recorded.clear();
	}
}

void OffscreenPass::flush() {
	ERR_FAIL_COND(pass_open);
	flush_internal();
}

namespace {
float debug_push_float(const Vector<uint8_t> &p_bytes, size_t p_index) {
	const size_t offset = p_index * sizeof(float);
	if (offset + sizeof(float) > size_t(p_bytes.size())) return -1.0f;
	float value;
	memcpy(&value, p_bytes.ptr() + offset, sizeof(value));
	return value;
}
} // namespace

void OffscreenPass::flush_internal() {
	FlushList list;
	if (recorded.is_empty()) {
		if (!clear_pending) return;
		list.framebuffer = framebuffer;
		list.clear = true;
	} else {
		list.framebuffer = framebuffer;
		list.clear = clear_pending;
		list.draws = recorded; // COW share; no per-field allocation or copy.
		bool snapshot = false;
		for (const RecordedDraw &draw : recorded) {
			if (draw.uses_screen) {
				snapshot = true;
				break;
			}
		}
		if (snapshot) {
			// Snapshot at the first screen-sampling draw, after this
			// pass clears and any preceding geometry has rendered.
			list.snapshot = true;
			list.snapshot_source = rd_texture;
			list.snapshot_dest = snapshot_texture;
			list.snapshot_size = Vector3(float(size.x), float(size.y), 1);
		}
	}
	static const bool debug = OS::get_singleton()->get_environment("GODOT_JFX_RD_DEBUG") == "1";
	if (debug) {
		print_line(String("RD_FLUSH draws=") + itos(recorded.size()) + " clear=" + itos(int(clear_pending)) +
				" passes=" + itos(stats.passes) + " sets=" + itos(stats.uniform_sets_created) +
				" vbs=" + itos(stats.vertex_buffers_created) + " ubos=" + itos(stats.uniform_buffers_created) +
				" pending_batch=" + itos(batch_pending.size()));
		for (const RecordedDraw &draw : recorded) {
			print_line(vformat("  draw pipeline_ok=%d set_ok=%d va_ok=%d ia_ok=%d idx=%d scissor=%d(%d,%d %dx%d) push0=[%.2f,%.2f,%.2f] ndc=[%.3f,%.3f]",
						int(draw.pipeline.is_valid()), int(draw.uniform_set.is_valid()), int(draw.vertex_array.is_valid()),
						int(draw.index_array.is_valid()), draw.index_count, int(draw.scissor), draw.scissor_rect.position.x,
						draw.scissor_rect.position.y, draw.scissor_rect.size.x, draw.scissor_rect.size.y,
						debug_push_float(draw.push, 0), debug_push_float(draw.push, 1), debug_push_float(draw.push, 2),
						debug_push_float(draw.push, 12), debug_push_float(draw.push, 14)));
		}
	}
	batch_pending.push_back(list);
	if (batching_disabled()) {
		// Legacy per-pass submission: identical render work, one job per pass.
		commit_batches();
	}
	initialized_contents = true;
	clear_pending = false;
	++stats.passes;
}

void OffscreenPass::finish_pass() {
	recorded.clear();
}

void OffscreenPass::clear_pass() {
	ERR_FAIL_COND(!pass_open);
	recorded.clear();
	clear_pending = true;
}

bool OffscreenPass::pipeline_for(const String &p_shader_source, RID p_framebuffer, PipelineEntry &r_entry) {
	for (const SourceMemo &memo : g_source_memo) {
		if (memo.entry.lifetime.is_valid() && memo.entry.source.ptr() == p_shader_source.ptr()) {
			g_prof_key_hits.fetch_add(1, std::memory_order_relaxed);
			// Refresh LRU position without rehashing the source text.
			g_pipeline_cache.get(memo.key, [](const PipelineEntry &) { return true; });
			r_entry = memo.entry;
			return true;
		}
	}
	g_prof_key_misses.fetch_add(1, std::memory_order_relaxed);
	const uint64_t len = p_shader_source.length();
	g_prof_src_len_total.fetch_add(len, std::memory_order_relaxed);
	uint64_t prev_max = g_prof_src_len_max.load(std::memory_order_relaxed);
	while (len > prev_max && !g_prof_src_len_max.compare_exchange_weak(prev_max, len, std::memory_order_relaxed)) {}
	const uint64_t key = p_shader_source.hash();
	if (const PipelineEntry *cached = g_pipeline_cache.get(key, [&](const PipelineEntry &candidate) { return candidate.source == p_shader_source; })) {
		remember_pipeline(key, *cached);
		r_entry = *cached;
		return true;
	}
	RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
	RdShaderSources translated = godot_javafx::translate_canvas_shader(p_shader_source);
	if (!translated.ok) {
		ERR_PRINT("RD-direct translation failed: " + translated.error);
		return false;
	}
	String compile_error;
	Vector<uint8_t> vertex_spirv = rd->shader_compile_spirv_from_source(RD::SHADER_STAGE_VERTEX, translated.vertex_source, RD::SHADER_LANGUAGE_GLSL, &compile_error);
	Vector<uint8_t> fragment_spirv = rd->shader_compile_spirv_from_source(RD::SHADER_STAGE_FRAGMENT, translated.fragment_source, RD::SHADER_LANGUAGE_GLSL, &compile_error);
	if (vertex_spirv.is_empty() || fragment_spirv.is_empty()) {
		ERR_PRINT("RD-direct shader compile failed: " + compile_error);
		return false;
	}
	Vector<RD::ShaderStageSPIRVData> stages;
	stages.resize(2);
	stages.write[0].shader_stage = RD::SHADER_STAGE_VERTEX;
	stages.write[0].spirv = vertex_spirv;
	stages.write[1].shader_stage = RD::SHADER_STAGE_FRAGMENT;
	stages.write[1].spirv = fragment_spirv;
	RID shader = rd->shader_create_from_spirv(stages);
	if (!shader.is_valid()) return false;
	// Canonical vertex format shared by every translated pipeline.
	Vector<RD::VertexAttribute> attributes;
	const int stride = 28;
	for (int a = 0; a < 3; ++a) {
		RD::VertexAttribute attribute;
		attribute.binding = 0;
		attribute.location = a;
		attribute.offset = a * 8;
		attribute.format = RD::DATA_FORMAT_R32G32_SFLOAT;
		attribute.stride = stride;
		attributes.push_back(attribute);
	}
	RD::VertexAttribute color_attribute;
	color_attribute.binding = 0;
	color_attribute.location = 3;
	color_attribute.offset = 24;
	color_attribute.format = RD::DATA_FORMAT_R8G8B8A8_UNORM;
	color_attribute.stride = stride;
	attributes.push_back(color_attribute);
	if (g_vertex_format < 0) g_vertex_format = rd->vertex_format_create(attributes);
	RD::PipelineColorBlendState blend;
	RD::PipelineColorBlendState::Attachment attachment;
	// render_mode drives the blend, mirroring the canvas renderer's factor
	// tables: the corpus is premultiplied, the composite/clear family picks
	// add/mul/disabled.
	if (translated.blend_mode == RdShaderSources::BLEND_DISABLED) {
		attachment.enable_blend = false;
	} else {
		attachment.enable_blend = true;
		switch (translated.blend_mode) {
			case RdShaderSources::BLEND_ADD:
				attachment.src_color_blend_factor = RD::BLEND_FACTOR_SRC_ALPHA;
				attachment.dst_color_blend_factor = RD::BLEND_FACTOR_ONE;
				attachment.src_alpha_blend_factor = RD::BLEND_FACTOR_SRC_ALPHA;
				attachment.dst_alpha_blend_factor = RD::BLEND_FACTOR_ONE;
				break;
			case RdShaderSources::BLEND_MUL:
				attachment.src_color_blend_factor = RD::BLEND_FACTOR_DST_COLOR;
				attachment.dst_color_blend_factor = RD::BLEND_FACTOR_ZERO;
				attachment.src_alpha_blend_factor = RD::BLEND_FACTOR_DST_ALPHA;
				attachment.dst_alpha_blend_factor = RD::BLEND_FACTOR_ZERO;
				break;
			default: // premultiplied alpha
				attachment.src_color_blend_factor = RD::BLEND_FACTOR_ONE;
				attachment.dst_color_blend_factor = RD::BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
				attachment.src_alpha_blend_factor = RD::BLEND_FACTOR_ONE;
				attachment.dst_alpha_blend_factor = RD::BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
				break;
		}
	}
	blend.attachments.push_back(attachment);
	RID pipeline = rd->render_pipeline_create(shader, rd->framebuffer_get_format(p_framebuffer), g_vertex_format,
			RD::RENDER_PRIMITIVE_TRIANGLES, RD::PipelineRasterizationState(), RD::PipelineMultisampleState(),
			RD::PipelineDepthStencilState(), blend);
	if (!pipeline.is_valid()) {
		// The shader has not entered the shared cache yet. RD destruction must
		// run on the render thread, including in separate-thread mode.
		RenderingServer *rs = RenderingServer::get_singleton();
		rs->call_on_render_thread(callable_mp_static(&free_failed_pipeline_shader).bind(shader));
		rs->sync();
		ERR_PRINT("RD-direct pipeline creation failed.");
		return false;
	}
	PipelineEntry entry;
	entry.lifetime.instantiate();
	entry.lifetime->pipeline = pipeline;
	entry.lifetime->shader = shader;
	entry.source = p_shader_source;
	entry.pipeline = pipeline;
	entry.shader = shader;
	entry.layout = translated;
	entry.uses_screen = translated.screen_sampler_index >= 0;
	clear_source_keys();
	const size_t payload_bytes = (size_t(p_shader_source.length()) + size_t(translated.vertex_source.length()) +
			size_t(translated.fragment_source.length())) * sizeof(char32_t) + translated.value_defaults.size();
	if (g_pipeline_cache.put(key, entry, payload_bytes)) remember_pipeline(key, entry);
	g_prof_pipelines.fetch_add(1, std::memory_order_relaxed);
	r_entry = entry;
	return true;
}

OffscreenPass::OffscreenPass() {
	g_live_passes.insert(this);
}

OffscreenPass::~OffscreenPass() {
	release();
	g_live_passes.erase(this);
}

void OffscreenPass::evict_vertex_caches() {
	// Buffer-cache eviction: the arrays built over those buffers die with
	// them (device cascade), and the identity cache only holds references,
	// so all three drop together into the garbage list.
	flush_partial_if_recording();
	for (const KeyValue<uint64_t, VertexArrayEntry> &entry : vertex_array_cache) {
		g_cache_garbage.push_back(entry.value.array);
		g_cache_garbage_kinds.push_back(1);
	}
	vertex_array_cache.clear();
	identity_vertex_cache.clear();
	for (const KeyValue<uint64_t, BufferEntry> &entry : vertex_buffer_cache) {
		g_cache_garbage.push_back(entry.value.buffer);
		g_cache_garbage_kinds.push_back(3);
	}
	vertex_buffer_cache.clear();
}

namespace {
void update_vertex_buffer_on_render_thread(RID p_buffer, PackedByteArray p_bytes) {
	RenderingDevice::get_singleton()->buffer_update(p_buffer, 0, p_bytes.size(), p_bytes.ptr());
}

void queue_vertex_buffer_update(RID p_buffer, const Vector<uint8_t> &p_bytes) {
	// Owned bytes survive until the render FIFO consumes the update. Every
	// subsequent draw job is queued through the same server, after this update.
	// PackedByteArray shares Vector storage through COW. The bound Variant
	// keeps it alive until execution; later producer writes detach instead of
	// overwriting queued bytes. Avoid another allocation/full geometry copy.
	PackedByteArray bytes = p_bytes;
	RenderingServer::get_singleton()->call_on_render_thread(
			callable_mp_static(&update_vertex_buffer_on_render_thread).bind(p_buffer, bytes));
}
} // namespace

RID OffscreenPass::acquire_vertex_buffer(const Vector<uint8_t> &p_bytes, uint64_t p_content_key, bool p_immutable) {
	if (const BufferEntry *cached = vertex_buffer_cache.getptr(p_content_key)) {
		if (cached->bytes == p_bytes) return cached->buffer;
		// A hash collision is a miss. Retire dependent arrays and identity
		// aliases together, after staging draws that still use their buffers.
		evict_vertex_caches();
	}
	static const bool ring_disabled = OS::get_singleton()->get_environment("GODOT_JFX_RD_RING") == "0";
	if (ring_disabled || p_immutable) {
		RenderingDevice *rd_legacy = RenderingServer::get_singleton()->get_rendering_device();
		RID legacy = rd_legacy->vertex_buffer_create(p_bytes.size(), Span<uint8_t>(const_cast<uint8_t *>(p_bytes.ptr()), p_bytes.size()));
		if (legacy.is_valid()) {
			if (vertex_buffer_cache.size() >= 128) evict_vertex_caches();
			vertex_buffer_cache.insert(p_content_key, { legacy, p_bytes });
			++stats.vertex_buffers_created;
		}
		return legacy;
	}
	RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
	// Changing content (animated uploads) never dedupes, so a device
	// allocation per frame dominated drag frames. Mutable ring buffers ride
	// buffer_update instead; they stay out of the content cache so a cached
	// RID can never alias a mutated slot. Exact size match only, and only a
	// slot whose last write predates the latest observed commit — a draw
	// recorded earlier in this tick must not see its slot rewritten.
	for (int i = 0; i < vertex_ring.size(); ++i) {
		if (vertex_ring_sizes[i] != p_bytes.size()) continue;
		if (vertex_ring_epochs[i] == vertex_ring_epoch) continue; // hot: written since last drain
		queue_vertex_buffer_update(vertex_ring[i], p_bytes);
		vertex_ring_epochs.write[i] = vertex_ring_epoch;
		return vertex_ring[i];
	}
	if (!p_immutable && vertex_ring.size() >= 16 && vertex_ring_epochs.size() == vertex_ring.size()) {
		bool any_size_match = false;
		for (int i = 0; i < vertex_ring.size(); ++i) any_size_match |= vertex_ring_sizes[i] == p_bytes.size();
		if (any_size_match) {
			// Every matching slot is hot: drain the pending batch, advance
			// the epoch (all earlier writes are now retired) and rotate.
			// The open pass may still reference these buffers in recorded,
			// not batch_pending. Stage it before advancing the reuse epoch.
			flush_partial_if_recording();
			commit_batches();
			++vertex_ring_epoch;
			for (int i = 0; i < vertex_ring.size(); ++i) {
				if (vertex_ring_sizes[i] == p_bytes.size()) {
					queue_vertex_buffer_update(vertex_ring[i], p_bytes);
					vertex_ring_epochs.write[i] = vertex_ring_epoch;
					return vertex_ring[i];
				}
			}
		}
	}
	RID buffer = rd->vertex_buffer_create(p_bytes.size(), Span<uint8_t>(const_cast<uint8_t *>(p_bytes.ptr()), p_bytes.size()));
	if (buffer.is_valid()) {
		if (!p_immutable && vertex_ring.size() < 16) {
			vertex_ring.push_back(buffer);
			vertex_ring_sizes.push_back(p_bytes.size());
			vertex_ring_epochs.push_back(vertex_ring_epoch);
		} else {
			// Ring exhausted by distinct sizes; fall back to the bounded
			// content cache for the overflow.
			if (vertex_buffer_cache.size() >= 128) evict_vertex_caches();
			vertex_buffer_cache.insert(p_content_key, { buffer, p_bytes });
		}
		++stats.vertex_buffers_created;
	}
	return buffer;
}

RID OffscreenPass::acquire_vertex_array(RID p_vertex_buffer, uint32_t p_vertex_count) {
	// RID ids are 64-bit; a shift-based key silently aliases buffers whose
	// ids share low bits, binding a foreign geometry into the array.
	const uint64_t key = hash_murmur3_one_64(p_vertex_buffer.get_id()) ^ hash_murmur3_one_64(uint64_t(p_vertex_count) + 1);
	if (const VertexArrayEntry *cached = vertex_array_cache.getptr(key)) {
		if (cached->buffer == p_vertex_buffer && cached->count == p_vertex_count) return cached->array;
		flush_partial_if_recording();
		g_cache_garbage.push_back(cached->array);
		g_cache_garbage_kinds.push_back(1);
		vertex_array_cache.erase(key);
	}
	RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
	Vector<RID> sources;
	sources.push_back(p_vertex_buffer);
	RID array = rd->vertex_array_create(p_vertex_count, g_vertex_format, sources);
	if (array.is_valid()) {
		if (vertex_array_cache.size() >= 256) {
			flush_partial_if_recording();
			for (const KeyValue<uint64_t, VertexArrayEntry> &entry : vertex_array_cache) {
				g_cache_garbage.push_back(entry.value.array);
				g_cache_garbage_kinds.push_back(1);
			}
			vertex_array_cache.clear();
		}
		vertex_array_cache.insert(key, { array, p_vertex_buffer, p_vertex_count });
	}
	return array;
}

RID OffscreenPass::acquire_index_array(uint32_t p_index_count) {
	if (const RID *cached = index_array_cache.getptr(p_index_count)) return *cached;
	RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
	RID array = rd->index_array_create(index_buffer, 0, p_index_count);
	if (array.is_valid()) {
		if (index_array_cache.size() >= 256) {
			for (const KeyValue<uint64_t, RID> &entry : index_array_cache) {
				g_cache_garbage.push_back(entry.value);
				g_cache_garbage_kinds.push_back(1);
			}
			index_array_cache.clear();
		}
		index_array_cache.insert(p_index_count, array);
	}
	return array;
}

namespace {
struct UniformBuild {
	// Resolves the sampled textures' RD views and creates the uniform set on
	// the render thread (ledger reads must not race the FIFO). Inputs ride a
	// static staging slot; acquire_uniform_set blocks on the FIFO sync.
	static RID set;
	static bool provisional;
	static RID shader;
	static const RdShaderSources *layout;
	static const Dictionary *parameters;
	static RID texture, snapshot, value_buffer;
	static void build() {
		provisional = false;
		RenderingDevice *rd = RenderingDevice::get_singleton();
		const RdShaderSources *p_layout = layout;
		const Dictionary *p_parameters = parameters;
		Vector<RD::Uniform> uniforms;
		for (int i = 0; i < p_layout->sampler_names.size(); ++i) {
			RID sampled_rs, sampled_rd;
			if (i == p_layout->screen_sampler_index) {
				sampled_rd = snapshot; // already a device texture
			} else {
				const Variant *value = p_parameters->getptr(String(p_layout->sampler_names[i]));
				if (value != nullptr && value->get_type() == Variant::RID) sampled_rs = *value;
				else sampled_rs = texture;
			}
			RID view = sampled_rd.is_valid() ? sampled_rd : RSG::texture_storage->texture_get_rd_texture(sampled_rs);
			if (rd_debug()) print_line("RD_SET_SAMPLER index=" + itos(i) + " engine=" + itos(sampled_rs.get_id()) + " view=" + itos(view.get_id()));
			if (rd_debug() && sampled_rs.is_valid()) {
				// External engine textures can have their RD view replaced
				// while the engine RID survives; every swap frees the sets
				// that referenced the previous view.
				static HashMap<RID, RID> last_views;
				const RID *previous = last_views.getptr(sampled_rs);
				if (previous != nullptr && *previous != view) {
					print_line("RD_VIEW_CHANGED engine=" + itos(sampled_rs.get_id()) + " view " + itos(previous->get_id()) + " -> " + itos(view.get_id()));
				}
				last_views[sampled_rs] = view;
			}
			if (!view.is_valid()) {
				provisional = true;
				// Sampled textures whose device view is not resolvable yet
				// (GodotView scene textures during bring-up) bind the engine
				// white default instead of failing the whole draw; once the
				// texture is ready the next pass rebuilds with the real view.
				ERR_PRINT_ONCE("RD-direct: sampled texture has no device view; binding white default.");
				view = RendererRD::TextureStorage::get_singleton()->texture_rd_get_default(RendererRD::TextureStorage::DEFAULT_RD_TEXTURE_WHITE);
			}
			RD::Uniform uniform;
			uniform.uniform_type = RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;
			uniform.binding = i;
			uniform.append_id(shared_sampler());
			uniform.append_id(view);
			uniforms.push_back(uniform);
		}
		if (p_layout->value_buffer_bytes > 0 && value_buffer.is_valid()) {
			RD::Uniform uniform;
			uniform.uniform_type = RD::UNIFORM_TYPE_UNIFORM_BUFFER;
			uniform.binding = p_layout->sampler_names.size();
			uniform.append_id(value_buffer);
			uniforms.push_back(uniform);
		}
		if (uniforms.is_empty()) return; // no uniforms: leave the set invalid
		set = rd->uniform_set_create(VectorView<RD::Uniform>(uniforms.ptr(), uniforms.size()), shader, 0);
		if (rd_debug()) print_line("RD_SET_CREATED set=" + itos(set.get_id()) + " buffer=" + itos(value_buffer.get_id()) + " shader=" + itos(shader.get_id()));
	}
};
RID UniformBuild::set;
bool UniformBuild::provisional = false;
RID UniformBuild::shader;
const RdShaderSources *UniformBuild::layout = nullptr;
const Dictionary *UniformBuild::parameters = nullptr;
RID UniformBuild::texture, UniformBuild::snapshot, UniformBuild::value_buffer;
} // namespace

RID OffscreenPass::acquire_uniform_set(const PipelineEntry &entry, const Dictionary &p_parameters, RID p_texture) {
	uint64_t key = hash_murmur3_one_64(entry.pipeline.get_id()) ^ hash_murmur3_one_64(p_parameters.hash()) ^ hash_murmur3_one_64(p_texture.get_id());
	if (const UniformEntry *cached = uniform_set_cache.getptr(key)) {
		bool identical = !cached->provisional && cached->pipeline == entry.pipeline && cached->texture == p_texture && cached->params == p_parameters;
		if (identical) {
			for (const RID &rid : cached->textures) {
				if (rid.is_valid() && !JavaFXRenderTarget::sampler_alive(rid)) identical = false;
			}
		}
		if (identical) {
			// Engine-RID liveness cannot see a set the device already freed
			// through its invalidation callback (a retired RD view or value
			// buffer the ledger still counts as alive). Binding that stale
			// RID silently drops every draw it covers, so rebuild instead.
			if (!RenderingServer::get_singleton()->get_rendering_device()->uniform_set_is_valid(cached->uniform_set)) {
				if (rd_debug()) {
					String textures;
					for (const RID &rid : cached->textures) textures += itos(rid.get_id()) + " ";
					print_line("RD_STALE_SET engine_rids=[" + textures + "]");
				}
				identical = false;
			}
		}
		if (identical) return cached->uniform_set;
		// A mismatch can be a hash collision, not only device invalidation.
		// Keep ownership until queued draws finish; retirement checks validity
		// on the render thread before freeing possibly invalidated sets.
		flush_partial_if_recording();
		g_cache_garbage.push_back(cached->uniform_set);
		g_cache_garbage_kinds.push_back(0);
		uniform_set_cache.erase(key);
	}
	Vector<uint8_t> value_bytes;
	if (entry.layout.value_buffer_bytes > 0) pack_value_bytes(value_bytes, entry.layout, p_parameters);
	RID value_buffer;
	if (value_bytes.size() > 0) {
		value_buffer = acquire_uniform_buffer(value_bytes);
		if (!value_buffer.is_valid()) return RID();
	}
	RenderingServer *rs = RenderingServer::get_singleton();
	UniformBuild::set = RID();
	UniformBuild::shader = entry.shader;
	UniformBuild::layout = &entry.layout;
	UniformBuild::parameters = &p_parameters;
	UniformBuild::texture = p_texture;
	UniformBuild::snapshot = snapshot_texture;
	UniformBuild::value_buffer = value_buffer;
	rs->call_on_render_thread(callable_mp_static(&UniformBuild::build));
	rs->sync();
	RID built = UniformBuild::set;
	if (!built.is_valid()) return RID();
	UniformEntry fresh;
	fresh.uniform_set = built;
	fresh.value_buffer = value_buffer;
	fresh.provisional = UniformBuild::provisional;
	fresh.pipeline = entry.pipeline;
	fresh.texture = p_texture;
	fresh.params = p_parameters.duplicate(true);
	for (const StringName &sampler : entry.layout.sampler_names) {
		const Variant *value = p_parameters.getptr(String(sampler));
		if (value != nullptr && value->get_type() == Variant::RID) fresh.textures.push_back(*value);
	}
	if (p_texture.is_valid()) fresh.textures.push_back(p_texture);
	if (uniform_set_cache.size() >= 256) {
		flush_partial_if_recording();
		for (const KeyValue<uint64_t, UniformEntry> &entry : uniform_set_cache) {
			g_cache_garbage.push_back(entry.value.uniform_set);
			g_cache_garbage_kinds.push_back(0);
		}
		uniform_set_cache.clear();
	}
	uniform_set_cache.insert(key, fresh);
	++stats.uniform_sets_created;
	return built;
}

void OffscreenPass::retire_uniform_sets_for(RID p_buffer) {
	Vector<uint64_t> keys;
	for (const KeyValue<uint64_t, UniformEntry> &entry : uniform_set_cache) {
		if (entry.value.value_buffer == p_buffer) keys.push_back(entry.key);
	}
	for (uint64_t key : keys) {
		g_cache_garbage.push_back(uniform_set_cache[key].uniform_set);
		g_cache_garbage_kinds.push_back(0);
		uniform_set_cache.erase(key);
	}
}

RID OffscreenPass::acquire_uniform_buffer(const Vector<uint8_t> &p_bytes) {
	const uint64_t key = bytes_hash(p_bytes.ptr(), p_bytes.size(), 0x9e3779b97f4a7c15ULL);
	if (const BufferEntry *cached = uniform_buffer_cache.getptr(key)) {
		if (cached->bytes == p_bytes) return cached->buffer;
		flush_partial_if_recording();
		retire_uniform_sets_for(cached->buffer);
		g_cache_garbage.push_back(cached->buffer);
		g_cache_garbage_kinds.push_back(2);
		uniform_buffer_cache.erase(key);
	}
	RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
	RID buffer = rd->uniform_buffer_create(p_bytes.size(), Span<uint8_t>(const_cast<uint8_t *>(p_bytes.ptr()), p_bytes.size()));
	if (buffer.is_valid()) {
		if (uniform_buffer_cache.size() >= 128) {
			flush_partial_if_recording();
			for (const KeyValue<uint64_t, BufferEntry> &entry : uniform_buffer_cache) {
				retire_uniform_sets_for(entry.value.buffer);
				g_cache_garbage.push_back(entry.value.buffer);
				g_cache_garbage_kinds.push_back(2);
			}
			uniform_buffer_cache.clear();
		}
		uniform_buffer_cache.insert(key, { buffer, p_bytes });
		++stats.uniform_buffers_created;
	}
	return buffer;
}

void OffscreenPass::pack_value_bytes(Vector<uint8_t> &r_bytes, const RdShaderSources &p_layout, const Dictionary &p_parameters) {
	r_bytes.resize(p_layout.value_buffer_bytes);
	memset(r_bytes.ptrw(), 0, r_bytes.size());
	if (p_layout.value_defaults.size() == r_bytes.size()) {
		memcpy(r_bytes.ptrw(), p_layout.value_defaults.ptr(), r_bytes.size());
	}
	for (const RdValueUniform &value : p_layout.value_uniforms) {
		const Variant *variant = p_parameters.getptr(String(value.name));
		if (variant == nullptr) continue;
		for (int element = 0; element < value.count; ++element) {
			for (int w = 0; w < value.words; ++w) {
				const int index = element * value.words + w;
				float word = 0.0f;
				int32_t integer = 0;
				if (value.is_array) {
					if (variant->get_type() == Variant::PACKED_FLOAT32_ARRAY) {
						const PackedFloat32Array array = *variant;
						if (index < array.size()) word = array[index];
					} else if (variant->get_type() == Variant::PACKED_INT32_ARRAY) {
						const PackedInt32Array array = *variant;
						if (index < array.size()) integer = array[index];
					}
				} else if (value.integer) {
					switch (value.words) {
						case 1: integer = int(*variant); break;
						case 2: { const Vector2i v = *variant; integer = v[w]; } break;
						case 3: { const Vector3i v = *variant; integer = v[w]; } break;
						default: { const Vector4i v = *variant; integer = v[w]; } break;
					}
				} else {
					switch (value.words) {
						case 1: word = *variant; break;
						case 2: { const Vector2 v = *variant; word = index == 0 ? v.x : v.y; } break;
						case 3: { const Vector3 v = *variant; word = index < 3 ? v[index] : 0.0f; } break;
						default: { const Vector4 v = *variant; word = index < 4 ? v[index] : 0.0f; } break;
					}
				}
				uint32_t bits = 0;
				if (value.integer) memcpy(&bits, &integer, sizeof(bits));
				else memcpy(&bits, &word, sizeof(bits));
				memcpy(r_bytes.ptrw() + value.offset + element * value.stride + w * 4, &bits, sizeof(bits));
			}
		}
	}
}

void OffscreenPass::build_push_constant(Vector<uint8_t> &r_push, const RdShaderSources &p_layout,
		const Transform2D &p_transform, float p_modulate) const {
	r_push.resize(p_layout.push_constant_bytes);
	memset(r_push.ptrw(), 0, r_push.size());
	float *push = reinterpret_cast<float *>(r_push.ptrw());
	// Java sends x' = mxx*x + mxy*y + mxt; the columns map onto the two
	// affine header vectors.
	push[0] = p_transform.columns[0][0]; push[1] = p_transform.columns[1][0]; push[2] = p_transform.columns[2][0];
	push[4] = p_transform.columns[0][1]; push[5] = p_transform.columns[1][1]; push[6] = p_transform.columns[2][1];
	push[8] = p_modulate; push[9] = p_modulate; push[10] = p_modulate; push[11] = p_modulate;
	push[12] = 2.0f / float(size.x); push[13] = 2.0f / float(size.y); push[14] = -1.0f; push[15] = -1.0f;
	if (p_layout.push_constant_bytes >= 72) {
		push[16] = float(size.x); push[17] = float(size.y);
	}
}

void OffscreenPass::ensure_index_buffer() {
	if (index_buffer.is_valid()) return;
	RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
	const int max_quads = 16384;
	Vector<uint8_t> bytes;
	bytes.resize(max_quads * 6 * 4);
	uint32_t *indices = reinterpret_cast<uint32_t *>(bytes.ptrw());
	for (int q = 0; q < max_quads; ++q) {
		const uint32_t base = q * 4;
		const uint32_t pattern[6] = { 0, 1, 2, 2, 1, 3 };
		for (int j = 0; j < 6; ++j) indices[q * 6 + j] = base + pattern[j];
	}
	index_buffer = rd->index_buffer_create(max_quads * 6, RD::INDEX_BUFFER_FORMAT_UINT32,
			Span<uint8_t>(bytes.ptrw(), bytes.size()));
}

Ref<Image> OffscreenPass::readback() {
	ERR_FAIL_COND_V_MSG(!Thread::is_main_thread(), Ref<Image>(), "RD readback must run on the host main thread.");
	ERR_FAIL_COND_V_MSG(!rd_texture.is_valid(), Ref<Image>(), "RD readback requires a live target.");
	// A pending batch may still hold this target's latest passes; its content
	// must reach the device texture before the readback job samples it.
	commit_batches();
	RenderingServer *rs = RenderingServer::get_singleton();
	static Vector<uint8_t> staging;
	struct Job {
		static void run(RID p_texture) {
			RenderingDevice *rd = RenderingDevice::get_singleton();
			staging = rd->texture_get_data(p_texture, 0);
		}
	};
	staging.clear();
	rs->call_on_render_thread(callable_mp_static(&Job::run).bind(rd_texture));
	rs->sync();
	// Image keeps the vector through copy-on-write. Transfer ownership out of
	// shared staging after sync rather than allocate/zero/copy another frame,
	// and do not retain the last full-target readback until the next request.
	Vector<uint8_t> pixels = staging;
	staging.clear();
	ERR_FAIL_COND_V_MSG(pixels.size() != int64_t(size.x) * size.y * 4, Ref<Image>(), "RD readback returned an unexpected byte count.");
	return Image::create_from_data(size.x, size.y, false, Image::FORMAT_RGBA8, pixels);
}

void OffscreenPass::release() {
	if (rd_debug()) print_line("RD_RELEASE_TARGET engine=" + itos(bridge_texture.get_id()) + " view=" + itos(rd_texture.get_id()));
	// Pending passes must render before their resources are freed; the commit
	// job is queued ahead of the FreeJob in the same FIFO.
	commit_batches();
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) return;
	if (bridge_texture.is_valid()) rs->free_rid(bridge_texture);
	bridge_texture = RID();
	RenderingDevice *rd = rs->get_rendering_device();
	if (rd == nullptr) return;
	// Retirement order matters: uniform sets depend on their shader's
	// layout, so freeing a shader first cascade-frees its sets and a later
	// explicit free trips an invalid-ID error.
	// Arrays depend on their buffers, framebuffers on their textures, and
	// the device cascade-frees dependents first — explicit frees must follow
	// the same order or they hit already-destroyed RIDs.
	Vector<RID> retire;
	Vector<RID> uniform_sets;
	for (const KeyValue<uint64_t, UniformEntry> &entry : uniform_set_cache) uniform_sets.push_back(entry.value.uniform_set);
	for (const KeyValue<uint64_t, VertexArrayEntry> &entry : vertex_array_cache) retire.push_back(entry.value.array);
	for (const KeyValue<uint64_t, RID> &entry : index_array_cache) retire.push_back(entry.value);
	for (const KeyValue<uint64_t, BufferEntry> &entry : vertex_buffer_cache) retire.push_back(entry.value.buffer);
	// identity_vertex_cache holds references owned by vertex_buffer_cache;
	// freeing here would double-free the same RIDs.
	retire.push_back(index_buffer);
	for (const RID &ring : vertex_ring) retire.push_back(ring);
	for (const KeyValue<uint64_t, BufferEntry> &entry : uniform_buffer_cache) retire.push_back(entry.value.buffer);
	retire.push_back(framebuffer);
	retire.push_back(rd_texture);
	retire.push_back(snapshot_texture);
	static Vector<RID> g_uniform_set_staging;
	g_uniform_set_staging = uniform_sets;
	static Vector<RID> g_retire_staging;
	g_retire_staging = retire;
	static Vector<RID> g_release_garbage;
	static Vector<uint8_t> g_release_garbage_kinds;
	g_release_garbage = g_cache_garbage;
	g_release_garbage_kinds = g_cache_garbage_kinds;
	g_cache_garbage.clear();
	g_cache_garbage_kinds.clear();
	struct FreeJob {
		static void run() {
			const Vector<RID> &p_uniform_sets = g_uniform_set_staging;
			RenderingDevice *rd = RenderingDevice::get_singleton();
			free_garbage_pass(rd, g_release_garbage, g_release_garbage_kinds);
			for (const RID &rid : p_uniform_sets) {
				if (rid.is_valid() && !rd->uniform_set_is_valid(rid)) continue; // invalidated
				if (rid.is_valid()) rd->free_rid(rid);
			}
			for (const RID &rid : g_retire_staging) {
				if (rid.is_valid()) {
					rd->free_rid(rid);
				}
			}
			g_retire_staging.clear();
		}
	};
	rs->call_on_render_thread(callable_mp_static(&FreeJob::run));
	// The staging vectors are static and shared with the render thread; a
	// second release (scene switches retire targets back-to-back) would
	// overwrite them while the previous FreeJob still reads them — the
	// unsynced hand-off freed garbage IDs in separate mode. Block like flush.
	rs->sync();
	vertex_buffer_cache.clear();
	vertex_ring.clear();
	vertex_ring_sizes.clear();
	vertex_ring_epochs.clear();
	identity_vertex_cache.clear();
	vertex_array_cache.clear();
	index_array_cache.clear();
	uniform_buffer_cache.clear();
	uniform_set_cache.clear();
	recorded.clear(); // Drop pipeline owners even when the target outlives teardown.
	rd_texture = RID();
	framebuffer = RID();
	snapshot_texture = RID();
	index_buffer = RID();
}

} // namespace godot_javafx::rd_direct
