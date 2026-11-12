#include "javafx_render_surface.h"

#include "prism_mesh.h"

#include "core/io/image.h"
#include "core/object/class_db.h"
#include "core/os/thread.h"
#include "core/os/os.h"
#include "servers/rendering/rendering_server.h"
#include "servers/rendering/rendering_server_globals.h"
#include "servers/rendering/storage/texture_storage.h"

void JavaFXRenderSurface::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_surface_size", "size"), &JavaFXRenderSurface::set_surface_size);
	ClassDB::bind_method(D_METHOD("get_surface_size"), &JavaFXRenderSurface::get_surface_size);
	ClassDB::bind_method(D_METHOD("clear_commands"), &JavaFXRenderSurface::clear_commands);
	ClassDB::bind_method(D_METHOD("add_rectangle", "rect", "color"), &JavaFXRenderSurface::add_rectangle);
	ClassDB::bind_method(D_METHOD("add_prism_quads", "vertices", "colors", "transform", "modulate"), &JavaFXRenderSurface::add_prism_quads, DEFVAL(Transform2D()), DEFVAL(1.0f));
	ClassDB::bind_method(D_METHOD("set_draw_shader_code", "code"), &JavaFXRenderSurface::set_draw_shader_code);
	ClassDB::bind_method(D_METHOD("set_draw_shader_parameters", "parameters"), &JavaFXRenderSurface::set_draw_shader_parameters);
	ClassDB::bind_method(D_METHOD("upload_rgba", "size", "pixels"), &JavaFXRenderSurface::upload_rgba);
	ClassDB::bind_method(D_METHOD("add_texture", "rect", "modulate"), &JavaFXRenderSurface::add_texture);
	ClassDB::bind_method(D_METHOD("add_render_target", "target", "rect", "opacity"), &JavaFXRenderSurface::add_render_target, DEFVAL(1.0f));
	ClassDB::bind_method(D_METHOD("add_scene_view", "scene", "rect"), &JavaFXRenderSurface::add_scene_view);
	ClassDB::bind_method(D_METHOD("set_shader_code", "code"), &JavaFXRenderSurface::set_shader_code);
	ClassDB::bind_method(D_METHOD("get_owned_resource_count"), &JavaFXRenderSurface::get_owned_resource_count);
	ClassDB::bind_method(D_METHOD("get_cached_mesh_count"), &JavaFXRenderSurface::get_cached_mesh_count);
	ClassDB::bind_method(D_METHOD("get_texture_resource_stats"), &JavaFXRenderSurface::get_texture_resource_stats);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "surface_size"), "set_surface_size", "get_surface_size");
}

void JavaFXRenderSurface::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		allocate();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		release();
	}
}

void JavaFXRenderSurface::allocate() {
	ERR_FAIL_COND_MSG(!Thread::is_main_thread(), "JavaFX surface allocation requires Godot main thread.");
	ERR_FAIL_COND(viewport.is_valid());
	auto *rs = RenderingServer::get_singleton();
	viewport = rs->viewport_create();
	canvas = rs->canvas_create();
	commands = rs->canvas_item_create();
	presentation = rs->canvas_item_create();
	rs->viewport_set_size(viewport, surface_size.x, surface_size.y);
	rs->viewport_set_disable_3d(viewport, true);
	rs->viewport_set_transparent_background(viewport, true);
	rs->viewport_set_clear_mode(viewport, RSE::VIEWPORT_CLEAR_ALWAYS);
	rs->viewport_set_update_mode(viewport, RSE::VIEWPORT_UPDATE_ALWAYS);
	rs->viewport_attach_canvas(viewport, canvas);
	rs->canvas_item_set_parent(commands, canvas);
	rs->canvas_item_set_parent(presentation, get_canvas_item());
	rs->viewport_set_active(viewport, true);
	// Prism colors and offscreen results use premultiplied alpha. Apply it
	// both when drawing into the viewport and when presenting its texture.
	set_draw_shader_code("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;");
	set_shader_code("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;");
	update_presentation();
}

void JavaFXRenderSurface::update_presentation() {
	auto *rs = RenderingServer::get_singleton();
	rs->canvas_item_clear(presentation);
	// The texture belongs to the viewport. Never free this borrowed RID.
	rs->canvas_item_add_texture_rect(presentation, Rect2(Vector2(), surface_size), rs->viewport_get_texture(viewport));
}

void JavaFXRenderSurface::release() {
	ERR_FAIL_COND_MSG(!Thread::is_main_thread(), "JavaFX surface disposal requires Godot main thread.");
	auto *rs = RenderingServer::get_singleton();
	// Release dependents before resources; zero each handle for idempotence.
	free_retained_draws();
	RID *owned[] = { &presentation, &commands, &background, &draw_material, &draw_shader, &material, &shader, &texture, &canvas, &viewport };
	for (RID *rid : owned) {
		if (rid->is_valid()) {
			rs->free_rid(*rid);
			*rid = RID();
		}
	}
	meshes.clear();
	retained_meshes.clear();
	mesh_cache.clear();
	sampled_targets.clear();
	sampled_scenes.clear();
	free_retired_textures();
	for (const auto &entry : textures) {
		JavaFXRenderTarget::live_sampler_rids.erase(entry.second.rid);
		if (entry.second.target.is_null() && entry.second.scene.is_null()) rs->free_rid(entry.second.rid);
	}
	textures.clear();
	draw_recorded = false;
	draw_code = String();
	compiled_draw_code = String();
	persistent_frames = false;
	clip_enabled = false;
	draw_parameters.clear();
}

void JavaFXRenderSurface::set_surface_size(const Size2i &p_size) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	ERR_FAIL_COND_MSG(p_size.x <= 0 || p_size.y <= 0 || p_size.x > 8192 || p_size.y > 8192, "Invalid JavaFX surface dimensions (1..8192).");
	surface_size = p_size;
	if (viewport.is_valid()) {
		RenderingServer::get_singleton()->viewport_set_size(viewport, p_size.x, p_size.y);
		update_presentation();
		if (background.is_valid()) set_background(background_color);
	}
}

void JavaFXRenderSurface::clear_commands() {
	clear_draw_resources();
	if (persistent_frames) RenderingServer::get_singleton()->viewport_set_clear_mode(viewport, RSE::VIEWPORT_CLEAR_ONLY_NEXT_FRAME);
}

void JavaFXRenderSurface::clear_draw_resources() {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	RenderingServer::get_singleton()->canvas_item_clear(commands);
	free_retained_draws();
	RenderingServer::get_singleton()->canvas_item_set_draw_index(commands, 0);
	draw_recorded = false;
	meshes.clear();
	retained_meshes.clear();
	sampled_targets.clear();
	sampled_scenes.clear();
	// Clear invalidates sampler bindings before their retained RIDs are freed.
	clip_enabled = false;
	set_draw_shader_parameters(Dictionary());
	free_retired_textures();
	// Clearing Canvas commands does not complete queued RD draws. Preserve
	// their texture revisions until a commit has drained the pending batches;
	// otherwise a later upload may overwrite a texture still awaiting sampling.
	{
		for (auto &entry : textures) entry.second.referenced = false;
	}
}

void JavaFXRenderSurface::begin_present() {
	ERR_FAIL_COND(!Thread::is_main_thread() || !viewport.is_valid());
	clear_draw_resources();
	persistent_frames = true;
	auto *rs = RenderingServer::get_singleton();
	rs->viewport_set_clear_mode(viewport, RSE::VIEWPORT_CLEAR_NEVER);
	rs->viewport_set_update_mode(viewport, RSE::VIEWPORT_UPDATE_DISABLED);
}

void JavaFXRenderSurface::commit_present() {
	ERR_FAIL_COND(!Thread::is_main_thread() || !viewport.is_valid());
	RenderingServer::get_singleton()->viewport_set_update_mode(viewport, RSE::VIEWPORT_UPDATE_ONCE);
}

void JavaFXRenderSurface::finish_present() {
	ERR_FAIL_COND(!Thread::is_main_thread() || !viewport.is_valid());
	clear_draw_resources();
}

void JavaFXRenderSurface::add_prism_quads(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors, const Transform2D &p_transform, float p_modulate) {
	draw_prism_quads(p_vertices, p_colors, p_transform, texture, p_modulate);
}

void JavaFXRenderSurface::draw_prism_quads(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors, const Transform2D &p_transform, RID p_texture, float p_modulate) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	// Vertices are local-space; the transform rides on a transform command.
	// Identical batches across frames (e.g. a translating parent) reuse the
	// cached mesh instead of rebuilding one per frame.
	static const bool cache_meshes = OS::get_singleton()->get_environment("GODOT_JFX_MESH_CACHE") != "0";
	Ref<ArrayMesh> mesh;
	if (cache_meshes) {
		PrismMeshCache::Key key = PrismMeshCache::hash(p_vertices, p_colors);
		mesh = mesh_cache.get(key, p_vertices, p_colors);
		if (mesh.is_null()) {
			build_prism_mesh(mesh, p_vertices, p_colors);
			ERR_FAIL_COND(mesh.is_null());
			mesh_cache.put(key, mesh, p_vertices, p_colors);
		}
	} else {
		build_prism_mesh(mesh, p_vertices, p_colors);
		ERR_FAIL_COND(mesh.is_null());
		meshes.push_back(mesh);
	}
	draw_prism_mesh(mesh, p_transform, p_texture, p_modulate);
}

void JavaFXRenderSurface::draw_prism_mesh(const Ref<ArrayMesh> &p_mesh, const Transform2D &p_transform, RID p_texture, float p_modulate) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid() || p_mesh.is_null());
	if (!retained_meshes.has(p_mesh->get_rid())) retained_meshes.insert(p_mesh->get_rid(), p_mesh);
	// The transform must ride on a transform command, not on the mesh draw:
	// Item::get_rect() ignores CommandMesh::transform when computing the cull
	// rect but does apply CommandTransform, so a translated mesh command would
	// be culled away. The shared commands item accumulates more draws after
	// this batch, so reset the transform to identity right after the mesh.
	auto *rs = RenderingServer::get_singleton();
	if (p_transform != Transform2D()) rs->canvas_item_add_set_transform(commands, p_transform);
	rs->canvas_item_add_mesh(commands, p_mesh->get_rid(), Transform2D(), Color(p_modulate, p_modulate, p_modulate, p_modulate), p_texture);
	if (p_transform != Transform2D()) rs->canvas_item_add_set_transform(commands, Transform2D());
	draw_recorded = true;
}

void JavaFXRenderSurface::add_prism_mesh(const Ref<ArrayMesh> &p_mesh, const Transform2D &p_transform, float p_modulate) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	draw_prism_mesh(p_mesh, p_transform, texture, p_modulate);
}

void JavaFXRenderSurface::add_textured_mesh(uint64_t p_handle, const Ref<ArrayMesh> &p_mesh, const Transform2D &p_transform, float p_modulate) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	auto found = textures.find(p_handle);
	ERR_FAIL_COND(found == textures.end());
	draw_prism_mesh(p_mesh, p_transform, found->second.rid, p_modulate);
	found->second.referenced = true;
}

void JavaFXRenderSurface::prepare_draw_state() {
	auto *rs = RenderingServer::get_singleton();
	// Recorded CanvasItem commands reference live material state. Freeze that
	// item before changing state, preserving submission order as canvas siblings.
	if (draw_recorded) {
		retained_draws.push_back({ commands, draw_material, draw_shader });
		commands = rs->canvas_item_create();
		rs->canvas_item_set_parent(commands, canvas);
		rs->canvas_item_set_draw_index(commands, retained_draws.size());
		draw_material = RID(); draw_shader = RID();
		draw_recorded = false;
	}
	const bool new_shader = !draw_shader.is_valid();
	if (new_shader) {
		draw_shader = rs->shader_create(); draw_material = rs->material_create();
		rs->material_set_shader(draw_material, draw_shader);
		rs->canvas_item_set_material(commands, draw_material);
	}
	// Uniform/clip changes and pass cleanup do not change shader source.
	// Re-submitting identical code invalidates Godot's compiled shader and
	// material pipelines, turning every target transition into compilation.
	if (new_shader || compiled_draw_code != draw_code) {
		rs->shader_set_code(draw_shader, draw_code);
		compiled_draw_code = draw_code;
	}
	rs->canvas_item_set_custom_rect(commands, clip_enabled, clip_rect);
	rs->canvas_item_set_clip(commands, clip_enabled);
	for (const Variant &key : draw_parameters.keys()) {
		rs->material_set_param(draw_material, key, draw_parameters[key]);
	}
}

void JavaFXRenderSurface::free_retained_draws() {
	auto *rs = RenderingServer::get_singleton();
	for (const DrawSegment &segment : retained_draws) {
		rs->free_rid(segment.item);
		rs->free_rid(segment.material);
		rs->free_rid(segment.shader);
	}
	retained_draws.clear();
}

void JavaFXRenderSurface::set_draw_shader_code(const String &p_code) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	if (!draw_recorded) {
		for (const Variant &key : draw_parameters.keys()) RenderingServer::get_singleton()->material_set_param(draw_material, key, Variant());
	}
	draw_code = p_code;
	draw_parameters.clear();
	prepare_draw_state();
}

void JavaFXRenderSurface::set_draw_shader_parameters(const Dictionary &p_parameters) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	if (!draw_recorded) {
		for (const Variant &key : draw_parameters.keys()) RenderingServer::get_singleton()->material_set_param(draw_material, key, Variant());
	}
	draw_parameters = p_parameters.duplicate(true);
	prepare_draw_state();
}

RID JavaFXRenderSurface::retain_sampler_texture(uint64_t p_handle) {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), RID());
	auto found = textures.find(p_handle);
	ERR_FAIL_COND_V(found == textures.end(), RID());
	found->second.referenced = true;
	JavaFXRenderTarget::live_sampler_rids.insert(found->second.rid);
	return found->second.rid;
}

void JavaFXRenderSurface::set_draw_clip(bool p_enabled, const Rect2i &p_rect) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	if (clip_enabled == p_enabled && (!p_enabled || clip_rect == p_rect)) return;
	clip_enabled = p_enabled;
	clip_rect = p_rect;
	prepare_draw_state();
}

void JavaFXRenderSurface::add_rectangle(const Rect2 &p_rect, const Color &p_color) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	RenderingServer::get_singleton()->canvas_item_add_rect(commands, p_rect, Color(p_color.r * p_color.a, p_color.g * p_color.a, p_color.b * p_color.a, p_color.a));
	draw_recorded = true;
}

void JavaFXRenderSurface::upload_rgba(const Size2i &p_size, const PackedByteArray &p_pixels) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	ERR_FAIL_COND(p_size.x <= 0 || p_size.y <= 0 || p_size.x > 8192 || p_size.y > 8192);
	ERR_FAIL_COND_MSG(p_pixels.size() != int64_t(p_size.x) * p_size.y * 4, "RGBA upload length does not match dimensions.");
	// M1 supports one immutable upload per surface. Replacing a referenced
	// texture needs transactional lifetime handling in the command bridge.
	ERR_FAIL_COND_MSG(texture.is_valid(), "Clear/recreate the surface before replacing the M1 texture.");
	PackedByteArray premultiplied = p_pixels;
	uint8_t *bytes = premultiplied.ptrw();
	for (int64_t i = 0; i < premultiplied.size(); i += 4) {
		for (int channel = 0; channel < 3; ++channel) bytes[i + channel] = (uint32_t(bytes[i + channel]) * bytes[i + 3] + 127) / 255;
	}
	Ref<Image> image = Image::create_from_data(p_size.x, p_size.y, false, Image::FORMAT_RGBA8, premultiplied);
	texture = RenderingServer::get_singleton()->texture_2d_create(image);
}

void JavaFXRenderSurface::add_texture(const Rect2 &p_rect, const Color &p_modulate) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid() || !texture.is_valid());
	Color premultiplied_modulate(p_modulate.r * p_modulate.a, p_modulate.g * p_modulate.a, p_modulate.b * p_modulate.a, p_modulate.a);
	RenderingServer::get_singleton()->canvas_item_add_texture_rect(commands, p_rect, texture, false, premultiplied_modulate);
	draw_recorded = true;
}

void JavaFXRenderSurface::set_shader_code(const String &p_code) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !presentation.is_valid());
	auto *rs = RenderingServer::get_singleton();
	if (!shader.is_valid()) {
		shader = rs->shader_create();
		material = rs->material_create();
		rs->material_set_shader(material, shader);
		rs->canvas_item_set_material(presentation, material);
	}
	rs->shader_set_code(shader, p_code);
}

void JavaFXRenderSurface::add_render_target(const Ref<JavaFXRenderTarget> &p_target, const Rect2 &p_rect, float p_opacity) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid() || p_target.is_null());
	ERR_FAIL_COND(!Math::is_finite(p_opacity) || p_opacity < 0 || p_opacity > 1);
	RID source = p_target->get_texture();
	ERR_FAIL_COND(!source.is_valid());
	RenderingServer::get_singleton()->canvas_item_add_texture_rect(commands, p_rect, source, false, Color(p_opacity,p_opacity,p_opacity,p_opacity));
	sampled_targets.push_back(p_target);
	draw_recorded = true;
}

void JavaFXRenderSurface::add_scene_view(const Ref<JavaFXSceneView> &p_scene, const Rect2 &p_rect) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid() || p_scene.is_null());
	RID source = p_scene->get_texture();
	ERR_FAIL_COND(!source.is_valid());
	RenderingServer::get_singleton()->canvas_item_add_texture_rect(commands, p_rect, source);
	sampled_scenes.push_back(p_scene);
	draw_recorded = true;
}

Dictionary JavaFXRenderSurface::get_texture_resource_stats() const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), Dictionary());
	Dictionary result;
	Array live, retired;
	int shared_target_meshes = 0;
	for (const auto &entry : textures) {
		Dictionary item;
		item["handle"] = int64_t(entry.first);
		item["referenced"] = entry.second.referenced;
		if (entry.second.target.is_valid()) {
			item["size"] = entry.second.target->get_size();
			item["references"] = entry.second.target->get_reference_count();
			item["owned"] = entry.second.target->get_owned_resource_count();
			item["meshes"] = entry.second.target->get_cached_mesh_count();
			shared_target_meshes = MAX(shared_target_meshes, entry.second.target->get_cached_mesh_count());
			item["shaders"] = entry.second.target->get_cached_shader_count();
			item["materials"] = entry.second.target->get_cached_material_count();
			item["slots"] = entry.second.target->get_draw_slot_count();
		}
		live.push_back(item);
	}
	for (const auto &target : retired_targets) retired.push_back(target->get_size());
	result["live"] = live; result["retired_targets"] = retired;
	result["surface_meshes"] = get_cached_mesh_count();
	result["shared_target_meshes"] = shared_target_meshes;
	result["retired_textures"] = int64_t(retired_textures.size());
	return result;
}

int JavaFXRenderSurface::get_owned_resource_count() const {
	int target_resources = 0;
	for (const auto &entry : textures) if (entry.second.target.is_valid()) target_resources += entry.second.target->get_owned_resource_count() - 1;
	for (const auto &target : retired_targets) target_resources += target->get_owned_resource_count();
	return int(viewport.is_valid()) + int(canvas.is_valid()) + int(commands.is_valid()) +
			int(presentation.is_valid()) + int(texture.is_valid()) + int(shader.is_valid()) + int(material.is_valid()) + int(background.is_valid()) +
			int(draw_shader.is_valid()) + int(draw_material.is_valid()) + meshes.size() + int(textures.size()) + retired_textures.size() + retained_draws.size() * 3 + target_resources;
}

void JavaFXRenderSurface::free_retired_textures() {
	for (RID rid : retired_textures) {
		JavaFXRenderTarget::live_sampler_rids.erase(rid);
		RenderingServer::get_singleton()->free_rid(rid);
	}
	retired_textures.clear();
	retired_targets.clear();
	retired_scenes.clear();
}

void JavaFXRenderSurface::put_texture(uint64_t p_handle, const Size2i &p_size, const PackedByteArray &p_pixels) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	ERR_FAIL_COND(p_pixels.size() != int64_t(p_size.x) * p_size.y * 4);
	Ref<Image> image = Image::create_from_data(p_size.x, p_size.y, false, Image::FORMAT_RGBA8, p_pixels);
	store_texture_image(p_handle, image);
}

void JavaFXRenderSurface::store_texture_image(uint64_t p_handle, const Ref<Image> &p_image) {
	auto previous = textures.find(p_handle);
	auto *rs = RenderingServer::get_singleton();
	RID replacement;
	if (previous != textures.end() && !previous->second.referenced) {
		replacement = previous->second.rid;
		rs->texture_2d_update(replacement, p_image);
	} else {
		replacement = rs->texture_2d_create(p_image);
		if (previous != textures.end()) retired_textures.push_back(previous->second.rid);
	}
	textures[p_handle] = { replacement, p_image, false };
}

void JavaFXRenderSurface::allocate_texture(uint64_t p_handle, const Size2i &p_size, bool p_floating, bool p_single_channel) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !commands.is_valid());
	Ref<Image> image = Image::create_empty(p_size.x, p_size.y, false, p_single_channel ? Image::FORMAT_R8 : p_floating ? Image::FORMAT_RGBAF : Image::FORMAT_RGBA8);
	image->fill(Color(0, 0, 0, 0));
	store_texture_image(p_handle, image);
}

bool JavaFXRenderSurface::is_single_channel_texture(uint64_t p_handle) const {
    auto found=textures.find(p_handle);
    return found!=textures.end() && found->second.image.is_valid() && found->second.image->get_format()==Image::FORMAT_R8;
}

void JavaFXRenderSurface::allocate_render_target(uint64_t p_handle, const Size2i &p_size) {
	ERR_FAIL_COND(!Thread::is_main_thread() || textures.count(p_handle));
	Ref<JavaFXRenderTarget> target; target.instantiate();
	ERR_FAIL_COND(!target->initialize(p_size));
	target->begin_pass(true); target->end_pass();
	textures[p_handle] = { target->get_texture(), Ref<Image>(), false, target };
}

bool JavaFXRenderSurface::allocate_scene_texture(uint64_t p_handle, const Size2i &p_size, const String &p_path) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || textures.count(p_handle), false);
	Ref<JavaFXSceneView> scene; scene.instantiate();
	if (!scene->initialize(this, p_path, p_size)) return false;
	textures[p_handle] = { scene->get_texture(), Ref<Image>(), false, Ref<JavaFXRenderTarget>(), scene };
	return true;
}

double JavaFXRenderSurface::get_offscreen_gpu_time_us() const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), 0.0);
	double total = 0.0;
	for (const auto &entry : textures)
		if (entry.second.target.is_valid()) total += entry.second.target->get_measured_gpu_time_us();
	return total;
}

Ref<JavaFXRenderTarget> JavaFXRenderSurface::get_render_target(uint64_t p_handle) const {
	auto found = textures.find(p_handle);
	ERR_FAIL_COND_V(found == textures.end() || found->second.target.is_null(), Ref<JavaFXRenderTarget>());
	return found->second.target;
}

Ref<JavaFXRenderTarget> JavaFXRenderSurface::find_render_target(uint64_t p_handle) const {
	auto found = textures.find(p_handle);
	return found == textures.end() ? Ref<JavaFXRenderTarget>() : found->second.target;
}

void JavaFXRenderSurface::resize_scene_texture(uint64_t p_handle, uint64_t p_source, const Size2i &p_size) {
	ERR_FAIL_COND(!Thread::is_main_thread() || textures.count(p_handle));
	auto previous = textures.find(p_source);
	ERR_FAIL_COND(previous == textures.end() || previous->second.scene.is_null() || previous->second.referenced);
	Ref<JavaFXSceneView> scene = previous->second.scene;
	scene->resize(p_size);
	textures.erase(previous);
	textures[p_handle] = {scene->get_texture(), Ref<Image>(), false, Ref<JavaFXRenderTarget>(), scene};
}

void JavaFXRenderSurface::scene_input(uint64_t p_handle, uint32_t p_kind, uint32_t p_flags, uint32_t p_code, uint32_t p_unicode, Vector2 p_position, Vector2 p_relative) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	auto found = textures.find(p_handle);
	ERR_FAIL_COND(found == textures.end() || found->second.scene.is_null());
	found->second.scene->dispatch_input(p_kind,p_flags,p_code,p_unicode,p_position,p_relative);
}

Dictionary JavaFXRenderSurface::get_texture_patch_profile() const {
	Dictionary result;
	result["profile_patch_copy_us"] = patch_copy_us;
	result["profile_patch_blit_us"] = patch_blit_us;
	result["profile_patch_submit_us"] = patch_submit_us;
	result["profile_patch_region_count"] = patch_region_count;
	result["profile_patch_replace_count"] = patch_replace_count;
	result["profile_patch_update_count"] = patch_update_count;
	result["profile_patch_input_bytes"] = patch_input_bytes;
	result["profile_patch_full_bytes"] = patch_full_bytes;
	result["profile_patch_reuse_count"] = patch_reuse_count;
	result["profile_patch_clone_count"] = patch_clone_count;
	return result;
}

void JavaFXRenderSurface::patch_texture(uint64_t p_handle, const Rect2i &p_region, const PackedByteArray &p_pixels) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	ERR_FAIL_COND_MSG(!RenderingServer::get_singleton()->is_on_render_thread(), "JavaFX texture uploads require --render-thread safe.");
	auto found = textures.find(p_handle);
	ERR_FAIL_COND(found == textures.end());
	static const bool profile = OS::get_singleton()->get_environment("GODOT_JFX_PROFILE_COMMANDS") == "1";
	static const bool reuse_enabled = OS::get_singleton()->get_environment("GODOT_JFX_REUSE_SHADOW") != "0";
	const uint64_t copy_start = profile ? OS::get_singleton()->get_ticks_usec() : 0;
	if (p_region.position == Point2i() && p_region.size == found->second.image->get_size()) {
		// Video planes usually replace the whole texture. The owned incoming
		// pixels already are the new shadow: cloning and blitting the old full
		// image adds a second per-pixel pass without preserving any content.
		Ref<Image> replacement = Image::create_from_data(p_region.size.x, p_region.size.y, false, found->second.image->get_format(), p_pixels);
		const uint64_t submit_start = profile ? OS::get_singleton()->get_ticks_usec() : 0;
		if (profile) {
			patch_copy_us += submit_start - copy_start;
			patch_input_bytes += p_pixels.size(); patch_full_bytes += p_pixels.size();
			if (found->second.referenced) ++patch_replace_count; else ++patch_update_count;
		}
		store_texture_image(p_handle, replacement);
		if (profile) patch_submit_us += OS::get_singleton()->get_ticks_usec() - submit_start;
		return;
	}
	// Queued uploads/caches retain their Image reference. Only mutate the
	// private shadow; shared pixel buffers still retain their own COW protection.
	const bool reuse = reuse_enabled && found->second.image->get_reference_count() == 1;
	Ref<Image> image;
	if (reuse) image = found->second.image;
	else image = found->second.image->duplicate();
	const uint64_t blit_start = profile ? OS::get_singleton()->get_ticks_usec() : 0;
	Ref<Image> patch = Image::create_from_data(p_region.size.x, p_region.size.y, false, image->get_format(), p_pixels);
	image->blit_rect(patch, Rect2i(Point2i(), p_region.size), p_region.position);
	const uint64_t submit_start = profile ? OS::get_singleton()->get_ticks_usec() : 0;
	if (profile) {
		if (reuse) ++patch_reuse_count; else ++patch_clone_count;
		patch_copy_us += blit_start - copy_start;
		patch_blit_us += submit_start - blit_start;
		patch_input_bytes += p_pixels.size();
		patch_full_bytes += image->get_data().size();
	}
	if (!found->second.referenced &&
			(image->get_format() == Image::FORMAT_RGBA8 || image->get_format() == Image::FORMAT_RGBAF) &&
			OS::get_singleton()->get_environment("GODOT_JFX_REGION_UPLOAD") != "0") {
		// Safe mode uploads the packed patch synchronously in command order.
		RSG::texture_storage->texture_2d_update_region(found->second.rid, patch, p_region);
		found->second.image = image;
		if (profile) { ++patch_region_count; patch_submit_us += OS::get_singleton()->get_ticks_usec() - submit_start; }
		return;
	}
	if (profile) { if (found->second.referenced) ++patch_replace_count; else ++patch_update_count; }
	store_texture_image(p_handle, image);
	if (profile) patch_submit_us += OS::get_singleton()->get_ticks_usec() - submit_start;
}

void JavaFXRenderSurface::dispose_texture(uint64_t p_handle) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	auto found = textures.find(p_handle);
	ERR_FAIL_COND(found == textures.end());
	JavaFXRenderTarget::live_sampler_rids.erase(found->second.rid);
	// Commands already submitted to this canvas retain their texture revision
	// until clear; disposal only invalidates subsequent logical handle uses.
	if (found->second.scene.is_valid()) {
		if (found->second.referenced) retired_scenes.push_back(found->second.scene);
	} else if (found->second.target.is_valid()) {
		if (found->second.referenced) retired_targets.push_back(found->second.target);
	} else if (found->second.referenced) retired_textures.push_back(found->second.rid);
	else RenderingServer::get_singleton()->free_rid(found->second.rid);
	textures.erase(found);
}

void JavaFXRenderSurface::add_textured_quads(uint64_t p_handle, const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors, const Transform2D &p_transform, float p_modulate) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	auto found = textures.find(p_handle);
	ERR_FAIL_COND(found == textures.end());
	draw_prism_quads(p_vertices, p_colors, p_transform, found->second.rid, p_modulate);
	found->second.referenced = true;
}

void JavaFXRenderSurface::set_background(const Color &p_color) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !canvas.is_valid());
	auto *rs = RenderingServer::get_singleton();
	if (!background.is_valid()) {
		background = rs->canvas_item_create();
		// Window background belongs behind the presented texture, not inside
		// the persistent framebuffer where it would erase every dirty update.
		rs->canvas_item_set_parent(background, get_canvas_item());
		rs->canvas_item_set_draw_index(background, -1);
	}
	background_color = p_color;
	rs->canvas_item_clear(background);
	rs->canvas_item_add_rect(background, Rect2(Vector2(), surface_size), p_color);
}

JavaFXRenderSurface::~JavaFXRenderSurface() {
	release();
}
