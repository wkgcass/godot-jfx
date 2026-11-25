#pragma once

#include "unix_drag_payload.h"
#include <map>
#include <memory>
#include <string_view>

namespace godot_javafx::linux_dnd {
using namespace godot_javafx::unix_drag;

using Formats = std::map<std::string, std::string>;
bool wayland_custom_name(std::u16string_view name);
bool supported_format(const std::string &type);
void decode_format(Payload &payload, const std::string &type, std::string bytes);
Formats encode_formats(const SourceData &source);

struct TargetHandler {
	int64_t id = 0;
	Upcall upcall;
	Payload enter_payload;
	uint64_t wayland_offer = 0;
	std::string wayland_mime;
	int x = 0, y = 0;
	uint32_t accepted = 0;

	uint32_t dispatch(int kind, uint32_t effects, uint32_t keys);
	void leave();
};
}
