#include "javafx_shader_translate.h"
#include "servers/rendering/shader_language.h"
#include "servers/rendering/shader_types.h"
#include <cstring>

namespace godot_javafx {
namespace {
// The canonical draw header always occupies the push constant block: affine
// transform (two columns), draw modulate, pixel-space -> NDC mapping, and —
// when the perspective idiom was rewritten — the target size for the
// normalized screen coordinates.
constexpr int DRAW_HEADER_BYTES = 64;

int align_up(int p_value, int p_alignment) {
	return (p_value + p_alignment - 1) & ~(p_alignment - 1);
}

// Index of the '}' matching the '{' at p_open_brace, or -1. Braces inside
// comments and string literals do not count — probe shaders deliberately
// carry `/* } return; */` and trailing helper functions after fragment().
int find_block_end(const String &p_source, int p_open_brace) {
	int depth = 0;
	for (int i = p_open_brace; i < p_source.length(); ++i) {
		const char32_t c = p_source[i];
		const char32_t next = i + 1 < p_source.length() ? p_source[i + 1] : 0;
		if (c == '/' && next == '/') {
			while (i < p_source.length() && p_source[i] != '\n') ++i;
		} else if (c == '/' && next == '*') {
			i += 2;
			while (i + 1 < p_source.length() && !(p_source[i] == '*' && p_source[i + 1] == '/')) ++i;
			++i;
		} else if (c == '"') {
			++i;
			while (i < p_source.length() && p_source[i] != '"') {
				if (p_source[i] == '\\') ++i;
				++i;
			}
		} else if (c == '{') {
			++depth;
		} else if (c == '}') {
			if (--depth == 0) return i;
		}
	}
	return -1;
}
} // namespace

RdShaderSources translate_canvas_shader(const String &p_canvas_source) {
	RdShaderSources result;
	// The perspective fill families recover window-relative pixel coordinates
	// from the canvas screen built-ins; the RD equivalent is gl_FragCoord.xy,
	// matching canvas.glsl and the production top-left NDC mapping. The
	// runtime LCD variant instead samples the destination through a
	// hint_screen_texture sampler at a bare SCREEN_UV coordinate — translated
	// to a regular snapshot sampler and the normalized fragment position.
	bool uses_pixcoord = p_canvas_source.contains("SCREEN_UV / SCREEN_PIXEL_SIZE");
	bool uses_screen_uv = p_canvas_source.contains("SCREEN_UV") && !uses_pixcoord;
	bool uses_screen_size = p_canvas_source.contains("SCREEN_PIXEL_SIZE") && !uses_pixcoord;
	if (uses_screen_uv || uses_screen_size || uses_pixcoord) {
		// Any screen builtin requires the target size push member.
		uses_pixcoord = true;
	}
	// Substrings only decide whether parsing is needed, never the mode itself:
	// generated Blend_ADD/Blend_MULTIPLY shaders have same-named helper functions.
	const bool parse_blend_mode = p_canvas_source.contains("blend_disabled") ||
			p_canvas_source.contains("blend_add") || p_canvas_source.contains("blend_mul");
	const int fragment_at = p_canvas_source.find("void fragment()");
	String body;
	String fragment_tail;
	if (fragment_at < 0) {
		// Implicit-fragment sources (the clear/blit family) rely on the
		// canvas default fragment, which passes the item's vertex color
		// through (its default texture is white); the RD equivalent needs
		// no texture at all.
		body = "\tCOLOR = godot_vertex_color;\n";
	} else {
		const int open_brace = p_canvas_source.find("{", fragment_at);
		const int close_brace = open_brace >= 0 ? find_block_end(p_canvas_source, open_brace) : -1;
		if (open_brace < 0 || close_brace < 0) {
			result.error = "fragment body not terminated";
			return result;
		}
		body = p_canvas_source.substr(open_brace + 1, close_brace - open_brace - 1);
		// Helpers declared after fragment() stay ahead of the generated main.
		fragment_tail = p_canvas_source.substr(close_brace + 1).strip_edges();
	}
	if (body.contains("SCREEN_UV / SCREEN_PIXEL_SIZE")) {
		body = body.replace("SCREEN_UV / SCREEN_PIXEL_SIZE", "gl_FragCoord.xy");
	}
	// RD target NDC maps increasing local Y to increasing framebuffer Y;
	// snapshots use that same orientation, so normalized sampling needs no flip.
	if (body.contains("SCREEN_UV")) {
		body = body.replace("SCREEN_UV", "vec2(gl_FragCoord.x / target_size.x, gl_FragCoord.y / target_size.y)");
	}
	if (body.contains("SCREEN_PIXEL_SIZE")) {
		body = body.replace("SCREEN_PIXEL_SIZE", "vec2(1.0 / target_size.x, 1.0 / target_size.y)");
	}
	// Ad-hoc Java sources (the blit shader) use the built-in UV directly in
	// the fragment; the canonical vertex stage always provides godot_uv0.
	// Token-scan so longer identifiers (SCREEN_UV already rewritten) survive.
	if (body.contains("UV") && !p_canvas_source.contains("varying vec2 godot_uv0")) {
		String rewritten_uv;
		int cursor = 0;
		while (cursor < body.length()) {
			const int at = body.find("UV", cursor);
			if (at < 0) { rewritten_uv += body.substr(cursor); break; }
			const char before = at > 0 ? body[at - 1] : ' ';
			const int after_at = at + 2;
			const char after = after_at < body.length() ? body[after_at] : ' ';
			const bool word_before = (before >= 'a' && before <= 'z') || (before >= 'A' && before <= 'Z') || (before >= '0' && before <= '9') || before == '_';
			const bool word_after = (after >= 'a' && after <= 'z') || (after >= 'A' && after <= 'Z') || (after >= '0' && after <= '9') || after == '_';
			if (word_before || word_after) rewritten_uv += body.substr(cursor, after_at - cursor);
			else rewritten_uv += body.substr(cursor, at - cursor) + "godot_uv0";
			cursor = after_at;
		}
		body = rewritten_uv;
	}
	// Raw GLSL cannot read back an out variable. Route every reference
	// through a local that starts as the interpolated vertex color — the
	// canvas fragment-entry COLOR — so reads, member writes and compound
	// assignments (the node-effect wrapper's `COLOR *= sample`) keep their
	// sequential GLSL semantics. Token-scan so longer identifiers survive.
	{
		String rewritten;
		int cursor = 0;
		while (cursor < body.length()) {
			const int at = body.find("COLOR", cursor);
			if (at < 0) { rewritten += body.substr(cursor); break; }
			const char before = at > 0 ? body[at - 1] : ' ';
			const int after_at = at + 5;
			const char after = after_at < body.length() ? body[after_at] : ' ';
			const bool word_before = (before >= 'a' && before <= 'z') || (before >= 'A' && before <= 'Z') || (before >= '0' && before <= '9') || before == '_';
			const bool word_after = (after >= 'a' && after <= 'z') || (after >= 'A' && after <= 'Z') || (after >= '0' && after <= '9') || after == '_';
			if (word_before || word_after) rewritten += body.substr(cursor, after_at - cursor);
			else rewritten += body.substr(cursor, at - cursor) + "godot_out";
			cursor = after_at;
		}
		body = rewritten;
	}
	body = "\tvec4 godot_out = godot_vertex_color;\n" + body + "\n\tfrag_color = godot_out;\n";

	// Header surgery: drop shader_type/render_mode/varying lines and the whole
	// vertex() block (the vertex stage is canonicalized), keep samplers as
	// combined image samplers, and collect every value uniform (scalar or
	// array) into a std140 uniform buffer bound on set 0 after the samplers.
	String header_kept;
	String value_members;
	String screen_sampler_decl;
	int value_cursor = 0;
	bool has_value_defaults = false;
	bool skipping_vertex = false;
	const int header_end = fragment_at >= 0 ? fragment_at : p_canvas_source.length();
	Vector<String> lines = p_canvas_source.substr(0, header_end).split("\n");
	for (const String &raw : lines) {
		String line = raw.strip_edges(true, false);
		if (skipping_vertex) {
			if (line.contains("}")) skipping_vertex = false;
			continue;
		}
		if (line.begins_with("shader_type") || line.begins_with("render_mode") || line.begins_with("varying")) {
			continue;
		}
		if (line.begins_with("void vertex()")) {
			skipping_vertex = true;
			continue;
		}
		if (line.begins_with("uniform")) {
			// uniform <type> <name>; / <name>[N]; / <name> : hints;
			// One-line user sources pack several declarations per line, and
			// canvas defaults (`= vec3(1.0)`) must not leak into the std140
			// block members — GLSL forbids initializers there.
			while (line.begins_with("uniform")) {
				const int semi = line.find(";");
				const int space1 = line.find(" ");
				const int space2 = line.find(" ", space1 + 1);
				if (semi < 0 || space1 < 0 || space2 < 0 || space2 > semi) {
					result.error = "malformed uniform declaration";
					return result;
				}
				const String type = line.substr(space1 + 1, space2 - space1 - 1).strip_edges();
				String name = line.substr(space2 + 1, semi - space2 - 1).strip_edges();
				if (type != "sampler2D" && name.contains("=")) has_value_defaults = true;
				String hints;
				if (const int colon = name.find(":"); colon >= 0) {
					hints = name.substr(colon + 1).strip_edges();
					name = name.substr(0, colon).strip_edges();
				}
				int array_size = 0;
				if (const int bracket = name.find("["); bracket >= 0) {
					array_size = name.substr(bracket + 1, name.find("]") - bracket - 1).to_int();
					name = name.substr(0, bracket).strip_edges();
					if (array_size < 1 || array_size > 1024) {
						result.error = "uniform array size out of range: " + name;
						return result;
					}
				}
				if (const int equal = name.find("="); equal >= 0) {
					has_value_defaults = true;
					name = name.substr(0, equal).strip_edges();
				}
				if (type == "sampler2D") {
					result.sampler_names.push_back(StringName(name));
					// The runtime LCD variant samples the destination through a
					// hint_screen_texture sampler; raw GLSL has no hints, so it
					// becomes a regular snapshot sampler with its original name.
					if (hints.contains("hint_screen_texture")) {
						if (result.screen_sampler_index >= 0) {
							result.error = "multiple screen samplers in one shader";
							return result;
						}
						result.screen_sampler_index = result.sampler_names.size() - 1;
						screen_sampler_decl = "layout(set = 0, binding = " + itos(result.sampler_names.size() - 1) + ") uniform sampler2D " + name + ";\n";
					} else {
						// Raw RD GLSL requires an explicit binding on every
						// sampler; declaration order defines the layout (set 0).
						header_kept += "layout(set = 0, binding = " + itos(result.sampler_names.size() - 1) + ") uniform " + type + " " + name + ";\n";
					}
				} else {
					RdValueUniform value;
					value.name = StringName(name);
					value.integer = type.begins_with("i");
					value.count = array_size > 0 ? array_size : 1;
					value.is_array = array_size > 0;
					int components = 1, alignment = 4, natural = 4;
					if (type == "vec2" || type == "ivec2") { components = 2; alignment = 8; natural = 8; }
					else if (type == "vec3" || type == "ivec3") { components = 3; alignment = 16; natural = 12; }
					else if (type == "vec4" || type == "ivec4") { components = 4; alignment = 16; natural = 16; }
					else if (type != "float" && type != "int") {
						result.error = "unsupported uniform type: " + type;
						return result;
					}
					value.words = components;
					if (array_size > 0) {
						// std140 rounds every array element up to a 16-byte stride and
						// aligns the member itself to 16.
						value.offset = align_up(value_cursor, 16);
						value.stride = 16;
						value_cursor = value.offset + array_size * 16;
					} else {
						value.offset = align_up(value_cursor, alignment);
						value.stride = natural;
						value_cursor = value.offset + natural;
					}
					result.value_uniforms.push_back(value);
					value_members += "\t" + type + " " + name + (array_size > 0 ? "[" + itos(array_size) + "]" : "") + ";\n";
				}
				line = semi + 1 < line.length() ? line.substr(semi + 1).strip_edges(true, false) : String();
			}
			if (!line.is_empty()) header_kept += line + "\n";
			continue;
		}
		header_kept += raw + "\n";
	}
	if (!fragment_tail.is_empty()) header_kept += fragment_tail + "\n";
	if (result.screen_sampler_index >= 0) {
		// Helpers reference the screen sampler by its canvas name; the kept
		// header needs the snapshot declaration before use. Preserve its name:
		// both helpers and fragment() may reference any declared sampler name.
		header_kept = screen_sampler_decl + header_kept;
	}
	result.push_constant_bytes = DRAW_HEADER_BYTES + (uses_pixcoord ? 8 : 0);
	result.value_buffer_bytes = result.value_uniforms.is_empty() ? 0 : align_up(value_cursor, 16);
	if (has_value_defaults || parse_blend_mode) {
		// Use the engine's constant evaluator, including constructor splats and
		// constant expressions. Removing GLSL member initializers must not erase
		// the canvas defaults when the application omits a parameter override.
		ShaderLanguage parser;
		ShaderLanguage::ShaderCompileInfo info;
		ShaderTypes *types = ShaderTypes::get_singleton();
		info.functions = types->get_functions(RSE::SHADER_CANVAS_ITEM);
		info.render_modes = types->get_modes(RSE::SHADER_CANVAS_ITEM);
		info.stencil_modes = types->get_stencil_modes(RSE::SHADER_CANVAS_ITEM);
		info.shader_types = types->get_types();
		if (parser.compile(p_canvas_source, info) != OK) {
			result.error = "Cannot parse canvas modes/defaults: " + parser.get_error_text();
			return result;
		}
		for (const StringName &mode : parser.get_shader()->render_modes) {
			if (mode == "blend_disabled") result.blend_mode = RdShaderSources::BLEND_DISABLED;
			else if (mode == "blend_add") result.blend_mode = RdShaderSources::BLEND_ADD;
			else if (mode == "blend_mul") result.blend_mode = RdShaderSources::BLEND_MUL;
			else if (mode == "blend_premul_alpha") result.blend_mode = RdShaderSources::BLEND_PREMUL;
		}
		if (has_value_defaults) {
			result.value_defaults.resize(result.value_buffer_bytes);
			memset(result.value_defaults.ptrw(), 0, result.value_defaults.size());
			for (const RdValueUniform &value : result.value_uniforms) {
				const auto *uniform = parser.get_shader()->uniforms.getptr(value.name);
				if (uniform == nullptr) continue;
				for (int element = 0; element < value.count; ++element) {
					for (int word = 0; word < value.words; ++word) {
						int index = element * value.words + word;
						if (index >= uniform->default_value.size()) continue;
						const auto &scalar = uniform->default_value[index];
						const void *bits = value.integer ? static_cast<const void *>(&scalar.sint) : static_cast<const void *>(&scalar.real);
						memcpy(result.value_defaults.ptrw() + value.offset + element * value.stride + word * 4, bits, 4);
					}
				}
			}
		}
	}

	// Both blocks are anonymous so their members stay in global scope:
	// generated bodies reference value uniforms by their bare names, exactly
	// as they did as loose uniforms.
	const String push_block = "layout(push_constant, std430) uniform DrawParams {\n"
			"\tvec4 xform_x;\n"
			"\tvec4 xform_y;\n"
			"\tvec4 modulate;\n"
			"\tvec4 target_ndc;\n" +
			(uses_pixcoord ? String("\tvec2 target_size;\n") : String()) +
			"};\n";
	const String value_block = result.value_buffer_bytes == 0 ? String() :
			"layout(set = 0, binding = " + itos(result.sampler_names.size()) + ", std140) uniform ShaderValues {\n" +
			value_members + "};\n";

	// The vertex stage is canonical: it always provides all three varyings,
	// so any subset consumed by the fragment links without declarations that
	// the generated corpus never varies.
	result.vertex_source = "#version 450\n" + push_block +
			"layout(location = 0) in vec2 vertex_position;\n"
			"layout(location = 1) in vec2 vertex_uv0;\n"
			"layout(location = 2) in vec2 vertex_uv1;\n"
			"layout(location = 3) in vec4 vertex_color;\n"
			"layout(location = 0) out vec2 godot_uv0;\n"
			"layout(location = 1) out vec2 godot_uv1;\n"
			"layout(location = 2) out vec4 godot_vertex_color;\n"
			"void main() {\n"
			"\tgodot_uv0 = vertex_uv0;\n"
			"\tgodot_uv1 = vertex_uv1;\n"
			"\tgodot_vertex_color = vertex_color * modulate;\n"
			"\tvec2 local = vec2(dot(xform_x.xy, vertex_position) + xform_x.z,\n"
			"\t\t\tdot(xform_y.xy, vertex_position) + xform_y.z);\n"
			"\tgl_Position = vec4(local * target_ndc.xy + target_ndc.zw, 0.0, 1.0);\n"
			"}\n";

	// The vertex stage is canonical: it always provides all three varyings,
	// so declare them unconditionally — bodies reference canonical names (the
	// node-effect wrapper's rewritten UV) even when the canvas source never
	// declared them, and unused inputs link fine against the full output set.
	String varyings;
	varyings += "layout(location = 0) in vec2 godot_uv0;\n";
	varyings += "layout(location = 1) in vec2 godot_uv1;\n";
	varyings += "layout(location = 2) in vec4 godot_vertex_color;\n";

	result.fragment_source = "#version 450\n" + push_block + value_block + varyings +
			"layout(location = 0) out vec4 frag_color;\n" +
			header_kept +
			"void main() {" + body + "}\n";
	result.ok = true;
	return result;
}

} // namespace godot_javafx
