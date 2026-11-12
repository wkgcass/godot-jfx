#include "javafx_render_target.h"
#include "javafx_shader_rewrite.h"

HashSet<RID> JavaFXRenderTarget::live_sampler_rids;
#include "prism_mesh.h"
#include "core/object/class_db.h"
#include "core/os/thread.h"
#include "core/os/os.h"
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
#include "javafx_rd_pass.h"
#endif

#include "core/templates/hashfuncs.h"
#include "servers/rendering/rendering_server.h"
#include "servers/rendering/rendering_server_globals.h"
#include "servers/rendering/renderer_viewport.h"
#include "servers/rendering/storage/texture_storage.h"
#include "core/object/callable_mp.h"
#include <atomic>

namespace {
// Accessed only by main-thread target drawing/destruction. The weak registry
// does not keep GPU resources alive after the final target releases its owner.
std::shared_ptr<PrismMeshCache> acquire_target_mesh_cache() {
	static std::weak_ptr<PrismMeshCache> registry;
	auto cache = registry.lock();
	if (!cache) {
		cache = std::make_shared<PrismMeshCache>();
		registry = cache;
	}
	return cache;
}
std::atomic<uint64_t> render_offscreen_us{0}, render_offscreen_calls{0}, render_offscreen_slow_calls{0};
}

Dictionary JavaFXRenderTarget::get_render_thread_profile() {
	Dictionary result;
	result["profile_render_offscreen_us"] = render_offscreen_us.load(std::memory_order_relaxed);
	result["profile_render_offscreen_calls"] = render_offscreen_calls.load(std::memory_order_relaxed);
	result["profile_render_offscreen_slow_calls"] = render_offscreen_slow_calls.load(std::memory_order_relaxed);
	return result;
}

int64_t JavaFXRenderTarget::get_rd_uniform_set_creation_count() const {
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	return rd_pass.is_valid() ? rd_pass->get_stats().uniform_sets_created : 0;
#else
	return 0;
#endif
}

int64_t JavaFXRenderTarget::get_rd_pipeline_cache_size() const {
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	return godot_javafx::rd_direct::shared_pipeline_cache_size();
#else
	return 0;
#endif
}

Dictionary JavaFXRenderTarget::get_instance_uniform_cache_stats() const {
	Dictionary stats;
	stats["entries"] = godot_javafx::instance_uniform_cache_size();
	stats["bytes"] = godot_javafx::instance_uniform_cache_bytes();
	return stats;
}

void JavaFXRenderTarget::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_instance_uniform_cache_stats"), &JavaFXRenderTarget::get_instance_uniform_cache_stats);
	ClassDB::bind_method(D_METHOD("get_rd_pipeline_cache_size"), &JavaFXRenderTarget::get_rd_pipeline_cache_size);
	ClassDB::bind_method(D_METHOD("initialize", "size", "force_viewport"), &JavaFXRenderTarget::initialize, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("is_rd_direct"), &JavaFXRenderTarget::is_rd_direct);
	ClassDB::bind_method(D_METHOD("get_rd_uniform_set_creation_count"), &JavaFXRenderTarget::get_rd_uniform_set_creation_count);
	ClassDB::bind_method(D_METHOD("draw_offscreen_pass"), &JavaFXRenderTarget::draw_offscreen_pass);
	ClassDB::bind_method(D_METHOD("rd_readback"), &JavaFXRenderTarget::rd_readback);
	ClassDB::bind_method(D_METHOD("begin_pass", "clear"), &JavaFXRenderTarget::begin_pass);
	ClassDB::bind_method(D_METHOD("add_rectangle", "rect", "color"), &JavaFXRenderTarget::add_rectangle);
	ClassDB::bind_method(D_METHOD("copy_target", "source", "rect"), &JavaFXRenderTarget::copy_target);
	ClassDB::bind_method(D_METHOD("end_pass"), &JavaFXRenderTarget::end_pass);
	ClassDB::bind_method(D_METHOD("finish_pass"), &JavaFXRenderTarget::finish_pass);
	ClassDB::bind_method(D_METHOD("draw_prism_quads", "vertices", "colors", "shader", "parameters", "clip", "rect", "texture", "transform", "modulate"), &JavaFXRenderTarget::draw_prism_quads, DEFVAL(RID()), DEFVAL(Transform2D()), DEFVAL(1.0f));
	ClassDB::bind_method(D_METHOD("draw_prism_mesh", "mesh", "shader", "parameters", "clip", "rect", "texture", "transform", "modulate"), &JavaFXRenderTarget::draw_prism_mesh, DEFVAL(RID()), DEFVAL(Transform2D()), DEFVAL(1.0f));
	ClassDB::bind_method(D_METHOD("get_size"), &JavaFXRenderTarget::get_size);
	ClassDB::bind_method(D_METHOD("get_texture"), &JavaFXRenderTarget::get_texture);
	ClassDB::bind_method(D_METHOD("get_owned_resource_count"), &JavaFXRenderTarget::get_owned_resource_count);
	ClassDB::bind_method(D_METHOD("get_cached_mesh_count"), &JavaFXRenderTarget::get_cached_mesh_count);
	ClassDB::bind_method(D_METHOD("get_cached_shader_count"), &JavaFXRenderTarget::get_cached_shader_count);
	ClassDB::bind_method(D_METHOD("get_cached_material_count"), &JavaFXRenderTarget::get_cached_material_count);
	ClassDB::bind_method(D_METHOD("get_draw_slot_count"), &JavaFXRenderTarget::get_draw_slot_count);
	ClassDB::bind_method(D_METHOD("get_shader_creation_count"), &JavaFXRenderTarget::get_shader_creation_count);
}

void JavaFXRenderTarget::initialize_texture_proxy(RID p_viewport, RID p_proxy) {
	RID texture = RSG::viewport->viewport_get_texture(p_viewport);
	ERR_FAIL_COND(!texture.is_valid());
	RSG::texture_storage->texture_proxy_initialize(p_proxy, texture);
}

bool JavaFXRenderTarget::initialize(const Size2i &p_size, bool p_force_viewport) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || viewport.is_valid() || is_rd_direct(), false);
	ERR_FAIL_COND_V(p_size.x < 1 || p_size.y < 1 || p_size.x > 8192 || p_size.y > 8192, false);
	size = p_size;
	// RD-direct backend (plan P3): replace this target's viewport render
	// cycle with raw RenderingDevice passes. gl_compatibility has no
	// RenderingDevice and keeps the viewport path regardless.
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	static const bool rd_direct = OS::get_singleton()->get_environment("GODOT_JFX_RD_DIRECT") == "1";
	if (!p_force_viewport && rd_direct && RenderingServer::get_singleton()->get_rendering_device() != nullptr) {
		rd_pass.instantiate();
		if (rd_pass->initialize(p_size)) {
			initialized_contents = false;
			if (rd_pass->get_texture().is_valid()) live_sampler_rids.insert(rd_pass->get_texture());
			return rd_pass->get_texture().is_valid();
		}
		rd_pass.unref(); // fall through to the viewport path on failure
	}
#else
	ERR_FAIL_COND_V_MSG(!p_force_viewport && OS::get_singleton()->get_environment("GODOT_JFX_RD_DIRECT") == "1", false,
			"RD-direct was not compiled; rebuild with javafx_rd_direct=yes or unset GODOT_JFX_RD_DIRECT.");
#endif

	auto *rs = RenderingServer::get_singleton();
	viewport = rs->viewport_create(); canvas = rs->canvas_create(); commands = rs->canvas_item_create();
	shader = rs->shader_create(); material = rs->material_create();
	rs->shader_set_code(shader, "shader_type canvas_item; render_mode unshaded, blend_premul_alpha;");
	rs->material_set_shader(material, shader);
	rs->canvas_item_set_material(commands, material);
	rs->canvas_item_set_parent(commands, canvas);
	rs->viewport_set_size(viewport, size.x, size.y);
	rs->viewport_set_disable_3d(viewport, true);
	rs->viewport_set_transparent_background(viewport, true);
	rs->viewport_attach_canvas(viewport, canvas);
	rs->viewport_set_clear_mode(viewport, RSE::VIEWPORT_CLEAR_ALWAYS);
	rs->viewport_set_update_mode(viewport, RSE::VIEWPORT_UPDATE_DISABLED);
	rs->viewport_set_active(viewport, true);
	if (OS::get_singleton()->get_environment("GODOT_JFX_ASYNC_TARGET_TEXTURE") == "1") {
		// texture_allocate is the same thread-safe RID allocation used by the
		// RenderingServer texture factories. Initialize only on the renderer,
		// after viewport setup and before any subsequent sampler commands.
		viewport_texture = RSG::texture_storage->texture_allocate();
		owns_viewport_texture = true;
		rs->call_on_render_thread(callable_mp_static(&JavaFXRenderTarget::initialize_texture_proxy).bind(viewport, viewport_texture));
	} else {
		viewport_texture = rs->viewport_get_texture(viewport);
	}
	if (viewport_texture.is_valid()) live_sampler_rids.insert(viewport_texture);
	return viewport_texture.is_valid();
}

void JavaFXRenderTarget::begin_pass(bool p_clear) {
	ERR_FAIL_COND(!Thread::is_main_thread() || pass_open);
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		if (!sources.is_empty()) {
			godot_javafx::rd_direct::OffscreenPass::commit_batches();
			sources.clear();
		}
		rd_pass->begin_pass(p_clear);
		pass_open = true;
		return;
	}
#endif

	ERR_FAIL_COND(!viewport.is_valid());
	auto *rs = RenderingServer::get_singleton();
	rs->viewport_set_update_mode(viewport, RSE::VIEWPORT_UPDATE_DISABLED);
	clear_draws();
	rs->viewport_set_clear_mode(viewport, (p_clear || !initialized_contents) ? RSE::VIEWPORT_CLEAR_ONLY_NEXT_FRAME : RSE::VIEWPORT_CLEAR_NEVER);
	pass_open = true;
}

void JavaFXRenderTarget::add_rectangle(const Rect2 &p_rect, const Color &p_color) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !pass_open);
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		rd_pass->add_rectangle(p_rect, Color(p_color.r * p_color.a, p_color.g * p_color.a, p_color.b * p_color.a, p_color.a));
		return;
	}
#endif

	RenderingServer::get_singleton()->canvas_item_add_rect(create_draw_item(material), p_rect,
		Color(p_color.r * p_color.a, p_color.g * p_color.a, p_color.b * p_color.a, p_color.a));
}

bool JavaFXRenderTarget::depends_on(const JavaFXRenderTarget *p_target) const {
	if (this == p_target) return true;
	for (const Ref<JavaFXRenderTarget> &source : sources) if (source->depends_on(p_target)) return true;
	return false;
}

void JavaFXRenderTarget::copy_target(const Ref<JavaFXRenderTarget> &p_source, const Rect2 &p_rect) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !pass_open || p_source.is_null());
	ERR_FAIL_COND_MSG(p_source->pass_open || !p_source->get_texture().is_valid() || p_source->depends_on(this), "Render target feedback/cyclic sampling requires a completed snapshot pass.");
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		rd_pass->copy_target(p_source->get_texture(), p_rect);
		sources.push_back(p_source);
		return;
	}
#endif

	RenderingServer::get_singleton()->canvas_item_add_texture_rect(create_draw_item(material), p_rect, p_source->get_texture());
	sources.push_back(p_source);
}

void JavaFXRenderTarget::end_pass() {
	ERR_FAIL_COND(!Thread::is_main_thread() || !pass_open);
	pass_open = false;
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		rd_pass->end_pass();
		return;
	}
#endif

	// Retired slots must not render in this pass's UPDATE_ONCE snapshot.
	hide_unused_slots();
	RenderingServer::get_singleton()->viewport_set_update_mode(viewport, RSE::VIEWPORT_UPDATE_ONCE);
}

void JavaFXRenderTarget::finish_pass() {
	ERR_FAIL_COND(!Thread::is_main_thread() || pass_open);
	initialized_contents = true;
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		rd_pass->finish_pass();
		// copy_target retains its source until recorded draws have reached the
		// device. Ordinary QUADS use the host ledger and need no extra fence.
		if (!sources.is_empty()) {
			godot_javafx::rd_direct::OffscreenPass::commit_batches();
			sources.clear();
		}
		return;
	}
#endif

	clear_draws();
}

void JavaFXRenderTarget::draw_offscreen_on_render_thread() {
	const uint64_t start = OS::get_singleton()->get_ticks_usec();
	draw_queued_offscreen(viewport);
	offscreen_draw_us = OS::get_singleton()->get_ticks_usec() - start;
}

uint64_t JavaFXRenderTarget::draw_offscreen_pass() {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || pass_open, 0);
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		const uint64_t start = OS::get_singleton()->get_ticks_usec();
		rd_pass->flush();
		return OS::get_singleton()->get_ticks_usec() - start;
	}
#endif

	auto *rs = RenderingServer::get_singleton();
	if (!rs->is_on_render_thread() && OS::get_singleton()->get_environment("GODOT_JFX_ASYNC_PASS_FENCE") != "0") {
		// Capture the RID by value, never the RefCounted target's address. All
		// later material mutations and RID frees use this same server FIFO.
		// The host fences the completed batch before readback/sequence release.
		rs->call_on_render_thread(callable_mp_static(&JavaFXRenderTarget::draw_queued_offscreen).bind(viewport));
		return 0; // Render-thread duration is not available before the batch fence.
	}
	// In single-thread (safe) mode the dispatch below executes synchronously on
	// this thread, so encoding order is already guaranteed; GPU-side ordering
	// between a pass and later sampling of its texture is the renderer's
	// barrier responsibility. The full-device sync therefore only paces the
	// CPU against GPU completion: waiting every pass keeps the command queue
	// short (and the host loop responsive), waiting never lets the queue grow
	// until a driver stall at submission. The interval knob selects a point
	// between the two measured extremes (1 = every pass, 0 = rely on the
	// end-of-tick batch fence).
	static int pass_sync_interval = [] {
		const String setting = OS::get_singleton()->get_environment("GODOT_JFX_PASS_SYNC_INTERVAL");
		// Default 0: rely on the end-of-tick batch fence. Waiting every pass
		// measured 42.4 fps vs 45.0-45.2 without it (after the instance-
		// uniform and material fixes landed); k>1 waits every k passes.
		return setting.is_empty() ? 0 : setting.to_int();
	}();
	static uint32_t pass_sync_counter = 0;
	// With the async batch path disabled, this callback still captures this
	// object and writes offscreen_draw_us. Finish it before returning on a
	// separate render thread, regardless of the safe-mode pacing interval.
	const bool separate_thread = !rs->is_on_render_thread();
	rs->call_on_render_thread(callable_mp(this, &JavaFXRenderTarget::draw_offscreen_on_render_thread));
	if (separate_thread || (pass_sync_interval > 0 && (++pass_sync_counter % (uint32_t)pass_sync_interval) == 0)) rs->sync();
	return offscreen_draw_us;
}

void JavaFXRenderTarget::draw_queued_offscreen(RID p_viewport) {
	static const bool profile = OS::get_singleton()->get_environment("GODOT_JFX_PROFILE_COMMANDS") == "1";
	const uint64_t start = profile ? OS::get_singleton()->get_ticks_usec() : 0;
	RSG::viewport->draw_offscreen_2d(p_viewport);
	if (profile) {
		const uint64_t elapsed = OS::get_singleton()->get_ticks_usec() - start;
		render_offscreen_us.fetch_add(elapsed, std::memory_order_relaxed);
		render_offscreen_calls.fetch_add(1, std::memory_order_relaxed);
		if (elapsed > 2000) render_offscreen_slow_calls.fetch_add(1, std::memory_order_relaxed);
	}
}

void JavaFXRenderTarget::clear_pass() {
	ERR_FAIL_COND(!Thread::is_main_thread() || !pass_open);
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		rd_pass->clear_pass();
		return;
	}
#endif

	clear_draws();
	RenderingServer::get_singleton()->viewport_set_clear_mode(viewport, RSE::VIEWPORT_CLEAR_ONLY_NEXT_FRAME);
}

RID JavaFXRenderTarget::get_texture() const {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || pass_open, RID());
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) return rd_pass->get_texture();
#endif

	ERR_FAIL_COND_V(!viewport.is_valid(), RID());
	return viewport_texture;
}

int JavaFXRenderTarget::get_owned_resource_count() const {
	return int(viewport.is_valid() || is_rd_direct()) + int(canvas.is_valid()) + int(commands.is_valid()) + int(shader.is_valid()) + int(material.is_valid()) + int(owns_viewport_texture && viewport_texture.is_valid()) + draw_resources.size() + shader_cache.size() + slots.size() + material_cache.size();
}

RID JavaFXRenderTarget::create_draw_item(RID p_material) {
	auto *rs = RenderingServer::get_singleton();
	RID item = rs->canvas_item_create();
	rs->canvas_item_set_parent(item, canvas);
	rs->canvas_item_set_draw_index(item, draw_index++);
	rs->canvas_item_set_material(item, p_material);
	draw_resources.push_back(item);
	return item;
}

RID JavaFXRenderTarget::acquire_material(RID p_shader, const Dictionary &p_parameters, bool p_persistent_shader) {
	auto *rs = RenderingServer::get_singleton();
	// Materials are immutable (shader + parameters); a moving parent repeats
	// the same pairs every pass. Sampler parameters carry retained texture
	// RIDs; such sets are cached with their RIDs recorded, and every hit
	// revalidates them against the live-sampler set so a retired revision is
	// never re-bound (RID values never recycle). Misses prune retired entries
	// before insertion. The shader must outlive the pass.
	static const bool rid_material_cache = OS::get_singleton()->get_environment("GODOT_JFX_RID_MATERIAL_CACHE") != "0";
	if (!rid_material_cache) {
		bool cacheable_legacy = true;
		for (const Variant &param : p_parameters.keys()) {
			if (p_parameters[param].get_type() == Variant::RID) { cacheable_legacy = false; break; }
		}
		if (!cacheable_legacy) {
			RID material_rid = rs->material_create();
			rs->material_set_shader(material_rid, p_shader);
			for (const Variant &param : p_parameters.keys()) rs->material_set_param(material_rid, param, p_parameters[param]);
			draw_resources.push_back(material_rid);
			return material_rid;
		}
	}
	if (!p_persistent_shader) {
		RID material_rid = rs->material_create();
		rs->material_set_shader(material_rid, p_shader);
		for (const Variant &param : p_parameters.keys()) rs->material_set_param(material_rid, param, p_parameters[param]);
		draw_resources.push_back(material_rid);
		return material_rid;
	}
	uint64_t key = hash_murmur3_one_64(p_shader.get_id()) ^ hash_murmur3_one_64(p_parameters.hash());
	Vector<RID> rids;
	for (const Variant &param : p_parameters.keys()) {
		if (p_parameters[param].get_type() == Variant::RID) rids.push_back(p_parameters[param]);
	}
	if (const MaterialEntry *cached = material_cache.getptr(key)) {
		bool identical = cached->shader == p_shader && cached->params == p_parameters && cached->material.is_valid();
		if (identical) {
			for (const RID &rid : cached->rids) if (!sampler_alive(rid)) { identical = false; break; }
		}
		if (identical) return cached->material;
	}
	// A miss may replace a disposed player's sampler RIDs. Reclaim dead
	// entries on misses instead of retaining one material per player until
	// capacity pressure. Hits keep their constant-time lookup; retirement
	// still follows the pass lifetime so queued draws retain their material.
	for (auto *order = material_cache_order.front(); order;) {
		auto *next = order->next();
		const uint64_t old_key = order->get();
		const MaterialEntry *entry = material_cache.getptr(old_key);
		bool alive = entry != nullptr;
		if (entry) {
			for (const RID &rid : entry->rids) if (!sampler_alive(rid)) { alive = false; break; }
		}
		// Collisions may store a full identity away from its initial hash.
		// Search before inserting even if deletion left a hole in that chain.
		if (alive && entry->shader == p_shader && entry->params == p_parameters && entry->material.is_valid()) {
			return entry->material;
		}
		if (!alive) {
			if (entry) {
				draw_resources.push_back(entry->material);
				material_cache.erase(old_key);
			}
			material_cache_order.erase(order);
		}
		order = next;
	}
	if (material_cache.size() >= 256 && material_cache_order.front()) {
		const uint64_t oldest = material_cache_order.front()->get();
		draw_resources.push_back(material_cache[oldest].material);
		material_cache.erase(oldest);
		material_cache_order.erase(material_cache_order.front());
	}
	// Published materials are immutable: earlier queued draws may still use
	// them. Hash equality must never authorize rebinding their samplers.
	while (material_cache.has(key)) ++key;
	RID material_rid = rs->material_create();
	rs->material_set_shader(material_rid, p_shader);
	for (const Variant &param : p_parameters.keys()) rs->material_set_param(material_rid, param, p_parameters[param]);
	if (material_cache.size() < 256) {
		MaterialEntry entry;
		entry.material = material_rid;
		entry.shader = p_shader;
		entry.params = p_parameters.duplicate(true);
		entry.rids = rids;
		material_cache.insert(key, entry);
		material_cache_order.push_back(key);
	} else {
		draw_resources.push_back(material_rid);
	}
	return material_rid;
}

void JavaFXRenderTarget::set_measure_gpu_time(bool p_enable) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	if (viewport.is_valid()) RenderingServer::get_singleton()->viewport_set_measure_render_time(viewport, p_enable);
}

double JavaFXRenderTarget::get_measured_gpu_time_us() const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), 0.0);
	if (viewport.is_null()) return 0.0;
	// The engine reports milliseconds as a double.
	return RenderingServer::get_singleton()->viewport_get_measured_render_time_gpu(viewport) * 1000.0;
}

void JavaFXRenderTarget::hide_unused_slots() {
	auto *rs = RenderingServer::get_singleton();
	for (DrawSlot &slot : slots) {
		if (!slot.used && slot.visible && slot.item.is_valid()) {
			// Clearing the command list removes the slot's geometry without
			// touching item visibility state.
			rs->canvas_item_clear(slot.item);
			slot.visible = false;
			slot.mesh_owner.unref();
			slot.mesh = RID();
		}
	}
}

void JavaFXRenderTarget::free_slots() {
	auto *rs = RenderingServer::get_singleton();
	for (DrawSlot &slot : slots)
		if (slot.item.is_valid()) rs->free_rid(slot.item);
	slots.clear();
	next_draw_slot = 0;
}

void JavaFXRenderTarget::clear_draws() {
	auto *rs = RenderingServer::get_singleton();
	for (RID rid : draw_resources) rs->free_rid(rid);
	draw_resources.clear(); uncached_meshes.clear(); sources.clear(); draw_index = 0;
	next_draw_slot = 0;
	// Slot items stay alive across passes; hide everything the previous pass
	// did not touch so stale geometry cannot leak into the next render.
	hide_unused_slots();
	for (DrawSlot &slot : slots) slot.used = false;
}

void JavaFXRenderTarget::draw_prism_quads(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors,
		const String &p_shader, const Dictionary &p_parameters, bool p_clip, const Rect2i &p_rect, RID p_texture,
		const Transform2D &p_transform, float p_modulate) {
	draw_prism_quads_with_instances(p_vertices, p_colors, p_shader, p_parameters, p_clip, p_rect, p_texture, p_transform, p_modulate, nullptr);
}

void JavaFXRenderTarget::draw_prism_quads_with_instances(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors,
		const String &p_shader, const Dictionary &p_parameters, bool p_clip, const Rect2i &p_rect, RID p_texture,
		const Transform2D &p_transform, float p_modulate, const HashMap<StringName, Variant> *p_instance_params) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !pass_open);
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		// This entry is also callable directly from Godot scripts, bypassing
		// the Java frame decoder. Match the Viewport path's 2D batch contract.
		const int64_t count = p_vertices.size() / 7;
		ERR_FAIL_COND_MSG(count <= 0 || count > 65536 || count % 4 || p_vertices.size() != count * 7 || p_colors.size() != count * 4,
				"Invalid RD Prism geometry shape.");
		const float *vertices = p_vertices.ptr();
		for (int64_t i = 0; i < count; ++i) {
			for (int component = 0; component < 7; ++component) {
				ERR_FAIL_COND_MSG(!Math::is_finite(vertices[i * 7 + component]), "Non-finite RD Prism vertex.");
			}
			ERR_FAIL_COND_MSG(vertices[i * 7 + 2] != 0, "3D Prism projection is not implemented.");
		}
		// PackedFloat32Array/PackedByteArray are these Vector types already.
		// draw_quads consumes them synchronously into its owned GPU payload;
		// copying both complete input arrays here adds no lifetime protection.
		draw_prism_raw(p_vertices, p_colors, p_shader, p_parameters, p_clip, p_rect, p_texture, p_transform, p_modulate, p_instance_params);
		return;
	}
#endif

	// Identical batches across passes (e.g. a translating parent) reuse the
	// cached mesh instead of rebuilding one per pass.
	static const bool cache_meshes = OS::get_singleton()->get_environment("GODOT_JFX_MESH_CACHE") != "0";
	Ref<ArrayMesh> mesh;
	if (cache_meshes) {
		if (!mesh_cache) mesh_cache = acquire_target_mesh_cache();
		PrismMeshCache::Key key = PrismMeshCache::hash(p_vertices, p_colors);
		mesh = mesh_cache->get(key, p_vertices, p_colors);
		if (mesh.is_null()) {
			build_prism_mesh(mesh, p_vertices, p_colors);
			ERR_FAIL_COND(mesh.is_null());
			mesh_cache->put(key, mesh, p_vertices, p_colors);
		}
	} else {
		build_prism_mesh(mesh, p_vertices, p_colors);
		ERR_FAIL_COND(mesh.is_null());
		uncached_meshes.push_back(mesh);
	}
	draw_prism_mesh_with_instances(mesh, p_shader, p_parameters, p_clip, p_rect, p_texture, p_transform, p_modulate, p_instance_params);
}

#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
void JavaFXRenderTarget::draw_prism_raw(const Vector<float> &p_vertices, const Vector<uint8_t> &p_colors, const String &p_shader,
		Dictionary p_parameters, bool p_clip, const Rect2i &p_rect, RID p_texture, const Transform2D &p_transform,
		float p_modulate, const HashMap<StringName, Variant> *p_instance_params, const void *p_identity_key) {
	// RD-direct: the instance-vs-material split is a viewport-path concern;
	// every constant rides the std140 uniform buffer here.
	const bool prof = godot_javafx::rd_direct::rd_profile_enabled();
	const uint64_t t0 = prof ? OS::get_singleton()->get_ticks_usec() : 0;
	if (p_instance_params) {
		for (const KeyValue<StringName, Variant> &param : *p_instance_params) p_parameters[param.key] = param.value;
	}
	if (prof) godot_javafx::rd_direct::rd_profile_sink(1, OS::get_singleton()->get_ticks_usec() - t0);
	const uint64_t t1 = prof ? OS::get_singleton()->get_ticks_usec() : 0;
	rd_pass->draw_quads(p_vertices, p_colors, p_shader, p_parameters, p_clip, p_rect, p_texture, p_transform, p_modulate, p_identity_key);
	if (prof) godot_javafx::rd_direct::rd_profile_sink(2, OS::get_singleton()->get_ticks_usec() - t1);
}
#endif

void JavaFXRenderTarget::draw_prism_mesh(const Ref<ArrayMesh> &p_mesh, const String &p_shader, const Dictionary &p_parameters,
		bool p_clip, const Rect2i &p_rect, RID p_texture, const Transform2D &p_transform, float p_modulate) {
	draw_prism_mesh_with_instances(p_mesh, p_shader, p_parameters, p_clip, p_rect, p_texture, p_transform, p_modulate, nullptr);
}

void JavaFXRenderTarget::draw_prism_mesh_with_instances(const Ref<ArrayMesh> &p_mesh, const String &p_shader, const Dictionary &p_parameters,
		bool p_clip, const Rect2i &p_rect, RID p_texture, const Transform2D &p_transform, float p_modulate,
		const HashMap<StringName, Variant> *p_instance_params) {
		ERR_FAIL_COND(!Thread::is_main_thread() || !pass_open || p_mesh.is_null());
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) {
		// RD-direct consumes raw batch bytes; recover them from the cached
		// mesh (QUADS_REF references whose raw pair was never registered).
		// The decode is memoized per mesh object - it dominates drag frames
		// when repeated for every pass.
		Vector<float> vertices;
		Vector<uint8_t> rgba;
		const void *memo_key = p_mesh.ptr();
		if (const auto *memo = rd_mesh_memo.getptr(p_mesh->get_instance_id())) {
			vertices = memo->first;
			rgba = memo->second;
		} else {
			// The pointer may have belonged to an older instance. A memo miss
			// must also invalidate this pass's pointer-based GPU buffer shortcut.
			rd_pass->purge_identity(memo_key);
			ERR_FAIL_COND(p_mesh->get_surface_count() != 1);
			const Array surface = p_mesh->surface_get_arrays(0);
			ERR_FAIL_COND(surface.size() != Mesh::ARRAY_MAX);
			const PackedVector2Array position_array = surface[Mesh::ARRAY_VERTEX];
			const PackedVector2Array uv_array = surface[Mesh::ARRAY_TEX_UV];
			const PackedFloat32Array custom_array = surface[Mesh::ARRAY_CUSTOM0];
			const PackedColorArray color_array = surface[Mesh::ARRAY_COLOR];
			const int count = position_array.size();
			ERR_FAIL_COND(count <= 0 || count > 65536 || count % 4 != 0);
			ERR_FAIL_COND(uv_array.size() != count || custom_array.size() != count * 4 || color_array.size() != count);
			const Vector2 *positions = position_array.ptr();
			const Vector2 *uvs = uv_array.ptr();
			const float *custom = custom_array.ptr();
			const Color *colors = color_array.ptr();
			vertices.resize(count * 7);
			rgba.resize(count * 4);
			for (int i = 0; i < count; ++i) {
				float *out = vertices.ptrw() + i * 7;
				out[0] = positions[i].x; out[1] = positions[i].y; out[2] = 0;
				out[3] = uvs[i].x; out[4] = uvs[i].y;
				out[5] = custom[i * 4]; out[6] = custom[i * 4 + 1];
				rgba.write[i * 4] = uint8_t(CLAMP(int(colors[i].r * 255.0f), 0, 255));
				rgba.write[i * 4 + 1] = uint8_t(CLAMP(int(colors[i].g * 255.0f), 0, 255));
				rgba.write[i * 4 + 2] = uint8_t(CLAMP(int(colors[i].b * 255.0f), 0, 255));
				rgba.write[i * 4 + 3] = uint8_t(CLAMP(int(colors[i].a * 255.0f), 0, 255));
			}
			if (rd_mesh_memo.size() >= 64) rd_mesh_memo.clear();
			rd_mesh_memo.insert(p_mesh->get_instance_id(), { vertices, rgba });
		}
		draw_prism_raw(vertices, rgba, p_shader, p_parameters, p_clip, p_rect, p_texture, p_transform, p_modulate, p_instance_params, memo_key);
		return;
	}
#endif

	auto *rs = RenderingServer::get_singleton();
	// Diagnostic switch (GODOT_JFX_SLOT_REUSE=0): per-pass free/recreate with
	// command transforms — the pre-optimization behavior.
	static const bool reuse_slots = OS::get_singleton()->get_environment("GODOT_JFX_SLOT_REUSE") != "0";
	RID shader_rid;
	bool persistent_shader = false;
	if (const RID *cached = shader_cache.getptr(p_shader)) {
		shader_rid = *cached;
		persistent_shader = true;
	} else {
		shader_rid = rs->shader_create();
		// Target-path shaders move their value uniforms to per-instance
		// uniforms: per-frame constants then ride item instance data instead
		// of rebuilding the material's uniform sets every pass.
		static const bool instance_uniforms = OS::get_singleton()->get_environment("GODOT_JFX_INSTANCE_UNIFORMS") != "0";
		if (instance_uniforms) {
			Vector<StringName> names;
			rs->shader_set_code(shader_rid, godot_javafx::rewrite_instance_uniforms(p_shader, names));
		} else {
			rs->shader_set_code(shader_rid, p_shader);
		}
		++shader_creations;
		// Codes are immutable keys. Bound persistent storage per target; overflow
		// shaders remain pass-owned so dynamic user code cannot grow this cache.
		if (shader_cache.size() < 64) { shader_cache.insert(p_shader, shader_rid); persistent_shader = true; }
		else draw_resources.push_back(shader_rid);
	}
	RID material_rid = acquire_material(shader_rid, p_parameters, persistent_shader);
	// Uniform modulation rides on each mesh command: slots re-record their
	// commands every pass, so the draw-time modulate always matches the
	// current batch without extra item state.
	const Color modulate(p_modulate, p_modulate, p_modulate, p_modulate);
	if (!reuse_slots) {
		uncached_meshes.push_back(p_mesh);
		RID item = rs->canvas_item_create();
		rs->canvas_item_set_parent(item, canvas);
		rs->canvas_item_set_material(item, material_rid);
		if (p_instance_params) {
			for (const KeyValue<StringName, Variant> &param : *p_instance_params) {
				rs->canvas_item_set_instance_shader_parameter(item, param.key, param.value);
			}
		}
		rs->canvas_item_set_draw_index(item, draw_index++);
		rs->canvas_item_set_custom_rect(item, p_clip, p_rect);
		rs->canvas_item_set_clip(item, p_clip);
		if (p_transform != Transform2D()) rs->canvas_item_add_set_transform(item, p_transform);
		rs->canvas_item_add_mesh(item, p_mesh->get_rid(), Transform2D(), modulate, p_texture);
		draw_resources.push_back(item);
		return;
	}
	// Slots keep one canvas item per quad draw; draw order equals slot order,
	// refreshed through draw_index each pass. An unchanged batch under a
	// moving parent only updates its transform.
	const int slot_index = next_draw_slot++;
	// Dropping an override requires a fresh item: passing NIL is invalid for
	// RD instance uniforms, and querying defaults synchronizes the render
	// thread. Recreate when the shader changes or parameters shrink; ordinary draws
	// retain their item and all explicitly supplied values are overwritten.
	if (slot_index < slots.size()) {
		DrawSlot &previous = slots.write[slot_index];
		// Godot also retains initialized defaults when switching shaders.
		bool reset_item = previous.shader != shader_rid;
		for (const StringName &name : previous.instance_names) {
			if (!p_instance_params || !p_instance_params->has(name)) {
				reset_item = true;
				break;
			}
		}
		if (reset_item) {
			rs->free_rid(previous.item);
			previous.item = rs->canvas_item_create();
			rs->canvas_item_set_parent(previous.item, canvas);
			previous.material = RID(); // Force complete material/draw setup below.
			previous.instance_names.clear();
		}
	}
	auto apply_instance_parameters = [&](DrawSlot &p_slot) {
		Vector<StringName> next_names;
		if (p_instance_params) {
			for (const KeyValue<StringName, Variant> &param : *p_instance_params) {
				rs->canvas_item_set_instance_shader_parameter(p_slot.item, param.key, param.value);
				next_names.push_back(param.key);
			}
		}
		p_slot.instance_names = next_names;
	};
	if (slot_index < slots.size() && slots[slot_index].matches(p_mesh->get_rid(), material_rid, p_texture, p_clip, p_rect)) {
		DrawSlot &slot = slots.write[slot_index];
		slot.used = true;
		slot.visible = true;
		apply_instance_parameters(slot);
		rs->canvas_item_set_draw_index(slot.item, draw_index++);
		// canvas_item_clear resets the recorded clip state, so a reused slot
		// re-applies rect and clip together with its two commands.
		rs->canvas_item_clear(slot.item);
		rs->canvas_item_set_custom_rect(slot.item, p_clip, p_rect);
		rs->canvas_item_set_clip(slot.item, p_clip);
		if (p_transform != Transform2D()) rs->canvas_item_add_set_transform(slot.item, p_transform);
		rs->canvas_item_add_mesh(slot.item, slot.mesh, Transform2D(), modulate, slot.texture);
		slot.transform = p_transform;
		return;
	}
	DrawSlot slot;
	// The item may come from a slot whose material differs; capture the
	// previous binding before the local struct is overwritten.
	RID previous_material;
	if (slot_index < slots.size()) {
		slot.item = slots[slot_index].item;
		slot.instance_names = slots[slot_index].instance_names;
		previous_material = slots[slot_index].material;
		rs->canvas_item_clear(slot.item);
	} else {
		slot.item = rs->canvas_item_create();
		rs->canvas_item_set_parent(slot.item, canvas);
	}
	slot.mesh = p_mesh->get_rid();
	slot.mesh_owner = p_mesh;
	slot.material = material_rid;
	slot.shader = shader_rid;
	slot.texture = p_texture;
	slot.clip = p_clip;
	slot.rect = p_rect;
	slot.used = true;
	slot.visible = true;
	// Re-binding the same material queues the item for dependency updates on
	// every pass; only switch when the material actually changed.
	static const bool skip_same_material = OS::get_singleton()->get_environment("GODOT_JFX_SLOT_MATERIAL_SKIP") != "0";
	if (!skip_same_material || previous_material != material_rid) rs->canvas_item_set_material(slot.item, material_rid);
	apply_instance_parameters(slot);
	// The cull rect ignores CommandMesh::transform; item-level transform
	// (canvas_item_set_transform) is applied to the cull rect through
	// final_xform, so offscreen targets keep correct clipping while it moves.
	rs->canvas_item_set_custom_rect(slot.item, p_clip, p_rect);
	rs->canvas_item_set_clip(slot.item, p_clip);
	if (p_transform != Transform2D()) rs->canvas_item_add_set_transform(slot.item, p_transform);
	slot.transform = p_transform;
	rs->canvas_item_add_mesh(slot.item, slot.mesh, Transform2D(), modulate, p_texture);
	rs->canvas_item_set_draw_index(slot.item, draw_index++);
	if (slot_index < slots.size()) slots.write[slot_index] = slot;
	else slots.push_back(slot);
}

JavaFXRenderTarget::~JavaFXRenderTarget() {
	ERR_FAIL_COND(!Thread::is_main_thread());
	auto *rs = RenderingServer::get_singleton();
	// Remove the identity before releasing either backend; get_texture() must
	// still resolve the RD bridge RID here, not an already-cleared pass.
	if (is_rd_direct() || viewport.is_valid()) live_sampler_rids.erase(get_texture());
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	if (rd_pass.is_valid()) rd_pass.unref();
#endif

	clear_draws();
	free_slots();
	for (const KeyValue<uint64_t, MaterialEntry> &entry : material_cache) rs->free_rid(entry.value.material);
	material_cache.clear();
	material_cache_order.clear();
	mesh_cache.reset();
	for (const KeyValue<String, RID> &entry : shader_cache) rs->free_rid(entry.value);
	shader_cache.clear();
	// FIFO initialization and destruction capture RID values, never this object.
	if (owns_viewport_texture && viewport_texture.is_valid()) rs->free_rid(viewport_texture);
	for (RID rid : { commands, material, shader, canvas, viewport }) if (rid.is_valid()) rs->free_rid(rid);
	sources.clear();
}
