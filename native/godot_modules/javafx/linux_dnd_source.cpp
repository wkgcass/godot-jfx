#ifdef LINUXBSD_ENABLED
#include "linux_dnd.h"
#include "macos_custom_format.h"
#include <glib.h>
#include <map>

namespace godot_javafx::linux_dnd {
namespace {
std::string to_utf8(const std::u16string &value) {
	std::unique_ptr<gchar, decltype(&g_free)> text(g_utf16_to_utf8(
			reinterpret_cast<const gunichar2 *>(value.data()), value.size(), nullptr, nullptr, nullptr), g_free);
	if (!text) throw std::invalid_argument("Invalid UTF-16 in drag data");
	return text.get();
}
}

Formats encode_formats(const SourceData &source) {
	Formats formats;
	if (!source.text.empty()) {
		formats["text/plain;charset=utf-8"] = to_utf8(source.text);
		formats["text/plain"] = formats["text/plain;charset=utf-8"];
	}
	if (!source.html.empty()) formats["text/html"] = source.html.substr(0, source.html.size() - 1);
	if (!source.rtf.empty()) formats["text/rtf"] = source.rtf.substr(0, source.rtf.size() - 1);
	std::string uris;
	if (!source.url.empty()) {
		auto url = to_utf8(source.url);
		if (url.find_first_of("\r\n") != std::string::npos) throw std::invalid_argument("Invalid line break in drag URL");
		uris = url + "\r\n";
	}
	for (const auto &file : source.files) {
		const auto path = to_utf8(file);
		std::unique_ptr<gchar, decltype(&g_free)> uri(g_filename_to_uri(path.c_str(), nullptr, nullptr), g_free);
		if (!uri) throw std::invalid_argument("Drag file needs an absolute Linux path");
		uris += uri.get();
		uris += "\r\n";
	}
	if (!uris.empty()) formats["text/uri-list"] = std::move(uris);
	for (const auto &entry : source.custom) {
		// The legacy text format includes its terminator on the wire.
		// Other Wayland private formats carry the exact application bytes.
		const auto size = entry.second.size() - (custom_format::valid_name(entry.first) ? 0 : 1);
		formats[to_utf8(entry.first)] = entry.second.substr(0, size);
	}
	return formats;
}
}
#endif
