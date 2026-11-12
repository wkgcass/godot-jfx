#pragma once

#include "core/templates/rid.h"
#include "core/variant/dictionary.h"
#include "javafx_render_target.h"
#include "javafx_shader_translate.h"

// RenderingDevice diagnostic probes (RD-direct backend plan, P1/P2).
// Production RD offscreen passes live in javafx_rd_pass.h; JavaFXRenderTarget
// selects that implementation or the RenderingServer viewport path. This file
// owns separate probe resources for measuring raw cycle cost and comparing
// translated shaders against the viewport path, including canvas consumption.
namespace godot_javafx::rd_direct {

struct CycleState {
	// RD-side resources: texture, framebuffer, solid-quad pipeline and geometry.
	RID rd_texture, framebuffer, shader, pipeline;
	RID vertex_buffer, vertex_array, index_buffer, index_array;
	// P2 translate probe: sampler + uniform set binding the shared test
	// texture, plus the std140 buffer carrying seeded value uniforms.
	RID sampler, uniform_set, value_buffer;
	// Texture-ledger RID wrapping rd_texture (shared RD view) plus a temporary
	// canvas item drawing it, proving RD output is canvas-sampleable.
	RID bridge_texture, bridge_item;
	// Translate-probe previews: the RD result and the viewport-path result
	// drawn side by side; the target owns the viewport half's resources.
	Ref<JavaFXRenderTarget> viewport_target;
	RID preview_item_rd, preview_item_viewport;
	// Phase A -> engine frame -> phase B hand-off for the translate probe.
	bool phase_pending = false;
	RID probe_parent_item, probe_texture;
	RID probe_screen_texture; // Transparent stand-in for the dest snapshot.
	int probe_screen_index = -1;
	PackedByteArray probe_push;
	int probe_sampler_count = 0, probe_uniform_count = 0;
	godot_javafx::RdShaderSources probe_translated;
	bool active = false;
	int width = 0, height = 0;
};

// Renders p_count offscreen cycles of p_items quad draws into a fresh RD
// framebuffer at effect-pass resolution, verifies pixels by readback, bridges
// the texture into the texture ledger and (when p_parent_canvas_item is valid)
// shows it on a temporary canvas item. Rejects a pending translate phase too:
// both probes share this state. Caller must release via release_cycle.
Dictionary cycle_probe(int p_items, int p_count, RID p_parent_canvas_item, CycleState &p_state);

// P2 translate probe, phase A: records the identical batch with the same
// canvas shader on a viewport target (the engine frame renders it as the
// reference — immediate offscreen renders lose first-use array material
// uniforms) and creates every RD-side resource from the translated shader.
// The caller lets one engine frame pass, then translate_probe_finish compares.
Dictionary translate_probe(const String &p_canvas_shader, RID p_texture, RID p_parent_canvas_item, CycleState &p_state);

// Phase B: reads the engine-rendered reference back, renders the RD half and
// compares pixel by pixel; also shows both results side by side when a parent
// item was given. Caller must release via release_cycle afterwards.
Dictionary translate_probe_finish(CycleState &p_state);

// Required after success or failure before starting another probe; frees even
// partially created resources. The RD texture outlives the bridged
// shared view, so the ledger RID goes first.
void release_cycle(CycleState &p_state);

} // namespace godot_javafx::rd_direct
