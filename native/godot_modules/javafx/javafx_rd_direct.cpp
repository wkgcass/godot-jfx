#include "javafx_rd_direct.h"
#include "javafx_shader_translate.h"

#include "core/os/os.h"
#include "core/io/image.h"
#include "core/templates/vector.h"
#include "core/object/callable_mp.h"
#include "servers/rendering/rendering_server.h"
#include "servers/rendering/rendering_device.h"
#include "servers/rendering/rendering_server_globals.h"

#include <string.h>

namespace godot_javafx::rd_direct {

namespace {
// Minimal RD-native passthrough pipeline: the P1 prototype proves the device
// path (texture -> framebuffer -> render pass -> readback), not shading.
const char *VERTEX_GLSL = R"GLSL(#version 450
layout(location = 0) in vec2 vertex_position;
layout(location = 1) in vec4 vertex_color;
layout(location = 0) out vec4 color_interp;
void main() {
	color_interp = vertex_color;
	gl_Position = vec4(vertex_position, 0.0, 1.0);
}
)GLSL";

const char *FRAGMENT_GLSL = R"GLSL(#version 450
layout(location = 0) in vec4 color_interp;
layout(location = 0) out vec4 frag_color;
void main() {
	frag_color = color_interp;
}
)GLSL";

// Chosen so byte values survive the float->unorm roundtrip unambiguously.
const Color QUAD_COLOR(0.9f, 0.5f, 0.3f, 1.0f);
const Color CLEAR_COLOR(0.1f, 0.2f, 0.3f, 1.0f);
const Color TRANSPARENT_CLEAR(0.0f, 0.0f, 0.0f, 0.0f);
const int COLOR_TOLERANCE = 2;

Dictionary fail(const String &p_reason) {
	Dictionary result;
	result["error"] = p_reason;
	return result;
}

// RenderingDevice's mutating operations (draw lists, readback, free_rid) are
// render-thread-only, and the engine's main device forbids submit()/sync() —
// its command stream is driven by the frame loop, and texture_get_data flushes
// internally. The probe therefore marshals its render-thread half through the
// RenderingServer FIFO (like the production draw_offscreen_pass path) and
// measures the CPU-side cycle cost: draw-list encoding per pass. One probe
// runs at a time, so a single staging slot carries results back.
struct RenderOutput {
	Vector<uint8_t> readback;
	RID bridge_texture;
	RID uniform_set;
	uint64_t elapsed_us = 0;
	bool done = false;
};
RenderOutput g_render_output;

void render_once(RenderingDevice *p_rd, const RID &p_framebuffer, const RID &p_pipeline, const RID &p_vertex_array,
		const RID &p_index_array, int p_draws) {
	RD::DrawListID list = p_rd->draw_list_begin(p_framebuffer, RD::DRAW_CLEAR_COLOR_ALL, VectorView<Color>(&CLEAR_COLOR, 1), 1.0f, 0);
	if (p_draws > 0) {
		p_rd->draw_list_bind_render_pipeline(list, p_pipeline);
		p_rd->draw_list_bind_vertex_array(list, p_vertex_array);
		p_rd->draw_list_bind_index_array(list, p_index_array);
		for (int i = 0; i < p_draws; ++i) p_rd->draw_list_draw(list, true);
	}
	p_rd->draw_list_end();
}

void rd_render_job(RID p_framebuffer, RID p_pipeline, RID p_vertex_array, RID p_index_array, RID p_texture, int p_draws, int p_count) {
	RenderingDevice *rd = RenderingDevice::get_singleton();
	// Verification render; texture_get_data forces its own staging flush.
	render_once(rd, p_framebuffer, p_pipeline, p_vertex_array, p_index_array, p_draws);
	g_render_output.readback = rd->texture_get_data(p_texture, 0);
	// Steady-state CPU cost of one offscreen cycle: warmup, then the loop.
	// The engine's main device executes the recorded commands at frame end,
	// so unlike the viewport benchmark there is no device fence here; the
	// elapsed number is encode/submit CPU time per cycle.
	render_once(rd, p_framebuffer, p_pipeline, p_vertex_array, p_index_array, p_draws);
	const uint64_t start = OS::get_singleton()->get_ticks_usec();
	for (int i = 0; i < p_count; ++i) render_once(rd, p_framebuffer, p_pipeline, p_vertex_array, p_index_array, p_draws);
	g_render_output.elapsed_us = OS::get_singleton()->get_ticks_usec() - start;
	// The ledger wrapper reads RD texture state, so it must be created here
	// (its validation is render-thread-only); same pattern as the render
	// target's render-thread texture proxy initialization.
	RID bridge = RSG::texture_storage->texture_allocate();
	RSG::texture_storage->texture_rd_initialize(bridge, p_texture, RSE::TEXTURE_LAYERED_2D_ARRAY);
	g_render_output.bridge_texture = bridge;
	g_render_output.done = true;
}

void rd_dirty_update_job() {
	// The engine frame normally runs this on the render thread before drawing;
	// an immediate offscreen render must do it itself or first-use material
	// uniforms (array constants) read as zero.
	RSG::utilities->update_dirty_resources();
}


void rd_free_job(RID p_pipeline, RID p_shader, RID p_index_array, RID p_index_buffer, RID p_vertex_array,
		RID p_vertex_buffer, RID p_framebuffer, RID p_texture) {
	RenderingDevice *rd = RenderingDevice::get_singleton();
	for (RID rid : { p_pipeline, p_shader, p_index_array, p_index_buffer, p_vertex_array, p_vertex_buffer, p_framebuffer }) {
		if (rid.is_valid()) rd->free_rid(rid);
	}
	// Freed last so it always outlives the framebuffer that renders into it.
	if (p_texture.is_valid()) rd->free_rid(p_texture);
}

void rd_free_extra_job(RID p_uniform_set, RID p_sampler, RID p_value_buffer) {
	RenderingDevice *rd = RenderingDevice::get_singleton();
	if (p_uniform_set.is_valid() && rd->uniform_set_is_valid(p_uniform_set)) rd->free_rid(p_uniform_set);
	if (p_sampler.is_valid()) rd->free_rid(p_sampler);
	if (p_value_buffer.is_valid()) rd->free_rid(p_value_buffer);
}

// Translate-probe render half: builds the uniform set on the render thread
// (the ledger's RD view of the shared texture must not race the FIFO) —
// samplers at bindings 0..n-1 and the std140 value buffer at binding n —
// draws the quad through the translated pipeline and stages the readback.
// p_push carries the exact push-constant bytes (canonical header, optional
// target_size) so both paths receive identical numbers.
void rd_translate_job(RID p_framebuffer, RID p_pipeline, RID p_vertex_array, RID p_index_array, RID p_rd_texture,
		RID p_shader, RID p_rs_texture, RID p_sampler, RID p_value_buffer, RID p_screen_texture, int p_screen_index, int p_sampler_count, int p_uniform_count, PackedByteArray p_push) {
	RenderingDevice *rd = RenderingDevice::get_singleton();
	if (p_uniform_count > 0) {
		Vector<RD::Uniform> uniforms;
		for (int i = 0; i < p_sampler_count; ++i) {
			RD::Uniform uniform;
			uniform.uniform_type = RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;
			uniform.binding = i;
			uniform.append_id(p_sampler);
			const RID sampled = i == p_screen_index ? p_screen_texture : p_rs_texture;
			uniform.append_id(RSG::texture_storage->texture_get_rd_texture(sampled));
			uniforms.push_back(uniform);
		}
		if (p_value_buffer.is_valid()) {
			RD::Uniform uniform;
			uniform.uniform_type = RD::UNIFORM_TYPE_UNIFORM_BUFFER;
			uniform.binding = p_sampler_count;
			uniform.append_id(p_value_buffer);
			uniforms.push_back(uniform);
		}
		g_render_output.uniform_set = rd->uniform_set_create(VectorView<RD::Uniform>(uniforms.ptr(), uniforms.size()), p_shader, 0);
	}
	RD::DrawListID list = rd->draw_list_begin(p_framebuffer, RD::DRAW_CLEAR_COLOR_ALL, VectorView<Color>(&TRANSPARENT_CLEAR, 1), 1.0f, 0);
	rd->draw_list_bind_render_pipeline(list, p_pipeline);
	if (p_uniform_count > 0 && g_render_output.uniform_set.is_valid()) rd->draw_list_bind_uniform_set(list, g_render_output.uniform_set, 0);
	rd->draw_list_bind_vertex_array(list, p_vertex_array);
	rd->draw_list_bind_index_array(list, p_index_array);
	rd->draw_list_set_push_constant(list, p_push.ptr(), p_push.size());
	rd->draw_list_draw(list, true);
	rd->draw_list_end();
	g_render_output.readback = rd->texture_get_data(p_rd_texture, 0);
	RID bridge = RSG::texture_storage->texture_allocate();
	RSG::texture_storage->texture_rd_initialize(bridge, p_rd_texture, RSE::TEXTURE_LAYERED_2D_ARRAY);
	g_render_output.bridge_texture = bridge;
	g_render_output.done = true;
}
} // namespace

Dictionary cycle_probe(int p_items, int p_count, RID p_parent_canvas_item, CycleState &p_state) {
	if (p_state.active || p_state.phase_pending) return fail("cycle_already_active");
	RenderingServer *rs = RenderingServer::get_singleton();
	RenderingDevice *rd = rs->get_rendering_device();
	if (rd == nullptr) return fail("rd_unavailable"); // gl_compatibility has no RenderingDevice.

	const int width = 2016, height = 928; // Effect-pass resolution, matches benchmark_offscreen_cycle.
	p_state.width = width;
	p_state.height = height;

	// Color attachment + sampling + copy source: the three roles a real
	// offscreen target plays (render, re-sample by later passes, readback).
	RD::TextureFormat format;
	format.format = RD::DATA_FORMAT_R8G8B8A8_UNORM;
	format.width = width;
	format.height = height;
	format.texture_type = RD::TEXTURE_TYPE_2D;
	format.array_layers = 1;
	format.mipmaps = 1;
	format.usage_bits = RD::TEXTURE_USAGE_SAMPLING_BIT | RD::TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RD::TEXTURE_USAGE_CAN_COPY_FROM_BIT;
	p_state.rd_texture = rd->texture_create(format, RD::TextureView());
	if (!p_state.rd_texture.is_valid()) return fail("texture_create");
	Vector<RID> attachments;
	attachments.push_back(p_state.rd_texture);
	p_state.framebuffer = rd->framebuffer_create(attachments);
	if (!p_state.framebuffer.is_valid()) return fail("framebuffer_create");

	String compile_error;
	Vector<uint8_t> vertex_spirv = rd->shader_compile_spirv_from_source(RD::SHADER_STAGE_VERTEX, VERTEX_GLSL, RD::SHADER_LANGUAGE_GLSL, &compile_error);
	if (vertex_spirv.is_empty()) return fail("vertex_spirv: " + compile_error);
	Vector<uint8_t> fragment_spirv = rd->shader_compile_spirv_from_source(RD::SHADER_STAGE_FRAGMENT, FRAGMENT_GLSL, RD::SHADER_LANGUAGE_GLSL, &compile_error);
	if (fragment_spirv.is_empty()) return fail("fragment_spirv: " + compile_error);
	Vector<RD::ShaderStageSPIRVData> stages;
	stages.resize(2);
	stages.write[0].shader_stage = RD::SHADER_STAGE_VERTEX;
	stages.write[0].spirv = vertex_spirv;
	stages.write[1].shader_stage = RD::SHADER_STAGE_FRAGMENT;
	stages.write[1].spirv = fragment_spirv;
	p_state.shader = rd->shader_create_from_spirv(stages);
	if (!p_state.shader.is_valid()) return fail("shader_create");

	// Interleaved layout in one buffer: float2 position + float4 color per
	// vertex. Both attributes bind buffer 0 explicitly — the UINT32_MAX
	// default derives the binding from the attribute index, which would
	// demand a second source buffer.
	Vector<RD::VertexAttribute> attributes;
	RD::VertexAttribute position_attribute;
	position_attribute.binding = 0;
	position_attribute.location = 0;
	position_attribute.offset = 0;
	position_attribute.format = RD::DATA_FORMAT_R32G32_SFLOAT;
	position_attribute.stride = 6 * sizeof(float);
	attributes.push_back(position_attribute);
	RD::VertexAttribute color_attribute;
	color_attribute.binding = 0;
	color_attribute.location = 1;
	color_attribute.offset = 2 * sizeof(float);
	color_attribute.format = RD::DATA_FORMAT_R32G32B32A32_SFLOAT;
	color_attribute.stride = 6 * sizeof(float);
	attributes.push_back(color_attribute);
	RD::VertexFormatID vertex_format = rd->vertex_format_create(attributes);

	// One quad covering the left half of the target in NDC.
	const float vertex_data[4][6] = {
		{ -1.0f, -1.0f, QUAD_COLOR.r, QUAD_COLOR.g, QUAD_COLOR.b, QUAD_COLOR.a },
		{ 0.0f, -1.0f, QUAD_COLOR.r, QUAD_COLOR.g, QUAD_COLOR.b, QUAD_COLOR.a },
		{ -1.0f, 1.0f, QUAD_COLOR.r, QUAD_COLOR.g, QUAD_COLOR.b, QUAD_COLOR.a },
		{ 0.0f, 1.0f, QUAD_COLOR.r, QUAD_COLOR.g, QUAD_COLOR.b, QUAD_COLOR.a },
	};
	Vector<uint8_t> vertex_bytes;
	vertex_bytes.resize(sizeof(vertex_data));
	memcpy(vertex_bytes.ptrw(), vertex_data, sizeof(vertex_data));
	p_state.vertex_buffer = rd->vertex_buffer_create(vertex_bytes.size(), Span<uint8_t>(vertex_bytes.ptrw(), vertex_bytes.size()));
	Vector<RID> vertex_sources;
	vertex_sources.push_back(p_state.vertex_buffer);
	p_state.vertex_array = rd->vertex_array_create(4, vertex_format, vertex_sources);
	const uint32_t index_data[6] = { 0, 1, 2, 2, 1, 3 };
	Vector<uint8_t> index_bytes;
	index_bytes.resize(sizeof(index_data));
	memcpy(index_bytes.ptrw(), index_data, sizeof(index_data));
	p_state.index_buffer = rd->index_buffer_create(6, RD::INDEX_BUFFER_FORMAT_UINT32, Span<uint8_t>(index_bytes.ptrw(), index_bytes.size()));
	p_state.index_array = rd->index_array_create(p_state.index_buffer, 0, 6);
	if (!p_state.vertex_array.is_valid() || !p_state.index_array.is_valid()) return fail("geometry_create");

	p_state.pipeline = rd->render_pipeline_create(p_state.shader, rd->framebuffer_get_format(p_state.framebuffer), vertex_format,
			RD::RENDER_PRIMITIVE_TRIANGLES, RD::PipelineRasterizationState(), RD::PipelineMultisampleState(),
			RD::PipelineDepthStencilState(), RD::PipelineColorBlendState::create_disabled(1));
	if (!p_state.pipeline.is_valid()) return fail("pipeline_create");

	Dictionary result;
	result["items"] = p_items;
	result["count"] = p_count;

	// Render-thread half: verification render + readback, then timing loop.
	g_render_output = RenderOutput();
	rs->call_on_render_thread(callable_mp_static(rd_render_job).bind(p_state.framebuffer, p_state.pipeline, p_state.vertex_array,
			p_state.index_array, p_state.rd_texture, p_items > 0 ? p_items : 0, p_count));
	rs->sync(); // Safe mode runs the job inline; separate mode fences the FIFO.
	if (!g_render_output.done) return fail("render_job");

	// Pixel verification by readback: the clear half always; the quad half
	// only when something was drawn (items=0 measures the bare cycle).
	const Vector<uint8_t> &data = g_render_output.readback;
	const int draws = p_items > 0 ? p_items : 0;
	bool pixels_ok = (int)data.size() == width * height * 4;
	if (pixels_ok) {
		const int quad_rgba[4] = { 230, 128, 77, 255 }; // (0.9, 0.5, 0.3, 1.0) * 255
		const int clear_rgba[4] = { 26, 51, 77, 255 }; // (0.1, 0.2, 0.3, 1.0) * 255
		auto channel = [&](int p_x, int p_y, int p_c) { return data[(p_y * width + p_x) * 4 + p_c]; };
		for (int c = 0; c < 4 && pixels_ok; ++c) {
			if (Math::abs(channel(3 * width / 4, height / 2, c) - clear_rgba[c]) > COLOR_TOLERANCE) pixels_ok = false;
		}
		for (int c = 0; c < 4 && pixels_ok && draws > 0; ++c) {
			if (Math::abs(channel(width / 4, height / 2, c) - quad_rgba[c]) > COLOR_TOLERANCE) pixels_ok = false;
		}
	}
	result["pixels_ok"] = pixels_ok;
	result["total_us"] = (int64_t)g_render_output.elapsed_us;
	result["per_cycle_us"] = p_count > 0 ? double(g_render_output.elapsed_us) / p_count : 0.0;

	// Bridge: the ledger RID wrapping the RD texture was created on the render
	// thread (see rd_render_job); canvas items can sample it directly.
	p_state.bridge_texture = g_render_output.bridge_texture;
	result["bridge_ok"] = p_state.bridge_texture.is_valid();
	if (p_parent_canvas_item.is_valid() && p_state.bridge_texture.is_valid()) {
		p_state.bridge_item = rs->canvas_item_create();
		rs->canvas_item_set_parent(p_state.bridge_item, p_parent_canvas_item);
		rs->canvas_item_add_texture_rect(p_state.bridge_item, Rect2(0, 0, 512, 256), p_state.bridge_texture);
		result["bridge_item_ok"] = p_state.bridge_item.is_valid();
	}

	p_state.active = true;
	return result;
}

Dictionary translate_probe(const String &p_canvas_shader, RID p_texture, RID p_parent_canvas_item, CycleState &p_state) {
	if (p_state.active || p_state.phase_pending) return fail("cycle_already_active");
	RenderingServer *rs = RenderingServer::get_singleton();
	RenderingDevice *rd = rs->get_rendering_device();
	if (rd == nullptr) return fail("rd_unavailable");
	p_state.probe_translated = godot_javafx::translate_canvas_shader(p_canvas_shader);
	const RdShaderSources &translated = p_state.probe_translated;
	if (!translated.ok) {
		Dictionary result = fail(translated.error);
		result["translate_ok"] = false;
		return result;
	}
	const int width = 512, height = 256;
	p_state.width = width;
	p_state.height = height;
	p_state.probe_parent_item = p_parent_canvas_item;
	p_state.probe_texture = p_texture;

	// Viewport half: the production path renders the identical batch through a
	// JavaFXRenderTarget; its readback is the reference for the RD pipeline.
	p_state.viewport_target.instantiate();
	// The reference must ride the viewport path even when the process runs
	// RD-direct, or the probe would compare the spike pipeline against itself.
	if (!p_state.viewport_target->initialize(Size2i(width, height), true)) return fail("viewport_target");
	const float quad[4][5] = {
		{ 32, 40, 0, 0 }, { 32, 216, 0, 1 }, { 480, 40, 1, 0 }, { 480, 216, 1, 1 },
	};
	const uint8_t quad_color[4] = { 217, 130, 87, 217 }; // premultiplied (1, .6, .4) x .85
	PackedFloat32Array vertices;
	PackedByteArray colors;
	vertices.resize(4 * 7);
	colors.resize(4 * 4);
	for (int i = 0; i < 4; ++i) {
		float *out = vertices.ptrw() + i * 7;
		out[0] = quad[i][0]; out[1] = quad[i][1]; out[2] = 0;
		out[3] = quad[i][2]; out[4] = quad[i][3]; out[5] = quad[i][2]; out[6] = quad[i][3];
		for (int c = 0; c < 4; ++c) colors.ptrw()[i * 4 + c] = quad_color[c];
	}
	Dictionary parameters;
	HashMap<StringName, Variant> instance_parameters;
	const int screen_index = translated.screen_sampler_index;
	for (int i = 0; i < translated.sampler_names.size(); ++i) {
		if (i == screen_index) continue; // hint sampler: canvas samples the destination itself
		parameters[translated.sampler_names[i]] = p_texture;
	}
	if (screen_index >= 0) {
		// Stand-in for the pre-pass destination snapshot. The canvas hint
		// sampler reads the cleared target back as opaque black (the canvas
		// backbuffer copy carries no transparency), so the stand-in must be
		// opaque black to keep both paths byte-comparable.
		Ref<Image> blank = Image::create_empty(8, 8, false, Image::FORMAT_RGBA8);
		blank->fill(Color(0, 0, 0, 1));
		p_state.probe_screen_texture = rs->texture_2d_create(blank);
		if (!p_state.probe_screen_texture.is_valid()) return fail("screen_texture_create");
	}
	// Seed value uniforms with a deterministic non-zero pattern on both paths:
	// zero defaults drive division-heavy shaders into NaNs whose bit patterns
	// are not guaranteed to match across the two rasterizers. The host moves
	// scalar value uniforms to per-item instance uniforms by default (arrays
	// stay material uniforms), so the viewport half receives scalars through
	// instance data and arrays as packed material parameters — the production
	// constant split — while the RD half reads the identical bytes from a
	// std140 uniform buffer.
	auto seed_word = [](int p_uniform, int p_element, int p_component) {
		return 0.31f + 0.05f * ((p_uniform * 7 + p_element * 3 + p_component * 5) % 13);
	};
	PackedByteArray push_bytes;
	push_bytes.resize(translated.push_constant_bytes);
	memset(push_bytes.ptrw(), 0, push_bytes.size());
	const float header[16] = { 1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 2.0f / width, 2.0f / height, -1.0f, -1.0f };
	memcpy(push_bytes.ptrw(), header, sizeof(header));
	if (translated.push_constant_bytes >= 72) {
		const float target_size[2] = { float(width), float(height) };
		memcpy(push_bytes.ptrw() + 64, target_size, sizeof(target_size));
	}
	PackedByteArray value_bytes;
	value_bytes.resize(translated.value_buffer_bytes);
	memset(value_bytes.ptrw(), 0, value_bytes.size());
	{
		int index = 0;
		for (const RdValueUniform &value : translated.value_uniforms) {
			// Array constants travel to canvas materials as flat packed word
			// arrays (the production host encodes them that way); scalars ride
			// instance data and the std140 buffer byte-for-byte on the RD side.
			PackedFloat32Array floats;
			PackedInt32Array ints;
			for (int element = 0; element < value.count; ++element) {
				for (int w = 0; w < value.words; ++w) {
					const float word = seed_word(index, element, w);
					uint32_t bits = 0;
					if (value.integer) {
						const int32_t integer = int32_t(word * 97.0f);
						ints.push_back(integer);
						memcpy(&bits, &integer, sizeof(bits));
					} else {
						floats.push_back(word);
						memcpy(&bits, &word, sizeof(bits));
					}
					memcpy(value_bytes.ptrw() + value.offset + element * value.stride + w * 4, &bits, sizeof(bits));
				}
			}
			Variant variant;
			if (value.is_array) {
				variant = value.integer ? Variant(ints) : Variant(floats);
				parameters[value.name] = variant; // arrays stay material uniforms
			} else {
				if (value.integer) variant = int(seed_word(index, 0, 0) * 97.0f);
				else {
					const float words[4] = { seed_word(index, 0, 0), seed_word(index, 0, 1), seed_word(index, 0, 2), seed_word(index, 0, 3) };
					switch (value.words) {
						case 1: variant = words[0]; break;
						case 2: variant = Vector2(words[0], words[1]); break;
						case 3: variant = Vector3(words[0], words[1], words[2]); break;
						default: variant = Vector4(words[0], words[1], words[2], words[3]); break;
					}
				}
				parameters[value.name] = variant;
				instance_parameters.insert(value.name, variant);
			}
			++index;
		}
	}
	if (translated.value_buffer_bytes > 0) {
		p_state.value_buffer = rd->uniform_buffer_create(value_bytes.size(), Span<uint8_t>(value_bytes.ptrw(), value_bytes.size()));
		if (!p_state.value_buffer.is_valid()) return fail("value_buffer_create");
	}
	p_state.probe_screen_index = translated.screen_sampler_index;
	p_state.probe_sampler_count = translated.sampler_names.size();
	p_state.probe_uniform_count = p_state.probe_sampler_count + (translated.value_buffer_bytes > 0 ? 1 : 0);
	p_state.probe_push = push_bytes;

	// The viewport reference pass is recorded after the RD half (see below).

	// RD half: same batch in the interleaved layout the canonical vertex
	// shader expects (pos, uv0, uv1 floats + RGBA8 color), premul blend.
	RD::TextureFormat format;
	format.format = RD::DATA_FORMAT_R8G8B8A8_UNORM;
	format.width = width;
	format.height = height;
	format.texture_type = RD::TEXTURE_TYPE_2D;
	format.array_layers = 1;
	format.mipmaps = 1;
	format.usage_bits = RD::TEXTURE_USAGE_SAMPLING_BIT | RD::TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RD::TEXTURE_USAGE_CAN_COPY_FROM_BIT;
	p_state.rd_texture = rd->texture_create(format, RD::TextureView());
	if (!p_state.rd_texture.is_valid()) return fail("texture_create");
	Vector<RID> attachments;
	attachments.push_back(p_state.rd_texture);
	p_state.framebuffer = rd->framebuffer_create(attachments);
	String compile_error;
	Vector<uint8_t> vertex_spirv = rd->shader_compile_spirv_from_source(RD::SHADER_STAGE_VERTEX, translated.vertex_source, RD::SHADER_LANGUAGE_GLSL, &compile_error);
	if (vertex_spirv.is_empty()) return fail("vertex_spirv: " + compile_error);
	Vector<uint8_t> fragment_spirv = rd->shader_compile_spirv_from_source(RD::SHADER_STAGE_FRAGMENT, translated.fragment_source, RD::SHADER_LANGUAGE_GLSL, &compile_error);
	if (fragment_spirv.is_empty()) return fail("fragment_spirv: " + compile_error);
	Vector<RD::ShaderStageSPIRVData> stages;
	stages.resize(2);
	stages.write[0].shader_stage = RD::SHADER_STAGE_VERTEX;
	stages.write[0].spirv = vertex_spirv;
	stages.write[1].shader_stage = RD::SHADER_STAGE_FRAGMENT;
	stages.write[1].spirv = fragment_spirv;
	p_state.shader = rd->shader_create_from_spirv(stages);
	if (!p_state.shader.is_valid()) return fail("shader_create");

	Vector<RD::VertexAttribute> attributes;
	const int stride = 6 * 4 + 4;
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
	RD::VertexFormatID vertex_format = rd->vertex_format_create(attributes);
	Vector<uint8_t> vertex_bytes;
	vertex_bytes.resize(4 * stride);
	for (int i = 0; i < 4; ++i) {
		float *out = reinterpret_cast<float *>(vertex_bytes.ptrw() + i * stride);
		out[0] = quad[i][0]; out[1] = quad[i][1];
		out[2] = quad[i][2]; out[3] = quad[i][3];
		out[4] = quad[i][2]; out[5] = quad[i][3];
		memcpy(vertex_bytes.ptrw() + i * stride + 24, quad_color, 4);
	}
	p_state.vertex_buffer = rd->vertex_buffer_create(vertex_bytes.size(), Span<uint8_t>(vertex_bytes.ptrw(), vertex_bytes.size()));
	Vector<RID> vertex_sources;
	vertex_sources.push_back(p_state.vertex_buffer);
	p_state.vertex_array = rd->vertex_array_create(4, vertex_format, vertex_sources);
	const uint32_t index_data[6] = { 0, 1, 2, 2, 1, 3 };
	Vector<uint8_t> index_bytes;
	index_bytes.resize(sizeof(index_data));
	memcpy(index_bytes.ptrw(), index_data, sizeof(index_data));
	p_state.index_buffer = rd->index_buffer_create(6, RD::INDEX_BUFFER_FORMAT_UINT32, Span<uint8_t>(index_bytes.ptrw(), index_bytes.size()));
	p_state.index_array = rd->index_array_create(p_state.index_buffer, 0, 6);
	if (!p_state.vertex_array.is_valid() || !p_state.index_array.is_valid()) return fail("geometry_create");

	RD::PipelineColorBlendState blend;
	RD::PipelineColorBlendState::Attachment attachment;
	attachment.enable_blend = true;
	attachment.src_color_blend_factor = RD::BLEND_FACTOR_ONE;
	attachment.dst_color_blend_factor = RD::BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
	attachment.src_alpha_blend_factor = RD::BLEND_FACTOR_ONE;
	attachment.dst_alpha_blend_factor = RD::BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
	blend.attachments.push_back(attachment);
	p_state.pipeline = rd->render_pipeline_create(p_state.shader, rd->framebuffer_get_format(p_state.framebuffer), vertex_format,
			RD::RENDER_PRIMITIVE_TRIANGLES, RD::PipelineRasterizationState(), RD::PipelineMultisampleState(),
			RD::PipelineDepthStencilState(), blend);
	if (!p_state.pipeline.is_valid()) return fail("pipeline_create");

	if (!translated.sampler_names.is_empty()) {
		RD::SamplerState sampler_state;
		sampler_state.mag_filter = RD::SAMPLER_FILTER_LINEAR;
		sampler_state.min_filter = RD::SAMPLER_FILTER_LINEAR;
		p_state.sampler = rd->sampler_create(sampler_state);
		if (!p_state.sampler.is_valid()) return fail("sampler_create");
	}

	// Phase A leaves the recorded pass for the engine frame: an immediate
	// draw_offscreen_2d loses first-use material-path uniforms (array
	// constants) — production hides that behind materials persisting across
	// frames — so the reference render rides the engine's UPDATE_ONCE frame,
	// which the GD-driven host probe proved delivers arrays.
	p_state.viewport_target->begin_pass(true);
	p_state.viewport_target->draw_prism_quads_with_instances(vertices, colors, p_canvas_shader, parameters, false,
			Rect2i(0, 0, width, height), p_texture, Transform2D(), 1.0f,
			instance_parameters.is_empty() ? nullptr : &instance_parameters);
	p_state.viewport_target->end_pass();

	p_state.phase_pending = true;
	Dictionary result;
	result["translate_ok"] = true;
	result["phase"] = "a";
	result["sampler_count"] = translated.sampler_names.size();
	result["value_count"] = translated.value_uniforms.size();
	result["push_bytes"] = translated.push_constant_bytes;
	return result;
}

Dictionary translate_probe_finish(CycleState &p_state) {
	if (p_state.active || !p_state.phase_pending) return fail("phase_a_not_pending");
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr || rs->get_rendering_device() == nullptr) return fail("rd_unavailable");
	const int width = p_state.width, height = p_state.height;
	// The engine frame rendered the viewport reference during UPDATE_ONCE.
	Ref<Image> viewport_image = rs->texture_2d_get(p_state.viewport_target->get_texture());
	if (viewport_image.is_null()) return fail("viewport_readback");
	if (viewport_image->get_format() != Image::FORMAT_RGBA8) viewport_image->convert(Image::FORMAT_RGBA8);

	g_render_output = RenderOutput();
	rs->call_on_render_thread(callable_mp_static(rd_translate_job).bind(p_state.framebuffer, p_state.pipeline, p_state.vertex_array,
			p_state.index_array, p_state.rd_texture, p_state.shader, p_state.probe_texture, p_state.sampler, p_state.value_buffer,
			p_state.probe_screen_texture, p_state.probe_screen_index, p_state.probe_sampler_count, p_state.probe_uniform_count, p_state.probe_push));
	rs->sync();
	p_state.phase_pending = false;
	if (!g_render_output.done) return fail("render_job");
	p_state.uniform_set = g_render_output.uniform_set;
	p_state.bridge_texture = g_render_output.bridge_texture;

	// Pixel-by-pixel comparison: both paths share the upstream batch, so any
	// divergence is a translation/semantics defect, not raster noise.
	const RdShaderSources &translated = p_state.probe_translated;
	Dictionary result;
	result["translate_ok"] = true;
	result["sampler_count"] = translated.sampler_names.size();
	result["value_count"] = translated.value_uniforms.size();
	result["push_bytes"] = translated.push_constant_bytes;
	const uint8_t *rd_data = g_render_output.readback.ptr();
	const uint8_t *vp_data = viewport_image->get_data().ptr();
	int max_diff = 0;
	int64_t diffs_gt1 = 0, diffs_gt4 = 0;
	if ((int)g_render_output.readback.size() == width * height * 4 && viewport_image->get_data().size() == g_render_output.readback.size()) {
		for (int i = 0; i < width * height * 4; ++i) {
			int diff = Math::abs(int(rd_data[i]) - int(vp_data[i]));
			if (diff > max_diff) max_diff = diff;
			if (diff > 1) ++diffs_gt1;
			if (diff > 4) ++diffs_gt4;
		}
	} else {
		return fail("readback_size");
	}
	result["max_diff"] = max_diff;
	result["diffs_gt1"] = diffs_gt1;
	result["diffs_gt4"] = diffs_gt4;
	const int center = (height / 2 * width + width / 2) * 4;
	result["rd_center"] = vformat("%d,%d,%d,%d", rd_data[center], rd_data[center + 1], rd_data[center + 2], rd_data[center + 3]);
	result["vp_center"] = vformat("%d,%d,%d,%d", vp_data[center], vp_data[center + 1], vp_data[center + 2], vp_data[center + 3]);

	// Side-by-side previews so the equality is visible in screenshots.
	if (p_state.probe_parent_item.is_valid()) {
		p_state.preview_item_rd = rs->canvas_item_create();
		rs->canvas_item_set_parent(p_state.preview_item_rd, p_state.probe_parent_item);
		rs->canvas_item_add_texture_rect(p_state.preview_item_rd, Rect2(8, 8, 240, 120), p_state.bridge_texture);
		p_state.preview_item_viewport = rs->canvas_item_create();
		rs->canvas_item_set_parent(p_state.preview_item_viewport, p_state.probe_parent_item);
		rs->canvas_item_add_texture_rect(p_state.preview_item_viewport, Rect2(256, 8, 240, 120), p_state.viewport_target->get_texture());
	}
	p_state.active = true;
	return result;
}
void release_cycle(CycleState &p_state) {
	// Partially-created states must clean up too: a failed probe leaves the
	// resources it did manage to create, so gate on RID validity, not on a
	// completed-cycle flag.
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return;
	}
	// Retire descriptor sets before any referenced texture or shader: freeing
	// the screen stand-in first cascade-destroys its set in RenderingDevice.
	if (rs->get_rendering_device() != nullptr &&
			(p_state.uniform_set.is_valid() || p_state.sampler.is_valid() || p_state.value_buffer.is_valid())) {
		rs->call_on_render_thread(callable_mp_static(rd_free_extra_job).bind(p_state.uniform_set, p_state.sampler, p_state.value_buffer));
	}
	// The ledger RID owns a shared RD view of rd_texture; free it first so the
	// underlying texture always outlives every view of it. free_rid on the
	// device is render-thread-only, so the device resources retire through the
	// FIFO; their RIDs drop immediately and the next cycle can start.
	if (p_state.preview_item_rd.is_valid()) rs->free_rid(p_state.preview_item_rd);
	if (p_state.preview_item_viewport.is_valid()) rs->free_rid(p_state.preview_item_viewport);
	if (p_state.bridge_item.is_valid()) rs->free_rid(p_state.bridge_item);
	if (p_state.bridge_texture.is_valid()) rs->free_rid(p_state.bridge_texture);
	if (p_state.probe_screen_texture.is_valid()) rs->free_rid(p_state.probe_screen_texture);
	// The viewport target's texture must retire before the target itself.
	p_state.viewport_target.unref();
	if (rs->get_rendering_device() != nullptr) {

		rs->call_on_render_thread(callable_mp_static(rd_free_job).bind(p_state.pipeline, p_state.shader, p_state.index_array,
				p_state.index_buffer, p_state.vertex_array, p_state.vertex_buffer, p_state.framebuffer, p_state.rd_texture));
	}
	p_state = CycleState();
}

} // namespace godot_javafx::rd_direct
