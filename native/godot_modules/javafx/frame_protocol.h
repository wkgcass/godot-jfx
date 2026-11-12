#pragma once

#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <vector>
#include <chrono>
#include <unordered_map>
#include <unordered_set>

namespace godot_javafx {

constexpr uint32_t FRAME_MAGIC = 0x31465847; // GXF1, little endian.
constexpr size_t MAX_FRAME_BYTES = 4 * 1024 * 1024;
constexpr size_t MAX_QUEUED_FRAMES = 3;

enum class Opcode : uint32_t { CLEAR = 1, RECTANGLE = 2, RESIZE = 3, QUADS = 4,
	TEXTURE_CREATE = 5, TEXTURE_UPDATE = 6, TEXTURE_DISPOSE = 7, TEXTURED_QUADS = 8,
	TEXTURE_ALLOCATE = 9, TEXTURE_PATCH = 10, SHADER_STATE = 11, CLIP = 12,
	BEGIN_PRESENT = 13, PRESENT = 14, TARGET_ALLOCATE = 15, TARGET_SELECT = 16, END_PASS = 17,
	FLOAT_TEXTURE_ALLOCATE = 18, FLOAT_TEXTURE_PATCH = 19, SCENE_TEXTURE_ALLOCATE = 20, SCENE_TEXTURE_RESIZE = 21, SCENE_INPUT = 22,
	WINDOW_PRESENT = 23, WINDOW_REMOVE = 24, WINDOW_CONFIGURE = 25, NATIVE_WINDOW_PRESENT = 26, ALPHA_TEXTURE_PATCH = 27, VIDEO_PLANE_ALLOCATE = 28,
	QUADS_REF = 29, GEOMETRY_FREE = 30 };

struct ShaderConstant {
	std::string name;
	uint32_t type = 0, components = 0, array_count = 0;
	std::vector<uint32_t> words;
};

struct Command {
	Opcode opcode;
	float values[8] = {};
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t x = 0, y = 0;
	uint32_t input_kind = 0, input_flags = 0, input_code = 0, input_unicode = 0;
	std::vector<float> vertices;
	std::vector<uint8_t> colors;
	// 2D affine applied at draw time (mxx, mxy, mxt, myx, myy, myt); vertices
	// stay in local space so unchanged batches are reusable across frames.
	float transform[6] = { 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f };
	// Uniform modulation carried as a draw parameter instead of being baked
	// into the vertex colors, so opacity animations keep batch content
	// byte-identical and drawable through QUADS_REF.
	float draw_alpha = 1.0f;
	uint64_t texture_handle = 0;
	uint64_t source_handle = 0;
	// Geometry deduplication: QUADS may tag its content with a fresh handle the
	// host keeps resident; QUADS_REF redraws it without resending vertices;
	// GEOMETRY_FREE retires one. Zero means the batch is not deduplicated.
	uint64_t geometry_handle = 0;
	uint64_t window_id = 0;
	int32_t window_z = 0;
	bool window_visible = true;
	std::vector<uint8_t> pixels;
	std::string shader_source;
	std::string scene_path;
	std::vector<ShaderConstant> constants;
	std::unordered_map<std::string, uint64_t> samplers;
	bool clip_enabled = false;
};

struct Frame {
	uint64_t sequence = 0;
	std::vector<Command> commands;
};

inline uint32_t read_u32(const uint8_t *p) {
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

// Decode a complete owned snapshot before any Godot state changes. Rejection
// cannot leave a partially applied frame, even when the final record is bad.
inline bool decode_frame(const std::vector<uint8_t> &bytes, Frame &out, std::string &error) {
	auto fail = [&](const char *message) { error = message; return false; };
	if (bytes.size() < 24 || bytes.size() > MAX_FRAME_BYTES) return fail("Invalid frame length");
	const uint8_t *p = bytes.data();
	if (read_u32(p) != FRAME_MAGIC || read_u32(p + 4) != 1) return fail("Unknown frame protocol");
	if (read_u32(p + 8) != bytes.size()) return fail("Declared frame length differs");
	uint32_t count = read_u32(p + 12);
	if (count > 65536 || count > (bytes.size() - 24) / 8) return fail("Invalid command count");
	Frame result;
	result.sequence = uint64_t(read_u32(p + 16)) | (uint64_t(read_u32(p + 20)) << 32);
	if (result.sequence == 0 || result.sequence > INT64_MAX) return fail("Invalid sequence");
	result.commands.reserve(count);
	size_t offset = 24;
	for (uint32_t i = 0; i < count; ++i) {
		if (bytes.size() - offset < 8) return fail("Truncated command header");
		Command command;
		command.opcode = static_cast<Opcode>(read_u32(p + offset));
		uint32_t size = read_u32(p + offset + 4);
		offset += 8;
		if (size > bytes.size() - offset) return fail("Truncated command payload");
		switch (command.opcode) {
			case Opcode::WINDOW_PRESENT:
			case Opcode::NATIVE_WINDOW_PRESENT:
			case Opcode::WINDOW_CONFIGURE:
			case Opcode::WINDOW_REMOVE: {
				bool configure = command.opcode == Opcode::WINDOW_CONFIGURE;
				bool geometry = command.opcode != Opcode::WINDOW_REMOVE;
				if (size != (configure ? 36u : geometry ? 32u : 8u) || i + 1 != count) return fail("Invalid window boundary");
				command.window_id = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				if (!command.window_id || command.window_id > INT64_MAX) return fail("Invalid window identity");
				if (geometry) {
					for (int j = 0; j < 5; ++j) {
						uint32_t bits = read_u32(p + offset + (j == 4 ? 28 : 8 + j * 4));
						std::memcpy(&command.values[j], &bits, 4);
						if (!std::isfinite(command.values[j])) return fail("Non-finite window geometry/opacity");
					}
					uint32_t z = read_u32(p + offset + 24); std::memcpy(&command.window_z, &z, 4);
					if (command.values[2] <= 0 || command.values[3] <= 0 || command.values[2] > 8192 || command.values[3] > 8192 || command.values[4] < 0 || command.values[4] > 1) return fail("Invalid window geometry/opacity");
					if (configure) {
						uint32_t visible = read_u32(p + offset + 32);
						if (visible > 1) return fail("Invalid window visibility");
						command.window_visible = visible != 0;
					}
				}
			} break;
			case Opcode::SCENE_INPUT: {
				if (size != 40) return fail("Invalid scene input payload");
				command.texture_handle = uint64_t(read_u32(p+offset)) | (uint64_t(read_u32(p+offset+4)) << 32);
				command.input_kind = read_u32(p+offset+8); command.input_flags = read_u32(p+offset+12);
				command.input_code = read_u32(p+offset+16); command.input_unicode = read_u32(p+offset+20);
				if (command.input_kind > 5 || command.input_flags > 63 || command.input_code > INT32_MAX || command.input_unicode > 0x10ffff || (command.input_unicode >= 0xd800 && command.input_unicode <= 0xdfff)) return fail("Invalid scene input fields");
				if (command.input_kind == 1 && (command.input_code < 1 || command.input_code > 9)) return fail("Invalid scene mouse button");
				for (int j = 0; j < 4; ++j) {
					uint32_t bits = read_u32(p+offset+24+j*4); std::memcpy(&command.values[j],&bits,4);
					if (!std::isfinite(command.values[j])) return fail("Non-finite scene input coordinates");
				}
			} break;
			case Opcode::SCENE_TEXTURE_RESIZE:
				if (size != 24) return fail("Invalid scene resize payload");
				command.texture_handle = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				command.source_handle = uint64_t(read_u32(p + offset + 8)) | (uint64_t(read_u32(p + offset + 12)) << 32);
				command.width = read_u32(p + offset + 16); command.height = read_u32(p + offset + 20);
				if (!command.width || !command.height || command.width > 8192 || command.height > 8192) return fail("Invalid scene resize dimensions");
				break;
			case Opcode::SCENE_TEXTURE_ALLOCATE: {
				if (size < 20) return fail("Truncated scene texture allocation");
				command.texture_handle = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				if (!uint32_t(command.texture_handle) || !(command.texture_handle >> 32)) return fail("Invalid scene texture handle");
				command.width = read_u32(p + offset + 8); command.height = read_u32(p + offset + 12);
				uint32_t length = read_u32(p + offset + 16);
				if (!command.width || !command.height || command.width > 8192 || command.height > 8192 || length < 7 || length > 4096 || size != 20 + length) return fail("Invalid scene texture dimensions/path length");
				command.scene_path.assign(reinterpret_cast<const char *>(p + offset + 20), length);
				if (command.scene_path.compare(0, 6, "res://") != 0 || command.scene_path.find('\0') != std::string::npos) return fail("Invalid scene resource path");
			} break;
			case Opcode::BEGIN_PRESENT:
			case Opcode::PRESENT:
			case Opcode::END_PASS:
				if (size != 0 || (command.opcode == Opcode::PRESENT && i + 1 != count)) return fail("Invalid presentation boundary");
				break;
			case Opcode::TARGET_SELECT:
				if (size != 8) return fail("Invalid target selection");
				command.texture_handle = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				break;
			case Opcode::CLIP: {
				if (size != 20 || read_u32(p + offset) > 1) return fail("Invalid clip payload");
				command.clip_enabled = read_u32(p + offset) != 0;
				command.x = read_u32(p + offset + 4); command.y = read_u32(p + offset + 8);
				command.width = read_u32(p + offset + 12); command.height = read_u32(p + offset + 16);
				if (command.width > INT32_MAX || command.height > INT32_MAX || (!command.clip_enabled && (command.x || command.y || command.width || command.height))) return fail("Invalid clip dimensions");
			} break;
			case Opcode::SHADER_STATE: {
				size_t cursor = offset, end = offset + size;
				auto text = [&](std::string &value, uint32_t maximum, bool identifier) {
					if (end - cursor < 4) return false;
					uint32_t length = read_u32(p + cursor); cursor += 4;
					if (!length || length > maximum || length > end - cursor) return false;
					for (uint32_t j = 0; j < length; ++j) {
						uint8_t c = p[cursor + j];
						if (!c || c > 127) return false;
						if (identifier && !(c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (j && c >= '0' && c <= '9'))) return false;
					}
					value.assign(reinterpret_cast<const char *>(p + cursor), length); cursor += length;
					return true;
				};
				if (!text(command.shader_source, 262144, false) || end - cursor < 4) return fail("Invalid shader source");
				uint32_t uniforms = read_u32(p + cursor); cursor += 4;
				if (uniforms > 1024) return fail("Too many shader constants");
				std::unordered_map<std::string, bool> names;
				for (uint32_t u = 0; u < uniforms; ++u) {
					ShaderConstant value;
					if (!text(value.name, 128, true) || !names.emplace(value.name, true).second || end - cursor < 12) return fail("Invalid shader constant name");
					value.type = read_u32(p + cursor); value.components = read_u32(p + cursor + 4); value.array_count = read_u32(p + cursor + 8); cursor += 12;
					if (value.type > 1 || value.components < 1 || value.components > 4 || value.array_count > 1024 || (value.array_count && value.components != 4)) return fail("Invalid shader constant shape");
					uint32_t words = value.components * (value.array_count ? value.array_count : 1);
					if (words * 4 > end - cursor) return fail("Truncated shader constant");
					for (uint32_t w = 0; w < words; ++w) {
						uint32_t bits = read_u32(p + cursor); cursor += 4;
						float f; std::memcpy(&f, &bits, 4);
						if (!value.type && !std::isfinite(f)) return fail("Non-finite shader constant");
						value.words.push_back(bits);
					}
					command.constants.push_back(std::move(value));
				}
				if (end - cursor < 4) return fail("Missing shader sampler count");
				uint32_t samplers = read_u32(p + cursor); cursor += 4;
				if (samplers > 16) return fail("Too many shader samplers");
				for (uint32_t s = 0; s < samplers; ++s) {
					std::string name;
					if (!text(name, 128, true) || !names.emplace(name, true).second || end - cursor < 8) return fail("Invalid shader sampler");
					uint64_t handle = uint64_t(read_u32(p + cursor)) | (uint64_t(read_u32(p + cursor + 4)) << 32); cursor += 8;
					command.samplers.emplace(name, handle);
				}
				if (cursor != end) return fail("Trailing shader state data");
			} break;
			case Opcode::CLEAR:
				if (size != 0) return fail("Invalid clear payload");
				break;
			case Opcode::RECTANGLE:
				if (size != 32) return fail("Invalid rectangle payload");
				for (size_t j = 0; j < 8; ++j) {
					uint32_t bits = read_u32(p + offset + j * 4);
					std::memcpy(&command.values[j], &bits, sizeof(float));
					if (!std::isfinite(command.values[j])) return fail("Non-finite rectangle value");
				}
				if (command.values[2] < 0 || command.values[3] < 0) return fail("Negative rectangle size");
				for (size_t j = 4; j < 8; ++j) {
					if (command.values[j] < 0 || command.values[j] > 1) return fail("Color outside 0..1");
				}
				break;
			case Opcode::RESIZE:
				if (size != 8) return fail("Invalid resize payload");
				command.width = read_u32(p + offset);
				command.height = read_u32(p + offset + 4);
				if (!command.width || !command.height || command.width > 8192 || command.height > 8192) return fail("Invalid surface size");
				break;
			case Opcode::TEXTURE_CREATE:
			case Opcode::TEXTURE_UPDATE:
			case Opcode::VIDEO_PLANE_ALLOCATE:
			case Opcode::TEXTURE_ALLOCATE:
			case Opcode::FLOAT_TEXTURE_ALLOCATE:
			case Opcode::FLOAT_TEXTURE_PATCH:
			case Opcode::TARGET_ALLOCATE:
			case Opcode::ALPHA_TEXTURE_PATCH:
			case Opcode::TEXTURE_PATCH:
			case Opcode::TEXTURE_DISPOSE: {
				if (size < 8) return fail("Truncated texture handle");
				command.texture_handle = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				if (!uint32_t(command.texture_handle) || !(command.texture_handle >> 32)) return fail("Invalid texture handle");
				if (command.opcode == Opcode::TEXTURE_DISPOSE) {
					if (size != 8) return fail("Invalid texture disposal payload");
					break;
				}
				bool floating = command.opcode == Opcode::FLOAT_TEXTURE_ALLOCATE || command.opcode == Opcode::FLOAT_TEXTURE_PATCH;
				bool allocation = command.opcode == Opcode::VIDEO_PLANE_ALLOCATE || command.opcode == Opcode::TEXTURE_ALLOCATE || command.opcode == Opcode::TARGET_ALLOCATE || command.opcode == Opcode::FLOAT_TEXTURE_ALLOCATE;
				uint32_t header = command.opcode == Opcode::ALPHA_TEXTURE_PATCH || command.opcode == Opcode::TEXTURE_PATCH || command.opcode == Opcode::FLOAT_TEXTURE_PATCH ? 24 : 16;
				if (size < header) return fail("Truncated texture dimensions");
				if (header == 24) { command.x = read_u32(p + offset + 8); command.y = read_u32(p + offset + 12); }
				command.width = read_u32(p + offset + header - 8); command.height = read_u32(p + offset + header - 4);
				if (!command.width || !command.height || command.width > 8192 || command.height > 8192 ||
					(allocation ? size != 16 : uint64_t(command.width) * command.height * (floating ? 16 : command.opcode == Opcode::ALPHA_TEXTURE_PATCH ? 1 : 4) != size - header)) return fail("Invalid texture image dimensions/length");
				if (floating && !allocation) {
					for (uint32_t j = header; j < size; j += 4) {
						uint32_t bits = read_u32(p + offset + j); float value; std::memcpy(&value, &bits, 4);
						if (!std::isfinite(value)) return fail("Non-finite float texture value");
					}
				}
				command.pixels.assign(p + offset + header, p + offset + size);
			} break;
			case Opcode::QUADS:
			case Opcode::TEXTURED_QUADS: {
				uint32_t prefix = command.opcode == Opcode::TEXTURED_QUADS ? 8 : 0;
				if (size < prefix + 12) return fail("Truncated quad vertex count");
				if (prefix) command.texture_handle = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				command.geometry_handle = uint64_t(read_u32(p + offset + prefix)) | (uint64_t(read_u32(p + offset + prefix + 4)) << 32);
				if (command.geometry_handle > INT64_MAX) return fail("Invalid geometry handle");
				size_t vertex_offset = offset + prefix + 8;
				uint32_t vertices = read_u32(p + vertex_offset);
				if (!vertices || vertices % 4 || vertices > 65536 || size != prefix + 12 + vertices * 32 + 28) return fail("Invalid quad vertex count/length");
				command.vertices.resize(size_t(vertices) * 7);
				command.colors.resize(size_t(vertices) * 4);
				for (uint32_t v = 0; v < vertices; ++v) {
					for (size_t a = 0; a < 7; ++a) {
						uint32_t bits = read_u32(p + vertex_offset + 4 + v * 32 + a * 4);
						float value;
						std::memcpy(&value, &bits, sizeof(float));
						if (!std::isfinite(value)) return fail("Non-finite quad attribute");
						if (a == 2 && value != 0) return fail("3D quad projection is not implemented");
						command.vertices[v * 7 + a] = value;
					}
					std::memcpy(command.colors.data() + v * 4, p + vertex_offset + 4 + v * 32 + 28, 4);
				}
				for (size_t t = 0; t < 6; ++t) {
					uint32_t bits = read_u32(p + vertex_offset + 4 + vertices * 32 + t * 4);
					std::memcpy(&command.transform[t], &bits, sizeof(float));
					if (!std::isfinite(command.transform[t])) return fail("Non-finite quad transform");
				}
				uint32_t alpha_bits = read_u32(p + vertex_offset + 4 + vertices * 32 + 24);
				std::memcpy(&command.draw_alpha, &alpha_bits, sizeof(float));
				if (!std::isfinite(command.draw_alpha) || command.draw_alpha < 0 || command.draw_alpha > 1) return fail("Invalid draw modulation");
			} break;
			case Opcode::QUADS_REF: {
				if (size != 44) return fail("Invalid geometry reference payload");
				command.geometry_handle = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				command.texture_handle = uint64_t(read_u32(p + offset + 8)) | (uint64_t(read_u32(p + offset + 12)) << 32);
				if (!command.geometry_handle || command.geometry_handle > INT64_MAX) return fail("Invalid geometry handle");
				if (command.texture_handle > INT64_MAX) return fail("Invalid geometry reference texture");
				for (size_t t = 0; t < 6; ++t) {
					uint32_t bits = read_u32(p + offset + 16 + t * 4);
					std::memcpy(&command.transform[t], &bits, sizeof(float));
					if (!std::isfinite(command.transform[t])) return fail("Non-finite quad transform");
				}
				uint32_t alpha_bits = read_u32(p + offset + 40);
				std::memcpy(&command.draw_alpha, &alpha_bits, sizeof(float));
				if (!std::isfinite(command.draw_alpha) || command.draw_alpha < 0 || command.draw_alpha > 1) return fail("Invalid draw modulation");
			} break;
			case Opcode::GEOMETRY_FREE: {
				if (size != 8) return fail("Invalid geometry disposal payload");
				command.geometry_handle = uint64_t(read_u32(p + offset)) | (uint64_t(read_u32(p + offset + 4)) << 32);
				if (!command.geometry_handle || command.geometry_handle > INT64_MAX) return fail("Invalid geometry handle");
			} break;
			default:
				return fail("Unknown command opcode");
		}
		result.commands.push_back(std::move(command));
		offset += size;
	}
	if (offset != bytes.size()) return fail("Trailing frame data");
	out = std::move(result);
	error.clear();
	return true;
}

enum class SubmitResult { ACCEPTED, FULL, STOPPED, STALE, INVALID_RESOURCE };

// Projected state includes queued batches, not only work already consumed by
// Godot. A failed transaction cannot reserve generations or retire live data.
class TextureLedger {
	struct Slot { uint32_t generation = 0, width = 0, height = 0; bool live = false, referenced = false, render_target = false, floating = false, scene = false, single_channel = false; };
	std::unordered_map<uint32_t, Slot> slots;
	std::unordered_map<uint64_t, uint64_t> presented_windows;
	uint64_t live_bytes = 0, retired_bytes = 0;
	bool presentation_mode = false, present_open = false;
	uint64_t active_target = 0;
	bool target_pass_open = true;
	bool pass_has_draws = false;

public:
	// Admission sanity bound, not memory policing: real allocations are
	// bounded by actual demand. Must stay coordinated with the Java-side
	// pool ceiling (GodotTexturePool), which previously shielded this bound.
	static constexpr uint64_t MAX_BYTES = 1024ULL * 1024 * 1024;

	bool apply(const Frame &frame) {
		for (const Command &command : frame.commands) {
			if (command.opcode == Opcode::WINDOW_CONFIGURE) {
				if (present_open || pass_has_draws || (target_pass_open && active_target) || !presented_windows.count(command.window_id)) return false;
				continue;
			}
			if (command.opcode == Opcode::WINDOW_REMOVE) {
				if (present_open || pass_has_draws || (target_pass_open && active_target) || !command.window_id || command.window_id > INT64_MAX) return false;
				presented_windows.erase(command.window_id);
				continue;
			}
			if (command.opcode == Opcode::SCENE_INPUT) {
				auto source = slots.find(uint32_t(command.texture_handle));
				if (source == slots.end() || !source->second.live || !source->second.scene || source->second.generation != uint32_t(command.texture_handle >> 32)) return false;
				continue;
			}
			if (command.opcode == Opcode::SCENE_TEXTURE_RESIZE) {
				uint32_t id = uint32_t(command.texture_handle), generation = uint32_t(command.texture_handle >> 32);
				auto source = slots.find(uint32_t(command.source_handle));
				auto next = slots.find(id);
				if (!id || id > 4096 || !generation || generation > INT32_MAX || source == slots.end() || !source->second.live || !source->second.scene || source->second.referenced || source->second.generation != uint32_t(command.source_handle >> 32)) return false;
				if ((next != slots.end() && next->second.live) || generation != (next == slots.end() ? 0 : next->second.generation) + 1) return false;
				uint64_t old_bytes = uint64_t(source->second.width) * source->second.height * 4;
				uint64_t new_bytes = uint64_t(command.width) * command.height * 4;
				if (live_bytes - old_bytes + new_bytes + retired_bytes > MAX_BYTES) return false;
				source->second.live = false;
				slots[id] = {generation, command.width, command.height, true, false, false, false, true};
				live_bytes = live_bytes - old_bytes + new_bytes;
				continue;
			}
			if (command.opcode == Opcode::TARGET_SELECT) {
				if (pass_has_draws) return false;
				uint64_t handle = command.texture_handle;
				if (handle) {
					auto found = slots.find(uint32_t(handle));
					if (found == slots.end() || !found->second.live || !found->second.render_target || found->second.generation != uint32_t(handle >> 32)) return false;
				}
				active_target = handle;
				target_pass_open = true;
				if (handle) slots[uint32_t(handle)].referenced = true;
				continue;
			}
			if (command.opcode == Opcode::END_PASS) {
				if (!target_pass_open) return false;
				target_pass_open = false;
				pass_has_draws = false;
				retired_bytes = 0;
				for (auto &entry : slots) entry.second.referenced = false;
				continue;
			}
			if (command.opcode == Opcode::BEGIN_PRESENT) {
				if (present_open) return false;
				presentation_mode = present_open = true;
				target_pass_open = true; active_target = 0; pass_has_draws = false;
			} else if (command.opcode == Opcode::PRESENT || command.opcode == Opcode::WINDOW_PRESENT || command.opcode == Opcode::NATIVE_WINDOW_PRESENT) {
				if (!present_open || !target_pass_open) return false;
				if (command.opcode == Opcode::WINDOW_PRESENT || command.opcode == Opcode::NATIVE_WINDOW_PRESENT) {
					auto target = slots.find(uint32_t(active_target));
					if (!command.window_id || command.window_id > INT64_MAX || !active_target || target == slots.end() || !target->second.live || !target->second.render_target || target->second.generation != uint32_t(active_target >> 32)) return false;
					if (!presented_windows.count(command.window_id) && presented_windows.size() >= 64) return false;
					presented_windows[command.window_id] = active_target;
				}
				present_open = false;
				target_pass_open = false;
				pass_has_draws = false;
				// The consumer pauses at PRESENT until post-draw cleanup. Future
				// queued commands therefore need no earlier frame's texture versions.
				retired_bytes = 0;
				for (auto &entry : slots) entry.second.referenced = false;
				continue;
			// Explicit offscreen targets may be rendered between window frames
			// (for example Node.snapshot). Root drawing still requires an open
			// presentation once retained presentation mode has been entered.
			} else if ((!target_pass_open || (presentation_mode && !present_open && !active_target)) && (command.opcode == Opcode::CLEAR || command.opcode == Opcode::QUADS || command.opcode == Opcode::TEXTURED_QUADS || command.opcode == Opcode::QUADS_REF || command.opcode == Opcode::RECTANGLE || command.opcode == Opcode::CLIP || command.opcode == Opcode::SHADER_STATE)) return false;
			if (command.opcode == Opcode::QUADS || command.opcode == Opcode::TEXTURED_QUADS || command.opcode == Opcode::QUADS_REF || command.opcode == Opcode::RECTANGLE || command.opcode == Opcode::CLEAR) pass_has_draws = true;
			if (active_target && (command.opcode == Opcode::QUADS || command.opcode == Opcode::TEXTURED_QUADS || command.opcode == Opcode::QUADS_REF || command.opcode == Opcode::RECTANGLE || command.opcode == Opcode::CLEAR)) {
				auto target = slots.find(uint32_t(active_target));
				if (target == slots.end() || !target->second.live || target->second.generation != uint32_t(active_target >> 32)) return false;
				target->second.referenced = true;
			}
			if (command.opcode == Opcode::SHADER_STATE) {
				for (const auto &sampler : command.samplers) {
					if (active_target && sampler.second == active_target) return false;
					uint32_t id = uint32_t(sampler.second), generation = uint32_t(sampler.second >> 32);
					auto found = slots.find(id);
					if (!id || id > 4096 || !generation || generation > INT32_MAX || found == slots.end() || !found->second.live || found->second.generation != generation) return false;
					found->second.referenced = true;
				}
				continue;
			}
			if (command.opcode == Opcode::CLEAR || command.opcode == Opcode::BEGIN_PRESENT) {
				retired_bytes = 0;
				for (auto &entry : slots) entry.second.referenced = false;
				if (active_target) slots[uint32_t(active_target)].referenced = true;
				continue;
			}
			if (command.opcode == Opcode::QUADS_REF && !command.texture_handle) continue;
			if (command.opcode != Opcode::TEXTURE_CREATE && command.opcode != Opcode::TEXTURE_UPDATE &&
				command.opcode != Opcode::TEXTURE_DISPOSE && command.opcode != Opcode::TEXTURED_QUADS &&
				command.opcode != Opcode::QUADS_REF &&
				command.opcode != Opcode::VIDEO_PLANE_ALLOCATE && command.opcode != Opcode::TEXTURE_ALLOCATE && command.opcode != Opcode::TARGET_ALLOCATE && command.opcode != Opcode::TEXTURE_PATCH && command.opcode != Opcode::ALPHA_TEXTURE_PATCH &&
				command.opcode != Opcode::FLOAT_TEXTURE_ALLOCATE && command.opcode != Opcode::FLOAT_TEXTURE_PATCH && command.opcode != Opcode::SCENE_TEXTURE_ALLOCATE) continue;
			uint32_t id = uint32_t(command.texture_handle), generation = uint32_t(command.texture_handle >> 32);
			if (!id || id > 4096 || !generation || generation > INT32_MAX) return false;
			auto found = slots.find(id);
			if (command.opcode == Opcode::TEXTURE_CREATE || command.opcode == Opcode::VIDEO_PLANE_ALLOCATE || command.opcode == Opcode::TEXTURE_ALLOCATE || command.opcode == Opcode::TARGET_ALLOCATE || command.opcode == Opcode::FLOAT_TEXTURE_ALLOCATE || command.opcode == Opcode::SCENE_TEXTURE_ALLOCATE) {
				uint32_t previous = found == slots.end() ? 0 : found->second.generation;
				if ((found != slots.end() && found->second.live) || generation != previous + 1) return false;
				bool floating = command.opcode == Opcode::FLOAT_TEXTURE_ALLOCATE;
				uint64_t bytes = uint64_t(command.width) * command.height * (floating ? 16 : command.opcode == Opcode::VIDEO_PLANE_ALLOCATE ? 1 : 4);
				if (live_bytes + retired_bytes + bytes > MAX_BYTES) return false;
				slots[id] = { generation, command.width, command.height, true, false, command.opcode == Opcode::TARGET_ALLOCATE, floating, command.opcode == Opcode::SCENE_TEXTURE_ALLOCATE, command.opcode == Opcode::VIDEO_PLANE_ALLOCATE }; live_bytes += bytes;
			} else {
				if (found == slots.end() || !found->second.live || found->second.generation != generation) return false;
				if ((command.opcode == Opcode::TEXTURED_QUADS || command.opcode == Opcode::QUADS_REF) && active_target && command.texture_handle == active_target) return false;
				Slot &slot = found->second;
				uint64_t bytes = uint64_t(slot.width) * slot.height * (slot.floating ? 16 : slot.single_channel ? 1 : 4);
				if (command.opcode == Opcode::TEXTURE_UPDATE || command.opcode == Opcode::TEXTURE_PATCH || command.opcode == Opcode::ALPHA_TEXTURE_PATCH || command.opcode == Opcode::FLOAT_TEXTURE_PATCH) {
					if (slot.single_channel && command.opcode != Opcode::ALPHA_TEXTURE_PATCH) return false;
					if (slot.render_target || slot.scene || slot.floating != (command.opcode == Opcode::FLOAT_TEXTURE_PATCH)) return false;
					if (command.opcode == Opcode::TEXTURE_UPDATE && (slot.width != command.width || slot.height != command.height)) return false;
					if (command.opcode != Opcode::TEXTURE_UPDATE && (command.x > slot.width || command.y > slot.height ||
						command.width > slot.width - command.x || command.height > slot.height - command.y)) return false;
					if (slot.referenced) {
						if (live_bytes + retired_bytes + bytes > MAX_BYTES) return false;
						retired_bytes += bytes;
					}
					slot.referenced = false;
				} else if (command.opcode == Opcode::TEXTURE_DISPOSE) {
					// A retained window image remains part of the live GPU budget
					// until its layer is removed or publishes another target.
					for (const auto &window : presented_windows) if (window.second == command.texture_handle) return false;
					slot.live = false; live_bytes -= bytes;
					if (slot.referenced) retired_bytes += bytes;
				} else if (command.opcode == Opcode::TEXTURED_QUADS || command.opcode == Opcode::QUADS_REF) {
					slot.referenced = true;
				}
			}
		}
		return true;
	}
};

// Geometry deduplication handshake projected across queued frames: QUADS
// registers a fresh handle, QUADS_REF requires a live one, GEOMETRY_FREE
// retires exactly one. A handle maps 1:1 to content, so re-registration is a
// protocol violation rather than an overwrite.
class GeometryLedger {
	std::unordered_set<uint64_t> live;
public:
	bool apply(const Frame &frame) {
		for (const Command &command : frame.commands) {
			if (command.opcode == Opcode::QUADS || command.opcode == Opcode::TEXTURED_QUADS) {
				if (command.geometry_handle && !live.insert(command.geometry_handle).second) return false;
			} else if (command.opcode == Opcode::QUADS_REF) {
				if (!live.count(command.geometry_handle)) return false;
			} else if (command.opcode == Opcode::GEOMETRY_FREE) {
				if (!live.erase(command.geometry_handle)) return false;
			}
		}
		return true;
	}
};

class FrameQueue {
	std::mutex mutex;
	std::condition_variable changed;
	std::deque<Frame> frames;
	uint64_t last_sequence = 0;
	uint64_t tick = 0;
	uint64_t frame_tick = 0;
	uint64_t input_tick = 0;
	uint64_t backpressure_count = 0;
	bool stopped = false;
	TextureLedger textures;
	GeometryLedger geometries;

public:
	SubmitResult submit(Frame &&frame) {
		std::lock_guard<std::mutex> lock(mutex);
		if (stopped) return SubmitResult::STOPPED;
		if (frame.sequence <= last_sequence) return SubmitResult::STALE;
		if (frames.size() == MAX_QUEUED_FRAMES) {
			++backpressure_count;
			return SubmitResult::FULL;
		}
		TextureLedger projected = textures;
		if (!projected.apply(frame)) return SubmitResult::INVALID_RESOURCE;
		GeometryLedger projected_geometries = geometries;
		if (!projected_geometries.apply(frame)) return SubmitResult::INVALID_RESOURCE;
		uint64_t accepted_sequence = frame.sequence;
		frames.push_back(std::move(frame));
		textures = std::move(projected);
		geometries = std::move(projected_geometries);
		last_sequence = accepted_sequence;
		return SubmitResult::ACCEPTED;
	}

	bool take(Frame &frame) {
		std::lock_guard<std::mutex> lock(mutex);
		if (frames.empty()) return false;
		frame = std::move(frames.front());
		frames.pop_front();
		return true;
	}

	uint64_t get_backpressure_count() {
		std::lock_guard<std::mutex> lock(mutex);
		return backpressure_count;
	}
	uint64_t get_last_sequence() {
		std::lock_guard<std::mutex> lock(mutex);
		return last_sequence;
	}

	void pulse() {
		std::lock_guard<std::mutex> lock(mutex);
		if (!stopped) ++tick;
		changed.notify_all();
	}

	int64_t await_tick(uint64_t after, uint32_t timeout_ms) {
		std::unique_lock<std::mutex> lock(mutex);
		changed.wait_for(lock, std::chrono::milliseconds(timeout_ms), [&] { return stopped || tick > after; });
		return stopped ? -1 : static_cast<int64_t>(tick);
	}

	void pulse_frame() {
		std::lock_guard<std::mutex> lock(mutex);
		if (!stopped) { ++frame_tick; ++tick; }
		changed.notify_all();
	}

	int64_t await_frame_tick(uint64_t after, uint32_t timeout_ms) {
		std::unique_lock<std::mutex> lock(mutex);
		changed.wait_for(lock, std::chrono::milliseconds(timeout_ms), [&] { return stopped || frame_tick > after; });
		return stopped ? -1 : static_cast<int64_t>(frame_tick);
	}

	// Input events arrive between frame ticks. A dedicated waiter lets the FX
	// event thread drain them immediately, so window commands they produce can
	// still reach the current frame's host-command application.
	void pulse_input() {
		std::lock_guard<std::mutex> lock(mutex);
		if (!stopped) ++input_tick;
		changed.notify_all();
	}

	int64_t await_input_tick(uint64_t after, uint32_t timeout_ms) {
		std::unique_lock<std::mutex> lock(mutex);
		changed.wait_for(lock, std::chrono::milliseconds(timeout_ms), [&] { return stopped || input_tick > after; });
		return stopped ? -1 : static_cast<int64_t>(input_tick);
	}

	// Normal JVM completion closes admission and wakes waiters, but the host
	// still consumes accepted disposal/removal commands. Explicit host stop
	// remains a cancellation and drops pending work below.
	void finish() {
		std::lock_guard<std::mutex> lock(mutex);
		stopped = true;
		changed.notify_all();
	}

	void stop() {
		std::lock_guard<std::mutex> lock(mutex);
		stopped = true;
		frames.clear();
		textures = TextureLedger();
		geometries = GeometryLedger();
		changed.notify_all();
	}
};

} // namespace godot_javafx
