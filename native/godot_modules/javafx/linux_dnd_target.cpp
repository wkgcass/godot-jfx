#ifdef LINUXBSD_ENABLED
#include "linux_dnd.h"
#include <glib.h>
#include "macos_custom_format.h"
#include <algorithm>

namespace godot_javafx::linux_dnd {
bool wayland_custom_name(std::u16string_view name) {
	constexpr std::u16string_view prefix = u"application/x-";
	if (name.size() <= prefix.size() || name.size() > custom_format::MAX_NAME_CHARS ||
			name.substr(0, prefix.size()) != prefix) return false;
	auto suffix = name.substr(prefix.size());
	if (suffix.substr(0, 5) == u"java-" || suffix == u"godot-custom-") return false;
	return std::all_of(suffix.begin(), suffix.end(), [](char16_t c) {
		return (c >= u'a' && c <= u'z') || (c >= u'0' && c <= u'9') || c == u'-' || c == u'.' || c == u'_';
	});
}

namespace {
bool custom_type(const std::string &name) {
	if (name.size() > custom_format::MAX_NAME_CHARS) return false;
	std::u16string wide(name.begin(), name.end());
	return wayland_custom_name(wide);
}

bool text_type(const std::string &type) {
	return type == "text/plain;charset=utf-8" || type == "text/plain";
}

void mime(Payload &p, const std::string &name) {
	if (!p.mimes.empty()) p.mimes += '\n';
	p.mimes += name;
}

bool from_utf8(const std::string &s, size_t max_units, std::u16string &output) {
	if (s.empty() || s.find('\0') != std::string::npos) return false;
	glong units = 0;
	std::unique_ptr<gunichar2, decltype(&g_free)> wide(g_utf8_to_utf16(s.data(), s.size(), nullptr, &units, nullptr), g_free);
	if (!wide || size_t(units) > max_units) return false;
	output.assign(reinterpret_cast<const char16_t *>(wide.get()), units);
	return true;
}

void decode_uris(Payload &p, const std::string &bytes) {
	if (bytes.find('\0') != std::string::npos) return;
	std::unique_ptr<gchar *, decltype(&g_strfreev)> uris(g_uri_list_extract_uris(bytes.c_str()), g_strfreev);
	size_t count = 0;
	std::u16string paths;
	for (auto **uri = uris.get(); uri && *uri; ++uri) {
		if (!g_str_has_prefix(*uri, "file:")) {
			if (!p.has_url && from_utf8(*uri, MAX_URL_CHARS, p.url)) {
				p.has_url = true;
				mime(p, "text/uri-list");
			}
			continue;
		}
		gchar *hostname = nullptr;
		std::unique_ptr<gchar, decltype(&g_free)> path(g_filename_from_uri(*uri, &hostname, nullptr), g_free);
		std::unique_ptr<gchar, decltype(&g_free)> host(hostname, g_free);
		if (!path || (hostname && *hostname && g_ascii_strcasecmp(hostname, "localhost") != 0)) continue;
		std::u16string wide;
		if (!from_utf8(path.get(), MAX_PATH_CHARS, wide) || wide.find(u'\n') != std::u16string::npos) continue;
		if (++count > MAX_PATHS) return;
		if (!paths.empty()) paths += u'\n';
		paths += wide;
	}
	if (!paths.empty()) {
		p.files = std::move(paths);
		p.has_files = true;
		mime(p, "application/x-java-file-list");
	}
}

}

bool supported_format(const std::string &type) {
	return text_type(type) || type == "text/html" || type == "text/rtf" || type == "text/uri-list" || custom_type(type);
}

void decode_format(Payload &p, const std::string &type, std::string bytes) {
	const bool custom = custom_type(type);
	if (!custom || custom_format::valid_name(std::u16string(type.begin(), type.end()))) {
		if (!bytes.empty() && bytes.back() == '\0') bytes.pop_back();
		if (bytes.find('\0') != std::string::npos) return;
	}
	if (text_type(type)) {
		if (!p.has_text && from_utf8(bytes, MAX_TEXT_BYTES / 2, p.text)) {
			p.has_text = true;
			mime(p, "text/plain");
		}
	} else if (type == "text/uri-list") {
		decode_uris(p, bytes);
	} else if (type == "text/rtf" || type == "text/html") {
		if (bytes.size() >= MAX_TEXT_BYTES) return;
		bytes.push_back('\0');
		if (type == "text/html") { p.has_html = true; p.html = std::move(bytes); }
		else { p.has_rtf = true; p.rtf = std::move(bytes); }
		mime(p, type);
	} else if (custom && bytes.size() < custom_format::MAX_DATA_BYTES && p.custom.size() < custom_format::MAX_FORMATS) {
		bytes.push_back('\0');
		p.custom.emplace_back(std::u16string(type.begin(), type.end()), std::move(bytes));
		mime(p, type);
	}
}

uint32_t TargetHandler::dispatch(int kind, uint32_t effects, uint32_t keys) {
	const Payload &p = enter_payload;
	return effects & call_target(upcall, kind, id, x, y, effects, keys, p.mimes,
			p.has_text ? &p.text : nullptr, p.has_html ? &p.html : nullptr, p.has_rtf ? &p.rtf : nullptr,
			p.has_url ? &p.url : nullptr, p.has_files ? &p.files : nullptr, p.custom.empty() ? nullptr : &p.custom);
}

void TargetHandler::leave() {
	bool notify = !enter_payload.mimes.empty();
	enter_payload = {};
	wayland_offer = 0;
	wayland_mime.clear();
	accepted = 0;
	if (notify) dispatch(3, 0, 0);
}
}
#endif
