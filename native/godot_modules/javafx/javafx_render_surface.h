#pragma once

#include "scene/2d/node_2d.h"
#include "scene/resources/mesh.h"
#include <unordered_map>
#include "core/io/image.h"
#include "javafx_render_target.h"
#include "javafx_scene_view.h"
#include "prism_mesh.h"

// Main-thread resource owner for an offscreen JavaFX rendering surface.
// The M1 API exercises RenderingServer directly. JNI command consumption is
// deliberately separate: Java render threads must never call these methods.
class JavaFXRenderSurface : public Node2D {
	GDCLASS(JavaFXRenderSurface, Node2D);

	RID viewport;
	RID canvas;
	RID commands;
	RID presentation;
	RID texture;
	RID shader;
	RID material;
	RID background;
	RID draw_shader;
	RID draw_material;
	struct DrawSegment { RID item, material, shader; };
	Vector<DrawSegment> retained_draws;
	bool draw_recorded = false;
	String draw_code;
	String compiled_draw_code;
	Dictionary draw_parameters;
	bool clip_enabled = false;
	Rect2i clip_rect;
	bool persistent_frames = false;
	Vector<Ref<ArrayMesh>> meshes;
	// Canvas commands carry RIDs, not Ref<ArrayMesh>. Cache eviction and
	// GEOMETRY_FREE must not invalidate meshes still used by this draw list.
	HashMap<RID, Ref<ArrayMesh>> retained_meshes;
	PrismMeshCache mesh_cache;
	Vector<Ref<JavaFXRenderTarget>> sampled_targets;
	Vector<Ref<JavaFXSceneView>> sampled_scenes;
	struct TextureRecord { RID rid; Ref<Image> image; bool referenced = false; Ref<JavaFXRenderTarget> target; Ref<JavaFXSceneView> scene; };
	std::unordered_map<uint64_t, TextureRecord> textures;
	Vector<RID> retired_textures;
	Vector<Ref<JavaFXRenderTarget>> retired_targets;
	Vector<Ref<JavaFXSceneView>> retired_scenes;
	Color background_color;
	Size2i surface_size = Size2i(320, 200);
	uint64_t patch_copy_us = 0, patch_blit_us = 0, patch_submit_us = 0;
	uint64_t patch_region_count = 0, patch_replace_count = 0, patch_update_count = 0;
	uint64_t patch_input_bytes = 0, patch_full_bytes = 0;
	uint64_t patch_reuse_count = 0, patch_clone_count = 0;

	void allocate();
	void release();
	void update_presentation();
	void draw_prism_quads(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors, const Transform2D &p_transform, RID p_texture, float p_modulate = 1.0f);
	void free_retired_textures();
public:
	// Sum of the most recent measured GPU render time of every tracked
	// offscreen target, in microseconds (measurement must be enabled).
	double get_offscreen_gpu_time_us() const;

private:
	void store_texture_image(uint64_t p_handle, const Ref<Image> &p_image);
	void prepare_draw_state();
	void free_retained_draws();
	void clear_draw_resources();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void set_surface_size(const Size2i &p_size);
	Dictionary get_texture_resource_stats() const;
	Dictionary get_texture_patch_profile() const;
	Size2i get_surface_size() const { return surface_size; }
	void clear_commands();
	void begin_present();
	void commit_present();
	void finish_present();
	void add_rectangle(const Rect2 &p_rect, const Color &p_color);
	void add_prism_quads(const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors, const Transform2D &p_transform, float p_modulate = 1.0f);
	// Geometry-deduplicated draws: redraw a host-resident mesh (registered by
	// the frame protocol's geometry handles) without re-decoding vertices.
	void draw_prism_mesh(const Ref<ArrayMesh> &p_mesh, const Transform2D &p_transform, RID p_texture, float p_modulate = 1.0f);
	void add_prism_mesh(const Ref<ArrayMesh> &p_mesh, const Transform2D &p_transform, float p_modulate = 1.0f);
	void add_textured_mesh(uint64_t p_handle, const Ref<ArrayMesh> &p_mesh, const Transform2D &p_transform, float p_modulate = 1.0f);
	void set_draw_shader_code(const String &p_code);
	void set_draw_shader_parameters(const Dictionary &p_parameters);
	RID retain_sampler_texture(uint64_t p_handle);
	void set_draw_clip(bool p_enabled, const Rect2i &p_rect);
	void put_texture(uint64_t p_handle, const Size2i &p_size, const PackedByteArray &p_premultiplied_pixels);
	void allocate_texture(uint64_t p_handle, const Size2i &p_size, bool p_floating = false, bool p_single_channel = false);
	bool is_single_channel_texture(uint64_t p_handle) const;
	void allocate_render_target(uint64_t p_handle, const Size2i &p_size);
	bool allocate_scene_texture(uint64_t p_handle, const Size2i &p_size, const String &p_path);
	void resize_scene_texture(uint64_t p_handle, uint64_t p_source, const Size2i &p_size);
	void scene_input(uint64_t p_handle, uint32_t p_kind, uint32_t p_flags, uint32_t p_code, uint32_t p_unicode, Vector2 p_position, Vector2 p_relative);
	Ref<JavaFXRenderTarget> get_render_target(uint64_t p_handle) const;
	Ref<JavaFXRenderTarget> find_render_target(uint64_t p_handle) const;
	void patch_texture(uint64_t p_handle, const Rect2i &p_region, const PackedByteArray &p_pixels);
	void dispose_texture(uint64_t p_handle);
	void add_textured_quads(uint64_t p_handle, const PackedFloat32Array &p_vertices, const PackedByteArray &p_colors, const Transform2D &p_transform, float p_modulate = 1.0f);
	void upload_rgba(const Size2i &p_size, const PackedByteArray &p_pixels);
	void add_texture(const Rect2 &p_rect, const Color &p_modulate);
	void add_render_target(const Ref<JavaFXRenderTarget> &p_target, const Rect2 &p_rect, float p_opacity = 1.0f);
	void add_scene_view(const Ref<JavaFXSceneView> &p_scene, const Rect2 &p_rect);
	void set_shader_code(const String &p_code);
	void set_background(const Color &p_color);
	int get_owned_resource_count() const;
	// Content-addressed mesh reuse is a bounded memo table, not per-draw
	// ownership; expose it separately from the hygiene count.
	int get_cached_mesh_count() const { return int(mesh_cache.size()); }
	~JavaFXRenderSurface();
};
