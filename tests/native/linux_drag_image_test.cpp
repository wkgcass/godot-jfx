#include "linux_drag_image.h"
#include "platform/linuxbsd/wayland/wayland_drag_image.h"
#include <cassert>

int main() {
	using namespace godot_javafx;
	unix_drag::SourceData::DragImage source;
	int x, y;
	assert(!linux_dnd::drag_image(source, x, y));
	source.width = 8;
	source.height = 6;
	assert(!linux_dnd::drag_image(source, x, y));
	source.bgra.resize(8 * 6 * 4);
	source.bgra[0] = 10;
	source.bgra[1] = 40;
	source.bgra[2] = 80;
	source.bgra[3] = 128;
	assert(linux_dnd::drag_image(source, x, y));
	assert(wayland_drag_argb(source.bgra.data()) == 0x80281405);
	assert(wayland_drag_argb(source.bgra.data() + 4) == 0);
	assert(x == 4 && y == 3);
	source.offset_x = 5;
	source.offset_y = 1;
	assert(linux_dnd::drag_image(source, x, y));
	assert(x == 5 && y == 1);
	std::puts("WAYLAND_DRAG_IMAGE_PASS");
}
