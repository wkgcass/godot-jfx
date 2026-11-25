#pragma once

#include "unix_drag_payload.h"

namespace godot_javafx::linux_dnd {
// Glass owns the straight BGRA bytes until Wayland copies them into its buffer.
inline bool drag_image(const unix_drag::SourceData::DragImage &image, int &hot_x, int &hot_y) {
	if (!image.present() || image.width > INT32_MAX / 4 / image.height ||
			image.bgra.size() != size_t(image.width) * image.height * 4) return false;
	hot_x = image.offset_x == INT32_MIN ? int(image.width / 2) : image.offset_x;
	hot_y = image.offset_y == INT32_MIN ? int(image.height / 2) : image.offset_y;
	return true;
}
}
