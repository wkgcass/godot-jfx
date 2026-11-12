#pragma once

#include "javafx_window_surface.h"
#include "javafx_native_window.h"
#include "windows_dnd.h"
#include "prism_mesh.h"
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
#include "javafx_rd_direct.h"
#endif

#include <memory>
#include <thread>
#include <set>

namespace godot_javafx { struct Runtime; }

class CanvasLayer;
class ColorRect;
class TextureRect;

class JavaFXHost : public JavaFXWindowSurface {
	GDCLASS(JavaFXHost, JavaFXWindowSurface);
	std::shared_ptr<godot_javafx::Runtime> runtime;
	std::thread worker;
	uint64_t applied_sequence = 0;
	bool reported_failure = false;
	bool previous_auto_accept_quit = true;
	bool present_pending = false;
	bool offscreen_pass_pending = false;
	bool completing_presentation = false;
	uint64_t completed_presentations = 0;
	uint64_t process_ticks = 0;
	uint64_t offscreen_passes = 0;
	uint64_t immediate_passes = 0;
	// Geometry deduplication observability: full uploads vs handle references.
	uint64_t quads_uploaded = 0, quads_referenced = 0;
	uint64_t process_us = 0, encode_us = 0, metadata_us = 0, host_commands_us = 0;
	uint64_t draw_sync_us = 0, draw_sync_calls = 0, max_draw_sync_us = 0;
	uint64_t direct_offscreen_calls = 0, direct_offscreen_us = 0, direct_offscreen_render_us = 0;
	uint64_t direct_presentation_passes = 0;
	bool profile_commands = false;
	bool gpu_timing_enabled = false;
	// HOVER_TAP stall probes (GODOT_JFX_HOVER_TAP=1): tick-gap and phase timing.
	bool hover_tap_probe = false;
	uint64_t hover_tap_epoch_us = 0;
	uint64_t hover_tap_last_tick_us = 0, hover_tap_last_body_us = 0, hover_tap_last_pipes = 0;
	uint64_t hover_tap_last_tex_mem = 0, hover_tap_last_buf_mem = 0;
	double window_gpu_time_us = 0.0;
	uint64_t profile_texture_us = 0, profile_target_us = 0, profile_geometry_us = 0, profile_shader_us = 0;
	uint64_t profile_shader_creations = 0;
	bool compose_target = false;
	int64_t pending_window_id = 0;
	bool pending_window_native = false;
	int64_t pending_native_composition = 0;
	std::set<int64_t> native_presentations;
	Rect2 pending_window_rect;
	int pending_window_z = 0;
	float pending_window_opacity = 1;
	bool ime_enabled = false;
	bool custom_cursor_active = false;
	bool cursor_visible = true, cursor_none_requested = false, managed_cursor_state = false;
	int previous_mouse_mode = 0;
	int previous_default_cursor_shape = 0;
	bool default_cursor_state_saved = false;
	// Per-window held mouse buttons (Glass modifier bits), tracked from the
	// press/release stream. Re-applied to motion masks and used to suppress
	// enter/exit notifications while a drag owns the pointer.
	std::map<int64_t, uint32_t> held_buttons;
	// Frame-protocol geometry deduplication: handle -> resident mesh. Filled
	// when a QUADS command tags fresh content, read by QUADS_REF, retired by
	// GEOMETRY_FREE. Main-thread only; cleared when the JVM stops.
	HashMap<uint64_t, Ref<ArrayMesh>> geometry_meshes;
	// RD-direct mode consumes raw batch bytes instead of meshes; the same
	// handle maps to the decoded vertex/color pair.
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	HashMap<uint64_t, std::pair<PackedFloat32Array, PackedByteArray>> geometry_raw;
#endif

	// One-shot VSync pacing health check. Some Windows display states pace FIFO
	// presents far below the refresh rate (observed: a stable ~33 Hz plateau on
	// a 60 Hz panel, while native D3D windows stay at 60). Windowed presents are
	// DWM-composited; disabling VSync and pacing on the CPU helped that observed
	// case, but low cadence alone does not establish its cause. Explicit engine
	// FPS caps are preserved. Opt out with GODOT_JFX_VSYNC_FALLBACK=0.
	uint64_t vsync_probe_begin_us = 0;
	uint64_t vsync_probe_prev_us = 0;
	uint64_t vsync_probe_sum_us = 0;
	uint32_t vsync_probe_count = 0;
	bool vsync_probe_done = false;
	int fallback_fps = 0;
	void check_vsync_pacing(uint64_t p_now_us);
	void restore_vsync_pacing();
	void refresh_custom_cursor_info();
	Dictionary custom_cursor_info;
	String ime_text;
	int ime_caret = 0;
	Point2i ime_position;
	Ref<JavaFXRenderTarget> active_target;
	String target_shader;
	Dictionary target_parameters;
	HashMap<StringName, Variant> target_instance_params;
	bool target_clip = false;
	struct NativeWindowEntry {
		JavaFXNativeWindow *window;
		int64_t owner;
		bool input_enabled = true;
		bool ime_enabled = false;
		String ime_text;
		int ime_caret = 0;
		Point2i ime_position;
	};
	std::map<int64_t, NativeWindowEntry> native_windows;
	int64_t native_window_sequence = 0;
	// OLE drag-in handlers per hosted Window, installed as DisplayServerWindows
	// drag delegates; the delegate userdata points at the TargetHandler.
	std::map<Window *, std::unique_ptr<godot_javafx::windows_dnd::TargetHandler>> drag_targets;
	void refresh_drag_delegates();
	void run_dnd_source(std::unique_ptr<godot_javafx::windows_dnd::SourceData> p_data);
	void apply_native_window_commands();
	Rect2i target_clip_rect;
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	godot_javafx::rd_direct::CycleState rd_cycle_state;
#endif

	bool startup_enabled = false;
	bool startup_logo_enabled = false;
	bool startup_consumed = false;
	bool startup_active = false;
	bool startup_frame_ready = false;
	bool startup_window_shown = false;
	bool startup_logo_drawn = false;
	int64_t startup_window_id = 0;
	int64_t completing_window_id = 0;
	uint64_t startup_logo_begin_us = 0;
	uint64_t startup_fade_begin_us = 0;
	uint64_t startup_logo_count = 0;
	int startup_previous_update_mode = -1;
	CanvasLayer *startup_overlay = nullptr;
	ColorRect *startup_background = nullptr;
	TextureRect *startup_image = nullptr;
	Window *startup_window() const;
	bool startup_show(int64_t p_id, bool p_visible);
	void startup_tick();
	void startup_post_draw();
	void startup_cancel();
	Dictionary get_startup_status() const;

	void frame_presented();
	void finish_pending_pass(bool p_target_drawn);
	void complete_offscreen_pass();
	void apply_host_commands();
	// Second application point late in the frame (RenderingServer frame_pre_draw,
	// always main thread): window commands produced in response to this frame's
	// input take effect on the same display frame instead of the next one.
	void pre_draw_host_commands();
	void apply_readback();
	void refresh_host_info();
	void request_window_focus(Window *p_window);
	void restack_window(Window *p_window, bool p_front);
	bool refresh_native_owners(int64_t p_hidden_owner = 0);
	void set_window_input_enabled(int64_t p_id, bool p_enabled);
	void window_ime_command(int64_t p_id, int p_operation, int p_a, int p_b);
	void window_input(const Ref<InputEvent> &p_event, int64_t p_id);
	void window_event(int p_kind, int64_t p_id);

protected:
	static void _bind_methods();
	void _notification(int p_what);
	void input(const Ref<InputEvent> &p_event) override;

public:
	static bool is_rd_direct_compiled() {
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
		return true;
#else
		return false;
#endif
	}
	bool create_native_window(int64_t p_id, int64_t p_owner, const Rect2i &p_bounds, const String &p_title, int p_flags);
	bool configure_native_window(int64_t p_id, const Rect2i &p_bounds, bool p_visible);
	bool set_native_window_property(int64_t p_id, int p_property, int p_a, int p_b, const String &p_text);
	Dictionary get_native_window_info(int64_t p_id) const;
	JavaFXNativeWindow *get_native_window(int64_t p_id) const;
	void destroy_native_window(int64_t p_id);
	int get_native_window_count() const { return native_windows.size(); }
	bool is_window_input_enabled(int64_t p_id) const;
	bool is_window_visible(int64_t p_id) const;
	bool is_window_above(int64_t p_id, int64_t p_other) const;
	bool start_jvm(const String &p_jdk, const String &p_sdk, const String &p_classpath, const String &p_main_class);
	void stop_jvm();
	String get_runtime_status() const;
	String get_runtime_error() const;
	int64_t get_applied_sequence() const { return applied_sequence; }
	int64_t get_completed_presentations() const { return completed_presentations; }
	int64_t get_backpressure_count() const;
	Dictionary get_render_stats() const;
	// Spike: cost of one offscreen viewport render cycle with K draw items.
	Dictionary benchmark_offscreen_cycle(int p_items, int p_count);
	// RD-direct backend P1 prototype: raw RenderingDevice offscreen cycle plus
	// the texture-ledger bridge. Resources stay alive until release_rd_cycle.
	Dictionary benchmark_rd_cycle(int p_items, int p_count, RID p_parent_item);
	// P2 translate probe: same canvas shader batch through the viewport path
	// and the translated RD pipeline, compared pixel by pixel. Two-phase: the
	// engine frame renders the reference between phase A and finish.
	Dictionary rd_translate_probe(const String &p_shader, RID p_texture, RID p_parent_item);
	Dictionary rd_translate_probe_finish();
	void release_rd_cycle();
	double get_offscreen_gpu_time_us() const { return JavaFXRenderSurface::get_offscreen_gpu_time_us(); }
	void set_window_gpu_time_us(double p_us) { window_gpu_time_us = p_us; }
	bool has_pending_readback() const;
	Dictionary get_custom_cursor_info() const { return custom_cursor_info; }
	Dictionary get_window_icon_info(int64_t p_id) const;
	bool is_ime_active() const { return ime_enabled; }
	void update_ime_composition(const String &p_text, int p_caret);
	void update_window_ime_composition(int64_t p_id, const String &p_text, int p_caret);
	bool simulate_external_drop(const Vector2i &p_point, const String &p_text, const String &p_url, const PackedStringArray &p_files, const String &p_custom_name, const PackedByteArray &p_custom_data);
	~JavaFXHost();
};
